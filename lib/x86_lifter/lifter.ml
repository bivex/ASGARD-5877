open Vm_ir
open X86_parser

type options = {
  function_name : string;
}

let default_options = {
  function_name = "func_virtualized";
}

let ( let* ) = Result.bind

let to_ir_operand = function
  | X86_parser.OpReg r -> Ok (Ir.Reg r)
  | X86_parser.OpImm i -> Ok (Ir.Imm i)
  | X86_parser.OpMem m ->
      Ok (Ir.Mem { base = m.base; index = m.index; disp = m.disp; width = m.width })
  | X86_parser.OpLabel l ->
      Error (Printf.sprintf "Label '%s' cannot be used directly as a value operand" l)

let to_target = function
  | X86_parser.OpLabel l -> Ir.Label l
  | X86_parser.OpImm i -> Ir.TargetImm i
  | X86_parser.OpReg r -> Ir.Label (Register.to_string r)
  | X86_parser.OpMem _ -> Ir.Label "indirect_mem"

let parse_jcc_mnemonic mnem =
  if not (String.starts_with ~prefix:"j" mnem) || mnem = "jmp" then None
  else
    let cond_str = String.sub mnem 1 (String.length mnem - 1) in
    match Flags.condition_of_string cond_str with
    | Ok cond -> Some cond
    | Error _ -> None

let parse_setcc_mnemonic mnem =
  if not (String.starts_with ~prefix:"set" mnem) then None
  else
    let cond_str = String.sub mnem 3 (String.length mnem - 3) in
    match Flags.condition_of_string cond_str with
    | Ok cond -> Some cond
    | Error _ -> None

let parse_cmovcc_mnemonic mnem =
  if not (String.starts_with ~prefix:"cmov" mnem) then None
  else
    let cond_str = String.sub mnem 4 (String.length mnem - 4) in
    match Flags.condition_of_string cond_str with
    | Ok cond -> Some cond
    | Error _ -> None

let lift_instr mnem ops =
  match mnem, ops with
  | "nop", [] -> Ok [ Ir.Nop ]
  | "ret", [] -> Ok [ Ir.Ret ]
  | "vm_enter", [] -> Ok [ Ir.Vm_enter ]
  | "vm_exit", [] -> Ok [ Ir.Vm_exit ]
  | "push", [ op ] ->
      let* ir_op = to_ir_operand op in
      Ok [ Ir.Push ir_op ]
  | "pop", [ op ] ->
      let* ir_op = to_ir_operand op in
      Ok [ Ir.Pop ir_op ]
  | "mov", [ dst; src ] ->
      let* ir_dst = to_ir_operand dst in
      let* ir_src = to_ir_operand src in
      Ok [ Ir.Mov { dst = ir_dst; src = ir_src } ]
  | "lea", [ dst; OpMem addr ] -> (
      match dst with
      | OpReg r ->
          Ok [ Ir.Lea { dst = r; addr = { base = addr.base; index = addr.index; disp = addr.disp; width = addr.width } } ]
      | _ -> Error "LEA destination must be a register")
  | "xchg", [ a; b ] ->
      let* ir_a = to_ir_operand a in
      let* ir_b = to_ir_operand b in
      Ok [ Ir.Xchg (ir_a, ir_b) ]
  | ("add" | "adc" | "sub" | "sbb" | "and" | "or" | "xor" | "shl" | "shr" | "sar" | "rol" | "ror" | "imul"), [ dst; src ] ->
      let alu_op = match mnem with
        | "add" -> Ir.Add | "adc" -> Ir.Adc | "sub" -> Ir.Sub | "sbb" -> Ir.Sbb
        | "and" -> Ir.And | "or"  -> Ir.Or  | "xor" -> Ir.Xor
        | "shl" -> Ir.Shl | "shr" -> Ir.Shr | "sar" -> Ir.Sar
        | "rol" -> Ir.Rol | "ror" -> Ir.Ror
        | "imul" -> Ir.Imul
        | _ -> assert false
      in
      let* ir_src = to_ir_operand src in
      (match dst with
      | OpReg r ->
          Ok [ Ir.Alu { op = alu_op; dst = r; src1 = Ir.Reg r; src2 = ir_src; set_flags = true } ]
      | OpMem m ->
          let mem_ref = { Ir.base = m.base; index = m.index; disp = m.disp; width = m.width } in
          Ok [
            Ir.Mov { dst = Ir.Reg Register.vtmp0; src = Ir.Mem mem_ref };
            Ir.Alu { op = alu_op; dst = Register.vtmp0; src1 = Ir.Reg Register.vtmp0; src2 = ir_src; set_flags = true };
            Ir.Mov { dst = Ir.Mem mem_ref; src = Ir.Reg Register.vtmp0 };
          ]
      | OpImm _ | OpLabel _ -> Error "Destination cannot be immediate or label")
  | ("inc" | "dec" | "not" | "neg"), [ dst ] ->
      let un_op = match mnem with
        | "inc" -> Ir.Inc | "dec" -> Ir.Dec | "not" -> Ir.Not | "neg" -> Ir.Neg
        | _ -> assert false
      in
      (match dst with
      | OpReg r ->
          Ok [ Ir.Unary { op = un_op; dst = r; src = Ir.Reg r; set_flags = true } ]
      | OpMem m ->
          let mem_ref = { Ir.base = m.base; index = m.index; disp = m.disp; width = m.width } in
          Ok [
            Ir.Mov { dst = Ir.Reg Register.vtmp0; src = Ir.Mem mem_ref };
            Ir.Unary { op = un_op; dst = Register.vtmp0; src = Ir.Reg Register.vtmp0; set_flags = true };
            Ir.Mov { dst = Ir.Mem mem_ref; src = Ir.Reg Register.vtmp0 };
          ]
      | _ -> Error "Destination must be register or memory")
  | "cmp", [ s1; s2 ] ->
      let* ir_s1 = to_ir_operand s1 in
      let* ir_s2 = to_ir_operand s2 in
      Ok [ Ir.Cmp { src1 = ir_s1; src2 = ir_s2 } ]
  | "test", [ s1; s2 ] ->
      let* ir_s1 = to_ir_operand s1 in
      let* ir_s2 = to_ir_operand s2 in
      Ok [ Ir.Test { src1 = ir_s1; src2 = ir_s2 } ]
  | "jmp", [ target ] ->
      Ok [ Ir.Jmp (to_target target) ]
  | "call", [ target ] ->
      Ok [ Ir.Call (to_target target) ]
  | other, [ target ] when parse_jcc_mnemonic other <> None ->
      let cond = Option.get (parse_jcc_mnemonic other) in
      Ok [ Ir.Jcc { cond; target_true = to_target target; target_false = Ir.Label "__fallthrough__" } ]
  | other, [ dst ] when parse_setcc_mnemonic other <> None ->
      let cond = Option.get (parse_setcc_mnemonic other) in
      let* ir_dst = to_ir_operand dst in
      Ok [ Ir.Setcc { cond; dst = ir_dst } ]
  | other, [ dst; src ] when parse_cmovcc_mnemonic other <> None ->
      let cond = Option.get (parse_cmovcc_mnemonic other) in
      let* ir_src = to_ir_operand src in
      (match dst with
      | OpReg r -> Ok [ Ir.Cmov { cond; dst = r; src = ir_src } ]
      | _ -> Error "CMOV destination must be a register")
  | other, _ ->
      Error (Printf.sprintf "Unsupported or invalid instruction '%s' with %d operands" other (List.length ops))

let is_terminator = function
  | Ir.Jmp _ | Ir.Jcc _ | Ir.Ret | Ir.Vm_exit | Ir.Trap _ -> true
  | _ -> false

let resolve_cfg_labels (cfg : Ir.cfg) =
  let label_to_id = Hashtbl.create 16 in
  Hashtbl.iter (fun id (b : Ir.basic_block) -> Hashtbl.replace label_to_id b.label id) cfg.blocks;

  let resolve_target = function
    | Ir.Label lbl -> (
        match Hashtbl.find_opt label_to_id lbl with
        | Some id -> Ir.BlockId id
        | None -> Ir.Label lbl)
    | other -> other
  in

  let resolved_blocks = Hashtbl.create (Hashtbl.length cfg.blocks) in
  Hashtbl.iter
    (fun id (b : Ir.basic_block) ->
      let resolved_instrs =
        List.map
          (fun instr ->
            match instr with
            | Ir.Jmp t -> Ir.Jmp (resolve_target t)
            | Ir.Jcc { cond; target_true; target_false } ->
                Ir.Jcc {
                  cond;
                  target_true = resolve_target target_true;
                  target_false = resolve_target target_false;
                }
            | Ir.Call t -> Ir.Call (resolve_target t)
            | other -> other)
          b.instrs
      in
      Hashtbl.replace resolved_blocks id { b with instrs = resolved_instrs })
    cfg.blocks;

  Ok { cfg with blocks = resolved_blocks }

let lift_lines ?(options = default_options) raw_lines =
  let block_id = ref 0 in
  let current_label = ref options.function_name in
  let current_instrs = ref [] in
  let raw_blocks = ref [] in

  let flush_block () =
    if !current_instrs <> [] || !raw_blocks = [] then begin
      let b = Ir.make_block ~id:!block_id ~label:!current_label ~instrs:(List.rev !current_instrs) in
      raw_blocks := b :: !raw_blocks;
      incr block_id;
      current_instrs := []
    end
  in

  let rec process = function
    | [] ->
        flush_block ();
        Ok (List.rev !raw_blocks)
    | X86_parser.LineEmpty :: rest | X86_parser.LineDirective _ :: rest
    | X86_parser.LineMarkerBegin _ :: rest | X86_parser.LineMarkerEnd :: rest ->
        process rest
    | X86_parser.LineLabel lbl :: rest ->
        if !current_instrs <> [] then flush_block ();
        current_label := lbl;
        process rest
    | X86_parser.LineInstr (mnem, ops) :: rest -> (
        match lift_instr mnem ops with
        | Error e -> Error e
        | Ok lifted ->
            List.iter (fun i -> current_instrs := i :: !current_instrs) lifted;
            let last_lifted = List.hd (List.rev lifted) in
            if is_terminator last_lifted then flush_block ();
            process rest)
  in

  let* blocks = process raw_lines in


  (* Patch fallthrough jumps between consecutive blocks *)
  let patched_blocks = ref [] in
  let n = List.length blocks in
  for i = 0 to n - 1 do
    let (b : Ir.basic_block) = List.nth blocks i in
    let next_id_opt = if i + 1 < n then Some (List.nth blocks (i + 1)).id else None in
    let new_instrs =
      match List.rev b.instrs with
      | [] -> (
          match next_id_opt with
          | Some next_id -> [ Ir.Jmp (Ir.BlockId next_id) ]
          | None -> [ Ir.Ret ])
      | last :: prev_rev -> (
          match last with
          | Ir.Jcc { cond; target_true; target_false = Ir.Label "__fallthrough__" } -> (
              match next_id_opt with
              | Some next_id ->
                  List.rev (Ir.Jcc { cond; target_true; target_false = Ir.BlockId next_id } :: prev_rev)
              | None ->
                  List.rev (Ir.Jcc { cond; target_true; target_false = Ir.Label "exit" } :: prev_rev))
          | _ ->
              if is_terminator last then b.instrs
              else
                match next_id_opt with
                | Some next_id -> b.instrs @ [ Ir.Jmp (Ir.BlockId next_id) ]
                | None -> b.instrs @ [ Ir.Ret ])
    in
    patched_blocks := { b with instrs = new_instrs } :: !patched_blocks
  done;

  let final_blocks = List.rev !patched_blocks in
  let func = Ir.make_func ~name:options.function_name ~entry_id:0 ~blocks:final_blocks in
  resolve_cfg_labels func.cfg
  |> Result.map (fun resolved_cfg -> { func with cfg = resolved_cfg })

let extract_marked_regions raw_lines =
  let has_markers =
    List.exists
      (function
        | X86_parser.LineMarkerBegin _ | X86_parser.LineMarkerEnd -> true
        | _ -> false)
      raw_lines
  in
  if not has_markers then
    [ (X86_parser.ModeUltra "main", raw_lines) ]
  else
    let regions = ref [] in
    let current_mode = ref None in
    let current_lines = ref [] in

    List.iter
      (function
        | X86_parser.LineMarkerBegin mode ->
            current_mode := Some mode;
            current_lines := []
        | X86_parser.LineMarkerEnd -> (
            match !current_mode with
            | Some m ->
                regions := (m, List.rev !current_lines) :: !regions;
                current_mode := None;
                current_lines := []
            | None -> ())
        | line ->
            if !current_mode <> None then
              current_lines := line :: !current_lines)
      raw_lines;

    if !regions = [] then
      [ (X86_parser.ModeUltra "main", raw_lines) ]
    else
      List.rev !regions

let lift_function ?options text =
  let* raw_lines = X86_parser.parse_lines text in
  lift_lines ?options raw_lines

