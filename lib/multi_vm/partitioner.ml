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

let classify_block (b : Ir.basic_block) : engine_affinity =
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

  if !math_score >= !flow_score && !math_score >= !mem_score then
    Engine_Math
  else if !flow_score >= !mem_score then
    Engine_Flow
  else
    Engine_Memory

let partition_function (f : Ir.func) : partition_report =
  let raw_blocks = Hashtbl.fold (fun _ b acc -> b :: acc) f.cfg.blocks [] in
  let sorted_blocks = List.sort (fun (a : Ir.basic_block) (b : Ir.basic_block) -> compare a.id b.id) raw_blocks in

  let classified = List.map (fun b ->
    let engine = classify_block b in
    (b, engine)
  ) sorted_blocks in

  let block_engine_map = Hashtbl.create 16 in
  List.iter (fun (b, eng) -> Hashtbl.replace block_engine_map b.Ir.id eng) classified;

  let transitions = ref 0 in
  let partitioned = List.map (fun (b, eng) ->
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
      is_bridge_entry = false;
      is_bridge_exit = !has_cross_succ;
    }
  ) classified in

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
