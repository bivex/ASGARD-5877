open Vm_ir

type cff_options = {
  inject_opaque_predicates : bool;
  obfuscate_states : bool;
  input_tainted_transitions : bool;
  split_rate : int;   (** 0..100: probability of splitting a block into two state aliases *)
  hub_count : int;    (** 1..6: number of dispatcher hubs for multi-hub partitioning *)
}

let default_cff_options = {
  inject_opaque_predicates = false; (* default false, can enable explicitly *)
  obfuscate_states = true;
  input_tainted_transitions = false;
  split_rate = 30;
  hub_count = 1;
}


let inject_opaque_predicate ?next_block_id ~rng ~trap_block_id (b : Ir.basic_block) =
  let _ = rng in
  let target_next =
    match next_block_id with
    | Some id -> Ir.BlockId id
    | None -> (if b.label <> "" then Ir.Label b.label else Ir.BlockId b.id)
  in
  (* Invariant: (x & (x + 1)) & 1 is always 0 because x and x+1 have opposite parities *)
  let opaque_check = [
    Ir.Mov { dst = Ir.Reg Register.vtmp0; src = Ir.Reg Register.rax };
    Ir.Alu { op = Ir.Add; dst = Register.vtmp1; src1 = Ir.Reg Register.vtmp0; src2 = Ir.Imm 1L; set_flags = false };
    Ir.Alu { op = Ir.And; dst = Register.vtmp0; src1 = Ir.Reg Register.vtmp0; src2 = Ir.Reg Register.vtmp1; set_flags = false };
    Ir.Alu { op = Ir.And; dst = Register.vtmp0; src1 = Ir.Reg Register.vtmp0; src2 = Ir.Imm 1L; set_flags = true };
    Ir.Cmp { src1 = Ir.Reg Register.vtmp0; src2 = Ir.Imm 0L };
    (* If not equal to 0 (which is mathematically impossible), jump to trap *)
    Ir.Jcc { cond = Flags.NE; target_true = Ir.BlockId trap_block_id; target_false = target_next };
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

let kronecker_product_states ~(base_states : int64 list) ~(dim : int) ~(seed : int64) : int64 list =
  let factors = List.init dim (fun i ->
    Int64.add seed (Int64.shift_left (Int64.of_int (i + 1)) 32)
  ) in
  List.concat_map (fun s ->
    List.map (fun f -> Int64.logxor s f) factors
  ) base_states

let split_hot_states ~(sorted_orig : Ir.basic_block list) ~(split_rate : int) ~rng ~(used_states : (int64, unit) Hashtbl.t) =
  let clone_map = Hashtbl.create (List.length sorted_orig) in
  let clone_entries = ref [] in
  if split_rate > 0 then
    List.iter
      (fun (b : Ir.basic_block) ->
        if Random.State.int rng 100 < split_rate then begin
          let rec gen_clone_state () =
            let s = Int64.logand (Int64.of_int32 (Random.State.int32 rng Int32.max_int)) 0xFFFFFFFEL in
            let s = if s = 0L then 0x200L else s in
            if Hashtbl.mem used_states s then gen_clone_state ()
            else begin
              Hashtbl.replace used_states s ();
              s
            end
          in
          let cs = gen_clone_state () in
          Hashtbl.replace clone_map b.id cs;
          clone_entries := (cs, b.id) :: !clone_entries
        end)
      sorted_orig;
  (clone_map, !clone_entries)

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

    let state_pool = Hashtbl.create n in
    List.iter (fun (b : Ir.basic_block) ->
      Hashtbl.replace state_pool b.id [get_state b.id]
    ) sorted_orig;

    (* State splitting: generate state aliases for blocks based on split_rate *)
    let (clone_map, clone_entries_list) =
      split_hot_states ~sorted_orig ~split_rate:options.split_rate ~rng ~used_states
    in
    let clone_entries = ref clone_entries_list in
    Hashtbl.iter (fun bid cs ->
      let cur = match Hashtbl.find_opt state_pool bid with Some l -> l | None -> [get_state bid] in
      Hashtbl.replace state_pool bid (cs :: cur)
    ) clone_map;

    (* Kronecker product state expansion: create non-isomorphic algebraic state clusters *)
    if options.obfuscate_states then begin
      let kron_seed = Random.State.int64 rng Int64.max_int in
      List.iter (fun (b : Ir.basic_block) ->
        let base_s = get_state b.id in
        let ks_list = kronecker_product_states ~base_states:[base_s] ~dim:2 ~seed:kron_seed in
        List.iter (fun ks ->
          if ks <> 0L && not (Hashtbl.mem used_states ks) then begin
            Hashtbl.replace used_states ks ();
            clone_entries := (ks, b.id) :: !clone_entries;
            let cur = match Hashtbl.find_opt state_pool b.id with Some l -> l | None -> [base_s] in
            Hashtbl.replace state_pool b.id (ks :: cur)
          end
        ) ks_list
      ) sorted_orig
    end;

    let get_target_state bid =
      match Hashtbl.find_opt state_pool bid with
      | Some pool when pool <> [] ->
          let idx = Random.State.int rng (List.length pool) in
          List.nth pool idx
      | _ -> get_state bid
    in

    (* P1-03: Input-tainted state transitions against Triton/angr DSE:
       dispatch variables depend on dynamic register hash:
       state <- (state * C1 + (input_reg >> 32)) mod M *)
    let c1 =
      let r = Random.State.int64 rng Int64.max_int in
      let c = Int64.logor r 1L in
      if c = 0L then 0x517CC1B727220A95L else c
    in

    let input_reg = Register.rdi in

    let emit_set_state_tainted dst_reg target_state =
      if options.input_tainted_transitions then [
        Ir.Mov { dst = Ir.Reg Register.vtmp2; src = Ir.Reg input_reg };
        Ir.Alu { op = Ir.Shr; dst = Register.vtmp2; src1 = Ir.Reg Register.vtmp2; src2 = Ir.Imm 32L; set_flags = false };
        Ir.Mov { dst = Ir.Reg dst_reg; src = Ir.Imm (Int64.mul target_state c1) };
        Ir.Alu { op = Ir.Add; dst = dst_reg; src1 = Ir.Reg dst_reg; src2 = Ir.Reg Register.vtmp2; set_flags = false };
      ] else [
        Ir.Mov { dst = Ir.Reg dst_reg; src = Ir.Imm target_state };
      ]
    in

    (* Entry Block: sets state to func.cfg.entry_id's state and jumps to disp_base_id *)
    let initial_state = get_state func.cfg.entry_id in
    let entry_instrs =
      (emit_set_state_tainted Register.vkey initial_state) @ [
        Ir.Jmp (Ir.BlockId disp_base_id);
      ]
    in
    let entry_block = Ir.make_block ~id:entry_block_id ~label:(func.name ^ "_cff_entry") ~instrs:entry_instrs in

    (* Trap Block *)
    let trap_block = Ir.make_block ~id:trap_block_id ~label:(func.name ^ "_cff_trap") ~instrs:[ Ir.Trap "CFF State Violation" ] in

    (* Dispatch Blocks Ladder: primary blocks + clone alias blocks *)
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

    let primary_targets = List.map (fun (b : Ir.basic_block) -> (get_state b.id, b.id)) ladder_blocks in
    let all_targets = primary_targets @ (List.rev !clone_entries) in
    let total_disp = List.length all_targets in

    let disp_blocks = ref [] in
    for i = 0 to total_disp - 1 do
      let cur_disp_id = disp_base_id + i in
      let next_disp_target =
        if i + 1 < total_disp then Ir.BlockId (disp_base_id + i + 1)
        else Ir.BlockId trap_block_id
      in
      let (target_state, target_bid) = List.nth all_targets i in
      let d_instrs =
        if options.input_tainted_transitions then [
          Ir.Mov { dst = Ir.Reg Register.vtmp2; src = Ir.Reg input_reg };
          Ir.Alu { op = Ir.Shr; dst = Register.vtmp2; src1 = Ir.Reg Register.vtmp2; src2 = Ir.Imm 32L; set_flags = false };
          Ir.Mov { dst = Ir.Reg Register.vtmp0; src = Ir.Imm (Int64.mul target_state c1) };
          Ir.Alu { op = Ir.Add; dst = Register.vtmp0; src1 = Ir.Reg Register.vtmp0; src2 = Ir.Reg Register.vtmp2; set_flags = false };
          Ir.Cmp { src1 = Ir.Reg Register.vkey; src2 = Ir.Reg Register.vtmp0 };
          Ir.Jcc { cond = Flags.E; target_true = Ir.BlockId target_bid; target_false = next_disp_target };
        ] else if Int64.shift_right_logical target_state 32 <> 0L || Int64.logand target_state 0x80000000L <> 0L then [
          Ir.Mov { dst = Ir.Reg Register.vtmp0; src = Ir.Imm target_state };
          Ir.Cmp { src1 = Ir.Reg Register.vkey; src2 = Ir.Reg Register.vtmp0 };
          Ir.Jcc { cond = Flags.E; target_true = Ir.BlockId target_bid; target_false = next_disp_target };
        ] else [
          Ir.Cmp { src1 = Ir.Reg Register.vkey; src2 = Ir.Imm target_state };
          Ir.Jcc { cond = Flags.E; target_true = Ir.BlockId target_bid; target_false = next_disp_target };
        ]
      in
      let blk = Ir.make_block ~id:cur_disp_id ~label:(Printf.sprintf "%s_disp_%d" func.name i) ~instrs:d_instrs in
      disp_blocks := blk :: !disp_blocks
    done;

    (* Transform each original block: redirect control flow back to disp_base_id *)
    let next_fresh_id = ref (disp_base_id + total_disp) in
    let transformed_blocks =
      List.concat_map
        (fun (b : Ir.basic_block) ->
          let rev_instrs = List.rev b.instrs in
          let new_instrs =
            match rev_instrs with
            | [] -> [ Ir.Jmp (Ir.BlockId disp_base_id) ]
            | last :: body_rev -> (
                let body = List.rev body_rev in
                match last with
                | Ir.Jmp (Ir.BlockId target_id) ->
                    let next_state = get_target_state target_id in
                    body @ (emit_set_state_tainted Register.vkey next_state) @ [
                      Ir.Jmp (Ir.BlockId disp_base_id);
                    ]
                | Ir.Jcc { cond; target_true = Ir.BlockId t_id; target_false = Ir.BlockId f_id } ->
                    let state_true = get_target_state t_id in
                    let state_false = get_target_state f_id in
                    if options.input_tainted_transitions then
                      let setup_states = [
                        Ir.Mov { dst = Ir.Reg Register.vtmp2; src = Ir.Reg input_reg };
                        Ir.Alu { op = Ir.Shr; dst = Register.vtmp2; src1 = Ir.Reg Register.vtmp2; src2 = Ir.Imm 32L; set_flags = false };
                        Ir.Mov { dst = Ir.Reg Register.vtmp0; src = Ir.Imm (Int64.mul state_true c1) };
                        Ir.Alu { op = Ir.Add; dst = Register.vtmp0; src1 = Ir.Reg Register.vtmp0; src2 = Ir.Reg Register.vtmp2; set_flags = false };
                        Ir.Mov { dst = Ir.Reg Register.vtmp1; src = Ir.Imm (Int64.mul state_false c1) };
                        Ir.Alu { op = Ir.Add; dst = Register.vtmp1; src1 = Ir.Reg Register.vtmp1; src2 = Ir.Reg Register.vtmp2; set_flags = false };
                      ] in
                      (match body_rev with
                      | Ir.Cmp cmp_args :: prev_body_rev ->
                          let prev_body = List.rev prev_body_rev in
                          prev_body @ setup_states @ [
                            Ir.Cmp cmp_args;
                            Ir.Cmov { cond; dst = Register.vtmp1; src = Ir.Reg Register.vtmp0 };
                            Ir.Mov { dst = Ir.Reg Register.vkey; src = Ir.Reg Register.vtmp1 };
                            Ir.Jmp (Ir.BlockId disp_base_id);
                          ]
                      | _ ->
                          body @ [ Ir.Get_flags Register.vtmp3 ] @ setup_states @ [
                            Ir.Set_flags (Ir.Reg Register.vtmp3);
                            Ir.Cmov { cond; dst = Register.vtmp1; src = Ir.Reg Register.vtmp0 };
                            Ir.Mov { dst = Ir.Reg Register.vkey; src = Ir.Reg Register.vtmp1 };
                            Ir.Jmp (Ir.BlockId disp_base_id);
                          ])
                    else
                      (match body_rev with
                      | Ir.Cmp cmp_args :: prev_body_rev ->
                          let prev_body = List.rev prev_body_rev in
                          prev_body @ [
                            Ir.Mov { dst = Ir.Reg Register.vtmp0; src = Ir.Imm state_true };
                            Ir.Mov { dst = Ir.Reg Register.vtmp1; src = Ir.Imm state_false };
                            Ir.Cmp cmp_args;
                            Ir.Cmov { cond; dst = Register.vtmp1; src = Ir.Reg Register.vtmp0 };
                            Ir.Mov { dst = Ir.Reg Register.vkey; src = Ir.Reg Register.vtmp1 };
                            Ir.Jmp (Ir.BlockId disp_base_id);
                          ]
                      | _ ->
                          body @ [
                            Ir.Mov { dst = Ir.Reg Register.vtmp0; src = Ir.Imm state_true };
                            Ir.Mov { dst = Ir.Reg Register.vtmp1; src = Ir.Imm state_false };
                            Ir.Cmov { cond; dst = Register.vtmp1; src = Ir.Reg Register.vtmp0 };
                            Ir.Mov { dst = Ir.Reg Register.vkey; src = Ir.Reg Register.vtmp1 };
                            Ir.Jmp (Ir.BlockId disp_base_id);
                          ])
                | Ir.Ret | Ir.Vm_exit | Ir.Trap _ ->
                    b.instrs
                | other ->
                    body @ [ other; Ir.Jmp (Ir.BlockId disp_base_id) ])
          in
          if options.inject_opaque_predicates && b.id <> func.cfg.entry_id then
            let body_id = !next_fresh_id in
            incr next_fresh_id;
            let pred_block =
              inject_opaque_predicate ~next_block_id:body_id ~rng ~trap_block_id
                { b with instrs = [] }
            in
            let body_block = Ir.make_block ~id:body_id ~label:(b.label ^ "_body") ~instrs:new_instrs in
            [ pred_block; body_block ]
          else
            [ { b with instrs = new_instrs } ])
        sorted_orig
    in

    let all_blocks = (entry_block :: trap_block :: !disp_blocks) @ transformed_blocks in
    let new_func = Ir.make_func ~name:func.name ~entry_id:entry_block_id ~blocks:all_blocks in
    Ok new_func

module Pop_coupler = Pop_coupler
