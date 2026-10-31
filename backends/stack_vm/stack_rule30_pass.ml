(** Phase 6e (Pass 24): Wolfram Rule 30 Non-Linear Keystream & Cellular Automaton Diffusion
    ────────────────────────────────────────────────────────────────────────────────────────
    Defeats automated SMT bit-vector decision procedures (QF_BV), Gaussian elimination
    over GF(2), and symbolic execution engines (angr, Triton, Miasm) by continuously evolving
    the VM keystream state through Wolfram's elementary 1D cellular automaton Rule 30
    (OEIS A269160, A030101).

    Rule 30 bit-parallel update on 64-bit registers:
      R_30(x) = rotl64(x, 1) ^ (x | rotr64(x, 1))

    Interleaved with operations, the pass injects Rule 30 invariant zero-knots:
      (R_30(v) ^ rotl(v, 1)) ^ (v | rotr(v, 1)) == 0L  (mod 2^64)

    Because Rule 30 non-linearly couples bitwise OR and XOR across adjacent bit positions,
    SAT/SMT bit-vector solvers cannot apply linear affine Gaussian reduction, forcing
    exponential clause count explosion during bounded model checking.

    Soundness Invariants:
    1. Exact Value Preservation: (R_30(v) ^ rotl(v, 1)) ^ (v | rotr(v, 1)) == 0L across all 2^64 values.
    2. Stack Delta Invariant: Net stack delta across the cluster is 0 (v + 0L = v).
    3. Flag Safety: Applied strictly when condition codes are not live (not flags_live) and
       excluding guest base registers (SP=4, FP=5).
*)

open Stack_ir
open Random_visa_constants.Magic_numbers

type rule30_config = {
  enabled : bool;
  rate : int;
  seed : int64;
}

let default_rule30_config seed = {
  enabled = true;
  rate = 30;
  seed;
}

type rng_state = { mutable state : int64 }

let make_rng seed = { state = seed }

let splitmix64 s =
  let open Int64 in
  let s = add s golden_ratio_64 in
  let z = s in
  let z = mul (logxor z (shift_right_logical z 30)) splitmix64_gamma in
  let z = mul (logxor z (shift_right_logical z 27)) splitmix64_mix in
  (s, logxor z (shift_right_logical z 31))

let next_int64 rng =
  let s, z = splitmix64 rng.state in
  rng.state <- s;
  z

let next_int rng n =
  if n <= 1 then 0
  else
    let z = next_int64 rng in
    Int64.to_int (Int64.logand z 0x7FFFFFFFL) mod n

(** Bitwise OR primitive: consumes [B, A], pushes [A | B]. Net stack delta = -1. *)
let emit_or () =
  [
    Nor;
    PushImm 0L;
    Nor;
  ]

(** Bitwise XOR primitive: consumes [B, A], pushes [A ^ B]. Net stack delta = -1. *)
let emit_xor () =
  [
    Dup2;                              (* [B, A, B, A] *)
    Nand; Dup; Nand;                   (* [A & B, B, A] *)
    Swap; Rot;                         (* [A, B, A & B] *)
    Nor; Dup; Nor;                     (* [A | B, A & B] *)
    Swap;
    Sub;                               (* [(A | B) - (A & B) = A ^ B] *)
  ]

(** Bitwise ROTL1 primitive: consumes [x], pushes [rotl(x, 1)]. Net stack delta = 0. *)
let emit_rotl1 () =
  [
    Dup;
    PushImm 1L;
    Shl;
    Swap;
    PushImm 63L;
    Shr;
  ] @ emit_or ()

(** Bitwise ROTR1 primitive: consumes [x], pushes [rotr(x, 1)]. Net stack delta = 0. *)
let emit_rotr1 () =
  [
    Dup;
    PushImm 1L;
    Shr;
    Swap;
    PushImm 63L;
    Shl;
  ] @ emit_or ()

(** Computes Wolfram Rule 30 step: consumes [x], pushes [R30(x)].
    R30(x) = rotl64(x, 1) ^ (x | rotr64(x, 1)).
    Net stack delta = 0. *)
let emit_rule30_step () =
  [
    Dup;                               (* [x, x] *)
  ] @ emit_rotl1 () @                  (* [L = rotl(x, 1), x] *)
  [
    Swap;                              (* [x, L] *)
    Dup;                               (* [x, x, L] *)
  ] @ emit_rotr1 () @                  (* [R = rotr(x, 1), x, L] *)
  emit_or () @                         (* [M = x | R, L] *)
  emit_xor ()                          (* [L ^ M = R30(x)] *)

(** Emits Wolfram Rule 30 invariant zero-knot:
    (R30(v) ^ rotl(v, 1)) ^ (v | rotr(v, 1)) == 0L.
    Pushes 0L onto stack. Net stack delta = +1. *)
let emit_rule30_zero_knot ~rule30_slot ~s_val =
  [
    PushImm s_val;
    PushReg rule30_slot;
  ] @ emit_xor () @                    (* [v = s ^ K] *)
  [
    Dup;                               (* [v, v] *)
  ] @ emit_rule30_step () @            (* [R = R30(v), v] *)
  [
    Swap;                              (* [v, R] *)
    Dup;                               (* [v, v, R] *)
  ] @ emit_rotl1 () @                  (* [L = rotl(v, 1), v, R] *)
  [
    Rot;                               (* [R, L, v] *)
  ] @ emit_xor () @                    (* [R ^ L, v] *)
  [
    Swap;                              (* [v, R ^ L] *)
    Dup;                               (* [v, v, R ^ L] *)
  ] @ emit_rotr1 () @                  (* [R_rot = rotr(v, 1), v, R ^ L] *)
  emit_or () @                         (* [M = v | R_rot, R ^ L] *)
  emit_xor ()                          (* [(R ^ L) ^ M == 0L] *)

(** Emits a Rule 30 keystream advance step on rule30_slot:
    K_{t+1} = R30(K_t) ^ salt. Net stack delta = 0. *)
let emit_advance_rule30 ~rule30_slot ~salt =
  [ PushReg rule30_slot ] @
  emit_rule30_step () @
  [ PushImm salt ] @
  emit_xor () @
  [ PopReg rule30_slot ]

let apply_block (cfg : rule30_config) ~rule30_slot (b : block) : block =
  if not cfg.enabled || cfg.rate <= 0 then b
  else
    let rng =
      make_rng
        (Int64.logxor cfg.seed
           (Int64.logxor rule30_salt
              (Int64.of_int (b.id * 0x2691 + 0x5877))))
    in
    let live = Stack_flag_liveness.analyze_list b.ops in
    let new_ops = ref [] in
    let budget = ref 2 in

    List.iteri (fun idx op ->
      let flags_live = if idx + 1 < Array.length live then live.(idx + 1) else false in
      match op with
      | PushReg s
        when (not flags_live)
             && s < 32
             && s <> 4
             && s <> 5
             && !budget > 0
             && next_int rng 100 < cfg.rate ->
          decr budget;
          let s_val = Int64.logor (next_int64 rng) 1L in
          let salt = next_int64 rng in
          let knot = emit_rule30_zero_knot ~rule30_slot ~s_val in
          let adv = emit_advance_rule30 ~rule30_slot ~salt in
          let cluster = [ PushReg s ] @ knot @ [ Add ] @ adv in
          new_ops := List.rev cluster @ !new_ops
      | _ ->
          new_ops := op :: !new_ops
    ) b.ops;
    { b with ops = List.rev !new_ops }

let apply_program (cfg : rule30_config) (ctx : Context_allocator.t) (prog : program) : program =
  if not cfg.enabled || cfg.rate <= 0 then prog
  else
    let rule30_slot = Context_allocator.alloc_scratch ctx in
    let sorted =
      Hashtbl.fold (fun id b acc -> (id, b) :: acc) prog.blocks []
      |> List.sort (fun (a, _) (b, _) -> compare a b)
      |> Array.of_list
    in
    let n = Array.length sorted in
    let out = Array.make n (0, { (snd sorted.(0)) with ops = [] }) in
    let pool = Random_visa_ports.Domain_pool.global_pool () in
    Random_visa_ports.Domain_pool.parallel_for ~min_n:4 pool ~n (fun i ->
      let (id, b) = sorted.(i) in
      let b' = apply_block cfg ~rule30_slot b in
      let b'' =
        if id = prog.entry_id then
          (* Initialize Rule 30 keystream register at program entry *)
          let init_ops = [ PushImm rule30_init_key; PopReg rule30_slot ] in
          { b' with ops = init_ops @ b'.ops }
        else b'
      in
      out.(i) <- (id, b'')
    );
    let new_blocks = Hashtbl.create n in
    Array.iter (fun (id, b) -> Hashtbl.replace new_blocks id b) out;
    let context_slots = max prog.context_slots (Context_allocator.total_slots ctx) in
    { prog with blocks = new_blocks; context_slots }

let rule30_stats prog_before prog_after =
  let count_ops prog =
    Hashtbl.fold (fun _ b acc -> acc + List.length b.ops) prog.blocks 0
  in
  let before = count_ops prog_before in
  let after = count_ops prog_after in
  let diff = after - before in
  Printf.sprintf "Wolfram Rule 30 Keystream: %d ops -> %d ops (+%d cellular automaton clusters, +%.1f%%)"
    before after diff
    (if before = 0 then 0.0 else float_of_int diff /. float_of_int before *. 100.0)
