(** ASGARD-5877: Tech-2608 (arXiv:2608.20628)
    Anti-Trace-Synthesis & Memory Chaffing Engine. *)

open Tech_2608_types

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

(* ── Address and Value Computation ────────────────────────────────────────── *)
let compute_chaff_address ~pool_base ~pool_size ~guest_reg ~salt : int64 =
  if pool_size <= 0 || (pool_size mod 64 <> 0) then
    invalid_arg "compute_chaff_address: pool_size must be a positive multiple of 64";
  let mask = Int64.of_int (pool_size - 8) in
  let raw_offset = Int64.logand (Int64.logxor guest_reg salt) mask in
  let aligned_offset = Int64.logand raw_offset (Int64.lognot 7L) in
  Int64.add pool_base aligned_offset

let compute_chaff_value ~guest_reg_a ~guest_reg_b ~rolling_key ~salt : int64 =
  let term_a = Int64.mul guest_reg_a 0x9E3779B97F4A7C15L in
  let term_b = Int64.mul guest_reg_b 0xBF58476D1CE4E5B9L in
  let k_mix = Int64.logxor rolling_key salt in
  Int64.logxor (Int64.add term_a term_b) k_mix

(* ── Chaff Events Synthesis ───────────────────────────────────────────────── *)
let synthesize_chaff_events
    ~(config : chaff_config)
    ~pool_base
    ~guest_regs
    ~rolling_key
    ~count : memory_event list =
  let prng = make_prng config.seed in
  let num_regs = Array.length guest_regs in
  let events = ref [] in

  for t = 0 to count - 1 do
    let r_idx_a = if num_regs > 0 then Int64.to_int (Int64.logand (next_u64 prng) 0x7FFFFFFFL) mod num_regs else 0 in
    let r_idx_b = if num_regs > 0 then (r_idx_a + 1) mod num_regs else 0 in
    let reg_a = if num_regs > 0 then guest_regs.(r_idx_a) else 0L in
    let reg_b = if num_regs > 0 then guest_regs.(r_idx_b) else 0L in

    let salt = next_u64 prng in
    let addr =
      match config.strategy with
      | UniformRandom ->
          let offset = Int64.logand salt (Int64.of_int (config.pool_size - 8)) in
          Int64.add pool_base (Int64.logand offset (Int64.lognot 7L))
      | RegisterEntangled | OpaqueGuarded | RollingKeyDependent ->
          compute_chaff_address ~pool_base ~pool_size:config.pool_size ~guest_reg:reg_a ~salt
    in

    let value =
      match config.strategy with
      | UniformRandom -> next_u64 prng
      | RegisterEntangled | OpaqueGuarded ->
          compute_chaff_value ~guest_reg_a:reg_a ~guest_reg_b:reg_b ~rolling_key ~salt
      | RollingKeyDependent ->
          Int64.logxor rolling_key (Int64.mul salt 0x9E3779B97F4A7C15L)
    in

    let op = if (t land 1) = 0 then MemWrite else MemRead in
    let ev = {
      timestamp = t;
      access_type = op;
      addr;
      size_bytes = 8;
      value;
      is_chaff = true;
    } in
    events := ev :: !events
  done;
  List.rev !events

(* ── Interleave Chaff with Genuine Trace ───────────────────────────────────── *)
let inject_chaff_into_trace
    ~(config : chaff_config)
    ~pool_base
    ~real_trace
    ~guest_regs
    ~rolling_key : memory_event list =
  let prng = make_prng config.seed in
  let num_regs = Array.length guest_regs in
  let result = ref [] in
  let ts = ref 0 in

  let generate_one_chaff is_write =
    let r_idx_a = if num_regs > 0 then Int64.to_int (Int64.logand (next_u64 prng) 0x7FFFFFFFL) mod num_regs else 0 in
    let r_idx_b = if num_regs > 0 then (r_idx_a + 1) mod num_regs else 0 in
    let reg_a = if num_regs > 0 then guest_regs.(r_idx_a) else 0L in
    let reg_b = if num_regs > 0 then guest_regs.(r_idx_b) else 0L in
    let salt = next_u64 prng in
    let addr = compute_chaff_address ~pool_base ~pool_size:config.pool_size ~guest_reg:reg_a ~salt in
    let value = compute_chaff_value ~guest_reg_a:reg_a ~guest_reg_b:reg_b ~rolling_key ~salt in
    let op = if is_write then MemWrite else MemRead in
    incr ts;
    {
      timestamp = !ts;
      access_type = op;
      addr;
      size_bytes = 8;
      value;
      is_chaff = true;
    }
  in

  List.iter (fun real_ev ->
    (* Chaff ops before real event *)
    let chaff_count = int_of_float (Float.round config.chaff_ratio) in
    for _ = 1 to chaff_count do
      result := generate_one_chaff true :: !result
    done;

    incr ts;
    result := { real_ev with timestamp = !ts } :: !result;

    (* Occasional chaff read after *)
    if Int64.logand (next_u64 prng) 1L = 1L then
      result := generate_one_chaff false :: !result
  ) real_trace;

  List.rev !result

(* ── Metrics Evaluation ───────────────────────────────────────────────────── *)
let evaluate_trace_metrics (trace : memory_event list) : (tech_2608_metrics, tech_2608_error) result =
  match trace with
  | [] -> Error EmptyMemoryTrace
  | _ ->
      let total_count = List.length trace in
      let chaff_count = List.fold_left (fun acc ev -> if ev.is_chaff then acc + 1 else acc) 0 trace in
      let chaff_density = (float_of_int chaff_count) /. (float_of_int total_count) in

      (* Address entropy across 4KB page buckets *)
      let page_counts = Hashtbl.create 64 in
      List.iter (fun ev ->
        let page = Int64.shift_right_logical ev.addr 12 in
        let curr = try Hashtbl.find page_counts page with Not_found -> 0 in
        Hashtbl.replace page_counts page (curr + 1)
      ) trace;

      let ent = ref 0.0 in
      let total_f = float_of_int total_count in
      Hashtbl.iter (fun _ count ->
        let p = (float_of_int count) /. total_f in
        ent := !ent -. (p *. (log p /. log 2.0))
      ) page_counts;
      let address_entropy = !ent in

      (* Entanglement score: fraction of chaff events with non-zero entropy value *)
      let entangled_chaff = List.fold_left (fun acc ev ->
        if ev.is_chaff && ev.value <> 0L then acc + 1 else acc
      ) 0 trace in
      let reg_score =
        if chaff_count > 0 then
          (float_of_int entangled_chaff) /. (float_of_int chaff_count)
        else 0.0
      in

      Ok {
        chaff_density;
        address_entropy;
        register_entanglement_score = reg_score;
      }

open Cpp_codegen.Cpp_ast
open Cpp_codegen.Cpp_dsl
open Cpp_codegen.Cpp_printer

let emit_chaff_store_method () : struct_member =
  member_method ~attrs:[AlwaysInline; NoExcept] Void "emit_chaff_store"
    [(UInt64, "reg_a"); (UInt64, "reg_b"); (UInt64, "k_dyn"); (UInt64, "salt")]
    [
      decl_var ~is_const:true SizeT "slot" ~init:(cast SizeT (var "reg_a" ^~ var "salt") &~ var "MASK_WORDS");
      const_u64 "val" (((var "reg_a" *~ u64 0x9E3779B97F4A7C15L) +~ (var "reg_b" *~ u64 0xBF58476D1CE4E5B9L)) ^~ (var "k_dyn" +~ var "salt"));
      idx (var "storage") (var "slot") := var "val";
    ]

let emit_chaff_load_method () : struct_member =
  member_method ~attrs:[AlwaysInline; NoExcept] ~is_const:true UInt64 "emit_chaff_load"
    [(UInt64, "reg_src"); (UInt64, "salt")]
    [
      decl_var ~is_const:true SizeT "slot" ~init:(cast SizeT (var "reg_src" ^~ var "salt") &~ var "MASK_WORDS");
      ret (idx (var "storage") (var "slot"));
    ]

let emit_chaff_memory_pool_def () : top_decl =
  template_struct_def ~align_as:64 ~template_params:["size_t PoolSize = 4096"] "ChaffMemoryPool" [
    member_static_assert ((var "PoolSize" &~ (var "PoolSize" -~ i32 1)) ==~ i32 0) "PoolSize must be power-of-two";
    member_static_assert (var "PoolSize" >=~ i32 64) "PoolSize must be at least 64 bytes";
    MemberRaw "alignas(64) volatile uint64_t storage[PoolSize / sizeof(uint64_t)]{0};";
    member_static_constexpr SizeT "MASK_WORDS" ((var "PoolSize" /~ sizeof_expr (var "uint64_t")) -~ i32 1);
    emit_chaff_store_method ();
    emit_chaff_load_method ();
  ]

(* ── Standalone C++20 Header Emitter ──────────────────────────────────────── *)
let emit_tech_2608_cpp_header () : string =
  let decls = [
    comment_top "============================================================================";
    comment_top "ASGARD-5877: Tech-2608 (arXiv:2608.20628)";
    comment_top "Anti-Trace-Synthesis & Memory Chaffing Runtime";
    comment_top "Thwarts BinMirror/LLM behavioral specification synthesis via:";
    comment_top "  1. Shadow Memory Chaff Pool with volatile decoys";
    comment_top "  2. Register-entangled memory reads and writes";
    comment_top "  3. Opaque-guarded side-effects indistinguishable from guest memory";
    comment_top "============================================================================";
    IncludeSys "cstdint";
    IncludeSys "cstddef";
    IncludeSys "array";
    namespace_def "asgard::tech_2608" [
      emit_chaff_memory_pool_def ();
    ];
  ] in
  "#pragma once\n" ^ render_top_decls decls

