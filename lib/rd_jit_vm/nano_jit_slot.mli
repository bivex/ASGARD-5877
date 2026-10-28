(** Single-Block Self-Wiping Nano-JIT & Sealed Nano-Arena (Tier-4+):
    Destroys the 'RIP == Instruction' invariant and protects against memory
    dumpers.  Chunks are decrypted into Golomb-placed slots of a sealed
    arena, executed, and wiped with a Rule 30 (OEIS A269160) gamma.

    OEIS catalogue implemented here: A269160 (wipe gamma), A003022 (slot
    placement), A000201/A001950 (real/honeypot partition), A001511
    (fractal wipe), A000695 (operand blinding), A000166 (register
    derangements), A002487 (Stern affine factors), A000002 (chunk fission,
    consumed by the emitter), A010060 (dummy opcode positions, consumed by
    the emitter). *)

(** Geometry of the sealed arena. *)
val nano_slot_bytes : int
val nano_slot_words : int
val nano_max_chunk_instrs : int
val nano_active_slots : int
val nano_arena_units : int
val nano_kolakoski_scale : int
val golomb5_marks : int64 array

(** OEIS A269160: Rule 30 step on a 64-bit ring. *)
val rule30_step : int64 -> int64

(** SplitMix64 transport keystream word (sealing only; wiping is Rule 30). *)
val keystream_word : int64 -> int64 -> int -> int64

(** Rule 30 wipe gamma for word [w] under (key, nonce). *)
val wipe_gamma_word : int64 -> int64 -> int -> int64

(** OEIS A000695: carry-free X + 2Y operand split and its inverse. *)
val moser_pack : int64 -> int64
val moser_unpack : int64 -> int64

(** OEIS A000002: first [n] terms of the Kolakoski word. *)
val kolakoski : int -> int array

(** OEIS A002487: Stern alpha_n = 2a(n)+1 (64 odd units of Z_2^64). *)
val stern_alphas : int64 array

(** OEIS A000201: branchless Beatty classification of arena unit [u]. *)
val beatty_is_real : int -> bool

(** OEIS A000166: fix-free gprs permutations, packed one nibble per slot. *)
val derangement_tables : int64 array
val perm_tables : int64 array
val perm_identity_index : int
val perm_apply : int64 -> int -> int

(** OEIS A010060: Thue-Morse parity of [n]. *)
val thue_morse : int -> bool

type nano_block_ticket = {
  block_id      : int;
  encrypted_bytes : bytes;
  stream_nonce    : int64;
  wipe_gamma      : int64;
}

(** Encryption of a native instruction block (up to 128 bytes) with a stream
    key for the Nano-JIT slot *)
val seal_nano_block :
  block_id:int -> raw_code:bytes -> master_key:int64 -> nonce:int64 -> nano_block_ticket

(** Simulation of the Nano-JIT slot lifecycle (Materialization -> Execution ->
    Rule 30 Self-Wipe).  Returns (the decrypted code during execution, the
    buffer state after wiping) *)
val simulate_nano_slot_lifecycle :
  nano_block_ticket -> master_key:int64 -> bytes * bytes

(** Construction of the C++20 AST of the standalone single-slot controller. *)
val build_nano_jit_slot_ast : unit -> Cpp_codegen.Cpp_ast.top_decl list

(** Emission of the C++20 controller of the self-wiping 128-byte Nano-JIT slot. *)
val emit_self_wiping_nano_jit_hpp : unit -> string

(** Construction of the C++20 AST of the sealed nano-arena controller
    (Golomb slot placement, Beatty honeypots, fractal wipe, derangement
    shuffle, Stern transfer).  Must be assembled after the RD-JIT types. *)
val build_nano_arena_ast : unit -> Cpp_codegen.Cpp_ast.top_decl list
