(** Phase 4b (Pass 16): Braided CFG Merging & Decoy Elimination
    ────────────────────────────────────────────────────────────
    Fuses pairs of real, reachable basic blocks (B_A, B_B) into an
    isomorphic braided block B_braid without creating unreachable decoy
    blocks.

    Route Selection:
      A route context slot r_route is set in predecessors to:
        - tau_A when branching to Path A
        - tau_B when branching to Path B
      where delta = tau_B - tau_A is odd and inv = delta^{-1} (mod 2^64).

    Klimov Single-Bit Discriminant:
      d = ((r_route - tau_A) * inv) & 1 in {0, 1}
      - d = 0 for Path A
      - d = 1 for Path B

    Multiplexed Register Updates:
      In Path A: PopReg r -> r = (1 - d) * v_new + d * r_old
      In Path B: PopReg r -> r = d * v_new + (1 - d) * r_old

    Soundness Invariants:
      1. Zero Decoy Blocks: B_braid exits conditionally to the real
         successors Succ_A and Succ_B. Both branch targets are live.
      2. Zero Register Clobber: when d = 0, Path B writes no-op r = r.
         when d = 1, Path A writes no-op r = r.
      3. Stack Balance: B_A and B_B enter and exit at depth 0;
         multiplexed pop clusters maintain exact net delta -1.
*)

open Stack_ir
val mod_inv_64 : int64 -> int64

(** Checks whether two basic blocks have identical non-terminator instruction shapes. *)
val are_isomorphic : block -> block -> bool


type braid_config = {
  enabled : bool;
  rate : int;      (** percentage of candidate block pairs to braid (0..100) *)
  seed : int64;
}

val default_braid_config : int64 -> braid_config

(** Evaluates the Klimov single-bit route discriminant d onto the stack:
    d = ((r_route - tau_A) * inv) & 1.  Stack delta = +1. *)
val emit_route_discriminant :
  route_slot:int ->
  tau_A:int64 ->
  inv:int64 ->
  stack_op list

(** Evaluates discriminant setup: computes both d and 1 - d into
    dedicated scratch slots. Net stack delta = 0. *)
val emit_discriminant_setup :
  route_slot:int ->
  d_slot:int ->
  d_bar_slot:int ->
  tau_A:int64 ->
  inv:int64 ->
  stack_op list

(** Evaluates multiplexed PopReg:
    If is_path_b is false: r = (1 - d) * v_new + d * r_old
    If is_path_b is true:  r = d * v_new + (1 - d) * r_old.
    Consumes [v_new] from stack; net delta = -1. *)
val emit_multiplexed_pop :
  d_slot:int ->
  d_bar_slot:int ->
  target_slot:int ->
  is_path_b:bool ->
  stack_op list

(** Braids a pair of candidate blocks (b_a, b_b) into a single block. *)
val braid_blocks :
  route_slot:int ->
  d_slot:int ->
  d_bar_slot:int ->
  flag_slot:int ->
  tau_A:int64 ->
  inv:int64 ->
  b_a:block ->
  b_b:block ->
  block

(** Applies braided block merging across candidate block pairs in [prog]. *)
val apply_program :
  braid_config ->
  Context_allocator.t ->
  program ->
  program

val braid_stats : program -> program -> string
