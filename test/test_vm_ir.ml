open Vm_ir
open Register
open Flags
open Ir
open Vm_eval

let test_registers_and_subregisters () =
  let state = make_state () in

  (* Test 64-bit write *)
  set_reg state rax 0x1122334455667788L;
  Alcotest.(check int64) "rax 64-bit" 0x1122334455667788L (get_reg state rax);

  (* Test 32-bit eax write: in x86_64, writing 32-bit zero-extends to 64-bit! *)
  let eax = Gpr (RAX, B32) in
  set_reg state eax 0xAABBCCDDL;
  Alcotest.(check int64) "eax 32-bit read" 0xAABBCCDDL (get_reg state eax);
  Alcotest.(check int64) "rax zero-extended" 0x00000000AABBCCDDL (get_reg state rax);

  (* Test 16-bit ax write: preserves upper bits *)
  let ax = Gpr (RAX, B16) in
  set_reg state ax 0x1234L;
  Alcotest.(check int64) "ax 16-bit read" 0x1234L (get_reg state ax);
  Alcotest.(check int64) "rax after ax" 0x00000000AABB1234L (get_reg state rax);

  (* Test 8-bit al write: preserves upper bits *)
  let al = Gpr (RAX, B8) in
  set_reg state al 0x56L;
  Alcotest.(check int64) "al 8-bit read" 0x56L (get_reg state al);
  Alcotest.(check int64) "rax after al" 0x00000000AABB1256L (get_reg state rax);

  (* Test register names *)
  Alcotest.(check string) "rax to_string" "rax" (Register.to_string rax);
  Alcotest.(check string) "eax to_string" "eax" (Register.to_string eax);
  Alcotest.(check string) "ax to_string" "ax" (Register.to_string ax);
  Alcotest.(check string) "al to_string" "al" (Register.to_string al);
  Alcotest.(check string) "vip to_string" "vip" (Register.to_string vip)

let test_lazy_flags_add () =
  (* Normal addition: 5 + 3 = 8 *)
  let op_norm = CC_OP_ADD { src1 = 5L; src2 = 3L; dst = 8L; width = B64 } in
  Alcotest.(check bool) "norm cf" false (compute_cf op_norm);
  Alcotest.(check bool) "norm zf" false (compute_zf op_norm);
  Alcotest.(check bool) "norm sf" false (compute_sf op_norm);
  Alcotest.(check bool) "norm of" false (compute_of op_norm);

  (* Unsigned overflow / Carry: 0xFFFFFFFFFFFFFFFF + 1 = 0 *)
  let op_carry = CC_OP_ADD { src1 = -1L; src2 = 1L; dst = 0L; width = B64 } in
  Alcotest.(check bool) "carry cf" true (compute_cf op_carry);
  Alcotest.(check bool) "carry zf" true (compute_zf op_carry);
  Alcotest.(check bool) "carry sf" false (compute_sf op_carry);
  Alcotest.(check bool) "carry of" false (compute_of op_carry);

  (* Signed overflow: MaxInt + 1 = MinInt *)
  let max_int = 0x7FFFFFFFFFFFFFFFL in
  let min_int = Int64.min_int in
  let op_of = CC_OP_ADD { src1 = max_int; src2 = 1L; dst = min_int; width = B64 } in
  Alcotest.(check bool) "overflow of" true (compute_of op_of);
  Alcotest.(check bool) "overflow sf" true (compute_sf op_of);
  Alcotest.(check bool) "overflow cf" false (compute_cf op_of)

let test_lazy_flags_sub_and_cmp () =
  (* Normal sub: 10 - 4 = 6 *)
  let op_sub = CC_OP_SUB { src1 = 10L; src2 = 4L; dst = 6L; width = B64 } in
  Alcotest.(check bool) "sub cf" false (compute_cf op_sub);
  Alcotest.(check bool) "sub zf" false (compute_zf op_sub);
  Alcotest.(check bool) "sub sf" false (compute_sf op_sub);
  Alcotest.(check bool) "sub of" false (compute_of op_sub);
  Alcotest.(check bool) "sub greater (G)" true (evaluate_condition op_sub G);
  Alcotest.(check bool) "sub less (L)" false (evaluate_condition op_sub L);

  (* Equal sub: 7 - 7 = 0 *)
  let op_eq = CC_OP_SUB { src1 = 7L; src2 = 7L; dst = 0L; width = B64 } in
  Alcotest.(check bool) "eq zf" true (compute_zf op_eq);
  Alcotest.(check bool) "eq E" true (evaluate_condition op_eq E);
  Alcotest.(check bool) "eq NE" false (evaluate_condition op_eq NE);
  Alcotest.(check bool) "eq LE" true (evaluate_condition op_eq LE);
  Alcotest.(check bool) "eq GE" true (evaluate_condition op_eq GE);

  (* Below / Unsigned borrow: 3 - 5 *)
  let op_borrow = CC_OP_SUB { src1 = 3L; src2 = 5L; dst = -2L; width = B64 } in
  Alcotest.(check bool) "borrow cf" true (compute_cf op_borrow);
  Alcotest.(check bool) "borrow B" true (evaluate_condition op_borrow B);
  Alcotest.(check bool) "borrow AE" false (evaluate_condition op_borrow AE);

  (* Signed less: -5 - 3 = -8 *)
  let op_sless = CC_OP_SUB { src1 = -5L; src2 = 3L; dst = -8L; width = B64 } in
  Alcotest.(check bool) "sless L" true (evaluate_condition op_sless L);
  Alcotest.(check bool) "sless G" false (evaluate_condition op_sless G)

let test_parity_flag () =
  (* 0x03 has 2 bits set (even) -> PF = 1 *)
  let op_p1 = CC_OP_LOGIC { dst = 0x03L; width = B64 } in
  Alcotest.(check bool) "parity even" true (compute_pf op_p1);

  (* 0x07 has 3 bits set (odd) -> PF = 0 *)
  let op_p0 = CC_OP_LOGIC { dst = 0x07L; width = B64 } in
  Alcotest.(check bool) "parity odd" false (compute_pf op_p0);

  (* High bits should not affect PF (only low byte matters in x86) *)
  let op_p_high = CC_OP_LOGIC { dst = 0xFF03L; width = B64 } in
  Alcotest.(check bool) "parity ignores high byte" true (compute_pf op_p_high)

let test_fibonacci_function_execution () =
  (* Computes fib(10) = 55 in pure VM-IR *)
  (*
     BB_0 (Entry):
       mov rax, 0      ; a = 0
       mov rbx, 1      ; b = 1
       mov rcx, 10     ; n = 10
       jmp BB_1
     BB_1 (Loop header):
       cmp rcx, 0
       jle BB_3 (Done), else BB_2 (Body)
     BB_2 (Body):
       mov rdx, rax    ; tmp = a
       add rax, rbx    ; a = a + b
       mov rbx, rdx    ; b = tmp
       dec rcx         ; n = n - 1
       jmp BB_1
     BB_3 (Done):
       vm_exit
  *)
  let b0 = make_block ~id:0 ~label:"entry" ~instrs:[
    Mov { dst = Reg rax; src = Imm 0L };
    Mov { dst = Reg rbx; src = Imm 1L };
    Mov { dst = Reg rcx; src = Imm 10L };
    Jmp (BlockId 1);
  ] in

  let b1 = make_block ~id:1 ~label:"loop_header" ~instrs:[
    Cmp { src1 = Reg rcx; src2 = Imm 0L };
    Jcc { cond = LE; target_true = BlockId 3; target_false = BlockId 2 };
  ] in

  let b2 = make_block ~id:2 ~label:"loop_body" ~instrs:[
    Mov { dst = Reg rdx; src = Reg rax };
    Alu { op = Add; dst = rax; src1 = Reg rax; src2 = Reg rbx; set_flags = false };
    Mov { dst = Reg rbx; src = Reg rdx };
    Unary { op = Dec; dst = rcx; src = Reg rcx; set_flags = true };
    Jmp (BlockId 1);
  ] in

  let b3 = make_block ~id:3 ~label:"done" ~instrs:[
    Vm_exit;
  ] in

  let fib_func = make_func ~name:"fib" ~entry_id:0 ~blocks:[ b0; b1; b2; b3 ] in
  let state = make_state () in

  match run_func state fib_func with
  | Error err -> Alcotest.fail err
  | Ok () ->
      Alcotest.(check bool) "vm halted" true state.halted;
      (* fib(10): 0, 1, 1, 2, 3, 5, 8, 13, 21, 34, 55 *)
      Alcotest.(check int64) "fib(10) is 55" 55L (get_reg state rax)

let test_memory_and_stack () =
  let state = make_state () in

  (* Push / Pop test *)
  let _ = step state (Push (Imm 0x123456789ABCDEF0L)) in
  let _ = step state (Push (Imm 0xCAFEBABE11223344L)) in

  let _ = step state (Pop (Reg rax)) in
  let _ = step state (Pop (Reg rbx)) in

  Alcotest.(check int64) "pop rax" 0xCAFEBABE11223344L (get_reg state rax);
  Alcotest.(check int64) "pop rbx" 0x123456789ABCDEF0L (get_reg state rbx);

  (* Complex addressing: lea rdi, [rax + rbx*2 + 0x20] *)
  set_reg state rax 100L;
  set_reg state rbx 50L;
  let mem_spec = { base = Some rax; index = Some (rbx, 2); disp = 0x20L; width = B64 } in
  let _ = step state (Lea { dst = rdi; addr = mem_spec }) in
  (* 100 + 50*2 + 32 = 232 *)
  Alcotest.(check int64) "lea effective addr" 232L (get_reg state rdi)

(** Property test: 1,000 random pairs verifying ADD / SUB flag consistency *)
let prop_lazy_flags =
  QCheck.Test.make
    ~name:"lazy_flags_add_sub_1000_seeds"
    ~count:1000
    (QCheck.pair QCheck.int64 QCheck.int64)
    (fun (a, b) ->
      let sum = Int64.add a b in
      let op_add = CC_OP_ADD { src1 = a; src2 = b; dst = sum; width = B64 } in
      let cf_add = compute_cf op_add in
      let zf_add = compute_zf op_add in
      let sf_add = compute_sf op_add in

      let diff = Int64.sub a b in
      let op_sub = CC_OP_SUB { src1 = a; src2 = b; dst = diff; width = B64 } in
      let cf_sub = compute_cf op_sub in
      let zf_sub = compute_zf op_sub in

      (* Invariants: *)
      (* 1. If sum is 0, zf_add must be true *)
      let inv1 = (sum = 0L) = zf_add in
      (* 2. If diff is 0, a must equal b and zf_sub must be true *)
      let inv2 = (a = b) = zf_sub in
      (* 3. If a < b (unsigned), cf_sub must be true *)
      let inv3 = (Int64.unsigned_compare a b < 0) = cf_sub in
      (* 4. If sum < a (unsigned), cf_add must be true *)
      let inv4 = (Int64.unsigned_compare sum a < 0) = cf_add in
      (* 5. If sum < 0 (signed), sf_add must be true *)
      let inv5 = (sum < 0L) = sf_add in

      inv1 && inv2 && inv3 && inv4 && inv5)

let tests = [
  Alcotest.test_case "registers_and_subregisters" `Quick test_registers_and_subregisters;
  Alcotest.test_case "lazy_flags_add" `Quick test_lazy_flags_add;
  Alcotest.test_case "lazy_flags_sub_and_cmp" `Quick test_lazy_flags_sub_and_cmp;
  Alcotest.test_case "parity_flag" `Quick test_parity_flag;
  Alcotest.test_case "fibonacci_function_execution" `Quick test_fibonacci_function_execution;
  Alcotest.test_case "memory_and_stack" `Quick test_memory_and_stack;
  QCheck_alcotest.to_alcotest prop_lazy_flags;
]
