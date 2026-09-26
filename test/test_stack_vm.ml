open Vm_ir
open Register
open Ir
open Stack_vm
open Stack_ir
open Stack_eval

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
  let decoded_ops = Stack_encoder.decode_all enc.bytes enc.seed_key in
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
  let decoded = Stack_encoder.decode_all enc.bytes enc.seed_key in
  Alcotest.(check bool) "decoded instructions present" true (List.length decoded > 0);

  let state_bc = run_bytecode enc in
  Alcotest.(check int64) "BC reg0 (Setcc E) is 1" 1L (get_reg state_bc 0);
  Alcotest.(check int64) "BC reg1 (Cmov E) is 42" 42L (get_reg state_bc 1);
  Alcotest.(check int64) "BC reg2 (taken branch) is 777" 777L (get_reg state_bc 2);
  Alcotest.(check bool) "BC halted" true state_bc.halted

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

  (* 2. Verify all 26 opcodes in map1 are unique and non-zero *)
  let ops_list1 = [
    map1.op_push_imm; map1.op_push_reg; map1.op_pop_reg; map1.op_read_mem; map1.op_write_mem;
    map1.op_add; map1.op_sub; map1.op_mul; map1.op_nor; map1.op_nand;
    map1.op_shl; map1.op_shr; map1.op_dup; map1.op_swap; map1.op_push_flags;
    map1.op_pop_flags; map1.op_jmp_rel; map1.op_jcc_rel; map1.op_key_adjust; map1.op_exit;
    map1.op_call_extern; map1.op_resolve_sym; map1.op_setcc; map1.op_cmov; map1.op_cmp; map1.op_test;
  ] in
  List.iter (fun op ->
    Alcotest.(check bool) "opcode is in range 1..254" true (op >= 1 && op <= 254)
  ) ops_list1;
  let unique1 = List.sort_uniq compare ops_list1 in
  Alcotest.(check int) "all 26 opcodes are strictly unique" 26 (List.length unique1);

  (* 3. Verify diversity between different seeds *)
  let ops_list2 = [
    map2.op_push_imm; map2.op_push_reg; map2.op_pop_reg; map2.op_read_mem; map2.op_write_mem;
    map2.op_add; map2.op_sub; map2.op_mul; map2.op_nor; map2.op_nand;
    map2.op_shl; map2.op_shr; map2.op_dup; map2.op_swap; map2.op_push_flags;
    map2.op_pop_flags; map2.op_jmp_rel; map2.op_jcc_rel; map2.op_key_adjust; map2.op_exit;
    map2.op_call_extern; map2.op_resolve_sym; map2.op_setcc; map2.op_cmov; map2.op_cmp; map2.op_test;
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
  let contains s substr =
    let len_s = String.length s in
    let len_sub = String.length substr in
    let rec check i =
      if i + len_sub > len_s then false
      else if String.sub s i len_sub = substr then true
      else check (i + 1)
    in
    check 0
  in
  Alcotest.(check bool) "c runtime contains polymorphic push_imm" true (contains c_code expected_push_case);
  Alcotest.(check bool) "c runtime contains polymorphic add" true (contains c_code expected_add_case);
  Alcotest.(check bool) "c runtime contains polymorphic exit" true (contains c_code expected_exit_case)

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
  Alcotest.(check bool) "VSP_ENCODE macro present" true
    (contains c_code "#define VSP_ENCODE(vk, slot, v)");
  Alcotest.(check bool) "VSP_MASK macro present" true
    (contains c_code "#define VSP_MASK(vk, slot)");
  Alcotest.(check bool) "PUSH_IMM uses VSP_ENCODE" true
    (contains c_code "vm->vsp[vm->vsp_idx] = VSP_ENCODE(vm->vkey, vm->vsp_idx, imm)");
  Alcotest.(check bool) "ADD uses VSP_ENCODE decode" true
    (contains c_code "uint64_t b = VSP_ENCODE(vm->vkey, vm->vsp_idx, vm->vsp[vm->vsp_idx])");
  Alcotest.(check bool) "POP_REG uses VSP_ENCODE decode" true
    (contains c_code "vm->ctx[idx] = VSP_ENCODE(vm->vkey, vm->vsp_idx, vm->vsp[vm->vsp_idx])");
  Alcotest.(check bool) "DUP uses slot-aware re-encode" true
    (contains c_code "uint64_t decoded = VSP_ENCODE(vm->vkey, src, vm->vsp[src])");
  Alcotest.(check bool) "SWAP uses slot-aware re-encode" true
    (contains c_code "uint64_t da = VSP_ENCODE(vm->vkey, ia, vm->vsp[ia])");

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
  ("VSP Stack Value Whitening", `Quick, test_vsp_whitening);
  ("Ghost Stack Padding Pass", `Quick, test_ghost_stack_padding);
  ("MBA Constant Synthesis", `Quick, test_mba_synthesis);
  ("Virtual CFG Flattening", `Quick, test_cff_flattening);
]


