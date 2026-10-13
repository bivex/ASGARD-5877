open Stack_ir

type stack_violation =
  | Underflow of { block_id : int; op_index : int; op : stack_op; depth : int }
  | NonZeroExit of { block_id : int; final_delta : int }
  | DepthMismatchAtMerge of { block_id : int; pred1 : int; depth1 : int; pred2 : int; depth2 : int }

type cfg_violation =
  | MissingEntryBlock of int
  | MissingTargetBlock of { from_block : int; target_block : int }
  | InvalidContextSlot of { block_id : int; op_index : int; slot : int; max_slots : int }
  | MissingTerminator of { block_id : int }

type key_violation =
  | KeyMismatchAtMerge of { block_id : int; pred1 : int; key1 : int64; pred2 : int; key2 : int64 }

type invariant_violation =
  | StackViolation of stack_violation
  | CfgViolation of cfg_violation
  | KeyViolation of key_violation

let violation_to_string = function
  | StackViolation (Underflow { block_id; op_index; op; depth }) ->
      Printf.sprintf "Stack Underflow: block %d, op[%d] '%s' caused stack depth %d (< 0)"
        block_id op_index (op_to_string op) depth
  | StackViolation (NonZeroExit { block_id; final_delta }) ->
      Printf.sprintf "Stack NonZeroExit: block %d finished with non-zero exit delta %d"
        block_id final_delta
  | StackViolation (DepthMismatchAtMerge { block_id; pred1; depth1; pred2; depth2 }) ->
      Printf.sprintf "Stack Depth Mismatch at merge block %d: pred %d enters with depth %d, but pred %d enters with %d"
        block_id pred1 depth1 pred2 depth2
  | CfgViolation (MissingEntryBlock id) ->
      Printf.sprintf "CFG Violation: entry block %d is missing from program block table" id
  | CfgViolation (MissingTargetBlock { from_block; target_block }) ->
      Printf.sprintf "CFG Violation: block %d branches to non-existent target block %d"
        from_block target_block
  | CfgViolation (InvalidContextSlot { block_id; op_index; slot; max_slots }) ->
      Printf.sprintf "CFG Violation: block %d, op[%d] accesses invalid context slot %d (alloc slots = %d)"
        block_id op_index slot max_slots
  | CfgViolation (MissingTerminator { block_id }) ->
      Printf.sprintf "CFG Violation: block %d lacks a valid control-flow terminator" block_id
  | KeyViolation (KeyMismatchAtMerge { block_id; pred1; key1; pred2; key2 }) ->
      Printf.sprintf "Key Invariant Violation: merge block %d receives inconsistent rolling keys: 0x%016LX (from %d) vs 0x%016LX (from %d)"
        block_id key1 pred1 key2 pred2

let get_successors (b : block) : int list =
  List.fold_left (fun acc op ->
    match op with
    | JmpRel target -> target :: acc
    | JccRel (target, _) -> target :: acc
    | _ -> acc
  ) [] b.ops

let check_stack_invariants (prog : program) : (unit, stack_violation list) result =
  let violations = ref [] in

  (* 1. Local block check: prefix non-negative and exit delta = 0 *)
  Hashtbl.iter (fun id b ->
    let depth = ref 0 in
    List.iteri (fun idx op ->
      depth := !depth + stack_delta op;
      if !depth < 0 then
        violations := Underflow { block_id = id; op_index = idx; op; depth = !depth } :: !violations
    ) b.ops;
    if !depth <> 0 then
      violations := NonZeroExit { block_id = id; final_delta = !depth } :: !violations
  ) prog.blocks;

  (* 2. Global CFG stack depth coherence across edges *)
  let entry_depths = Hashtbl.create 32 in
  let queue = Queue.create () in
  if Hashtbl.mem prog.blocks prog.entry_id then begin
    Hashtbl.replace entry_depths prog.entry_id (0, prog.entry_id);
    Queue.push prog.entry_id queue
  end;

  while not (Queue.is_empty queue) do
    let cur_id = Queue.pop queue in
    match Hashtbl.find_opt prog.blocks cur_id with
    | None -> ()
    | Some cur_block ->
        let (cur_entry_depth, _) = Hashtbl.find entry_depths cur_id in
        let cur_exit_depth = List.fold_left (fun acc op -> acc + stack_delta op) cur_entry_depth cur_block.ops in
        let succs = get_successors cur_block in
        List.iter (fun s_id ->
          match Hashtbl.find_opt entry_depths s_id with
          | None ->
              Hashtbl.replace entry_depths s_id (cur_exit_depth, cur_id);
              Queue.push s_id queue
          | Some (prev_depth, prev_pred) ->
              if prev_depth <> cur_exit_depth then
                violations := DepthMismatchAtMerge {
                  block_id = s_id;
                  pred1 = prev_pred;
                  depth1 = prev_depth;
                  pred2 = cur_id;
                  depth2 = cur_exit_depth;
                } :: !violations
        ) succs
  done;

  if !violations = [] then Ok () else Error (List.rev !violations)

let check_cfg_invariants (prog : program) : (unit, cfg_violation list) result =
  let violations = ref [] in

  if not (Hashtbl.mem prog.blocks prog.entry_id) then
    violations := MissingEntryBlock prog.entry_id :: !violations;

  Hashtbl.iter (fun id b ->
    (* Check context slot bounds *)
    let check_slot idx slot =
      if slot < 0 || slot >= prog.context_slots then
        violations := InvalidContextSlot {
          block_id = id;
          op_index = idx;
          slot;
          max_slots = prog.context_slots;
        } :: !violations
    in
    List.iteri (fun idx op ->
      match op with
      | PushReg s | PopReg s -> check_slot idx s
      | Cmov (_, s) -> check_slot idx s
      | SetRegImm (s, _) | AddRegImm (s, _) -> check_slot idx s
      | KeyFeedback (s, _) -> check_slot idx s
      | _ -> ()
    ) b.ops;

    (* Check jump targets *)
    let succs = get_successors b in
    List.iter (fun tgt ->
      if not (Hashtbl.mem prog.blocks tgt) then
        violations := MissingTargetBlock { from_block = id; target_block = tgt } :: !violations
    ) succs;

    (* Check terminator presence *)
    let has_term = List.exists Stack_balance_pass.is_terminator b.ops in
    if not has_term then
      violations := MissingTerminator { block_id = id } :: !violations
  ) prog.blocks;

  if !violations = [] then Ok () else Error (List.rev !violations)

let check_key_invariants ?(initial_key = 0L) (prog : program) : (unit, key_violation list) result =
  let violations = ref [] in
  let block_entry_keys = Hashtbl.create 32 in
  let queue = Queue.create () in

  if Hashtbl.mem prog.blocks prog.entry_id then begin
    Hashtbl.replace block_entry_keys prog.entry_id (initial_key, prog.entry_id);
    Queue.push prog.entry_id queue
  end;

  while not (Queue.is_empty queue) do
    let cur_id = Queue.pop queue in
    match Hashtbl.find_opt prog.blocks cur_id with
    | None -> ()
    | Some cur_block ->
        let (cur_entry_key, _) = Hashtbl.find block_entry_keys cur_id in
        let cur_exit_key =
          List.fold_left (fun k op ->
            match op with
            | KeyAdjust delta -> Int64.logxor k delta
            | _ -> k
          ) cur_entry_key cur_block.ops
        in
        let succs = get_successors cur_block in
        List.iter (fun s_id ->
          match Hashtbl.find_opt block_entry_keys s_id with
          | None ->
              Hashtbl.replace block_entry_keys s_id (cur_exit_key, cur_id);
              Queue.push s_id queue
          | Some (prev_key, prev_pred) ->
              if prev_key <> cur_exit_key then
                violations := KeyMismatchAtMerge {
                  block_id = s_id;
                  pred1 = prev_pred;
                  key1 = prev_key;
                  pred2 = cur_id;
                  key2 = cur_exit_key;
                } :: !violations
        ) succs
  done;

  if !violations = [] then Ok () else Error (List.rev !violations)

let verify_all_invariants ?initial_key (prog : program) : (unit, invariant_violation list) result =
  let all = ref [] in
  (match check_stack_invariants prog with
   | Ok () -> ()
   | Error errs -> all := !all @ List.map (fun v -> StackViolation v) errs);
  (match check_cfg_invariants prog with
   | Ok () -> ()
   | Error errs -> all := !all @ List.map (fun v -> CfgViolation v) errs);
  (match check_key_invariants ?initial_key prog with
   | Ok () -> ()
   | Error errs -> all := !all @ List.map (fun v -> KeyViolation v) errs);
  if !all = [] then Ok () else Error !all
