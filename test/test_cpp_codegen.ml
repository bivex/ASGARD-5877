open Cpp_codegen.Cpp_ast
open Cpp_codegen.Cpp_dsl
open Cpp_codegen.Cpp_printer

let contains_str str sub =
  let slen = String.length str in
  let sublen = String.length sub in
  let rec check i =
    if i + sublen > slen then false
    else if String.sub str i sublen = sub then true
    else check (i + 1)
  in
  check 0

let () =
  let rng = Random.State.make [| 0x5877; 0xED51 |] in
  
  (* 1. Basic typed function AST + scrambling *)
  let ast = [
    IncludeSys "cstdint";
    Namespace ("asgard::edsl_test", [
      FuncDecl {
        attrs    = [AlwaysInline; NoExcept];
        ret_type = UInt64;
        name     = "exec_synthetic_handler";
        params   = [(UInt64, "x"); (UInt64, "y")];
        body     = [
          constexpr_u64 "C1" 0x9E3779B97F4A7C15L;
          constexpr_u64 "C2" 0xBF58476D1CE4E5B9L;
          let_u64 "acc" ((var "x" ^~ var "y") *~ var "C1");
          var "acc" += ((var "x" &~ var "y") *~ var "C2");
          ret (var "acc" %~ u64 83L);
        ]
      }
    ])
  ] in
  let scrambled_ast = List.map (Cpp_codegen.Cpp_ast_obf.scramble_top_decl rng) ast in
  let code = render_header_unit scrambled_ast in
  assert (String.length code > 100);
  Printf.printf "[PASS] Step 1: Typed C++20 EDSL & AST Scrambler emitted valid header.\n";

  (* 2. Test control flow & statement printing *)
  let s_while = while_loop (var "i" <~ i32 10) [
    (var "i" += i32 1);
    if_then (var "i" ==~ i32 5) [ continue_stmt ];
    if_then (var "i" ==~ i32 9) [ break_stmt ];
  ] in
  let s_goto = goto "EXIT_VM" in
  let s_label = label "H_TEST" in
  assert (string_of_stmt s_goto = "goto EXIT_VM;");
  assert (string_of_stmt s_label = "H_TEST:");
  assert (String.length (string_of_stmt s_while) > 10);
  Printf.printf "[PASS] Step 2: C++ statements (while, goto, label, break, continue) stringification verified.\n";

  (* 3. Test Egraph AST emitter *)
  let egraph_ast = Native_vm.Egraph_cpp_emitter.egraph_add_rr_ast ~rng in
  let egraph_cpp = string_of_expr egraph_ast in
  assert (String.length egraph_cpp > 0);
  assert (String.contains egraph_cpp '(');
  Printf.printf "[PASS] Step 3: Typed Egraph AST expression generated: %s\n" egraph_cpp;

  (* 4. Test ALU handlers buffer emission *)
  let buf_alu = Buffer.create 2048 in
  Native_vm.Vm_alu_handlers.emit_alu_handlers buf_alu ~rng ~enable_egraph_expansion:true ();
  let alu_code = Buffer.contents buf_alu in
  assert (String.length alu_code > 500);
  Printf.printf "[PASS] Step 4: Vm_alu_handlers emitted %d bytes using typed AST.\n" (String.length alu_code);

  (* 5. Test Decoy handlers buffer emission *)
  let buf_decoy = Buffer.create 2048 in
  Native_vm.Vm_mem_handlers.emit_decoy_handlers ~rng buf_decoy;
  let decoy_code = Buffer.contents buf_decoy in
  assert (String.length decoy_code > 500);
  Printf.printf "[PASS] Step 5: Vm_mem_handlers (decoys) emitted %d bytes using typed AST.\n" (String.length decoy_code);

  (* 6. Test Control Flow handlers buffer emission *)
  let buf_ctrl = Buffer.create 2048 in
  Native_vm.Vm_control_handlers.emit_control_handlers buf_ctrl ~rng ~enable_nanomites:false ~enable_running_key:true ();
  let ctrl_code = Buffer.contents buf_ctrl in
  assert (String.length ctrl_code > 1000);
  assert (String.contains ctrl_code 'H');
  List.iter (fun lbl ->
    if not (String.contains ctrl_code lbl.[0]) then
      failwith ("Missing control label: " ^ lbl)
  ) [ "H_JMP"; "H_JCC"; "H_CMOV"; "H_SETCC"; "H_CALL"; "H_IJMP_R"; "H_ICALL_R"; "H_RET"; "H_EXIT" ];
  Printf.printf "[PASS] Step 6: Vm_control_handlers emitted %d bytes using typed AST.\n" (String.length ctrl_code);

  (* 7. Test Super-operator handlers buffer emission *)
  let buf_super = Buffer.create 2048 in
  Native_vm.Vm_control_handlers.emit_super_operators ~rng buf_super;
  let super_code = Buffer.contents buf_super in
  assert (String.length super_code > 500);
  List.iter (fun lbl ->
    let pat = "    " ^ lbl ^ ":" in
    let rec find idx =
      if idx + String.length pat > String.length super_code then false
      else if String.sub super_code idx (String.length pat) = pat then true
      else find (idx + 1)
    in
    if not (find 0) then failwith ("Missing super-operator label: " ^ lbl)
  ) [ "H_FUSED_MOV_ADD_RRI"; "H_FUSED_ADD_IMUL_RRI"; "H_FUSED_ADD_XOR_RRI"; "H_FUSED_SUB_XOR_RRI"; "H_FUSED_XOR_ADD_RRI"; "H_FUSED_CMP_CMOV" ];
  Printf.printf "[PASS] Step 7: Vm_control_handlers (super-operators) emitted %d bytes using typed AST.\n" (String.length super_code);

  (* 8. Test VMContext structure emission *)
  let buf_ctx = Buffer.create 2048 in
  let reg_perm = Array.init 32 (fun i -> i) in
  Native_vm.Vm_context_emitter.emit_context_hpp buf_ctx
    ~key_seed:0x5877CAFEl ~reg_perm ~stride:13 ~offset:7
    ~enable_running_key:true ~enable_stack_scramble:true ~enable_mem_sanitize:true;
  let ctx_code = Buffer.contents buf_ctx in
  assert (String.length ctx_code > 2000);
  List.iter (fun kw ->
    let rec find idx =
      if idx + String.length kw > String.length ctx_code then false
      else if String.sub ctx_code idx (String.length kw) = kw then true
      else find (idx + 1)
    in
    if not (find 0) then failwith ("Missing VMContext keyword: " ^ kw)
  ) [ "enum RegMap : uint8_t"; "struct VMContext"; "REG_AFFINE_A"; "REG_AFFINE_B";
      "reg_phys_idx"; "CANARY_VAL"; "canary_head"; "canary_tail"; "get_reg"; "set_reg";
      "eval_condition"; "compute_sub_flags"; "compute_add_flags" ];
  Printf.printf "[PASS] Step 8: Vm_context_emitter emitted %d bytes using typed AST.\n" (String.length ctx_code);

  (* 9. Test Modular Vanguard Runtime headers & Runtime_policy *)
  assert (String.length Native_vm.Native_vm_templates.platform_compat_header > 500);
  assert (String.length Native_vm.Native_vm_templates.crypto_primitives_header > 500);
  assert (String.length Native_vm.Native_vm_templates.sanitization_header > 200);
  assert (String.contains Native_vm.Native_vm_templates.platform_compat_header '<');
  assert (String.contains Native_vm.Native_vm_templates.crypto_primitives_header 'a');
  assert (String.contains Native_vm.Native_vm_templates.sanitization_header 'S');

  let default_policy = Native_vm.Vm_runtime_emitter.Runtime_policy.of_config None in
  assert (default_policy.enable_smc = true);
  assert (default_policy.enable_anti_emu = true);
  assert (default_policy.num_domains >= 1);
  let models = Native_vm.Vm_runtime_emitter.Runtime_policy.to_models default_policy in
  assert (List.length models = 15);

  let opcode_to_handler = Array.make 256 "H_NOP" in
  let header_src = Native_vm.Vm_runtime_emitter.emit_cpp_threaded_header
    ~rng ~key_seed:0x5877CAFEl ~reg_perm ~expected_hash:0x1234567890ABCDEFL
    opcode_to_handler
  in
  assert (String.length header_src > 5000);
  assert (contains_str header_src "vanguard/platform_compat.hpp");
  assert (contains_str header_src "vanguard/crypto_primitives.hpp");
  assert (contains_str header_src "vanguard/sanitization.hpp");
  Printf.printf "[PASS] Step 9: Modular Vanguard runtime headers & Runtime_policy verified (%d bytes emitted).\n" (String.length header_src);

  (* 10. Test Stack-VM Manipulation handlers AST emission *)
  let buf_stack = Buffer.create 2048 in
  Stack_vm.Stack_handlers_emitter.emit_handlers_source buf_stack;
  let stack_code = Buffer.contents buf_stack in
  assert (String.length stack_code > 1000);
  List.iter (fun kw ->
    let rec find idx =
      if idx + String.length kw > String.length stack_code then false
      else if String.sub stack_code idx (String.length kw) = kw then true
      else find (idx + 1)
    in
    if not (find 0) then failwith ("Missing Stack-VM handler: " ^ kw)
  ) [ "h_push_imm"; "h_push_imm32"; "h_push_reg"; "h_pop_reg";
      "h_dup"; "h_dup2"; "h_rot"; "h_swap";
      "h_read_mem"; "h_write_mem"; "h_add"; "h_sub"; "h_mul"; "h_nor";
      "h_nand"; "h_shl"; "h_shr"; "h_sar"; "h_div"; "h_idiv";
      "h_push_flags"; "h_pop_flags" ];
  Printf.printf "[PASS] Step 10: Stack_handlers_emitter emitted %d bytes using typed AST.\n" (String.length stack_code);

  (* 11. Test Multi-VM Typed Structures & Bridges AST emission *)
  let multi_vm_code = Multi_vm.Multi_vm_context_emitter.emit_asgard_multi_vm_source () in
  assert (String.length multi_vm_code > 500);
  List.iter (fun kw ->
    let rec find idx =
      if idx + String.length kw > String.length multi_vm_code then false
      else if String.sub multi_vm_code idx (String.length kw) = kw then true
      else find (idx + 1)
    in
    if not (find 0) then failwith ("Missing Multi-VM keyword: " ^ kw)
  ) [ "namespace asgard_multi_vm"; "struct MathVMContext"; "struct FlowVMContext";
      "union SharedVMContext"; "bridge_switch_to_flow"; "bridge_switch_to_math" ];
  Printf.printf "[PASS] Step 11: Multi_vm_context_emitter emitted %d bytes using typed AST.\n" (String.length multi_vm_code);

  (* 12. Test C++ Pre-flight Syntax & Structural Validation *)
  let valid_cpp = {|
    #include <cstdint>
    namespace test {
        struct Sample {
            uint64_t a;
            inline void foo(int x) {
                if (x > 0) {
                    a += (uint64_t)x;
                }
            }
        };
    }
  |} in
  (match Cpp_codegen.Cpp_validator.validate_cpp_syntax valid_cpp with
   | Ok () -> ()
   | Error err -> failwith ("Expected valid C++ to pass, but failed: " ^ err));

  (* Validate that unclosed bracket is caught *)
  let invalid_bracket = "int main() { if (1) { return 0; } " in
  (match Cpp_codegen.Cpp_validator.validate_cpp_syntax invalid_bracket with
   | Error _ -> ()
   | Ok () -> failwith "Expected unclosed bracket to fail validation");

  (* Validate that mismatched delimiter is caught *)
  let mismatched_bracket = "int main() { return (int)5]; }" in
  (match Cpp_codegen.Cpp_validator.validate_cpp_syntax mismatched_bracket with
   | Error _ -> ()
   | Ok () -> failwith "Expected mismatched bracket to fail validation");

  (* Validate that leftover Jingoo template tag is caught *)
  let leftover_template = "int x = {{ my_var }};" in
  (match Cpp_codegen.Cpp_validator.validate_cpp_syntax leftover_template with
   | Error _ -> ()
   | Ok () -> failwith "Expected leftover template marker to fail validation");

  (* Validate that compiler check passes for valid simple C++ *)
  (match Cpp_codegen.Cpp_validator.validate_cpp_syntax ~use_compiler:true "int add(int a, int b) { return a + b; }" with
   | Ok () -> ()
   | Error err -> failwith ("Compiler syntax check failed: " ^ err));

  Printf.printf "[PASS] Step 12: Pre-flight C++ syntax validation verified (structural & clang++).\n";

  (* 13. Test RD-JIT VM typed RNS & Context code generation *)
  let rd_jit_hdr = Rd_jit_vm.Rd_jit_buffer.header () in
  assert (String.length rd_jit_hdr > 1000);
  List.iter (fun kw ->
    let rec find idx =
      if idx + String.length kw > String.length rd_jit_hdr then false
      else if String.sub rd_jit_hdr idx (String.length kw) = kw then true
      else find (idx + 1)
    in
    if not (find 0) then failwith ("Missing RD-JIT keyword in header: " ^ kw)
  ) [ "struct RNS_Register"; "struct RD_JIT_Context"; "RNS_M1"; "RNS_M2"; "decode_crt"; "DualMappedJITBuffer" ];

  let synth_hdr = Rd_jit_vm.Rd_jit_synth.header () in
  assert (String.length synth_hdr > 500);
  List.iter (fun kw ->
    let rec find idx =
      if idx + String.length kw > String.length synth_hdr then false
      else if String.sub synth_hdr idx (String.length kw) = kw then true
      else find (idx + 1)
    in
    if not (find 0) then failwith ("Missing RD-JIT Synth keyword in header: " ^ kw)
  ) [ "enum JITOpKind : uint8_t"; "struct JITInstr"; "struct JITBlock"; "JITBlockFn" ];
  Printf.printf "[PASS] Step 13: RD-JIT VM typed RNS & context emitted using typed AST.\n";

  (* 14. Test Stack-VM superoperators and Vanguard-9292 decoder typed AST *)
  let superops = Stack_vm.Stack_handlers_emitter.emit_superop_handlers_string () in
  assert (String.length superops > 500);
  List.iter (fun kw ->
    let rec find idx =
      if idx + String.length kw > String.length superops then false
      else if String.sub superops idx (String.length kw) = kw then true
      else find (idx + 1)
    in
    if not (find 0) then failwith ("Missing Stack-VM superoperator: " ^ kw)
  ) [ "h_cmp"; "h_test"; "h_add_imm"; "h_sub_imm"; "h_add_ii"; "h_sub_ii" ];
  (match Cpp_codegen.Cpp_validator.validate_cpp_syntax superops with
   | Ok () -> ()
   | Error err -> failwith ("Superops syntax validation failed: " ^ err));

  let rng = Random.State.make [| 42 |] in
  (match Random_visa_domain.Isa_grammar.generate_isa ~rng ~name:"Vanguard_Test" ~num_instructions:4 () with
   | Error _ -> failwith "Failed to generate test ISA spec"
   | Ok spec ->
       (match Vanguard_9292.of_isa_spec ~rng spec with
        | Error err -> failwith ("Failed to generate vanguard scheme: " ^ err)
        | Ok vanguard_scheme ->
            let decoder_cpp = Vanguard_9292.emit_cpp_decoder vanguard_scheme spec in
            assert (String.length decoder_cpp > 1000);
            List.iter (fun kw ->
              let rec find idx =
                if idx + String.length kw > String.length decoder_cpp then false
                else if String.sub decoder_cpp idx (String.length kw) = kw then true
                else find (idx + 1)
              in
              if not (find 0) then failwith ("Missing Vanguard decoder keyword: " ^ kw)
            ) [ "struct RollingKey"; "struct VanguardDecoder"; "decode_and_execute"; "next64" ];
            (match Cpp_codegen.Cpp_validator.validate_cpp_syntax decoder_cpp with
             | Ok () -> ()
             | Error err -> failwith ("Vanguard decoder syntax validation failed: " ^ err))));
  Printf.printf "[PASS] Step 14: Stack-VM superoperators & Vanguard 9292 decoder emitted using typed AST.\n";

  (* 15. Test Stack-VM control, cond, and reg_imm handlers typed AST *)
  let ctrl_handlers = Stack_vm.Stack_handlers_emitter.emit_control_handlers_string () in
  let cond_handlers = Stack_vm.Stack_handlers_emitter.emit_cond_handlers_string () in
  let reg_imm_handlers = Stack_vm.Stack_handlers_emitter.emit_reg_imm_handlers_string () in
  assert (String.length ctrl_handlers > 200);
  assert (String.length cond_handlers > 200);
  assert (String.length reg_imm_handlers > 200);
  List.iter (fun kw ->
    let rec find s idx =
      if idx + String.length kw > String.length s then false
      else if String.sub s idx (String.length kw) = kw then true
      else find s (idx + 1)
    in
    if not (find ctrl_handlers 0 || find cond_handlers 0 || find reg_imm_handlers 0) then
      failwith ("Missing Stack-VM handler: " ^ kw)
  ) [ "h_jmp_rel"; "h_jcc_rel"; "h_key_adjust"; "h_exit"; "h_resolve_sym"; "h_setcc"; "h_cmov"; "h_set_reg_imm"; "h_add_reg_imm"; "h_key_feedback" ];
  (match Cpp_codegen.Cpp_validator.validate_cpp_syntax (ctrl_handlers ^ "\n" ^ cond_handlers ^ "\n" ^ reg_imm_handlers) with
   | Ok () -> ()
   | Error err -> failwith ("Control/Cond/RegImm handlers syntax validation failed: " ^ err));
  Printf.printf "[PASS] Step 15: Stack-VM control, cond & reg_imm handlers emitted using typed AST.\n";

  (* 16. Vector ISA C++ Emulator AST (VRegFile, EmulatorState, Decoder, InstructionExecutor) *)
  let vreg_file_code = render_top_decl (Random_visa_cpp_emitter.Cpp_header_emitters.emit_vreg_file_def ()) in
  let emu_state_code = render_top_decl (Random_visa_cpp_emitter.Cpp_header_emitters.emit_emulator_state_def ()) in
  (match Cpp_codegen.Cpp_validator.validate_cpp_syntax (vreg_file_code ^ "\n" ^ emu_state_code) with
   | Ok () -> ()
   | Error err -> failwith ("Vector ISA State syntax validation failed: " ^ err));
  assert (String.length vreg_file_code > 500);
  assert (String.length emu_state_code > 200);
  Printf.printf "[PASS] Step 16: Vector ISA C++ Emulator AST (VRegFile & EmulatorState) emitted.\n";

  (* 17. Tech-2603 NonLinearVPCDispatcher template struct AST *)
  let vpc_dispatcher_code = render_top_decl (Tech_2603.Tech_2603_engine.emit_nonlinear_vpc_dispatcher_def ()) in
  (match Cpp_codegen.Cpp_validator.validate_cpp_syntax vpc_dispatcher_code with
   | Ok () -> ()
   | Error err -> failwith ("NonLinearVPCDispatcher syntax validation failed: " ^ err));
  assert (String.length vpc_dispatcher_code > 300);
  Printf.printf "[PASS] Step 17: Tech-2603 NonLinearVPCDispatcher template struct emitted using typed AST.\n";

  (* 18. C11 Vector ISA Emulator AST *)
  let c11_csr = render_top_decls (Random_visa_c11_emitter.C11_emitter_adapter.emit_csr_state_c11_def ()) in
  let c11_emu = render_top_decls (Random_visa_c11_emitter.C11_emitter_adapter.emit_emulator_state_c11_def ()) in
  let c11_dec = render_top_decls (Random_visa_c11_emitter.C11_emitter_adapter.emit_decoded_inst_c11_def ()) in
  let c11_protos = render_top_decls (Random_visa_c11_emitter.C11_emitter_adapter.emit_c11_prototypes ()) in
  assert (String.length c11_csr > 50);
  assert (String.length c11_emu > 50);
  assert (String.length c11_dec > 50);
  assert (String.length c11_protos > 100);
  Printf.printf "[PASS] Step 18: C11 Vector ISA Emulator structs & prototypes emitted using typed AST.\n";

  (* 19. GPU MBA Substitution Matrix AST *)
  let rng = Random.State.make [| 42 |] in
  let mat = Gpu_synth.Gpu_matrix.generate ~dim:16 ~rng () in
  let mat_ast_decls = Gpu_synth.Gpu_matrix.emit_cpp_constants_ast mat in
  let mat_cpp = render_top_decls mat_ast_decls in
  (match Cpp_codegen.Cpp_validator.validate_cpp_syntax mat_cpp with
   | Ok () -> ()
   | Error err -> failwith ("GPU MBA Matrix syntax validation failed: " ^ err));
  assert (String.length mat_cpp > 100);
  Printf.printf "[PASS] Step 19: GPU MBA substitution matrix emitted using typed AST.\n";

  (* 20. C Nanomite Branch Functions & Auto-Init Constructor AST *)
  let nano_site = {
    C_macro_obf.C_nanomites.ns_id = 1;
    ns_cond = "x > 0";
    ns_then_fn = "asgbranch_t_100";
    ns_else_fn = "asgbranch_f_100";
    ns_then_src = "printf(\"then\\n\");";
    ns_else_src = "printf(\"else\\n\");";
    ns_key = 0x1234;
    ns_has_return = false;
  } in
  let nano_ast_decls = C_macro_obf.C_nanomites.emit_nanomite_preamble_ast [ nano_site ] in
  let nano_cpp = render_top_decls nano_ast_decls in
  (match Cpp_codegen.Cpp_validator.validate_cpp_syntax nano_cpp with
   | Ok () -> ()
   | Error err -> failwith ("Nanomite preamble syntax validation failed: " ^ err));
  assert (String.length nano_cpp > 100);
  Printf.printf "[PASS] Step 20: C Nanomite branch functions & auto-init constructor emitted using typed AST.\n";

  (* 21. Multi-VM Affine Bridge Matrices & Morphing AST *)
  let bridge = Multi_vm.Bridge.generate_bridge rng in
  let bridge_cpp = Multi_vm.Bridge.emit_cpp_bridge_code bridge in
  (match Cpp_codegen.Cpp_validator.validate_cpp_syntax bridge_cpp with
   | Ok () -> ()
   | Error err -> failwith ("Multi-VM Bridge syntax validation failed: " ^ err));
  assert (String.length bridge_cpp > 500);
  Printf.printf "[PASS] Step 21: Multi-VM affine bridge matrices & morphing functions emitted using typed AST.\n";

  (* 22. Native VM Whitebox Seed Derivation AST *)
  let wbox_cpp = Native_vm.Vm_runtime_emitter.generate_wbox_seed_derivation ~rng 0x5877CAFEl in
  (match Cpp_codegen.Cpp_validator.validate_cpp_syntax wbox_cpp with
   | Ok () -> ()
   | Error err -> failwith ("Whitebox seed derivation syntax validation failed: " ^ err));
  assert (String.length wbox_cpp > 500);
  Printf.printf "[PASS] Step 22: Native VM whitebox seed derivation emitted using typed AST.\n";

  (* 23. Residue Number System (RNS-4) Garner CRT AST *)
  let rns_ast = Vm_ir.Rns.emit_cpp_rns_ast () in
  let rns_cpp = Vm_ir.Rns.emit_cpp_rns_header () in
  (match Cpp_codegen.Cpp_validator.validate_cpp_syntax rns_cpp with
   | Ok () -> ()
   | Error err -> failwith ("RNS Garner CRT syntax validation failed: " ^ err));
  assert (List.length rns_ast > 0);
  assert (String.length rns_cpp > 300);
  Printf.printf "[PASS] Step 23: Residue Number System (RNS-4) Garner CRT emitted using typed AST.\n";

  (* 24. Tech-2603 Anti-VPC-Tracking C++20 Header AST *)
  let tech_2603_cpp = Tech_2603.Tech_2603_engine.emit_tech_2603_cpp_header () in
  (match Cpp_codegen.Cpp_validator.validate_cpp_syntax tech_2603_cpp with
   | Ok () -> ()
   | Error err -> failwith ("Tech-2603 header syntax validation failed: " ^ err));
  assert (String.length tech_2603_cpp > 300);
  Printf.printf "[PASS] Step 24: Tech-2603 Anti-VPC-Tracking runtime emitted using typed AST.\n";

  (* 25. Tech-2608 Anti-Trace-Synthesis & Chaff Memory Pool C++20 Header AST *)
  let tech_2608_cpp = Tech_2608.Tech_2608_engine.emit_tech_2608_cpp_header () in
  (match Cpp_codegen.Cpp_validator.validate_cpp_syntax tech_2608_cpp with
   | Ok () -> ()
   | Error err -> failwith ("Tech-2608 header syntax validation failed: " ^ err));
  assert (String.length tech_2608_cpp > 300);
  Printf.printf "[PASS] Step 25: Tech-2608 Anti-Trace-Synthesis & Chaff Memory Pool emitted using typed AST.\n";

  (* 26. Vector ISA C++ Emulator main.cpp and ISA constants AST *)
  (match Random_visa_domain.Isa_grammar.generate_isa ~rng ~name:"Emulator_Test" ~num_instructions:4 () with
   | Error _ -> failwith "Failed to generate test ISA spec"
   | Ok test_spec ->
       let isa_consts = Random_visa_cpp_emitter.Cpp_header_emitters.emit_isa_constants_defs test_spec in
       let main_cpp = Random_visa_cpp_emitter.Cpp_emitter_adapter.emit_main_cpp test_spec in
       (match Cpp_codegen.Cpp_validator.validate_cpp_syntax main_cpp with
        | Ok () -> ()
        | Error err -> failwith ("Vector ISA main.cpp syntax validation failed: " ^ err));
       assert (List.length isa_consts = 4);
       assert (String.length main_cpp > 300);
       Printf.printf "[PASS] Step 26: Vector ISA C++ Emulator main.cpp & constants emitted using typed AST.\n");

  (* 27. RD-JIT VM runner main function AST *)
  let rd_main_decl = Rd_jit_vm.Rd_jit_emitter.emit_rd_jit_main_def () in
  let rd_main_cpp = render_top_decl rd_main_decl in
  (match Cpp_codegen.Cpp_validator.validate_cpp_syntax rd_main_cpp with
   | Ok () -> ()
   | Error err -> failwith ("RD-JIT main function syntax validation failed: " ^ err));
  assert (String.length rd_main_cpp > 200);
  Printf.printf "[PASS] Step 27: RD-JIT VM runner main function emitted using typed AST.\n";

  (* 28. Native VM runner main function & full runner AST *)
  let native_main_decl = Native_vm.Vm_runtime_emitter.emit_native_runner_main_def () in
  let native_runner_cpp = Native_vm.Vm_runtime_emitter.emit_runner_cpp ~reg_perm:[|0;1;2;3|] [0x123456789ABCDEF0L; 0xDEADBEEFCAFEBABEL] in
  (match Cpp_codegen.Cpp_validator.validate_cpp_syntax (render_top_decl native_main_decl) with
   | Ok () -> ()
   | Error err -> failwith ("Native VM main function syntax validation failed: " ^ err));
  (match Cpp_codegen.Cpp_validator.validate_cpp_syntax native_runner_cpp with
   | Ok () -> ()
   | Error err -> failwith ("Native VM runner.cpp syntax validation failed: " ^ err));
  assert (String.length native_runner_cpp > 400);
  Printf.printf "[PASS] Step 28: Native VM runner main function & full runner emitted using typed AST.\n";

  (* 29. Stack-VM runner & probe AST *)
  let stack_runner_decl = Stack_vm.Stack_runtime.emit_stack_runner_main_def () in
  let stack_probe_decl = Stack_vm.Stack_runtime.emit_stack_probe_main_def () in
  let stack_runner_cpp = Stack_vm.Stack_runtime.emit_runner_cpp [0x1111222233334444L; 0x5555666677778888L] in
  let stack_probe_cpp = Stack_vm.Stack_runtime.emit_probe_cpp () in
  (match Cpp_codegen.Cpp_validator.validate_cpp_syntax (render_top_decl stack_runner_decl) with
   | Ok () -> ()
   | Error err -> failwith ("Stack-VM runner main function syntax validation failed: " ^ err));
  (match Cpp_codegen.Cpp_validator.validate_cpp_syntax (render_top_decl stack_probe_decl) with
   | Ok () -> ()
   | Error err -> failwith ("Stack-VM probe main function syntax validation failed: " ^ err));
  (match Cpp_codegen.Cpp_validator.validate_cpp_syntax stack_runner_cpp with
   | Ok () -> ()
   | Error err -> failwith ("Stack-VM runner.cpp syntax validation failed: " ^ err));
  (match Cpp_codegen.Cpp_validator.validate_cpp_syntax stack_probe_cpp with
   | Ok () -> ()
   | Error err -> failwith ("Stack-VM probe.cpp syntax validation failed: " ^ err));
  assert (String.length stack_runner_cpp > 300);
  assert (String.length stack_probe_cpp > 100);
  Printf.printf "[PASS] Step 29: Stack-VM runner & probe emitted using typed AST.\n";

  (* 30. Multi-VM runner main function & runner AST *)
  let multi_vm_main_decl = Multi_vm.Multi_vm_emitter.emit_multi_vm_runner_main_def
    ~math_blocks:3 ~flow_blocks:2 ~inter_vm_transitions:4 () in
  let multi_vm_main_cpp = render_top_decl multi_vm_main_decl in
  (match Cpp_codegen.Cpp_validator.validate_cpp_syntax multi_vm_main_cpp with
   | Ok () -> ()
   | Error err -> failwith ("Multi-VM runner main function syntax validation failed: " ^ err));
  assert (String.length multi_vm_main_cpp > 300);
  Printf.printf "[PASS] Step 30: Multi-VM runner main function & weak global linkage emitted using typed AST.\n";

  (* 31. Native VM external symbols & constants tables AST *)
  let native_ext_syms_decl = Native_vm.Vm_runtime_emitter.emit_external_symbols_table_ast [ "printf"; "malloc"; "_free" ] in
  let native_consts_decls = Native_vm.Vm_runtime_emitter.emit_constants_tables_ast ~rng [ ("hello", "world"); ("sec", "\x01\x02\x03\x04") ] in
  let native_ext_syms_cpp = render_top_decl native_ext_syms_decl in
  let native_consts_cpp = render_top_decls native_consts_decls in
  (match Cpp_codegen.Cpp_validator.validate_cpp_syntax native_ext_syms_cpp with
   | Ok () -> ()
   | Error err -> failwith ("Native VM external symbols table syntax validation failed: " ^ err));
  (match Cpp_codegen.Cpp_validator.validate_cpp_syntax native_consts_cpp with
   | Ok () -> ()
   | Error err -> failwith ("Native VM constants tables syntax validation failed: " ^ err));
  assert (String.length native_ext_syms_cpp > 50);
  assert (String.length native_consts_cpp > 100);
  Printf.printf "[PASS] Step 31: Native VM external symbols & aligned constants tables emitted using typed AST.\n";

  (* 32. Stack-VM external symbols & constants tables AST *)
  let stack_ext_syms_decl = Stack_vm.Stack_runtime.emit_stack_external_symbols_table_ast [ "puts"; "_exit" ] in
  let stack_consts_decls = Stack_vm.Stack_runtime.emit_stack_constants_tables_ast [ ("cfg", "alpha_beta"); ("key", "12345678") ] in
  let stack_ext_syms_cpp = render_top_decl stack_ext_syms_decl in
  let stack_consts_cpp = render_top_decls stack_consts_decls in
  (match Cpp_codegen.Cpp_validator.validate_cpp_syntax stack_ext_syms_cpp with
   | Ok () -> ()
   | Error err -> failwith ("Stack-VM external symbols table syntax validation failed: " ^ err));
  (match Cpp_codegen.Cpp_validator.validate_cpp_syntax stack_consts_cpp with
   | Ok () -> ()
   | Error err -> failwith ("Stack-VM constants tables syntax validation failed: " ^ err));
  assert (String.length stack_ext_syms_cpp > 50);
  assert (String.length stack_consts_cpp > 100);
  Printf.printf "[PASS] Step 32: Stack-VM external symbols & constants tables emitted using typed AST.\n";

  (* 33. Core SDK additions: Pragma, MacroDef, DoWhile *)
  let pragma_decl = pragma "once" in
  let macro_decl1 = macro_def ~value:(i32 1) "FOO_FLAG" in
  let macro_decl2 = macro_def "BAR_EMPTY" in
  let dowhile_fn = func_decl Void "loop_test" [] [
    let_u32 "x" (u32 10l);
    do_while (var "x" >~ i32 0) [
      var "x" -= i32 1;
    ];
    ret_void;
  ] in
  let sdk_cpp = render_top_decls [ pragma_decl; macro_decl1; macro_decl2; dowhile_fn ] in
  (match Cpp_codegen.Cpp_validator.validate_cpp_syntax sdk_cpp with
   | Ok () -> ()
   | Error err -> failwith ("Core SDK pragma/macro/dowhile validation failed: " ^ err));
  assert (String.contains sdk_cpp '#');
  Printf.printf "[PASS] Step 33: Core SDK Pragma, MacroDef, and DoWhile validated.\n";

  (* 34. Native VM address-bound block spans tables AST *)
  let spans = [ (0, 32); (32, 64); (96, 48) ] in
  let native_spans_decls = Native_vm.Vm_runtime_emitter.emit_block_spans_tables_ast spans in
  let native_spans_cpp = render_top_decls native_spans_decls in
  (match Cpp_codegen.Cpp_validator.validate_cpp_syntax native_spans_cpp with
   | Ok () -> ()
   | Error err -> failwith ("Native VM block spans tables validation failed: " ^ err));
  assert (contains_str native_spans_cpp "g_num_blocks");
  assert (contains_str native_spans_cpp "g_block_offsets");
  assert (contains_str native_spans_cpp "g_block_lengths");
  Printf.printf "[PASS] Step 34: Native VM address-bound block spans tables emitted using typed AST.\n";

  (* 35. Stack-VM block tables AST *)
  let stack_tables_decls = Stack_vm.Stack_runtime.emit_stack_block_tables_ast
    ~max_bid:2
    ~block_offsets:[ 0x1000L; 0x2000L; 0x3000L ]
    ~block_keys:[ 0xCAFEBABEL; 0xDEADBEEFL; 0x1337BEEFL ]
    ~tag_key0:0x58775877L
    ~tag_key1:0x92929292L
    ()
  in
  let stack_tables_cpp = render_top_decls stack_tables_decls in
  (match Cpp_codegen.Cpp_validator.validate_cpp_syntax stack_tables_cpp with
   | Ok () -> ()
   | Error err -> failwith ("Stack-VM block tables validation failed: " ^ err));
  assert (contains_str stack_tables_cpp "g_stack_block_offsets");
  assert (contains_str stack_tables_cpp "g_stack_block_keys");
  assert (contains_str stack_tables_cpp "g_stack_tag_keys");
  Printf.printf "[PASS] Step 35: Stack-VM block tables emitted using typed AST.\n";

  (* 36. Multi-VM header AST & source emission *)
  let multi_vm_hdr_cpp = Multi_vm.Multi_vm_emitter.emit_multi_vm_header_source
    ~bridge_cpp:"// test bridge code\n"
    ~asgard_multi_vm_source:"namespace asgard_multi_vm { struct DummyCtx {}; }\n"
    ~base_runtime_source:"namespace vanguard_threaded_vm { struct BaseCtx {}; }\n"
    ()
  in
  (match Cpp_codegen.Cpp_validator.validate_cpp_syntax multi_vm_hdr_cpp with
   | Ok () -> ()
   | Error err -> failwith ("Multi-VM header syntax validation failed: " ^ err));
  assert (contains_str multi_vm_hdr_cpp "ASGARD_MULTI_VM_ENABLED");
  Printf.printf "[PASS] Step 36: Multi-VM header emitted using typed EDSL without Jingoo.\n";

  (* 37. Core SDK Preproc directives, ComputedGoto, LabelAddr, DesignatedIndex/Range *)
  let preproc_test_decl =
    preproc_ifndef "TEST_GUARD" [
      macro_def "TEST_GUARD";
      include_sys "stdint.h";
      preproc_if "defined(__GNUC__)" [
        func_decl Void "test_gnuc" [] [
          decl_var ~is_static:true (Array (ConstPtr Void, 4)) "tbl"
            ~init:(init_list [
              desig_range (i32 0) (i32 2) (label_addr "l_default");
              desig_idx (u8 3) (label_addr "l_three");
            ]);
          computed_goto (idx (var "tbl") (i32 0));
          label "l_three";
          ret_void;
          label "l_default";
          ret_void;
        ];
      ] ~else_decls:[
        func_decl Void "test_fallback" [] [
          preproc_if_stmt "defined(_MSC_VER)" [
            raw "// msvc path";
          ] ~else_stmts:[
            raw "// generic path";
          ];
          ret_void;
        ];
      ];
    ]
  in
  let preproc_test_cpp = render_top_decls [ preproc_test_decl ] in
  (match Cpp_codegen.Cpp_validator.validate_cpp_syntax preproc_test_cpp with
   | Ok () -> ()
   | Error err -> failwith ("Core SDK Preproc and ComputedGoto validation failed: " ^ err));
  assert (contains_str preproc_test_cpp "#ifndef TEST_GUARD");
  assert (contains_str preproc_test_cpp "#if defined(__GNUC__)");
  assert (contains_str preproc_test_cpp "&&l_default");
  assert (contains_str preproc_test_cpp "goto *");
  Printf.printf "[PASS] Step 37: Core SDK Preproc directives, ComputedGoto, LabelAddr, and DesignatedIndex/Range validated.\n";

  (* 38. Stack-VM typed dispatch EDSL & Native VM dispatch tables AST *)
  let test_dispatch_cases = [
    (0x01, "PUSH_IMM", "h_push_imm");
    (0x02, "ADD", "h_add");
    (0xFF, "EXIT", "h_exit");
  ] in
  let stack_disp_cpp = Stack_vm.Stack_runtime.emit_stack_dispatch_source ~entry_bid:0 test_dispatch_cases in
  assert (contains_str stack_disp_cpp "dispatch_table[256]");
  assert (contains_str stack_disp_cpp "&&lbl_default");
  assert (contains_str stack_disp_cpp "case 0x01: /* PUSH_IMM */");
  assert (contains_str stack_disp_cpp "case 0x02: /* ADD */");
  assert (contains_str stack_disp_cpp "case 0xFF: /* EXIT */");

  let test_domain_salts = [| 0x11; 0x22 |] in
  let native_salt_stmt = Native_vm.Vm_runtime_emitter.emit_native_domain_salt_ast test_domain_salts in
  let native_salt_cpp = Cpp_codegen.Cpp_printer.string_of_stmt native_salt_stmt in
  assert (contains_str native_salt_cpp "domain_salt[2]");
  assert (contains_str native_salt_cpp "0x11");
  assert (contains_str native_salt_cpp "0x22");
  Printf.printf "[PASS] Step 38: Stack-VM typed dispatch EDSL and Native VM dispatch tables AST validated.\n";

  (* 39. Stack-VM complete typed C++20 EDSL runtime emission *)
  let blk = Stack_vm.Stack_ir.make_block 0 "entry" [Stack_vm.Stack_ir.PushImm 42L; Stack_vm.Stack_ir.Exit] in
  let prog = Stack_vm.Stack_ir.make_program 0 [blk] 16 in
  let cfg = Stack_vm.Stack_runtime.default_config Stack_vm.Stack_runtime.X86_64 in
  let decls = Stack_vm.Stack_runtime.emit_stack_runtime_hpp_decls cfg prog in
  let stack_runtime_cpp = Cpp_codegen.Cpp_printer.render_top_decls decls in
  assert (contains_str stack_runtime_cpp "struct AsgardConstantEntry");
  assert (contains_str stack_runtime_cpp "volatile int32_t ready;");
  assert (contains_str stack_runtime_cpp "struct asgard_ext_sym_t");
  assert (contains_str stack_runtime_cpp "namespace asgard_stack_vm");
  assert (contains_str stack_runtime_cpp "struct stack_vm_t");
  assert (contains_str stack_runtime_cpp "g_stack_handler_table");
  assert (contains_str stack_runtime_cpp "stack_vm_run");
  assert (contains_str stack_runtime_cpp "stack_vm_call");
  assert (contains_str stack_runtime_cpp "namespace vanguard_threaded_vm");
  assert (contains_str stack_runtime_cpp "asgard_vm_call");
  let h_extern = Stack_vm.Stack_runtime.emit_h_call_extern Stack_vm.Stack_runtime.X86_64 in
  let h_extern_cpp = Cpp_codegen.Cpp_printer.string_of_top_decl h_extern in
  assert (contains_str h_extern_cpp "h_call_extern");
  assert (contains_str h_extern_cpp "asgard_resolve_sym_idx");
  Printf.printf "[PASS] Step 39: Stack-VM complete typed C++20 EDSL runtime emission and ABI extern calls validated.\n"








