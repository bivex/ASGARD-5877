type matrix = int64 array array

type affine_bridge = {
  forward_matrix : matrix;
  inverse_matrix : matrix;
  dim : int;
  initial_digest : int64;
}

(** Compute modular inverse in Z/(2^64)Z via Newton-Raphson iterations. *)
val mod_inverse_64 : int64 -> int64

(** Generate an invertible affine bridge matrix over Z/(2^64)Z. *)
val generate_bridge : ?dim:int -> Random.State.t -> affine_bridge

(** Transform a 16-register vector using forward affine morphing:
    V_dst = (M_fwd * V_src) XOR TraceDigest *)
val forward_morph : affine_bridge -> int64 array -> int64 -> int64 array

(** Invert a 16-register vector using inverse affine morphing:
    V_src = M_inv * (V_dst XOR TraceDigest) *)
val inverse_morph : affine_bridge -> int64 array -> int64 -> int64 array

(** Update cumulative cross-VM trace digest:
    K_{t+1} = ROL13(K_t) XOR (Opcode + VIP * 0x9E3779B97F4A7C15) *)
val update_trace_digest : int64 -> int64 -> int64 -> int64

(** Emit C++ In-Place Zero-Bridge transformation helper functions. *)
val emit_cpp_bridge_code : affine_bridge -> string
