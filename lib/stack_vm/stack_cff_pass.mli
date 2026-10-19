(** Virtual CFG Flattening Pass — public interface *)

open Stack_ir

type cff_config = {
  seed : int64;
}

val default_cff_config : int64 -> cff_config

val apply_program : cff_config -> Context_allocator.t -> program -> program

(** The dispatcher state: the VPC context slot and the token every real
    block is addressed by.  On entry to a real block the VPC provably
    holds that block's token (the predecessor writes it before jumping
    to the dispatcher, and the dispatcher only compares it), so the
    value is statically known - which is what the state-feedback pass
    and the encryptor need. *)
type dispatcher_info = {
  vpc_slot : int;
  block_tokens : (int, int64) Hashtbl.t;  (** real block id -> VPC token *)
}

val apply_program_with_info :
  cff_config -> Context_allocator.t -> program -> program * dispatcher_info

val cff_stats      : program -> program -> string
val direct_jmp_count : program -> int
