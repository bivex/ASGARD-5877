open Vm_ir
open X86_lifter
open Vm_eval

let test_parser_memory_operands () =
  let p1 = Result.get_ok (X86_parser.parse_mem_operand "[rax]" Register.B64) in
  Alcotest.(check (option string)) "base rax" (Some "rax") (Option.map Register.to_string p1.base);
  Alcotest.(check bool) "no index" true (Option.is_none p1.index);
  Alcotest.(check int64) "disp 0" 0L p1.disp;

  let p2 = Result.get_ok (X86_parser.parse_mem_operand "[rdi + rsi*4 - 0x20]" Register.B32) in
  Alcotest.(check (option string)) "base rdi" (Some "rdi") (Option.map Register.to_string p2.base);
  (match p2.index with
  | Some (idx, scale) ->
      Alcotest.(check string) "index rsi" "rsi" (Register.to_string idx);
      Alcotest.(check int) "scale 4" 4 scale
  | None -> Alcotest.fail "expected index");
  Alcotest.(check int64) "disp -0x20" (-0x20L) p2.disp

let test_lift_and_eval_math () =
  let asm = {|
func_math:
    push rbp
    mov rbp, rsp
    mov rax, rdi
    add rax, rsi
    imul rax, 3
    pop rbp
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let state = make_state () in
      set_reg state Register.rdi 10L;
      set_reg state Register.rsi 4L;
      match run_func state func with
      | Error e -> Alcotest.fail e
      | Ok () ->
          (* (10 + 4) * 3 = 42 *)
          Alcotest.(check int64) "math (10+4)*3 = 42" 42L (get_reg state Register.rax)

let test_lift_and_eval_abs_branch () =
  let asm = {|
func_abs:
    mov rax, rdi
    cmp rax, 0
    jge .Ldone
    neg rax
.Ldone:
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      (* Case 1: negative input -99 *)
      let state1 = make_state () in
      set_reg state1 Register.rdi (-99L);
      (match run_func state1 func with
      | Error e -> Alcotest.fail e
      | Ok () ->
          Alcotest.(check int64) "abs(-99) = 99" 99L (get_reg state1 Register.rax));

      (* Case 2: positive input 123 *)
      let state2 = make_state () in
      set_reg state2 Register.rdi 123L;
      (match run_func state2 func with
      | Error e -> Alcotest.fail e
      | Ok () ->
          Alcotest.(check int64) "abs(123) = 123" 123L (get_reg state2 Register.rax))

let test_lift_and_eval_factorial_loop () =
  let asm = {|
factorial:
    mov rax, 1
.Lloop:
    cmp rdi, 1
    jle .Lexit
    imul rax, rdi
    dec rdi
    jmp .Lloop
.Lexit:
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let state = make_state () in
      set_reg state Register.rdi 6L; (* 6! = 720 *)
      match run_func state func with
      | Error e -> Alcotest.fail e
      | Ok () ->
          Alcotest.(check int64) "6! = 720" 720L (get_reg state Register.rax)

let test_lift_and_eval_mem_rmw () =
  let asm = {|
mem_test:
    mov qword ptr [rsp - 16], rdi
    add qword ptr [rsp - 16], 100
    mov rax, qword ptr [rsp - 16]
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let state = make_state () in
      set_reg state Register.rdi 50L;
      match run_func state func with
      | Error e -> Alcotest.fail e
      | Ok () ->
          (* 50 + 100 = 150 *)
          Alcotest.(check int64) "mem 50 + 100 = 150" 150L (get_reg state Register.rax)

let test_lift_and_eval_array_sum_sib () =
  let asm = {|
array_sum:
    xor rax, rax
    xor rcx, rcx
.Lloop:
    cmp rcx, rsi
    jge .Ldone
    add rax, qword ptr [rdi + rcx*8]
    inc rcx
    jmp .Lloop
.Ldone:
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let state = make_state () in
      let base_addr = 0x2000L in
      set_reg state Register.rdi base_addr;
      set_reg state Register.rsi 4L;

      (* Populate memory array: [10, 20, 30, 40] *)
      write_mem state 0x2000L Register.B64 10L;
      write_mem state 0x2008L Register.B64 20L;
      write_mem state 0x2010L Register.B64 30L;
      write_mem state 0x2018L Register.B64 40L;

      match run_func state func with
      | Error e -> Alcotest.fail e
      | Ok () ->
          (* 10 + 20 + 30 + 40 = 100 *)
          Alcotest.(check int64) "array sum = 100" 100L (get_reg state Register.rax)

let test_marker_region_extraction () =
  let asm_with_markers = {|
func_with_markers:
    mov rdx, 10
    ; --- START PROTECTED REGION ---
    .byte 0xEB, 0x0E, 'A','S','G','A','R','D','_','B','E','G','_','U','_','_'
    mov rax, rdi
    add rax, rsi
    imul rax, 2
    .byte 0xEB, 0x0E, 'A','S','G','A','R','D','_','E','N','D','_','_','_','_'
    ; --- END PROTECTED REGION ---
    ret
|} in
  let raw_lines = Result.get_ok (X86_parser.parse_lines asm_with_markers) in
  let regions = Lifter.extract_marked_regions raw_lines in
  Alcotest.(check int) "detected 1 marked region" 1 (List.length regions);
  let (mode, lines) = List.hd regions in
  Alcotest.(check string) "mode is ULTRA" "ULTRA(region)" (X86_parser.marker_mode_to_string mode);
  match Lifter.lift_lines lines with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let state = make_state () in
      set_reg state Register.rdi 15L;
      set_reg state Register.rsi 5L;
      match run_func state func with
      | Error e -> Alcotest.fail e
      | Ok () ->
          (* (15 + 5) * 2 = 40 *)
          Alcotest.(check int64) "virtualized slice result (15+5)*2 = 40" 40L (get_reg state Register.rax)

let tests = [
  Alcotest.test_case "parser_memory_operands" `Quick test_parser_memory_operands;
  Alcotest.test_case "lift_and_eval_math" `Quick test_lift_and_eval_math;
  Alcotest.test_case "lift_and_eval_abs_branch" `Quick test_lift_and_eval_abs_branch;
  Alcotest.test_case "lift_and_eval_factorial_loop" `Quick test_lift_and_eval_factorial_loop;
  Alcotest.test_case "lift_and_eval_mem_rmw" `Quick test_lift_and_eval_mem_rmw;
  Alcotest.test_case "lift_and_eval_array_sum_sib" `Quick test_lift_and_eval_array_sum_sib;
  Alcotest.test_case "marker_region_extraction" `Quick test_marker_region_extraction;
]

