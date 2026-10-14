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

(* ── Standalone C++20 Header Emitter ──────────────────────────────────────── *)
let emit_tech_2608_cpp_header () : string =
  let b = Buffer.create 4096 in
  Buffer.add_string b {|#pragma once
// ============================================================================
// ASGARD-5877: Tech-2608 (arXiv:2608.20628)
// Anti-Trace-Synthesis & Memory Chaffing Runtime
// Thwarts BinMirror/LLM behavioral specification synthesis via:
//   1. Shadow Memory Chaff Pool with volatile decoys
//   2. Register-entangled memory reads and writes
//   3. Opaque-guarded side-effects indistinguishable from guest memory
// ============================================================================

#include <cstdint>
#include <cstddef>
#include <array>

namespace asgard::tech_2608 {

template<size_t PoolSize = 4096>
struct alignas(64) ChaffMemoryPool {
    static_assert((PoolSize & (PoolSize - 1)) == 0, "PoolSize must be power-of-two");
    static_assert(PoolSize >= 64, "PoolSize must be at least 64 bytes");

    alignas(64) volatile uint64_t storage[PoolSize / sizeof(uint64_t)]{0};
    static constexpr size_t MASK_WORDS = (PoolSize / sizeof(uint64_t)) - 1;

    inline void emit_chaff_store(uint64_t reg_a, uint64_t reg_b, uint64_t k_dyn, uint64_t salt) noexcept {
        const size_t slot = (static_cast<size_t>(reg_a ^ salt)) & MASK_WORDS;
        const uint64_t val = (reg_a * 0x9E3779B97F4A7C15ULL) + (reg_b * 0xBF58476D1CE4E5B9ULL) ^ (k_dyn + salt);
        storage[slot] = val;
    }

    [[nodiscard]] inline uint64_t emit_chaff_load(uint64_t reg_src, uint64_t salt) const noexcept {
        const size_t slot = (static_cast<size_t>(reg_src ^ salt)) & MASK_WORDS;
        return storage[slot];
    }
};

} // namespace asgard::tech_2608
|};
  Buffer.contents b
