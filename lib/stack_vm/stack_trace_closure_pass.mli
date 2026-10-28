(** Phase 5g (Pass 15): T-Function Trace Invariant Closure *)

open Stack_ir

type trace_closure_config = {
  enabled : bool;
  rate : int;   (** percentage of live-write sites to entangle (0..100) *)
  seed : int64;
}

val default_trace_closure_config : int64 -> trace_closure_config

(** Klimov-Shamir T-function T(x) = x + (x^2 | 5) over Z_{2^64}. *)
val t_function : int64 -> int64

(** Compile-time nibble trace mu_k = T^k(g0) & 0xF followed exactly by
    the emitted code's accumulator low nibble (the entropy term is
    16-aligned and never touches bits [0..3]). *)
val nibble_trace : int64 -> int -> int64 array

(** Emits the accumulator closure step onto the stack: [] -> [G'].
    G' = (raw & ~0xF) | (T(G) & 0xF)
    raw = T(G) + 16 * ((live | G) * C_odd).  Stack delta = +1. *)
val emit_t_step :
  g_slot:int ->
  live_slot:int ->
  c_odd:int64 ->
  stack_op list

(** Pre-write entanglement: maps pending value [v] to [v'] =
    v + (G & 0xF) - mu_k (compile-time zero at runtime). *)
val pre_canonical :
  g_slot:int ->
  mu_k:int64 ->
  stack_op list

(** (pre, post) closure pair around a live-write [PushX; PopReg r]:
    pre maps [v] -> [v'] (bit-identical), post steps the accumulator
    with net stack delta 0. *)
val generate_closure_pair :
  g_slot:int ->
  live_slot:int ->
  mu_k:int64 ->
  c_odd:int64 ->
  stack_op list * stack_op list

(** Applies trace closure to a basic block at selected live-write sites. *)
val apply_block :
  trace_closure_config ->
  g_slot:int ->
  live_writes:int list ->
  mu:int64 array ->
  c_odd:int64 ->
  block ->
  block

(** Applies trace closure across the program; allocates the accumulator
    slot and entangles the mapped guest GPR writes. *)
val apply_program :
  trace_closure_config ->
  Context_allocator.t ->
  program ->
  program

val trace_closure_stats : program -> program -> string
