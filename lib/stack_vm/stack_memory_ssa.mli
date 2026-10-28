(** Pass D: Memory SSA & Alias-Aware Transformation Engine
    ─────────────────────────────────────────────────────────
    Constructs an explicit Memory SSA dependency graph over Stack-IR
    memory operations (ReadMem, WriteMem):
      M_{i+1} = Store(M_i, addr, val, width)
      val     = Load(M_j, addr, width)

    Models physical address aliasing, byte-range overlaps, and store-load
    forwarding validity:
      - MustAlias: provably identical byte span
      - MustDisjoint: provably disjoint byte spans (|addr1 - addr2| >= width)
      - PartialOverlap: byte spans intersect but addresses differ
      - MayAlias: dynamic addresses with unresolved aliasing

    Guarantees that memory-entanglement passes preserve true observable
    memory semantics under optimizing C++ compilers.
*)

open Stack_ir

type mem_version = int

type alias_relation =
  | MustAlias
  | MustDisjoint
  | PartialOverlap
  | MayAlias

type mem_access =
  | MemStore of { ver_in : mem_version; ver_out : mem_version; addr_offset : int64 option; width : int }
  | MemLoad of { ver_read : mem_version; addr_offset : int64 option; width : int }

type memory_ssa_graph = {
  current_version : mem_version;
  accesses : mem_access list;
}

val empty_graph : memory_ssa_graph

val classify_alias :
  addr1:int64 option -> width1:int ->
  addr2:int64 option -> width2:int ->
  alias_relation

val build_block_memory_ssa : block -> memory_ssa_graph

val can_forward_store_to_load :
  store_addr:int64 option -> store_width:int ->
  load_addr:int64 option -> load_width:int ->
  intervening_stores:(int64 option * int) list ->
  bool
