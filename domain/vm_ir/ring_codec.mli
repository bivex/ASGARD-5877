(** Affine ring automorphism over Z_{2^64}: φ(x) = a·x + b. *)

type t = {
  a     : int64;
  a_inv : int64;
  b     : int64;
}

val gen : rng:Random.State.t -> unit -> t
val encode : t -> int64 -> int64
val decode : t -> int64 -> int64
val hom_add_fixup : t -> int64
val hom_sub_fixup : t -> int64
val emit_encode : t:t -> dst:Register.t -> Ir.instr list
val emit_decode : t:t -> dst:Register.t -> Ir.instr list
