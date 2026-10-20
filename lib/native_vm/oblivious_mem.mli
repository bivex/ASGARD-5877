(** Oblivious Memory Layout & Decoy Access Engine (Step 3 Tier-4+):
    Hides the memory access graph from DBI tracers (Tenet / Pin) via:
    1. Bijective shuffling of the local frame slots
    2. Positional tweak-encryption (Tweakable Memory Masking)
    3. Multiple reads (1 true + 3 false) with an arithmetic multiplexer *)

type frame_scrambler = {
  n_slots     : int;     (** Number of 64-bit slots in the frame *)
  coprime_p   : int;     (** Step coprime with n_slots: gcd(p, n_slots) = 1 *)
  inv_p       : int;     (** Inverse index modulo n_slots *)
  offset_q    : int;     (** Slot offset *)
  frame_key   : int64;   (** Tweak-encryption key for the memory cells *)
}

(** Creation of the memory frame scrambler for a given number of slots *)
val gen_frame_scrambler : Random.State.t -> n_slots:int -> frame_scrambler

(** Mapping of the logical slot index [0 .. n_slots-1] to a physical index *)
val logical_to_physical_slot : frame_scrambler -> int -> int

(** Inverse mapping of a physical index to a logical one *)
val physical_to_logical_slot : frame_scrambler -> int -> int

(** Positional gamma for a slot (depending on the logical address and the frame key) *)
val slot_tweak_mask : frame_scrambler -> logical_idx:int -> int64

(** Write into the protected memory frame *)
val oblivious_store : frame_scrambler -> int64 array -> logical_idx:int -> int64 -> unit

(** Read from the protected frame with the generation of 3 false accesses (Decoy Reads)
    and selection of the true value without branching. Returns (value, list of 4 physical trace addresses) *)
val oblivious_load_with_decoys :
  frame_scrambler -> int64 array -> logical_idx:int -> noise_seed:int64 -> int64 * int list

(** Generation of the C++ EDSL AST for asgard::oblivious_mem *)
val emit_oblivious_mem_decls : Random.State.t -> Cpp_codegen.Cpp_ast.top_decl list

(** Generation of the C++ header file asgard::oblivious_mem *)
val emit_oblivious_mem_hpp : Random.State.t -> string
