(* Metamorphic ISA decoder: C++20 header codegen (Input: Isa_metamorphic_synth spec+basis, Output: header text). *)
(* Split out of domain/isa_metamorphic_synth.ml: emission never belonged to the pure domain layer. *)
open Domain.Isa_metamorphic_synth
open Cpp_codegen.Cpp_ast
open Cpp_codegen.Cpp_dsl

let build_metamorphic_isa_ast (spec : isa_radix_spec) (basis : alu_basis_pair) : top_decl list =
  let extract_field field_name radix_const = [
    (var "out" $. field_name) := cast UInt32 (var "u" %~ var radix_const);
    var "u" /= var radix_const;
  ] in

  let decode_fn = FuncDecl {
    attrs    = [AlwaysInline; NoExcept];
    ret_type = StructType "DecodedInsn";
    name     = "decode_insn";
    params   = [(UInt64, "raw_word"); (UInt64, "rolling_key")];
    body     = [
      let_u64 "u" (((var "raw_word" ^~ var "rolling_key") -~ var "ISA_AFFINE_B") *~ var "ISA_AFFINE_A_INV");
      decl_var (StructType "DecodedInsn") "out";
    ]
    @ extract_field "opcode"   "ISA_N_OPCODES"
    @ extract_field "rd"       "ISA_N_REGS"
    @ extract_field "rs1"      "ISA_N_REGS"
    @ extract_field "rs2"      "ISA_N_REGS"
    @ extract_field "route_id" "ISA_N_ROUTES"
    @ [
      (var "out" $. "imm16") := cast UInt32 (var "u" &~ u64 0xFFFFL);
      ret (var "out");
    ]
  } in

  let make_psi_fn fn_name (op : synthetic_alu_op) = FuncDecl {
    attrs    = [AlwaysInline; NoExcept];
    ret_type = UInt64;
    name     = fn_name;
    params   = [(UInt64, "x"); (UInt64, "y")];
    body     = [
      constexpr_u64 "C_XOR" op.c_xor;
      constexpr_u64 "C_AND" op.c_and;
      constexpr_u64 "BIAS"  op.bias;
      ret ((var "C_XOR" *~ (var "x" ^~ var "y")) +~ (var "C_AND" *~ (var "x" &~ var "y")) +~ var "BIAS");
    ]
  } in

  [
    IncludeSys "cstdint";
    Namespace ("asgard::metamorphic_isa", [
      StructDecl {
        align_as = None;
        name     = "DecodedInsn";
        fields   = [
          (UInt32, "opcode"); (UInt32, "rd"); (UInt32, "rs1");
          (UInt32, "rs2"); (UInt32, "route_id"); (UInt32, "imm16");
        ];
      };
      ConstexprGlobal (UInt64, "ISA_AFFINE_A_INV", u64 spec.affine_ainv);
      ConstexprGlobal (UInt64, "ISA_AFFINE_B",     u64 spec.affine_b);
      ConstexprGlobal (UInt64, "ISA_N_OPCODES",    u64 (Int64.of_int spec.n_opcodes));
      ConstexprGlobal (UInt64, "ISA_N_REGS",       u64 (Int64.of_int spec.n_regs));
      ConstexprGlobal (UInt64, "ISA_N_ROUTES",     u64 (Int64.of_int spec.n_routes));
      decode_fn;
      make_psi_fn "exec_psi1" basis.psi1;
      make_psi_fn "exec_psi2" basis.psi2;
    ])
  ]

let emit_cpp20_decoder_header (spec : isa_radix_spec) (basis : alu_basis_pair) : string =
  let decls = build_metamorphic_isa_ast spec basis in
  Cpp_codegen.Cpp_printer.render_header_unit decls
