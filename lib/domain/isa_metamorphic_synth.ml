open Random_visa_constants.Magic_numbers
open Int64

type addressing_endpoint =
  | EpStack
  | EpReg of int
  | EpAcc of int

type hybrid_routing = {
  dst  : addressing_endpoint;
  src1 : addressing_endpoint;
  src2 : addressing_endpoint;
}

type synthetic_alu_op = {
  opcode_id : int;
  c_xor     : int64;
  c_and     : int64;
  bias      : int64;
}

type alu_basis_pair = {
  psi1   : synthetic_alu_op;
  psi2   : synthetic_alu_op;
  inv_11 : int64;
  inv_12 : int64;
  inv_21 : int64;
  inv_22 : int64;
}

type std_alu_op =
  | StdAdd
  | StdSub
  | StdXor
  | StdAnd
  | StdOr

type isa_radix_spec = {
  n_opcodes   : int;
  n_regs      : int;
  n_routes    : int;
  affine_a    : int64;
  affine_ainv : int64;
  affine_b    : int64;
}

type raw_instruction = {
  opcode   : int;
  rd       : int;
  rs1      : int;
  rs2      : int;
  route_id : int;
  imm16    : int;
}

let inv_odd_64 (a : int64) : int64 =
  if logand a 1L = 0L then
    invalid_arg "Isa_metamorphic_synth.inv_odd_64: multiplier must be odd";
  let step x = mul x (sub 2L (mul a x)) in
  step (step (step (step (step a))))

let rand_bits64 (rng : Random.State.t) : int64 =
  let hi = Random.State.bits rng |> of_int in
  let mid = Random.State.bits rng |> of_int in
  let lo = Random.State.bits rng |> of_int in
  logor (shift_left hi 34) (logor (shift_left mid 4) (logand lo 0xFL))

let synth_orthogonal_alu_basis (rng : Random.State.t) ~(op1_id : int) ~(op2_id : int)
    : alu_basis_pair =
  let rand_odd ()  = logor (rand_bits64 rng) 1L in
  let rand_even () = logand (rand_bits64 rng) (lognot 1L) in

  let a = rand_odd () in
  let b = rand_even () in
  let c = rand_even () in
  let d = rand_odd () in

  let bias1 = rand_bits64 rng in
  let bias2 = rand_bits64 rng in

  (* det = a*d - b*c (odd * odd - even * even = odd, invertible in Z_{2^64}) *)
  let det = sub (mul a d) (mul b c) in
  let det_inv = inv_odd_64 det in

  let inv_11 = mul d det_inv in
  let inv_12 = mul (neg b) det_inv in
  let inv_21 = mul (neg c) det_inv in
  let inv_22 = mul a det_inv in

  {
    psi1 = { opcode_id = op1_id; c_xor = a; c_and = b; bias = bias1 };
    psi2 = { opcode_id = op2_id; c_xor = c; c_and = d; bias = bias2 };
    inv_11; inv_12; inv_21; inv_22;
  }

let eval_synthetic_op (op : synthetic_alu_op) (x : int64) (y : int64) : int64 =
  let x_xor_y = logxor x y in
  let x_and_y = logand x y in
  add (add (mul op.c_xor x_xor_y) (mul op.c_and x_and_y)) op.bias

let lower_std_op_to_basis (basis : alu_basis_pair) (op : std_alu_op)
    : int64 * int64 * int64 =
  let (k_xor, k_and) = match op with
    | StdXor -> (1L, 0L)
    | StdAnd -> (0L, 1L)
    | StdOr  -> (1L, 1L)
    | StdAdd | StdSub -> (1L, 2L)
  in
  let w1 = add (mul k_xor basis.inv_11) (mul k_and basis.inv_21) in
  let w2 = add (mul k_xor basis.inv_12) (mul k_and basis.inv_22) in
  let base_const = neg (add (mul w1 basis.psi1.bias) (mul w2 basis.psi2.bias)) in
  let w_const = if op = StdSub then add base_const 1L else base_const in
  (w1, w2, w_const)

let gen_non_separable_isa_spec (rng : Random.State.t) : isa_radix_spec =
  let primes_reg = [| 19; 23; 29; 31; 37 |] in
  let primes_op  = [| 67; 71; 73; 79; 83; 89; 97; 101; 103; 107; 109; 113 |] in
  let primes_rt  = [| 11; 13; 17; 19 |] in
  let n_regs    = primes_reg.(Random.State.int rng (Array.length primes_reg)) in
  let n_opcodes = primes_op.(Random.State.int rng (Array.length primes_op)) in
  let n_routes  = primes_rt.(Random.State.int rng (Array.length primes_rt)) in
  let affine_a  = logor (rand_bits64 rng) 1L in
  let affine_ainv = inv_odd_64 affine_a in
  let affine_b  = rand_bits64 rng in
  { n_opcodes; n_regs; n_routes; affine_a; affine_ainv; affine_b }

let encode_mixed_radix_insn (spec : isa_radix_spec) (insn : raw_instruction) : int64 =
  if insn.opcode < 0 || insn.opcode >= spec.n_opcodes then
    invalid_arg "encode_mixed_radix_insn: opcode out of range";
  if insn.rd < 0 || insn.rd >= spec.n_regs ||
     insn.rs1 < 0 || insn.rs1 >= spec.n_regs ||
     insn.rs2 < 0 || insn.rs2 >= spec.n_regs then
    invalid_arg "encode_mixed_radix_insn: register index out of range";
  if insn.route_id < 0 || insn.route_id >= spec.n_routes then
    invalid_arg "encode_mixed_radix_insn: route_id out of range";

  let nop = of_int spec.n_opcodes in
  let nr  = of_int spec.n_regs in
  let nrt = of_int spec.n_routes in
  let imm = logand (of_int insn.imm16) 0xFFFFL in

  (* Horner scheme in unsigned arithmetic:
     U = opcode + nop * (rd + nr * (rs1 + nr * (rs2 + nr * (route_id + nrt * imm)))) *)
  let u = add (of_int insn.route_id) (mul nrt imm) in
  let u = add (of_int insn.rs2)      (mul nr u) in
  let u = add (of_int insn.rs1)      (mul nr u) in
  let u = add (of_int insn.rd)       (mul nr u) in
  let u = add (of_int insn.opcode)   (mul nop u) in

  add (mul u spec.affine_a) spec.affine_b

let decode_mixed_radix_insn (spec : isa_radix_spec) (word : int64) : raw_instruction =
  let unmasked = sub word spec.affine_b in
  let u0 = mul unmasked spec.affine_ainv in

  let nop = of_int spec.n_opcodes in
  let nr  = of_int spec.n_regs in
  let nrt = of_int spec.n_routes in

  let opcode = unsigned_rem u0 nop |> to_int in
  let u1     = unsigned_div u0 nop in

  let rd     = unsigned_rem u1 nr |> to_int in
  let u2     = unsigned_div u1 nr in

  let rs1    = unsigned_rem u2 nr |> to_int in
  let u3     = unsigned_div u2 nr in

  let rs2    = unsigned_rem u3 nr |> to_int in
  let u4     = unsigned_div u3 nr in

  let route_id = unsigned_rem u4 nrt |> to_int in
  let imm16    = unsigned_div u4 nrt |> logand 0xFFFFL |> to_int in

  { opcode; rd; rs1; rs2; route_id; imm16 }

let step_mealy_grammar_state ~(state : int64) ~(insn_word : int64) ~(data_invariant : int64) : int64 =
  (* SplitMix64 / Stafford Mix13 nonlinear bijection of the decoder automaton state *)
  let z = add state golden_ratio_64 in
  let z = logxor z ( add insn_word (mul data_invariant splitmix64_gamma) ) in
  let z = mul (logxor z (shift_right_logical z 30)) splitmix64_gamma in
  let z = mul (logxor z (shift_right_logical z 27)) splitmix64_mix in
  logxor z (shift_right_logical z 31)

let next_insn_byte_width ~(state : int64) : int =
  match to_int (logand state 3L) with
  | 0 -> 3  (* Compact stack archetype *)
  | 1 -> 5  (* Two-operand hybrid archetype *)
  | _ -> 8  (* Full-size Mixed-Radix archetype *)

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
