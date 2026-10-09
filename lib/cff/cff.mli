open Vm_ir

type cff_options = {
  inject_opaque_predicates : bool;
  obfuscate_states : bool;
}

val default_cff_options : cff_options

(** Control Flow Graph modeled with OCamlGraph *)
module Node : sig
  type t = int
  val compare : t -> t -> int
  val hash : t -> int
  val equal : t -> t -> bool
end

module CFG : Graph.Sig.I with type V.t = Node.t

type cfg_metrics = {
  num_vertices : int;
  num_edges : int;
  cyclomatic_complexity : int;
  scc_count : int;
  has_cycles : bool;
  loop_headers : int list;
}

(** Build an OCamlGraph directed graph from an IR function. *)
val build_cfg : Ir.func -> CFG.t

(** Analyze structural metrics of a function CFG using OCamlGraph algorithms. *)
val analyze_cfg : ?entry_id:int -> CFG.t -> cfg_metrics

(** Export CFG to Graphviz DOT string representation. *)
val export_dot : ?name:string -> ?func:Ir.func -> CFG.t -> string

(** Returns list of reachable block IDs from entry. *)
val reachable_blocks : entry_id:int -> CFG.t -> int list

(** Flattens the control flow graph of a function into a centralized state dispatcher. *)
val flatten_func :
  ?options:cff_options ->
  rng:Random.State.t ->
  Ir.func ->
  (Ir.func, string) result

(** Injects an opaque predicate into a basic block, creating an invariant conditional branch. *)
val inject_opaque_predicate :
  ?next_block_id:int ->
  rng:Random.State.t ->
  trap_block_id:int ->
  Ir.basic_block ->
  Ir.basic_block

module Pop_coupler : module type of Pop_coupler
