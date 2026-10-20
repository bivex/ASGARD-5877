(** Algebraic synthesizer of the metamorphic ISA for ASGARD-5877:
    - Non-separable Mixed-Radix encoding (protection against DSE/Triton bit-tainting)
    - Synthesis of a functionally complete ALU basis in GL(2, Z_{2^64})
    - Mealy stream automaton for dynamic switching of length archetypes
    - Stack-Reg-Accumulator addressing continuum *)

type addressing_endpoint =
  | EpStack                 (** Fetch/store via the top of the virtual stack (TOS) *)
  | EpReg of int            (** Index of the virtual register 0 .. n_regs - 1 *)
  | EpAcc of int            (** Internal shadow accumulator of the dispatcher 0 .. 3 *)

type hybrid_routing = {
  dst  : addressing_endpoint;
  src1 : addressing_endpoint;
  src2 : addressing_endpoint;
}

type synthetic_alu_op = {
  opcode_id : int;
  c_xor     : int64;        (** Coefficient of (x ^ y) *)
  c_and     : int64;        (** Coefficient of (x & y) *)
  bias      : int64;        (** Additive offset constant in Z_{2^64} *)
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
  n_opcodes   : int;        (** Odd/prime opcode base (not a power of 2) *)
  n_regs      : int;        (** Prime register base (not a power of 2) *)
  n_routes    : int;        (** Number of hybrid addressing routes *)
  affine_a    : int64;      (** Odd scrambling multiplier in Z_{2^64} *)
  affine_ainv : int64;      (** Multiplicatively inverse element a^{-1} mod 2^64 *)
  affine_b    : int64;      (** Additive shift *)
}

type raw_instruction = {
  opcode   : int;
  rd       : int;
  rs1      : int;
  rs2      : int;
  route_id : int;
  imm16    : int;
}

(** Computation of a^{-1} mod 2^64 by the Newton-Hensel method for odd a *)
val inv_odd_64 : int64 -> int64

(** Generation of a pair of synthetic operators (\Psi_1, \Psi_2) forming an invertible basis in GL(2, Z_{2^64}) *)
val synth_orthogonal_alu_basis :
  Random.State.t -> op1_id:int -> op2_id:int -> alu_basis_pair

(** Evaluation of the synthetic operator \Psi(x, y) in the reference semantics *)
val eval_synthetic_op : synthetic_alu_op -> int64 -> int64 -> int64

(** Lowering of a standard operation (ADD, XOR, AND, OR) into a linear combination
    of two synthetic operators: w1 * \Psi_1(x,y) + w2 * \Psi_2(x,y) + w_const *)
val lower_std_op_to_basis :
  alu_basis_pair -> std_alu_op -> int64 * int64 * int64

(** Generation of the specification of a non-separable Mixed-Radix codec *)
val gen_non_separable_isa_spec : Random.State.t -> isa_radix_spec

(** Packing of an instruction into a 64-bit word without dedicated bit fields *)
val encode_mixed_radix_insn : isa_radix_spec -> raw_instruction -> int64

(** Decoding of a 64-bit word back into the instruction structure (for verification and tests) *)
val decode_mixed_radix_insn : isa_radix_spec -> int64 -> raw_instruction

(** Step of the Mealy automaton for a context-dependent grammar of the bytecode stream *)
val step_mealy_grammar_state :
  state:int64 -> insn_word:int64 -> data_invariant:int64 -> int64

(** Determination of the byte length (3, 5, 8) of the next instruction from the Mealy automaton state *)
val next_insn_byte_width : state:int64 -> int

(** Construction of a typed C++20 AST for the metamorphic ISA decoder *)
val build_metamorphic_isa_ast :
  isa_radix_spec -> alu_basis_pair -> Cpp_codegen.Cpp_ast.top_decl list

(** Emission of a C++20 header with the decoder and synthetic handlers for the given specification *)
val emit_cpp20_decoder_header : isa_radix_spec -> alu_basis_pair -> string
