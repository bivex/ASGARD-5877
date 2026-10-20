(** Mathematical Bytecode Amplifier for ASGARD-5877:
    densifies the def-use graph of the stack-VM basic blocks without changing semantics.
    Implemented mechanisms (all — identities over Z_{2^64}):
    1. Horner Polynomial Constant Synthesis (destruction of explicit constants):
       PushImm C → polynomial of degree horner_degree with t_0 masking.
    2. Carry-Chain Add/Sub: two-stage ripple via the minterm basis
       NOR/NAND (bridge to Mba_engine.Nullspace_mba) + ring twist
       k_odd * k_inv (Mba_engine.Metamorphic_ring). With live flags the
       replacement ends with a hidden re-definition of CC_OP_ADD/SUB on the
       saved operands (sx, sy) — a PushFlags wrapper is
       incorrect here (it would restore the pre-command flags).
    3. Def-Use Webbing: identity zero Nor(r, Nor(r, r)), wired
       to a random anchor from the ring buffer of the last K writes
       (K = clamp expander_chord_len 1..6) — chords reach long-range up to
       K writes back, not only to the last one.
    4. Ring twist after Mul/Nor/Nand/Shl/Shr/Sar/Div/Idiv: the original
       command stays, on top of it — a flag-neutral invertible
       scaling (x * k) * k^{-1} = x.

    What is NOT implemented yet (declared in the road-map, not here):
    - bit_slice_lanes is used only as an on/off switch for carry-chain
      (the lane count does not parameterize the decomposition);
    - chords are intra-block (no inter-block anchors via Context_allocator);
    - no treewidth estimates in amplifier_stats (only the op-count ratio);
    - Div/Idiv/shifts of variable magnitude are not re-encoded algebraically
      (only the ring twist on top). *)

open Stack_ir

type amplification_profile = {
  horner_degree       : int;   (** Degree of the interpolating constant polynomial (e.g. 2..8) *)
  bit_slice_lanes     : int;   (** 0 = carry-chain disabled; > 0 = enabled (the lane count does not parameterize the decomposition yet) *)
  expander_chord_len  : int;   (** Periodicity of the chords (step) and size of the anchor ring K = clamp 1..6 *)
  expander_chord_rate : int;   (** Probability of inserting expander knots (0..100) *)
}

val default_heavy_profile : amplification_profile
val balanced_profile : amplification_profile
val light_profile : amplification_profile
val adaptive_profile : ?block_size:int -> ?post_mba:bool -> unit -> amplification_profile

val rand_u64 : Random.State.t -> int64

(** Synthesis of a Horner polynomial of degree degree at a random odd point t_0:
    C = ((...(a_d * t_0 + a_{d-1}) * t_0 + ...) * t_0 + a_0) mod 2^64.
    Returns (t_0, [a_d; a_{d-1}; ...; a_0]). *)
val synth_horner_polynomial :
  Random.State.t -> target_const:int64 -> degree:int -> int64 * int64 list

(** Evaluation of the Horner polynomial by its coefficients at the point t_0 (for verification) *)
val eval_horner_polynomial : t0:int64 -> coeffs:int64 list -> int64

(** Generation of a chain of stack operations evaluating the Horner polynomial with t_0 masking.
    Stack delta = +1 (equivalent to PushImm target_const). *)
val emit_horner_stack_insns :
  Random.State.t -> target_const:int64 -> degree:int -> stack_op list

(** Ring twist [PushImm k_odd; Mul; PushImm k_inv; Mul]:
    value- and flag-preserving (Mul is flag-neutral).
    Stack delta = 0. *)
val emit_ring_twist : Random.State.t -> stack_op list

(** Minterm representations over a pair of registers (bridge to Nullspace_mba),
    each leaves one value on the stack. *)
val push_or_regs : int -> int -> stack_op list
val push_and_regs : int -> int -> stack_op list
val push_xor_regs : int -> int -> stack_op list

(** Hidden re-definition of the flags CC_OP_ADD/SUB{src1=sx; src2=sy} after
    a carry-chain replacement with live flags. Delta = 0. *)
val emit_flag_redef_add : int -> int -> stack_op list
val emit_flag_redef_sub : int -> int -> stack_op list

(** Carry network for Add over Z_{2^64} (result = s1 + s2, delta = +1
    from an empty stack; the operands are read from s1/s2).
    The original operands are saved into sx/sy. *)
val emit_carry_chain_add :
  Random.State.t -> s1:int -> s2:int -> sx:int -> sy:int -> stack_op list

(** Carry network for Sub over Z_{2^64} (result = s1 - s2).
    The original y is saved into sy for the flag re-definition. *)
val emit_carry_chain_sub :
  Random.State.t -> s1:int -> s2:int -> sx:int -> sy:int -> stack_op list

(** Identity zero Nor(r, Nor(r, r)) ≡ 0, wired to an anchor register
    (a long-range def-use chord) or to the stack top. Delta = 0. *)
val emit_expander_web_knot :
  Random.State.t -> ?s_reg:int option -> unit -> stack_op list

(** Transformation of a single basic block *)
val amplify_block :
  Random.State.t -> profile:amplification_profile -> scratch_base:int -> block -> block

(** Transformation of a Stack_ir program (determinism: blocks are processed
    in increasing id order). Increases the bytecode size without dead code. *)
val amplify_stack_program :
  Random.State.t -> ?ctx:Context_allocator.t -> profile:amplification_profile -> program -> program

(** Amplification statistics (before vs after; currently only the op-count ratio) *)
val amplifier_stats : program -> program -> string
