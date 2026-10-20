(** ASGARD-5877: Tech-2603 (arXiv:2603.18355)
    Anti-VPC-Tracking & Non-Linear Dispatch Test Suite.
    Verifies:
      1. Bijective affine permutation over Z_{2^k}.
      2. Modular inverse correctness: (a * a_inv) mod 2^k = 1.
      3. Successor table sequence roundtrip.
      4. Split-VPC dual variable encoding and dynamic advance.
      5. Bytecode scrambling with entropy-whitened decoy synthesis.
      6. Anti-PUSHAN metrics: monotonicity drops from 1.0 to < 0.05.
      7. C++20 runtime integration and execution via clang++. *)

open Alcotest
open Tech_2603
open Tech_2603_types
open Tech_2603_engine

let test_modular_inverse () =
  let test_cases = [
    (3L, 4, 16);
    (5L, 6, 64);
    (0x5877CAFE1337BEE1L, 64, 0);
    (0x9E3779B97F4A7C15L, 64, 0);
    (11L, 8, 256);
  ] in
  List.iter (fun (a, shift, modulus) ->
    let inv = compute_modular_inverse_64 a shift in
    let prod = Int64.mul a inv in
    if modulus > 0 then begin
      let mask = Int64.of_int (modulus - 1) in
      let rem = Int64.logand prod mask in
      check int64 "modular inverse mod 2^k is 1" 1L rem
    end else begin
      (* mod 2^64 *)
      check int64 "modular inverse mod 2^64 is 1" 1L prod
    end
  ) test_cases

let test_affine_bijection () =
  let seed = 0x13375877CAFEBABEL in
  let real_count = 37 in
  match generate_affine_plan ~seed ~real_count () with
  | Error err -> fail (error_to_string err)
  | Ok plan ->
      let capacity = plan.total_capacity in
      check bool "capacity is power of two" true (is_power_of_two capacity);
      check bool "capacity >= real_count" true (capacity >= real_count);

      (* Verify bijection: every slot 0..capacity-1 must be hit exactly once *)
      let hits = Array.make capacity 0 in
      for i = 0 to capacity - 1 do
        let p = plan.logical_to_physical.(i) in
        hits.(p) <- hits.(p) + 1;
        (* Verify inverse *)
        let orig_i = plan.physical_to_logical.(p) in
        check int "roundtrip inverse" i orig_i
      done;
      Array.iteri (fun p count ->
        check int (Printf.sprintf "slot %d hit exactly once" p) 1 count
      ) hits

let test_successor_table_traversal () =
  let seed = 0xDEADBEEF01234567L in
  let real_count = 25 in
  match generate_affine_plan ~seed ~real_count () with
  | Error err -> fail (error_to_string err)
  | Ok plan ->
      (* Start at logical instruction 0 (physical slot = logical_to_physical.(0)) *)
      let visited_logical = ref [] in
      let curr_phys = ref plan.logical_to_physical.(0) in
      let steps = ref 0 in

      while !curr_phys >= 0 && !steps < real_count do
        let log_idx = plan.physical_to_logical.(!curr_phys) in
        visited_logical := log_idx :: !visited_logical;
        curr_phys := plan.successor_table.(!curr_phys);
        incr steps
      done;

      let seq = List.rev !visited_logical in
      check int "traversed exact real_count instructions" real_count (List.length seq);
      List.iteri (fun expected_i actual_i ->
        check int "in-order logical traversal" expected_i actual_i
      ) seq;
      (* Final successor must be -1 (exit) *)
      check int "final successor is -1" (-1) !curr_phys

let test_split_vpc_encoding_and_advance () =
  let seed = 0xCAFEBABE11223344L in
  let real_count = 20 in
  match generate_affine_plan ~seed ~real_count () with
  | Error err -> fail (error_to_string err)
  | Ok plan ->
      let p0 = plan.logical_to_physical.(0) in
      let split0 = encode_split_vpc ~seed ~physical_slot:p0 in
      let resolved0 = resolve_split_vpc split0 in
      check int "split_vpc initial resolution" p0 resolved0;

      (* Step through using advance_split_vpc *)
      let curr_split = ref split0 in
      for step = 0 to real_count - 2 do
        let dyn_key = Int64.of_int (step * 0x5877) in
        curr_split := advance_split_vpc !curr_split ~plan ~dynamic_key:dyn_key;
        let expected_logical = step + 1 in
        let expected_phys = plan.logical_to_physical.(expected_logical) in
        let resolved = resolve_split_vpc !curr_split in
        check int (Printf.sprintf "resolved step %d" expected_logical) expected_phys resolved
      done

let test_bytecode_scrambling_and_whitening () =
  let seed = 0x4242424299999999L in
  let real_count = 10 in
  let bytecode = Array.init real_count (fun i ->
    Int64.add 0x1000000000000000L (Int64.of_int (i * 0x100))
  ) in
  match generate_affine_plan ~min_capacity:32 ~seed ~real_count () with
  | Error err -> fail (error_to_string err)
  | Ok plan ->
      let scrambled = scramble_bytecode ~seed ~bytecode ~plan in
      check int "scrambled array length matches capacity" plan.total_capacity (Array.length scrambled);

      (* Verify real instructions preserved *)
      for i = 0 to real_count - 1 do
        let p = plan.logical_to_physical.(i) in
        check int64 "real bytecode word preserved at physical slot" bytecode.(i) scrambled.(p)
      done;

      (* Verify padding slots are not all zero (entropy whitened) *)
      List.iter (fun p ->
        check bool "padding slot is non-zero decoy" true (scrambled.(p) <> 0L)
      ) plan.padding_slots

let test_anti_pushan_monotonicity_drop () =
  let seed = 0x9876543210ABCDEFL in
  let count = 64 in
  (* 1. Linear sequential baseline (how normal VM bytecode progresses: 0, 1, 2, ... 63) *)
  let linear_trace = Array.init count (fun i -> i) in
  let linear_metrics = evaluate_trace_metrics linear_trace in
  check bool "linear baseline monotonicity is 1.0" true (linear_metrics.monotonicity_score > 0.99);

  (* 2. Tech-2603 Non-linear Scrambled trace *)
  match generate_affine_plan ~seed ~real_count:count () with
  | Error err -> fail (error_to_string err)
  | Ok plan ->
      let scrambled_trace = Array.init count (fun i -> plan.logical_to_physical.(i)) in
      let scrambled_metrics = evaluate_trace_metrics scrambled_trace in

      (* PUSHAN heuristic looks for monotonicity > 0.8 to identify VPC.
         Tech-2603 breaks this heuristic by driving monotonicity down below 0.05. *)
      check bool "scrambled monotonicity drops below 0.05" true
        (scrambled_metrics.monotonicity_score < 0.05);

      (* Jump distance must be high (non-local) *)
      check bool "average jump distance > 10.0 slots" true
        (scrambled_metrics.average_jump_distance > 10.0)

let test_cpp_runtime_execution () =
  let seed = 0x58771337BEEFCAFEL in
  let real_count = 16 in
  match generate_affine_plan ~seed ~real_count () with
  | Error err -> fail (error_to_string err)
  | Ok plan ->
      Test_helpers.with_temp_dir (fun tmp_dir ->
        let hdr_path = Filename.concat tmp_dir "asg_tech_2603.hpp" in
        Test_helpers.write_file_string hdr_path (emit_tech_2603_cpp_header ());

        let cpp_src = Printf.sprintf {|
#include <iostream>
#include <cassert>
#include "asg_tech_2603.hpp"

int main() {
    using namespace asgard::tech_2603;

    NonLinearVPCDispatcher<%d> disp;
    disp.a_mul = 0x%LXu;
    disp.a_inv = 0x%LXu;
    disp.b_add = 0x%LXu;

    // Test logical to physical and back
    for (size_t i = 0; i < %d; ++i) {
        size_t phys = disp.logical_to_physical(i);
        size_t orig = disp.physical_to_logical(phys);
        if (orig != i) return 1;
    }

    // Test SplitVPC
    SplitVPC vpc;
    const size_t initial_p = disp.logical_to_physical(0);
    vpc.advance(initial_p, 0x12345ULL);
    if (vpc.resolve() != initial_p) return 2;

    for (size_t step = 1; step < %d; ++step) {
        size_t next_p = disp.logical_to_physical(step);
        vpc.advance(next_p, 0x5877ULL * step);
        if (vpc.resolve() != next_p) return 3;
    }

    std::cout << "TECH-2603-OK" << std::endl;
    return 0;
}
|} plan.total_capacity plan.affine_gen.a plan.affine_gen.a_inv plan.affine_gen.b
   plan.total_capacity real_count in

        let runner_path = Filename.concat tmp_dir "test_runner.cpp" in
        Test_helpers.write_file_string runner_path cpp_src;

        let bin_path = Filename.concat tmp_dir "test_runner" in
        let cmd = Printf.sprintf "clang++ -std=c++20 -O0 -I%s %s -o %s" tmp_dir runner_path bin_path in
        let status = Sys.command cmd in
        check int "clang++ compilation status" 0 status;

        let run_status, out = Test_helpers.run_command_capture bin_path in
        check bool "binary exited normally" true (run_status = Unix.WEXITED 0);
        check bool "output contains TECH-2603-OK" true (Test_helpers.string_contains out "TECH-2603-OK")
      )

let tests = [
  ("Modular Inverse Modulo 2^k", `Quick, test_modular_inverse);
  ("Affine Coprime Bijection", `Quick, test_affine_bijection);
  ("Successor Table In-Order Traversal", `Quick, test_successor_table_traversal);
  ("Split-VPC Dual Variable Advance", `Quick, test_split_vpc_encoding_and_advance);
  ("Bytecode Scrambling and Whitening", `Quick, test_bytecode_scrambling_and_whitening);
  ("Anti-PUSHAN Monotonicity Reduction (<0.05)", `Quick, test_anti_pushan_monotonicity_drop);
  ("C++20 Runtime End-to-End Execution", `Quick, test_cpp_runtime_execution);
]
