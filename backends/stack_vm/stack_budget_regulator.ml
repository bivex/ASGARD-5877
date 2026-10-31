(* lib/stack_vm/stack_budget_regulator.ml
   ASGARD-5877: Dynamic budget regulator for Stack-VM pass pipeline *)

open Random_visa_ports
open Stack_ir

type pass_kind =
  | ExpansionPass
  | StructuralPass
  | EssentialPass

type t = {
  budget_bytes : int option;
}

let create ~budget_kb =
  let budget_bytes =
    match budget_kb with
    | Some k when k > 0 -> Some (k * 1024)
    | _ -> None
  in
  { budget_bytes }

let op_byte_cost = function
  | PushImm _ | AddImm _ | SubImm _ | SetRegImm _ | AddRegImm _
  | KeyFeedback _ | KeyAdjust _ -> 16
  | AddImmImm _ | SubImmImm _ -> 24
  | NativeEscape (_, _, _, _, raw_bytes) -> 16 + List.length raw_bytes
  | _ -> 8

let estimate_program_bytes (prog : Stack_ir.program) : int =
  Hashtbl.fold
    (fun _id (b : Stack_ir.block) acc ->
      let block_ops_bytes =
        List.fold_left (fun sum op -> sum + op_byte_cost op) 0 b.ops
      in
      acc + 16 + block_ops_bytes)
    prog.blocks 0

let check_budget_headroom (reg : t) ~(prog : Stack_ir.program) : float =
  match reg.budget_bytes with
  | None -> 1.0
  | Some b ->
      let cur = estimate_program_bytes prog in
      max 0.0 (1.0 -. (float_of_int cur /. float_of_int b))

let throttle_rate (reg : t) ~pass_name ~kind ~nominal_rate ~(prog : Stack_ir.program) : int * float =
  if nominal_rate <= 0 then (0, 0.0)
  else
    match reg.budget_bytes with
    | None -> (nominal_rate, 1.0)
    | Some b ->
        let cur_bytes = float_of_int (estimate_program_bytes prog) in
        let b_bytes = float_of_int b in
        let ratio = cur_bytes /. b_bytes in
        let scale =
          if ratio <= 0.50 then 1.0
          else if ratio <= 0.85 then
            let alpha = (0.85 -. ratio) /. 0.35 in
            match kind with
            | ExpansionPass -> alpha *. alpha
            | StructuralPass -> max 0.30 alpha
            | EssentialPass -> 1.0
          else
            match kind with
            | ExpansionPass -> 0.0
            | StructuralPass -> 0.15
            | EssentialPass -> 1.0
        in
        let effective_rate =
          max 0 (min 100 (int_of_float (Float.round (float_of_int nominal_rate *. scale))))
        in
        if effective_rate < nominal_rate then
          Logger.debugf ~loc:__LOC__ ~section:"BUDGET"
            "Pass '%s' throttled: %d%% -> %d%% (size: %.1f KB / budget: %.1f KB, ratio: %.1f%%)"
            pass_name nominal_rate effective_rate (cur_bytes /. 1024.0) (b_bytes /. 1024.0)
            (ratio *. 100.0);
        (effective_rate, scale)
