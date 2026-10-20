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

(* MOVZX covers five encodings: 0F B6 (r/m8) and 0F B7 (r/m16) with a
   16/32/64-bit destination.  Every destination width must end up with the
   source zero-extended and, for 32-bit destinations, with the upper 32 bits
   of the parent register cleared. *)
let test_lift_and_eval_movzx_forms () =
  let asm = {|
movzx_forms:
    movzx r8, cl
    movzx r9d, dl
    movzx r10, cx
    movzx r11d, dx
    movzx r12, byte ptr [rdi]
    movzx r13d, byte ptr [rdi]
    movzx r14, word ptr [rdi + 2]
    movzx r15d, word ptr [rdi + 2]
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let state = make_state () in
      set_reg state Register.rdi 0x1000L;
      set_reg state Register.rcx 0x1234L;
      set_reg state Register.rdx 0xA5L;
      write_mem state 0x1000L Register.B8 0x5AL;
      write_mem state 0x1002L Register.B16 0xBEEFL;
      match run_func state func with
      | Error e -> Alcotest.fail e
      | Ok () ->
          Alcotest.(check int64) "movzx r64, r/m8 (reg)" 0x34L (get_reg state Register.r8);
          Alcotest.(check int64) "movzx r32, r/m8 (reg)" 0xA5L (get_reg state Register.r9);
          Alcotest.(check int64) "movzx r64, r/m16 (reg)" 0x1234L (get_reg state Register.r10);
          Alcotest.(check int64) "movzx r32, r/m16 (reg)" 0xA5L (get_reg state Register.r11);
          Alcotest.(check int64) "movzx r64, r/m8 (mem)" 0x5AL (get_reg state Register.r12);
          Alcotest.(check int64) "movzx r32, r/m8 (mem)" 0x5AL (get_reg state Register.r13);
          Alcotest.(check int64) "movzx r64, r/m16 (mem)" 0xBEEFL (get_reg state Register.r14);
          Alcotest.(check int64) "movzx r32, r/m16 (mem)" 0xBEEFL (get_reg state Register.r15)

let test_lift_and_eval_rol_ror () =
  let asm = {|
rol_ror_test:
    rol rax, 4
    ror rbx, 4
    rol edx, 8
    ror ecx, 1
    rol r8
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let state = make_state () in
      set_reg state Register.rax 0x123456789ABCDEF0L;
      set_reg state Register.rbx 0x123456789ABCDEF0L;
      set_reg state Register.rdx 0x1122334412345678L;
      set_reg state Register.rcx 0x0000000000000001L;
      set_reg state Register.r8  0x8000000000000001L;
      match run_func state func with
      | Error e -> Alcotest.fail e
      | Ok () ->
          Alcotest.(check int64) "rol rax, 4" 0x23456789ABCDEF01L (get_reg state Register.rax);
          Alcotest.(check int64) "ror rbx, 4" 0x0123456789ABCDEFL (get_reg state Register.rbx);
          Alcotest.(check int64) "rol edx, 8 zeroes upper 32" 0x34567812L (get_reg state Register.rdx);
          Alcotest.(check int64) "ror ecx, 1 zeroes upper 32" 0x80000000L (get_reg state Register.rcx);
          Alcotest.(check int64) "rol r8 (implicit 1)" 0x0000000000000003L (get_reg state Register.r8)

let test_x86_fpu_load_store () =
  let asm = {|
fpu_ld_st:
    sub rsp, 64
    fld1
    fldz
    fldpi
    fst qword ptr [rsp]
    fstp qword ptr [rsp + 8]
    mov dword ptr [rsp + 16], 42
    fild dword ptr [rsp + 16]
    fistp dword ptr [rsp + 24]
    add rsp, 64
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let state = make_state () in
      set_reg state Register.rsp 0x1000L;
      match run_func state func with
      | Error e -> Alcotest.fail e
      | Ok () ->
          let sp = 0x1000L in
          let pi_bits = read_mem state (Int64.sub sp 64L) Register.B64 in
          let pi_val = Int64.float_of_bits pi_bits in
          Alcotest.(check bool) "fst stored pi" true (abs_float (pi_val -. 3.141592653589793) < 1e-10);
          let pi_bits2 = read_mem state (Int64.add (Int64.sub sp 64L) 8L) Register.B64 in
          let pi_val2 = Int64.float_of_bits pi_bits2 in
          Alcotest.(check bool) "fstp stored pi" true (abs_float (pi_val2 -. 3.141592653589793) < 1e-10);
          let int_res = read_mem state (Int64.add (Int64.sub sp 64L) 24L) Register.B32 in
          Alcotest.(check int64) "fistp converted 42 back to int" 42L int_res

let test_x86_fpu_arithmetic () =
  let asm = {|
fpu_arith:
    sub rsp, 32
    fld1
    fld1
    faddp st(1), st(0)
    fst qword ptr [rsp]
    fld1
    fsubp
    fst qword ptr [rsp + 8]
    fld1
    fld1
    faddp
    fld1
    fld1
    faddp
    fmulp
    fstp qword ptr [rsp + 16]
    add rsp, 32
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let state = make_state () in
      set_reg state Register.rsp 0x1000L;
      match run_func state func with
      | Error e -> Alcotest.fail e
      | Ok () ->
          let sp = 0x1000L in
          let two_bits = read_mem state (Int64.sub sp 32L) Register.B64 in
          let two_val = Int64.float_of_bits two_bits in
          Alcotest.(check bool) "faddp 1+1 = 2" true (abs_float (two_val -. 2.0) < 1e-10);
          let one_bits = read_mem state (Int64.add (Int64.sub sp 32L) 8L) Register.B64 in
          let one_val = Int64.float_of_bits one_bits in
          Alcotest.(check bool) "fsubp 2-1 = 1" true (abs_float (one_val -. 1.0) < 1e-10);
          let four_bits = read_mem state (Int64.add (Int64.sub sp 32L) 16L) Register.B64 in
          let four_val = Int64.float_of_bits four_bits in
          Alcotest.(check bool) "fmulp 2*2 = 4" true (abs_float (four_val -. 4.0) < 1e-10)

let test_x86_fpu_comparison () =
  let asm = {|
fpu_cmp:
    fld1
    fldz
    fcomi st(1)
    setb dl
    fstsw ax
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let state = make_state () in
      match run_func state func with
      | Error e -> Alcotest.fail e
      | Ok () ->
          let ax_val = Int64.logand (get_reg state Register.rax) 0xFFFFL in
          Alcotest.(check bool) "fstsw ax wrote status word" true (ax_val <> 0L);
          let dl_val = Int64.logand (get_reg state Register.rdx) 0xFFL in
          Alcotest.(check int64) "fcomi 0 < 1 set CF (setb dl=1)" 1L dl_val

let test_x86_fpu_unary_and_transcendental () =
  let asm = {|
fpu_trans:
    sub rsp, 32
    fld1
    fchs
    fabs
    fst qword ptr [rsp]
    fldz
    fcos
    fst qword ptr [rsp + 8]
    add rsp, 32
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let state = make_state () in
      set_reg state Register.rsp 0x1000L;
      match run_func state func with
      | Error e -> Alcotest.fail e
      | Ok () ->
          let sp = 0x1000L in
          let one_bits = read_mem state (Int64.sub sp 32L) Register.B64 in
          let one_val = Int64.float_of_bits one_bits in
          Alcotest.(check bool) "fchs + fabs = 1.0" true (abs_float (one_val -. 1.0) < 1e-10);
          let cos_bits = read_mem state (Int64.add (Int64.sub sp 32L) 8L) Register.B64 in
          let cos_val = Int64.float_of_bits cos_bits in
          Alcotest.(check bool) "fcos(0) = 1.0" true (abs_float (cos_val -. 1.0) < 1e-10)

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

let test_x86_movss_movsd_vector_moves () =
  let asm = {|
func_moves:
    movss xmm0, xmm1
    movsd xmm2, xmm3
    movss dword ptr [rsp + 16], xmm0
    movss xmm5, dword ptr [rsp + 16]
    movsd qword ptr [rsp + 24], xmm2
    movsd xmm6, qword ptr [rsp + 24]
    vmovss xmm7, xmm0, xmm1
    vmovsd xmm8, xmm2, xmm3
    movups xmm9, xmm0
    movaps xmm10, xmm1
    movdqu xmm11, xmm2
    movdqa xmm12, xmm3
    movupd xmm13, xmm0
    movapd xmm14, xmm1
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let state = make_state () in
      state.vsp <- 0x1000L;
      Hashtbl.replace state.vectors 0 [| 0x1111111122222222L; 0x3333333344444444L; 0x5555555566666666L; 0x7777777788888888L; 0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 1 [| 0xAAAABBBBCCCCDDDDL; 0xEEEEFFFF00001111L; 0L; 0L; 0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 2 [| 0x123456789ABCDEF0L; 0xFEDCBA9876543210L; 0L; 0L; 0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 3 [| 0x0102030405060708L; 0x090A0B0C0D0E0F00L; 0L; 0L; 0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 7 [| 0L; 0L; 0xDEADBEEFCAFEBABEL; 0xDEADBEEFCAFEBABEL; 0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 8 [| 0L; 0L; 0xDEADBEEFCAFEBABEL; 0xDEADBEEFCAFEBABEL; 0L; 0L; 0L; 0L |];
      write_mem state 0x1014L B32 0xA5A5A5A5L;
      (match run_func state func with
      | Error e -> Alcotest.fail e
      | Ok () ->
          let v0 = Hashtbl.find state.vectors 0 in
          let v2 = Hashtbl.find state.vectors 2 in
          let v5 = Hashtbl.find state.vectors 5 in
          let v6 = Hashtbl.find state.vectors 6 in
          let v7 = Hashtbl.find state.vectors 7 in
          let v8 = Hashtbl.find state.vectors 8 in
          let v9 = Hashtbl.find state.vectors 9 in
          let v10 = Hashtbl.find state.vectors 10 in
          let v11 = Hashtbl.find state.vectors 11 in
          let v12 = Hashtbl.find state.vectors 12 in
          let v13 = Hashtbl.find state.vectors 13 in
          let v14 = Hashtbl.find state.vectors 14 in
          Alcotest.(check int64) "movss reg lane0" 0x11111111CCCCDDDDL v0.(0);
          Alcotest.(check int64) "movss reg lane1" 0x3333333344444444L v0.(1);
          Alcotest.(check int64) "movsd reg lane0" 0x0102030405060708L v2.(0);
          Alcotest.(check int64) "movsd reg lane1" 0xFEDCBA9876543210L v2.(1);
          Alcotest.(check int64) "canary untouched" 0xA5A5A5A5L (read_mem state 0x1014L B32);
          Alcotest.(check int64) "movss mem lane0" 0x00000000CCCCDDDDL v5.(0);
          Alcotest.(check int64) "movss mem lane1 zeroed" 0L v5.(1);
          Alcotest.(check int64) "movsd mem lane0" 0x0102030405060708L v6.(0);
          Alcotest.(check int64) "movsd mem lane1 zeroed" 0L v6.(1);
          Alcotest.(check int64) "vmovss lane0" 0x11111111CCCCDDDDL v7.(0);
          Alcotest.(check int64) "vmovss lane1" 0x3333333344444444L v7.(1);
          Alcotest.(check int64) "vmovss lane2 zeroed" 0L v7.(2);
          Alcotest.(check int64) "vmovsd lane0" 0x0102030405060708L v8.(0);
          Alcotest.(check int64) "vmovsd lane1" 0xFEDCBA9876543210L v8.(1);
          Alcotest.(check int64) "vmovsd lane2 zeroed" 0L v8.(2);
          Alcotest.(check int64) "movups" v0.(0) v9.(0);
          Alcotest.(check int64) "movaps" (Hashtbl.find state.vectors 1).(0) v10.(0);
          Alcotest.(check int64) "movdqu" v2.(0) v11.(0);
          Alcotest.(check int64) "movdqa" (Hashtbl.find state.vectors 3).(0) v12.(0);
          Alcotest.(check int64) "movupd" v0.(0) v13.(0);
          Alcotest.(check int64) "movapd" (Hashtbl.find state.vectors 1).(0) v14.(0))

let test_x86_scalar_and_packed_fp_arithmetic () =
  let asm = {|
func_fp_arith:
    addss xmm0, xmm1
    subss xmm2, xmm3
    mulss xmm4, xmm5
    divss xmm6, xmm7
    addsd xmm8, xmm9
    subsd xmm10, xmm11
    mulsd xmm12, xmm13
    divsd xmm14, xmm15
    addpd xmm16, xmm17
    subpd xmm18, xmm19
    mulpd xmm20, xmm21
    divpd xmm22, xmm23
    vdivps ymm24, ymm25, ymm26
    vdivpd ymm27, ymm28, ymm29
    vaddss xmm30, xmm0, xmm1
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let fbits v = Int64.logand (Int64.of_int32 (Int32.bits_of_float v)) 0xFFFFFFFFL in
      let dbits v = Int64.bits_of_float v in
      let state = make_state () in
      Hashtbl.replace state.vectors 0 [| Int64.logor (fbits 10.0) 0x1111111100000000L; 0x2222222233333333L; 0L; 0L; 0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 1 [| fbits 2.5; 0L; 0L; 0L; 0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 2 [| Int64.logor (fbits 10.0) 0x4444444400000000L; 0x5555555566666666L; 0L; 0L; 0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 3 [| fbits 2.5; 0L; 0L; 0L; 0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 4 [| fbits 10.0; 0x7777777788888888L; 0L; 0L; 0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 5 [| fbits 2.5; 0L; 0L; 0L; 0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 6 [| fbits 10.0; 0x99999999AAAAAAAAL; 0L; 0L; 0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 7 [| fbits 2.5; 0L; 0L; 0L; 0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 8 [| dbits 10.0; 0xBBBBBBBBCCCCCCCCL; 0L; 0L; 0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 9 [| dbits 2.5; 0L; 0L; 0L; 0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 10 [| dbits 10.0; 0xDDDDDDDDEEEEEEEEL; 0L; 0L; 0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 11 [| dbits 2.5; 0L; 0L; 0L; 0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 12 [| dbits 10.0; 0xFFFFFFFF00000000L; 0L; 0L; 0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 13 [| dbits 2.5; 0L; 0L; 0L; 0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 14 [| dbits 10.0; 0x1234567812345678L; 0L; 0L; 0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 15 [| dbits 2.5; 0L; 0L; 0L; 0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 16 [| dbits 1.0; dbits 2.0; 0L; 0L; 0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 17 [| dbits 3.0; dbits 4.0; 0L; 0L; 0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 18 [| dbits 10.0; dbits 20.0; 0L; 0L; 0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 19 [| dbits 1.0; dbits 2.0; 0L; 0L; 0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 20 [| dbits 2.0; dbits 3.0; 0L; 0L; 0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 21 [| dbits 4.0; dbits 5.0; 0L; 0L; 0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 22 [| dbits 10.0; dbits 20.0; 0L; 0L; 0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 23 [| dbits 2.0; dbits 4.0; 0L; 0L; 0L; 0L; 0L; 0L |];
      let pack2 a b = Int64.logor (fbits a) (Int64.shift_left (fbits b) 32) in
      Hashtbl.replace state.vectors 25 [| pack2 10.0 20.0; pack2 30.0 40.0; pack2 50.0 60.0; pack2 70.0 80.0; 0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 26 [| pack2 2.0 4.0; pack2 5.0 8.0; pack2 10.0 12.0; pack2 14.0 16.0; 0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 28 [| dbits 100.0; dbits 200.0; dbits 300.0; dbits 400.0; 0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 29 [| dbits 10.0; dbits 20.0; dbits 30.0; dbits 40.0; 0L; 0L; 0L; 0L |];
      (match run_func state func with
      | Error e -> Alcotest.fail e
      | Ok () ->
          let v0 = Hashtbl.find state.vectors 0 in
          let v2 = Hashtbl.find state.vectors 2 in
          let v4 = Hashtbl.find state.vectors 4 in
          let v6 = Hashtbl.find state.vectors 6 in
          let v8 = Hashtbl.find state.vectors 8 in
          let v10 = Hashtbl.find state.vectors 10 in
          let v12 = Hashtbl.find state.vectors 12 in
          let v14 = Hashtbl.find state.vectors 14 in
          let v16 = Hashtbl.find state.vectors 16 in
          let v18 = Hashtbl.find state.vectors 18 in
          let v20 = Hashtbl.find state.vectors 20 in
          let v22 = Hashtbl.find state.vectors 22 in
          let v24 = Hashtbl.find state.vectors 24 in
          let v27 = Hashtbl.find state.vectors 27 in
          let v30 = Hashtbl.find state.vectors 30 in
          Alcotest.(check int64) "addss val" (fbits 12.5) (Int64.logand v0.(0) 0xFFFFFFFFL);
          Alcotest.(check int64) "addss upper32" 0x1111111100000000L (Int64.logand v0.(0) 0xFFFFFFFF00000000L);
          Alcotest.(check int64) "addss lane1" 0x2222222233333333L v0.(1);
          Alcotest.(check int64) "subss val" (fbits 7.5) (Int64.logand v2.(0) 0xFFFFFFFFL);
          Alcotest.(check int64) "subss lane1" 0x5555555566666666L v2.(1);
          Alcotest.(check int64) "mulss val" (fbits 25.0) (Int64.logand v4.(0) 0xFFFFFFFFL);
          Alcotest.(check int64) "mulss lane1" 0x7777777788888888L v4.(1);
          Alcotest.(check int64) "divss val" (fbits 4.0) (Int64.logand v6.(0) 0xFFFFFFFFL);
          Alcotest.(check int64) "divss lane1" 0x99999999AAAAAAAAL v6.(1);
          Alcotest.(check int64) "addsd val" (dbits 12.5) v8.(0);
          Alcotest.(check int64) "addsd lane1" 0xBBBBBBBBCCCCCCCCL v8.(1);
          Alcotest.(check int64) "subsd val" (dbits 7.5) v10.(0);
          Alcotest.(check int64) "subsd lane1" 0xDDDDDDDDEEEEEEEEL v10.(1);
          Alcotest.(check int64) "mulsd val" (dbits 25.0) v12.(0);
          Alcotest.(check int64) "mulsd lane1" 0xFFFFFFFF00000000L v12.(1);
          Alcotest.(check int64) "divsd val" (dbits 4.0) v14.(0);
          Alcotest.(check int64) "divsd lane1" 0x1234567812345678L v14.(1);
          Alcotest.(check int64) "addpd lane0" (dbits 4.0) v16.(0);
          Alcotest.(check int64) "addpd lane1" (dbits 6.0) v16.(1);
          Alcotest.(check int64) "subpd lane0" (dbits 9.0) v18.(0);
          Alcotest.(check int64) "subpd lane1" (dbits 18.0) v18.(1);
          Alcotest.(check int64) "mulpd lane0" (dbits 8.0) v20.(0);
          Alcotest.(check int64) "mulpd lane1" (dbits 15.0) v20.(1);
          Alcotest.(check int64) "divpd lane0" (dbits 5.0) v22.(0);
          Alcotest.(check int64) "divpd lane1" (dbits 5.0) v22.(1);
          Alcotest.(check int64) "vdivps 0" (fbits 5.0) (Int64.logand v24.(0) 0xFFFFFFFFL);
          Alcotest.(check int64) "vdivps 1" (fbits 5.0) (Int64.logand (Int64.shift_right_logical v24.(0) 32) 0xFFFFFFFFL);
          Alcotest.(check int64) "vdivpd 0" (dbits 10.0) v27.(0);
          Alcotest.(check int64) "vdivpd 1" (dbits 10.0) v27.(1);
          Alcotest.(check int64) "vdivpd 2" (dbits 10.0) v27.(2);
          Alcotest.(check int64) "vdivpd 3" (dbits 10.0) v27.(3);
          Alcotest.(check int64) "vaddss val" (fbits 15.0) (Int64.logand v30.(0) 0xFFFFFFFFL);
          Alcotest.(check int64) "vaddss upper32" 0x1111111100000000L (Int64.logand v30.(0) 0xFFFFFFFF00000000L);
          Alcotest.(check int64) "vaddss lane1" 0x2222222233333333L v30.(1);
          Alcotest.(check int64) "vaddss lane2 zeroed" 0L v30.(2))

(* ORPS / ORPD are bitwise operations on the raw element patterns: the result
   is the OR of the operands, never a numeric operation on the floats.  The
   legacy SSE form has two operands (dst = dst | src) and writes only the low
   128 bits, so the upper half of the destination survives; the VEX form has
   three operands and zeroes the upper half of a 128-bit destination. *)
let test_x86_lift_orps_orpd () =
  let asm = {|
func_orps_orpd:
    orps xmm0, xmm1
    orpd xmm2, xmm3
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let state = make_state () in
      Hashtbl.replace state.vectors 0
        [| 0x0F0F0F0F0F0F0F0FL;
           0x1234567890ABCDEFL;
           0xAAAAAAAAAAAAAAAAL;
           0xBBBBBBBBBBBBBBBBL;
           0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 1
        [| 0xF0F0F0F0F0F0F0F0L;
           0x0F0F0F0F0F0F0F0FL;
           0x5555555555555555L;
           0L; 0L; 0L; 0L; 0L |];
      (* ORPD over double bit patterns: 1.0, -2.0 and a raw pattern *)
      Hashtbl.replace state.vectors 2
        [| 0x3FF0000000000000L;
           0xC000000000000000L;
           0xAAAAAAAAAAAAAAAAL;
           0L; 0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 3
        [| 0x3FE0000000000000L;
           0x00000000000000FFL;
           0x5555555555555555L;
           0L; 0L; 0L; 0L; 0L |];
      (match run_func state func with
      | Error e -> Alcotest.fail e
      | Ok () ->
          let xmm0 = Hashtbl.find state.vectors 0 in
          let xmm2 = Hashtbl.find state.vectors 2 in
          Alcotest.(check int64) "orps lane 0" 0xFFFFFFFFFFFFFFFFL xmm0.(0);
          Alcotest.(check int64) "orps lane 1" 0x1F3F5F7F9FAFCFEFL xmm0.(1);
          Alcotest.(check int64) "orps keeps the upper 128 bits" 0xAAAAAAAAAAAAAAAAL xmm0.(2);
          Alcotest.(check int64) "orps keeps the upper 128 bits" 0xBBBBBBBBBBBBBBBBL xmm0.(3);
          Alcotest.(check int64) "orpd lane 0" 0x3FF0000000000000L xmm2.(0);
          Alcotest.(check int64) "orpd lane 1" 0xC0000000000000FFL xmm2.(1);
          Alcotest.(check int64) "orpd keeps the upper 128 bits" 0xAAAAAAAAAAAAAAAAL xmm2.(2))

let test_x86_lift_vorps_vorpd () =
  let asm = {|
func_vor:
    vorps ymm0, ymm1, ymm2
    vorpd ymm3, ymm4, ymm5
    vorps xmm6, xmm7, xmm8
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let state = make_state () in
      Hashtbl.replace state.vectors 1
        [| 0x0F0F0F0F0F0F0F0FL;
           0x1111111111111111L;
           0x2222222222222222L;
           0x3333333333333333L;
           0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 2
        [| 0xF0F0F0F0F0F0F0F0L;
           0x0F0F0F0F0F0F0F0FL;
           0x00000000000000FFL;
           0x000000000000FF00L;
           0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 4
        [| 0x3FF0000000000000L;
           0xC000000000000000L;
           0x0F0F0F0F0F0F0F0FL;
           0x7777777777777777L;
           0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 5
        [| 0x3FE0000000000000L;
           0x00000000000000FFL;
           0xF0F0F0F0F0F0F0F0L;
           0L; 0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 7
        [| 0x0F0F0F0F0F0F0F0FL;
           0x1234567890ABCDEFL;
           0xCCCCCCCCCCCCCCCCL;
           0xDDDDDDDDDDDDDDDDL;
           0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 8
        [| 0xF0F0F0F0F0F0F0F0L;
           0x0F0F0F0F0F0F0F0FL;
           0L; 0L; 0L; 0L; 0L; 0L |];
      (match run_func state func with
      | Error e -> Alcotest.fail e
      | Ok () ->
          let ymm0 = Hashtbl.find state.vectors 0 in
          let ymm3 = Hashtbl.find state.vectors 3 in
          let xmm6 = Hashtbl.find state.vectors 6 in
          Alcotest.(check int64) "vorps chunk 0" 0xFFFFFFFFFFFFFFFFL ymm0.(0);
          Alcotest.(check int64) "vorps chunk 1" 0x1F1F1F1F1F1F1F1FL ymm0.(1);
          Alcotest.(check int64) "vorps chunk 2" 0x22222222222222FFL ymm0.(2);
          Alcotest.(check int64) "vorps chunk 3" 0x333333333333FF33L ymm0.(3);
          Alcotest.(check int64) "vorpd chunk 0" 0x3FF0000000000000L ymm3.(0);
          Alcotest.(check int64) "vorpd chunk 1" 0xC0000000000000FFL ymm3.(1);
          Alcotest.(check int64) "vorpd chunk 2" 0xFFFFFFFFFFFFFFFFL ymm3.(2);
          Alcotest.(check int64) "vorpd chunk 3" 0x7777777777777777L ymm3.(3);
          Alcotest.(check int64) "vex-128 vorps lane 0" 0xFFFFFFFFFFFFFFFFL xmm6.(0);
          Alcotest.(check int64) "vex-128 vorps lane 1" 0x1F3F5F7F9FAFCFEFL xmm6.(1);
          Alcotest.(check int64) "vex-128 vorps zeroes the upper half" 0L xmm6.(2);
          Alcotest.(check int64) "vex-128 vorps zeroes the upper half" 0L xmm6.(3))

let test_x86_bitmanip () =
  let asm = {|
func_bitmanip:
    mov rdi, 0x123456789abcdef0
    bswap rdi
    mov rax, rdi
    popcnt rdx, rax
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let state = make_state () in
      match run_func state func with
      | Error e -> Alcotest.fail e
      | Ok () ->
          Alcotest.(check int64) "bswap64" (-1090226688147180526L) (get_reg state Register.rax);
          Alcotest.(check int64) "popcount64" 32L (get_reg state Register.rdx)

let test_x86_fp_scalar () =
  let asm = {|
func_fpscalar:
    mov rdi, 10
    cvtsi2sd xmm0, rdi
    mov rsi, 4
    cvtsi2sd xmm1, rsi
    addsd xmm0, xmm1
    cvttsd2si rax, xmm0
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let state = make_state () in
      match run_func state func with
      | Error e -> Alcotest.fail e
      | Ok () ->
          Alcotest.(check int64) "fp 10 + 4 = 14" 14L (get_reg state Register.rax)

let test_x86_int_float_conversions () =
  let asm = {|
func_conversions:
    cvtsi2ss xmm0, edi
    cvtsi2sd xmm1, rsi
    cvttss2si r8d, xmm0
    cvttsd2si r9, xmm1
    cvtsd2ss xmm2, xmm1
    cvtss2sd xmm3, xmm0
    vcvtsi2sd xmm4, xmm1, edx
    cvtsi2sd xmm5, dword ptr [rsp + 16]
    cvttss2si r10d, dword ptr [rsp + 24]
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let fbits v = Int64.logand (Int64.of_int32 (Int32.bits_of_float v)) 0xFFFFFFFFL in
      let dbits v = Int64.bits_of_float v in
      let state = make_state () in
      state.vsp <- 0x2000L;
      set_reg state Register.rdi 42L;
      set_reg state Register.rsi (-100L);
      set_reg state Register.rdx 77L;
      write_mem state 0x2010L B32 0xFFFFFFFBL;
      write_mem state 0x2018L B32 (fbits 12.5);
      Hashtbl.replace state.vectors 0 [| 0x1111111100000000L; 0x2222222233333333L; 0L; 0L; 0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 1 [| 0L; 0x4444444455555555L; 0L; 0L; 0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 2 [| 0x6666666600000000L; 0x7777777788888888L; 0L; 0L; 0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 3 [| 0L; 0x99999999AAAAAAAAL; 0L; 0L; 0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 4 [| 0L; 0L; 0xDEADBEEFCAFEBABEL; 0xDEADBEEFCAFEBABEL; 0L; 0L; 0L; 0L |];
      (match run_func state func with
      | Error e -> Alcotest.fail e
      | Ok () ->
          let v0 = Hashtbl.find state.vectors 0 in
          let v1 = Hashtbl.find state.vectors 1 in
          let v2 = Hashtbl.find state.vectors 2 in
          let v3 = Hashtbl.find state.vectors 3 in
          let v4 = Hashtbl.find state.vectors 4 in
          let v5 = Hashtbl.find state.vectors 5 in
          Alcotest.(check int64) "cvtsi2ss val" (fbits 42.0) (Int64.logand v0.(0) 0xFFFFFFFFL);
          Alcotest.(check int64) "cvtsi2ss upper32" 0x1111111100000000L (Int64.logand v0.(0) 0xFFFFFFFF00000000L);
          Alcotest.(check int64) "cvtsi2ss lane1" 0x2222222233333333L v0.(1);
          Alcotest.(check int64) "cvtsi2sd val" (dbits (-100.0)) v1.(0);
          Alcotest.(check int64) "cvtsi2sd lane1" 0x4444444455555555L v1.(1);
          Alcotest.(check int64) "cvttss2si" 42L (get_reg state (Register.Gpr (Register.R8, Register.B32)));
          Alcotest.(check int64) "cvttsd2si" (-100L) (get_reg state (Register.Gpr (Register.R9, Register.B64)));
          Alcotest.(check int64) "cvtsd2ss val" (fbits (-100.0)) (Int64.logand v2.(0) 0xFFFFFFFFL);
          Alcotest.(check int64) "cvtsd2ss upper32" 0x6666666600000000L (Int64.logand v2.(0) 0xFFFFFFFF00000000L);
          Alcotest.(check int64) "cvtsd2ss lane1" 0x7777777788888888L v2.(1);
          Alcotest.(check int64) "cvtss2sd val" (dbits 42.0) v3.(0);
          Alcotest.(check int64) "cvtss2sd lane1" 0x99999999AAAAAAAAL v3.(1);
          Alcotest.(check int64) "vcvtsi2sd val" (dbits 77.0) v4.(0);
          Alcotest.(check int64) "vcvtsi2sd lane1" 0x4444444455555555L v4.(1);
          Alcotest.(check int64) "vcvtsi2sd lane2 zeroed" 0L v4.(2);
          Alcotest.(check int64) "cvtsi2sd mem signed" (dbits (-5.0)) v5.(0);
          Alcotest.(check int64) "cvttss2si mem" 12L (get_reg state (Register.Gpr (Register.R10, Register.B32))))

let test_x86_float_comparisons () =
  let asm = {|
func_comi:
    mov rax, 0
    ucomiss xmm0, xmm1
    jbe .L_skip1
    mov rax, 1
.L_skip1:
    mov rbx, 0
    comiss xmm2, xmm3
    jae .L_skip2
    mov rbx, 1
.L_skip2:
    mov rcx, 0
    ucomisd xmm4, xmm5
    jne .L_skip3
    mov rcx, 1
.L_skip3:
    mov rdx, 0
    comisd xmm6, xmm7
    jnp .L_skip4
    mov rdx, 1
.L_skip4:
    mov rsi, 0
    comiss xmm0, dword ptr [rsp + 16]
    jne .L_skip5
    mov rsi, 1
.L_skip5:
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let fbits v = Int64.logand (Int64.of_int32 (Int32.bits_of_float v)) 0xFFFFFFFFL in
      let dbits v = Int64.bits_of_float v in
      let state = make_state () in
      state.vsp <- 0x1000L;
      write_mem state 0x1010L B32 (fbits 10.0);
      Hashtbl.replace state.vectors 0 [| fbits 10.0; 0L; 0L; 0L; 0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 1 [| fbits 2.5; 0L; 0L; 0L; 0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 2 [| fbits 1.0; 0L; 0L; 0L; 0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 3 [| fbits 5.0; 0L; 0L; 0L; 0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 4 [| dbits 7.5; 0L; 0L; 0L; 0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 5 [| dbits 7.5; 0L; 0L; 0L; 0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 6 [| dbits Float.nan; 0L; 0L; 0L; 0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 7 [| dbits 1.0; 0L; 0L; 0L; 0L; 0L; 0L; 0L |];
      (match run_func state func with
      | Error e -> Alcotest.fail e
      | Ok () ->
          Alcotest.(check int64) "greater: ja taken" 1L (get_reg state Register.rax);
          Alcotest.(check int64) "less: jb taken" 1L (get_reg state Register.rbx);
          Alcotest.(check int64) "equal: je taken" 1L (get_reg state Register.rcx);
          Alcotest.(check int64) "nan: jp taken" 1L (get_reg state Register.rdx);
          Alcotest.(check int64) "mem equal: je taken" 1L (get_reg state Register.rsi))

let test_x86_pand_por_pxor_pandn () =
  let asm = {|
func_bitwise:
    pand xmm0, xmm1
    por xmm2, xmm3
    pxor xmm4, xmm5
    pxor xmm6, xmm6
    pandn xmm7, xmm8
    vpandn xmm9, xmm7, xmm8
    vpor ymm10, ymm11, ymm12
    vpxor ymm13, ymm14, ymm15
    pand xmm0, xmmword ptr [rsp + 16]
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let state = make_state () in
      state.vsp <- 0x1000L;
      write_mem state 0x1010L B64 0x0F0F0F0F0F0F0F0FL;
      write_mem state 0x1018L B64 0x0F0F0F0F0F0F0F0FL;
      Hashtbl.replace state.vectors 0 [| 0xAAAAAAAAAAAAAAAA_L; 0xCCCCCCCCCCCCCCCC_L; 0L; 0L; 0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 1 [| 0xFFFFFFFF00000000L; 0x123456789ABCDEF0L; 0L; 0L; 0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 2 [| 0xAAAAAAAAAAAAAAAA_L; 0x1111111111111111L; 0L; 0L; 0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 3 [| 0x5555555555555555L; 0x2222222222222222L; 0L; 0L; 0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 4 [| 0xAAAAAAAAAAAAAAAA_L; 0x123456789ABCDEF0L; 0L; 0L; 0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 5 [| 0xFFFFFFFFFFFFFFFF_L; 0x123456789ABCDEF0L; 0L; 0L; 0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 6 [| 0xDEADBEEFCAFEBABEL; 0xFEEDFACEDEADBEEFL; 0L; 0L; 0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 7 [| 0x00000000FFFFFFFFL; 0x1111111111111111L; 0L; 0L; 0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 8 [| 0xFFFFFFFFFFFFFFFF_L; 0xFFFFFFFFFFFFFFFF_L; 0L; 0L; 0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 9 [| 0L; 0L; 0xDEADBEEFCAFEBABEL; 0xDEADBEEFCAFEBABEL; 0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 11 [| 0x1111111111111111L; 0x2222222222222222L; 0x3333333333333333L; 0x4444444444444444L; 0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 12 [| 0xEEEEEEEEEEEEEEEEL; 0xDDDDDDDDDDDDDDDD_L; 0xCCCCCCCCCCCCCCCC_L; 0xBBBBBBBBBBBBBBBB_L; 0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 14 [| 0x1234567890ABCDEF_L; 0xFEEDBEEFCAFE1234L; 0x5555555555555555L; 0xAAAAAAAAAAAAAAAA_L; 0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 15 [| 0x1234567890ABCDEF_L; 0x0000000000000000L; 0xAAAAAAAAAAAAAAAA_L; 0x5555555555555555L; 0L; 0L; 0L; 0L |];
      (match run_func state func with
      | Error e -> Alcotest.fail e
      | Ok () ->
          let v0 = Hashtbl.find state.vectors 0 in
          let v2 = Hashtbl.find state.vectors 2 in
          let v4 = Hashtbl.find state.vectors 4 in
          let v6 = Hashtbl.find state.vectors 6 in
          let v7 = Hashtbl.find state.vectors 7 in
          let v9 = Hashtbl.find state.vectors 9 in
          let v10 = Hashtbl.find state.vectors 10 in
          let v13 = Hashtbl.find state.vectors 13 in
          Alcotest.(check int64) "pand mem lane0" 0x0A0A0A0A00000000L v0.(0);
          Alcotest.(check int64) "por lane0" (-1L) v2.(0);
          Alcotest.(check int64) "por lane1" 0x3333333333333333L v2.(1);
          Alcotest.(check int64) "pxor lane0" 0x5555555555555555L v4.(0);
          Alcotest.(check int64) "pxor lane1" 0L v4.(1);
          Alcotest.(check int64) "pxor zero lane0" 0L v6.(0);
          Alcotest.(check int64) "pxor zero lane1" 0L v6.(1);
          Alcotest.(check int64) "pandn lane0" 0xFFFFFFFF00000000L v7.(0);
          Alcotest.(check int64) "pandn lane1" 0xEEEEEEEEEEEEEEEEL v7.(1);
          Alcotest.(check int64) "vpandn lane0" 0x00000000FFFFFFFFL v9.(0);
          Alcotest.(check int64) "vpandn lane1" 0x1111111111111111L v9.(1);
          Alcotest.(check int64) "vpandn lane2 zeroed" 0L v9.(2);
          Alcotest.(check int64) "vpor 0" (-1L) v10.(0);
          Alcotest.(check int64) "vpor 1" (-1L) v10.(1);
          Alcotest.(check int64) "vpor 2" (-1L) v10.(2);
          Alcotest.(check int64) "vpor 3" (-1L) v10.(3);
          Alcotest.(check int64) "vpxor 0" 0L v13.(0);
          Alcotest.(check int64) "vpxor 1" 0xFEEDBEEFCAFE1234L v13.(1);
          Alcotest.(check int64) "vpxor 2" (-1L) v13.(2);
          Alcotest.(check int64) "vpxor 3" (-1L) v13.(3))

let test_x86_aes_ni () =
  let asm = {|
func_aes:
    aesenc xmm0, xmm1
    aesimc xmm2, xmm1
    aeskeygenassist xmm3, xmm4, 0x01
    aesenclast xmm5, xmm6
    aesdec xmm7, xmm8
    aesdeclast xmm9, xmm10
    vaesenc xmm11, xmm0, xmm1
    aesenc xmm12, xmmword ptr [rsp + 16]
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let state = make_state () in
      state.vsp <- 0x1000L;
      write_mem state 0x1010L B64 0xB12C548817FEFAA0L;
      write_mem state 0x1018L B64 0x05766C2A3939A323L;
      Hashtbl.replace state.vectors 0 [| 0x2BE2F4A0BEE33D19L; 0x0848F8E92A8DC69AL; 0L; 0L; 0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 1 [| 0xB12C548817FEFAA0L; 0x05766C2A3939A323L; 0L; 0L; 0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 4 [| 0xA6D2AE2816157E2BL; 0x3C4FCF098815F7ABL; 0L; 0L; 0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 5 [| 0x1111111122222222L; 0x3333333344444444L; 0L; 0L; 0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 6 [| 0x5555555566666666L; 0x7777777788888888L; 0L; 0L; 0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 7 [| 0x2B359F68F27F9CA4L; 0x49506A0243EA5B6BL; 0L; 0L; 0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 8 [| 0x05D462F2A708372BL; 0x627D614BBFBD3EBCL; 0L; 0L; 0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 9 [| 0xAAAABBBBCCCCDDDDL; 0xEEEEFFFF00001111L; 0L; 0L; 0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 10 [| 0x123456789ABCDEF0L; 0x0102030405060708L; 0L; 0L; 0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 11 [| 0L; 0L; 0xDEADBEEFCAFEBABEL; 0xDEADBEEFCAFEBABEL; 0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 12 [| 0x2BE2F4A0BEE33D19L; 0x0848F8E92A8DC69AL; 0L; 0L; 0L; 0L; 0L; 0L |];
      (match run_func state func with
      | Error e -> Alcotest.fail e
      | Ok () ->
          let v0 = Hashtbl.find state.vectors 0 in
          let v2 = Hashtbl.find state.vectors 2 in
          let v3 = Hashtbl.find state.vectors 3 in
          let v11 = Hashtbl.find state.vectors 11 in
          let v12 = Hashtbl.find state.vectors 12 in
          Alcotest.(check int64) "aesenc lane0" 0x2B359F68F27F9CA4L v0.(0);
          Alcotest.(check int64) "aesenc lane1" 0x49506A0243EA5B6BL v0.(1);
          Alcotest.(check int64) "aesimc lane0" 0x05D462F2A708372BL v2.(0);
          Alcotest.(check int64) "aesimc lane1" 0x627D614BBFBD3EBCL v2.(1);
          Alcotest.(check int64) "aeskeygenassist lane0" 0x3424B5E524B5E434L v3.(0);
          Alcotest.(check int64) "aeskeygenassist lane1" 0x01EB848BEB848A01L v3.(1);
          Alcotest.(check int64) "vaesenc lane2 zeroed" 0L v11.(2);
          Alcotest.(check int64) "vaesenc lane3 zeroed" 0L v11.(3);
          Alcotest.(check int64) "aesenc mem lane0" 0x2B359F68F27F9CA4L v12.(0);
          Alcotest.(check int64) "aesenc mem lane1" 0x49506A0243EA5B6BL v12.(1))

let test_x86_lift_aes_ni_fips197_full_cycle () =
  let asm = {|
func_aes_full_cycle:
    pxor xmm0, xmm1
    aesenc xmm0, xmm2
    aesenc xmm0, xmm3
    aesenc xmm0, xmm4
    aesenc xmm0, xmm5
    aesenc xmm0, xmm6
    aesenc xmm0, xmm7
    aesenc xmm0, xmm8
    aesenc xmm0, xmm9
    aesenc xmm0, xmm10
    aesenclast xmm0, xmm11
    movaps xmm12, xmm0
    aesimc xmm2, xmm2
    aesimc xmm3, xmm3
    aesimc xmm4, xmm4
    aesimc xmm5, xmm5
    aesimc xmm6, xmm6
    aesimc xmm7, xmm7
    aesimc xmm8, xmm8
    aesimc xmm9, xmm9
    aesimc xmm10, xmm10
    pxor xmm12, xmm11
    aesdec xmm12, xmm10
    aesdec xmm12, xmm9
    aesdec xmm12, xmm8
    aesdec xmm12, xmm7
    aesdec xmm12, xmm6
    aesdec xmm12, xmm5
    aesdec xmm12, xmm4
    aesdec xmm12, xmm3
    aesdec xmm12, xmm2
    aesdeclast xmm12, xmm1
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let state = make_state () in
      (* Plaintext *)
      Hashtbl.replace state.vectors 0 [| 0x8D305A88A8F64332L; 0x340737E0A2983131L; 0L; 0L; 0L; 0L; 0L; 0L |];
      (* Round keys 0..10 *)
      Hashtbl.replace state.vectors 1 [| 0xA6D2AE2816157E2BL; 0x3C4FCF098815F7ABL; 0L; 0L; 0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 2 [| 0xB12C548817FEFAA0L; 0x05766C2A3939A323L; 0L; 0L; 0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 3 [| 0x43B9967AF295C2F2L; 0x7FF659737A803559L; 0L; 0L; 0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 4 [| 0x3EFE16477D47803DL; 0x3B887A6D447E231EL; 0L; 0L; 0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 5 [| 0x7F5B52A841A544EFL; 0x00AD0BDB3B2571B6L; 0L; 0L; 0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 6 [| 0x879D837CF8C6D1D4L; 0xBC15F911BCB8F2CAL; 0L; 0L; 0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 7 [| 0xFD3E0B117AA3886DL; 0xFD9300CA4186F9DBL; 0L; 0L; 0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 8 [| 0xF3C95F5F0EF7544EL; 0x4FDCA64EB24FA684L; 0L; 0L; 0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 9 [| 0xD2BA8DB52173D2EAL; 0x2F298D7F60F52B31L; 0L; 0L; 0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 10 [| 0x21DCFA19F36677ACL; 0x6E005C574129D128L; 0L; 0L; 0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 11 [| 0x8925EEC9A8F914D0L; 0xA60C63B6C80C3FE1L; 0L; 0L; 0L; 0L; 0L; 0L |];
      (match run_func state func with
      | Error e -> Alcotest.fail e
      | Ok () ->
          let v0 = Hashtbl.find state.vectors 0 in
          let v12 = Hashtbl.find state.vectors 12 in
          let v2 = Hashtbl.find state.vectors 2 in
          let v10 = Hashtbl.find state.vectors 10 in
          (* Encrypted ciphertext must match NIST FIPS-197 *)
          Alcotest.(check int64) "full cipher ct lane0" 0xFB09DC021D842539L v0.(0);
          Alcotest.(check int64) "full cipher ct lane1" 0x320B6A19978511DCL v0.(1);
          (* Decrypted plaintext must match original plaintext *)
          Alcotest.(check int64) "full cipher pt lane0" 0x8D305A88A8F64332L v12.(0);
          Alcotest.(check int64) "full cipher pt lane1" 0x340737E0A2983131L v12.(1);
          (* Inverted round keys *)
          Alcotest.(check int64) "dec key 1 lane0" 0x05D462F2A708372BL v2.(0);
          Alcotest.(check int64) "dec key 1 lane1" 0x627D614BBFBD3EBCL v2.(1);
          Alcotest.(check int64) "dec key 9 lane0" 0xFEEA1913635A7B0CL v10.(0);
          Alcotest.(check int64) "dec key 9 lane1" 0xB4FB4C66908839B0L v10.(1))

let test_x86_lift_shufps_shufpd () =
  let asm = {|
func_shuf:
    vshufps xmm4, xmm0, xmm1, 0xD8
    vshufpd xmm5, xmm2, xmm3, 0x01
    shufps xmm0, xmm1, 0xD8
    shufpd xmm2, xmm3, 0x01
    shufps xmm6, xmmword ptr [rsp + 16], 0xD8
    vshufps ymm7, ymm8, ymm9, 0xD8
    vshufpd ymm10, ymm11, ymm12, 0x05
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let state = make_state () in
      state.vsp <- 0x1000L;
      write_mem state 0x1010L B64 0x0000000600000005L;
      write_mem state 0x1018L B64 0x0000000800000007L;
      (* xmm0, xmm1 for shufps *)
      Hashtbl.replace state.vectors 0 [| 0x0000000200000001L; 0x0000000400000003L; 0L; 0L; 0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 1 [| 0x0000000600000005L; 0x0000000800000007L; 0L; 0L; 0L; 0L; 0L; 0L |];
      (* xmm2, xmm3 for shufpd *)
      Hashtbl.replace state.vectors 2 [| 0x1111111111111111L; 0x2222222222222222L; 0L; 0L; 0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 3 [| 0x3333333333333333L; 0x4444444444444444L; 0L; 0L; 0L; 0L; 0L; 0L |];
      (* xmm4, xmm5 pre-filled with upper junk to verify zeroing *)
      Hashtbl.replace state.vectors 4 [| 0L; 0L; 0xDEADBEEFCAFEBABEL; 0xDEADBEEFCAFEBABEL; 0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 5 [| 0L; 0L; 0xDEADBEEFCAFEBABEL; 0xDEADBEEFCAFEBABEL; 0L; 0L; 0L; 0L |];
      (* xmm6 for mem shufps *)
      Hashtbl.replace state.vectors 6 [| 0x0000000200000001L; 0x0000000400000003L; 0L; 0L; 0L; 0L; 0L; 0L |];
      (* ymm8, ymm9 for 256-bit vshufps *)
      Hashtbl.replace state.vectors 8 [| 0x0000000200000001L; 0x0000000400000003L; 0x0000000B0000000AL; 0x0000000D0000000CL; 0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 9 [| 0x0000000600000005L; 0x0000000800000007L; 0x0000000F0000000EL; 0x0000001100000010L; 0L; 0L; 0L; 0L |];
      (* ymm11, ymm12 for 256-bit vshufpd *)
      Hashtbl.replace state.vectors 11 [| 0x1111111111111111L; 0x2222222222222222L; 0x5555555555555555L; 0x6666666666666666L; 0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 12 [| 0x3333333333333333L; 0x4444444444444444L; 0x7777777777777777L; 0x8888888888888888L; 0L; 0L; 0L; 0L |];
      (match run_func state func with
      | Error e -> Alcotest.fail e
      | Ok () ->
          let v0 = Hashtbl.find state.vectors 0 in
          let v2 = Hashtbl.find state.vectors 2 in
          let v4 = Hashtbl.find state.vectors 4 in
          let v5 = Hashtbl.find state.vectors 5 in
          let v6 = Hashtbl.find state.vectors 6 in
          let v7 = Hashtbl.find state.vectors 7 in
          let v10 = Hashtbl.find state.vectors 10 in
          (* shufps xmm0, xmm1, 0xD8 -> [1, 3, 6, 8] *)
          Alcotest.(check int64) "shufps lane0" 0x0000000300000001L v0.(0);
          Alcotest.(check int64) "shufps lane1" 0x0000000800000006L v0.(1);
          (* shufpd xmm2, xmm3, 0x01 -> [xmm2[1], xmm3[0]] *)
          Alcotest.(check int64) "shufpd lane0" 0x2222222222222222L v2.(0);
          Alcotest.(check int64) "shufpd lane1" 0x3333333333333333L v2.(1);
          (* vshufps zeroing *)
          Alcotest.(check int64) "vshufps lane2 zeroed" 0L v4.(2);
          Alcotest.(check int64) "vshufps lane3 zeroed" 0L v4.(3);
          (* vshufpd zeroing *)
          Alcotest.(check int64) "vshufpd lane0" 0x2222222222222222L v5.(0);
          Alcotest.(check int64) "vshufpd lane1" 0x3333333333333333L v5.(1);
          Alcotest.(check int64) "vshufpd lane2 zeroed" 0L v5.(2);
          Alcotest.(check int64) "vshufpd lane3 zeroed" 0L v5.(3);
          (* shufps with memory *)
          Alcotest.(check int64) "shufps mem lane0" 0x0000000300000001L v6.(0);
          Alcotest.(check int64) "shufps mem lane1" 0x0000000800000006L v6.(1);
          (* 256-bit vshufps *)
          Alcotest.(check int64) "vshufps 256 lane0" 0x0000000300000001L v7.(0);
          Alcotest.(check int64) "vshufps 256 lane1" 0x0000000800000006L v7.(1);
          Alcotest.(check int64) "vshufps 256 lane2" 0x0000000C0000000AL v7.(2);
          Alcotest.(check int64) "vshufps 256 lane3" 0x000000110000000FL v7.(3);
          (* 256-bit vshufpd imm8=0x05 (0b0101): blk0: [1, 0]->[0x2222, 0x3333]; blk1: [1, 0]->[0x6666, 0x7777] *)
          Alcotest.(check int64) "vshufpd 256 lane0" 0x2222222222222222L v10.(0);
          Alcotest.(check int64) "vshufpd 256 lane1" 0x3333333333333333L v10.(1);
          Alcotest.(check int64) "vshufpd 256 lane2" 0x6666666666666666L v10.(2);
          Alcotest.(check int64) "vshufpd 256 lane3" 0x7777777777777777L v10.(3))

let test_x86_lift_packed_conversions () =
  let asm = {|
func_packed_conv:
    cvtps2pd xmm0, xmm1
    cvtpd2ps xmm2, xmm3
    cvtdq2ps xmm4, xmm5
    cvtps2dq xmm6, xmm7
    cvttps2dq xmm8, xmm7
    cvtdq2pd xmm9, xmm10
    cvtpd2dq xmm11, xmm12
    cvttpd2dq xmm13, xmm12
    vcvtps2pd ymm14, xmm1
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let state = make_state () in
      (* xmm1: floats 1.5, -2.5 (lower 64 bits) *)
      Hashtbl.replace state.vectors 1 [| 0xC02000003FC00000L; 0L; 0L; 0L; 0L; 0L; 0L; 0L |];
      (* xmm3: doubles 3.25, -4.75 *)
      Hashtbl.replace state.vectors 3 [| 0x400A000000000000L; 0xC013000000000000L; 0L; 0L; 0L; 0L; 0L; 0L |];
      (* xmm5: ints 10, -20, 1000, -50000 *)
      Hashtbl.replace state.vectors 5 [| 0xFFFFFFEC0000000AL; 0xFFFF3CB0000003E8L; 0L; 0L; 0L; 0L; 0L; 0L |];
      (* xmm7: floats 1.2, 1.8, -1.8, -1.2 *)
      Hashtbl.replace state.vectors 7 [| 0x3FE666663F99999AL; 0xBF99999ABFE66666L; 0L; 0L; 0L; 0L; 0L; 0L |];
      (* xmm10: ints 42, -99 *)
      Hashtbl.replace state.vectors 10 [| 0xFFFFFF9D0000002AL; 0L; 0L; 0L; 0L; 0L; 0L; 0L |];
      (* xmm12: doubles 42.7, -99.8 *)
      Hashtbl.replace state.vectors 12 [| 0x404559999999999AL; 0xC058F33333333333L; 0L; 0L; 0L; 0L; 0L; 0L |];
      (match run_func state func with
      | Error e -> Alcotest.fail e
      | Ok () ->
          let v0 = Hashtbl.find state.vectors 0 in
          let v2 = Hashtbl.find state.vectors 2 in
          let v4 = Hashtbl.find state.vectors 4 in
          let v6 = Hashtbl.find state.vectors 6 in
          let v8 = Hashtbl.find state.vectors 8 in
          let v9 = Hashtbl.find state.vectors 9 in
          let v11 = Hashtbl.find state.vectors 11 in
          let v13 = Hashtbl.find state.vectors 13 in
          let v14 = Hashtbl.find state.vectors 14 in
          (* cvtps2pd xmm0, xmm1 -> doubles 1.5, -2.5 *)
          Alcotest.(check int64) "cvtps2pd d0" 0x3FF8000000000000L v0.(0);
          Alcotest.(check int64) "cvtps2pd d1" 0xC004000000000000L v0.(1);
          (* cvtpd2ps xmm2, xmm3 -> floats 3.25, -4.75; upper zeroed *)
          Alcotest.(check int64) "cvtpd2ps f0f1" 0xC098000040500000L v2.(0);
          Alcotest.(check int64) "cvtpd2ps upper zero" 0L v2.(1);
          (* cvtdq2ps xmm4, xmm5 -> floats 10.0, -20.0, 1000.0, -50000.0 *)
          Alcotest.(check int64) "cvtdq2ps f0f1" 0xC1A0000041200000L v4.(0);
          Alcotest.(check int64) "cvtdq2ps f2f3" 0xC7435000447A0000L v4.(1);
          (* cvtps2dq xmm6, xmm7 (round nearest even) -> 1, 2, -2, -1 *)
          Alcotest.(check int64) "cvtps2dq i0i1" 0x0000000200000001L v6.(0);
          Alcotest.(check int64) "cvtps2dq i2i3" 0xFFFFFFFF00000000L (Int64.logand v6.(1) 0xFFFFFFFF00000000L);
          Alcotest.(check int64) "cvtps2dq i2" (-2L) (Int64.of_int32 (Int64.to_int32 v6.(1)));
          (* cvttps2dq xmm8, xmm7 (truncate) -> 1, 1, -1, -1 *)
          Alcotest.(check int64) "cvttps2dq i0i1" 0x0000000100000001L v8.(0);
          Alcotest.(check int64) "cvttps2dq i2" (-1L) (Int64.of_int32 (Int64.to_int32 v8.(1)));
          (* cvtdq2pd xmm9, xmm10 -> doubles 42.0, -99.0 *)
          Alcotest.(check int64) "cvtdq2pd d0" 0x4045000000000000L v9.(0);
          Alcotest.(check int64) "cvtdq2pd d1" 0xC058C00000000000L v9.(1);
          (* cvtpd2dq xmm11, xmm12 -> ints 43, -100; upper zeroed *)
          Alcotest.(check int64) "cvtpd2dq i0" 43L (Int64.logand v11.(0) 0xFFFFFFFFL);
          Alcotest.(check int64) "cvtpd2dq i1" (-100L) (Int64.of_int32 (Int64.to_int32 (Int64.shift_right_logical v11.(0) 32)));
          Alcotest.(check int64) "cvtpd2dq upper zero" 0L v11.(1);
          (* cvttpd2dq xmm13, xmm12 -> ints 42, -99; upper zeroed *)
          Alcotest.(check int64) "cvttpd2dq i0" 42L (Int64.logand v13.(0) 0xFFFFFFFFL);
          Alcotest.(check int64) "cvttpd2dq i1" (-99L) (Int64.of_int32 (Int64.to_int32 (Int64.shift_right_logical v13.(0) 32)));
          Alcotest.(check int64) "cvttpd2dq upper zero" 0L v13.(1);
          (* 256-bit vcvtps2pd ymm14, xmm1 *)
          Alcotest.(check int64) "vcvtps2pd d0" 0x3FF8000000000000L v14.(0);
          Alcotest.(check int64) "vcvtps2pd d1" 0xC004000000000000L v14.(1))

let test_x86_lift_movlhps_movhlps_movlps_movhps () =
  let asm = {|
func_subvector_moves:
    vmovlhps xmm4, xmm0, xmm1
    vmovhlps xmm5, xmm2, xmm3
    movlhps xmm0, xmm1
    movhlps xmm2, xmm3
    movlps xmm6, qword ptr [rsp + 16]
    movlps qword ptr [rsp + 24], xmm6
    movhps xmm7, qword ptr [rsp + 16]
    movhps qword ptr [rsp + 32], xmm7
    vmovlps xmm8, xmm0, qword ptr [rsp + 16]
    vmovhps xmm9, xmm0, qword ptr [rsp + 16]
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let state = make_state () in
      state.vsp <- 0x1000L;
      write_mem state 0x1010L B64 0x1234567890ABCDEFL;
      (* xmm0: [0x1111..., 0x2222...] *)
      Hashtbl.replace state.vectors 0 [| 0x1111111111111111L; 0x2222222222222222L; 0L; 0L; 0L; 0L; 0L; 0L |];
      (* xmm1: [0x3333..., 0x4444...] *)
      Hashtbl.replace state.vectors 1 [| 0x3333333333333333L; 0x4444444444444444L; 0L; 0L; 0L; 0L; 0L; 0L |];
      (* xmm2: [0x5555..., 0x6666...] *)
      Hashtbl.replace state.vectors 2 [| 0x5555555555555555L; 0x6666666666666666L; 0L; 0L; 0L; 0L; 0L; 0L |];
      (* xmm3: [0x7777..., 0x8888...] *)
      Hashtbl.replace state.vectors 3 [| 0x7777777777777777L; 0x8888888888888888L; 0L; 0L; 0L; 0L; 0L; 0L |];
      (* xmm4, xmm5: upper junk *)
      Hashtbl.replace state.vectors 4 [| 0L; 0L; 0xDEADBEEFCAFEBABEL; 0xDEADBEEFCAFEBABEL; 0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 5 [| 0L; 0L; 0xDEADBEEFCAFEBABEL; 0xDEADBEEFCAFEBABEL; 0L; 0L; 0L; 0L |];
      (* xmm6, xmm7: [0xAAAA..., 0xBBBB...] *)
      Hashtbl.replace state.vectors 6 [| 0xAAAAAAAAAAAAAAAA_L; 0xBBBBBBBBBBBBBBBB_L; 0L; 0L; 0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 7 [| 0xAAAAAAAAAAAAAAAA_L; 0xBBBBBBBBBBBBBBBB_L; 0L; 0L; 0L; 0L; 0L; 0L |];
      (match run_func state func with
      | Error e -> Alcotest.fail e
      | Ok () ->
          let v0 = Hashtbl.find state.vectors 0 in
          let v2 = Hashtbl.find state.vectors 2 in
          let v4 = Hashtbl.find state.vectors 4 in
          let v5 = Hashtbl.find state.vectors 5 in
          let v6 = Hashtbl.find state.vectors 6 in
          let v7 = Hashtbl.find state.vectors 7 in
          let v8 = Hashtbl.find state.vectors 8 in
          let v9 = Hashtbl.find state.vectors 9 in
          (* movlhps xmm0, xmm1 -> [xmm0[0], xmm1[0]] *)
          Alcotest.(check int64) "movlhps l0" 0x1111111111111111L v0.(0);
          Alcotest.(check int64) "movlhps l1" 0x3333333333333333L v0.(1);
          (* movhlps xmm2, xmm3 -> [xmm3[1], xmm2[1]] *)
          Alcotest.(check int64) "movhlps l0" 0x8888888888888888L v2.(0);
          Alcotest.(check int64) "movhlps l1" 0x6666666666666666L v2.(1);
          (* vmovlhps xmm4 *)
          Alcotest.(check int64) "vmovlhps l0" 0x1111111111111111L v4.(0);
          Alcotest.(check int64) "vmovlhps l1" 0x3333333333333333L v4.(1);
          Alcotest.(check int64) "vmovlhps l2 zero" 0L v4.(2);
          Alcotest.(check int64) "vmovlhps l3 zero" 0L v4.(3);
          (* vmovhlps xmm5 *)
          Alcotest.(check int64) "vmovhlps l0" 0x8888888888888888L v5.(0);
          Alcotest.(check int64) "vmovhlps l1" 0x6666666666666666L v5.(1);
          Alcotest.(check int64) "vmovhlps l2 zero" 0L v5.(2);
          Alcotest.(check int64) "vmovhlps l3 zero" 0L v5.(3);
          (* movlps load xmm6 -> [mem, xmm6[1]] *)
          Alcotest.(check int64) "movlps load l0" 0x1234567890ABCDEFL v6.(0);
          Alcotest.(check int64) "movlps load l1" 0xBBBBBBBBBBBBBBBB_L v6.(1);
          (* movlps store to rsp + 24 *)
          Alcotest.(check int64) "movlps store mem" 0x1234567890ABCDEFL (read_mem state 0x1018L B64);
          (* movhps load xmm7 -> [xmm7[0], mem] *)
          Alcotest.(check int64) "movhps load l0" 0xAAAAAAAAAAAAAAAA_L v7.(0);
          Alcotest.(check int64) "movhps load l1" 0x1234567890ABCDEFL v7.(1);
          (* movhps store to rsp + 32 *)
          Alcotest.(check int64) "movhps store mem" 0x1234567890ABCDEFL (read_mem state 0x1020L B64);
          (* vmovlps xmm8 *)
          Alcotest.(check int64) "vmovlps l0" 0x1234567890ABCDEFL v8.(0);
          Alcotest.(check int64) "vmovlps l1" 0x3333333333333333L v8.(1);
          Alcotest.(check int64) "vmovlps l2 zero" 0L v8.(2);
          (* vmovhps xmm9 *)
          Alcotest.(check int64) "vmovhps l0" 0x1111111111111111L v9.(0);
          Alcotest.(check int64) "vmovhps l1" 0x1234567890ABCDEFL v9.(1);
          Alcotest.(check int64) "vmovhps l2 zero" 0L v9.(2))

let test_x86_lift_system_and_compiler_traps () =
  (* 1. endbr64 and endbr32 *)
  let asm_endbr = {|
func_endbr:
    endbr64
    endbr32
    mov rax, 42
    ret
|} in
  (match Lifter.lift_function asm_endbr with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let state = make_state () in
      (match run_func state func with
      | Error e -> Alcotest.fail e
      | Ok () ->
          Alcotest.(check int64) "endbr pass rax" 42L (get_reg state Register.rax)));
  (* 2. ud2 unreachable trap *)
  let asm_ud2 = {|
func_ud2:
    mov rax, 10
    ud2
    mov rax, 20
    ret
|} in
  (match Lifter.lift_function asm_ud2 with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let state = make_state () in
      (match run_func state func with
      | Error msg ->
          Alcotest.(check string) "ud2 trapped" "VM Trapped: ud2" msg;
          Alcotest.(check int64) "ud2 stopped before rax=20" 10L (get_reg state Register.rax)
      | Ok () -> Alcotest.fail "ud2 should have trapped"));
  (* 3. int3 breakpoint trap *)
  let asm_int3 = {|
func_int3:
    int3
    ret
|} in
  (match Lifter.lift_function asm_int3 with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let state = make_state () in
      (match run_func state func with
      | Error msg -> Alcotest.(check string) "int3 trapped" "VM Trapped: int3" msg
      | Ok () -> Alcotest.fail "int3 should have trapped"));
  (* 4. int 0x80 syscall interrupt *)
  let asm_int80 = {|
func_int80:
    int 0x80
    ret
|} in
  (match Lifter.lift_function asm_int80 with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let state = make_state () in
      (match run_func state func with
      | Error msg -> Alcotest.(check string) "int 128 trapped" "VM Trapped: int 128" msg
      | Ok () -> Alcotest.fail "int 128 should have trapped"));
  (* 5. hlt instruction *)
  let asm_hlt = {|
func_hlt:
    hlt
    ret
|} in
  (match Lifter.lift_function asm_hlt with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let state = make_state () in
      (match run_func state func with
      | Error msg -> Alcotest.(check string) "hlt trapped" "VM Trapped: hlt" msg
      | Ok () -> Alcotest.fail "hlt should have trapped"))

let test_x86_lift_bmi () =
  let asm = {|
func_bmi:
    mov rdi, 0xFF00FF00
    mov rsi, 0x0F0F0F0F
    andn rax, rdi, rsi
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let state = make_state () in
      match run_func state func with
      | Error e -> Alcotest.fail e
      | Ok () ->
          Alcotest.(check int64) "andn result" 0x000F000FL (get_reg state Register.rax)

let test_x86_lift_shld_shrd () =
  let asm = {|
func_shld_shrd:
    mov rax, 0x1234567890ABCDEF
    mov rdx, 0xFEDCBA0987654321
    shld rax, rdx, 16
    mov [rsp - 8], rax
    mov r8, rax

    mov rax, 0x1234567890ABCDEF
    shrd rax, rdx, 16
    mov r9, rax

    # test count 0 preserving dest
    mov rax, 0x1234567890ABCDEF
    shld rax, rdx, 0
    mov r10, rax
    shrd rax, rdx, 0
    mov r11, rax

    # test mem dest
    mov rax, 0x1234567890ABCDEF
    mov [rsp - 16], rax
    shld [rsp - 16], rdx, 16
    mov r12, [rsp - 16]

    mov rax, 0x1234567890ABCDEF
    mov [rsp - 24], rax
    shrd [rsp - 24], rdx, 16
    mov r13, [rsp - 24]

    # test mem dest with count 0
    mov rax, 0x1234567890ABCDEF
    mov [rsp - 32], rax
    shld [rsp - 32], rdx, 0
    mov r14, [rsp - 32]

    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let state = make_state () in
      set_reg state Register.rsp 0x2000L;
      match run_func state func with
      | Error e -> Alcotest.fail e
      | Ok () ->
          Alcotest.(check int64) "shld 16 bits reg" 0x567890ABCDEFFEDCL (get_reg state Register.r8);
          Alcotest.(check int64) "shrd 16 bits reg" 0x43211234567890ABL (get_reg state Register.r9);
          Alcotest.(check int64) "shld 0 bits reg unchanged" 0x1234567890ABCDEFL (get_reg state Register.r10);
          Alcotest.(check int64) "shrd 0 bits reg unchanged" 0x1234567890ABCDEFL (get_reg state Register.r11);
          Alcotest.(check int64) "shld 16 bits mem" 0x567890ABCDEFFEDCL (get_reg state Register.r12);
          Alcotest.(check int64) "shrd 16 bits mem" 0x43211234567890ABL (get_reg state Register.r13);
          Alcotest.(check int64) "shld 0 bits mem unchanged" 0x1234567890ABCDEFL (get_reg state Register.r14)

let test_x86_lift_cdq_dirty_upper_rax () =
  let asm = {|
func_cdq_dirty:
    mov rax, 0x1234567800000005
    cdq
    mov r8, rdx
    mov rax, 0x1234567880000000
    cdq
    mov r9, rdx
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let state = make_state () in
      match run_func state func with
      | Error e -> Alcotest.fail e
      | Ok () ->
          Alcotest.(check int64) "cdq positive bit 31 clears rdx" 0L (get_reg state Register.r8);
          Alcotest.(check int64) "cdq negative bit 31 sign-extends rdx to -1" (-1L) (get_reg state Register.r9)

let test_x86_lift_movbe () =
  let asm = {|
func_movbe:
    mov [rsp - 8], rdi
    movbe rax, [rsp - 8]
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let state = make_state () in
      set_reg state Register.rdi 0x123456789ABCDEF0L;
      set_reg state Register.rsp 0x1000L;
      match run_func state func with
      | Error e -> Alcotest.fail e
      | Ok () ->
          Alcotest.(check int64) "movbe byteswapped" (-1090226688147180526L) (get_reg state Register.rax)

(* The bit-scan family: BLSR (BMI1) computes (SRC - 1) & SRC and so clears
   the lowest set bit of the source, BSF and BSR return the index of the
   lowest and the highest set bit, LZCNT and TZCNT count the leading and the
   trailing zeros.  BSF and BSR keep the destination when the source is
   zero.  The expected values and flags are the ones the hardware produces:
   the same programs were assembled and executed on an x86-64 machine. *)
let test_x86_lift_bit_scan_family () =
  let run asm src =
    match Lifter.lift_function asm with
    | Error e -> Alcotest.fail e
    | Ok func ->
        let state = make_state () in
        set_reg state Register.rax src;
        (match run_func state func with
        | Error e -> Alcotest.fail e
        | Ok () -> state)
  in
  let zf state = Flags.compute_zf state.flags in
  let cf state = Flags.compute_cf state.flags in
  (* BLSR: the lowest set bit of the source is cleared *)
  let s = run {|
func_blsr:
    blsr rbx, rax
    ret
|} 0xDEADBEEFDEADBEEFL in
  Alcotest.(check int64) "blsr clears the lowest set bit" 0xDEADBEEFDEADBEEEL (get_reg s Register.rbx);
  Alcotest.(check bool) "blsr ZF = 0" false (zf s);
  Alcotest.(check bool) "blsr CF = 0" false (cf s);
  let s = run {|
func_blsr_zero:
    blsr rbx, rax
    ret
|} 0L in
  Alcotest.(check int64) "blsr of zero is zero" 0L (get_reg s Register.rbx);
  Alcotest.(check bool) "blsr of zero sets ZF" true (zf s);
  Alcotest.(check bool) "blsr of zero sets CF" true (cf s);
  (* BLSR of a single bit gives zero *)
  let s = run {|
func_blsr_one:
    blsr rbx, rax
    ret
|} 0x8000000000000000L in
  Alcotest.(check int64) "blsr of a single high bit is zero" 0L (get_reg s Register.rbx);
  Alcotest.(check bool) "blsr of a single high bit sets ZF" true (zf s);
  Alcotest.(check bool) "blsr of a single high bit clears CF" false (cf s);
  (* BSR: the index of the highest set bit *)
  let s = run {|
func_bsr:
    bsr rcx, rax
    ret
|} 0x100000000L in
  Alcotest.(check int64) "bsr of 1<<32 is 32" 32L (get_reg s Register.rcx);
  Alcotest.(check bool) "bsr ZF = 0" false (zf s);
  let s = run {|
func_bsr_high:
    bsr rcx, rax
    ret
|} 0xDEADBEEFDEADBEEFL in
  Alcotest.(check int64) "bsr of 0xDEADBEEFDEADBEEF is 63" 63L (get_reg s Register.rcx);
  (* BSF: the index of the lowest set bit *)
  let s = run {|
func_bsf:
    bsf rdx, rax
    ret
|} 0x100000000L in
  Alcotest.(check int64) "bsf of 1<<32 is 32" 32L (get_reg s Register.rdx);
  Alcotest.(check bool) "bsf ZF = 0" false (zf s);
  (* BSF and BSR keep the destination when the source is zero *)
  let s = run {|
func_bsf_zero:
    mov rdx, 0x1122334455667788
    bsf rdx, rax
    ret
|} 0L in
  Alcotest.(check int64) "bsf of zero keeps the destination" 0x1122334455667788L (get_reg s Register.rdx);
  Alcotest.(check bool) "bsf of zero sets ZF" true (zf s);
  let s = run {|
func_bsr_zero:
    mov rcx, 0x1122334455667788
    bsr rcx, rax
    ret
|} 0L in
  Alcotest.(check int64) "bsr of zero keeps the destination" 0x1122334455667788L (get_reg s Register.rcx);
  Alcotest.(check bool) "bsr of zero sets ZF" true (zf s);
  (* LZCNT and TZCNT always write the destination *)
  let s = run {|
func_lzcnt:
    lzcnt rsi, rax
    ret
|} 0L in
  Alcotest.(check int64) "lzcnt of zero is 64" 64L (get_reg s Register.rsi);
  Alcotest.(check bool) "lzcnt of zero clears ZF" false (zf s);
  Alcotest.(check bool) "lzcnt of zero sets CF" true (cf s);
  let s = run {|
func_lzcnt_top:
    lzcnt rsi, rax
    ret
|} 0x8000000000000000L in
  Alcotest.(check int64) "lzcnt of 1<<63 is 0" 0L (get_reg s Register.rsi);
  Alcotest.(check bool) "lzcnt of 1<<63 sets ZF" true (zf s);
  Alcotest.(check bool) "lzcnt of 1<<63 clears CF" false (cf s);
  let s = run {|
func_tzcnt:
    tzcnt rdi, rax
    ret
|} 0L in
  Alcotest.(check int64) "tzcnt of zero is 64" 64L (get_reg s Register.rdi);
  Alcotest.(check bool) "tzcnt of zero clears ZF" false (zf s);
  Alcotest.(check bool) "tzcnt of zero sets CF" true (cf s);
  let s = run {|
func_tzcnt_bit:
    tzcnt rdi, rax
    ret
|} 0x100000000L in
  Alcotest.(check int64) "tzcnt of 1<<32 is 32" 32L (get_reg s Register.rdi);
  Alcotest.(check bool) "tzcnt of 1<<32 clears ZF" false (zf s);
  Alcotest.(check bool) "tzcnt of 1<<32 clears CF" false (cf s)

(* The sign-extension family: CBW and CWDE extend the low part of RAX, and
   CWD, CDQ and CQO build the high half of the dividend in RDX.  The expected
   values are the ones the hardware produces; the same programs were
   assembled and executed on an x86-64 machine. *)
let test_x86_lift_sign_extension_family () =
  let run asm =
    match Lifter.lift_function asm with
    | Error e -> Alcotest.fail e
    | Ok func ->
        let state = make_state () in
        (match run_func state func with
        | Error e -> Alcotest.fail e
        | Ok () -> state)
  in
  let s = run {|
func_cbw:
    mov rax, 0x12345678000000FF
    cbw
    ret
|} in
  Alcotest.(check int64) "cbw sign-extends AL into AX" 0x123456780000FFFFL (get_reg s Register.rax);
  let s = run {|
func_cwde:
    mov rax, 0x123456780000FFFF
    cwde
    ret
|} in
  Alcotest.(check int64) "cwde sign-extends AX into EAX" 0xFFFFFFFFL (get_reg s Register.rax);
  let s = run {|
func_cwtl:
    mov rax, 0x123456780000FFFF
    cwtl
    ret
|} in
  Alcotest.(check int64) "cwtl is the AT&T spelling of cwde" 0xFFFFFFFFL (get_reg s Register.rax);
  let s = run {|
func_cdqe:
    mov rax, 0x12345678FFFFFFFF
    cdqe
    ret
|} in
  Alcotest.(check int64) "cdqe sign-extends EAX into RAX" (-1L) (get_reg s Register.rax);
  let s = run {|
func_cqto:
    mov rax, 0x123456789ABCDEF0
    cqto
    mov rbx, rdx
    ret
|} in
  Alcotest.(check int64) "cqto sign-extends RAX into RDX" 0L (get_reg s Register.rbx);
  let s = run {|
func_cwtd:
    mov rax, 0x1234567800000005
    cwtd
    mov rbx, rdx
    ret
|} in
  Alcotest.(check int64) "cwtd is the AT&T spelling of cdq" 0L (get_reg s Register.rbx)

(* The x86 SHA extensions (SHA-NI).  Every instruction works on the four
   32-bit words of a 128-bit vector register; the destination is both a source
   and the destination, and SHA256RNDS2 takes its round constants from the
   implicit XMM0.  The expected values follow the Intel SDM. *)
let test_x86_lift_sha_ni () =
  let asm = {|
func_sha_ni:
    sha1rnds4 xmm3, xmm4, 0x0
    sha1nexte xmm5, xmm6
    sha1msg1 xmm7, xmm8
    sha1msg2 xmm9, xmm10
    sha256rnds2 xmm11, xmm12
    sha256msg1 xmm13, xmm14
    sha256msg2 xmm15, xmm16
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let state = make_state () in
      (* the SHA-1 state (A, B, C, D) and the source words *)
      let state_words = [| 0x89ABCDEF01234567L; 0x76543210FEDCBA98L |] in
      let src_words = [| 0x2222222211111111L; 0x4444444433333333L |] in
      List.iter (fun reg -> Hashtbl.replace state.vectors reg state_words) [ 3; 5; 7; 9; 11; 13; 15 ];
      List.iter (fun reg -> Hashtbl.replace state.vectors reg src_words) [ 4; 6; 8; 10; 12; 14; 16 ];
      (* the two SHA-256 round constants of the implicit XMM0 *)
      Hashtbl.replace state.vectors 0 [| 0x0BADF00DCAFEBABEL; 0L |];
      (match run_func state func with
      | Error e -> Alcotest.fail e
      | Ok () ->
          let words reg =
            let lanes = Hashtbl.find state.vectors reg in
            let w i =
              Int64.logand (Int64.shift_right_logical lanes.(i / 2) (32 * (i mod 2))) 0xFFFFFFFFL
            in
            [| w 0; w 1; w 2; w 3 |]
          in
          let check name reg expected =
            let got = words reg in
            Array.iteri
              (fun i e ->
                Alcotest.(check int64) (Printf.sprintf "%s word %d" name i) e got.(i))
              expected
          in
          check "sha1rnds4" 3 [| 0xFA700561L; 0x0FBEFBB6L; 0xF3458385L; 0xA3B63C88L |];
          check "sha1nexte" 5 [| 0xD159E26AL; 0x22222222L; 0x33333333L; 0x44444444L |];
          check "sha1msg1" 7 [| 0xFFFFFFFFL; 0xFFFFFFFFL; 0xEFCDAB89L; 0x54761032L |];
          check "sha1msg2" 9 [| 0x4602CE8AL; 0x7531FDB9L; 0x7531FDB9L; 0x60ADF934L |];
          check "sha256rnds2" 11 [| 0xC1C9B1D2L; 0xCAFE3234L; 0x64E9BCB2L; 0xCAFE7678L |];
          check "sha256msg1" 13 [| 0x0FEEEDC8L; 0x20FDBA9BL; 0xF0111236L; 0x89ABCDEFL |];
          check "sha256msg2" 15 [| 0x54320FEDL; 0xEDCBA986L; 0xDBA986C3L; 0xCFE19A0CL |])

(* PCLMULQDQ computes the carry-less product of two 64-bit halves of a
   128-bit vector register, and the CET instructions RDSSP and INCSSP move
   the shadow stack pointer. *)
let test_x86_lift_pclmul_cet () =
  let asm = {|
func_pclmul_cet:
    pclmulqdq xmm3, xmm4, 0x00
    pclmulqdq xmm5, xmm6, 0x11
    rdsspq rax
    rdsspd ecx
    incsspq
    incsspd
    rdsspq rdx
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let state = make_state () in
      let set_lanes reg l0 l1 = Hashtbl.replace state.vectors reg [| l0; l1 |] in
      set_lanes 3 0x0123456789ABCDEFL 0xFEDCBA9876543210L;
      set_lanes 4 0x1111111111111111L 0x2222222222222222L;
      set_lanes 5 0x0123456789ABCDEFL 0xFEDCBA9876543210L;
      set_lanes 6 0x1111111111111111L 0x2222222222222222L;
      (match run_func state func with
      | Error e -> Alcotest.fail e
      | Ok () ->
          let lanes reg = Hashtbl.find state.vectors reg in
          Alcotest.(check int64) "pclmulqdq 0x00 low half" 0x00130417081B0C1FL (lanes 3).(0);
          Alcotest.(check int64) "pclmulqdq 0x00 high half" 0x00130417081B0C1FL (lanes 3).(1);
          Alcotest.(check int64) "pclmulqdq 0x11 low half" 0x1E3816300E280620L (lanes 5).(0);
          Alcotest.(check int64) "pclmulqdq 0x11 keeps the high half" 0xFEDCBA9876543210L (lanes 5).(1);
          Alcotest.(check int64) "rdsspq reads the shadow stack pointer" 0x50000000L
            (get_reg state Register.rax);
          Alcotest.(check int64) "rdsspd reads the low half" 0x50000000L
            (get_reg state Register.rcx);
          Alcotest.(check int64) "incsspq and incsspd grow the shadow stack" 0x50000050L
            (get_reg state Register.rdx))

let test_x86_lift_adc_sbb () =
  let asm = {|
func_adc_sbb:
    mov rax, -1
    add rax, 1
    mov rbx, 10
    adc rbx, 20
    mov rcx, 10
    sub rcx, 15
    mov rdx, 20
    sbb rdx, 10
    mov rax, rbx
    add rax, rdx
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let state = make_state () in
      match run_func state func with
      | Error e -> Alcotest.fail e
      | Ok () ->
          Alcotest.(check int64) "adc and sbb with carry = 40" 40L (get_reg state Register.rax)

let test_x86_lift_lahf_sahf () =
  let asm = {|
func_lahf_sahf:
    xor rax, rax
    cmp rax, 0
    lahf
    mov rbx, rax
    mov rax, 1
    cmp rax, 0
    mov rax, rbx
    sahf
    sete al
    movzx rax, al
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let state = make_state () in
      match run_func state func with
      | Error e -> Alcotest.fail e
      | Ok () ->
          Alcotest.(check int64) "lahf and sahf preserve ZF=1" 1L (get_reg state Register.rax)

let test_x86_lift_cmpxchg () =
  let asm = {|
test_cmpxchg:
    mov rax, 42
    mov rbx, 42
    mov rcx, 100
    cmpxchg rbx, rcx
    mov r8, rbx
    mov r9, 0
    setz r9b

    mov rax, 10
    mov rbx, 20
    mov rcx, 30
    cmpxchg rbx, rcx
    mov r10, rax
    mov r11, rbx
    mov r12, 0
    setnz r12b

    mov qword ptr [rsp - 16], 55
    mov rax, 55
    mov rdx, 77
    cmpxchg qword ptr [rsp - 16], rdx
    mov r13, qword ptr [rsp - 16]
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let state = make_state () in
      match run_func state func with
      | Error e -> Alcotest.fail e
      | Ok () ->
          Alcotest.(check int64) "cmpxchg equal dst updated" 100L (get_reg state Register.r8);
          Alcotest.(check int64) "cmpxchg equal ZF=1" 1L (get_reg state Register.r9);
          Alcotest.(check int64) "cmpxchg not-equal rax updated" 20L (get_reg state Register.r10);
          Alcotest.(check int64) "cmpxchg not-equal dst unchanged" 20L (get_reg state Register.r11);
          Alcotest.(check int64) "cmpxchg not-equal ZF=0" 1L (get_reg state Register.r12);
          Alcotest.(check int64) "cmpxchg mem updated" 77L (get_reg state Register.r13)

let test_x86_lift_xadd () =
  let asm = {|
test_xadd:
    mov rax, 15
    mov rbx, 25
    xadd rax, rbx

    mov qword ptr [rsp - 16], 50
    mov rcx, 30
    xadd qword ptr [rsp - 16], rcx
    mov rdx, qword ptr [rsp - 16]
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let state = make_state () in
      match run_func state func with
      | Error e -> Alcotest.fail e
      | Ok () ->
          Alcotest.(check int64) "xadd reg sum in dst" 40L (get_reg state Register.rax);
          Alcotest.(check int64) "xadd reg old in src" 15L (get_reg state Register.rbx);
          Alcotest.(check int64) "xadd mem old in src" 50L (get_reg state Register.rcx);
          Alcotest.(check int64) "xadd mem sum in mem" 80L (get_reg state Register.rdx)

let test_x86_lift_xadd_same_reg () =
  let asm = {|
test_xadd_same:
    mov rax, 21
    xadd rax, rax
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let state = make_state () in
      match run_func state func with
      | Error e -> Alcotest.fail e
      | Ok () ->
          Alcotest.(check int64) "xadd rax rax doubles rax" 42L (get_reg state Register.rax)

let test_x86_lift_verified_alu_simulation () =
  let asm = {|
test_sim:
    mov rax, 100
    mov rbx, 35
    add rax, rbx
    sub rax, 15
    xor rax, 0x55
    and rax, 0xFF
    or  rax, 0x100
    not rax
    neg rax
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let state = make_state () in
      match run_func state func with
      | Error e -> Alcotest.fail e
      | Ok () ->
          Alcotest.(check int64) "alu simulation matches composite semantics" 302L (get_reg state Register.rax)

let test_x86_lift_xlat () =
  let asm = {|
test_xlat:
    mov byte ptr [rsp - 32], 10
    mov byte ptr [rsp - 31], 20
    mov byte ptr [rsp - 30], 30
    lea rbx, [rsp - 32]
    mov rax, 0x1122334455667702
    xlatb
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let state = make_state () in
      match run_func state func with
      | Error e -> Alcotest.fail e
      | Ok () ->
          Alcotest.(check int64) "xlatb loads table entry into AL" 0x112233445566771eL (get_reg state Register.rax)

let test_x86_lift_string_ops () =
  let asm = {|
string_test:
    sub rsp, 32
    lea rdi, [rsp]
    mov rax, 0x1122334455667788
    stosq
    lea rsi, [rsp]
    xor rax, rax
    lodsq
    lea rdi, [rsp + 16]
    lea rsi, [rsp]
    movsq
    mov r8, [rsp + 16]
    add rsp, 32
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let state = make_state () in
      match run_func state func with
      | Error e -> Alcotest.fail e
      | Ok () ->
          Alcotest.(check int64) "lodsq & movsq roundtrip" 0x1122334455667788L (get_reg state Register.rax);
          Alcotest.(check int64) "movsq copied value" 0x1122334455667788L (get_reg state Register.r8)

let test_x86_lift_bit_tests () =
  let asm = {|
bit_test:
    xor rax, rax
    xor rcx, rcx
    bts rax, 3
    bt rax, 3
    setc cl
    bts rax, 5
    btc rax, 3
    btr rax, 5
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let state = make_state () in
      match run_func state func with
      | Error e -> Alcotest.fail e
      | Ok () ->
          Alcotest.(check int64) "bts/btc/btr bit test ops" 0L (get_reg state Register.rax);
          Alcotest.(check int64) "bt sets CF correctly" 1L (get_reg state Register.rcx)

let test_x86_lift_pext_pdep () =
  let asm = {|
bmi2_pext_pdep:
    mov rdi, 0xB2
    mov rsi, 0xF0
    pext rax, rdi, rsi
    mov rdx, 11
    pdep rcx, rdx, rsi
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let state = make_state () in
      match run_func state func with
      | Error e -> Alcotest.fail e
      | Ok () ->
          Alcotest.(check int64) "pext 0xB2 with mask 0xF0 = 11" 11L (get_reg state Register.rax);
          Alcotest.(check int64) "pdep 11 with mask 0xF0 = 0xB0 (176)" 176L (get_reg state Register.rcx)

let test_x86_fp_sqrt_and_cvt () =
  let asm = {|
func_fpsqrt:
    mov rdi, 64
    cvtsi2sd xmm0, rdi
    sqrtsd xmm1, xmm0
    cvtsd2ss xmm2, xmm1
    cvtss2sd xmm3, xmm2
    cvttsd2si rax, xmm3
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let state = make_state () in
      match run_func state func with
      | Error e -> Alcotest.fail e
      | Ok () ->
          Alcotest.(check int64) "sqrt(64) = 8" 8L (get_reg state Register.rax)

let test_x86_rcl_rcr_cmc () =
  let asm = {|
func_rcl_rcr:
    clc
    mov rax, 1
    cmc
    rcl rax, 1
    rcr rax, 1
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let state = make_state () in
      match run_func state func with
      | Error e -> Alcotest.fail e
      | Ok () ->
          Alcotest.(check int64) "rcl followed by rcr restores rax" 1L (get_reg state Register.rax)

let test_x86_rep_stosb () =
  let asm = {|
func_rep_stosb:
    sub rsp, 32
    lea rdi, [rsp]
    mov al, 0x5a
    mov rcx, 8
    rep stosb
    mov rax, qword ptr [rsp]
    add rsp, 32
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let state = make_state () in
      set_reg state Register.rsp 0x1000L;
      match run_func state func with
      | Error e -> Alcotest.fail e
      | Ok () ->
          Alcotest.(check int64) "rep stosb fills 8 bytes" 0x5a5a5a5a5a5a5a5aL (get_reg state Register.rax);
          Alcotest.(check int64) "rcx is 0 after rep" 0L (get_reg state Register.rcx);
          Alcotest.(check int64) "rdi advanced by 8" 0x0fe8L (get_reg state Register.rdi)

let test_x86_rep_movsb () =
  let asm = {|
func_rep_movsb:
    sub rsp, 64
    mov qword ptr [rsp], 0x1122334455667788
    lea rsi, [rsp]
    lea rdi, [rsp + 32]
    mov rcx, 8
    rep movsb
    mov rax, qword ptr [rsp + 32]
    add rsp, 64
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let state = make_state () in
      set_reg state Register.rsp 0x1000L;
      match run_func state func with
      | Error e -> Alcotest.fail e
      | Ok () ->
          Alcotest.(check int64) "rep movsb copies 8 bytes" 0x1122334455667788L (get_reg state Register.rax);
          Alcotest.(check int64) "rcx is 0 after rep" 0L (get_reg state Register.rcx)

let test_x86_repne_scasb () =
  let asm = {|
func_repne_scasb:
    sub rsp, 32
    mov byte ptr [rsp], 0x41
    mov byte ptr [rsp + 1], 0x42
    mov byte ptr [rsp + 2], 0x43
    mov byte ptr [rsp + 3], 0x00
    lea rdi, [rsp]
    xor al, al
    mov rcx, 10
    repne scasb
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let state = make_state () in
      set_reg state Register.rsp 0x1000L;
      match run_func state func with
      | Error e -> Alcotest.fail e
      | Ok () ->
          Alcotest.(check int64) "rcx decremented by 4" 6L (get_reg state Register.rcx);
          Alcotest.(check int64) "rdi stopped after null byte" 0x0fe4L (get_reg state Register.rdi)

let test_x86_repe_cmpsb () =
  let asm = {|
func_repe_cmpsb:
    sub rsp, 32
    mov byte ptr [rsp], 0x10
    mov byte ptr [rsp + 1], 0x20
    mov byte ptr [rsp + 2], 0x99
    mov byte ptr [rsp + 16], 0x10
    mov byte ptr [rsp + 17], 0x20
    mov byte ptr [rsp + 18], 0x88
    lea rsi, [rsp]
    lea rdi, [rsp + 16]
    mov rcx, 5
    repe cmpsb
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let state = make_state () in
      set_reg state Register.rsp 0x1000L;
      match run_func state func with
      | Error e -> Alcotest.fail e
      | Ok () ->
          Alcotest.(check int64) "repe stops on mismatch at rcx=2" 2L (get_reg state Register.rcx)

let test_x86_cmpxchg8b () =
  let asm = {|
func_cmpxchg8b:
    sub rsp, 32
    mov dword ptr [rsp], 0x11111111
    mov dword ptr [rsp + 4], 0x22222222
    mov eax, 0x11111111
    mov edx, 0x22222222
    mov ebx, 0x33333333
    mov ecx, 0x44444444
    cmpxchg8b qword ptr [rsp]
    mov r8, qword ptr [rsp]
    add rsp, 32
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let state = make_state () in
      set_reg state Register.rsp 0x1000L;
      match run_func state func with
      | Error e -> Alcotest.fail e
      | Ok () ->
          Alcotest.(check int64) "cmpxchg8b match stores ecx:ebx" 0x4444444433333333L (get_reg state (Register.Gpr (Register.R8, Register.B64)))

let test_x86_cmpxchg16b () =
  let asm = {|
func_cmpxchg16b:
    sub rsp, 64
    mov qword ptr [rsp], 0x1234
    mov qword ptr [rsp + 8], 0x5678
    mov rax, 0x1234
    mov rdx, 0x5678
    mov rbx, 0xAAAA
    mov rcx, 0xBBBB
    cmpxchg16b [rsp]
    mov r8, qword ptr [rsp]
    mov r9, qword ptr [rsp + 8]
    add rsp, 64
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let state = make_state () in
      set_reg state Register.rsp 0x1000L;
      match run_func state func with
      | Error e -> Alcotest.fail e
      | Ok () ->
          Alcotest.(check int64) "cmpxchg16b low word becomes rbx" 0xAAAAL (get_reg state (Register.Gpr (Register.R8, Register.B64)));
          Alcotest.(check int64) "cmpxchg16b high word becomes rcx" 0xBBBBL (get_reg state (Register.Gpr (Register.R9, Register.B64)))

let contains_sub s sub =
  let len_s = String.length s in
  let len_sub = String.length sub in
  if len_sub > len_s then false
  else
    let rec check i =
      if i + len_sub > len_s then false
      else if String.sub s i len_sub = sub then true
      else check (i + 1)
    in
    check 0

let test_x86_avx256_arithmetic () =
  let asm = {|
func_avx256:
    vpaddd ymm0, ymm1, ymm2
    vpxor ymm3, ymm1, ymm2
    vpsubd ymm4, ymm1, ymm2
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let state = make_state () in
      let ymm1 = [|
        Int64.logor 1L (Int64.shift_left 2L 32);
        Int64.logor 3L (Int64.shift_left 4L 32);
        Int64.logor 5L (Int64.shift_left 6L 32);
        Int64.logor 7L (Int64.shift_left 8L 32);
        0L; 0L; 0L; 0L
      |] in
      let ymm2 = [|
        Int64.logor 10L (Int64.shift_left 20L 32);
        Int64.logor 30L (Int64.shift_left 40L 32);
        Int64.logor 50L (Int64.shift_left 60L 32);
        Int64.logor 70L (Int64.shift_left 80L 32);
        0L; 0L; 0L; 0L
      |] in
      Hashtbl.replace state.vectors 1 ymm1;
      Hashtbl.replace state.vectors 2 ymm2;
      (match run_func state func with
      | Error e -> Alcotest.fail e
      | Ok () ->
          let ymm0 = Hashtbl.find state.vectors 0 in
          let ymm3 = Hashtbl.find state.vectors 3 in
          let ymm4 = Hashtbl.find state.vectors 4 in
          Alcotest.(check int64) "vpaddd chunk 0" (Int64.logor 11L (Int64.shift_left 22L 32)) ymm0.(0);
          Alcotest.(check int64) "vpaddd chunk 1" (Int64.logor 33L (Int64.shift_left 44L 32)) ymm0.(1);
          Alcotest.(check int64) "vpaddd chunk 2" (Int64.logor 55L (Int64.shift_left 66L 32)) ymm0.(2);
          Alcotest.(check int64) "vpaddd chunk 3" (Int64.logor 77L (Int64.shift_left 88L 32)) ymm0.(3);
          Alcotest.(check int64) "vpxor chunk 0" (Int64.logxor ymm1.(0) ymm2.(0)) ymm3.(0);
          Alcotest.(check int64) "vpxor chunk 2" (Int64.logxor ymm1.(2) ymm2.(2)) ymm3.(2);
          let sub_dw a b = Int64.logand (Int64.sub a b) 0xFFFFFFFFL in
          let exp_sub_c0 = Int64.logor (sub_dw 1L 10L) (Int64.shift_left (sub_dw 2L 20L) 32) in
          Alcotest.(check int64) "vpsubd chunk 0" exp_sub_c0 ymm4.(0))

let test_x86_avx_shifts_minmax_abs () =
  let asm = {|
func_avx_ops:
    vpslld ymm0, ymm1, 2
    vpminud ymm2, ymm1, ymm3
    vpabsd ymm4, ymm5
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let state = make_state () in
      let ymm1 = [|
        Int64.logor 10L (Int64.shift_left 20L 32);
        Int64.logor 30L (Int64.shift_left 40L 32);
        Int64.logor 50L (Int64.shift_left 60L 32);
        Int64.logor 70L (Int64.shift_left 80L 32);
        0L; 0L; 0L; 0L
      |] in
      let ymm3 = [|
        Int64.logor 5L (Int64.shift_left 25L 32);
        Int64.logor 35L (Int64.shift_left 15L 32);
        Int64.logor 55L (Int64.shift_left 45L 32);
        Int64.logor 75L (Int64.shift_left 65L 32);
        0L; 0L; 0L; 0L
      |] in
      let ymm5 = [|
        Int64.logor 0xFFFFFFD6L (Int64.shift_left 100L 32);
        0L; 0L; 0L; 0L; 0L; 0L; 0L
      |] in
      Hashtbl.replace state.vectors 1 ymm1;
      Hashtbl.replace state.vectors 3 ymm3;
      Hashtbl.replace state.vectors 5 ymm5;
      (match run_func state func with
      | Error e -> Alcotest.fail e
      | Ok () ->
          let ymm0 = Hashtbl.find state.vectors 0 in
          let ymm2 = Hashtbl.find state.vectors 2 in
          let ymm4 = Hashtbl.find state.vectors 4 in
          Alcotest.(check int64) "vpslld chunk 0" (Int64.logor 40L (Int64.shift_left 80L 32)) ymm0.(0);
          Alcotest.(check int64) "vpminud chunk 0" (Int64.logor 5L (Int64.shift_left 20L 32)) ymm2.(0);
          Alcotest.(check int64) "vpabsd chunk 0" (Int64.logor 42L (Int64.shift_left 100L 32)) ymm4.(0))

let test_x86_avx_upper_zeroing () =
  let asm = {|
func_upper_zero:
    vpaddd xmm0, xmm1, xmm2
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let state = make_state () in
      Hashtbl.replace state.vectors 0 [| 999L; 999L; 0xDEADBEEFL; 0xCAFEBABEL; 0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 1 [| 10L; 20L; 0L; 0L; 0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 2 [| 5L; 15L; 0L; 0L; 0L; 0L; 0L; 0L |];
      (match run_func state func with
      | Error e -> Alcotest.fail e
      | Ok () ->
          let ymm0 = Hashtbl.find state.vectors 0 in
          Alcotest.(check int64) "vpaddd 128 low lane 0" 15L (Int64.logand ymm0.(0) 0xFFFFFFFFL);
          Alcotest.(check int64) "upper chunk 2 zeroed" 0L ymm0.(2);
          Alcotest.(check int64) "upper chunk 3 zeroed" 0L ymm0.(3))

let test_x86_vzeroupper () =
  let asm = {|
func_vzero:
    vzeroupper
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let state = make_state () in
      Hashtbl.replace state.vectors 0 [| 1L; 2L; 3L; 4L; 0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 7 [| 10L; 20L; 30L; 40L; 0L; 0L; 0L; 0L |];
      (match run_func state func with
      | Error e -> Alcotest.fail e
      | Ok () ->
          let ymm0 = Hashtbl.find state.vectors 0 in
          let ymm7 = Hashtbl.find state.vectors 7 in
          Alcotest.(check int64) "ymm0 chunk 0 intact" 1L ymm0.(0);
          Alcotest.(check int64) "ymm0 chunk 1 intact" 2L ymm0.(1);
          Alcotest.(check int64) "ymm0 chunk 2 zeroed" 0L ymm0.(2);
          Alcotest.(check int64) "ymm0 chunk 3 zeroed" 0L ymm0.(3);
          Alcotest.(check int64) "ymm7 chunk 2 zeroed" 0L ymm7.(2);
          Alcotest.(check int64) "ymm7 chunk 3 zeroed" 0L ymm7.(3))

let test_x86_pmovmskb () =
  let asm = {|
func_pmov:
    pmovmskb eax, xmm1
    vpmovmskb ebx, ymm2
    movmskps ecx, xmm3
    vmovmskps r8d, ymm4
    movmskpd edx, xmm5
    vmovmskpd r9d, ymm6
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let state = make_state () in
      Hashtbl.replace state.vectors 1 [| 0x8000000000000080L; 0x8000000000000000L; 0L; 0L; 0L; 0L; 0L; 0L |];
      Hashtbl.replace state.vectors 2 [| 0x80L; 0L; 0L; 0x8000000000000000L; 0L; 0L; 0L; 0L |];
      (* lane0 sign at bit31 = 0, lane1 sign at bit63 = 1, lane2/3 = 0 *)
      Hashtbl.replace state.vectors 3 [| 0x8000000000000000L; 0L; 0L; 0L; 0L; 0L; 0L; 0L |];
      (* 256-bit, 32-bit lanes: lane1 (bit 63 of chunk 0) and lane5 (bit 63 of chunk 2) signed *)
      Hashtbl.replace state.vectors 4 [| 0x8000000000000000L; 0L; 0x8000000000000000L; 0L; 0L; 0L; 0L; 0L |];
      (* 64-bit lanes: lane0 sign=1, lane1 sign=0 *)
      Hashtbl.replace state.vectors 5 [| 0x8000000000000000L; 0L; 0L; 0L; 0L; 0L; 0L; 0L |];
      (* 256-bit, 64-bit lanes: lane1 and lane3 signed *)
      Hashtbl.replace state.vectors 6 [| 0L; 0x8000000000000000L; 0L; 0x8000000000000000L; 0L; 0L; 0L; 0L |];
      (match run_func state func with
      | Error e -> Alcotest.fail e
      | Ok () ->
          Alcotest.(check int64) "pmovmskb eax" 0x8081L (get_reg state (Register.Gpr (Register.RAX, Register.B32)));
          Alcotest.(check int64) "vpmovmskb ebx" 0x80000001L (get_reg state (Register.Gpr (Register.RBX, Register.B32)));
          Alcotest.(check int64) "movmskps ecx" 0x2L (get_reg state (Register.Gpr (Register.RCX, Register.B32)));
          Alcotest.(check int64) "vmovmskps r8d" 0x22L (get_reg state (Register.Gpr (Register.R8, Register.B32)));
          Alcotest.(check int64) "movmskpd edx" 0x1L (get_reg state (Register.Gpr (Register.RDX, Register.B32)));
          Alcotest.(check int64) "vmovmskpd r9d" 0xAL (get_reg state (Register.Gpr (Register.R9, Register.B32))))

let test_x86_unpck_fp () =
  let asm = {|
func_unpck:
    unpcklps xmm1, xmm2
    unpckhps xmm3, xmm4
    unpcklpd xmm5, xmm6
    unpckhpd xmm7, xmm8
    vunpcklpd xmm10, xmm5, xmm2
    vunpcklps ymm9, ymm1, ymm2
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->

      let state = make_state () in
      let setv i c0 c1 c2 c3 = Hashtbl.replace state.vectors i [| c0; c1; c2; c3; 0L; 0L; 0L; 0L |] in
      setv 1 0x2222222211111111L 0x4444444433333333L 0xAAAAAAAABBBBBBBBL 0L;
      setv 2 0x6666666655555555L 0x8888888877777777L 0xDDDDDDDDCCCCCCCCL 0L;
      setv 3 0x2222222211111111L 0x4444444433333333L 0L 0L;
      setv 4 0x6666666655555555L 0x8888888877777777L 0L 0L;
      setv 5 0x2222222211111111L 0x4444444433333333L 0L 0L;
      setv 6 0x6666666655555555L 0x8888888877777777L 0L 0L;
      setv 7 0x2222222211111111L 0x4444444433333333L 0L 0L;
      setv 8 0x6666666655555555L 0x8888888877777777L 0L 0L;
      setv 10 0L 0L 0xDEADBEEFCAFEBABEL 0xFEEDFACE12345678L;
      (match run_func state func with
      | Error e -> Alcotest.fail e
      | Ok () ->
          let vec i = Hashtbl.find state.vectors i in
          (* unpcklps: [d0, s0, d1, s1] *)
          Alcotest.(check int64) "unpcklps lo" 0x5555555511111111L (vec 1).(0);
          Alcotest.(check int64) "unpcklps hi" 0x6666666622222222L (vec 1).(1);
          (* unpckhps: [d2, s2, d3, s3] *)
          Alcotest.(check int64) "unpckhps lo" 0x7777777733333333L (vec 3).(0);
          Alcotest.(check int64) "unpckhps hi" 0x8888888844444444L (vec 3).(1);
          (* unpcklpd: [D0, S0] *)
          Alcotest.(check int64) "unpcklpd lo" 0x2222222211111111L (vec 5).(0);
          Alcotest.(check int64) "unpcklpd hi" 0x6666666655555555L (vec 5).(1);
          (* unpckhpd: [D1, S1] *)
          Alcotest.(check int64) "unpckhpd lo" 0x4444444433333333L (vec 7).(0);
          Alcotest.(check int64) "unpckhpd hi" 0x8888888877777777L (vec 7).(1);
          (* vunpcklps ymm: per-128-bit block [d,s,d,s] *)
          Alcotest.(check int64) "vunpcklps b0" 0x5555555511111111L (vec 9).(0);
          Alcotest.(check int64) "vunpcklps b1" 0x6666666655555555L (vec 9).(1);
          Alcotest.(check int64) "vunpcklps b2" 0xCCCCCCCCBBBBBBBBL (vec 9).(2);
          Alcotest.(check int64) "vunpcklps b3" 0xDDDDDDDDAAAAAAAAL (vec 9).(3);
          (* vunpcklpd xmm (VEX-128): result plus zeroed upper half *)
          Alcotest.(check int64) "vunpcklpd lo" 0x2222222211111111L (vec 10).(0);
          Alcotest.(check int64) "vunpcklpd hi" 0x6666666655555555L (vec 10).(1);
          Alcotest.(check int64) "vunpcklpd upper zeroed" 0L (vec 10).(2);
          Alcotest.(check int64) "vunpcklpd upper zeroed 2" 0L (vec 10).(3))

(* PTEST (SSE4.1) and VPTEST (AVX) do a bitwise test of two vector registers:
   ZF is set when (SRC1 AND SRC2) is zero, CF is set when (SRC2 ANDNOT SRC1)
   is zero, and no other flag is touched.  The expected values were taken
   from a real x86-64 machine (the same programs were run under Rosetta). *)
let test_x86_ptest () =
  let all = -1L in
  let run asm a b =
    match Lifter.lift_function asm with
    | Error e -> Alcotest.fail e
    | Ok func ->
        let state = make_state () in
        Hashtbl.replace state.vectors 1 (Array.append a [| 0L; 0L; 0L; 0L |]);
        Hashtbl.replace state.vectors 2 (Array.append b [| 0L; 0L; 0L; 0L |]);
        (match run_func state func with
        | Error e -> Alcotest.fail e
        | Ok () -> state)
  in
  let zf state = Flags.compute_zf state.flags in
  let cf state = Flags.compute_cf state.flags in
  let lo x = [| x; 0L; 0L; 0L |] in
  let ptest_asm = {|
func_ptest:
    ptest xmm1, xmm2
    ret
|} in
  let vptest_asm = {|
func_vptest:
    vptest ymm1, ymm2
    ret
|} in
  let s = run ptest_asm (lo 0L) (lo 0L) in
  Alcotest.(check bool) "ptest 0/0 sets ZF" true (zf s);
  Alcotest.(check bool) "ptest 0/0 sets CF" true (cf s);
  let s = run ptest_asm (lo all) (lo 0L) in
  Alcotest.(check bool) "ptest all/0 sets ZF" true (zf s);
  Alcotest.(check bool) "ptest all/0 sets CF" true (cf s);
  let s = run ptest_asm (lo 0L) (lo all) in
  Alcotest.(check bool) "ptest 0/all sets ZF" true (zf s);
  Alcotest.(check bool) "ptest 0/all clears CF" false (cf s);
  let s = run ptest_asm (lo all) (lo all) in
  Alcotest.(check bool) "ptest all/all clears ZF" false (zf s);
  Alcotest.(check bool) "ptest all/all sets CF" true (cf s);
  let s = run ptest_asm (lo 0xF0L) (lo 0x0FL) in
  Alcotest.(check bool) "ptest 0xF0/0x0F sets ZF" true (zf s);
  Alcotest.(check bool) "ptest 0xF0/0x0F clears CF" false (cf s);
  let s = run ptest_asm (lo 0xFFL) (lo 0x0FL) in
  Alcotest.(check bool) "ptest 0xFF/0x0F clears ZF" false (zf s);
  Alcotest.(check bool) "ptest 0xFF/0x0F sets CF" true (cf s);
  let s = run ptest_asm (lo 0x0FL) (lo 0xFFL) in
  Alcotest.(check bool) "ptest 0x0F/0xFF clears ZF" false (zf s);
  Alcotest.(check bool) "ptest 0x0F/0xFF clears CF" false (cf s);
  (* the 128-bit form looks at the low 128 bits only: the upper halves
     differ, but the low halves give ZF = 1 and CF = 1 *)
  let s = run ptest_asm [| all; 0L; 0L; 0L |] [| 0L; 0L; all; all |] in
  Alcotest.(check bool) "ptest xmm ignores the upper half (ZF)" true (zf s);
  Alcotest.(check bool) "ptest xmm ignores the upper half (CF)" true (cf s);
  (* the 256-bit form looks at all 256 bits: the same vectors now give
     ZF = 1 and CF = 0 *)
  let s = run vptest_asm [| all; 0L; 0L; 0L |] [| 0L; 0L; all; all |] in
  Alcotest.(check bool) "vptest sees the upper half (ZF)" true (zf s);
  Alcotest.(check bool) "vptest sees the upper half (CF)" false (cf s);
  let s = run vptest_asm [| 0xFFFFFFFFL; 0L; all; all |] [| 0L; 0L; all; all |] in
  Alcotest.(check bool) "vptest common bits only in the upper half clears ZF" false (zf s);
  Alcotest.(check bool) "vptest common bits only in the upper half sets CF" true (cf s);
  let s = run vptest_asm [| 0xFFFFFFFFL; 0L; 0L; 0L |] [| 0xFFFFFFFFL; 0L; all; all |] in
  Alcotest.(check bool) "vptest differing bits only in the upper half clears ZF" false (zf s);
  Alcotest.(check bool) "vptest differing bits only in the upper half clears CF" false (cf s)

let test_x86_evex_zmm_trap () =
  let asm = {|
func_evex:
    vpaddd zmm0, zmm1, zmm2
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let state = make_state () in
      match run_func state func with
      | Error msg ->
          Alcotest.(check bool) "trapped with evex message" true (contains_sub msg "AVX-512 EVEX is unsupported")
      | Ok () ->
          Alcotest.fail "Expected AVX-512 EVEX trap but execution succeeded"

let test_x86_tls_fs_gs_segment_prefixes () =
  let asm = {|
tls_test:
    mov rax, qword ptr fs:[0x28]
    mov rbx, qword ptr gs:[0x30]
    xor rdx, rdx
    cmp rax, 0xCAFEBABE13375877
    jne mismatch
    mov rdx, 1
mismatch:
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let state = make_state () in
      write_mem state 0x70000030L Register.B64 0x123456789ABCDEF0L;
      match run_func state func with
      | Error e -> Alcotest.fail e
      | Ok () ->
          Alcotest.(check int64) "fs:[0x28] canary matches default" 0xCAFEBABE13375877L (get_reg state Register.rax);
          Alcotest.(check int64) "gs:[0x30] loaded correctly" 0x123456789ABCDEF0L (get_reg state Register.rbx);
          Alcotest.(check int64) "canary check passed" 1L (get_reg state Register.rdx)

let test_x86_tls_native_vm_canonicalize () =
  let m = { Ir.base = None; index = None; disp = 0x28L; width = Register.B64; is_signed = false; segment = Some Ir.FS } in
  let instr = Ir.Mov { dst = Ir.Reg Register.rax; src = Ir.Mem m } in
  let canon = Native_vm.Vm_transform.canonicalize_instr instr in
  match canon with
  | [ Ir.Mov { dst = Ir.Reg d; src = Ir.Mem m_canon } ] ->
      Alcotest.(check string) "dst is rax" (Register.to_string Register.rax) (Register.to_string d);
      Alcotest.(check bool) "base is vfs_base" true (m_canon.base = Some Register.vfs_base);
      Alcotest.(check bool) "segment cleared" true (m_canon.segment = None);
      Alcotest.(check int64) "disp preserved" 0x28L m_canon.disp
  | _ -> Alcotest.fail "Unexpected canonicalization for fs:[0x28] load"

let test_x86_moffs_memory () =
  let asm = {|
moffs_test:
    mov al, byte ptr [0x1000]
    mov [0x1008], al
    mov ecx, dword ptr [0x1000]
    mov [0x1010], ecx
    mov rdx, [0x1000]
    mov [0x1018], rdx
    mov r8b, ds:[0x1000]
    mov r9b, ds:0x1001
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let state = make_state () in
      write_mem state 0x1000L Register.B64 0x0102030405060708L;
      match run_func state func with
      | Error e -> Alcotest.fail e
      | Ok () ->
          Alcotest.(check int64) "al loaded 0x08" 0x08L (get_reg state (Register.Gpr (Register.RAX, Register.B8)));
          Alcotest.(check int64) "mem 0x1008 has 0x08" 0x08L (read_mem state 0x1008L Register.B8);
          Alcotest.(check int64) "ecx loaded 0x05060708" 0x05060708L (get_reg state (Register.Gpr (Register.RCX, Register.B32)));
          Alcotest.(check int64) "mem 0x1010 has 0x05060708" 0x05060708L (read_mem state 0x1010L Register.B32);
          Alcotest.(check int64) "rdx loaded full 64-bit" 0x0102030405060708L (get_reg state Register.rdx);
          Alcotest.(check int64) "mem 0x1018 has full 64-bit" 0x0102030405060708L (read_mem state 0x1018L Register.B64);
          Alcotest.(check int64) "r8b ds:[0x1000] loaded" 0x08L (get_reg state (Register.Gpr (Register.R8, Register.B8)));
          Alcotest.(check int64) "r9b ds:0x1001 loaded" 0x07L (get_reg state (Register.Gpr (Register.R9, Register.B8)))

let test_x86_segment_registers_push_pop_mov () =
  let asm = {|
seg_test:
    mov ax, 0x1234
    mov ds, ax
    mov es, ax
    push ds
    push es
    push fs
    push gs
    pop gs
    pop fs
    pop es
    pop ds
    mov bx, ds
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let state = make_state () in
      match run_func state func with
      | Error e -> Alcotest.fail e
      | Ok () ->
          Alcotest.(check int64) "bx loaded from ds" 0x1234L (get_reg state (Register.Gpr (Register.RBX, Register.B16)));
          let invalid_asm = {|
bad_cs:
    pop cs
    ret
|} in
          (match Lifter.lift_function invalid_asm with
          | Error msg ->
              Alcotest.(check bool) "pop cs rejected" true (contains_sub msg "pop cs is an invalid")
          | Ok _ -> Alcotest.fail "Expected pop cs to be rejected");
          let invalid_mov_cs = {|
bad_mov_cs:
    mov cs, ax
    ret
|} in
          (match Lifter.lift_function invalid_mov_cs with
          | Error msg ->
              Alcotest.(check bool) "mov cs rejected" true (contains_sub msg "mov cs is an invalid")
          | Ok _ -> Alcotest.fail "Expected mov cs to be rejected")

let test_x86_fsbase_gsbase_rdfsbase_wrfsbase () =
  let asm = {|
base_test:
    rdfsbase rax
    rdgsbase rbx
    mov rdi, 0x1122334455667788
    wrfsbase rdi
    mov rsi, 0x8877665544332211
    wrgsbase rsi
    rdfsbase r8
    rdgsbase r9
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let state = make_state () in
      match run_func state func with
      | Error e -> Alcotest.fail e
      | Ok () ->
          Alcotest.(check int64) "initial fs_base" 0x60000000L (get_reg state Register.rax);
          Alcotest.(check int64) "initial gs_base" 0x70000000L (get_reg state Register.rbx);
          Alcotest.(check int64) "updated fs_base" 0x1122334455667788L (get_reg state Register.r8);
          Alcotest.(check int64) "updated gs_base" 0x8877665544332211L (get_reg state Register.r9)

let test_x86_lift_atomic_rmw_and_lock () =
  let asm = {|
func_atomic_rmw:
    mov qword ptr [rsp - 16], 100
    lock add qword ptr [rsp - 16], 25
    lock sub qword ptr [rsp - 16], 10
    lock inc qword ptr [rsp - 16]
    lock dec qword ptr [rsp - 16]
    mov rax, qword ptr [rsp - 16]
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let state = make_state () in
      match run_func state func with
      | Error e -> Alcotest.fail e
      | Ok () ->
          (* 100 + 25 - 10 + 1 - 1 = 115 *)
          Alcotest.(check int64) "lock rmw 100+25-10+1-1=115" 115L (get_reg state Register.rax)

let test_x86_lift_atomic_mem_nodes () =
  let asm = {|
func_atomic_nodes:
    lock add qword ptr [rdi], 42
    lock sub qword ptr [rdi], 12
    lock inc qword ptr [rdi]
    xchg qword ptr [rdi], rsi
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let b0 = Hashtbl.find func.cfg.blocks 0 in
      let atomic_count = List.fold_left (fun acc -> function
        | Ir.Atomic_mem _ -> acc + 1
        | _ -> acc
      ) 0 b0.instrs in
      Alcotest.(check bool) "emits Atomic_mem for locked/memory RMW" true (atomic_count >= 4)

let test_x86_cpuid () =
  let run asm in_rax in_rcx =
    match Lifter.lift_function asm with
    | Error e -> Alcotest.fail e
    | Ok func ->
        let state = make_state () in
        set_reg state Register.rax in_rax;
        set_reg state Register.rcx in_rcx;
        match run_func state func with
        | Error e -> Alcotest.fail e
        | Ok () -> state
  in
  (* Leaf 0: Vendor String & Maximum Basic Leaf *)
  let s0 = run {|
func_cpuid_0:
    mov eax, 0
    cpuid
    ret
|} 0L 0L in
  Alcotest.(check int64) "cpuid leaf 0: EAX = max basic leaf (0x16)" 0x16L (get_reg s0 Register.rax);
  Alcotest.(check int64) "cpuid leaf 0: EBX = 'Genu' (0x756e6547)" 0x756e6547L (get_reg s0 Register.rbx);
  Alcotest.(check int64) "cpuid leaf 0: EDX = 'ineI' (0x49656e69)" 0x49656e69L (get_reg s0 Register.rdx);
  Alcotest.(check int64) "cpuid leaf 0: ECX = 'ntel' (0x6c65746e)" 0x6c65746eL (get_reg s0 Register.rcx);

  (* Leaf 1: Processor Signature & Standard Feature Flags *)
  let s1 = run {|
func_cpuid_1:
    mov eax, 1
    cpuid
    ret
|} 0L 0L in
  Alcotest.(check int64) "cpuid leaf 1: EAX = signature" 0x000906E9L (get_reg s1 Register.rax);
  Alcotest.(check int64) "cpuid leaf 1: EBX = brand/apic" 0x00080800L (get_reg s1 Register.rbx);
  Alcotest.(check int64) "cpuid leaf 1: ECX = features" 0x7FFAFBEFL (get_reg s1 Register.rcx);
  Alcotest.(check int64) "cpuid leaf 1: EDX = features" 0xBFEBFBFFL (get_reg s1 Register.rdx);

  (* Leaf 7: Structured Extended Features *)
  let s7 = run {|
func_cpuid_7:
    mov eax, 7
    xor ecx, ecx
    cpuid
    ret
|} 0L 0L in
  Alcotest.(check int64) "cpuid leaf 7: EBX extended features" 0x209C01A9L (get_reg s7 Register.rbx);

  (* Extended Leaf 0x80000000: Max Extended Function *)
  let sext = run {|
func_cpuid_ext:
    mov eax, 0x80000000
    cpuid
    ret
|} 0L 0L in
  Alcotest.(check int64) "cpuid ext leaf: EAX = 0x80000008" 0x80000008L (get_reg sext Register.rax);

  (* Extended Leaf 0x80000002: Processor Brand String 1 *)
  let sbrand = run {|
func_cpuid_brand:
    mov eax, 0x80000002
    cpuid
    ret
|} 0L 0L in
  Alcotest.(check int64) "cpuid brand EAX" 0x65746E49L (get_reg sbrand Register.rax);
  Alcotest.(check int64) "cpuid brand EBX" 0x2952286CL (get_reg sbrand Register.rbx);

  (* High 32 bits cleared in 64-bit mode *)
  let s_clear = run {|
func_cpuid_clear_high:
    mov rax, 0xFFFFFFFF00000001
    mov rbx, 0xFFFFFFFFFFFFFFFF
    mov rcx, 0xFFFFFFFFFFFFFFFF
    mov rdx, 0xFFFFFFFFFFFFFFFF
    cpuid
    ret
|} 0L 0L in
  Alcotest.(check bool) "cpuid RAX upper 32 bits zeroed" true (Int64.shift_right_logical (get_reg s_clear Register.rax) 32 = 0L);
  Alcotest.(check bool) "cpuid RBX upper 32 bits zeroed" true (Int64.shift_right_logical (get_reg s_clear Register.rbx) 32 = 0L);
  Alcotest.(check bool) "cpuid RCX upper 32 bits zeroed" true (Int64.shift_right_logical (get_reg s_clear Register.rcx) 32 = 0L);
  Alcotest.(check bool) "cpuid RDX upper 32 bits zeroed" true (Int64.shift_right_logical (get_reg s_clear Register.rdx) 32 = 0L)

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
  Alcotest.test_case "lift_and_eval_movzx_forms" `Quick test_lift_and_eval_movzx_forms;
  Alcotest.test_case "lift_and_eval_rol_ror" `Quick test_lift_and_eval_rol_ror;
  Alcotest.test_case "lift_and_eval_fpu_load_store" `Quick test_x86_fpu_load_store;
  Alcotest.test_case "lift_and_eval_fpu_arithmetic" `Quick test_x86_fpu_arithmetic;
  Alcotest.test_case "lift_and_eval_fpu_comparison" `Quick test_x86_fpu_comparison;
  Alcotest.test_case "lift_and_eval_fpu_trans" `Quick test_x86_fpu_unary_and_transcendental;
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
  Alcotest.test_case "lift_orps_orpd" `Quick test_x86_lift_orps_orpd;
  Alcotest.test_case "lift_bit_scan_family" `Quick test_x86_lift_bit_scan_family;
  Alcotest.test_case "lift_sign_extension_family" `Quick test_x86_lift_sign_extension_family;
  Alcotest.test_case "lift_sha_ni" `Quick test_x86_lift_sha_ni;
  Alcotest.test_case "lift_pclmul_cet" `Quick test_x86_lift_pclmul_cet;
  Alcotest.test_case "lift_vorps_vorpd" `Quick test_x86_lift_vorps_vorpd;
  Alcotest.test_case "lift_x86_bitmanip" `Quick test_x86_bitmanip;
  Alcotest.test_case "lift_x86_fp_scalar" `Quick test_x86_fp_scalar;
  Alcotest.test_case "lift_x86_bmi" `Quick test_x86_lift_bmi;
  Alcotest.test_case "lift_x86_shld_shrd" `Quick test_x86_lift_shld_shrd;
  Alcotest.test_case "lift_x86_cdq_dirty_upper_rax" `Quick test_x86_lift_cdq_dirty_upper_rax;
  Alcotest.test_case "lift_x86_movbe" `Quick test_x86_lift_movbe;
  Alcotest.test_case "lift_x86_adc_sbb" `Quick test_x86_lift_adc_sbb;
  Alcotest.test_case "lift_x86_lahf_sahf" `Quick test_x86_lift_lahf_sahf;
  Alcotest.test_case "lift_x86_cmpxchg" `Quick test_x86_lift_cmpxchg;
  Alcotest.test_case "lift_x86_xadd" `Quick test_x86_lift_xadd;
  Alcotest.test_case "lift_x86_xlat" `Quick test_x86_lift_xlat;
  Alcotest.test_case "lift_x86_string_ops" `Quick test_x86_lift_string_ops;
  Alcotest.test_case "lift_x86_bit_tests" `Quick test_x86_lift_bit_tests;
  Alcotest.test_case "lift_x86_pext_pdep" `Quick test_x86_lift_pext_pdep;
  Alcotest.test_case "lift_x86_fp_sqrt_and_cvt" `Quick test_x86_fp_sqrt_and_cvt;
  Alcotest.test_case "lift_x86_rcl_rcr_cmc" `Quick test_x86_rcl_rcr_cmc;
  Alcotest.test_case "lift_x86_rep_stosb" `Quick test_x86_rep_stosb;
  Alcotest.test_case "lift_x86_rep_movsb" `Quick test_x86_rep_movsb;
  Alcotest.test_case "lift_x86_repne_scasb" `Quick test_x86_repne_scasb;
  Alcotest.test_case "lift_x86_repe_cmpsb" `Quick test_x86_repe_cmpsb;
  Alcotest.test_case "lift_x86_cmpxchg8b" `Quick test_x86_cmpxchg8b;
  Alcotest.test_case "lift_x86_cmpxchg16b" `Quick test_x86_cmpxchg16b;
  Alcotest.test_case "lift_x86_avx256_arithmetic" `Quick test_x86_avx256_arithmetic;
  Alcotest.test_case "lift_x86_avx_shifts_minmax_abs" `Quick test_x86_avx_shifts_minmax_abs;
  Alcotest.test_case "lift_x86_avx_upper_zeroing" `Quick test_x86_avx_upper_zeroing;
  Alcotest.test_case "lift_x86_vzeroupper" `Quick test_x86_vzeroupper;
  Alcotest.test_case "lift_x86_pmovmskb" `Quick test_x86_pmovmskb;
  Alcotest.test_case "lift_x86_unpck_fp" `Quick test_x86_unpck_fp;
  Alcotest.test_case "lift_x86_ptest" `Quick test_x86_ptest;
  Alcotest.test_case "lift_x86_evex_zmm_trap" `Quick test_x86_evex_zmm_trap;
  Alcotest.test_case "lift_x86_tls_fs_gs_segment_prefixes" `Quick test_x86_tls_fs_gs_segment_prefixes;
  Alcotest.test_case "lift_x86_tls_native_vm_canonicalize" `Quick test_x86_tls_native_vm_canonicalize;
  Alcotest.test_case "lift_x86_moffs_memory" `Quick test_x86_moffs_memory;
  Alcotest.test_case "lift_x86_segment_registers_push_pop_mov" `Quick test_x86_segment_registers_push_pop_mov;
  Alcotest.test_case "lift_x86_fsbase_gsbase_rdfsbase_wrfsbase" `Quick test_x86_fsbase_gsbase_rdfsbase_wrfsbase;
  Alcotest.test_case "lift_x86_xadd_same_reg" `Quick test_x86_lift_xadd_same_reg;
  Alcotest.test_case "lift_x86_verified_alu_simulation" `Quick test_x86_lift_verified_alu_simulation;
  Alcotest.test_case "lift_x86_atomic_rmw_and_lock" `Quick test_x86_lift_atomic_rmw_and_lock;
  Alcotest.test_case "lift_x86_atomic_mem_nodes" `Quick test_x86_lift_atomic_mem_nodes;
  Alcotest.test_case "lift_x86_cpuid" `Quick test_x86_cpuid;
  Alcotest.test_case "lift_x86_movss_movsd_vector_moves" `Quick test_x86_movss_movsd_vector_moves;
  Alcotest.test_case "lift_x86_scalar_and_packed_fp_arithmetic" `Quick test_x86_scalar_and_packed_fp_arithmetic;
  Alcotest.test_case "lift_x86_int_float_conversions" `Quick test_x86_int_float_conversions;
  Alcotest.test_case "lift_x86_float_comparisons" `Quick test_x86_float_comparisons;
  Alcotest.test_case "lift_x86_pand_por_pxor_pandn" `Quick test_x86_pand_por_pxor_pandn;
  Alcotest.test_case "lift_x86_aes_ni" `Quick test_x86_aes_ni;
  Alcotest.test_case "lift_x86_aes_ni_fips197_full_cycle" `Quick test_x86_lift_aes_ni_fips197_full_cycle;
  Alcotest.test_case "lift_x86_shufps_shufpd" `Quick test_x86_lift_shufps_shufpd;
  Alcotest.test_case "lift_x86_packed_conversions" `Quick test_x86_lift_packed_conversions;
  Alcotest.test_case "lift_x86_movlhps_movhlps_movlps_movhps" `Quick test_x86_lift_movlhps_movhlps_movlps_movhps;
  Alcotest.test_case "lift_x86_system_and_compiler_traps" `Quick test_x86_lift_system_and_compiler_traps;
]

