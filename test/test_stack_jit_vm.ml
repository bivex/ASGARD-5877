open Alcotest
open Stack_vm
open Stack_ir
open Rd_jit_vm
open Vm_ir
open Random_visa_ports
open Protect_ports

let contains_sub (s : string) (sub : string) : bool =
  let n = String.length s and m = String.length sub in
  if m = 0 then true
  else
    let rec go i = i + m <= n && (String.sub s i m = sub || go (i + 1)) in
    go 0

let test_chunker_basic_arithmetic () =
  let ops = [ PushImm 100L; PushImm 200L; Add ] in
  let ref_stk = Stack_jit_chunker.reference_eval (Array.make 8 0L) ops in
  check (list int64) "Reference eval stack" [ 300L ] ref_stk;
  match Stack_jit_chunker.translate_trace () ops with
  | Error err -> fail ("Translation failed: " ^ err)
  | Ok tr ->
      check int "Final depth is 1" 1 tr.final_depth;
      let gprs = Array.make 16 0L in
      Stack_jit_chunker.simulate_chunks tr.chunks gprs;
      check int64 "Result in gprs.(0) is 300" 300L gprs.(0)

let test_chunker_multi_op () =
  let ops = [ PushImm 50L; PushImm 30L; Add; PushImm 15L; Sub ] in
  let ref_stk = Stack_jit_chunker.reference_eval (Array.make 8 0L) ops in
  check (list int64) "Reference eval stack" [ 65L ] ref_stk;
  match Stack_jit_chunker.translate_trace () ops with
  | Error err -> fail ("Translation failed: " ^ err)
  | Ok tr ->
      let gprs = Array.make 16 0L in
      Stack_jit_chunker.simulate_chunks tr.chunks gprs;
      check int64 "Result in gprs.(0) is 65" 65L gprs.(0)

let test_chunker_logic_nand_nor () =
  let ops = [ PushImm 0xF0F0L; PushImm 0x0FF0L; Nand ] in
  let ref_stk = Stack_jit_chunker.reference_eval (Array.make 8 0L) ops in
  check (list int64) "Reference eval stack Nand" [ Int64.lognot 0x00F0L ] ref_stk;
  match Stack_jit_chunker.translate_trace () ops with
  | Error err -> fail ("Translation failed: " ^ err)
  | Ok tr ->
      let gprs = Array.make 16 0L in
      Stack_jit_chunker.simulate_chunks tr.chunks gprs;
      check int64 "Nand simulation matches" (Int64.lognot 0x00F0L) gprs.(0);
      let ops_nor = [ PushImm 0xF0F0L; PushImm 0x0FF0L; Nor ] in
      let ref_nor = Stack_jit_chunker.reference_eval (Array.make 8 0L) ops_nor in
      check (list int64) "Reference eval stack Nor" [ Int64.lognot 0xFFF0L ] ref_nor;
      (match Stack_jit_chunker.translate_trace () ops_nor with
       | Error err -> fail ("Translation failed: " ^ err)
       | Ok tr_nor ->
           let gprs_nor = Array.make 16 0L in
           Stack_jit_chunker.simulate_chunks tr_nor.chunks gprs_nor;
           check int64 "Nor simulation matches" (Int64.lognot 0xFFF0L) gprs_nor.(0))

let test_chunker_dup_swap () =
  let ops = [ PushImm 10L; PushImm 20L; Swap; Dup; Add; Sub ] in
  let ref_stk = Stack_jit_chunker.reference_eval (Array.make 8 0L) ops in
  check (list int64) "Reference eval stack Dup/Swap" [ 0L ] ref_stk;
  match Stack_jit_chunker.translate_trace () ops with
  | Error err -> fail ("Translation failed: " ^ err)
  | Ok tr ->
      let gprs = Array.make 16 0L in
      Stack_jit_chunker.simulate_chunks tr.chunks gprs;
      check int64 "Dup/Swap simulation matches 0" 0L gprs.(0)

let test_chunker_context_registers () =
  let ops = [ PushImm 42L; PopReg 1; PushImm 58L; PushReg 1; Add ] in
  let regs = Array.make 8 0L in
  let ref_stk = Stack_jit_chunker.reference_eval regs ops in
  check (list int64) "Reference eval stack" [ 100L ] ref_stk;
  check int64 "Reg 1 stored 42" 42L regs.(1);
  match Stack_jit_chunker.translate_trace () ops with
  | Error err -> fail ("Translation failed: " ^ err)
  | Ok tr ->
      let gprs = Array.make 16 0L in
      Stack_jit_chunker.simulate_chunks tr.chunks gprs;
      check int64 "Result is 100" 100L gprs.(0);
      check int64 "Context slot 1 is 42" 42L gprs.(1)

let test_chunker_rejections () =
  check bool "Rejects JmpRel" true
    (Result.is_error (Stack_jit_chunker.translate_trace () [ JmpRel 1 ]));
  check bool "Rejects JccRel" true
    (Result.is_error (Stack_jit_chunker.translate_trace () [ JccRel (1, Flags.E) ]));
  check bool "Rejects too many distinct context slots" true
    (Result.is_error
       (Stack_jit_chunker.translate_trace ()
          [ PushReg 0; PushReg 1; PushReg 2; PushReg 3;
            PushReg 4; PushReg 5; PushReg 6; PushReg 7;
            PushReg 8; PushReg 9; PushReg 10; PushReg 11; PushReg 12 ]));
  check bool "Rejects stack window overflow" true
    (Result.is_error
       (Stack_jit_chunker.translate_trace ()
          [ PushImm 1L; PushImm 2L; PushImm 3L; PushImm 4L; PushImm 5L ]))

let test_chunker_symbols () =
  let ops = [ ResolveSym 0; PopReg 1; CallExtern 1 ] in
  match Stack_jit_chunker.translate_trace () ops with
  | Error err -> fail ("Symbols translation failed: " ^ err)
  | Ok tr ->
      let gprs = Array.make 16 0L in
      Stack_jit_chunker.simulate_chunks tr.chunks gprs;
      check int64 "Resolved symbol in slot 1" 0x1000L gprs.(1)
let test_chunker_div_rot_dup2 () =
  let ops_div = [ PushImm 100L; PushImm 4L; Div ] in
  let ref_div = Stack_jit_chunker.reference_eval (Array.make 8 0L) ops_div in
  check (list int64) "Reference div 100/4" [ 25L ] ref_div;
  (match Stack_jit_chunker.translate_trace () ops_div with
   | Error err -> fail ("Div translation failed: " ^ err)
   | Ok tr ->
       let gprs = Array.make 16 0L in
       Stack_jit_chunker.simulate_chunks tr.chunks gprs;
       check int64 "Result 100/4 is 25" 25L gprs.(0));
  let ops_rot = [ PushImm 0x1234567800000000L; PushImm 16L; Rot ] in
  let ref_rot = Stack_jit_chunker.reference_eval (Array.make 8 0L) ops_rot in
  (match Stack_jit_chunker.translate_trace () ops_rot with
   | Error err -> fail ("Rot translation failed: " ^ err)
   | Ok tr ->
       let gprs = Array.make 16 0L in
       Stack_jit_chunker.simulate_chunks tr.chunks gprs;
       check int64 "Rot matches reference" (List.hd ref_rot) gprs.(0));
  let ops_dup2 = [ PushImm 11L; PushImm 22L; Dup2; Add; PopReg 1; Add ] in
  let regs = Array.make 8 0L in
  let ref_dup2 = Stack_jit_chunker.reference_eval regs ops_dup2 in
  (match Stack_jit_chunker.translate_trace () ops_dup2 with
   | Error err -> fail ("Dup2 translation failed: " ^ err)
   | Ok tr ->
       let gprs = Array.make 16 0L in
       Stack_jit_chunker.simulate_chunks tr.chunks gprs;
       check int64 "Dup2 final top matches" (List.hd ref_dup2) gprs.(0);
       check int64 "Reg 1 is 11+22=33" 33L gprs.(1))

let test_chunker_cmp_cmov_branchless () =
  let ops = [ PushImm 10L; PushImm 20L; Cmp; PushImm 99L; Cmov (Flags.L, 1) ] in
  let regs = Array.make 8 0L in
  let _ = Stack_jit_chunker.reference_eval regs ops in
  check int64 "Reference cmov sets reg 1 to 99" 99L regs.(1);
  match Stack_jit_chunker.translate_trace () ops with
  | Error err -> fail ("Cmp/Cmov translation failed: " ^ err)
  | Ok tr ->
      let gprs = Array.make 16 0L in
      Stack_jit_chunker.simulate_chunks tr.chunks gprs;
      check int64 "Simulated cmov sets gprs.(1) to 99" 99L gprs.(1)

let test_stack_jit_div_rem_hardware_e2e () =
  let asm = {|
    mov x0, #100
    mov x1, #7
    udiv x2, x0, x1
    msub x0, x2, x1, x0
    lsl x0, x0, #3
    ret
  |} in
  match Arm64_lifter.lift_function asm with
  | Error err -> fail ("Failed to lift ARM64: " ^ err)
  | Ok func ->
      let ext_syms = Hashtbl.create 16 in
      let ctx = Context_allocator.create ~permute:false () in
      let _ctx, prog = Ir_to_stack.lower_func ~ctx ~ext_syms func in
      let entry = Hashtbl.find prog.blocks prog.entry_id in
      (match Stack_jit_chunker.translate_trace () entry.ops with
       | Error err -> fail ("Stack-JIT translation failed: " ^ err)
       | Ok tr ->
           let rng = Random.State.make [| 99991111 |] in
           let pkg =
             Rd_jit_emitter.compile_and_package_chunked
               ~rng
               ~enable_cff:false
               ~enable_mba:false
               ~chunks:tr.chunks
               func
           in
           Test_helpers.with_temp_dir (fun temp_dir ->
             let hdr_file = Filename.concat temp_dir "jit_vm_runtime.hpp" in
             Test_helpers.write_file_string hdr_file pkg.cpp_runtime_source;
             let runner_file = Filename.concat temp_dir "runner.cpp" in
             Test_helpers.write_file_string runner_file pkg.runner_source;
             let bin_file = Filename.concat temp_dir "stack_jit_div_app" in
             let cmd = Printf.sprintf "clang++ -std=c++20 -O0 -I%s %s -o %s" temp_dir runner_file bin_file in
             let status = Sys.command cmd in
             check int "Stack-JIT div/rem compilation status == 0" 0 status;
             let run_st, out_str = Test_helpers.run_command_capture bin_file in
             check bool "Stack-JIT div/rem run status == 0" true (run_st = Unix.WEXITED 0);
             (* (100 % 7) << 3 = 2 << 3 = 16 (0x10) *)
             let expected = "Result (REG 0): 16 (0x10)" in
             check bool "Exact result 16" true (contains_sub out_str expected)))

let test_stack_jit_e2e_compilation () =
  let asm = {|
    mov x0, #22647
    mov x1, #42
    mul x0, x0, x1
    add x0, x0, #4919
    ret
  |} in
  match Arm64_lifter.lift_function asm with
  | Error err -> fail ("Failed to lift ARM64: " ^ err)
  | Ok func ->
      let ext_syms = Hashtbl.create 16 in
      let ctx = Context_allocator.create ~permute:false () in
      let _ctx, prog = Ir_to_stack.lower_func ~ctx ~ext_syms func in
      let entry = Hashtbl.find prog.blocks prog.entry_id in
      (match Stack_jit_chunker.translate_trace () entry.ops with
       | Error err -> fail ("Stack-JIT translation failed: " ^ err)
       | Ok tr ->
           let rng = Random.State.make [| 58771337 |] in
           let pkg =
             Rd_jit_emitter.compile_and_package_chunked
               ~rng
               ~enable_cff:false
               ~enable_mba:false
               ~chunks:tr.chunks
               func
           in
           Test_helpers.with_temp_dir (fun temp_dir ->
             let hdr_file = Filename.concat temp_dir "jit_vm_runtime.hpp" in
             Test_helpers.write_file_string hdr_file pkg.cpp_runtime_source;
             let runner_file = Filename.concat temp_dir "runner.cpp" in
             Test_helpers.write_file_string runner_file pkg.runner_source;
             let bin_file = Filename.concat temp_dir "stack_jit_app" in
             let cmd = Printf.sprintf "clang++ -std=c++20 -O0 -I%s %s -o %s" temp_dir runner_file bin_file in
             let status = Sys.command cmd in
             check int "Stack-JIT compilation status == 0" 0 status;
             let run_st, out_str = Test_helpers.run_command_capture bin_file in
             check bool "Stack-JIT run status == 0" true (run_st = Unix.WEXITED 0);
             (* 22647 * 42 + 4919 = 956093 (0xe96bd) *)
             let expected = "Result (REG 0): 956093 (0xe96bd)" in
             check bool "Exact result 956093" true (contains_sub out_str expected)))
let test_stack_jit_c_macro_e2e () =
  let c_code = {|
#include <stdio.h>
#include "asgard_obf.h"

int compute(int a, int b) {
    ASGARD_BEGIN_VIRTUALIZE("compute");
    return a + b * 2;
}

int main() {
    printf("compute(10, 20) = %d\n", compute(10, 20));
    return 0;
}
|} in
  Test_helpers.with_temp_dir (fun temp_dir ->
    let c_file = Filename.concat temp_dir "test_macro.c" in
    let obf_hdr = Filename.concat temp_dir "asgard_obf.h" in
    let orig_hdr = "examples/asgard_obf.h" in
    Test_helpers.write_file_string c_file c_code;
    if Sys.file_exists orig_hdr then
      Test_helpers.write_file_string obf_hdr (Test_helpers.read_file_string orig_hdr);
    let out_dir = Filename.concat temp_dir "out" in
    let module Arm64_adapter = Protect_adapters.Arm64_lifter_adapter in
    let module C_macro_adapter = Protect_adapters.C_macro_obf_adapter in
    let module Trampoline_adapter = Protect_adapters.C_trampoline_adapter in
    let module Toolchain_adapter = Protect_adapters.Clang_toolchain_adapter in
    let module Vm_packager_adapters = Protect_adapters.Vm_packagers in
    let lifter = (module Arm64_adapter : Lifter) in
    let c_macro_obfuscator = (module C_macro_adapter : C_macro_obfuscator) in
    let trampoline_engine = (module Trampoline_adapter.C_trampoline_engine : Trampoline_engine) in
    let toolchain = (module Toolchain_adapter : Toolchain) in
    let vm_packager = (module Vm_packager_adapters.Stack_jit_packager : Vm_packager) in
    let raw_cfg = Protect_adapters.Config_adapter.unwrap Protect_adapters.Config_adapter.default in
    let cfg = Protect_adapters.Config_adapter.wrap raw_cfg in
    let rng = Random.State.make [| 5877 |] in
    match
      Random_visa_application.Protect_pipeline.run
        ~lifter
        ~c_macro_obfuscator
        ~vm_packager
        ~trampoline_engine
        ~toolchain
        ~rng
        ~config:cfg
        ~input_file:c_file
        ~out_dir
        ~compile:true
        ()
    with
    | Error err -> fail ("Pipeline failed: " ^ err)
    | Ok _ ->
        let app_bin = Filename.concat out_dir "protected_app" in
        check bool "protected_app exists" true (Sys.file_exists app_bin);
        let run_st, out_str = Test_helpers.run_command_capture app_bin in
        check bool "Run status is 0" true (run_st = Unix.WEXITED 0);
        check bool "Output is compute(10, 20) = 50" true (contains_sub out_str "compute(10, 20) = 50"))
let test_stack_jit_loop_branch_e2e () =
  let c_code = {|
#include <stdio.h>
#include "asgard_obf.h"

int loop_accumulate(int n) {
    ASGARD_BEGIN_VIRTUALIZE("loop_accumulate");
    int acc = 0;
    for (int i = 1; i <= n; i++) {
        acc += i * 2;
    }
    return acc;
}

int main() {
    printf("loop_accumulate(5) = %d\n", loop_accumulate(5));
    return 0;
}
|} in
  Test_helpers.with_temp_dir (fun temp_dir ->
    let c_file = Filename.concat temp_dir "test_loop.c" in
    let obf_hdr = Filename.concat temp_dir "asgard_obf.h" in
    let orig_hdr = "examples/asgard_obf.h" in
    Test_helpers.write_file_string c_file c_code;
    if Sys.file_exists orig_hdr then
      Test_helpers.write_file_string obf_hdr (Test_helpers.read_file_string orig_hdr);
    let out_dir = Filename.concat temp_dir "out" in
    let module Arm64_adapter = Protect_adapters.Arm64_lifter_adapter in
    let module C_macro_adapter = Protect_adapters.C_macro_obf_adapter in
    let module Trampoline_adapter = Protect_adapters.C_trampoline_adapter in
    let module Toolchain_adapter = Protect_adapters.Clang_toolchain_adapter in
    let module Vm_packager_adapters = Protect_adapters.Vm_packagers in
    let lifter = (module Arm64_adapter : Lifter) in
    let c_macro_obfuscator = (module C_macro_adapter : C_macro_obfuscator) in
    let trampoline_engine = (module Trampoline_adapter.C_trampoline_engine : Trampoline_engine) in
    let toolchain = (module Toolchain_adapter : Toolchain) in
    let vm_packager = (module Vm_packager_adapters.Stack_jit_packager : Vm_packager) in
    let raw_cfg = Protect_adapters.Config_adapter.unwrap Protect_adapters.Config_adapter.default in
    let cfg = Protect_adapters.Config_adapter.wrap raw_cfg in
    let rng = Random.State.make [| 5877 |] in
    match
      Random_visa_application.Protect_pipeline.run
        ~lifter
        ~c_macro_obfuscator
        ~vm_packager
        ~trampoline_engine
        ~toolchain
        ~rng
        ~config:cfg
        ~input_file:c_file
        ~out_dir
        ~compile:true
        ()
    with
    | Error err -> fail ("Pipeline failed: " ^ err)
    | Ok _ ->
        let app_bin = Filename.concat out_dir "protected_app" in
        check bool "protected_app exists" true (Sys.file_exists app_bin);
        let run_st, out_str = Test_helpers.run_command_capture app_bin in
        check bool "Run status is 0" true (run_st = Unix.WEXITED 0);
        check bool "Output is loop_accumulate(5) = 30" true (contains_sub out_str "loop_accumulate(5) = 30"))

let test_chunker_bit_manip_ops () =
  (* OEIS-backed Group A: Bswap / Clz / Ctz / Rbit / Popcnt end-to-end
     through translate_trace + simulate_chunks, cross-checked against
     the reference Stack-IR evaluator. *)
  let run_one name ops expected =
    let ref_stk = Stack_jit_chunker.reference_eval (Array.make 8 0L) ops in
    check int64 (name ^ " reference") expected (List.hd ref_stk);
    match Stack_jit_chunker.translate_trace () ops with
    | Error err -> fail (name ^ " translation failed: " ^ err)
    | Ok tr ->
        let gprs = Array.make 16 0L in
        Stack_jit_chunker.simulate_chunks tr.chunks gprs;
        check int64 (name ^ " simulated") expected gprs.(0)
  in
  (* Bswap: byte reversal of 0x1234567890ABCDEF -> 0xEFCDAB9078563412 *)
  run_one "Bswap"
    [ PushImm 0x1234567890ABCDEFL; Bswap ]
    0xEFCDAB9078563412L;
  (* Bswap of 0 is 0 *)
  run_one "Bswap(0)" [ PushImm 0L; Bswap ] 0L;
  (* Clz: 0xFF has 56 leading zeros; 0 has 64 *)
  run_one "Clz(0xFF)" [ PushImm 0xFFL; Clz ] 56L;
  run_one "Clz(0)" [ PushImm 0L; Clz ] 64L;
  run_one "Clz(1)" [ PushImm 1L; Clz ] 63L;
  (* Ctz: 0x10 = 16 has 4 trailing zeros; 0 has 64 per spec *)
  run_one "Ctz(0x10)" [ PushImm 0x10L; Ctz ] 4L;
  run_one "Ctz(0)" [ PushImm 0L; Ctz ] 64L;
  run_one "Ctz(0x5877)" [ PushImm 0x5877L; Ctz ] 0L;
  (* Rbit: reversing bits of 1 gives 0x8000000000000000 *)
  run_one "Rbit(1)" [ PushImm 1L; Rbit ] 0x8000000000000000L;
  (* Rbit is an involution: Rbit(Rbit(x)) = x *)
  run_one "Rbit(Rbit(x))"
    [ PushImm 0x5877CAFE1337BEEFL; Rbit; Rbit ]
    0x5877CAFE1337BEEFL;
  (* Popcnt: 0xFFFF has 16 bits; 0 has 0 *)
  run_one "Popcnt(0xFFFF)" [ PushImm 0xFFFFL; Popcnt ] 16L;
  run_one "Popcnt(0)" [ PushImm 0L; Popcnt ] 0L;
  run_one "Popcnt(0xFFFFFFFFFFFFFFFF)"
    [ PushImm (-1L); Popcnt ] 64L;
  (* A001511 step: ctz(8) = 3 -> ruler level 4 *)
  run_one "Ctz(8) feeds A001511"
    [ PushImm 8L; Ctz ] 3L

let test_chunker_imm_peepholes () =
  (* Group B peepholes: [MOV_RI imm][CMP_RR] -> [CMP_RI] and
     Rot-by-immediate -> [ROR_RI]; correctness via reference parity,
     firing via direct inspection of the emitted chunk items. *)
  let module C = Stack_jit_chunker in
  let suffix op =
    String.sub op (String.length "asgard_rd_jit::JIT_OP_") (String.length op - String.length "asgard_rd_jit::JIT_OP_")
  in
  (* 1. Rot by immediate folds to ROR_RI and matches the reference. *)
  let ops_rot = [ PushImm 0x1234567800000001L; PushImm 12L; Rot ] in
  let ref_rot = List.hd (C.reference_eval (Array.make 8 0L) ops_rot) in
  (match C.translate_trace () ops_rot with
   | Error e -> fail ("Rot imm translation failed: " ^ e)
   | Ok tr ->
       let all_items = List.concat tr.chunks in
       check bool "Rot-by-imm folds to ROR_RI" true
         (List.exists (fun (op, _, _, _) -> suffix op = "ROR_RI") all_items);
       let gprs = Array.make 16 0L in
       C.simulate_chunks tr.chunks gprs;
       check int64 "ROR_RI simulation matches reference" ref_rot gprs.(0));
  (* 2. Cmp with immediate folds to CMP_RI (peephole fires). *)
  let ops_cmp = [ PushImm 42L; PushImm 7L; Cmp ] in
  (match C.translate_trace () ops_cmp with
   | Error e -> fail ("Cmp imm translation failed: " ^ e)
   | Ok tr ->
       let all_items = List.concat tr.chunks in
       check bool "Cmp-by-imm folds to CMP_RI" true
         (List.exists (fun (op, _, _, _) -> suffix op = "CMP_RI") all_items));
  (* 3. Cmp between two registers keeps CMP_RR (no fold). *)
  let ops_cmp_rr = [ PushImm 42L; Dup; Cmp ] in
  (match C.translate_trace () ops_cmp_rr with
   | Error e -> fail ("Cmp rr translation failed: " ^ e)
   | Ok tr ->
       let all_items = List.concat tr.chunks in
       check bool "Cmp reg-vs-reg keeps CMP_RR" true
         (List.exists (fun (op, _, _, _) -> suffix op = "CMP_RR") all_items));
  (* 4. CMP_RI flag path feeding Cmov: reference evaluator models the
     compare-vs-immediate flags; simulator covers the value path.
     Collatz guard shape: n <= 1 (unsigned BE) selects the fallback 99. *)
  let ops_cmov =
    [ PushImm 5L; PushImm 1L; Cmp; PushImm 99L; Cmov (Flags.BE, 1) ]
  in
  let regs4 = Array.make 8 0L in
  let _ = C.reference_eval regs4 ops_cmov in
  (match C.translate_trace () ops_cmov with
   | Error e -> fail ("Cmov-after-CMP_RI translation failed: " ^ e)
   | Ok tr ->
       let all_items = List.concat tr.chunks in
       check bool "Cmp-by-imm folds to CMP_RI before Cmov" true
         (List.exists (fun (op, _, _, _) -> suffix op = "CMP_RI") all_items);
       let gprs = Array.make 16 0L in
       C.simulate_chunks tr.chunks gprs;
       (* n = 5 > 1 so BE is not taken: reg 1 keeps the pushed 99 via Csel. *)
       check int64 "Cmov value path intact after CMP_RI fold" 99L gprs.(1))

let test_chunker_ruler_a001511 () =
  (* OEIS A001511: A001511(t) = 1 + ctz(t) = 1 + v2(2t) *)
  let module C = Stack_jit_chunker in
  (* Known values: A001511(1)=1, A001511(2)=2, A001511(3)=1, A001511(4)=3,
     A001511(5)=1, A001511(6)=2, A001511(7)=1, A001511(8)=4 *)
  let expected = [| 1; 2; 1; 3; 1; 2; 1; 4; 1; 2; 1; 3; 1; 2; 1; 5 |] in
  let computed = Array.init 16 (fun i -> C.ruler_a001511 (i + 1)) in
  check bool "A001511 first 16 terms" true (computed = expected);
  (* Level-k wipes happen at every t divisible by 2^(k-1) *)
  for k = 1 to 5 do
    for mult = 1 to 8 do
      let t = mult * (1 lsl (k - 1)) in
      check bool (Printf.sprintf "A001511(%d) >= %d" t k) true
        (C.ruler_a001511 t >= k)
    done
  done;
  (* invalidation_schedule for a small translation is computed correctly *)
  (match C.translate_trace () [ PushImm 1L; PushImm 2L; Add ] with
   | Error e -> fail ("Translate failed: " ^ e)
   | Ok tr ->
       let n = List.length tr.chunks in
       check bool "invalidation_schedule length = num_chunks" true
         (Array.length tr.invalidation_schedule = n);
       (* Every entry is a positive integer (level >= 1) *)
       check bool "all wipe levels >= 1" true
         (Array.for_all (fun v -> v >= 1) tr.invalidation_schedule);
       (* First chunk k=0 -> A001511(1)=1, second k=1 -> A001511(2)=2 (if exists) *)
       if n >= 1 then
         check int "schedule[0] = A001511(1) = 1" 1 tr.invalidation_schedule.(0);
       if n >= 2 then
         check int "schedule[1] = A001511(2) = 2" 2 tr.invalidation_schedule.(1))
let test_stack_jit_multi_function_parallel_e2e () =
  let c_code = {|
#include <stdio.h>
#include "asgard_obf.h"

int func_add(int a, int b) {
    ASGARD_BEGIN_VIRTUALIZE("func_add");
    return a + b;
}

int func_sub(int a, int b) {
    ASGARD_BEGIN_VIRTUALIZE("func_sub");
    return a - b;
}

int func_mul(int a, int b) {
    ASGARD_BEGIN_VIRTUALIZE("func_mul");
    return a * b;
}

int main() {
    printf("res: add=%d sub=%d mul=%d\n", func_add(10, 20), func_sub(50, 15), func_mul(6, 7));
    return 0;
}
|} in
  Test_helpers.with_temp_dir (fun temp_dir ->
    let c_file = Filename.concat temp_dir "test_multi.c" in
    let obf_hdr = Filename.concat temp_dir "asgard_obf.h" in
    let orig_hdr = "examples/asgard_obf.h" in
    Test_helpers.write_file_string c_file c_code;
    if Sys.file_exists orig_hdr then
      Test_helpers.write_file_string obf_hdr (Test_helpers.read_file_string orig_hdr);
    let out_dir = Filename.concat temp_dir "out" in
    let module Arm64_adapter = Protect_adapters.Arm64_lifter_adapter in
    let module C_macro_adapter = Protect_adapters.C_macro_obf_adapter in
    let module Trampoline_adapter = Protect_adapters.C_trampoline_adapter in
    let module Toolchain_adapter = Protect_adapters.Clang_toolchain_adapter in
    let module Vm_packager_adapters = Protect_adapters.Vm_packagers in
    let lifter = (module Arm64_adapter : Lifter) in
    let c_macro_obfuscator = (module C_macro_adapter : C_macro_obfuscator) in
    let trampoline_engine = (module Trampoline_adapter.C_trampoline_engine : Trampoline_engine) in
    let toolchain = (module Toolchain_adapter : Toolchain) in
    let vm_packager = (module Vm_packager_adapters.Stack_jit_packager : Vm_packager) in
    let raw_cfg = Protect_adapters.Config_adapter.unwrap Protect_adapters.Config_adapter.default in
    let cfg = Protect_adapters.Config_adapter.wrap raw_cfg in
    let rng = Random.State.make [| 5877 |] in
    match
      Random_visa_application.Protect_pipeline.run
        ~lifter
        ~c_macro_obfuscator
        ~vm_packager
        ~trampoline_engine
        ~toolchain
        ~rng
        ~config:cfg
        ~input_file:c_file
        ~out_dir
        ~compile:true
        ()
    with
    | Error err -> fail ("Pipeline failed: " ^ err)
    | Ok _ ->
        let app_bin = Filename.concat out_dir "protected_app" in
        check bool "protected_app exists" true (Sys.file_exists app_bin);
        let run_st, out_str = Test_helpers.run_command_capture app_bin in
        check bool "Run status is 0" true (run_st = Unix.WEXITED 0);
        check bool "Output is res: add=30 sub=35 mul=42" true
          (contains_sub out_str "res: add=30 sub=35 mul=42"))

let tests = [
  ("Stack-JIT Basic Arithmetic Simulation", `Quick, test_chunker_basic_arithmetic);
  ("Stack-JIT Multi-Op Simulation", `Quick, test_chunker_multi_op);
  ("Stack-JIT Nand/Nor Simulation", `Quick, test_chunker_logic_nand_nor);
  ("Stack-JIT Dup/Swap Simulation", `Quick, test_chunker_dup_swap);
  ("Stack-JIT Context Registers Simulation", `Quick, test_chunker_context_registers);
  ("Stack-JIT Rejections of Unsupported Ops", `Quick, test_chunker_rejections);
  ("Stack-JIT Div, Rot, Dup2 Simulation", `Quick, test_chunker_div_rot_dup2);
  ("Stack-JIT Cmp & Cmov Simulation", `Quick, test_chunker_cmp_cmov_branchless);
  ("Stack-JIT ResolveSym & CallExtern Simulation", `Quick, test_chunker_symbols);
  ("Stack-JIT Hardware E2E Execution", `Quick, test_stack_jit_e2e_compilation);
  ("Stack-JIT Hardware Div/Rem/Shift E2E", `Quick, test_stack_jit_div_rem_hardware_e2e);
  ("Stack-JIT C Macro Trampoline E2E", `Quick, test_stack_jit_c_macro_e2e);
  ("Stack-JIT Dynamic Loop & Branching E2E", `Quick, test_stack_jit_loop_branch_e2e);
  ("Stack-JIT A001511 Ruler & Invalidation Schedule", `Quick, test_chunker_ruler_a001511);
  ("Stack-JIT Bswap/Clz/Ctz/Rbit/Popcnt Simulation", `Quick, test_chunker_bit_manip_ops);
  ("Stack-JIT CMP_RI & ROR_RI Immediate Peepholes", `Quick, test_chunker_imm_peepholes);
  ("Stack-JIT Multi-Function Parallel E2E", `Quick, test_stack_jit_multi_function_parallel_e2e);
]
