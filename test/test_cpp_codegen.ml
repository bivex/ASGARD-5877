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
  Printf.printf "[PASS] Step 5: Vm_mem_handlers (decoys) emitted %d bytes using typed AST.\n" (String.length decoy_code)
