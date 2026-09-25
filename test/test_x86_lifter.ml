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

let test_lift_and_eval_div64_signed () =
  let asm = {|
div64_signed:
    mov rax, rdi
    cqo
    idiv rsi
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let state = make_state () in
      set_reg state Register.rdi (-47L);
      set_reg state Register.rsi 5L;
      match run_func state func with
      | Error e -> Alcotest.fail e
      | Ok () ->
          Alcotest.(check int64) "idiv -47/5 quotient = -9" (-9L) (get_reg state Register.rax);
          Alcotest.(check int64) "idiv -47/5 remainder = -2" (-2L) (get_reg state Register.rdx)

let test_lift_and_eval_div64_unsigned () =
  let asm = {|
div64_unsigned:
    mov rax, rdi
    xor rdx, rdx
    div rsi
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let state = make_state () in
      set_reg state Register.rdi (-1L); (* 0xFFFFFFFFFFFFFFFF as unsigned *)
      set_reg state Register.rsi 2L;
      match run_func state func with
      | Error e -> Alcotest.fail e
      | Ok () ->
          Alcotest.(check int64) "div max/2 quotient" 0x7FFFFFFFFFFFFFFFL (get_reg state Register.rax);
          Alcotest.(check int64) "div max/2 remainder = 1" 1L (get_reg state Register.rdx)

let test_lift_and_eval_div64_with_rdx () =
  let asm = {|
div64_rdx:
    mov rax, rdi
    mov rdx, 1
    div rsi
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let state = make_state () in
      set_reg state Register.rdi 0L;
      set_reg state Register.rsi 2L;
      match run_func state func with
      | Error e -> Alcotest.fail e
      | Ok () ->
          Alcotest.(check int64) "div (1:0)/2 quotient = 2^63" (Int64.min_int) (get_reg state Register.rax);
          Alcotest.(check int64) "div (1:0)/2 remainder = 0" 0L (get_reg state Register.rdx)

let test_lift_and_eval_idiv32_signed () =
  let asm = {|
div32_signed:
    mov eax, edi
    cdq
    idiv ecx
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let state = make_state () in
      set_reg state Register.rdi (-47L);
      set_reg state Register.rcx 5L;
      match run_func state func with
      | Error e -> Alcotest.fail e
      | Ok () ->
          (* eax = zext32(-9), edx = zext32(-2) *)
          Alcotest.(check int64) "idivl -47/5 eax" 4294967287L (get_reg state Register.rax);
          Alcotest.(check int64) "idivl -47/5 edx" 4294967294L (get_reg state Register.rdx)

let test_lift_and_eval_div32_unsigned () =
  let asm = {|
div32_unsigned:
    mov eax, edi
    xor edx, edx
    div ecx
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let state = make_state () in
      set_reg state Register.rdi 4294967295L;
      set_reg state Register.rcx 10L;
      match run_func state func with
      | Error e -> Alcotest.fail e
      | Ok () ->
          Alcotest.(check int64) "divl 0xFFFFFFFF/10 eax" 429496729L (get_reg state Register.rax);
          Alcotest.(check int64) "divl 0xFFFFFFFF/10 edx" 5L (get_reg state Register.rdx)

let test_lift_and_eval_cdqe_sext () =
  let asm = {|
cdqe_check:
    mov eax, edi
    cdqe
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let state = make_state () in
      set_reg state Register.rdi (-47L);
      match run_func state func with
      | Error e -> Alcotest.fail e
      | Ok () ->
          (* eax = 0xFFFFFFD1 before cdqe; afterwards rax = sext32 = -47 *)
          Alcotest.(check int64) "cdqe sign-extends eax into rax" (-47L) (get_reg state Register.rax)

let test_lift_and_eval_b32_write_zero_extends () =
  let asm = {|
zext_check:
    mov rax, rdi
    mov eax, esi
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let state = make_state () in
      set_reg state Register.rdi 0x123456789AL;
      set_reg state Register.rsi 66L;
      match run_func state func with
      | Error e -> Alcotest.fail e
      | Ok () ->
          (* writing esi/eax must zero the upper half of rax, not merge it *)
          Alcotest.(check int64) "mov eax zeroes upper 32" 66L (get_reg state Register.rax)

let test_lift_and_eval_movsx_mem () =
  let asm = {|
movsx_mem:
    mov byte ptr [rsp - 8], dil
    mov word ptr [rsp - 16], si
    mov dword ptr [rsp - 24], edx
    movsx rax, byte ptr [rsp - 8]
    movsx rcx, word ptr [rsp - 16]
    add rax, rcx
    movsxd rcx, dword ptr [rsp - 24]
    add rax, rcx
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let state = make_state () in
      set_reg state Register.rdi 0xFBL; (* -5 *)
      set_reg state Register.rsi 0xFED4L; (* -300 *)
      set_reg state Register.rdx 0xFFFE7960L; (* -100000 *)
      match run_func state func with
      | Error e -> Alcotest.fail e
      | Ok () ->
          (* (-5) + (-300) + (-100000) = -100305 *)
          Alcotest.(check int64) "movsx/movsxd mem sum = -100305" (-100305L) (get_reg state Register.rax)

let test_lift_and_eval_movsx_reg () =
  let asm = {|
movsx_reg:
    mov cl, dil
    movsx eax, cl
    mov dx, si
    movsx r8, dx
    mov r10d, r9d
    movsxd r11, r10d
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let state = make_state () in
      set_reg state Register.rdi 0xFBL; (* -5 in cl *)
      set_reg state Register.rsi 0xFED4L; (* -300 in dx *)
      set_reg state Register.r9 0xFFFE7960L; (* -100000 in r10d *)
      match run_func state func with
      | Error e -> Alcotest.fail e
      | Ok () ->
          (* eax is 32-bit: sign-extended byte to 32 bits = 0x00000000FFFFFFFB *)
          Alcotest.(check int64) "movsx eax, cl" 0xFFFFFFFBL (get_reg state Register.rax);
          (* r8 is 64-bit: sign-extended word to 64 bits = -300 *)
          Alcotest.(check int64) "movsx r8, dx" (-300L) (get_reg state Register.r8);
          (* r11 is 64-bit: sign-extended dword to 64 bits = -100000 *)
          Alcotest.(check int64) "movsxd r11, r10d" (-100000L) (get_reg state Register.r11)

let test_lift_and_eval_movzx_reg () =
  let asm = {|
movzx_reg:
    mov rcx, rdi
    movzx eax, cl
    movzx rdx, cx
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let state = make_state () in
      set_reg state Register.rdi 0x12345678_9ABCDEFBL;
      match run_func state func with
      | Error e -> Alcotest.fail e
      | Ok () ->
          Alcotest.(check int64) "movzx eax, cl zeroes upper bits" 0xFBL (get_reg state Register.rax);
          Alcotest.(check int64) "movzx rdx, cx zeroes upper bits" 0xDEFBL (get_reg state Register.rdx)

let test_lift_one_operand_mul () =
  let asm = {|
mul8:
    mov al, 0x10
    mov cl, 0x20
    mul cl
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let state = make_state () in
      set_reg state Register.rdi 0L;
      set_reg state Register.rsi 0L;
      (match run_func state func with
      | Error e -> Alcotest.fail e
      | Ok () ->
          Alcotest.(check int64) "one operand B8 mul" 0x200L (get_reg state Register.rax))

let test_lift_one_operand_mul_signed () =
  let asm = {|
mul8_signed:
    mov al, 0xF6
    mov bl, 0x03
    imul bl
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let state = make_state () in
      (match run_func state func with
      | Error e -> Alcotest.fail e
      | Ok () -> Alcotest.(check int64) "one operand signed B8 imul" 0xFFE2L (get_reg state Register.rax))

let test_lift_one_operand_mul64 () =
  let asm = {|
mul64:
    mov rax, 0x123456789ABCDEF0
    mov rcx, 0xFEDCBA9876543210
    mul rcx
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let state = make_state () in
      (match run_func state func with
      | Error e -> Alcotest.fail e
      | Ok () ->
          Alcotest.(check int64) "one operand B64 mul low" 0x236D88FE5618CF00L (get_reg state Register.rax);
          Alcotest.(check int64) "one operand B64 mul high" 0x121FA00AD77D7422L (get_reg state Register.rdx))

let test_lift_one_operand_imul64 () =
  let asm = {|
imul64:
    mov rax, 0x100000000
    mov rcx, -2
    imul rcx
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let state = make_state () in
      (match run_func state func with
      | Error e -> Alcotest.fail e
      | Ok () ->
          Alcotest.(check int64) "one operand B64 imul low (pos * neg)" 0xFFFFFFFE00000000L (get_reg state Register.rax);
          Alcotest.(check int64) "one operand B64 imul high (pos * neg)" (-1L) (get_reg state Register.rdx));
  let asm_neg_neg = {|
imul64_neg_neg:
    mov rax, -2
    mov rcx, -3
    imul rcx
    ret
|} in
  match Lifter.lift_function asm_neg_neg with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let state = make_state () in
      (match run_func state func with
      | Error e -> Alcotest.fail e
      | Ok () ->
          Alcotest.(check int64) "one operand B64 imul low (neg * neg)" 6L (get_reg state Register.rax);
          Alcotest.(check int64) "one operand B64 imul high (neg * neg)" 0L (get_reg state Register.rdx))

let test_lift_one_operand_mul32 () =
  let asm = {|
mul32:
    mov rax, 0x1111111100000000
    mov rdx, 0x2222222200000000
    mov eax, 0x80000000
    mov ecx, 3
    mul ecx
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let state = make_state () in
      (match run_func state func with
      | Error e -> Alcotest.fail e
      | Ok () ->
          (* 0x80000000 * 3 = 0x180000000. EAX = 0x80000000, EDX = 1, upper 32 bits zeroed *)
          Alcotest.(check int64) "one operand B32 mul low eax" 0x80000000L (get_reg state Register.rax);
          Alcotest.(check int64) "one operand B32 mul high edx" 1L (get_reg state Register.rdx))

let test_lift_one_operand_imul32 () =
  let asm = {|
imul32:
    mov rax, 0x1111111100000000
    mov rdx, 0x2222222200000000
    mov eax, 0x80000000
    mov ecx, 3
    imul ecx
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let state = make_state () in
      (match run_func state func with
      | Error e -> Alcotest.fail e
      | Ok () ->
          (* -2147483648 * 3 = -6442450944 = 0xFFFFFFFE80000000. EAX = 0x80000000, EDX = 0xFFFFFFFE *)
          Alcotest.(check int64) "one operand B32 imul low eax" 0x80000000L (get_reg state Register.rax);
          Alcotest.(check int64) "one operand B32 imul high edx" 0xFFFFFFFEL (get_reg state Register.rdx))

let test_lift_one_operand_mul16 () =
  let asm = {|
mul16:
    mov rax, 0x1111222233330000
    mov rdx, 0x5555666677770000
    mov ax, 0x8000
    mov cx, 3
    mul cx
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let state = make_state () in
      (match run_func state func with
      | Error e -> Alcotest.fail e
      | Ok () ->
          (* 0x8000 * 3 = 0x18000. AX = 0x8000, DX = 1. Upper 48 bits preserved *)
          Alcotest.(check int64) "one operand B16 mul low ax" 0x1111222233338000L (get_reg state Register.rax);
          Alcotest.(check int64) "one operand B16 mul high dx" 0x5555666677770001L (get_reg state Register.rdx))

let test_lift_one_operand_imul16 () =
  let asm = {|
imul16:
    mov rax, 0x1111222233330000
    mov rdx, 0x5555666677770000
    mov ax, 0x8000
    mov cx, 3
    imul cx
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let state = make_state () in
      (match run_func state func with
      | Error e -> Alcotest.fail e
      | Ok () ->
          (* -32768 * 3 = -98304 = 0xFFFE8000. AX = 0x8000, DX = 0xFFFE. Upper 48 bits preserved *)
          Alcotest.(check int64) "one operand B16 imul low ax" 0x1111222233338000L (get_reg state Register.rax);
          Alcotest.(check int64) "one operand B16 imul high dx" 0x555566667777FFFEL (get_reg state Register.rdx))

let test_lift_one_operand_mul_mem () =
  let asm = {|
mul_mem64:
    mov rax, 0x100000000
    mul qword ptr [rdi]
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let state = make_state () in
      let mem_addr = 0x3000L in
      set_reg state Register.rdi mem_addr;
      write_mem state mem_addr Register.B64 0x20L;
      (match run_func state func with
      | Error e -> Alcotest.fail e
      | Ok () ->
          (* 0x100000000 * 0x20 = 0x2000000000 *)
          Alcotest.(check int64) "one operand B64 mul mem low" 0x2000000000L (get_reg state Register.rax);
          Alcotest.(check int64) "one operand B64 mul mem high" 0L (get_reg state Register.rdx));
  let asm_imul = {|
imul_mem64:
    mov rax, 0x100000000
    imul qword ptr [rdi]
    ret
|} in
  match Lifter.lift_function asm_imul with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let state = make_state () in
      let mem_addr = 0x3000L in
      set_reg state Register.rdi mem_addr;
      write_mem state mem_addr Register.B64 (-2L);
      (match run_func state func with
      | Error e -> Alcotest.fail e
      | Ok () ->
          Alcotest.(check int64) "one operand B64 imul mem low" 0xFFFFFFFE00000000L (get_reg state Register.rax);
          Alcotest.(check int64) "one operand B64 imul mem high" (-1L) (get_reg state Register.rdx))

let test_lift_narrow_division () =
  let asm = {|
div8_unsigned:
    mov ax, 0x1234
    mov cl, 0x10
    div cl
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let state = make_state () in
      (match run_func state func with
      | Error e -> Alcotest.fail e
      | Ok () ->
          Alcotest.(check int64) "one operand B8 div" 0x0423L (get_reg state Register.rax))

let test_lift_narrow_division_signed () =
  let asm = {|
div8_signed:
    mov ax, 0xFFF0
    mov cl, 0x02
    idiv cl
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let state = make_state () in
      (match run_func state func with
      | Error e -> Alcotest.fail e
      | Ok () -> Alcotest.(check int64) "one operand signed B8 idiv" 0x00F8L (get_reg state Register.rax))

let test_lift_narrow_division16 () =
  let asm = {|
div16_unsigned:
    xor edx, edx
    mov ax, 0x1234
    mov cx, 0x10
    div cx
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let state = make_state () in
      (match run_func state func with
      | Error e -> Alcotest.fail e
      | Ok () ->
          Alcotest.(check int64) "one operand B16 div quotient" 0x0123L (get_reg state Register.rax);
          Alcotest.(check int64) "one operand B16 div remainder" 4L (get_reg state Register.rdx))

let test_division_by_zero_fault () =
  let asm = {|
division_by_zero:
    xor edx, edx
    mov rax, 1
    xor rcx, rcx
    div rcx
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let state = make_state () in
      (match run_func state func with
      | Error e -> Alcotest.(check string) "division by zero faults" "VM divide by zero" e
      | Ok () -> Alcotest.fail "division by zero did not fault")

let test_b8_b16_merge_semantics () =
  let asm = {|
merge_subregs:
    mov rax, 0x1122334455667788
    mov al, 0x99
    mov ax, 0xAABB
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let state = make_state () in
      (match run_func state func with
      | Error e -> Alcotest.fail e
      | Ok () -> Alcotest.(check int64) "B8/B16 merge" 0x112233445566AABBL (get_reg state Register.rax))

let test_lift_sse_avx () =
  let asm = {|
vector_ops:
    movaps xmm0, xmm1
    paddq xmm0, xmm2
    vaddps ymm3, ymm4, ymm5
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let fbits value = Int64.logand (Int64.of_int32 (Int32.bits_of_float value)) 0xFFFFFFFFL in
      let pack_f32s a b c d =
        let chunk0 = Int64.logor (fbits a) (Int64.shift_left (fbits b) 32) in
        let chunk1 = Int64.logor (fbits c) (Int64.shift_left (fbits d) 32) in
        [| chunk0; chunk1; 0L; 0L; 0L; 0L; 0L; 0L |]
      in
      let state = make_state () in
      Hashtbl.replace state.vectors 1 [|10L; 20L; 0L; 0L; 0L; 0L; 0L; 0L|];
      Hashtbl.replace state.vectors 2 [|3L; 4L; 30L; 40L; 0L; 0L; 0L; 0L|];
      Hashtbl.replace state.vectors 4 (pack_f32s 1.0 2.0 3.0 4.0);
      Hashtbl.replace state.vectors 5 (pack_f32s 10.0 20.0 30.0 40.0);
      Hashtbl.replace state.vectors 0 [|100L; 200L; 300L; 400L; 0L; 0L; 0L; 0L|];
      Hashtbl.replace state.vectors 3 [|0L; 0L; 0L; 0L; 0L; 0L; 0L; 0L|];
      (match run_func state func with
      | Error e -> Alcotest.fail e
      | Ok () ->
          let xmm0 = Hashtbl.find state.vectors 0 in
          let ymm3 = Hashtbl.find state.vectors 3 in
          Alcotest.(check int64) "SSE paddq" 13L xmm0.(0);
          Alcotest.(check int64) "SSE paddq high" 24L xmm0.(1);
          Alcotest.(check int64) "AVX vaddps lane0" (fbits 11.0) (Int64.logand ymm3.(0) 0xFFFFFFFFL);
          Alcotest.(check int64) "AVX vaddps lane1" (fbits 22.0) (Int64.logand (Int64.shift_right_logical ymm3.(0) 32) 0xFFFFFFFFL);
          Alcotest.(check int64) "AVX vaddps lane2" (fbits 33.0) (Int64.logand ymm3.(1) 0xFFFFFFFFL);
          Alcotest.(check int64) "AVX vaddps lane3" (fbits 44.0) (Int64.logand (Int64.shift_right_logical ymm3.(1) 32) 0xFFFFFFFFL))

let tests = [
  Alcotest.test_case "parser_memory_operands" `Quick test_parser_memory_operands;
  Alcotest.test_case "lift_and_eval_math" `Quick test_lift_and_eval_math;
  Alcotest.test_case "lift_and_eval_abs_branch" `Quick test_lift_and_eval_abs_branch;
  Alcotest.test_case "lift_and_eval_factorial_loop" `Quick test_lift_and_eval_factorial_loop;
  Alcotest.test_case "lift_and_eval_mem_rmw" `Quick test_lift_and_eval_mem_rmw;
  Alcotest.test_case "lift_and_eval_array_sum_sib" `Quick test_lift_and_eval_array_sum_sib;
  Alcotest.test_case "marker_region_extraction" `Quick test_marker_region_extraction;
  Alcotest.test_case "lift_and_eval_div64_signed" `Quick test_lift_and_eval_div64_signed;
  Alcotest.test_case "lift_and_eval_div64_unsigned" `Quick test_lift_and_eval_div64_unsigned;
  Alcotest.test_case "lift_and_eval_div64_with_rdx" `Quick test_lift_and_eval_div64_with_rdx;
  Alcotest.test_case "lift_and_eval_idiv32_signed" `Quick test_lift_and_eval_idiv32_signed;
  Alcotest.test_case "lift_and_eval_div32_unsigned" `Quick test_lift_and_eval_div32_unsigned;
  Alcotest.test_case "lift_and_eval_cdqe_sext" `Quick test_lift_and_eval_cdqe_sext;
  Alcotest.test_case "lift_and_eval_b32_write_zero_extends" `Quick test_lift_and_eval_b32_write_zero_extends;
  Alcotest.test_case "lift_and_eval_movsx_mem" `Quick test_lift_and_eval_movsx_mem;
  Alcotest.test_case "lift_and_eval_movsx_reg" `Quick test_lift_and_eval_movsx_reg;
    Alcotest.test_case "lift_and_eval_movzx_reg" `Quick test_lift_and_eval_movzx_reg;
    Alcotest.test_case "lift_one_operand_mul_b8" `Quick test_lift_one_operand_mul;
    Alcotest.test_case "lift_one_operand_mul_b8_signed" `Quick test_lift_one_operand_mul_signed;
    Alcotest.test_case "lift_one_operand_mul_b64" `Quick test_lift_one_operand_mul64;
    Alcotest.test_case "lift_one_operand_imul_b64" `Quick test_lift_one_operand_imul64;
    Alcotest.test_case "lift_one_operand_mul_b32" `Quick test_lift_one_operand_mul32;
    Alcotest.test_case "lift_one_operand_imul_b32" `Quick test_lift_one_operand_imul32;
    Alcotest.test_case "lift_one_operand_mul_b16" `Quick test_lift_one_operand_mul16;
    Alcotest.test_case "lift_one_operand_imul_b16" `Quick test_lift_one_operand_imul16;
    Alcotest.test_case "lift_one_operand_mul_mem" `Quick test_lift_one_operand_mul_mem;
    Alcotest.test_case "lift_narrow_division_b8" `Quick test_lift_narrow_division;
    Alcotest.test_case "lift_narrow_division_b8_signed" `Quick test_lift_narrow_division_signed;
  Alcotest.test_case "lift_narrow_division_b16" `Quick test_lift_narrow_division16;
  Alcotest.test_case "division_by_zero_fault" `Quick test_division_by_zero_fault;
  Alcotest.test_case "b8_b16_merge_semantics" `Quick test_b8_b16_merge_semantics;
    Alcotest.test_case "lift_sse_avx" `Quick test_lift_sse_avx;
 ]

