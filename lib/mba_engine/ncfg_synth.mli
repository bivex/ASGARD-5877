(** ASGARD-5877: Non-Context-Free Grammar (NCFG) MBA Synthesizer
    Based on research from arXiv:2506.23634 (gMBA Resistance) & arXiv:2406.10016:
    "gMBA: Expression Semantic Guided Mixed Boolean-Arithmetic Deobfuscation Using Transformer Architectures" *)

open Mba

(** Synthesize a Transformer-resistant NCFG expression for (x XOR y).
    Destroys local operator attention patterns using cross-variable affine bit-matrices. *)
val synthesize_ncfg_xor : rng:Random.State.t -> expr -> expr -> expr

(** Synthesize a Transformer-resistant NCFG expression for (x + y). *)
val synthesize_ncfg_add : rng:Random.State.t -> expr -> expr -> expr

(** Synthesize a Transformer-resistant NCFG expression for (x - y). *)
val synthesize_ncfg_sub : rng:Random.State.t -> expr -> expr -> expr

(** Synthesize a Transformer-resistant NCFG expression for (x & y). *)
val synthesize_ncfg_and : rng:Random.State.t -> expr -> expr -> expr

(** Synthesize a Transformer-resistant NCFG expression for (x | y). *)
val synthesize_ncfg_or : rng:Random.State.t -> expr -> expr -> expr

(** Synthesize a Transformer-resistant NCFG expression for (~x). *)
val synthesize_ncfg_not : rng:Random.State.t -> expr -> expr

(** Synthesize a Transformer-resistant NCFG expression for (-x). *)
val synthesize_ncfg_neg : rng:Random.State.t -> expr -> expr

(** Synthesize a Transformer-resistant NCFG expression for (x * y). *)
val synthesize_ncfg_mul : rng:Random.State.t -> expr -> expr -> expr

(** Rewrites an AST into deep Non-Context-Free MBA representations. *)
val rewrite_ncfg : rng:Random.State.t -> depth:int -> expr -> expr

(** Obfuscate a single ALU operation using the expanded NCFG grammar. *)
val obfuscate_alu :
  rng:Random.State.t ->
  depth:int ->
  dst:Vm_ir.Register.t ->
  src1:Vm_ir.Ir.operand ->
  src2:Vm_ir.Ir.operand ->
  Vm_ir.Ir.alu_op ->
  Vm_ir.Ir.instr list
