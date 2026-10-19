(** examples/pipeline_dump/dump_pipeline.ml

    Replays the exact 10-phase protection chain of the Stack VM packager
    (lib/adapters/protect_adapters/vm_packagers.ml, module
    [Stack_vm_packager]) on a small synthetic program and writes one
    JSON file per phase.

    The dumps are the input of the MATLAB pipeline compatibility analyzer
    (scripts/pipeline_compat.m), which re-implements the runtime
    invariants independently and reports which pass breaks which
    invariant of the previous phase.

    Usage:
      dune exec examples/pipeline_dump/dump_pipeline.exe -- <out_dir>
    Default out_dir: binaries/pipeline_dump *)

open Stack_vm
open Stack_vm.Stack_ir

let out_dir =
  if Array.length Sys.argv > 1 then Sys.argv.(1) else "binaries/pipeline_dump"

(* Two adversarial modes for the analyzer:
   - "--unbalanced": the input block leaves two values on the stack, so
     every phase inherits a non-zero exit delta and only the balance pass
     (phase 7) can repair it.  The compatibility matrix must show the
     violation and the repair.
   - "--adversarial-context": the declared context is larger than the
     slot count the allocator knows about.  The amplifier must NOT shrink
     the declared context (it used to, which turned the program's high
     register slots into out-of-range accesses). *)
let adversarial =
  Array.exists (fun a -> a = "--adversarial-context") Sys.argv
let unbalanced =
  Array.exists (fun a -> a = "--unbalanced") Sys.argv

let block_count (prog : program) =
  Hashtbl.fold (fun _ _ acc -> acc + 1) prog.blocks 0

let op_count (prog : program) =
  Hashtbl.fold (fun _ b acc -> acc + List.length b.ops) prog.blocks 0

let dump ~phase (prog : program) =
  let slug = String.map (fun c -> if c = ' ' then '_' else c) phase in
  let path = Filename.concat out_dir (Printf.sprintf "phase_%s.json" slug) in
  let json = Stack_vm.Stack_ir_json.program_to_json ~phase prog in
  Yojson.Safe.to_file path json;
  let inv =
    match Stack_invariants.verify_all_invariants prog with
    | Ok () -> "invariants: OK"
    | Error errs -> Printf.sprintf "invariants: %d VIOLATION(S)" (List.length errs)
  in
  Printf.printf "  %-18s blocks=%-4d ops=%-6d ctx_slots=%-4d  %s\n%!"
    phase (block_count prog) (op_count prog) prog.context_slots inv;
  (match Stack_invariants.verify_all_invariants prog with
  | Ok () -> ()
  | Error errs ->
      List.iter (fun v -> Printf.printf "      ! %s\n" (Stack_invariants.violation_to_string v)) errs)

(* ------------------------------------------------------------------ *)
(* Synthetic input program                                             *)
(* ------------------------------------------------------------------ *)

(* Three blocks: a computed entry, a taken branch and a fall-through.
   The program is stack-balanced and underflow-free BEFORE the passes,
   so any violation reported later is caused by a pass, not by the
   input. *)
let make_input_program ~(ctx : Context_allocator.t) : program =
  (* In the faithful mode the slots stay below the allocator's count; in
     the adversarial mode they sit ABOVE the size the amplifier would
     shrink to, so a shrinking amplifier becomes a real violation. *)
  let slot_a, slot_b, slot_c = if adversarial then (50, 51, 49) else (30, 31, 29) in
  let entry_ops =
    [ PushImm 0xCAFE0000L      (* constant: target of Horner/MBA synthesis *)
    ; PushImm 0x1111L
    ; Mul
    ; PushReg 0
    ; Add
    ; PushReg 1
    ; Add
    ; PopReg slot_a             (* a high slot on purpose: the declared  *)
                                (* context must never shrink below it  *)
    ; PushReg 0
    ; PushReg 1
    ; Add                       (* flags live for the Setcc below     *)
    ; Setcc Vm_ir.Flags.G
    ; PopReg slot_b             (* ctx[slot_b] = flag value            *)
    ; PopReg slot_c             (* drain the Add result -> balanced    *)
    ; PushImm 0L
    ; PushImm 1L
    ; Cmp                       (* flags: 0 != 1 -> NE               *)
    ; JccRel (1, Vm_ir.Flags.NE)
    ; Exit
    ] in
  (* The unbalanced variant drops the PopRegs that drain the stack, so the
     entry block exits with a non-zero delta. *)
  let entry_ops =
    if unbalanced then
      List.filter
        (fun op -> match op with PopReg _ -> false | _ -> true)
        entry_ops
    else entry_ops
  in
  let then_ops = [ PushImm 0xDEADL; PopReg 4; Exit ] in
  let else_ops = [ PushImm 0xBEEFL; PopReg 5; Exit ] in
  let blocks = Hashtbl.create 3 in
  Hashtbl.replace blocks 0 { id = 0; label = "entry"; ops = entry_ops };
  Hashtbl.replace blocks 1 { id = 1; label = "then"; ops = then_ops };
  Hashtbl.replace blocks 2 { id = 2; label = "else"; ops = else_ops };
  (* Faithful to Ir_to_stack.lower_func: the declared context size is the
     allocator's slot count.  The adversarial mode inflates it to expose
     the amplifier's assumption. *)
  let declared =
    if adversarial then Context_allocator.total_slots ctx + 32
    else Context_allocator.total_slots ctx
  in
  { entry_id = 0; blocks; context_slots = declared }

(* ------------------------------------------------------------------ *)

let () =
  if not (Sys.file_exists out_dir) then Unix.mkdir out_dir 0o755;
  Printf.printf "\nAsgard-5877 — 10-phase pipeline dump -> %s%s\n\n" out_dir
    (if adversarial then "  [ADVERSARIAL CONTEXT MODE]" else "");

  let ctx = Context_allocator.create () in
  let prog = make_input_program ~ctx in

  (* Phase 1: lowering output (the lifter/lowering stage is out of scope
     for this harness, the Stack IR is taken as the phase-1 state). *)
  let prog = ref prog in
  dump ~phase:"1-lowered" !prog;

  (* Phase 2a: superoperator fusion on the original instructions *)
  let superop_cfg = Stack_superop_pass.default_superop_config 0x2AL in
  prog := Stack_superop_pass.apply_program superop_cfg !prog;
  dump ~phase:"2a-pre-superop" !prog;

  (* Phase 2: mathematical bytecode amplification *)
  let amp_profile = Bytecode_amplifier.adaptive_profile () in
  prog := Bytecode_amplifier.amplify_stack_program (Random.State.make [| 0x5877 |])
            ~ctx ~profile:amp_profile !prog;
  dump ~phase:"2-amplified" !prog;

  (* Phase 2a (post): superoperator fusion on the synthesized constants *)
  prog := Stack_superop_pass.apply_program superop_cfg !prog;
  dump ~phase:"2a-post-superop" !prog;

  (* Phase 2b: MBA constant synthesis *)
  let mba_cfg = Stack_mba_pass.default_mba_config 0x2BL in
  prog := Stack_mba_pass.apply_program mba_cfg !prog;
  dump ~phase:"2b-mba" !prog;

  (* Phase 3: virtual CFG flattening *)
  let cff_cfg = Stack_cff_pass.default_cff_config 0x2CL in
  prog := Stack_cff_pass.apply_program cff_cfg ctx !prog;
  dump ~phase:"3-cff" !prog;

  (* Phase 4: spaghetti control-flow splitting *)
  let cur_b = Hashtbl.length !prog.blocks in
  let spaghetti_cfg =
    { (Stack_spaghetti_pass.default_spaghetti_config 0x2DL) with
      max_blocks = cur_b + max 16 (min 128 (cur_b / 4)) }
  in
  prog := Stack_spaghetti_pass.apply_program spaghetti_cfg !prog;
  dump ~phase:"4-spaghetti" !prog;

  (* Phase 5: ghost stack padding *)
  let ghost_cfg = Stack_ghost_pass.default_ghost_config 0x2EL in
  prog := Stack_ghost_pass.apply_program ghost_cfg ctx !prog;
  dump ~phase:"5-ghost" !prog;

  (* Phase 6: state-feedback rolling key *)
  let feedback_cfg = Stack_feedback_pass.default_feedback_config 0x2FL in
  prog := Stack_feedback_pass.apply_program feedback_cfg !prog;
  dump ~phase:"6-feedback" !prog;

  (* Phase 7: stack balance repair *)
  prog := Stack_balance_pass.repair_program ctx !prog;
  dump ~phase:"7-balance" !prog;

  Printf.printf "\nDone. 10 phase dumps written to %s.\n\n" out_dir
