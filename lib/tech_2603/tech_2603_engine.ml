(** ASGARD-5877: Tech-2603 (arXiv:2603.18355)
    Anti-VPC-Tracking & Non-Linear Dispatch Engine. *)

open Tech_2603_types

let is_power_of_two n =
  n > 0 && (n land (n - 1)) = 0

let next_power_of_two n =
  if n <= 1 then 1
  else
    let rec loop v =
      if v >= n then v
      else loop (v lsl 1)
    in
    loop 1

let log2_int n =
  let rec loop v count =
    if v <= 1 then count
    else loop (v lsr 1) (count + 1)
  in
  loop n 0

(* ── SplitMix64 PRNG ──────────────────────────────────────────────────────── *)
let splitmix64 s =
  let s = Int64.add s 0x9E3779B97F4A7C15L in
  let z = s in
  let z = Int64.logxor z (Int64.shift_right_logical z 30) in
  let z = Int64.mul z 0xBF58476D1CE4E5B9L in
  let z = Int64.logxor z (Int64.shift_right_logical z 27) in
  let z = Int64.mul z 0x94D049BB133111EBL in
  let z = Int64.logxor z (Int64.shift_right_logical z 31) in
  (s, z)

type prng = { mutable state : int64 }

let make_prng seed = { state = seed }

let next_u64 prng =
  let s, z = splitmix64 prng.state in
  prng.state <- s;
  z

let _next_int prng n =
  if n <= 0 then 0
  else
    let v = Int64.to_int (Int64.logand (next_u64 prng) 0x7FFFFFFFL) in
    v mod n

(* ── Modular Inverse Modulo 2^k (Newton-Raphson / Hensel Lifting) ─────────── *)
let compute_modular_inverse_64 (a : int64) (shift : int) : int64 =
  if Int64.logand a 1L = 0L then
    invalid_arg "compute_modular_inverse_64: multiplier must be odd (coprime to 2^k)";
  let mask =
    if shift >= 64 then -1L
    else Int64.sub (Int64.shift_left 1L shift) 1L
  in
  (* x_0 = 3*a ^ 2 modulo 8 is exact for mod 8 *)
  let x = ref (Int64.logxor (Int64.mul 3L a) 2L) in
  (* Newton-Raphson: x = x * (2 - a * x) mod 2^k *)
  for _ = 1 to 6 do
    let ax = Int64.mul a !x in
    let two_minus_ax = Int64.sub 2L ax in
    x := Int64.logand (Int64.mul !x two_minus_ax) mask
  done;
  Int64.logand !x mask

(* ── Bijective Affine Permutation Plan Generation ────────────────────────── *)
let generate_affine_plan ?(min_capacity = 16) ~seed ~real_count () : (vpc_scramble_plan, tech_2603_error) result =
  if real_count <= 0 then
    Error (InvalidPermutation "real_count must be positive")
  else
    let capacity = next_power_of_two (max min_capacity real_count) in
    let shift = log2_int capacity in
    let mask64 = Int64.of_int (capacity - 1) in
    let prng = make_prng seed in

    (* Generate non-trivial odd multiplier a such that gcd(a, capacity) = 1 *)
    let rec find_a attempts =
      if attempts > 100 then
        (* Fallback safe prime multiplier *)
        0x5877CAFE1337BEE1L
      else
        let cand = Int64.logor (next_u64 prng) 1L in
        let cand_mod = Int64.logand cand mask64 in
        (* Reject identity (cand_mod = 1) and trivial inverse (cand_mod = capacity - 1) *)
        if cand_mod <> 1L && cand_mod <> mask64 && cand_mod <> 0L then cand
        else find_a (attempts + 1)
    in
    let a = find_a 0 in
    let a_inv = compute_modular_inverse_64 a shift in
    let b = Int64.logand (next_u64 prng) mask64 in

    let affine_gen = {
      a = Int64.logand a mask64;
      a_inv;
      b;
      modulus = capacity;
      shift;
    } in

    let logical_to_phys = Array.make capacity 0 in
    let phys_to_logical = Array.make capacity 0 in
    let visited = Array.make capacity false in

    for i = 0 to capacity - 1 do
      let i64 = Int64.of_int i in
      let p64 = Int64.logand (Int64.add (Int64.mul affine_gen.a i64) affine_gen.b) mask64 in
      let p = Int64.to_int p64 in
      if visited.(p) then
        failwith "Internal error: affine mapping collided despite coprime condition";
      visited.(p) <- true;
      logical_to_phys.(i) <- p;
      phys_to_logical.(p) <- i
    done;

    (* Build successor table: for physical slot p, find logical index i = phys_to_logical[p].
       If i + 1 < real_count, successor is logical_to_phys[i + 1].
       If i + 1 >= real_count, this is the exit slot; set successor to -1. *)
    let successor_table = Array.make capacity (-1) in
    let padding_slots_rev = ref [] in

    for p = 0 to capacity - 1 do
      let i = phys_to_logical.(p) in
      if i < real_count then begin
        if i + 1 < real_count then
          successor_table.(p) <- logical_to_phys.(i + 1)
        else
          successor_table.(p) <- -1 (* Terminating block *)
      end else begin
        padding_slots_rev := p :: !padding_slots_rev;
        (* In padding slots, set dummy successor to preserve non-empty table *)
        successor_table.(p) <- logical_to_phys.(0)
      end
    done;

    Ok {
      logical_to_physical = logical_to_phys;
      physical_to_logical = phys_to_logical;
      successor_table;
      padding_slots = List.rev !padding_slots_rev;
      real_count;
      total_capacity = capacity;
      affine_gen;
    }

(* ── Decoy Word Synthesis (Entropy Whitening) ─────────────────────────────── *)
let synthesize_decoy_word ~seed ~slot : int64 =
  let slot_seed = Int64.logxor seed (Int64.of_int (slot * 0x5877 + 0x1337)) in
  let _, z1 = splitmix64 slot_seed in
  let _, z2 = splitmix64 z1 in
  (* Pack valid-looking fields:
     op: valid decoy ALU/NOP opcodes (e.g., 0x00..0x3F)
     dst: reg 0..31
     src: reg 0..31
     imm: realistic immediate *)
  let decoy_op = Int64.logand z1 0x3FL in
  let decoy_dst = Int64.shift_left (Int64.logand (Int64.shift_right_logical z1 8) 0x1FL) 8 in
  let decoy_src = Int64.shift_left (Int64.logand (Int64.shift_right_logical z1 16) 0x1FL) 13 in
  let decoy_imm = Int64.shift_left (Int64.logand z2 0x3FFFFFFFFFFL) 18 in
  Int64.logor decoy_op (Int64.logor decoy_dst (Int64.logor decoy_src decoy_imm))

(* ── Bytecode Scrambling ─────────────────────────────────────────────────── *)
let scramble_bytecode ~seed ~bytecode ~plan : int64 array =
  let capacity = plan.total_capacity in
  let result = Array.make capacity 0L in
  let n = Array.length bytecode in
  if n <> plan.real_count then
    invalid_arg "scramble_bytecode: bytecode length does not match plan.real_count";

  (* 1. Place genuine instructions in their permuted physical slots *)
  for i = 0 to n - 1 do
    let p = plan.logical_to_physical.(i) in
    result.(p) <- bytecode.(i)
  done;

  (* 2. Populate unused padding slots with entropy-whitened decoys *)
  List.iter (fun p ->
    result.(p) <- synthesize_decoy_word ~seed ~slot:p
  ) plan.padding_slots;

  result

(* ── Split-VPC Dual Variable Implementation ───────────────────────────────── *)
let split_mask = 0x7FFFFFFFL

let encode_split_vpc ~seed ~physical_slot : split_vpc =
  let slot64 = Int64.of_int physical_slot in
  let _, key = splitmix64 (Int64.logxor seed (Int64.mul slot64 0x9E3779B97F4A7C15L)) in
  let key_low = Int64.to_int (Int64.logand key split_mask) in
  let masked = Int64.of_int (physical_slot lxor key_low) in
  {
    key;
    masked;
    epoch = 1l;
  }

let resolve_split_vpc (v : split_vpc) : int =
  let key_low = Int64.to_int (Int64.logand v.key split_mask) in
  let masked_int = Int64.to_int v.masked in
  masked_int lxor key_low

let advance_split_vpc (v : split_vpc) ~plan ~dynamic_key : split_vpc =
  let curr_p = resolve_split_vpc v in
  let next_p =
    if curr_p >= 0 && curr_p < plan.total_capacity then
      let succ = plan.successor_table.(curr_p) in
      if succ = -1 then curr_p else succ
    else
      0
  in
  let next_epoch = Int32.add v.epoch 1l in
  let _, new_key = splitmix64 (Int64.logxor v.key (Int64.logxor dynamic_key (Int64.of_int32 next_epoch))) in
  let key_low = Int64.to_int (Int64.logand new_key split_mask) in
  let masked = Int64.of_int (next_p lxor key_low) in
  {
    key = new_key;
    masked;
    epoch = next_epoch;
  }

(* ── Anti-PUSHAN Trace Resilience Metrics ─────────────────────────────────── *)
let evaluate_trace_metrics (trace : int array) : tech_2603_metrics =
  let n = Array.length trace in
  if n <= 1 then
    { monotonicity_score = 0.0; entropy_variance = 0.0; average_jump_distance = 0.0 }
  else begin
    let step_count = n - 1 in
    let monotonic_transitions = ref 0 in
    let total_jump = ref 0 in

    for t = 0 to step_count - 1 do
      let delta = abs (trace.(t + 1) - trace.(t)) in
      total_jump := !total_jump + delta;
      if delta <= 1 then
        incr monotonic_transitions
    done;

    let monotonicity_score = (float_of_int !monotonic_transitions) /. (float_of_int step_count) in
    let average_jump_distance = (float_of_int !total_jump) /. (float_of_int step_count) in

    (* Calculate Shannon byte entropy over 16-slot sliding windows *)
    let window_size = min 16 n in
    let num_windows = max 1 (n - window_size + 1) in
    let entropies = Array.init num_windows (fun w ->
      let counts = Array.make 256 0 in
      for i = 0 to window_size - 1 do
        let byte_val = trace.(w + i) land 0xFF in
        counts.(byte_val) <- counts.(byte_val) + 1
      done;
      let ent = ref 0.0 in
      let total_f = float_of_int window_size in
      for b = 0 to 255 do
        if counts.(b) > 0 then
          let p = (float_of_int counts.(b)) /. total_f in
          ent := !ent -. (p *. (log p /. log 2.0))
      done;
      !ent
    ) in

    let mean_ent = (Array.fold_left (+.) 0.0 entropies) /. (float_of_int num_windows) in
    let sq_diff_sum = Array.fold_left (fun acc e -> acc +. ((e -. mean_ent) ** 2.0)) 0.0 entropies in
    let entropy_variance = sq_diff_sum /. (float_of_int num_windows) in

    {
      monotonicity_score;
      entropy_variance;
      average_jump_distance;
    }
  end

open Cpp_codegen.Cpp_ast
open Cpp_codegen.Cpp_dsl
open Cpp_codegen.Cpp_printer

let emit_split_vpc_def () : top_decl =
  StructDef {
    align_as = Some 16;
    name = "SplitVPC";
    members = [
      member_field UInt64 "key" ~init:(u64 0L);
      member_field UInt64 "masked" ~init:(u64 0L);
      member_field UInt32 "epoch" ~init:(u32 0l);
      MemberStaticConstexpr { ty = UInt64; name = "MASK_31"; init = u64 0x7FFFFFFFL };
      member_method ~attrs:[AlwaysInline; NoExcept] ~is_const:true SizeT "resolve" [] [
        const_u64 "key_low" (var "key" &~ var "MASK_31");
        ret (cast SizeT (var "masked" ^~ var "key_low"));
      ];
      member_method ~attrs:[AlwaysInline; NoExcept] Void "advance" [(SizeT, "next_slot"); (UInt64, "dynamic_key")] [
        var "epoch" += i32 1;
        comment "SplitMix64 evolution of the key state";
        let_u64 "s" (var "key" ^~ var "dynamic_key" ^~ (cast UInt64 (var "epoch") *~ u64 0x9E3779B97F4A7C15L));
        var "s" += u64 0x9E3779B97F4A7C15L;
        let_u64 "z" (var "s");
        var "z" := (var "z" ^~ (var "z" >>~ i32 30)) *~ u64 0xBF58476D1CE4E5B9L;
        var "z" := (var "z" ^~ (var "z" >>~ i32 27)) *~ u64 0x94D049BB133111EBL;
        var "key" := var "z" ^~ (var "z" >>~ i32 31);
        const_u64 "key_low" (var "key" &~ var "MASK_31");
        var "masked" := cast UInt64 (var "next_slot") ^~ var "key_low";
      ];
    ];
  }

let emit_nonlinear_vpc_dispatcher_def () : top_decl =
  template_struct_def ~template_params:["size_t Capacity"] "NonLinearVPCDispatcher" [
    member_static_assert ((var "Capacity" &~ (var "Capacity" -~ i32 1)) ==~ i32 0) "Capacity must be power-of-two";
    member_static_constexpr SizeT "MASK" (var "Capacity" -~ i32 1);
    member_field UInt64 "a_mul" ~init:(i32 1);
    member_field UInt64 "a_inv" ~init:(i32 1);
    member_field UInt64 "b_add" ~init:(i32 0);
    member_field (ConstPtr Int32) "successor_lut" ~init:(var "nullptr");
    member_method ~attrs:[Nodiscard; ConstexprFn; NoExcept] ~is_const:true SizeT "logical_to_physical"
      [(SizeT, "logical_idx")] [
      ret (((var "logical_idx" *~ var "a_mul") +~ var "b_add") &~ var "MASK");
    ];
    member_method ~attrs:[Nodiscard; ConstexprFn; NoExcept] ~is_const:true SizeT "physical_to_logical"
      [(SizeT, "physical_idx")] [
      ret (((var "physical_idx" -~ var "b_add") *~ var "a_inv") &~ var "MASK");
    ];
    member_method ~attrs:[Nodiscard; InlineFn; NoExcept] ~is_const:true SizeT "next_physical"
      [(SizeT, "current_physical")] [
      if_then (ne (var "successor_lut") (var "nullptr")) [
        decl_var Int32 "succ" ~init:(Index (var "successor_lut", var "current_physical" &~ var "MASK"));
        ret (ternary (var "succ" >=~ i32 0) (cast SizeT (var "succ")) (var "current_physical"));
      ];
      comment "Direct affine stepping: i -> i + 1 in logical space";
      decl_var SizeT "logical" ~init:(call "physical_to_logical" [var "current_physical"]);
      ret (call "logical_to_physical" [var "logical" +~ i32 1]);
    ];
  ]

(* ── Standalone C++20 Header Emitter ──────────────────────────────────────── *)
let emit_tech_2603_cpp_header () : string =
  let b = Buffer.create 4096 in
  Buffer.add_string b {|#pragma once
// ============================================================================
// ASGARD-5877: Tech-2603 (arXiv:2603.18355)
// Anti-VPC-Tracking & Non-Linear Dispatch Runtime
// Thwarts PUSHAN/VM-Doctor heuristic VPC identification via:
//   1. Non-linear affine bijective VPC hopping: next_vpc = (a * vpc + b) & mask
//   2. Dual-variable Split-VPC: physical_slot = masked ^ (key & 0x7FFFFFFF)
//   3. Decoy padding with entropy whitening
// ============================================================================

#include <cstdint>
#include <cstddef>
#include <bit>

namespace asgard::tech_2603 {
|};
  Buffer.add_string b (render_top_decl (emit_split_vpc_def ()));
  Buffer.add_string b "\n\n";
  Buffer.add_string b (render_top_decl (emit_nonlinear_vpc_dispatcher_def ()));
  Buffer.add_string b "\n\n} // namespace asgard::tech_2603\n";
  Buffer.contents b
