open Alcotest
open Stack_vm
open Stack_ir
open Rd_jit_vm

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
  check bool "Rejects Div" true
    (Result.is_error (Stack_jit_chunker.translate_trace () [ PushImm 10L; PushImm 2L; Div ]));
  check bool "Rejects JmpRel" true
    (Result.is_error (Stack_jit_chunker.translate_trace () [ JmpRel 1 ]));
  check bool "Rejects too many distinct context slots" true
    (Result.is_error
       (Stack_jit_chunker.translate_trace ()
          [ PushReg 0; PushReg 1; PushReg 2; PushReg 3;
            PushReg 4; PushReg 5; PushReg 6; PushReg 7; PushReg 8 ]));
  check bool "Rejects stack window overflow" true
    (Result.is_error
       (Stack_jit_chunker.translate_trace ()
          [ PushImm 1L; PushImm 2L; PushImm 3L; PushImm 4L;
            PushImm 5L; PushImm 6L; PushImm 7L; PushImm 8L; PushImm 9L ]))

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

let tests = [
  ("Stack-JIT Basic Arithmetic Simulation", `Quick, test_chunker_basic_arithmetic);
  ("Stack-JIT Multi-Op Simulation", `Quick, test_chunker_multi_op);
  ("Stack-JIT Nand/Nor Simulation", `Quick, test_chunker_logic_nand_nor);
  ("Stack-JIT Dup/Swap Simulation", `Quick, test_chunker_dup_swap);
  ("Stack-JIT Context Registers Simulation", `Quick, test_chunker_context_registers);
  ("Stack-JIT Rejections of Unsupported Ops", `Quick, test_chunker_rejections);
  ("Stack-JIT Hardware E2E Execution", `Quick, test_stack_jit_e2e_compilation);
]
