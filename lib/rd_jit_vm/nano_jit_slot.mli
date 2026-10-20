(** Single-Block Self-Wiping Nano-JIT (Step 5 Tier-4+):
    Destroys the 'RIP == Instruction' invariant and protects against memory dumpers.
    All basic blocks are decrypted in turn into the same 128-byte slot,
    executed and immediately overwritten with a pseudorandom keystream in the epilogue. *)

type nano_block_ticket = {
  block_id      : int;
  encrypted_bytes : bytes;
  stream_nonce  : int64;
  wipe_gamma    : int64;
}

(** Encryption of a native instruction block (up to 128 bytes) with a stream key for the Nano-JIT slot *)
val seal_nano_block :
  block_id:int -> raw_code:bytes -> master_key:int64 -> nonce:int64 -> nano_block_ticket

(** Simulation of the Nano-JIT slot lifecycle (Materialization -> Execution -> Self-Wipe with the keystream).
    Returns (the decrypted code during execution, the buffer state after wiping) *)
val simulate_nano_slot_lifecycle :
  nano_block_ticket -> master_key:int64 -> bytes * bytes

(** Construction of the C++20 AST of the controller of the self-wiping 128-byte Nano-JIT slot *)
val build_nano_jit_slot_ast : unit -> Cpp_codegen.Cpp_ast.top_decl list

(** Emission of the C++20 controller of the self-wiping 128-byte Nano-JIT slot *)
val emit_self_wiping_nano_jit_hpp : unit -> string
