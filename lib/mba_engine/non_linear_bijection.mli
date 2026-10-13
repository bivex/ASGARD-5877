(** ASGARD-5877: Non-linear Bijections & XorShift-Mul Involutions (P1-01)
    Counters SiMBA (Walsh-Hadamard transform) and GAMBA (Gröbner basis)
    algebraic deobfuscation by breaking bit-slice linearity via ring-mixing
    T-functions over Z_{2^64}. *)

open Vm_ir

type involution_params = {
  c : int64;
  c_inv : int64;
  shift : int;
}

val mod_inverse_64 : int64 -> int64

val make_params : ?shift:int -> int64 -> involution_params

val random_params : ?shift:int -> Random.State.t -> involution_params

val forward : involution_params -> int64 -> int64

val inverse : involution_params -> int64 -> int64

val emit_forward_ir : params:involution_params -> dst:Register.t -> src:Register.t -> Ir.instr list

val emit_inverse_ir : params:involution_params -> dst:Register.t -> src:Register.t -> Ir.instr list

val synth_xorshift_involution : rng:Random.State.t -> dst:Register.t -> Ir.instr list

val wrap_non_algebraic_mba : rng:Random.State.t -> dst:Register.t -> Ir.instr list -> Ir.instr list
