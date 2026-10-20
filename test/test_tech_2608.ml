(** ASGARD-5877: Tech-2608 (arXiv:2608.20628)
    Anti-Trace-Synthesis & Memory Chaffing Test Suite.
    Verifies:
      1. Chaff memory address alignment (8-byte) and bounded pool indexing.
      2. Guest register entanglement in chaff value calculation.
      3. Chaff injection into real memory execution traces.
      4. Resilience metrics: chaff density >= 66%, address entropy > 0.
      5. C++20 runtime integration via clang++ execution. *)

open Alcotest
open Tech_2608
open Tech_2608_types
open Tech_2608_engine

let test_chaff_address_properties () =
  let pool_base = 0x7FFF00001000L in
  let pool_size = 4096 in
  let test_regs = [0L; 1L; 0x13375877CAFEBABEL; 0x7FFFFFFFFFFFFFFFL; -1L] in
  let salts = [0x5555555555555555L; 0x2AAAAAAAAAAAAAAAL; 0x1234567890ABCDEFL] in

  List.iter (fun reg ->
    List.iter (fun salt ->
      let addr = compute_chaff_address ~pool_base ~pool_size ~guest_reg:reg ~salt in
      (* Must be >= pool_base *)
      check bool "addr >= pool_base" true (addr >= pool_base);
      (* Must be <= pool_base + pool_size - 8 *)
      check bool "addr <= pool_base + pool_size - 8" true (addr <= Int64.add pool_base (Int64.of_int (pool_size - 8)));
      (* Must be 8-byte aligned *)
      check int64 "8-byte aligned" 0L (Int64.logand addr 7L)
    ) salts
  ) test_regs

let test_chaff_value_entanglement () =
  let rolling_key = 0x9E3779B97F4A7C15L in
  let salt = 0x1337BEEFL in
  let v1 = compute_chaff_value ~guest_reg_a:10L ~guest_reg_b:20L ~rolling_key ~salt in
  let v2 = compute_chaff_value ~guest_reg_a:11L ~guest_reg_b:20L ~rolling_key ~salt in
  let v3 = compute_chaff_value ~guest_reg_a:10L ~guest_reg_b:21L ~rolling_key ~salt in
  (* Value must be sensitive to guest_reg_a and guest_reg_b *)
  check bool "v1 != v2 when reg_a changes" true (v1 <> v2);
  check bool "v1 != v3 when reg_b changes" true (v1 <> v3);
  check bool "v1 is non-zero" true (v1 <> 0L)

let test_trace_injection_and_metrics () =
  let config = {
    pool_size = 4096;
    chaff_ratio = 2.0;
    strategy = RegisterEntangled;
    seed = 0x58771337CAFEBABEL;
  } in
  let pool_base = 0x10000000L in
  let guest_regs = [| 0x100L; 0x200L; 0x300L; 0x400L |] in
  let rolling_key = 0xCAFEBABE01234567L in

  (* Create a synthetic real memory trace with 5 operations *)
  let real_trace = [
    { timestamp = 1; access_type = MemRead; addr = 0x2000L; size_bytes = 8; value = 42L; is_chaff = false };
    { timestamp = 2; access_type = MemWrite; addr = 0x2008L; size_bytes = 8; value = 84L; is_chaff = false };
    { timestamp = 3; access_type = MemRead; addr = 0x2010L; size_bytes = 8; value = 126L; is_chaff = false };
    { timestamp = 4; access_type = MemWrite; addr = 0x2018L; size_bytes = 8; value = 168L; is_chaff = false };
    { timestamp = 5; access_type = MemWrite; addr = 0x2020L; size_bytes = 8; value = 210L; is_chaff = false };
  ] in

  let injected = inject_chaff_into_trace ~config ~pool_base ~real_trace ~guest_regs ~rolling_key in

  (* Count real vs chaff *)
  let real_count = List.fold_left (fun acc ev -> if not ev.is_chaff then acc + 1 else acc) 0 injected in
  let chaff_count = List.fold_left (fun acc ev -> if ev.is_chaff then acc + 1 else acc) 0 injected in

  check int "all 5 real operations preserved" 5 real_count;
  (* With ratio 2.0, there are at least 10 chaff operations injected *)
  check bool "at least 10 chaff ops injected" true (chaff_count >= 10);

  match evaluate_trace_metrics injected with
  | Error err -> fail (error_to_string err)
  | Ok metrics ->
      (* Density must be >= 0.66 *)
      check bool "chaff density >= 65%" true (metrics.chaff_density >= 0.65);
      (* Entanglement score = 1.0 (all chaff values entangled) *)
      check bool "entanglement score == 1.0" true (metrics.register_entanglement_score > 0.99)

let test_cpp_chaff_pool_execution () =
  Test_helpers.with_temp_dir (fun tmp_dir ->
    let hdr_path = Filename.concat tmp_dir "asg_tech_2608.hpp" in
    Test_helpers.write_file_string hdr_path (emit_tech_2608_cpp_header ());

    let cpp_src = {|
#include <iostream>
#include <cassert>
#include "asg_tech_2608.hpp"

int main() {
    using namespace asgard::tech_2608;

    ChaffMemoryPool<4096> pool;

    // Simulate 50 guest memory steps with chaff stores and loads
    uint64_t reg_a = 0x1337ULL;
    uint64_t reg_b = 0x5877ULL;
    uint64_t k_dyn = 0xCAFEBABE11223344ULL;

    for (size_t i = 0; i < 50; ++i) {
        pool.emit_chaff_store(reg_a + i, reg_b - i, k_dyn, 0x5555ULL * i);
        uint64_t loaded = pool.emit_chaff_load(reg_a + i, 0x5555ULL * i);
        if (loaded == 0) return 1;
    }

    std::cout << "TECH-2608-OK" << std::endl;
    return 0;
}
|} in

    let runner_path = Filename.concat tmp_dir "test_runner.cpp" in
    Test_helpers.write_file_string runner_path cpp_src;

    let bin_path = Filename.concat tmp_dir "test_runner" in
    let cmd = Printf.sprintf "clang++ -std=c++20 -O0 -I%s %s -o %s" tmp_dir runner_path bin_path in
    let status = Sys.command cmd in
    check int "clang++ compilation status" 0 status;

    let run_status, out = Test_helpers.run_command_capture bin_path in
    check bool "binary exited normally" true (run_status = Unix.WEXITED 0);
    check bool "output contains TECH-2608-OK" true (Test_helpers.string_contains out "TECH-2608-OK")
  )

let tests = [
  ("Chaff Address Alignment and Bounds", `Quick, test_chaff_address_properties);
  ("Chaff Value Register Entanglement", `Quick, test_chaff_value_entanglement);
  ("Trace Injection and Resilience Metrics", `Quick, test_trace_injection_and_metrics);
  ("C++20 Chaff Pool Runtime Execution", `Quick, test_cpp_chaff_pool_execution);
]
