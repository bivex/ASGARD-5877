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

  (* det = a*d - b*c (нечетное * нечетное - четное * четное = нечетное, обратимо в Z_{2^64}) *)
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
    | StdAdd -> (1L, 2L)
    | StdSub ->
      (* Для вычитания x - y испозьзуется предварительная инверсия второго операнда,
         либо тождество над (x ^ y) и (~x & y); здесь базовое разложение для сумматора *)
      (1L, 2L)
  in
  let w1 = add (mul k_xor basis.inv_11) (mul k_and basis.inv_21) in
  let w2 = add (mul k_xor basis.inv_12) (mul k_and basis.inv_22) in
  let w_const = neg (add (mul w1 basis.psi1.bias) (mul w2 basis.psi2.bias)) in
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

  (* Схема Горнера в беззнаковой арифметике:
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
  (* SplitMix64 / Stafford Mix13 нелинейная биекция состояния автомата декодера *)
  let z = add state 0x9E3779B97F4A7C15L in
  let z = logxor z ( add insn_word (mul data_invariant 0xBF58476D1CE4E5B9L) ) in
  let z = mul (logxor z (shift_right_logical z 30)) 0xBF58476D1CE4E5B9L in
  let z = mul (logxor z (shift_right_logical z 27)) 0x94D049BB133111EBL in
  logxor z (shift_right_logical z 31)

let next_insn_byte_width ~(state : int64) : int =
  match to_int (logand state 3L) with
  | 0 -> 3  (* Компактный стековый архетип *)
  | 1 -> 5  (* Двухоперандный гибридный архетип *)
  | _ -> 8  (* Полноразмерный Mixed-Radix архетип *)

let emit_cpp20_decoder_header (spec : isa_radix_spec) (basis : alu_basis_pair) : string =
  Printf.sprintf
{|#pragma once
// AUTO-GENERATED BY ASGARD-5877 METAMORPHIC ISA SYNTHESIZER
#include <cstdint>

namespace asgard::metamorphic_isa {

struct DecodedInsn {
    uint32_t opcode;
    uint32_t rd;
    uint32_t rs1;
    uint32_t rs2;
    uint32_t route_id;
    uint32_t imm16;
};

constexpr uint64_t ISA_AFFINE_A_INV = 0x%016LxULL;
constexpr uint64_t ISA_AFFINE_B     = 0x%016LxULL;
constexpr uint64_t ISA_N_OPCODES    = %dULL;
constexpr uint64_t ISA_N_REGS       = %dULL;
constexpr uint64_t ISA_N_ROUTES     = %dULL;

__attribute__((always_inline)) inline DecodedInsn decode_insn(
    uint64_t raw_word,
    uint64_t rolling_key
) noexcept {
    uint64_t u = ((raw_word ^ rolling_key) - ISA_AFFINE_B) * ISA_AFFINE_A_INV;
    DecodedInsn out{};
    out.opcode   = static_cast<uint32_t>(u %% ISA_N_OPCODES); u /= ISA_N_OPCODES;
    out.rd       = static_cast<uint32_t>(u %% ISA_N_REGS);    u /= ISA_N_REGS;
    out.rs1      = static_cast<uint32_t>(u %% ISA_N_REGS);    u /= ISA_N_REGS;
    out.rs2      = static_cast<uint32_t>(u %% ISA_N_REGS);    u /= ISA_N_REGS;
    out.route_id = static_cast<uint32_t>(u %% ISA_N_ROUTES);  u /= ISA_N_ROUTES;
    out.imm16    = static_cast<uint32_t>(u & 0xFFFFULL);
    return out;
}

// Synthetic Basis Operator Psi_1 (Opcode %d)
__attribute__((always_inline)) inline uint64_t exec_psi1(uint64_t x, uint64_t y) noexcept {
    constexpr uint64_t C_XOR = 0x%016LxULL;
    constexpr uint64_t C_AND = 0x%016LxULL;
    constexpr uint64_t BIAS  = 0x%016LxULL;
    return C_XOR * (x ^ y) + C_AND * (x & y) + BIAS;
}

// Synthetic Basis Operator Psi_2 (Opcode %d)
__attribute__((always_inline)) inline uint64_t exec_psi2(uint64_t x, uint64_t y) noexcept {
    constexpr uint64_t C_XOR = 0x%016LxULL;
    constexpr uint64_t C_AND = 0x%016LxULL;
    constexpr uint64_t BIAS  = 0x%016LxULL;
    return C_XOR * (x ^ y) + C_AND * (x & y) + BIAS;
}

} // namespace asgard::metamorphic_isa
|}
    spec.affine_ainv
    spec.affine_b
    spec.n_opcodes
    spec.n_regs
    spec.n_routes
    basis.psi1.opcode_id basis.psi1.c_xor basis.psi1.c_and basis.psi1.bias
    basis.psi2.opcode_id basis.psi2.c_xor basis.psi2.c_and basis.psi2.bias
