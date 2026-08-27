(** ASGARD-5877: Def-Use Chain Scrambler (Anti-LLVM Deobfuscation)
    Based on research from arXiv:2601.12916:
    "Static Detection of Core Structures in Tigress Virtualization-Based Obfuscation Using an LLVM Pass"
    (An, Lee, Cho, Jan 2026) *)

open Vm_ir

type scramble_level = Light | Aggressive | SOTA

type defuse_config = {
  level : scramble_level;
  alias_depth : int;
  opaque_alias_mask : int64;
}

val default_defuse_config : defuse_config

(** Scrambles def-use chains across all IR basic blocks by inserting aliased memory
    indirections and non-linear pointer transformations to defeat static LLVM IR analyzers. *)
val scramble_func_defuse : ?config:defuse_config -> rng:Random.State.t -> Ir.func -> Ir.func
