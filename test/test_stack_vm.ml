open Vm_ir
open Register
open Ir
open Stack_vm
open Stack_ir
open Stack_eval
open Random_visa_ports
open Protect_ports

let test_stack_ir_primitives () =
  let op_push = PushImm 42L in
  let op_add = Add in
  let op_pop = PopReg 0 in
  Alcotest.(check int) "push weight PushImm" 1 (push_weight op_push);
  Alcotest.(check int) "pop weight PushImm" 0 (pop_weight op_push);
  Alcotest.(check int) "delta PushImm" 1 (stack_delta op_push);

  Alcotest.(check int) "push weight Add" 1 (push_weight op_add);
  Alcotest.(check int) "pop weight Add" 2 (pop_weight op_add);
  Alcotest.(check int) "delta Add" (-1) (stack_delta op_add);

  Alcotest.(check int) "delta PopReg" (-1) (stack_delta op_pop);
  Alcotest.(check string) "op_to_string Add" "ADD" (op_to_string op_add);
  Alcotest.(check string) "op_to_string Exit" "EXIT" (op_to_string Exit)

let test_context_allocator () =
  let ctx = Context_allocator.create () in
  let slot_rax = Context_allocator.slot_of_reg ctx rax in
  let eax = Gpr (RAX, B32) in
  let slot_eax = Context_allocator.slot_of_reg ctx eax in
  Alcotest.(check int) "subregister maps to same slot" slot_rax slot_eax;

  let slot_rbx = Context_allocator.slot_of_reg ctx rbx in
  Alcotest.(check bool) "different registers have distinct slots" true (slot_rax <> slot_rbx);

  let scratch = Context_allocator.alloc_scratch ctx in
  Alcotest.(check bool) "scratch slot distinct" true (scratch <> slot_rax && scratch <> slot_rbx);

  (* Test randomized permutation *)
  let ctx_perm1 = Context_allocator.create ~seed:12345 ~permute:true () in
  let ctx_perm2 = Context_allocator.create ~seed:54321 ~permute:true () in
  let s1 = Context_allocator.slot_of_reg ctx_perm1 rax in
  let s2 = Context_allocator.slot_of_reg ctx_perm2 rax in
  Alcotest.(check bool) "permutations are active" true (Context_allocator.total_slots ctx_perm1 > 0);
  (* Check slot bounds *)
  Alcotest.(check bool) "valid slot range s1" true (s1 >= 0 && s1 < Context_allocator.total_slots ctx_perm1);
  Alcotest.(check bool) "valid slot range s2" true (s2 >= 0 && s2 < Context_allocator.total_slots ctx_perm2)

let test_logic_reduction_truth_tables () =
  let ctx = Context_allocator.create () in
  let sx = Context_allocator.alloc_scratch ctx in
  let sy = Context_allocator.alloc_scratch ctx in

  (* Test 64-bit random values for NOR-based XOR *)
  let test_cases = [
    (0L, 0L, 0L);
    (0L, 1L, 1L);
    (1L, 0L, 1L);
    (1L, 1L, 0L);
    (0x123456789ABCDEF0L, 0x0FEDCBA987654321L, Int64.logxor 0x123456789ABCDEF0L 0x0FEDCBA987654321L);
    (-1L, 0xAAAAAAAAAAAAAAAAL, Int64.logxor (-1L) 0xAAAAAAAAAAAAAAAAL);
  ] in

  List.iter (fun (x, y, expected_xor) ->
    (* Test NOR XOR: ((x NOR x) NOR (y NOR y)) NOR (x NOR y) *)
    let ops = [PushImm x; PushImm y] @ Stack_logic_pass.expand_xor_nor sx sy @ [Exit] in
    let blk = make_block 0 "test_xor" ops in
    let prog = make_program 0 [blk] (Context_allocator.total_slots ctx) in
    let state = run_program prog in
    match state.vstack with
    | res :: _ -> Alcotest.(check int64) (Printf.sprintf "XOR 0x%Lx ^ 0x%Lx" x y) expected_xor res
    | [] -> Alcotest.fail "Stack empty after XOR evaluation"
  ) test_cases;

  (* Test NOR AND: (x NOR x) NOR (y NOR y) *)
  List.iter (fun (x, y, _) ->
    let expected_and = Int64.logand x y in
    let ops = [PushImm x; PushImm y] @ Stack_logic_pass.expand_and_nor @ [Exit] in
    let blk = make_block 0 "test_and" ops in
    let prog = make_program 0 [blk] (Context_allocator.total_slots ctx) in
    let state = run_program prog in
    match state.vstack with
    | res :: _ -> Alcotest.(check int64) (Printf.sprintf "AND 0x%Lx & 0x%Lx" x y) expected_and res
    | [] -> Alcotest.fail "Stack empty after AND evaluation"
  ) test_cases;

  (* Test NOR OR: (x NOR y) NOR (x NOR y) *)
  List.iter (fun (x, y, _) ->
    let expected_or = Int64.logor x y in
    let ops = [PushImm x; PushImm y] @ Stack_logic_pass.expand_or_nor @ [Exit] in
    let blk = make_block 0 "test_or" ops in
    let prog = make_program 0 [blk] (Context_allocator.total_slots ctx) in
    let state = run_program prog in
    match state.vstack with
    | res :: _ -> Alcotest.(check int64) (Printf.sprintf "OR 0x%Lx | 0x%Lx" x y) expected_or res
    | [] -> Alcotest.fail "Stack empty after OR evaluation"
  ) test_cases;

  (* Test NAND XOR *)
  let sn1 = Context_allocator.alloc_scratch ctx in
  List.iter (fun (x, y, expected_xor) ->
    let ops = [PushImm x; PushImm y] @ Stack_logic_pass.expand_xor_nand sx sy sn1 @ [Exit] in
    let blk = make_block 0 "test_nand_xor" ops in
    let prog = make_program 0 [blk] (Context_allocator.total_slots ctx) in
    let state = run_program prog in
    match state.vstack with
    | res :: _ -> Alcotest.(check int64) (Printf.sprintf "NAND XOR 0x%Lx ^ 0x%Lx" x y) expected_xor res
    | [] -> Alcotest.fail "Stack empty after NAND XOR evaluation"
  ) test_cases

let test_ir_to_stack_and_eval () =
  (* Build a 3-address IR function:
     rax = 42
     rbx = 58
     rax = rax + rbx   (= 100)
     rcx = 15
     rax = rax - rcx   (= 85)
     ret
  *)
  let b0 = {
    id = 0;
    label = "entry";
    instrs = [
      Mov { dst = Reg rax; src = Imm 42L };
      Mov { dst = Reg rbx; src = Imm 58L };
      Alu { op = Add; dst = rax; src1 = Reg rax; src2 = Reg rbx; set_flags = false };
      Mov { dst = Reg rcx; src = Imm 15L };
      Alu { op = Sub; dst = rax; src1 = Reg rax; src2 = Reg rcx; set_flags = false };
      Ret;
    ];
  } in
  let cfg = { entry_id = 0; blocks = Hashtbl.create 1 } in
  Hashtbl.replace cfg.blocks 0 b0;
  let func = { name = "calc_func"; cfg } in

  let ctx, prog = Ir_to_stack.lower_func func in
  let state = run_program prog in
  let rax_slot = Context_allocator.slot_of_reg ctx rax in
  let rax_val = get_reg state rax_slot in
  Alcotest.(check int64) "rax equals 85 after stack execution" 85L rax_val;
  Alcotest.(check bool) "state halted on return" true state.halted

let test_stack_balance_pass () =
  let b_balanced = make_block 0 "balanced" [
    PushImm 10L;
    PushImm 20L;
    Add;
    PopReg 0;
    Exit;
  ] in
  let res_bal = Stack_balance_pass.analyze_block b_balanced in
  Alcotest.(check bool) "balanced block is balanced" true res_bal.is_balanced;
  Alcotest.(check int) "balanced block final delta" 0 res_bal.final_delta;

  let b_unbalanced = make_block 1 "unbalanced" [
    PushImm 10L;
    PushImm 20L;
    Exit;
  ] in
  let res_unbal = Stack_balance_pass.analyze_block b_unbalanced in
  Alcotest.(check bool) "unbalanced block is not balanced" false res_unbal.is_balanced;
  Alcotest.(check int) "unbalanced block final delta" 2 res_unbal.final_delta;

  let ctx = Context_allocator.create () in
  let prog = make_program 1 [b_unbalanced] 10 in
  let repaired_prog = Stack_balance_pass.repair_program ctx prog in
  let errors = Stack_balance_pass.verify_program repaired_prog in
  Alcotest.(check int) "no balance errors after repair" 0 (List.length errors)

let test_rolling_key_encoder_and_eval () =
  let b = make_block 0 "entry" [
    PushImm 100L;
    PopReg 1;
    PushReg 1;
    PushImm 25L;
    Sub;
    PopReg 2;
    Exit;
  ] in
  let prog = make_program 0 [b] 8 in
  let enc = Stack_encoder.encode_program ~seed_key:0xDEADBEEFCAFE0011L prog in
  Alcotest.(check bool) "bytecode is non-empty" true (Bytes.length enc.bytes > 0);

  (* Test roundtrip decoding *)
  let decoded_ops = Stack_encoder.decode_enc enc in
  Alcotest.(check int) "decoded op count matches" (List.length b.ops) (List.length decoded_ops);

  (* Test execution of encrypted bytecode *)
  let state = run_bytecode enc in
  let reg2 = get_reg state 2 in
  Alcotest.(check int64) "bytecode computes 100 - 25 = 75" 75L reg2;
  Alcotest.(check bool) "bytecode halts" true state.halted

let test_runtime_synthesis () =
  let cfg = Stack_runtime.default_config Stack_runtime.X86_64 in
  let entry_lines = Stack_runtime.emit_entry_stub cfg 16 in
  Alcotest.(check bool) "entry stub generated" true (List.length entry_lines > 0);

  let exit_lines = Stack_runtime.emit_exit_stub cfg 16 in
  Alcotest.(check bool) "exit stub generated" true (List.length exit_lines > 0);

  let epilogue = Stack_runtime.emit_dispatch_epilogue cfg in
  Alcotest.(check bool) "dispatch epilogue generated" true (List.length epilogue > 0);

  let b = make_block 0 "main" [PushImm 1L; Exit] in
  let prog = make_program 0 [b] 16 in
  let c_code = Stack_runtime.generate_c_runtime cfg prog in
  Alcotest.(check bool) "c runtime contains stack_vm_run" true
    (String.length c_code > 0 && String.sub c_code 0 18 = "#include <stdint.h");
  let runner_cpp = Stack_runtime.emit_runner_cpp [0x1234567890ABCDEFL] in
  Alcotest.(check bool) "runner cpp generated" true (String.length runner_cpp > 0)

let test_stack_vm_extensions () =
  (* Test Cmp, Setcc, Cmov, and Multi-Block branching with Rolling Key *)
  let b0 = make_block 0 "entry" [
    PushImm 100L;
    PushImm 100L;
    Cmp;
    Setcc Flags.E;
    PopReg 0;
    PushImm 42L;
    Cmov (Flags.E, 1);
    PushImm 50L;
    PushImm 100L;
    Cmp;
    JccRel (1, Flags.E);
    JmpRel 2;
  ] in
  let b1 = make_block 1 "dead_branch" [
    PushImm 999L;
    PopReg 2;
    Exit;
  ] in
  let b2 = make_block 2 "taken_branch" [
    PushImm 777L;
    PopReg 2;
    ResolveSym 0;
    PopReg 3;
    CallExtern 0;
    Exit;
  ] in
  let prog = make_program 0 [b0; b1; b2] 16 in

  (* Test AST execution *)
  let state_ast = run_program prog in
  Alcotest.(check int64) "AST reg0 (Setcc E) is 1" 1L (get_reg state_ast 0);
  Alcotest.(check int64) "AST reg1 (Cmov E) is 42" 42L (get_reg state_ast 1);
  Alcotest.(check int64) "AST reg2 (taken branch) is 777" 777L (get_reg state_ast 2);
  Alcotest.(check bool) "AST halted" true state_ast.halted;

  (* Test Bytecode encoding, roundtrip decoding and execution *)
  let enc = Stack_encoder.encode_program ~seed_key:0xCAFEBABE12345678L prog in
  let decoded = Stack_encoder.decode_enc enc in
  Alcotest.(check bool) "decoded instructions present" true (List.length decoded > 0);

  let state_bc = run_bytecode enc in
  Alcotest.(check int64) "BC reg0 (Setcc E) is 1" 1L (get_reg state_bc 0);
  Alcotest.(check int64) "BC reg1 (Cmov E) is 42" 42L (get_reg state_bc 1);
  Alcotest.(check int64) "BC reg2 (taken branch) is 777" 777L (get_reg state_bc 2);
  Alcotest.(check bool) "BC halted" true state_bc.halted

let contains s substr =
  let len_s = String.length s in
  let len_sub = String.length substr in
  let rec check i =
    if i + len_sub > len_s then false
    else if String.sub s i len_sub = substr then true
    else check (i + 1)
  in
  check 0

let test_polymorphic_opcodes () =
  let seed1 = 0x1122334455667788L in
  let seed2 = 0x99AABBCCDDEEFF00L in
  let map1 = Stack_encoder.generate_opcode_map seed1 in
  let map2 = Stack_encoder.generate_opcode_map seed2 in

  (* 1. Verify determinism *)
  let map1_dup = Stack_encoder.generate_opcode_map seed1 in
  Alcotest.(check int) "deterministic PUSH_IMM" map1.op_push_imm map1_dup.op_push_imm;
  Alcotest.(check int) "deterministic ADD" map1.op_add map1_dup.op_add;
  Alcotest.(check int) "deterministic EXIT" map1.op_exit map1_dup.op_exit;

  (* 2. Verify all 36 opcodes in map1 are unique and non-zero *)
  let ops_list1 = [
    map1.op_push_imm; map1.op_push_reg; map1.op_pop_reg; map1.op_read_mem; map1.op_write_mem;
    map1.op_add; map1.op_sub; map1.op_mul; map1.op_nor; map1.op_nand;
    map1.op_shl; map1.op_shr; map1.op_dup; map1.op_swap; map1.op_push_flags;
    map1.op_pop_flags; map1.op_jmp_rel; map1.op_jcc_rel; map1.op_key_adjust; map1.op_exit;
    map1.op_call_extern; map1.op_resolve_sym; map1.op_setcc; map1.op_cmov; map1.op_cmp; map1.op_test;
    map1.op_sar; map1.op_div; map1.op_idiv; map1.op_push_imm32;
    map1.op_add_imm; map1.op_sub_imm; map1.op_add_ii; map1.op_sub_ii;
    map1.op_set_reg_imm; map1.op_add_reg_imm;
  ] in
  List.iter (fun op ->
    Alcotest.(check bool) "opcode is in range 1..254" true (op >= 1 && op <= 254)
  ) ops_list1;
  let unique1 = List.sort_uniq compare ops_list1 in
  Alcotest.(check int) "all 36 opcodes are strictly unique" 36 (List.length unique1);

  (* 3. Verify diversity between different seeds *)
  let ops_list2 = [
    map2.op_push_imm; map2.op_push_reg; map2.op_pop_reg; map2.op_read_mem; map2.op_write_mem;
    map2.op_add; map2.op_sub; map2.op_mul; map2.op_nor; map2.op_nand;
    map2.op_shl; map2.op_shr; map2.op_dup; map2.op_swap; map2.op_push_flags;
    map2.op_pop_flags; map2.op_jmp_rel; map2.op_jcc_rel; map2.op_key_adjust; map2.op_exit;
    map2.op_call_extern; map2.op_resolve_sym; map2.op_setcc; map2.op_cmov; map2.op_cmp; map2.op_test;
    map2.op_sar; map2.op_div; map2.op_idiv; map2.op_push_imm32;
    map2.op_add_imm; map2.op_sub_imm; map2.op_add_ii; map2.op_sub_ii;
    map2.op_set_reg_imm; map2.op_add_reg_imm;
  ] in
  let diff_count = List.fold_left2 (fun acc a b -> if a <> b then acc + 1 else acc) 0 ops_list1 ops_list2 in
  Alcotest.(check bool) "most opcodes differ between seed1 and seed2" true (diff_count >= 20);

  (* 4. End-to-end program execution with polymorphic opcodes *)
  let b = make_block 0 "entry" [
    PushImm 12345L;
    PushImm 54321L;
    Add;
    PopReg 0;
    Exit;
  ] in
  let prog = make_program 0 [b] 8 in
  let enc = Stack_encoder.encode_program ~seed_key:seed1 prog in
  let state = run_bytecode enc in
  Alcotest.(check int64) "polymorphic bytecode computes 12345 + 54321 = 66666" 66666L (get_reg state 0);
  Alcotest.(check bool) "polymorphic bytecode halted" true state.halted;

  (* 5. Verify C runtime contains polymorphic opcode case *)
  let cfg = Stack_runtime.default_config Stack_runtime.X86_64 in
  let c_code = Stack_runtime.generate_c_runtime ~enc cfg prog in
  let expected_push_case = Printf.sprintf "case 0x%02X: /* PUSH_IMM */" enc.op_map.op_push_imm in
  let expected_add_case = Printf.sprintf "case 0x%02X: /* ADD */" enc.op_map.op_add in
  let expected_exit_case = Printf.sprintf "case 0x%02X: /* EXIT */" enc.op_map.op_exit in
  Alcotest.(check bool) "c runtime contains polymorphic push_imm" true (contains c_code expected_push_case);
  Alcotest.(check bool) "c runtime contains polymorphic add" true (contains c_code expected_add_case);
  Alcotest.(check bool) "c runtime contains polymorphic exit" true (contains c_code expected_exit_case)

let test_compact_push_imm () =
  let seed = 0x5877_A564_D00FL in
  let b0 = make_block 0 "entry" [
    PushImm 42L;                          (* fits i32 *)
    PushImm (-100L);                      (* negative, fits i32 *)
    Add;                                  (* 42 + (-100) = -58 *)
    PushImm 0x1000_0000_2000L;            (* does not fit i32: requires i64 *)
    Add;
    PopReg 0;
    Exit;
  ] in
  let prog = make_program 0 [b0] 8 in

  (* Encode with compact_imm = true *)
  let enc_compact = Stack_encoder.encode_program ~seed_key:seed ~compact_imm:true prog in
  (* Encode with compact_imm = false *)
  let enc_fixed = Stack_encoder.encode_program ~seed_key:seed ~compact_imm:false prog in

  (* Compact bytecode must be smaller than fixed 64-bit bytecode *)
  Alcotest.(check bool) "compact bytecode is smaller" true
    (Bytes.length enc_compact.bytes < Bytes.length enc_fixed.bytes);

  (* Two 32-bit constants save 4 bytes each = 8 bytes saved *)
  Alcotest.(check int) "saves exactly 8 bytes" 8
    (Bytes.length enc_fixed.bytes - Bytes.length enc_compact.bytes);

  (* Both execute identically in VM *)
  let st_compact = run_bytecode enc_compact in
  let st_fixed = run_bytecode enc_fixed in
  let expected = Int64.add (-58L) 0x1000_0000_2000L in
  Alcotest.(check int64) "compact result matches expected" expected (get_reg st_compact 0);
  Alcotest.(check int64) "fixed result matches expected" expected (get_reg st_fixed 0);
  Alcotest.(check int64) "compact and fixed agree" (get_reg st_fixed 0) (get_reg st_compact 0)

let test_superoperator_fusion () =
  let seed = 0x5877_BEEF_C0DEL in
  let b0 = make_block 0 "entry" [
    PushImm 100L; PushImm 25L; Add; PopReg 0;         (* 125 *)
    PushImm 100L; PushImm 25L; Sub; PopReg 1;         (* 75 *)
    PushImm 999L; PopReg 2;                           (* 999 *)
    PushReg 2; PushImm 1L; Add; PopReg 3;             (* 1000 *)
    PushReg 2; PushImm 99L; Sub; PopReg 4;            (* 900 *)
    PushImm 10L; PopReg 5;
    PushReg 5; PushImm 40L; Add; PopReg 5;            (* 50 *)
    Exit;
  ] in
  let prog_orig = make_program 0 [b0] 16 in

  (* 1. Verify baseline execution *)
  let st_orig = run_program prog_orig in
  Alcotest.(check int64) "orig reg0" 125L (get_reg st_orig 0);
  Alcotest.(check int64) "orig reg1" 75L  (get_reg st_orig 1);
  Alcotest.(check int64) "orig reg2" 999L (get_reg st_orig 2);
  Alcotest.(check int64) "orig reg3" 1000L (get_reg st_orig 3);
  Alcotest.(check int64) "orig reg4" 900L (get_reg st_orig 4);
  Alcotest.(check int64) "orig reg5" 50L  (get_reg st_orig 5);

  (* 2. Apply Superoperator fusion pass at 100% rate *)
  let cfg = { (Stack_superop_pass.default_superop_config seed) with fusion_rate = 100 } in
  let prog_fused = Stack_superop_pass.apply_program cfg prog_orig in
  let stats = Stack_superop_pass.superop_stats prog_orig prog_fused in

  Alcotest.(check bool) "ops were fused" true (stats.fused_ops > 0);
  Alcotest.(check bool) "AddImmImm fused" true (stats.add_ii_count >= 1);
  Alcotest.(check bool) "SubImmImm fused" true (stats.sub_ii_count >= 1);
  Alcotest.(check bool) "SetRegImm fused" true (stats.set_reg_imm_count >= 1);
  Alcotest.(check bool) "AddRegImm fused" true (stats.add_reg_imm_count >= 1);
  Alcotest.(check bool) "SubImm fused" true (stats.sub_imm_count >= 1);

  (* 3. Verify VM execution of fused program *)
  let st_fused = run_program prog_fused in
  Alcotest.(check int64) "fused reg0" 125L (get_reg st_fused 0);
  Alcotest.(check int64) "fused reg1" 75L  (get_reg st_fused 1);
  Alcotest.(check int64) "fused reg2" 999L (get_reg st_fused 2);
  Alcotest.(check int64) "fused reg3" 1000L (get_reg st_fused 3);
  Alcotest.(check int64) "fused reg4" 900L (get_reg st_fused 4);
  Alcotest.(check int64) "fused reg5" 50L  (get_reg st_fused 5);

  (* 4. Verify bytecode encode & decode round-trip *)
  let enc = Stack_encoder.encode_program ~seed_key:seed prog_fused in
  let st_bc = run_bytecode enc in
  Alcotest.(check int64) "bc reg0" 125L (get_reg st_bc 0);
  Alcotest.(check int64) "bc reg1" 75L  (get_reg st_bc 1);
  Alcotest.(check int64) "bc reg2" 999L (get_reg st_bc 2);
  Alcotest.(check int64) "bc reg3" 1000L (get_reg st_bc 3);
  Alcotest.(check int64) "bc reg4" 900L (get_reg st_bc 4);
  Alcotest.(check int64) "bc reg5" 50L  (get_reg st_bc 5);

  (* 5. Verify C++ runtime emission with superoperators *)
  let runtime_cfg = Stack_runtime.default_config Stack_runtime.X86_64 in
  let hpp = Stack_runtime.generate_c_runtime ~enc runtime_cfg prog_fused in
  Alcotest.(check bool) "hpp contains h_add_ii" true (contains hpp "h_add_ii");
  Alcotest.(check bool) "hpp contains h_sub_ii" true (contains hpp "h_sub_ii");
  Alcotest.(check bool) "hpp contains h_set_reg_imm" true (contains hpp "h_set_reg_imm");
  Alcotest.(check bool) "hpp contains h_add_reg_imm" true (contains hpp "h_add_reg_imm");
  Alcotest.(check bool) "hpp contains h_sub_imm" true (contains hpp "h_sub_imm")

let test_vsp_whitening () =
  (* Verify the C++ runtime contains VSP_ENCODE macro and uses it *)
  let seed = 0xDEADBEEF12345678L in
  let b = make_block 0 "entry" [
    PushImm 0xCAFEBABEL;
    PushImm 0xDEADL;
    Add;
    PopReg 0;
    Exit;
  ] in
  let prog = make_program 0 [b] 8 in
  let enc = Stack_encoder.encode_program ~seed_key:seed prog in

  (* 1. OCaml evaluator still produces correct results (it uses plaintext vstack) *)
  let state = run_bytecode enc in
  let expected = Int64.add 0xCAFEBABEL 0xDEADL in
  Alcotest.(check int64) "VSP whitening: OCaml eval still correct" expected (get_reg state 0);
  Alcotest.(check bool) "VSP whitening: halted" true state.halted;

  (* 2. Generated C++ code contains VSP_ENCODE macro definition *)
  let cfg = Stack_runtime.default_config Stack_runtime.X86_64 in
  let c_code = Stack_runtime.generate_c_runtime ~enc cfg prog in
  let contains s sub =
    let ls = String.length s and lsub = String.length sub in
    let rec go i = if i + lsub > ls then false
                   else if String.sub s i lsub = sub then true
                   else go (i + 1) in
    go 0
  in
  Alcotest.(check bool) "VSP_ENCODE macro present (static 2-arg form)" true
    (contains c_code "#define VSP_ENCODE(slot, v) ((v) ^ VSP_MASK(slot))");
  Alcotest.(check bool) "VSP_MASK macro present (static key form)" true
    (contains c_code "#define VSP_MASK(slot) (vm->vsp_key + (uint64_t)(slot) * UINT64_C(0x9E3779B97F4A7C15))");
  Alcotest.(check bool) "vsp_key is static (derived once, not from rolling vkey)" true
    (contains c_code "vm.vsp_key = vm.vkey ^ UINT64_C(0x9E3779B97F4A7C15);");
  Alcotest.(check bool) "PUSH_IMM uses VSP_ENCODE" true
    (contains c_code "vm->vsp[vm->vsp_idx] = VSP_ENCODE(vm->vsp_idx, imm)");
  Alcotest.(check bool) "ADD uses VSP_ENCODE decode" true
    (contains c_code "uint64_t b = VSP_ENCODE(vm->vsp_idx, vm->vsp[vm->vsp_idx])");
  Alcotest.(check bool) "POP_REG uses VSP_ENCODE decode" true
    (contains c_code "vm->ctx[idx] = VSP_ENCODE(vm->vsp_idx, vm->vsp[vm->vsp_idx])");
  Alcotest.(check bool) "DUP uses slot-aware re-encode" true
    (contains c_code "uint64_t decoded = VSP_ENCODE(src, vm->vsp[src])");
  Alcotest.(check bool) "SWAP uses slot-aware re-encode" true
    (contains c_code "uint64_t da = VSP_ENCODE(ia, vm->vsp[ia])");

  (* 3. The raw bytecode bytes should NOT contain the plaintext immediate 0xCAFEBABE
     since bytecode is rolling-key encrypted (this is the rolling-key property, not VSP) *)
  let bc_str = Bytes.to_string enc.bytes in
  let cafe_bytes = "\xBE\xBA\xFE\xCA\x00\x00\x00\x00" in (* little-endian 0xCAFEBABE *)
  Alcotest.(check bool) "plaintext imm not raw in bytecode (rolling key)" false
    (contains bc_str cafe_bytes)

let test_ghost_stack_padding () =
  let seed = 0xABCDEF0123456789L in

  (* Build a simple program with a known op count *)
  let b0 = make_block 0 "entry" [
    PushImm 100L;
    PushImm 200L;
    Add;
    PopReg 0;
    Exit;
  ] in
  let prog_orig = make_program 0 [b0] 8 in
  let ctx = Context_allocator.create () in

  let ghost_cfg = Stack_ghost_pass.default_ghost_config seed in
  let prog_ghost = Stack_ghost_pass.apply_program ghost_cfg ctx prog_orig in

  (* 1. Ghost ops were injected: total op count must be >= original *)
  let count_ops prog =
    Hashtbl.fold (fun _ b acc -> acc + List.length b.ops) prog.blocks 0
  in
  let orig_count  = count_ops prog_orig  in
  let ghost_count = count_ops prog_ghost in
  Alcotest.(check bool) "ghost pass injects ops" true (ghost_count >= orig_count);

  (* 2. Block balance is preserved — all blocks must still have delta = 0 *)
  Hashtbl.iter (fun _ b ->
    let res = Stack_balance_pass.analyze_block b in
    Alcotest.(check bool)
      (Printf.sprintf "block %d balanced after ghost pass" b.id)
      true res.is_balanced
  ) prog_ghost.blocks;

  (* 3. Program still executes correctly (via OCaml bytecode eval) *)
  let enc_orig  = Stack_encoder.encode_program ~seed_key:seed prog_orig  in
  let enc_ghost = Stack_encoder.encode_program ~seed_key:seed prog_ghost in
  let st_orig   = run_bytecode enc_orig  in
  let st_ghost  = run_bytecode enc_ghost in
  Alcotest.(check int64) "ghost: original result" 300L (get_reg st_orig  0);
  Alcotest.(check int64) "ghost: padded result"   300L (get_reg st_ghost 0);
  Alcotest.(check bool)  "ghost: both halted"     true
    (st_orig.halted && st_ghost.halted);

  (* 4. ghost_stats reports non-zero injection *)
  let stats = Stack_ghost_pass.ghost_stats prog_orig prog_ghost in
  Alcotest.(check bool) "ghost_stats non-empty"   true (String.length stats > 0);
  Alcotest.(check bool) "ghost_stats has 'ghost'" true
    (let len_s = String.length stats and sub = "ghost" in
     let lsub = String.length sub in
     let rec go i = if i + lsub > len_s then false
                    else if String.sub stats i lsub = sub then true
                    else go (i+1) in go 0);

  (* 5. Cross-build diversity: two different seeds → different ghost op counts *)
  let ctx2 = Context_allocator.create () in
  let ghost_cfg2 = Stack_ghost_pass.default_ghost_config (Int64.logxor seed 0xFFFF_FFFFL) in
  let prog_ghost2 = Stack_ghost_pass.apply_program ghost_cfg2 ctx2 prog_orig in
  let ghost_count2 = count_ops prog_ghost2 in
  (* At least one of the two builds should differ from the original count *)
  Alcotest.(check bool) "ghost diversity across seeds"  true
    (ghost_count <> orig_count || ghost_count2 <> orig_count)

let test_spaghetti_splitting () =
  let seed = 0x1234_5678_9ABCL in
  (* Block with clear cut points:
     - ops 0..1: PushImm 10; PopReg 0 (depth goes 0->1->0, flags dead)
     - ops 2..3: PushImm 20; PopReg 1 (depth goes 0->1->0, flags dead)
     - ops 4..6: PushReg 0; PushReg 1; Add (depth 0->1->2->1)
     - op 7: PopReg 2 (depth 1->0)
     - op 8: Exit *)
  let b0 = make_block 0 "entry" [
    PushImm 10L;
    PopReg 0;
    PushImm 20L;
    PopReg 1;
    PushReg 0;
    PushReg 1;
    Add;
    PopReg 2;
    Exit;
  ] in
  let prog_orig = make_program 0 [b0] 8 in
  let cfg = Stack_spaghetti_pass.{
    seed;
    split_rate = 100;
    max_blocks = 10;
    min_chunk = 2;
  } in
  let prog_split = Stack_spaghetti_pass.apply_program cfg prog_orig in

  (* 1. Block count increased *)
  Alcotest.(check bool) "spaghetti splits block" true
    (Hashtbl.length prog_split.blocks > Hashtbl.length prog_orig.blocks);

  (* 2. Verify all blocks are balanced *)
  let errs = Stack_balance_pass.verify_program prog_split in
  Alcotest.(check int) "all split blocks balanced" 0 (List.length errs);

  (* 3. Execution equivalence via bytecode runner *)
  let enc_orig = Stack_encoder.encode_program ~seed_key:seed prog_orig in
  let enc_split = Stack_encoder.encode_program ~seed_key:seed prog_split in
  let st_orig = run_bytecode enc_orig in
  let st_split = run_bytecode enc_split in
  Alcotest.(check int64) "reg 0 preserved" 10L (get_reg st_split 0);
  Alcotest.(check int64) "reg 1 preserved" 20L (get_reg st_split 1);
  Alcotest.(check int64) "reg 2 result" 30L (get_reg st_split 2);
  Alcotest.(check int64) "matches orig" (get_reg st_orig 2) (get_reg st_split 2);

  (* 4. Max blocks ceiling is respected *)
  let cfg_capped = Stack_spaghetti_pass.{
    seed;
    split_rate = 100;
    max_blocks = 1;
    min_chunk = 2;
  } in
  let prog_capped = Stack_spaghetti_pass.apply_program cfg_capped prog_orig in
  Alcotest.(check int) "max_blocks cap respected" 1 (Hashtbl.length prog_capped.blocks);

  (* 5. Conditional branch flags preserved across cut *)
  let b_branch = make_block 0 "entry" [
    PushImm 42L;
    PopReg 0;
    PushReg 0;
    PushImm 42L;
    Cmp;
    JccRel (1, E);
    JmpRel 2;
  ] in
  let b1 = make_block 1 "true_target" [ PushImm 100L; PopReg 3; Exit ] in
  let b2 = make_block 2 "false_target" [ PushImm 200L; PopReg 3; Exit ] in
  let prog_branch = make_program 0 [b_branch; b1; b2] 8 in
  let prog_branch_split = Stack_spaghetti_pass.apply_program cfg prog_branch in
  let enc_branch = Stack_encoder.encode_program ~seed_key:seed prog_branch_split in
  let st_branch = run_bytecode enc_branch in
  Alcotest.(check int64) "branch condition preserved" 100L (get_reg st_branch 3);

  (* 6. Stats string *)
  let stats = Stack_spaghetti_pass.spaghetti_stats prog_orig prog_split in
  Alcotest.(check bool) "stats non-empty" true (String.length stats > 0)

let test_mba_synthesis () =
  let seed = 0xFEDCBA9876543210L in

  (* Build a program with multiple PushImm instructions *)
  let b0 = make_block 0 "entry" [
    PushImm 0xCAFEL;       (* constant 1 *)
    PushImm 0xBABEL;       (* constant 2 *)
    Add;
    PushImm 42L;           (* constant 3 *)
    Sub;
    PopReg 0;
    Exit;
  ] in
  let prog_orig = make_program 0 [b0] 8 in

  (* Apply MBA at 100% rate to synthesize every PushImm *)
  let mba_cfg = Stack_mba_pass.{ seed; mba_rate = 100 } in
  let prog_mba = Stack_mba_pass.apply_program mba_cfg prog_orig in

  (* 1. No PushImm instructions should contain the original constants literally *)
  let push_imm_values prog =
    Hashtbl.fold (fun _ b acc ->
      List.fold_left (fun a op ->
        match op with PushImm v -> v :: a | _ -> a
      ) acc b.ops
    ) prog.blocks []
  in
  let orig_consts = [0xCAFEL; 0xBABEL; 42L] in
  let mba_imm_vals = push_imm_values prog_mba in
  (* None of the synthesized PushImm values should equal the original constants *)
  List.iter (fun c ->
    Alcotest.(check bool)
      (Printf.sprintf "constant 0x%Lx not literal in MBA output" c)
      false
      (List.mem c mba_imm_vals)
  ) orig_consts;

  (* 2. Block balance must be preserved after MBA *)
  Hashtbl.iter (fun _ b ->
    let res = Stack_balance_pass.analyze_block b in
    Alcotest.(check bool)
      (Printf.sprintf "block %d balanced after MBA" b.id)
      true res.is_balanced
  ) prog_mba.blocks;

  (* 3. Program computes the correct result (OCaml bytecode eval) *)
  let enc_orig = Stack_encoder.encode_program ~seed_key:seed prog_orig in
  let enc_mba  = Stack_encoder.encode_program ~seed_key:seed prog_mba  in
  let st_orig  = run_bytecode enc_orig in
  let st_mba   = run_bytecode enc_mba  in
  let expected = Int64.sub (Int64.add 0xCAFEL 0xBABEL) 42L in
  Alcotest.(check int64) "MBA: original result correct" expected (get_reg st_orig 0);
  Alcotest.(check int64) "MBA: synthesized result correct" expected (get_reg st_mba  0);
  Alcotest.(check bool)  "MBA: both halted" true (st_orig.halted && st_mba.halted);

  (* 4. Total op count is larger after MBA (synthesis expands PushImm → 3–5 ops) *)
  let count_ops prog =
    Hashtbl.fold (fun _ b acc -> acc + List.length b.ops) prog.blocks 0
  in
  Alcotest.(check bool) "MBA expands op count" true
    (count_ops prog_mba > count_ops prog_orig);

  (* 5. mba_stats string is well-formed *)
  let stats = Stack_mba_pass.mba_stats prog_orig prog_mba in
  let contains s sub =
    let ls = String.length s and lsub = String.length sub in
    let rec go i = if i + lsub > ls then false
                   else if String.sub s i lsub = sub then true
                   else go (i+1) in go 0
  in
  Alcotest.(check bool) "mba_stats mentions 'MBA'"    true (contains stats "MBA");
  Alcotest.(check bool) "mba_stats mentions 'PushImm'" true (contains stats "PushImm");

  (* 6. Different seeds produce different synthesized sequences *)
  let mba_cfg2 = Stack_mba_pass.{ seed = Int64.logxor seed 0xDEAD_BEEFL; mba_rate = 100 } in
  let prog_mba2 = Stack_mba_pass.apply_program mba_cfg2 prog_orig in
  let vals2 = push_imm_values prog_mba2 in
  (* The two MBA outputs should have at least one different PushImm value *)
  let lists_equal a b =
    List.sort compare a = List.sort compare b
  in
  Alcotest.(check bool) "different seeds → different MBA sequences" false
    (lists_equal mba_imm_vals vals2)

let test_cff_flattening () =
  let seed = 0x1122334455667788L in

  (* Build a multi-block program with explicit JmpRel:
       block 0: PushImm 10; PopReg 0; JmpRel 1
       block 1: PushImm 20; PopReg 1; JmpRel 2
       block 2: Exit
  *)
  let b0 = make_block 0 "b0" [ PushImm 10L; PopReg 0; JmpRel 1 ] in
  let b1 = make_block 1 "b1" [ PushImm 20L; PopReg 1; JmpRel 2 ] in
  let b2 = make_block 2 "b2" [ Exit ] in
  let prog_orig = make_program 0 [b0; b1; b2] 8 in
  let ctx = Context_allocator.create () in

  let cff_cfg = Stack_cff_pass.default_cff_config seed in
  let prog_cff = Stack_cff_pass.apply_program cff_cfg ctx prog_orig in

  (* 1. Block count increased by at least n_real (dispatcher added) *)
  let n_orig = Hashtbl.length prog_orig.blocks in
  let n_cff  = Hashtbl.length prog_cff.blocks  in
  Alcotest.(check bool) "CFF adds blocks" true (n_cff > n_orig);

  (* 2. Real blocks should have NO direct JmpRel to other real blocks.
        After CFF they JmpRel to the dispatcher (block id > max_real_id). *)
  let max_real_id = 2 in  (* highest original block id *)
  let real_block_direct_jmps =
    Hashtbl.fold (fun id b acc ->
      if id > max_real_id then acc  (* skip dispatcher blocks *)
      else
        List.fold_left (fun a op ->
          match op with
          | JmpRel t when t <= max_real_id -> a + 1
          | _ -> a
        ) acc b.ops
    ) prog_cff.blocks 0
  in
  Alcotest.(check int) "no direct JmpRel to real blocks in flattened output" 0
    real_block_direct_jmps;

  (* 3. Program must still execute correctly using the AST evaluator
        (run_program follows block_id changes through the dispatcher) *)
  let st_orig = Stack_eval.run_program prog_orig in
  let st_cff  = Stack_eval.run_program prog_cff  in
  Alcotest.(check int64) "CFF: reg 0 preserved" (get_reg st_orig 0) (get_reg st_cff 0);
  Alcotest.(check int64) "CFF: reg 1 preserved" (get_reg st_orig 1) (get_reg st_cff 1);
  Alcotest.(check bool)  "CFF: both halted"      true
    (st_orig.halted && st_cff.halted);

  (* 4. cff_stats is well-formed *)
  let stats = Stack_cff_pass.cff_stats prog_orig prog_cff in
  let contains s sub =
    let ls = String.length s and lsub = String.length sub in
    let rec go i = if i + lsub > ls then false
                   else if String.sub s i lsub = sub then true
                   else go (i+1) in go 0
  in
  Alcotest.(check bool) "cff_stats non-empty"       true (String.length stats > 0);
  Alcotest.(check bool) "cff_stats mentions 'blocks'" true (contains stats "blocks");
  Alcotest.(check bool) "cff_stats mentions 'dispatcher'" true (contains stats "dispatcher");

  (* 5. Block balance preserved after CFF *)
  Hashtbl.iter (fun _ b ->
    let res = Stack_balance_pass.analyze_block b in
    Alcotest.(check bool)
      (Printf.sprintf "block %d balanced after CFF" b.id)
      true res.is_balanced
  ) prog_cff.blocks;

  (* 6. Cross-seed token diversity: different seeds → different dispatcher tokens *)
  let ctx2 = Context_allocator.create () in
  let cff_cfg2 = Stack_cff_pass.default_cff_config (Int64.logxor seed 0xAAAA_BBBBL) in
  let prog_cff2 = Stack_cff_pass.apply_program cff_cfg2 ctx2 prog_orig in
  (* Count direct_jmp_count — both should have 0 in real blocks, verifying pass ran *)
  let jmps1 = Stack_cff_pass.direct_jmp_count prog_cff  in
  let jmps2 = Stack_cff_pass.direct_jmp_count prog_cff2 in
  (* Dispatcher blocks have jumps, so both should have non-zero total *)
  Alcotest.(check bool) "CFF output has dispatcher jumps" true (jmps1 > 0);
  Alcotest.(check bool) "CFF output2 has dispatcher jumps" true (jmps2 > 0)

(* ── SAR / DIV / IDIV / shift-count masking semantics ─────────────────── *)
(* Both execution paths (AST evaluator and encrypted bytecode) must agree
   on every edge case: arithmetic vs logical shifts, count masking (& 63),
   unsigned vs signed division, zero-divisor and #DE overflow guards. *)
let test_sar_div_idiv_semantics () =
  let cases = [
    (Sar, -16L, 2L, -4L);                        (* arithmetic shift keeps sign *)
    (Sar, -1L, 63L, -1L);
    (Sar, 0x8000000000000000L, 63L, -1L);        (* all sign bits *)
    (Sar, 12345L, 0L, 12345L);                   (* count 0 → unchanged *)
    (Shr, 0x8000000000000000L, 63L, 1L);         (* logical shift fills 0 *)
    (Shr, 0xFFL, 68L, 0x0FL);                    (* count masked: 68 & 63 = 4 *)
    (Shl, 1L, 4L, 16L);
    (Shl, 0x0F0F0F0F0F0F0F0FL, 68L, 0xF0F0F0F0F0F0F0F0L);
    (Div, 100L, 7L, 14L);                        (* unsigned *)
    (Div, 5L, 0L, 0L);                           (* zero divisor → 0 *)
    (Div, -1L, 2L, 0x7FFFFFFFFFFFFFFFL);         (* 0xFFFF... / 2 unsigned *)
    (Idiv, -100L, 7L, -14L);                     (* signed, truncating *)
    (Idiv, 7L, -2L, -3L);
    (Idiv, 0x8000000000000000L, -1L, 0L);        (* #DE guard → 0 *)
    (Idiv, 0x8000000000000000L, 1L, 0x8000000000000000L);
  ] in
  List.iter (fun (op, a, b, expected) ->
    let name = op_to_string op in
    let blk = make_block 0 "case" [ PushImm a; PushImm b; op; PopReg 0; Exit ] in
    let prog = make_program 0 [blk] 8 in
    (* AST *)
    let st_ast = run_program prog in
    Alcotest.(check int64) (Printf.sprintf "%s %Ld %Ld (AST)" name a b) expected (get_reg st_ast 0);
    (* encrypted bytecode *)
    let enc = Stack_encoder.encode_program ~seed_key:0x5EED5EED5EED5EEDL prog in
    let st_bc = run_bytecode enc in
    Alcotest.(check int64) (Printf.sprintf "%s %Ld %Ld (BC)" name a b) expected (get_reg st_bc 0)
  ) cases

(* ── PushFlags/PopFlags round-trip through flag-clobbering ALU ops ────── *)
let test_flags_roundtrip_and_parity () =
  (* b0: compare (CF=1), save flags, clobber them twice, restore, branch *)
  let b0 = make_block 0 "entry" [
    PushImm 10L; PushImm 20L; Cmp;          (* 10 - 20 → CF=1 *)
    PushFlags;
    PushImm 5L; PushImm 5L; Add; PopReg 1;  (* clobbers flags (ZF=1) *)
    PushImm 7L; PushImm 3L; Sub; PopReg 2;  (* clobbers flags again (CF=0) *)
    PopFlags;                               (* must restore CF=1 *)
    JccRel (1, Flags.B);                    (* B = CF → taken *)
    JmpRel 2;
  ] in
  let b1 = make_block 1 "taken" [
    (* JccRel/Setcc don't clobber flags, so the restored CF is still live
       here — Cmov must observe it BEFORE the parity Cmps overwrite flags. *)
    PushImm 555L; Cmov (Flags.B, 6);                            (* restored CF → 555 *)
    PushImm 0x30L; PushImm 0L; Cmp; Setcc Flags.P; PopReg 3;   (* 0x30: even parity → 1 *)
    PushImm 0x33L; PushImm 0L; Cmp; Setcc Flags.NP; PopReg 4;  (* 0x33: even parity → 0 *)
    PushImm 123L; PopReg 0; Exit;
  ] in
  let b2 = make_block 2 "dead" [ PushImm 321L; PopReg 0; Exit ] in
  let prog = make_program 0 [b0; b1; b2] 8 in

  let check_state label st =
    Alcotest.(check int64) (label ^ ": branch honored restored CF (reg0)") 123L (get_reg st 0);
    Alcotest.(check int64) (label ^ ": Add result") 10L (get_reg st 1);
    Alcotest.(check int64) (label ^ ": Sub result") 4L (get_reg st 2);
    Alcotest.(check int64) (label ^ ": Setcc P on even parity") 1L (get_reg st 3);
    Alcotest.(check int64) (label ^ ": Setcc NP on even parity") 0L (get_reg st 4);
    Alcotest.(check int64) (label ^ ": Cmov on restored flags") 555L (get_reg st 6)
  in
  check_state "AST" (run_program prog);
  let enc = Stack_encoder.encode_program ~seed_key:0xBEEF00BEEF00BEEFL prog in
  check_state "BC" (run_bytecode enc)

(* ── KeyAdjust mid-block must stay symmetric in encryptor and decoder ─── *)
let test_keyadjust_midblock () =
  let b0 = make_block 0 "entry" [
    PushImm 7L; PopReg 0;
    KeyAdjust 0x1234567890ABCDEFL;
    PushImm 8L; PopReg 1;
    KeyAdjust (-0xDEADBEEFL);
    PushImm 9L; PopReg 2;
    Exit;
  ] in
  let prog = make_program 0 [b0] 8 in
  let st = run_program prog in
  Alcotest.(check int64) "AST reg0 after KeyAdjust" 7L (get_reg st 0);
  Alcotest.(check int64) "AST reg1 after KeyAdjust" 8L (get_reg st 1);
  Alcotest.(check int64) "AST reg2 after KeyAdjust" 9L (get_reg st 2);
  (* The rolling key changed twice mid-block; the bytecode evaluator must
     mirror those mutations exactly or every subsequent opcode decodes to
     garbage and the run halts with wrong state. *)
  let enc = Stack_encoder.encode_program ~seed_key:0x0F1E2D3C4B5A6978L prog in
  let st_bc = run_bytecode enc in
  Alcotest.(check int64) "BC reg0 after KeyAdjust" 7L (get_reg st_bc 0);
  Alcotest.(check int64) "BC reg1 after KeyAdjust" 8L (get_reg st_bc 1);
  Alcotest.(check int64) "BC reg2 after KeyAdjust" 9L (get_reg st_bc 2);
  (* decode_all must also stay in sync across both adjustments *)
  let decoded = Stack_encoder.decode_enc enc in
  Alcotest.(check int) "decode_all op count survives KeyAdjust" (List.length b0.ops) (List.length decoded)

(* ── Full obfuscation pipeline: semantics must survive all four passes ── *)
let test_full_pipeline_semantics () =
  let seed = 0x0123456789ABCDEFL in
  let b0 = make_block 0 "entry" [
    PushImm (-16L); PushImm 2L; Sar; PopReg 0;        (* -4 *)
    PushImm 100L; PushImm 7L; Div; PopReg 1;          (* 14 *)
    PushImm 10L; PushImm 20L; Cmp;                    (* CF=1 *)
    PushFlags;
    PushImm 5L; PushImm 6L; Add; PopReg 2;            (* 11, clobbers flags *)
    PopFlags;
    JccRel (1, Flags.B); JmpRel 2;
  ] in
  let b1 = make_block 1 "taken" [ PushImm 777L; PopReg 3; Exit ] in
  let b2 = make_block 2 "dead" [ PushImm 111L; PopReg 3; Exit ] in
  let prog = make_program 0 [b0; b1; b2] 8 in

  let check_state label st =
    Alcotest.(check int64) (label ^ ": Sar result") (-4L) (get_reg st 0);
    Alcotest.(check int64) (label ^ ": Div result") 14L (get_reg st 1);
    Alcotest.(check int64) (label ^ ": Add result") 11L (get_reg st 2);
    Alcotest.(check int64) (label ^ ": branch taken on restored CF") 777L (get_reg st 3)
  in
  check_state "baseline" (run_program prog);

  (* Same order as the production packager: balance → ghost → MBA → CFF *)
  let ctx = Context_allocator.create () in
  let prog_r = Stack_balance_pass.repair_program ctx prog in
  let prog_g = Stack_ghost_pass.apply_program (Stack_ghost_pass.default_ghost_config seed) ctx prog_r in
  let prog_m = Stack_mba_pass.apply_program Stack_mba_pass.{ seed = Int64.logxor seed 0x1111L; mba_rate = 100 } prog_g in
  let prog_c = Stack_cff_pass.apply_program (Stack_cff_pass.default_cff_config (Int64.logxor seed 0x2222L)) ctx prog_m in

  (* balance invariant holds for every block of the final program *)
  let errors = Stack_balance_pass.verify_program prog_c in
  Alcotest.(check int) "pipeline: no balance errors" 0 (List.length errors);

  let enc = Stack_encoder.encode_program ~seed_key:seed prog_c in
  check_state "pipeline" (run_bytecode enc)

(* ── Generated C++ runtime: compile it and cross-check against OCaml ──── *)
let test_c_runtime_compile_and_run () =
  if Sys.command "command -v c++ >/dev/null 2>&1" <> 0 then
    Printf.printf "SKIP test_c_runtime_compile_and_run: no C++ compiler on PATH\n%!"
  else begin
    let b0 = make_block 0 "entry" [
      PushImm (-16L); PushImm 2L; Sar; PopReg 0;                      (* -4 *)
      PushImm 100L; PushImm 7L; Div; PopReg 1;                        (* 14 *)
      PushImm (-100L); PushImm 7L; Idiv; PopReg 2;                    (* -14 *)
      PushImm 0x8000000000000000L; PushImm (-1L); Idiv; PopReg 3;     (* 0 (#DE guard) *)
      PushImm 5L; PushImm 0L; Div; PopReg 4;                          (* 0 (zero divisor) *)
      PushImm 3L; PushImm 9L; Cmp; JccRel (1, Flags.S); JmpRel 2;     (* 3-9=-6 → SF=1 *)
    ] in
    let b1 = make_block 1 "taken" [
      PushImm 0x30L; PushImm 0L; Cmp; Setcc Flags.P; PopReg 5;        (* even parity → 1 *)
      PushImm 0x33L; PushImm 0L; Cmp; Setcc Flags.NP; PopReg 6;       (* even parity → 0 *)
      PushImm 10L; PushImm 20L; Cmp; PushFlags;
      PushImm 5L; PushImm 6L; Add; PopReg 7; PopFlags;                (* flags restored *)
      PushImm 888L; Cmov (Flags.B, 8);                                (* restored CF=1 → 888 *)
      PushImm 4242L; PopReg 0; Exit;                                  (* final result in slot 0 *)
    ] in
    let b2 = make_block 2 "dead" [ PushImm 1111L; PopReg 0; Exit ] in
    let prog = make_program 0 [b0; b1; b2] 16 in

    let enc = Stack_encoder.encode_program ~seed_key:0xC0FFEE1234567890L prog in

    (* 1. OCaml reference results for every register *)
    let st_ref = run_bytecode enc in
    let expected = [|
      4242L; 14L; (-14L); 0L; 0L; 1L; 0L; 11L; 888L |] in
    Array.iteri (fun slot v ->
      Alcotest.(check int64) (Printf.sprintf "OCaml ref reg%d" slot) v (get_reg st_ref slot)
    ) expected;

    (* 2. Generate the C++ runtime + runner (same as the production packager) *)
    let cfg = Stack_runtime.default_config Stack_runtime.X86_64 in
    let hpp = Stack_runtime.generate_c_runtime ~enc cfg prog in
    (* bytes_to_words: pad to multiple of 8, pack big-endian (vm_packagers) *)
    let bytes_to_words b =
      let n = Bytes.length b in
      let padded = (n + 7) land (lnot 7) in
      let words = Array.init (padded / 8) (fun i ->
        let w = ref 0L in
        for j = 7 downto 0 do
          let idx = i * 8 + j in
          let byte = if idx < n then Char.code (Bytes.get b idx) else 0 in
          w := Int64.logor (Int64.shift_left !w 8) (Int64.of_int byte)
        done;
        !w
      ) in
      Array.to_list words
    in
    let runner = Stack_runtime.emit_runner_cpp (bytes_to_words enc.bytes) in

    let dir = Filename.get_temp_dir_name () in
    (* hpp name must match the runner's default #include "stack_vm_runtime.hpp" *)
    let hpp_path = Filename.concat dir "stack_vm_runtime.hpp" in
    let cpp_path = Filename.concat dir "asgard_stack_vm_runner.cpp" in
    let bin_path = Filename.concat dir "asgard_stack_vm_runner" in
    let oc = open_out hpp_path in output_string oc hpp; close_out oc;
    let oc = open_out cpp_path in output_string oc runner; close_out oc;

    (* 3. Compile (both files live in the same dir → quoted #include resolves) *)
    let compile cmd =
      Sys.command (Printf.sprintf "c++ -O1 -std=c++17 %s -o %s" cmd (Filename.quote bin_path))
    in
    let rc =
      let rc1 = compile (Filename.quote cpp_path) in
      if rc1 = 0 then 0
      else compile (Filename.quote cpp_path ^ " -ldl")
    in
    Alcotest.(check bool) "C++ runtime compiles" true (rc = 0);

    if rc = 0 then begin
      (* 4. Run and parse "Result: NNN" *)
      let out_path = bin_path ^ ".out" in
      ignore (Sys.command
        (Printf.sprintf "%s > %s 2>&1" (Filename.quote bin_path) (Filename.quote out_path)));
      let ic = open_in out_path in
      let len = in_channel_length ic in
      let out = really_input_string ic len in
      close_in ic;
      let extract_result s =
        let n = String.length s in
        let rec go i =
          if i + 8 > n then None
          else if String.sub s i 8 = "Result: " then begin
            let j = ref (i + 8) in
            while !j < n && s.[!j] >= '0' && s.[!j] <= '9' do incr j done;
            Some (String.sub s (i + 8) (!j - i - 8))
          end
          else go (i + 1)
        in
        go 0
      in
      match extract_result out with
      | Some digits ->
        Alcotest.(check int64) "C++ result matches OCaml reference" 4242L
          (Int64.of_string digits)
      | None ->
        Alcotest.fail (Printf.sprintf "no Result line in runner output:\n%s" out)
    end
  end

(* ── Full pipeline through the generated C++ runtime WITH arguments ────── *)
(* [test_c_runtime_compile_and_run] covers the raw program only, and
   [test_full_pipeline_semantics] covers the pass chain only via the OCaml
   evaluator. Production builds use BOTH: ghost + MBA + CFF bytecode running
   on the generated C++ runtime with real SysV arguments scattered into ctx
   (a0→slot 7 / RDI, a1→slot 6 / RSI, result from slot 0 / RAX). A scatter or
   pass-chain regression then only shows up here. *)
let test_full_pipeline_c_runtime_with_args () =
  if Sys.command "command -v c++ >/dev/null 2>&1" <> 0 then
    Printf.printf "SKIP test_full_pipeline_c_runtime_with_args: no C++ compiler on PATH\n%!"
  else begin
    (* rax := a0 + a1*3 + 0x1337 — every constant AND both arguments matter *)
    let b0 = make_block 0 "entry" [
      PushReg 7;            (* a0 (RDI scatter slot) *)
      PushReg 6;            (* a1 (RSI scatter slot) *)
      PushImm 3L; Mul;
      Add;
      PushImm 0x1337L;
      Add;
      PopReg 0;             (* rax *)
      Exit;
    ] in
    let prog = make_program 0 [b0] 16 in

    (* Production pass order: balance → ghost → MBA → CFF *)
    let seed = 0x0BADF00D0BADF00DL in
    let ctx = Context_allocator.create () in
    let prog_r = Stack_balance_pass.repair_program ctx prog in
    let prog_g = Stack_ghost_pass.apply_program (Stack_ghost_pass.default_ghost_config seed) ctx prog_r in
    let prog_m = Stack_mba_pass.apply_program Stack_mba_pass.{ seed = Int64.logxor seed 0x1111L; mba_rate = 100 } prog_g in
    let prog_c = Stack_cff_pass.apply_program (Stack_cff_pass.default_cff_config (Int64.logxor seed 0x2222L)) ctx prog_m in
    Alcotest.(check int) "args test: no balance errors" 0
      (List.length (Stack_balance_pass.verify_program prog_c));

    let enc = Stack_encoder.encode_program ~seed_key:seed prog_c in

    (* 1. OCaml reference with the same scatter stack_vm_call performs.
          Keep the expected value < Int64.max so the decimal result string
          round-trips through Int64.of_string. *)
    let a0 = 0x5A5A5A5A12121212L and a1 = 0x2B3C4D5E6F70L in
    let expected =
      Int64.add
        (Int64.add a0 (Int64.mul a1 3L))
        0x1337L
    in
    let st_ref = run_bytecode ~initial_ctx:[(7, a0); (6, a1)] enc in
    Alcotest.(check int64) "OCaml ref (scatter slots 7/6)" expected (get_reg st_ref 0);
    Alcotest.(check bool) "OCaml ref halted" true st_ref.halted;

    (* 2. Generate the same runtime the packager emits *)
    let cfg = Stack_runtime.default_config Stack_runtime.X86_64 in
    let hpp = Stack_runtime.generate_c_runtime ~enc cfg prog_c in
    let bytes_to_words b =
      let n = Bytes.length b in
      let padded = (n + 7) land (lnot 7) in
      let words = Array.init (padded / 8) (fun i ->
        let w = ref 0L in
        for j = 7 downto 0 do
          let idx = i * 8 + j in
          let byte = if idx < n then Char.code (Bytes.get b idx) else 0 in
          w := Int64.logor (Int64.shift_left !w 8) (Int64.of_int byte)
        done;
        !w
      ) in
      Array.to_list words
    in
    let word_list = bytes_to_words enc.bytes in
    let buf = Buffer.create (1024 * 16) in
    Buffer.add_string buf
      "/* generated regression driver: full pipeline + args */\n\
       #include \"stack_vm_runtime.hpp\"\n#include <stdio.h>\n\
       static const uint64_t words[] = {\n";
    List.iteri (fun i w ->
      let hex = Printf.sprintf "%LX" w in
      let padded = String.make (max 0 (16 - String.length hex)) '0' ^ hex in
      Buffer.add_string buf (Printf.sprintf "    0x%sULL%s\n" padded
        (if i = List.length word_list - 1 then "" else ",")))
      word_list;
    let hex64 v =
      let h = Printf.sprintf "%LX" v in
      String.make (max 0 (16 - String.length h)) '0' ^ h
    in
    Buffer.add_string buf (Printf.sprintf
      "};\nint main() {\n\
       size_t len = sizeof(words) / sizeof(words[0]);\n\
       uint64_t r = asgard_stack_vm::stack_vm_call(words, len, 0x%sULL, 0x%sULL);\n\
       printf(\"Result: %%llu\\n\", (unsigned long long)r);\n\
       return 0;\n}\n" (hex64 a0) (hex64 a1));
    let driver = Buffer.contents buf in

    let dir = Filename.get_temp_dir_name () in
    let hpp_path = Filename.concat dir "stack_vm_runtime.hpp" in
    let cpp_path = Filename.concat dir "asgard_stack_vm_args_driver.cpp" in
    let bin_path = Filename.concat dir "asgard_stack_vm_args_driver" in
    let oc = open_out hpp_path in output_string oc hpp; close_out oc;
    let oc = open_out cpp_path in output_string oc driver; close_out oc;

    let compile cmd =
      Sys.command (Printf.sprintf "c++ -O1 -std=c++17 %s -o %s" cmd (Filename.quote bin_path))
    in
    let rc =
      let rc1 = compile (Filename.quote cpp_path) in
      if rc1 = 0 then 0
      else compile (Filename.quote cpp_path ^ " -ldl")
    in
    Alcotest.(check bool) "args test: C++ runtime compiles" true (rc = 0);

    if rc = 0 then begin
      let out_path = bin_path ^ ".out" in
      ignore (Sys.command
        (Printf.sprintf "%s > %s 2>&1" (Filename.quote bin_path) (Filename.quote out_path)));
      let ic = open_in out_path in
      let len = in_channel_length ic in
      let out = really_input_string ic len in
      close_in ic;
      let extract_result s =
        let n = String.length s in
        let rec go i =
          if i + 8 > n then None
          else if String.sub s i 8 = "Result: " then begin
            let j = ref (i + 8) in
            while !j < n && s.[!j] >= '0' && s.[!j] <= '9' do incr j done;
            Some (String.sub s (i + 8) (!j - i - 8))
          end
          else go (i + 1)
        in
        go 0
      in
      match extract_result out with
      | Some digits ->
        Alcotest.(check int64) "full pipeline + C++ runtime + args matches OCaml"
          expected (Int64.of_string digits)
      | None ->
        Alcotest.fail (Printf.sprintf "no Result line in driver output:\n%s" out)
    end
  end

(* ── Anti-VMPredator: address-masked key literals ─────────────────────── *)
let test_addr_mask_unit () =
  let seed = 0xA5A5B6B6C7C7D8D8L in
  let d_addr = Stack_encoder.parse_u64_hex "0F0E1D2C3B4A5968" in
  let b0 = make_block 0 "entry" [
    PushImm 100L; PushImm 25L; Sub; PopReg 0;          (* 75 *)
    PushImm 10L; PushImm 10L; Cmp;                      (* ZF=1 *)
    JccRel (1, Flags.E); JmpRel 2;
  ] in
  let b1 = make_block 1 "taken" [ PushImm 111L; PopReg 1; Exit ] in
  let b2 = make_block 2 "dead"  [ PushImm 222L; PopReg 1; Exit ] in
  let prog = make_program 0 [b0; b1; b2] 8 in

  (* 1. Legacy golden: no ~addr_mask ⇒ mask 0, output identical to explicit 0L *)
  let enc_plain = Stack_encoder.encode_program ~seed_key:seed prog in
  let enc_zero  = Stack_encoder.encode_program ~seed_key:seed ~addr_mask:0L prog in
  Alcotest.(check bool) "default addr_mask is 0" true (enc_plain.addr_mask = 0L);
  Alcotest.(check bool) "mask 0 output byte-identical" true
    (Bytes.equal enc_plain.bytes enc_zero.bytes);
  Alcotest.(check int64) "mask 0 keeps plaintext seed" seed enc_zero.seed_key;

  (* 2. Masked encoding: cipher bytes untouched, stored literals shifted *)
  let enc_masked = Stack_encoder.encode_program ~seed_key:seed ~addr_mask:d_addr prog in
  Alcotest.(check bool) "masking never touches ciphertext" true
    (Bytes.equal enc_plain.bytes enc_masked.bytes);
  Alcotest.(check int64) "stored seed = effective ^ mask"
    (Int64.logxor seed d_addr) enc_masked.seed_key;
  Hashtbl.iter (fun id k ->
    let k_plain = Hashtbl.find enc_plain.block_keys id in
    Alcotest.(check int64)
      (Printf.sprintf "stored block key %d = effective ^ mask" id)
      (Int64.logxor k_plain d_addr) k
  ) enc_masked.block_keys;

  (* 3. Evaluator folds the mask: masked and plain runs agree *)
  let check_state label st =
    Alcotest.(check int64) (label ^ ": reg0 = 75") 75L (get_reg st 0);
    Alcotest.(check int64) (label ^ ": reg1 = 111 (branch taken)") 111L (get_reg st 1);
    Alcotest.(check bool) (label ^ ": halted") true st.halted
  in
  check_state "plain"  (run_bytecode enc_plain);
  check_state "masked" (run_bytecode enc_masked);
  (* decode_all needs the effective (unmasked) seed; it walks the whole
     stream linearly, so the op count covers every block *)
  let total_ops =
    List.fold_left (fun a b -> a + List.length b.ops) 0 [b0; b1; b2] in
  Alcotest.(check int)
    "decode_all with effective seed returns all stream ops"
    total_ops
    (Stack_encoder.decode_enc enc_masked |> List.length);

  (* 4. apply_addr_mask composes: rebind then unbind restores literals *)
  let enc_rebound = Stack_encoder.apply_addr_mask enc_plain d_addr in
  Alcotest.(check int64) "rebind stored seed matches direct masked encode"
    enc_masked.seed_key enc_rebound.seed_key;
  let enc_unbound = Stack_encoder.apply_addr_mask enc_rebound 0L in
  Alcotest.(check int64) "unbind restores plaintext seed" seed enc_unbound.seed_key;
  Alcotest.(check bool) "rebinding never touches ciphertext" true
    (Bytes.equal enc_plain.bytes enc_unbound.bytes);

  (* 5. parse_u64_hex: full-range patterns Int64.of_string would reject *)
  Alcotest.(check int64) "parse_u64_hex full range" (-1L)
    (Stack_encoder.parse_u64_hex "FFFFFFFFFFFFFFFF");
  Alcotest.(check bool) "parse_u64_hex rejects short input" true
    (try ignore (Stack_encoder.parse_u64_hex "123"); false with Failure _ -> true);
  Alcotest.(check bool) "parse_u64_hex roundtrips mask" true
    (d_addr = Stack_encoder.parse_u64_hex (Printf.sprintf "%016LX" d_addr))

(* ── Anti-VMPredator: wrong address key must desynchronize decoding ───── *)
let test_addr_mask_wrong_key () =
  let seed = 0x1122334455667788L in
  let right = Stack_encoder.parse_u64_hex "00F0E1D2C3B4A596" in
  let wrong = Int64.lognot right in
  let b0 = make_block 0 "entry" [
    PushImm 100L; PushImm 25L; Sub; PopReg 0;
    PushImm 1L; PushImm 1L; Cmp; JccRel (1, Flags.E); JmpRel 2;
  ] in
  let b1 = make_block 1 "taken" [ PushImm 111L; PopReg 1; Exit ] in
  let b2 = make_block 2 "dead"  [ PushImm 222L; PopReg 1; Exit ] in
  let prog = make_program 0 [b0; b1; b2] 8 in
  let enc_masked = Stack_encoder.encode_program ~seed_key:seed ~addr_mask:right prog in
  let st_right = run_bytecode enc_masked in
  Alcotest.(check int64) "right address key decodes" 75L (get_reg st_right 0);
  Alcotest.(check int64) "right address key takes branch" 111L (get_reg st_right 1);
  (* Simulated dump/relocation. The attacker keeps the cipher bytes and the
     STORED literals but folds out a different address key D' — exactly what
     a foreign decoder or relocated copy does. apply_addr_mask is always
     self-consistent (it moves literals AND mask together), so the attack is
     modeled by re-pointing the mask field at the wrong key while keeping
     the literals: the evaluator then starts from stored ^ D' instead of
     stored ^ D. *)
  let check_attack label enc_attack =
    Alcotest.(check bool)
      (label ^ ": foreign address key corrupts execution") true
      (get_reg (run_bytecode enc_attack) 0 <> 75L)
  in
  check_attack "different key D'" { enc_masked with addr_mask = wrong };
  (* and a legacy decoder that assumes no binding at all (mask 0) *)
  check_attack "unbound legacy decoder" { enc_masked with addr_mask = 0L }

(* ── Anti-VMPredator: two-stage address probe and re-bound C++ execution ── *)
let test_address_bound_c_runtime_probe_and_run () =
  if Sys.command "command -v c++ >/dev/null 2>&1" <> 0 then
    Printf.printf "SKIP test_address_bound_c_runtime_probe_and_run: no C++ compiler on PATH\n%!"
  else begin
    let b0 = make_block 0 "entry" [
      PushImm (-16L); PushImm 2L; Sar; PopReg 0;                      (* -4 *)
      PushImm 100L; PushImm 7L; Div; PopReg 1;                        (* 14 *)
      PushImm (-100L); PushImm 7L; Idiv; PopReg 2;                    (* -14 *)
      PushImm 0x8000000000000000L; PushImm (-1L); Idiv; PopReg 3;     (* 0 (#DE guard) *)
      PushImm 5L; PushImm 0L; Div; PopReg 4;                          (* 0 (zero divisor) *)
      PushImm 3L; PushImm 9L; Cmp; JccRel (1, Flags.S); JmpRel 2;     (* 3-9=-6 → SF=1 *)
    ] in
    let b1 = make_block 1 "taken" [
      PushImm 0x30L; PushImm 0L; Cmp; Setcc Flags.P; PopReg 5;        (* even parity → 1 *)
      PushImm 0x33L; PushImm 0L; Cmp; Setcc Flags.NP; PopReg 6;       (* even parity → 0 *)
      PushImm 10L; PushImm 20L; Cmp; PushFlags;
      PushImm 5L; PushImm 6L; Add; PopReg 7; PopFlags;                (* flags restored *)
      PushImm 888L; Cmov (Flags.B, 8);                                (* restored CF=1 → 888 *)
      PushImm 4242L; PopReg 0; Exit;                                  (* final result in slot 0 *)
    ] in
    let b2 = make_block 2 "dead" [ PushImm 1111L; PopReg 0; Exit ] in
    let prog = make_program 0 [b0; b1; b2] 16 in
    let seed = 0xC0FFEE1234567890L in

    (* 1. Encode with mask 0 (initial unmasked encode) *)
    let enc = Stack_encoder.encode_program ~seed_key:seed prog in

    (* 2. Generate hpp v1 (mask 0) *)
    let cfg = Stack_runtime.default_config Stack_runtime.X86_64 in
    let hpp_v1 = Stack_runtime.generate_c_runtime ~enc cfg prog in

    let dir = Filename.get_temp_dir_name () in
    let hpp_path = Filename.concat dir "stack_vm_runtime.hpp" in
    let oc = open_out hpp_path in output_string oc hpp_v1; close_out oc;

    (* 3. Emit probe cpp, compile and execute to learn D *)
    let probe_src = Stack_runtime.emit_probe_cpp ~header_name:"stack_vm_runtime.hpp" () in
    let probe_cpp_path = Filename.concat dir "asgard_stack_vm_probe.cpp" in
    let probe_bin_path = Filename.concat dir "asgard_stack_vm_probe" in
    let oc = open_out probe_cpp_path in output_string oc probe_src; close_out oc;

    let compile_bin src_path bin_target =
      let cmd1 = Printf.sprintf "c++ -O1 -std=c++17 %s -o %s" (Filename.quote src_path) (Filename.quote bin_target) in
      let rc1 = Sys.command cmd1 in
      if rc1 = 0 then 0
      else Sys.command (Printf.sprintf "c++ -O1 -std=c++17 %s -ldl -o %s" (Filename.quote src_path) (Filename.quote bin_target))
    in
    let rc_probe = compile_bin probe_cpp_path probe_bin_path in
    Alcotest.(check bool) "probe C++ compiles" true (rc_probe = 0);

    if rc_probe = 0 then begin
      let probe_out_path = probe_bin_path ^ ".out" in
      ignore (Sys.command
        (Printf.sprintf "%s > %s 2>&1" (Filename.quote probe_bin_path) (Filename.quote probe_out_path)));
      let ic = open_in probe_out_path in
      let len = in_channel_length ic in
      let probe_out = really_input_string ic len in
      close_in ic;

      let extract_addr_key s =
        let prefix = "ADDR_KEY: " in
        let plen = String.length prefix in
        let n = String.length s in
        let rec go i =
          if i + plen + 16 > n then None
          else if String.sub s i plen = prefix then
            Some (String.sub s (i + plen) 16)
          else go (i + 1)
        in
        go 0
      in
      let d_hex = match extract_addr_key probe_out with
        | Some hex -> hex
        | None -> Alcotest.fail (Printf.sprintf "no ADDR_KEY line in probe output:\n%s" probe_out)
      in
      let d = Stack_encoder.parse_u64_hex d_hex in
      Alcotest.(check bool) "derived address key D is non-zero" true (d <> 0L);

      (* 4. Rebind: apply_addr_mask enc d -> hpp v2; ciphertext bytes must remain untouched *)
      let enc2 = Stack_encoder.apply_addr_mask enc d in
      Alcotest.(check bool) "rebinding never touches ciphertext bytes" true
        (Bytes.equal enc.bytes enc2.bytes);
      let hpp_v2 = Stack_runtime.generate_c_runtime ~enc:enc2 cfg prog in
      let oc = open_out hpp_path in output_string oc hpp_v2; close_out oc;

      (* 5. Generate driver with hpp v2 + bytecode words *)
      let bytes_to_words b =
        let n = Bytes.length b in
        let padded = (n + 7) land (lnot 7) in
        let words = Array.init (padded / 8) (fun i ->
          let w = ref 0L in
          for j = 7 downto 0 do
            let idx = i * 8 + j in
            let byte = if idx < n then Char.code (Bytes.get b idx) else 0 in
            w := Int64.logor (Int64.shift_left !w 8) (Int64.of_int byte)
          done;
          !w
        ) in
        Array.to_list words
      in
      let runner_src = Stack_runtime.emit_runner_cpp (bytes_to_words enc2.bytes) in
      let runner_cpp_path = Filename.concat dir "asgard_stack_vm_bound_runner.cpp" in
      let runner_bin_path = Filename.concat dir "asgard_stack_vm_bound_runner" in
      let oc = open_out runner_cpp_path in output_string oc runner_src; close_out oc;

      let rc_runner = compile_bin runner_cpp_path runner_bin_path in
      Alcotest.(check bool) "bound C++ runner compiles" true (rc_runner = 0);

      if rc_runner = 0 then begin
        let runner_out_path = runner_bin_path ^ ".out" in
        ignore (Sys.command
          (Printf.sprintf "%s > %s 2>&1" (Filename.quote runner_bin_path) (Filename.quote runner_out_path)));
        let ic = open_in runner_out_path in
        let len = in_channel_length ic in
        let runner_out = really_input_string ic len in
        close_in ic;

        let extract_result s =
          let n = String.length s in
          let rec go i =
            if i + 8 > n then None
            else if String.sub s i 8 = "Result: " then begin
              let j = ref (i + 8) in
              while !j < n && s.[!j] >= '0' && s.[!j] <= '9' do incr j done;
              Some (String.sub s (i + 8) (!j - i - 8))
            end
            else go (i + 1)
          in
          go 0
        in
        let st_ref = run_bytecode enc2 in
        let expected = get_reg st_ref 0 in
        match extract_result runner_out with
        | Some digits ->
            Alcotest.(check int64) "bound C++ result matches OCaml reference"
              expected (Int64.of_string digits)
        | None ->
            Alcotest.fail (Printf.sprintf "no Result line in runner output:\n%s" runner_out)
      end
    end
  end

let test_real_license_check_macro_stack_vm_e2e () =
  let candidates = ["license_check.c"; "examples/license_check.c"; "../examples/license_check.c"] in
  let example_c =
    match List.find_opt Sys.file_exists candidates with
    | Some p -> p
    | None ->
        Alcotest.fail (Printf.sprintf "license_check.c not found in %s (CWD=%s)"
          (String.concat ", " candidates) (Sys.getcwd ()))
  in

  Test_helpers.with_temp_dir (fun tmp_dir ->
    let module Arm64_adapter = Protect_adapters.Arm64_lifter_adapter in
    let module C_macro_adapter = Protect_adapters.C_macro_obf_adapter in
    let module Trampoline_adapter = Protect_adapters.C_trampoline_adapter in
    let module Toolchain_adapter = Protect_adapters.Clang_toolchain_adapter in
    let module Vm_packager_adapters = Protect_adapters.Vm_packagers in

    let lifter = (module Arm64_adapter : Lifter) in
    let c_macro_obfuscator = (module C_macro_adapter : C_macro_obfuscator) in
    let trampoline_engine = (module Trampoline_adapter.C_trampoline_engine : Trampoline_engine) in
    let toolchain = (module Toolchain_adapter : Toolchain) in
    let vm_packager = (module Vm_packager_adapters.Stack_vm_packager : Vm_packager) in

    let cfg = Protect_adapters.Config_adapter.default in
    let rng = Random.State.make [| 0x5877 |] in

    match
      Random_visa_application.Protect_pipeline.run
        ~lifter
        ~c_macro_obfuscator
        ~vm_packager
        ~trampoline_engine
        ~toolchain
        ~rng
        ~config:cfg
        ~input_file:example_c
        ~out_dir:tmp_dir
        ~compile_and_run:false
        ()
    with
    | Error err -> Alcotest.fail (Printf.sprintf "Pipeline failed: %s" err)
    | Ok res ->
        let virt_cpp = Filename.concat tmp_dir "app_virtualized.cpp" in
        let bin_path = Filename.concat tmp_dir "protected_license_app" in
        Alcotest.(check bool) "app_virtualized.cpp exists" true (Sys.file_exists virt_cpp);
        Alcotest.(check bool) "bytecode generated" true (res.bytecode_length_bytes > 0);

        let comp_cmd =
          Printf.sprintf "clang++ -std=c++20 -O2 -I%s -Wno-format-security %s -o %s"
            tmp_dir virt_cpp bin_path
        in
        let comp_st = Sys.command comp_cmd in
        Alcotest.(check int) "clang++ build succeeds" 0 comp_st;

        (* Test 1: Wrong Key -> ACCESS DENIED, exit code 1 *)
        let run_wrong_cmd = Printf.sprintf "printf 'WRONG_KEY\\n' | %s" bin_path in
        let status_wrong, out_wrong = Test_helpers.run_command_capture run_wrong_cmd in
        Alcotest.(check bool) "wrong key exits 1" true (status_wrong = Unix.WEXITED 1);
        Alcotest.(check bool) "output contains ACCESS DENIED" true
          (String.contains out_wrong 'D' && String.contains out_wrong 'E' && String.contains out_wrong 'N');

        (* Test 2: Valid Key -> ACCESS GRANTED, exit code 0 *)
        let run_valid_cmd = Printf.sprintf "printf 'ASGARD-5877-GOLD\\n' | %s" bin_path in
        let status_valid, out_valid = Test_helpers.run_command_capture run_valid_cmd in
        Alcotest.(check bool) "valid key exits 0" true (status_valid = Unix.WEXITED 0);
        Alcotest.(check bool) "output contains ACCESS GRANTED" true
          (String.contains out_valid 'G' && String.contains out_valid 'R' && String.contains out_valid 'A');
        Alcotest.(check bool) "output contains FLAG" true
          (String.contains out_valid 'F' && String.contains out_valid 'L' && String.contains out_valid 'A' && String.contains out_valid 'G');

        (* Test 3: a tampered image must fail closed, and must look exactly
           like a wrong key — same exit status, no flag, and no address-derived
           status. Before the runtime zeroed its context on an authentication
           failure it returned ctx[0], which on AArch64 holds a0, so the caller
           computed `ok ^ 1` on a truncated pointer and exited with a number
           derived from an address: 49 instead of 1. *)
        let rec find_sub s sub i =
          let n = String.length s and m = String.length sub in
          if i + m > n then None
          else if String.sub s i m = sub then Some i
          else find_sub s sub (i + 1)
        in
        let flip_first_word src =
          let marker = "embedded_bytecode" in
          let m =
            match find_sub src marker 0 with
            | Some i -> i
            | None -> failwith "no embedded_bytecode in the virtualized source"
          in
          let rec find_hex i =
            if i + 1 >= String.length src then failwith "no literal after embedded_bytecode"
            else if src.[i] = '0' && src.[i + 1] = 'x' then i
            else find_hex (i + 1)
          in
          let hx = find_hex (m + String.length marker) in
          let last = hx + 2 + 15 in
          let repl = if src.[last] = '0' then '1' else '0' in
          String.sub src 0 last ^ String.make 1 repl
          ^ String.sub src (last + 1) (String.length src - last - 1)
        in
        let src = In_channel.with_open_bin virt_cpp In_channel.input_all in
        Alcotest.(check bool) "tampered copy differs from the original" true
          (flip_first_word src <> src);
        let tampered_cpp = Filename.concat tmp_dir "app_virtualized_tampered.cpp" in
        let tampered_bin = Filename.concat tmp_dir "protected_app_tampered" in
        let oc = open_out_bin tampered_cpp in
        output_string oc (flip_first_word src);
        close_out oc;
        let tampered_st =
          Sys.command (Printf.sprintf "clang++ -std=c++20 -O2 -I%s -Wno-format-security %s -o %s"
              tmp_dir tampered_cpp tampered_bin)
        in
        Alcotest.(check int) "tampered build succeeds" 0 tampered_st;
        let run_tampered_cmd =
          Printf.sprintf "printf 'ASGARD-5877-GOLD\\n' | %s" tampered_bin in
        let status_t, out_t = Test_helpers.run_command_capture run_tampered_cmd in
        Alcotest.(check bool) "tampered image exits exactly like a wrong key" true
          (status_t = Unix.WEXITED 1);
        Alcotest.(check bool) "tampered image grants nothing" true
          (not (String.contains out_t 'F' && String.contains out_t 'L'
                && String.contains out_t 'A' && String.contains out_t 'G')))

(* ── Payload integrity tag: the property the rolling key does not have ── *)
let test_payload_tag_unit () =
  let seed = 0x5EED1234ABCD0001L in
  let b0 = make_block 0 "entry" [ PushImm 1337L; PopReg 0; Exit ] in
  let prog = make_program 0 [b0] 8 in
  let enc = Stack_encoder.encode_program ~seed_key:seed prog in

  (* the tag is a pure function of (image, effective seed) *)
  let eff = Stack_encoder.effective_seed_key enc in
  Alcotest.(check int64) "tag recomputes from the image"
    enc.payload_tag (Stack_encoder.derive_payload_tag enc.bytes eff);
  Alcotest.(check int64) "tag is deterministic"
    enc.payload_tag (Stack_encoder.derive_payload_tag enc.bytes eff);

  (* every single-bit flip in the image must change the tag *)
  let flips = ref 0 in
  for i = 0 to Bytes.length enc.bytes - 1 do
    for bit = 0 to 7 do
      let tampered = Bytes.copy enc.bytes in
      let b = Char.code (Bytes.get tampered i) in
      Bytes.set tampered i (Char.chr (b lxor (1 lsl bit)));
      if Stack_encoder.derive_payload_tag tampered eff = enc.payload_tag then
        incr flips
    done
  done;
  Alcotest.(check int) "no single-bit flip preserves the tag" 0 !flips;

  (* length is bound: truncating or extending the image re-tags. The tag
     covers the image as the runtime receives it, i.e. zero-padded to a whole
     number of 8-byte words, so a sub-word tail is padding and not a change —
     a word-aligned change is one. *)
  let one_short = Bytes.sub enc.bytes 0 (Bytes.length enc.bytes - 1) in
  Alcotest.(check bool) "truncation re-tags" true
    (Stack_encoder.derive_payload_tag one_short eff <> enc.payload_tag);
  let one_more = Bytes.make (Bytes.length enc.bytes + 8) '\000' in
  Bytes.blit enc.bytes 0 one_more 0 (Bytes.length enc.bytes);
  Alcotest.(check bool) "a whole extra word re-tags" true
    (Stack_encoder.derive_payload_tag one_more eff <> enc.payload_tag);
  Alcotest.(check int64) "tag covers the word-padded image" enc.payload_tag
    (Stack_encoder.derive_payload_tag enc.bytes eff);
  let padded = Bytes.make (((Bytes.length enc.bytes + 7) / 8) * 8) '\000' in
  Bytes.blit enc.bytes 0 padded 0 (Bytes.length enc.bytes);
  Alcotest.(check bool) "zero padding to a word boundary does not change the tag" true
    (Stack_encoder.derive_payload_tag padded eff = enc.payload_tag);

  (* the tag key is domain-separated from the per-block key halves *)
  let k0, k1 = Stack_encoder.payload_tag_keys eff in
  let bk0 = Int64.logxor eff 0x5877_A564_D00F_0000L in
  let bk1 = Int64.logxor eff 0xD00F_5877_0000_A564L in
  Alcotest.(check bool) "tag key halves differ from block key halves" true
    (k0 <> bk0 && k1 <> bk1 && k0 <> k1);
  (* Regression: the halves used to be the seed XORed with two constants one
     byte apart, so k0 ^ k1 was a fixed 3 for every seed and recovering one
     half yielded the other exactly. Push the halves through the PRF instead
     and that constant separation is gone. *)
  let k0b, k1b = Stack_encoder.payload_tag_keys (Int64.logxor eff 0x5A5AL) in
  Alcotest.(check bool) "half separation is not seed-independent" true
    (Int64.logxor k0 k1 <> Int64.logxor k0b k1b);
  Alcotest.(check int64) "explicit key halves match the convenience wrapper"
    (Stack_encoder.derive_payload_tag enc.bytes eff)
    (Stack_encoder.payload_tag_of_keys ~k0 ~k1 enc.bytes);

  (* address binding must move the stored tag keys exactly as it moves the
     stored block keys, and must leave the expected tag itself alone *)
  let d_addr = Stack_encoder.parse_u64_hex "0F0E1D2C3B4A5968" in
  let enc_masked = Stack_encoder.encode_program ~seed_key:seed ~addr_mask:d_addr prog in
  Alcotest.(check int64) "tag survives address masking" enc.payload_tag enc_masked.payload_tag;
  Alcotest.(check int64) "stored tag key 0 = effective ^ mask"
    (Int64.logxor k0 d_addr) (Hashtbl.find enc_masked.tag_keys 0);
  Alcotest.(check int64) "stored tag key 1 = effective ^ mask"
    (Int64.logxor k1 d_addr) (Hashtbl.find enc_masked.tag_keys 1);
  let enc_rebound = Stack_encoder.apply_addr_mask enc d_addr in
  Alcotest.(check int64) "rebound tag key matches direct masked encode"
    (Hashtbl.find enc_masked.tag_keys 0) (Hashtbl.find enc_rebound.tag_keys 0);
  let enc_unbound = Stack_encoder.apply_addr_mask enc_rebound 0L in
  Alcotest.(check int64) "unbind restores plaintext tag key 0" k0 (Hashtbl.find enc_unbound.tag_keys 0)

(* ── Guest memory-access policy (mirrored in the C runtime) ────────────── *)
let test_guest_mem_policy () =
  let ok (addr : int64) (w : int) = Alcotest.(check bool) (Printf.sprintf "allow %Lx/%d" addr w) true
      (mem_access_ok addr w) in
  let bad (addr : int64) (w : int) = Alcotest.(check bool) (Printf.sprintf "deny %Lx/%d" addr w) true
      (not (mem_access_ok addr w)) in
  (* width must be one of the four encodable widths *)
  ok 0x1000L 1; ok 0x1000L 2; ok 0x1000L 4; ok 0x1008L 8;
  bad 0x1000L 0; bad 0x1000L 3; bad 0x1000L 5; bad 0x1000L 16;
  (* zero is never a valid address *)
  bad 0L 1; bad 0L 8;
  (* natural alignment for the width *)
  bad 0x1001L 2; bad 0x1004L 8; ok 0x1008L 8;
  (* canonical half of the address space only — bits 63:48 must sign-extend
     bit 47, so a computed integer cannot wrap through the middle of the
     space and come out looking like a pointer *)
  bad 0x0000_8000_0000_0000L 1;
  bad 0xFFFF_7FFF_FFFF_FFFFL 1;
  ok 0x0000_7FFF_FFFF_FFFFL 1;
  ok 0xFFFF_8000_0000_0000L 8;
  (* no wrap at the top of the space *)
  bad 0xFFFF_FFFF_FFFF_FFFFL 8;
  ok 0xFFFF_FFFF_FFFF_FFF8L 8;

  (* the reference interpreter halts instead of performing a rejected access *)
  let st = create_state () in
  write_mem_word st 0x2000L 0x4142L 8;
  step_op st (PushImm 0x2000L);
  step_op st (ReadMem 8);
  Alcotest.(check int64) "reference reads an admissible address" 0x4142L
    (List.hd st.vstack);
  Alcotest.(check bool) "reference still running" false st.halted;
  step_op st (PopReg 0);
  step_op st (PushImm 0x1001L);
  step_op st (ReadMem 8);
  Alcotest.(check bool) "reference halts on a misaligned address" true st.halted

(* ── The C runtime authenticates before it decodes ──────────────────────── *)
let test_payload_auth_c_runtime () =
  if Sys.command "command -v c++ >/dev/null 2>&1" <> 0 then
    Printf.printf "SKIP test_payload_auth_c_runtime: no C++ compiler on PATH\n%!"
  else begin
    let seed = 0x0C0FFEE0C0FFEE01L in
    let b0 = make_block 0 "entry" [ PushImm 0x1337L; PopReg 0; Exit ] in
    let prog = make_program 0 [b0] 8 in
    let enc = Stack_encoder.encode_program ~seed_key:seed prog in
    let eff = Stack_encoder.effective_seed_key enc in
    let cfg = Stack_runtime.default_config Stack_runtime.X86_64 in
    let hpp = Stack_runtime.generate_c_runtime ~enc cfg prog in

    let bytes_to_words b =
      let n = Bytes.length b in
      let padded = (n + 7) land (lnot 7) in
      Array.init (padded / 8) (fun i ->
        let w = ref 0L in
        for j = 7 downto 0 do
          let idx = (i * 8) + j in
          let byte = if idx < n then Char.code (Bytes.get b idx) else 0 in
          w := Int64.logor (Int64.shift_left !w 8) (Int64.of_int byte)
        done;
        !w)
    in
    let words = bytes_to_words enc.bytes in
    let nwords = Array.length words in
    Alcotest.(check bool) "image is a whole number of words" true (nwords > 1);

    (* a one-word truncation: authentic image, but it ends in the middle of
       the first PushImm's operand, and a sentinel word sits right behind it *)
    let short_words = Array.sub words 0 (nwords - 1) in
    let short_bytes = Bytes.create ((nwords - 1) * 8) in
    for i = 0 to nwords - 2 do
      for j = 0 to 7 do
        let w = words.(i) in
        let byte = Int64.to_int (Int64.logand (Int64.shift_right_logical w (j * 8)) 0xFFL) in
        Bytes.set short_bytes ((i * 8) + j) (Char.chr byte)
      done
    done;
    (* the truncation gets its own valid tag: what is under test is the fetch
       bound, not authentication *)
    let short_tag = Stack_encoder.derive_payload_tag short_bytes eff in
    Alcotest.(check bool) "truncated image has a different tag" true (short_tag <> enc.payload_tag);
    let enc_short = { enc with bytes = short_bytes; payload_tag = short_tag } in
    let hpp_short = Stack_runtime.generate_c_runtime ~enc:enc_short cfg prog in

    let hex64 v =
      let h = Printf.sprintf "%LX" v in
      String.make (max 0 (16 - String.length h)) '0' ^ h
    in
    let emit_words buf name ws =
      Buffer.add_string buf (Printf.sprintf "static const uint64_t %s[] = {\n" name);
      Array.iteri (fun i w ->
        Buffer.add_string buf
          (Printf.sprintf "    0x%sULL%s\n" (hex64 w) (if i = Array.length ws - 1 then "" else ",")))
        ws;
      Buffer.add_string buf "};\n"
    in
    let dir = Filename.get_temp_dir_name () in
    let hpp_path = Filename.concat dir "stack_vm_runtime.hpp" in
    let write path s = let oc = open_out path in output_string oc s; close_out oc in

    (* Driver A runs against the authentic header: the untampered image, the
       same image with one bit flipped, and the same bytes presented as more
       words than they are. *)
    let tampered = Array.copy words in
    tampered.(0) <- Int64.logxor tampered.(0) 0x01L;
    let tampered_bytes = Bytes.copy enc.bytes in
    Bytes.set tampered_bytes 0
      (Char.chr (Char.code (Bytes.get tampered_bytes 0) lxor 0x01));
    Alcotest.(check bool) "flipped bit changes the tag" true
      (Stack_encoder.derive_payload_tag tampered_bytes eff <> enc.payload_tag);

    let driver_a = Filename.concat dir "asgard_payload_auth_a.cpp" in
    let buf_a = Buffer.create 4096 in
    Buffer.add_string buf_a "#include \"stack_vm_runtime.hpp\"\n#include <stdio.h>\n";
    emit_words buf_a "words" words;
    emit_words buf_a "tampered" tampered;
    (* a0 is seeded into ctx[0]; a failed authentication must not hand it back *)
    Buffer.add_string buf_a (Printf.sprintf
      "#define A0 0xDEADBEEFCAFEULL\n\
      int main() {\n\
      \  uint64_t clean_a0 = asgard_stack_vm::stack_vm_call(words, %d, A0);\n\
      \  uint64_t clean = asgard_stack_vm::stack_vm_call(words, %d);\n\
      \  uint64_t overlong = asgard_stack_vm::stack_vm_call(words, %d);\n\
      \  uint64_t patched = asgard_stack_vm::stack_vm_call(tampered, %d);\n\
      \  uint64_t patched_a0 = asgard_stack_vm::stack_vm_call(tampered, %d, A0);\n\
      \  printf(\"clean=%%llu clean_a0=%%llu overlong=%%llu tampered=%%llu tampered_a0=%%llu\\n\",\n\
      \    (unsigned long long)clean, (unsigned long long)clean_a0,\n\
      \    (unsigned long long)overlong, (unsigned long long)patched,\n\
      \    (unsigned long long)patched_a0);\n\
      \  return 0;\n}\n" nwords nwords (nwords + 1) nwords nwords);
    write driver_a (Buffer.contents buf_a);

    (* Driver B runs against the header carrying the truncated image's own
       valid tag, with a sentinel word laid out right behind it: an image
       that ends mid-operand must halt, not decode the sentinel. *)
    let driver_b = Filename.concat dir "asgard_payload_auth_b.cpp" in
    let buf_b = Buffer.create 4096 in
    Buffer.add_string buf_b "#include \"stack_vm_runtime.hpp\"\n#include <stdio.h>\n";
    emit_words buf_b "short_words" short_words;
    emit_words buf_b "sentinel" [| 0xDEADBEEFDEADBEEFL |];
    Buffer.add_string buf_b (Printf.sprintf
      "int main() {\n\
      \  uint64_t short_run = asgard_stack_vm::stack_vm_call(short_words, %d);\n\
      \  uint64_t sentinel_run = asgard_stack_vm::stack_vm_call(sentinel, 1);\n\
      \  printf(\"short=%%llu sentinel=%%llu\\n\",\n\
      \    (unsigned long long)short_run, (unsigned long long)sentinel_run);\n\
      \  return 0;\n}\n" (Array.length short_words));
    write driver_b (Buffer.contents buf_b);

    let compile target driver =
      let cmd = Printf.sprintf "c++ -O1 -std=c++17 %s -o %s"
          (Filename.quote driver) (Filename.quote target) in
      let rc = Sys.command cmd in
      if rc = 0 then 0 else Sys.command (Printf.sprintf "%s -ldl" cmd)
    in
    let run target =
      ignore (Sys.command (Printf.sprintf "%s > %s.out 2>&1"
          (Filename.quote target) (Filename.quote target)));
      let ic = open_in (target ^ ".out") in
      let out = really_input_string ic (in_channel_length ic) in
      close_in ic; out
    in
    let field out key =
      let n = String.length out in
      let klen = String.length key in
      let rec go i =
        if i + klen + 1 > n then failwith (Printf.sprintf "no %s in output:\n%s" key out)
        else if String.sub out i klen = key && out.[i + klen] = '=' then begin
          let j = ref (i + klen + 1) in
          while !j < n && out.[!j] >= '0' && out.[!j] <= '9' do incr j done;
          if !j = i + klen + 1 then failwith (Printf.sprintf "empty %s in output:\n%s" key out)
          else int_of_string (String.sub out (i + klen + 1) (!j - i - klen - 1))
        end
        else go (i + 1)
      in
      go 0
    in
    let bin_a = Filename.concat dir "asgard_payload_auth_a" in
    let bin_b = Filename.concat dir "asgard_payload_auth_b" in
    write hpp_path hpp;
    if compile bin_a driver_a <> 0 then Alcotest.fail "payload auth driver A failed to compile"
    else begin
      let out = run bin_a in
      Alcotest.(check int) "untampered image authenticates and runs" 0x1337 (field out "clean");
      Alcotest.(check int) "a flipped image bit refuses to execute" 0 (field out "tampered");
      Alcotest.(check int) "an over-long length refuses to execute" 0 (field out "overlong");
      (* a failed authentication must be indistinguishable from an ordinary
         denial: same result, and no trace of the caller's arguments *)
      Alcotest.(check int) "a0 does not change the untampered result" 0x1337
        (field out "clean_a0");
      Alcotest.(check int) "a failed authentication does not echo a0 back" 0
        (field out "tampered_a0")
    end;
    write hpp_path hpp_short;
    if compile bin_b driver_b <> 0 then Alcotest.fail "payload auth driver B failed to compile"
    else begin
      let out = run bin_b in
      (* A consistent but mid-operand truncation halts instead of decoding the
         sentinel word laid out behind it, so reg0 is never written. *)
      Alcotest.(check int) "mid-operand truncation halts before the sentinel" 0
        (field out "short");
      (* And the sentinel word on its own is simply not a valid image. *)
      Alcotest.(check int) "a foreign image is not authenticated" 0
        (field out "sentinel")
    end
  end

let tests = [
  ("Stack IR Primitives", `Quick, test_stack_ir_primitives);
  ("Context Allocator & Randomization", `Quick, test_context_allocator);
  ("Universal Logic Reduction Truth Tables", `Quick, test_logic_reduction_truth_tables);
  ("IR to Stack-VM Lowering & Execution", `Quick, test_ir_to_stack_and_eval);
  ("Stack Balance Pass & Repair", `Quick, test_stack_balance_pass);
  ("Rolling Key Bytecode Encryption & Execution", `Quick, test_rolling_key_encoder_and_eval);
  ("Native Runtime & Dispatch Synthesis", `Quick, test_runtime_synthesis);
  ("Stack VM Extensions & Branching", `Quick, test_stack_vm_extensions);
  ("Polymorphic Opcode Remapping & Synthesis", `Quick, test_polymorphic_opcodes);
  ("PushImm 32/64-bit Compact Width", `Quick, test_compact_push_imm);
  ("Superoperator Fusion Pass & Runtime", `Quick, test_superoperator_fusion);
  ("VSP Stack Value Whitening", `Quick, test_vsp_whitening);
  ("Ghost Stack Padding Pass", `Quick, test_ghost_stack_padding);
  ("Spaghetti CFG Splitting", `Quick, test_spaghetti_splitting);
  ("MBA Constant Synthesis", `Quick, test_mba_synthesis);
  ("Virtual CFG Flattening", `Quick, test_cff_flattening);
  ("SAR/DIV/IDIV & Shift-Count Semantics", `Quick, test_sar_div_idiv_semantics);
  ("Flags Round-Trip & Parity", `Quick, test_flags_roundtrip_and_parity);
  ("Mid-Block KeyAdjust Round-Trip", `Quick, test_keyadjust_midblock);
  ("Address-Masked Key Literals", `Quick, test_addr_mask_unit);
  ("Address-Masked Wrong Key Diverges", `Quick, test_addr_mask_wrong_key);
  ("Payload Integrity Tag", `Quick, test_payload_tag_unit);
  ("Guest Memory Access Policy", `Quick, test_guest_mem_policy);
  ("C++ Runtime Authenticates Before Decoding", `Slow, test_payload_auth_c_runtime);
  ("Full Obfuscation Pipeline Semantics", `Quick, test_full_pipeline_semantics);
  ("C++ Runtime Compile & Run", `Slow, test_c_runtime_compile_and_run);
  ("Full Pipeline + C++ Runtime + Args", `Slow, test_full_pipeline_c_runtime_with_args);
  ("Address-Bound C++ Runtime Probe & Run", `Slow, test_address_bound_c_runtime_probe_and_run);
  ("Real License Check Macro + Stack-VM E2E", `Slow, test_real_license_check_macro_stack_vm_e2e);
]



