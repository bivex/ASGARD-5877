(** Pass A: Relational State Encoding Pass
    ────────────────────────────────────────
    Encodes relations between pairs of virtual context registers (rx, ry)
    using reversible Feistel round transformations:
      u = x
      v = y ^ ROL(x, k)
    with exact inverse:
      x = u
      y = v ^ ROL(u, k)

    Destroys independent register taint and isolated-slot memory dumps:
    an analyst inspecting slot ry cannot determine y without solving the
    relational link to rx.
*)

open Stack_ir

type relational_config = {
  enabled : bool;
  shift_k : int;
  seed    : int64;
}

val default_relational_config : int64 -> relational_config

(** Emits Stack-IR sequence encoding (rx, ry) into relational state *)
val emit_relational_encode : rx:int -> ry:int -> k:int -> stack_op list

(** Emits Stack-IR sequence decoding relational state back into (rx, ry) *)
val emit_relational_decode : rx:int -> ry:int -> k:int -> stack_op list

val apply_block :
  relational_config ->
  Context_allocator.t ->
  block ->
  block

val apply_program :
  relational_config ->
  Context_allocator.t ->
  program ->
  program
