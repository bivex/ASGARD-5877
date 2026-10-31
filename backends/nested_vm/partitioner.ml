open Vm_ir

type engine_affinity =
  | Engine_Math
  | Engine_Flow
  | Engine_Memory

type partitioned_block = {
  block : Ir.basic_block;
  engine : engine_affinity;
  is_bridge_entry : bool;
  is_bridge_exit : bool;
}

type partition_report = {
  total_blocks : int;
  math_blocks : int;
  flow_blocks : int;
  memory_blocks : int;
  inter_vm_transitions : int;
  blocks : partitioned_block list;
}

module Node = struct
  type t = int
  let compare = Int.compare
  let hash = Hashtbl.hash
  let equal = Int.equal
end

module CFG = Graph.Imperative.Digraph.ConcreteBidirectional(Node)
module SCC = Graph.Components.Make(CFG)

module EdgeWeight = struct
  type t = int
  let compare = Int.compare
  let default = 0
end

module FlowG = Graph.Imperative.Digraph.ConcreteLabeled(Node)(EdgeWeight)

module FlowInt = struct
  type t = int
  type label = int
  let max_capacity l = l
  let flow _ = 0
  let add = ( + )
  let sub = ( - )
  let zero = 0
  let compare = Int.compare
end

module GT = Graph.Flow.Goldberg_Tarjan(FlowG)(FlowInt)

let build_cfg (f : Ir.func) : CFG.t =
  let g = CFG.create () in
  Hashtbl.iter (fun id _ -> CFG.add_vertex g id) f.cfg.blocks;
  Hashtbl.iter (fun id (b : Ir.basic_block) ->
    let last_instr = match List.rev b.Ir.instrs with hd :: _ -> Some hd | [] -> None in
    match last_instr with
    | Some (Ir.Jmp (BlockId target)) ->
        if Hashtbl.mem f.cfg.blocks target then CFG.add_edge g id target
    | Some (Ir.Jcc { target_true = BlockId t; target_false = BlockId f_id; _ }) ->
        if Hashtbl.mem f.cfg.blocks t then CFG.add_edge g id t;
        if Hashtbl.mem f.cfg.blocks f_id then CFG.add_edge g id f_id
    | _ -> ()
  ) f.cfg.blocks;
  g

module Dot = Graph.Graphviz.Dot(struct
  include CFG
  let edge_attributes _ = []
  let default_edge_attributes _ = []
  let get_subgraph _ = None
  let vertex_attributes v = [`Label (Printf.sprintf "Block_%d" v); `Shape `Box]
  let vertex_name v = Printf.sprintf "node_%d" v
  let default_vertex_attributes _ = []
  let graph_attributes _ = [`Rankdir `TopToBottom]
end)

let export_dot ?func:_ (cfg : CFG.t) : string =
  let buf = Buffer.create 512 in
  let fmt = Format.formatter_of_buffer buf in
  Dot.fprint_graph fmt cfg;
  Format.pp_print_flush fmt ();
  Buffer.contents buf

let score_block (b : Ir.basic_block) : int * int * int =
  let math_score = ref 0 in
  let flow_score = ref 0 in
  let mem_score = ref 0 in
  List.iter (function
    | Ir.Alu _ | Ir.Unary _ -> math_score := !math_score + 2
    | Ir.Cmp _ | Ir.Test _ | Ir.Jcc _ | Ir.Jmp _ -> flow_score := !flow_score + 2
    | Ir.Mov { dst = Mem _; _ } | Ir.Mov { src = Mem _; _ }
    | Ir.Push _ | Ir.Pop _ -> mem_score := !mem_score + 2
    | _ -> ()
  ) b.instrs;
  (!math_score, !flow_score, !mem_score)

let classify_block (b : Ir.basic_block) : engine_affinity =
  let (math_score, flow_score, mem_score) = score_block b in
  if math_score >= flow_score && math_score >= mem_score then
    Engine_Math
  else if flow_score >= mem_score then
    Engine_Flow
  else
    Engine_Memory

let partition_function (f : Ir.func) : partition_report =
  let raw_blocks = Hashtbl.fold (fun _ b acc -> b :: acc) f.cfg.blocks [] in
  let sorted_blocks = List.sort (fun (a : Ir.basic_block) (b : Ir.basic_block) -> compare a.id b.id) raw_blocks in

  let block_count = List.length sorted_blocks in
  let block_engine_map = Hashtbl.create 16 in

  if block_count <= 1 then begin
    List.iter (fun b -> Hashtbl.replace block_engine_map b.Ir.id (classify_block b)) sorted_blocks
  end else begin
    let cfg = build_cfg f in
    let (_scc_count, scc_map) = SCC.scc cfg in

    let s_node = -1 in
    let t_node = -2 in
    let flow_g = FlowG.create () in
    FlowG.add_vertex flow_g s_node;
    FlowG.add_vertex flow_g t_node;

    List.iter (fun (b : Ir.basic_block) ->
      FlowG.add_vertex flow_g b.id;
      let (m_score, f_score, mem_score) = score_block b in
      let cap_s_to_b = max 1 (if m_score >= f_score && m_score > 0 then 10 + (m_score - f_score) * 4 else 1) in
      let cap_b_to_t = max 1 (if f_score > m_score then 10 + (f_score - m_score) * 4 + mem_score else 1) in
      FlowG.add_edge_e flow_g (FlowG.E.create s_node cap_s_to_b b.id);
      FlowG.add_edge_e flow_g (FlowG.E.create b.id cap_b_to_t t_node)
    ) sorted_blocks;

    Hashtbl.iter (fun id (b : Ir.basic_block) ->
      let last_instr = match List.rev b.Ir.instrs with hd :: _ -> Some hd | [] -> None in
      let succs = match last_instr with
        | Some (Ir.Jmp (BlockId target)) -> [target]
        | Some (Ir.Jcc { target_true = BlockId t; target_false = BlockId f_id; _ }) -> [t; f_id]
        | _ -> []
      in
      List.iter (fun succ_id ->
        if Hashtbl.mem f.cfg.blocks succ_id then begin
          let in_loop = scc_map id = scc_map succ_id in
          let w = if in_loop then 20 else 6 in
          FlowG.add_edge_e flow_g (FlowG.E.create id w succ_id);
          FlowG.add_edge_e flow_g (FlowG.E.create succ_id w id)
        end
      ) succs
    ) f.cfg.blocks;

    let (flow_fn, _) = GT.maxflow flow_g s_node t_node in
    let in_s_set = Hashtbl.create (FlowG.nb_vertex flow_g) in
    let q = Queue.create () in
    Hashtbl.replace in_s_set s_node ();
    Queue.push s_node q;
    while not (Queue.is_empty q) do
      let u = Queue.pop q in
      FlowG.iter_succ_e (fun e ->
        let v = FlowG.E.dst e in
        let cap = FlowG.E.label e in
        let f = flow_fn e in
        if cap - f > 0 && not (Hashtbl.mem in_s_set v) then begin
          Hashtbl.replace in_s_set v ();
          Queue.push v q
        end
      ) flow_g u;
      FlowG.iter_pred_e (fun e ->
        let v = FlowG.E.src e in
        let f = flow_fn e in
        if f > 0 && not (Hashtbl.mem in_s_set v) then begin
          Hashtbl.replace in_s_set v ();
          Queue.push v q
        end
      ) flow_g u;
    done;


    List.iter (fun (b : Ir.basic_block) ->
      let (m_score, f_score, mem_score) = score_block b in
      let eng =
        if Hashtbl.mem in_s_set b.id then
          Engine_Math
        else if mem_score > f_score && mem_score > m_score then
          Engine_Memory
        else
          Engine_Flow
      in
      Hashtbl.replace block_engine_map b.id eng
    ) sorted_blocks
  end;

  let pred_engine_cross = Hashtbl.create 16 in
  List.iter (fun (b : Ir.basic_block) ->
    let eng = Hashtbl.find block_engine_map b.id in
    let last_instr = match List.rev b.Ir.instrs with hd :: _ -> Some hd | [] -> None in
    let succs = match last_instr with
      | Some (Ir.Jmp (BlockId target_id)) -> [target_id]
      | Some (Ir.Jcc { target_true = BlockId t_id; target_false = BlockId f_id; _ }) -> [t_id; f_id]
      | _ -> []
    in
    List.iter (fun succ_id ->
      match Hashtbl.find_opt block_engine_map succ_id with
      | Some succ_eng when succ_eng <> eng ->
          Hashtbl.replace pred_engine_cross succ_id true
      | _ -> ()
    ) succs
  ) sorted_blocks;

  let transitions = ref 0 in
  let partitioned = List.map (fun (b : Ir.basic_block) ->
    let eng = Hashtbl.find block_engine_map b.id in
    let has_cross_succ = ref false in
    let last_instr = match List.rev b.Ir.instrs with hd :: _ -> Some hd | [] -> None in
    (match last_instr with
    | Some (Ir.Jmp (BlockId target_id)) ->
        (match Hashtbl.find_opt block_engine_map target_id with
        | Some target_eng when target_eng <> eng ->
            has_cross_succ := true;
            incr transitions
        | _ -> ())
    | Some (Ir.Jcc { target_true = BlockId t_id; target_false = BlockId f_id; _ }) ->
        let t_eng = Hashtbl.find_opt block_engine_map t_id in
        let f_eng = Hashtbl.find_opt block_engine_map f_id in
        if (match t_eng with Some e -> e <> eng | None -> false) ||
           (match f_eng with Some e -> e <> eng | None -> false) then begin
          has_cross_succ := true;
          incr transitions
        end
    | _ -> ());

    {
      block = b;
      engine = eng;
      is_bridge_entry = Hashtbl.mem pred_engine_cross b.id;
      is_bridge_exit = !has_cross_succ;
    }
  ) sorted_blocks in

  let math_count = List.filter (fun p -> p.engine = Engine_Math) partitioned |> List.length in
  let flow_count = List.filter (fun p -> p.engine = Engine_Flow) partitioned |> List.length in
  let mem_count = List.filter (fun p -> p.engine = Engine_Memory) partitioned |> List.length in

  {
    total_blocks = List.length partitioned;
    math_blocks = math_count;
    flow_blocks = flow_count;
    memory_blocks = mem_count;
    inter_vm_transitions = !transitions;
    blocks = partitioned;
  }
