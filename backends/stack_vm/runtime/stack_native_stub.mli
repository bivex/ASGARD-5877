(** Native Micro-Handler Stub Assembler (Phase 6f / Pass 27) *)

type arch =
  | X86_64
  | AArch64
  | RV64

(** Byte offset of the [ctx] array inside [stack_vm_t]. *)
val ctx_offset : int

(** Maximum stub length accepted by the runtime escape handler. *)
val max_stub_len : int

(** Micro-operation kind identifiers (Add / Sub / Mul). *)
val kind_add : int
val kind_sub : int
val kind_mul : int

(** [emit arch kind a b c] returns the native machine-code bytes (int list)
    implementing [ctx[c] = ctx[a] OP ctx[b]]. *)
val emit : arch -> int -> int -> int -> int -> int list
