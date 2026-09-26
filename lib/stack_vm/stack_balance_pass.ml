open Stack_ir

type balance_result = {
  block_id : int;
  max_depth : int;
  final_delta : int;
  is_balanced : bool;
}

let analyze_block block =
  let depth = ref 0 in
  let max_d = ref 0 in
  List.iter (fun op ->
    depth := !depth + stack_delta op;
    if !depth > !max_d then max_d := !depth
  ) block.ops;
  {
    block_id = block.id;
    max_depth = !max_d;
    final_delta = !depth;
    is_balanced = (!depth = 0);
  }

let verify_program prog =
  let errors = ref [] in
  Hashtbl.iter (fun id b ->
    let res = analyze_block b in
    if not res.is_balanced then
      errors := (id, Printf.sprintf "Block %d '%s' is unbalanced: exit delta is %d (expected 0)"
                       id b.label res.final_delta) :: !errors
  ) prog.blocks;
  !errors

let is_terminator = function
  | JmpRel _ | JccRel _ | Exit -> true
  | _ -> false

let repair_block ctx block =
  let res = analyze_block block in
  if res.is_balanced then block
  else if res.final_delta > 0 then
    (* Stack has leftover elements: insert PopReg dummy before terminator *)
    let dummies = List.init res.final_delta (fun _ ->
      PopReg (Context_allocator.alloc_scratch ctx)
    ) in
    (* Split ops into non-terminators and terminators *)
    let non_terms, terms = List.partition (fun op -> not (is_terminator op)) block.ops in
    { block with ops = non_terms @ dummies @ terms }
  else
    (* Stack underflow: insert PushImm 0L at the beginning of the block *)
    let underflow_count = abs res.final_delta in
    let pads = List.init underflow_count (fun _ -> PushImm 0L) in
    { block with ops = pads @ block.ops }

let repair_program ctx prog =
  let new_blocks = Hashtbl.create (Hashtbl.length prog.blocks) in
  Hashtbl.iter (fun id b ->
    Hashtbl.replace new_blocks id (repair_block ctx b)
  ) prog.blocks;
  { prog with blocks = new_blocks }
