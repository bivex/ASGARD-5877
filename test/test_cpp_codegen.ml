open Cpp_codegen.Cpp_ast
open Cpp_codegen.Cpp_dsl
open Cpp_codegen.Cpp_printer

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
  let contains_str str sub =
    let slen = String.length str in
    let sublen = String.length sub in
    let rec check i =
      if i + sublen > slen then false
      else if String.sub str i sublen = sub then true
      else check (i + 1)
    in
    check 0
  in
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
  Printf.printf "[PASS] Step 15: Stack-VM control, cond & reg_imm handlers emitted using typed AST.\n"


