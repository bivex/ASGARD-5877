(** E-graph Equality Expansion (Scrambler, arXiv:2603.03624).

    A minimal egg-style e-graph (union-find + congruence closure + pattern
    rewrite rules) used for *Equality Expansion* — the dual of classic
    Equality Saturation: rewrite rules grow the graph toward the most
    complex equivalent expression, and extraction {b maximizes}
    (AST size, MBA alternation) instead of minimizing cost.

    Every rewrite rule is a verified identity from [Mba], so extracted
    expressions are semantically equivalent to the input by construction —
    no SMT solver is needed in the synthesis loop. *)

open Vm_ir

(** Budget configuration for the expansion loop. *)
type config = {
  node_limit : int;      (** soft cap on e-graph nodes (default 2000) *)
  time_budget_s : float; (** CPU-seconds budget (default 1.0) *)
  iter_limit : int;      (** max saturation iterations (default 24) *)
}

val default_config : config

(** Saturation / extraction statistics. *)
type stats = {
  iterations : int;            (** saturation iterations executed *)
  classes : int;               (** final e-class count *)
  nodes : int;                 (** final e-node count *)
  unions : int;                (** union-find merges performed *)
  extracted_size : int;        (** AST size of the extracted expression *)
  extracted_alternation : int; (** MBA alternation of the extracted expression *)
}

(** Expand [e] into a semantically equivalent, structurally more complex MBA
    expression. Deterministic for a given rng state; polymorphic across
    different rng states. *)
val expand : rng:Random.State.t -> ?config:config -> Mba.expr -> Mba.expr

(** [expand] with saturation statistics. *)
val expand_full :
  rng:Random.State.t -> ?config:config -> Mba.expr -> Mba.expr * stats

(** Structural metric: total AST node count (leaves included). *)
val ast_size : Mba.expr -> int

(** Structural metric: operator count (leaves excluded). *)
val op_count : Mba.expr -> int

(** MBA alternation: domain switches between arithmetic
    ({!Add}, {!Sub}, {!Mul}, {!Neg}) and boolean ({!And}, {!Or}, {!Xor},
    {!Not}) summed over all root-to-leaf paths. *)
val alternation : Mba.expr -> int

(** Evaluate every rewrite rule LHS/RHS pair under [trials] randomized and
    edge-case assignments; true iff all rules are identities over
    Z_(2^64) (including the degenerate x = y case). *)
val verify_rules : rng:Random.State.t -> trials:int -> bool

(** Number of built-in rewrite rules. *)
val rule_count : int

(** E-graph-based counterpart of [Mba.obfuscate_alu]: expand the ALU
    operation via Equality Expansion and lower it to VM-IR instructions
    writing [dst]. Unsupported operations fall back to a plain ALU op. *)
val obfuscate_alu :
  rng:Random.State.t ->
  ?config:config ->
  dst:Register.t ->
  src1:Ir.operand ->
  src2:Ir.operand ->
  Ir.alu_op ->
  Ir.instr list
