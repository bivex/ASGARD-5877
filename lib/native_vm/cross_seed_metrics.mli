(** Cross-seed inter-build entropy metrics.
    Measures structural divergence between two compiled builds of the same
    function with different seeds. *)

open Vm_ir

type cross_seed_report = {
  ngram3_jaccard        : float;   (** Jaccard similarity of IR 3-gram sets (0=disjoint, 1=identical) *)
  cfg_edge_count_delta  : int;     (** |edges(B_s1)| - |edges(B_s2)| *)
  block_count_delta     : int;     (** |blocks(B_s1)| - |blocks(B_s2)| *)
  instr_count_delta     : int;     (** total instruction count delta *)
  passes_disjointness_gate : bool; (** true if ngram3_jaccard < 0.10 *)
}

val compare_builds : f1:Ir.func -> f2:Ir.func -> cross_seed_report
val report_to_string : cross_seed_report -> string
