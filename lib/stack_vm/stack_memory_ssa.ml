(** Pass D: Memory SSA & Alias-Aware Transformation Engine
    ─────────────────────────────────────────────────────────
    Constructs an explicit Memory SSA dependency graph over Stack-IR
    memory operations (ReadMem, WriteMem).
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

let empty_graph = {
  current_version = 0;
  accesses = [];
}

let classify_alias ~addr1 ~width1 ~addr2 ~width2 =
  match addr1, addr2 with
  | Some a1, Some a2 ->
      if a1 = a2 && width1 = width2 then MustAlias
      else
        let a1_end = Int64.add a1 (Int64.of_int width1) in
        let a2_end = Int64.add a2 (Int64.of_int width2) in
        if a1_end <= a2 || a2_end <= a1 then MustDisjoint
        else PartialOverlap
  | _ ->
      MayAlias

let can_forward_store_to_load ~store_addr ~store_width ~load_addr ~load_width ~intervening_stores =
  if classify_alias ~addr1:store_addr ~width1:store_width ~addr2:load_addr ~width2:load_width <> MustAlias then
    false
  else
    (* If any intervening store MayAlias or MustAlias the load address, forwarding is prohibited *)
    List.for_all (fun (i_addr, i_width) ->
      classify_alias ~addr1:i_addr ~width1:i_width ~addr2:load_addr ~width2:load_width = MustDisjoint
    ) intervening_stores

let build_block_memory_ssa (b : block) : memory_ssa_graph =
  let cur_ver = ref 0 in
  let accesses = ref [] in
  List.iter (function
    | WriteMem w ->
        let v_in = !cur_ver in
        let v_out = v_in + 1 in
        cur_ver := v_out;
        accesses := MemStore { ver_in = v_in; ver_out = v_out; addr_offset = None; width = w } :: !accesses
    | ReadMem w ->
        accesses := MemLoad { ver_read = !cur_ver; addr_offset = None; width = w } :: !accesses
    | _ -> ()
  ) b.ops;
  {
    current_version = !cur_ver;
    accesses = List.rev !accesses;
  }
