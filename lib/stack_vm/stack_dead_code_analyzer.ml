(** Stack-VM Dead Code Causality Analyzer
    ──────────────────────────────────────
    Implementation of root-cause dead code analysis, causality diagnosis,
    and pipeline phase tracking. *)

open Stack_ir

type dead_reason =
  | Dead_write_unreferenced of { slot : int }
  | Dead_write_overwritten of { slot : int; next_write_pos : int }
  | Stack_pop_to_dead_slot of { slot : int; push_op : string }
  | Structural_identity of { pattern : string; length : int }
  | Algebraic_zero_knot of { formula : string }
  | Redundant_sub_zero_cmp
  | Balance_drain_orphan of { slot : int }
  | Unreachable_block of { block_id : int; label : string }
  | Dead_flag_production of { op_name : string }
  | Slicing_unobservable of { op_name : string }

type dead_instruction = {
  block_id : int;
  pos : int;
  op : stack_op;
  reason : dead_reason;
  category : string;
  culprit_phase_hint : string;
  remediation_hint : string;
}

type causality_summary = {
  total_ops : int;
  dead_ops_count : int;
  dead_ops_ratio : float;
  by_category : (string * int) list;
  by_phase_hint : (string * int) list;
  top_dead_slots : (int * int) list;
  unreachable_blocks : int list;
}

type program_diagnosis = {
  dead_instructions : dead_instruction list;
  summary : causality_summary;
}

type phase_diff = {
  phase_name : string;
  total_ops : int;
  dead_count : int;
  dead_ratio : float;
  new_dead_ops : dead_instruction list;
  culprit_distribution : (string * int) list;
}

let slot_reads = function
  | PushReg r | AddRegImm (r, _) | KeyFeedback (r, _) -> [ r ]
  | _ -> []

let slot_writes = function
  | PopReg r | SetRegImm (r, _) | Cmov (_, r) | AddRegImm (r, _) -> [ r ]
  | _ -> []

let collect_global_reads (prog : program) =
  let reads = Hashtbl.create 64 in
  Hashtbl.iter (fun _ b ->
    List.iter (fun op ->
      List.iter (fun r -> Hashtbl.replace reads r ()) (slot_reads op)
    ) b.ops
  ) prog.blocks;
  reads

let collect_reachable_blocks (prog : program) =
  let reachable = Hashtbl.create (Hashtbl.length prog.blocks) in
  let q = Queue.create () in
  if Hashtbl.mem prog.blocks prog.entry_id then begin
    Queue.push prog.entry_id q;
    Hashtbl.replace reachable prog.entry_id ()
  end;
  while not (Queue.is_empty q) do
    let bid = Queue.pop q in
    match Hashtbl.find_opt prog.blocks bid with
    | None -> ()
    | Some b ->
        List.iter (function
          | JmpRel target ->
              if not (Hashtbl.mem reachable target) then begin
                Hashtbl.replace reachable target ();
                Queue.push target q
              end
          | JccRel (target, _) ->
              if not (Hashtbl.mem reachable target) then begin
                Hashtbl.replace reachable target ();
                Queue.push target q
              end
          | _ -> ()
        ) b.ops
  done;
  reachable

let analyze_block ~global_reads (b : block) : dead_instruction list =
  let ops_arr = Array.of_list b.ops in
  let n = Array.length ops_arr in
  if n = 0 then []
  else
    let flag_live = Stack_flag_liveness.analyze_arr ops_arr in

    (* Map slot -> list of (pos, is_read) events sorted by pos *)
    let events = Hashtbl.create 16 in
    Array.iteri (fun pos op ->
      List.iter (fun r ->
        let l = match Hashtbl.find_opt events r with Some l -> l | None -> [] in
        Hashtbl.replace events r ((pos, true) :: l)
      ) (slot_reads op);
      List.iter (fun r ->
        let l = match Hashtbl.find_opt events r with Some l -> l | None -> [] in
        Hashtbl.replace events r ((pos, false) :: l)
      ) (slot_writes op)
    ) ops_arr;
    Hashtbl.filter_map_inplace (fun _ l -> Some (List.rev l)) events;

    let is_slot_dead_at pos slot =
      match Hashtbl.find_opt events slot with
      | None -> not (Hashtbl.mem global_reads slot)
      | Some evs ->
          let rec find_next = function
            | [] -> not (Hashtbl.mem global_reads slot)
            | (p, is_read) :: rest ->
                if p < pos then find_next rest
                else not is_read (* If first event after pos is a write -> dead *)
          in
          find_next evs
    in

    let get_next_write_pos pos slot =
      match Hashtbl.find_opt events slot with
      | None -> None
      | Some evs ->
          let rec find = function
            | [] -> None
            | (p, is_read) :: rest ->
                if p <= pos then find rest
                else if not is_read then Some p
                else None
          in
          find evs
    in

    let dead_list = ref [] in
    let record ~pos ~op ~reason ~category ~culprit ~remediation =
      dead_list := {
        block_id = b.id;
        pos;
        op;
        reason;
        category;
        culprit_phase_hint = culprit;
        remediation_hint = remediation;
      } :: !dead_list
    in

    let i = ref 0 in
    while !i < n do
      let op = ops_arr.(!i) in
      let pos = !i in

      (* 1. CFF Sub-Zero Redundancy: Sub, PushImm 0L, Cmp *)
      if pos + 2 < n && op = Sub && ops_arr.(pos + 1) = PushImm 0L && ops_arr.(pos + 2) = Cmp then begin
        record ~pos:(pos + 1) ~op:ops_arr.(pos + 1)
          ~reason:Redundant_sub_zero_cmp
          ~category:"CFF Sub-Zero Redundancy"
          ~culprit:"Phase 3 (Stack_cff_pass)"
          ~remediation:"Use Sub condition flags directly without redundant PushImm 0L; Cmp";
        record ~pos:(pos + 2) ~op:ops_arr.(pos + 2)
          ~reason:Redundant_sub_zero_cmp
          ~category:"CFF Sub-Zero Redundancy"
          ~culprit:"Phase 3 (Stack_cff_pass)"
          ~remediation:"Sub already sets ZF/CF/SF/OF flags; remove subsequent zero Cmp";
        i := !i + 3
      end

      (* 2. Stack Pop to Dead Slot: PushImm v, PopReg r *)
      else if pos + 1 < n && (match op with PushImm _ -> true | _ -> false) &&
              (match ops_arr.(pos + 1) with PopReg _ -> true | _ -> false) then begin
        let r = match ops_arr.(pos + 1) with PopReg reg -> reg | _ -> -1 in
        if is_slot_dead_at (pos + 2) r then begin
          let is_balance_drain = r >= 64 in
          let (cat, culprit, remed) =
            if is_balance_drain then
              ("Stack Balance Discard Drain", "Phase 7 (Stack_balance_pass)",
               "Balance pass injected PopReg scratch to satisfy exit delta=0; anchor slot or absorb into live op")
            else
              ("Dead Stack-to-Slot Drain", "Phase 5b (Stack_avid_pass)",
               "Avid junk pushed immediate into unreferenced scratch slot; anchor slot into live def-use chord")
          in
          record ~pos ~op
            ~reason:(Stack_pop_to_dead_slot { slot = r; push_op = "PushImm" })
            ~category:cat ~culprit ~remediation:remed;
          record ~pos:(pos + 1) ~op:ops_arr.(pos + 1)
            ~reason:(if is_balance_drain then Balance_drain_orphan { slot = r }
                     else Dead_write_unreferenced { slot = r })
            ~category:cat ~culprit ~remediation:remed;
          i := !i + 2
        end else begin
          i := !i + 1
        end
      end

      (* 3. Structural Identities: Swap; Swap *)
      else if pos + 1 < n && op = Swap && ops_arr.(pos + 1) = Swap then begin
        record ~pos ~op
          ~reason:(Structural_identity { pattern = "Swap; Swap"; length = 2 })
          ~category:"Structural Identity"
          ~culprit:"Phase 2a (Stack_multiplicity_pass)"
          ~remediation:"Self-inverting Swap pair; replace with non-trivial permutation or omit";
        record ~pos:(pos + 1) ~op:ops_arr.(pos + 1)
          ~reason:(Structural_identity { pattern = "Swap; Swap"; length = 2 })
          ~category:"Structural Identity"
          ~culprit:"Phase 2a (Stack_multiplicity_pass)"
          ~remediation:"Second Swap inverts the first; eliminate redundant identity";
        i := !i + 2
      end

      (* 4. Structural Identities: Rot * 4 *)
      else if pos + 3 < n && op = Rot && ops_arr.(pos + 1) = Rot &&
              ops_arr.(pos + 2) = Rot && ops_arr.(pos + 3) = Rot then begin
        for k = 0 to 3 do
          record ~pos:(pos + k) ~op:ops_arr.(pos + k)
            ~reason:(Structural_identity { pattern = "Rot * 4"; length = 4 })
            ~category:"Structural Identity"
            ~culprit:"Phase 2a (Stack_multiplicity_pass)"
            ~remediation:"Rot is period 3 on 3-stack or period 4; eliminate cyclic identity"
        done;
        i := !i + 4
      end

      (* 5. Algebraic Zero-Knots: PushImm 0L, Add *)
      else if pos + 1 < n && op = PushImm 0L && ops_arr.(pos + 1) = Add then begin
        record ~pos ~op
          ~reason:(Algebraic_zero_knot { formula = "x + 0 == x" })
          ~category:"Algebraic Neutral Element"
          ~culprit:"Phase 5 (Stack_ghost_pass) or Lowering"
          ~remediation:"Adding zero is an identity; replace with non-associative knot or remove";
        record ~pos:(pos + 1) ~op:ops_arr.(pos + 1)
          ~reason:(Algebraic_zero_knot { formula = "x + 0 == x" })
          ~category:"Algebraic Neutral Element"
          ~culprit:"Phase 5 (Stack_ghost_pass) or Lowering"
          ~remediation:"Addition with zero-immediate; remove neutral ALU operation";
        i := !i + 2
      end

      (* 6. Algebraic Zero-Knots: PushImm 1L, Mul *)
      else if pos + 1 < n && op = PushImm 1L && ops_arr.(pos + 1) = Mul then begin
        record ~pos ~op
          ~reason:(Algebraic_zero_knot { formula = "x * 1 == x" })
          ~category:"Algebraic Neutral Element"
          ~culprit:"Phase 2 (Bytecode_amplifier) or Lowering"
          ~remediation:"Multiplying by 1 is identity; remove neutral element";
        record ~pos:(pos + 1) ~op:ops_arr.(pos + 1)
          ~reason:(Algebraic_zero_knot { formula = "x * 1 == x" })
          ~category:"Algebraic Neutral Element"
          ~culprit:"Phase 2 (Bytecode_amplifier) or Lowering"
          ~remediation:"Multiplication by 1; remove neutral ALU operation";
        i := !i + 2
      end

      (* 7. Self-canceling Register: PushReg r, PopReg r *)
      else if pos + 1 < n &&
              (match op with PushReg r1 -> (match ops_arr.(pos + 1) with PopReg r2 -> r1 = r2 | _ -> false) | _ -> false) then begin
        let r = match op with PushReg reg -> reg | _ -> -1 in
        record ~pos ~op
          ~reason:(Structural_identity { pattern = Printf.sprintf "PushReg %d; PopReg %d" r r; length = 2 })
          ~category:"Structural Identity"
          ~culprit:"Phase 2a (Multiplicity) or Lowering"
          ~remediation:"Pushing and immediately popping the same register is a no-op";
        record ~pos:(pos + 1) ~op:ops_arr.(pos + 1)
          ~reason:(Structural_identity { pattern = Printf.sprintf "PushReg %d; PopReg %d" r r; length = 2 })
          ~category:"Structural Identity"
          ~culprit:"Phase 2a (Multiplicity) or Lowering"
          ~remediation:"Redundant register pop back to original slot";
        i := !i + 2
      end

      (* 8. Standalone Dead Register Writes *)
      else begin
        let writes = slot_writes op in
        List.iter (fun r ->
          if is_slot_dead_at (pos + 1) r then begin
            match get_next_write_pos pos r with
            | Some next_pos ->
                record ~pos ~op
                  ~reason:(Dead_write_overwritten { slot = r; next_write_pos = next_pos })
                  ~category:"Overwritten Register Write (WAW)"
                  ~culprit:"Lowering or Phase 5 (Ghost/Avid)"
                  ~remediation:(Printf.sprintf "Slot %d is overwritten at pos %d before any read; remove dead write" r next_pos)
            | None ->
                if not (Hashtbl.mem global_reads r) then
                  record ~pos ~op
                    ~reason:(Dead_write_unreferenced { slot = r })
                    ~category:"Unreferenced Register Write"
                    ~culprit:"Lowering (Unused Arch Register) or Phase 7 (Balance Drain)"
                    ~remediation:(Printf.sprintf "Slot %d is never read globally; anchor slot or prune dead write" r)
          end
        ) writes;

        (* 9. Dead Flag Production: Cmp/Test without downstream flag consumer *)
        if (op = Cmp || op = Test) && not flag_live.(pos + 1) then begin
          record ~pos ~op
            ~reason:(Dead_flag_production { op_name = op_to_string op })
            ~category:"Dead Flag Production"
            ~culprit:"Lowering or Phase 3 (CFF)"
            ~remediation:"Comparison produces status flags that are never tested by JccRel/Setcc/Cmov"
        end;

        i := !i + 1
      end
    done;
    List.rev !dead_list

let analyze_program ?(trace_slicing = false) (prog : program) : program_diagnosis =
  let global_reads = collect_global_reads prog in
  let reachable = collect_reachable_blocks prog in

  let all_dead = ref [] in
  let total_ops = ref 0 in

  (* Detect unreachable blocks *)
  let unreachable_bids = ref [] in
  Hashtbl.iter (fun bid b ->
    if not (Hashtbl.mem reachable bid) && bid <> prog.entry_id then begin
      unreachable_bids := bid :: !unreachable_bids;
      List.iteri (fun pos op ->
        all_dead := {
          block_id = bid;
          pos;
          op;
          reason = Unreachable_block { block_id = bid; label = b.label };
          category = "Unreachable CFG Block";
          culprit_phase_hint = "Phase 4 (Spaghetti) or Phase 3 (CFF Decoy)";
          remediation_hint = "Block has zero incoming edges; remove orphaned block or repair dispatcher routing";
        } :: !all_dead
      ) b.ops
    end
  ) prog.blocks;

  (* Analyze reachable blocks *)
  Hashtbl.iter (fun bid b ->
    total_ops := !total_ops + List.length b.ops;
    if Hashtbl.mem reachable bid || bid = prog.entry_id then begin
      let block_dead = analyze_block ~global_reads b in
      let block_dead =
        if not trace_slicing then block_dead
        else
          let ops_arr = Array.of_list b.ops in
          let n = Array.length ops_arr in
          let needed = Array.make n false in
          let needed_slots = Hashtbl.create 8 in
          let stack_needed = ref 0 in
          for pos = n - 1 downto 0 do
            let op = ops_arr.(pos) in
            let is_sink = match op with
              | CallExtern _ | ResolveSym _ | WriteMem _ | Exit | JmpRel _ | JccRel _ -> true
              | _ -> false
            in
            let writes = slot_writes op in
            let writes_needed = List.exists (Hashtbl.mem needed_slots) writes in
            let pushes = push_weight op in
            let satisfies_stack = !stack_needed > 0 && pushes > 0 in
            if is_sink || writes_needed || satisfies_stack then begin
              needed.(pos) <- true;
              List.iter (Hashtbl.remove needed_slots) writes;
              List.iter (fun r -> Hashtbl.replace needed_slots r ()) (slot_reads op);
              stack_needed := max 0 (!stack_needed - pushes) + pop_weight op
            end
          done;
          let slice_dead = ref [] in
          Array.iteri (fun pos op ->
            if not needed.(pos) && not (List.exists (fun d -> d.pos = pos) block_dead) then
              slice_dead := {
                block_id = b.id;
                pos;
                op;
                reason = Slicing_unobservable { op_name = op_to_string op };
                category = "Slicing Unobservable (Disconnected)";
                culprit_phase_hint = "Phase 2 (Amplification) or Phase 5 (Ghost)";
                remediation_hint = "Instruction does not flow into any observable I/O or control sink; anchor into live dataflow";
              } :: !slice_dead
          ) ops_arr;
          block_dead @ List.rev !slice_dead
      in
      all_dead := List.rev_append block_dead !all_dead
    end
  ) prog.blocks;

  let dead_instructions = List.rev !all_dead in
  let dead_ops_count = List.length dead_instructions in
  let dead_ops_ratio =
    if !total_ops = 0 then 0.0
    else (float_of_int dead_ops_count /. float_of_int !total_ops) *. 100.0
  in

  (* Aggregations *)
  let cat_counts = Hashtbl.create 8 in
  let phase_counts = Hashtbl.create 8 in
  let slot_counts = Hashtbl.create 16 in

  List.iter (fun d ->
    let c = match Hashtbl.find_opt cat_counts d.category with Some n -> n + 1 | None -> 1 in
    Hashtbl.replace cat_counts d.category c;

    let p = match Hashtbl.find_opt phase_counts d.culprit_phase_hint with Some n -> n + 1 | None -> 1 in
    Hashtbl.replace phase_counts d.culprit_phase_hint p;

    match d.reason with
    | Dead_write_unreferenced { slot }
    | Dead_write_overwritten { slot; _ }
    | Stack_pop_to_dead_slot { slot; _ }
    | Balance_drain_orphan { slot } ->
        let s = match Hashtbl.find_opt slot_counts slot with Some n -> n + 1 | None -> 1 in
        Hashtbl.replace slot_counts slot s
    | _ -> ()
  ) dead_instructions;

  let sort_desc tbl =
    let l = Hashtbl.fold (fun k v acc -> (k, v) :: acc) tbl [] in
    List.sort (fun (_, a) (_, b) -> compare b a) l
  in

  let by_category = sort_desc cat_counts in
  let by_phase_hint = sort_desc phase_counts in
  let top_dead_slots =
    let l = Hashtbl.fold (fun k v acc -> (k, v) :: acc) slot_counts [] in
    List.sort (fun (_, a) (_, b) -> compare b a) l
  in

  let summary = {
    total_ops = !total_ops;
    dead_ops_count;
    dead_ops_ratio;
    by_category;
    by_phase_hint;
    top_dead_slots;
    unreachable_blocks = List.sort compare !unreachable_bids;
  } in

  { dead_instructions; summary }

let diagnose_pipeline (phases : (string * program) list) : phase_diff list =
  List.map (fun (name, prog) ->
    let diag = analyze_program prog in
    {
      phase_name = name;
      total_ops = diag.summary.total_ops;
      dead_count = diag.summary.dead_ops_count;
      dead_ratio = diag.summary.dead_ops_ratio;
      new_dead_ops = diag.dead_instructions;
      culprit_distribution = diag.summary.by_phase_hint;
    }
  ) phases

let format_diagnosis_report ?(verbose = false) (diag : program_diagnosis) : string =
  let buf = Buffer.create 2048 in
  let bpf fmt = Printf.bprintf buf fmt in

  bpf "================================================================================\n";
  bpf "               STACK-VM DEAD CODE CAUSALITY ANALYSIS REPORT\n";
  bpf "================================================================================\n";
  bpf "Total Bytecode Operations : %d\n" diag.summary.total_ops;
  bpf "Dead Operations Identified: %d (%.2f%% dead code overhead)\n"
    diag.summary.dead_ops_count diag.summary.dead_ops_ratio;
  bpf "Live Operations (Effective): %d (%.2f%% live rate)\n\n"
    (diag.summary.total_ops - diag.summary.dead_ops_count)
    (100.0 -. diag.summary.dead_ops_ratio);

  bpf "--- BREAKDOWN BY CAUSALITY CATEGORY ---\n";
  if diag.summary.by_category = [] then
    bpf "  [+] Zero dead operations detected! Bytecode is 100%% live.\n"
  else
    List.iter (fun (cat, count) ->
      let pct = (float_of_int count /. float_of_int diag.summary.dead_ops_count) *. 100.0 in
      bpf "  • %-36s : %5d ops (%5.1f%%)\n" cat count pct
    ) diag.summary.by_category;

  bpf "\n--- CULPRIT PIPELINE PHASES (ORIGIN OF DEAD CODE) ---\n";
  if diag.summary.by_phase_hint = [] then
    bpf "  [+] No pipeline phases introduced unanchored dead code.\n"
  else
    List.iter (fun (culprit, count) ->
      let pct = (float_of_int count /. float_of_int diag.summary.dead_ops_count) *. 100.0 in
      bpf "  • %-36s : %5d ops (%5.1f%%)\n" culprit count pct
    ) diag.summary.by_phase_hint;

  if diag.summary.top_dead_slots <> [] then begin
    bpf "\n--- TOP UNREFERENCED / DEAD CONTEXT SLOTS ---\n";
    List.iter (fun (slot, hits) ->
      bpf "  • Context Slot [ctx+%d] : %d dead writes\n" slot hits
    ) (List.filteri (fun i _ -> i < 10) diag.summary.top_dead_slots)
  end;

  if diag.summary.unreachable_blocks <> [] then begin
    bpf "\n--- UNREACHABLE CFG BLOCKS (ORPHANED) ---\n";
    bpf "  • Block IDs: %s\n"
      (String.concat ", " (List.map string_of_int diag.summary.unreachable_blocks))
  end;

  if verbose && diag.dead_instructions <> [] then begin
    bpf "\n--- DETAILED DEAD INSTRUCTION TRACE (SAMPLE 20) ---\n";
    let sample = List.filteri (fun i _ -> i < 20) diag.dead_instructions in
    List.iteri (fun idx d ->
      bpf "  [%2d] Block %d, pos %d: %s\n" (idx + 1) d.block_id d.pos (op_to_string d.op);
      bpf "       Category:    %s\n" d.category;
      bpf "       Culprit:     %s\n" d.culprit_phase_hint;
      bpf "       Remediation: %s\n\n" d.remediation_hint
    ) sample
  end;

  bpf "================================================================================\n";
  Buffer.contents buf

let format_pipeline_diff (phases : (string * program) list) : string =
  let diffs = diagnose_pipeline phases in
  let buf = Buffer.create 2048 in
  let bpf fmt = Printf.bprintf buf fmt in

  bpf "================================================================================\n";
  bpf "         PIPELINE PROGRESSION: DEAD CODE EMERGENCE & CAUSALITY\n";
  bpf "================================================================================\n";
  bpf "%-22s | %10s | %10s | %10s | %s\n"
    "Pipeline Phase" "Total Ops" "Dead Ops" "Dead Ratio" "Primary Culprit Category";
  bpf "-----------------------+------------+------------+------------+---------------------------------\n";

  List.iter (fun d ->
    let primary =
      match d.culprit_distribution with
      | (top, _) :: _ -> top
      | [] -> "None (Clean)"
    in
    bpf "%-22s | %10d | %10d | %9.2f%% | %s\n"
      d.phase_name d.total_ops d.dead_count d.dead_ratio primary
  ) diffs;
  bpf "================================================================================\n";
  Buffer.contents buf
