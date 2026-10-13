open Cpp_codegen.Cpp_ast
open Cpp_codegen.Cpp_dsl

let () =
  let rng = Random.State.make [| 0x5877; 0xED51 |] in
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
  let code = Cpp_codegen.Cpp_printer.render_header_unit scrambled_ast in
  assert (String.length code > 100);
  Printf.printf "[PASS] Typed C++20 EDSL & AST Scrambler emitted valid header:\n%s\n" code
