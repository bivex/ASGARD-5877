open Vm_ir

type cff_options = {
  inject_opaque_predicates : bool;
  obfuscate_states : bool;
}

let default_cff_options = {
  inject_opaque_predicates = false; (* default false, can enable explicitly *)
  obfuscate_states = true;
}

let inject_opaque_predicate ~rng ~trap_block_id (b : Ir.basic_block) =
  let _ = rng in
  (* Invariant: x & 1 and (x + 1) & 1: one is always 0, so x * (x + 1) is always even *)
  let opaque_check = [
    Ir.Mov { dst = Ir.Reg Register.vtmp0; src = Ir.Reg Register.rax };
    Ir.Alu { op = Ir.Add; dst = Register.vtmp1; src1 = Ir.Reg Register.vtmp0; src2 = Ir.Imm 1L; set_flags = false };
    Ir.Alu { op = Ir.And; dst = Register.vtmp0; src1 = Ir.Reg Register.vtmp0; src2 = Ir.Reg Register.vtmp1; set_flags = false };
    Ir.Alu { op = Ir.And; dst = Register.vtmp0; src1 = Ir.Reg Register.vtmp0; src2 = Ir.Imm 1L; set_flags = true };
    Ir.Cmp { src1 = Ir.Reg Register.vtmp0; src2 = Ir.Imm 0L };
    (* If not equal to 0 (which is mathematically impossible), jump to trap *)
    Ir.Jcc { cond = Flags.NE; target_true = Ir.BlockId trap_block_id; target_false = Ir.Label b.label };
  ] in
  { b with instrs = opaque_check @ b.instrs }

module Node = struct
  type t = int
  let compare = Int.compare
  let hash = Hashtbl.hash
  let equal = ( = )
end

module CFG = Graph.Imperative.Digraph.ConcreteBidirectional(Node)
module Dfs = Graph.Traverse.Dfs(CFG)
module Bfs = Graph.Traverse.Bfs(CFG)
module Components = Graph.Components.Make(CFG)
module Topological = Graph.Topological.Make(CFG)
module Dominator = Graph.Dominator.Make(CFG)

type cfg_metrics = {
  num_vertices : int;
  num_edges : int;
  cyclomatic_complexity : int;
  scc_count : int;
  has_cycles : bool;
  loop_headers : int list;
}

let build_cfg (func : Ir.func) : CFG.t =
  let g = CFG.create () in
  let label_to_id = Hashtbl.create 16 in
  Hashtbl.iter (fun _ (b : Ir.basic_block) ->
    CFG.add_vertex g b.id;
    if b.label <> "" then Hashtbl.replace label_to_id b.label b.id
  ) func.cfg.blocks;

  let resolve_target = function
    | Ir.BlockId id -> Some id
    | Ir.Label lbl -> Hashtbl.find_opt label_to_id lbl
    | Ir.TargetImm _ | Ir.TargetReg _ -> None
  in

  Hashtbl.iter (fun _ (b : Ir.basic_block) ->
    match List.rev b.instrs with
    | [] -> ()
    | last :: _ -> (
        match last with
        | Ir.Jmp target -> (
            match resolve_target target with
            | Some tid -> CFG.add_edge g b.id tid
            | None -> ())
        | Ir.Jcc { target_true; target_false; _ } ->
            (match resolve_target target_true with
             | Some tid -> CFG.add_edge g b.id tid
             | None -> ());
            (match resolve_target target_false with
             | Some fid -> CFG.add_edge g b.id fid
             | None -> ())
        | _ -> ()
      )
  ) func.cfg.blocks;
  g

let analyze_cfg ?entry_id (g : CFG.t) : cfg_metrics =
  let num_vertices = CFG.nb_vertex g in
  let num_edges = CFG.nb_edges g in
  let cyclomatic_complexity = max 1 (num_edges - num_vertices + 2) in
  let sccs = Components.scc_list g in
  let scc_count = List.length sccs in
  let has_cycles =
    List.exists (fun scc ->
      match scc with
      | [] -> false
      | [v] -> CFG.mem_edge g v v
      | _ -> true
    ) sccs
  in
  let loop_headers =
    List.fold_left (fun acc scc ->
      let is_cyclic =
        match scc with
        | [] -> false
        | [v] -> CFG.mem_edge g v v
        | _ -> true
      in
      if not is_cyclic then acc
      else
        let scc_set = Hashtbl.create (List.length scc) in
        List.iter (fun v -> Hashtbl.replace scc_set v ()) scc;
        let headers =
          List.filter (fun v ->
            (match entry_id with Some eid -> v = eid | None -> false) ||
            List.exists (fun pred -> not (Hashtbl.mem scc_set pred)) (CFG.pred g v)
          ) scc
        in
        headers @ acc
    ) [] sccs
  in
  {
    num_vertices;
    num_edges;
    cyclomatic_complexity;
    scc_count;
    has_cycles;
    loop_headers = List.sort_uniq Int.compare loop_headers;
  }

let export_dot ?(name = "func_cfg") ?func (g : CFG.t) : string =
  let _ = name in
  let buf = Buffer.create 512 in
  let fmt = Format.formatter_of_buffer buf in
  let module Dot = Graph.Graphviz.Dot(struct
    include CFG
    let edge_attributes _ = []
    let default_edge_attributes _ = []
    let get_subgraph _ = None
    let vertex_attributes v =
      match func with
      | Some (f : Ir.func) -> (
          match Hashtbl.find_opt f.cfg.blocks v with
          | Some b ->
              let lbl =
                if b.label <> "" then
                  Printf.sprintf "bb_%d\\n(%s, %d instrs)" v b.label (List.length b.instrs)
                else
                  Printf.sprintf "bb_%d\\n(%d instrs)" v (List.length b.instrs)
              in
              [`Shape `Box; `Label lbl]
          | None -> [`Shape `Box; `Label (Printf.sprintf "bb_%d" v)])
      | None -> [`Shape `Box; `Label (Printf.sprintf "bb_%d" v)]
    let vertex_name v = Printf.sprintf "node_%d" v
    let default_vertex_attributes _ = []
    let graph_attributes _ = [`Rankdir `TopToBottom]
  end) in
  Dot.fprint_graph fmt g;
  Format.pp_print_flush fmt ();
  Buffer.contents buf

let reachable_blocks ~entry_id (g : CFG.t) : int list =
  let visited = Hashtbl.create 16 in
  let res = ref [] in
  if CFG.mem_vertex g entry_id then begin
    Dfs.prefix_component (fun v ->
      if not (Hashtbl.mem visited v) then begin
        Hashtbl.replace visited v ();
        res := v :: !res
      end
    ) g entry_id;
    List.rev !res
  end else []

let flatten_func ?(options = default_cff_options) ~rng (func : Ir.func) =
  let cfg = build_cfg func in
  let metrics = analyze_cfg ~entry_id:func.cfg.entry_id cfg in
  let original_blocks = Hashtbl.fold (fun _ b acc -> b :: acc) func.cfg.blocks [] in
  let sorted_orig = List.sort (fun (a : Ir.basic_block) (b : Ir.basic_block) -> Int.compare a.id b.id) original_blocks in
  let n = List.length sorted_orig in
  if n <= 1 || metrics.num_vertices <= 1 then
    (* Trivial 1-block function doesn't need flattening *)
    Ok func
  else
    let max_id = List.fold_left (fun acc (b : Ir.basic_block) -> max acc b.id) 0 sorted_orig in
    let entry_block_id = max_id + 1 in
    let trap_block_id = max_id + 2 in
    let disp_base_id = max_id + 3 in

    (* Map block IDs to unique random 64-bit state keys *)
    let state_map = Hashtbl.create n in
    let used_states = Hashtbl.create n in
    List.iter
      (fun (b : Ir.basic_block) ->
        let rec gen_state () =
          let s = Int64.logand (Int64.of_int32 (Random.State.int32 rng Int32.max_int)) 0xFFFFFFFEL in
          let s = if s = 0L then 0x100L else s in
          if Hashtbl.mem used_states s then gen_state ()
          else begin
            Hashtbl.replace used_states s ();
            s
          end
        in
        Hashtbl.replace state_map b.id (gen_state ()))
      sorted_orig;

    let get_state bid =
      match Hashtbl.find_opt state_map bid with
      | Some s -> s
      | None -> 0xDEADBEEFL
    in

    (* Entry Block: sets state to func.cfg.entry_id's state and jumps to disp_base_id *)
    let initial_state = get_state func.cfg.entry_id in
    let entry_instrs = [
      Ir.Mov { dst = Ir.Reg Register.vtmp3; src = Ir.Imm initial_state };
      Ir.Jmp (Ir.BlockId disp_base_id);
    ] in
    let entry_block = Ir.make_block ~id:entry_block_id ~label:(func.name ^ "_cff_entry") ~instrs:entry_instrs in

    (* Trap Block *)
    let trap_block = Ir.make_block ~id:trap_block_id ~label:(func.name ^ "_cff_trap") ~instrs:[ Ir.Trap "CFF State Violation" ] in

    (* Dispatch Blocks Ladder: disp_base_id + i *)
    let ladder_blocks =
      if options.obfuscate_states then begin
        let arr = Array.of_list sorted_orig in
        for i = Array.length arr - 1 downto 1 do
          let j = Random.State.int rng (i + 1) in
          let tmp = arr.(i) in
          arr.(i) <- arr.(j);
          arr.(j) <- tmp
        done;
        Array.to_list arr
      end else
        sorted_orig
    in

    let disp_blocks = ref [] in
    for i = 0 to n - 1 do
      let cur_disp_id = disp_base_id + i in
      let next_disp_target =
        if i + 1 < n then Ir.BlockId (disp_base_id + i + 1)
        else Ir.BlockId trap_block_id
      in
      let target_b = List.nth ladder_blocks i in
      let target_state = get_state target_b.id in
      let d_instrs = [
        Ir.Cmp { src1 = Ir.Reg Register.vtmp3; src2 = Ir.Imm target_state };
        Ir.Jcc { cond = Flags.E; target_true = Ir.BlockId target_b.id; target_false = next_disp_target };
      ] in
      let blk = Ir.make_block ~id:cur_disp_id ~label:(Printf.sprintf "%s_disp_%d" func.name i) ~instrs:d_instrs in
      disp_blocks := blk :: !disp_blocks
    done;

    (* Transform each original block: redirect control flow back to disp_base_id *)
    let transformed_blocks =
      List.map
        (fun (b : Ir.basic_block) ->
          let rev_instrs = List.rev b.instrs in
          let new_instrs =
            match rev_instrs with
            | [] -> [ Ir.Jmp (Ir.BlockId disp_base_id) ]
            | last :: body_rev -> (
                let body = List.rev body_rev in
                match last with
                | Ir.Jmp (Ir.BlockId target_id) ->
                    let next_state = get_state target_id in
                    body @ [
                      Ir.Mov { dst = Ir.Reg Register.vtmp3; src = Ir.Imm next_state };
                      Ir.Jmp (Ir.BlockId disp_base_id);
                    ]
                | Ir.Jcc { cond; target_true = Ir.BlockId t_id; target_false = Ir.BlockId f_id } ->
                    let state_true = get_state t_id in
                    let state_false = get_state f_id in
                    (match body_rev with
                    | Ir.Cmp cmp_args :: prev_body_rev ->
                        let prev_body = List.rev prev_body_rev in
                        prev_body @ [
                          Ir.Mov { dst = Ir.Reg Register.vtmp0; src = Ir.Imm state_true };
                          Ir.Mov { dst = Ir.Reg Register.vtmp1; src = Ir.Imm state_false };
                          Ir.Cmp cmp_args;
                          Ir.Cmov { cond; dst = Register.vtmp1; src = Ir.Reg Register.vtmp0 };
                          Ir.Mov { dst = Ir.Reg Register.vtmp3; src = Ir.Reg Register.vtmp1 };
                          Ir.Jmp (Ir.BlockId disp_base_id);
                        ]
                    | _ ->
                        body @ [
                          Ir.Mov { dst = Ir.Reg Register.vtmp0; src = Ir.Imm state_true };
                          Ir.Mov { dst = Ir.Reg Register.vtmp1; src = Ir.Imm state_false };
                          Ir.Cmov { cond; dst = Register.vtmp1; src = Ir.Reg Register.vtmp0 };
                          Ir.Mov { dst = Ir.Reg Register.vtmp3; src = Ir.Reg Register.vtmp1 };
                          Ir.Jmp (Ir.BlockId disp_base_id);
                        ])
                | Ir.Ret | Ir.Vm_exit | Ir.Trap _ ->
                    b.instrs
                | other ->
                    body @ [ other; Ir.Jmp (Ir.BlockId disp_base_id) ])
          in
          let res_block = { b with instrs = new_instrs } in
          if options.inject_opaque_predicates && b.id <> func.cfg.entry_id then
            inject_opaque_predicate ~rng ~trap_block_id res_block
          else res_block)
        sorted_orig
    in

    let all_blocks = (entry_block :: trap_block :: !disp_blocks) @ transformed_blocks in
    let new_func = Ir.make_func ~name:func.name ~entry_id:entry_block_id ~blocks:all_blocks in
    Ok new_func

module Pop_coupler = Pop_coupler
