open Stack_ir

type balance_result = {
  block_id : int;
  max_depth : int;
  min_depth : int;
  final_delta : int;
  is_balanced : bool;
}

let analyze_block block =
  let depth = ref 0 in
  let max_d = ref 0 in
  let min_d = ref 0 in
  List.iter (fun op ->
    depth := !depth + stack_delta op;
    if !depth > !max_d then max_d := !depth;
    if !depth < !min_d then min_d := !depth
  ) block.ops;
  {
    block_id = block.id;
    max_depth = !max_d;
    min_depth = !min_d;
    final_delta = !depth;
    is_balanced = (!depth = 0 && !min_d >= 0);
  }

let verify_program prog =
  let errors = ref [] in
  Hashtbl.iter (fun id b ->
    let res = analyze_block b in
    if not res.is_balanced then
      if res.min_depth < 0 then
        errors := (id, Printf.sprintf "Block %d '%s' has stack underflow: min prefix depth is %d"
                         id b.label res.min_depth) :: !errors
      else
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
  else
    (* Step 1: Fix prefix underflow if min_depth < 0 *)
    let underflow_count = if res.min_depth < 0 then abs res.min_depth else 0 in
    let pads = List.init underflow_count (fun _ -> PushImm 0L) in
    let padded_ops = pads @ block.ops in
    (* Step 2: Calculate leftover elements after prepending pads *)
    let leftover = res.final_delta + underflow_count in
    if leftover <= 0 then
      { block with ops = padded_ops }
    else
      (* Step 3: Stack has leftover elements: insert flag-neutral anchored drains before terminator *)
      let dummies = List.concat (List.init leftover (fun _ ->
        let dummy = Context_allocator.alloc_scratch ctx in
        [ PopReg dummy; PushReg dummy; PushImm 1L; Mul; PopReg dummy ]
      )) in
      let rec split acc = function
        | [] -> (List.rev acc, [])
        | op :: rest when is_terminator op -> (List.rev acc, op :: rest)
        | op :: rest -> split (op :: acc) rest
      in
      let non_terms, terms = split [] padded_ops in
      { block with ops = non_terms @ dummies @ terms }

let repair_program ctx prog =
  let new_blocks = Hashtbl.create (Hashtbl.length prog.blocks) in
  Hashtbl.iter (fun id b ->
    Hashtbl.replace new_blocks id (repair_block ctx b)
  ) prog.blocks;
  (* Dummy PopReg slots may be freshly allocated — grow the context *)
  { prog with
    blocks = new_blocks;
    context_slots = max prog.context_slots (Context_allocator.total_slots ctx) }
