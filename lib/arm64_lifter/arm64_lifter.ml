open Vm_ir
open Arm64_parser

type options = {
  function_name : string;
}

let default_options = {
  function_name = "arm64_lifted_func";
}

let is_terminator = function
  | Ir.Jmp _ | Ir.Jcc _ | Ir.Ret | Ir.Trap _ | Ir.Vm_exit -> true
  | _ -> false

let raw_to_ir_operand = function
  | OpReg r -> Ir.Reg r
  | OpImm i -> Ir.Imm i
  | OpMem m ->
      Ir.Mem {
        base = m.base;
        index = m.index;
        disp = m.disp;
        width = m.width;
      }
  | OpLabel _ -> Ir.Imm 0L

let lift_instr (mnemonic : string) (ops : raw_op list) : (Ir.instr list, string) result =
  match (mnemonic, ops) with
  | ("nop", []) -> Ok [ Ir.Nop ]
  | ("ret", _) -> Ok [ Ir.Ret ]

  (* Moves & Loads of Constants *)
  | ("mov", [ OpReg dst; (OpReg _ | OpImm _ | OpMem _) as src ]) ->
      Ok [ Ir.Mov { dst = Reg dst; src = raw_to_ir_operand src } ]
  | ("movz", (OpReg dst :: OpImm imm :: _)) ->
      Ok [ Ir.Mov { dst = Reg dst; src = Imm imm } ]
  | ("movk", (OpReg dst :: OpImm imm :: _)) ->
      Ok [ Ir.Alu { op = Or; dst; src1 = Reg dst; src2 = Imm imm; set_flags = false } ]
  | ("mvn", [ OpReg dst; OpReg src ]) ->
      Ok [
        Ir.Mov { dst = Reg dst; src = Reg src };
        Ir.Unary { op = Not; dst; src = Reg dst; set_flags = false };
      ]
  | (("adr" | "adrp"), [ OpReg dst; _ ]) ->
      Ok [ Ir.Mov { dst = Reg dst; src = Imm 0x100000000L } ]

  (* Arithmetic *)
  | ("add", [ OpReg dst; OpReg src1; ((OpReg _ | OpImm _) as src2) ]) ->
      Ok [ Ir.Alu { op = Add; dst; src1 = Reg src1; src2 = raw_to_ir_operand src2; set_flags = false } ]
  | ("add", (OpReg dst :: OpReg src1 :: _)) ->
      Ok [ Ir.Alu { op = Add; dst; src1 = Reg src1; src2 = Imm 0L; set_flags = false } ]
  | ("adds", [ OpReg dst; OpReg src1; ((OpReg _ | OpImm _) as src2) ]) ->
      Ok [ Ir.Alu { op = Add; dst; src1 = Reg src1; src2 = raw_to_ir_operand src2; set_flags = true } ]

  | ("sub", [ OpReg dst; OpReg src1; ((OpReg _ | OpImm _) as src2) ]) ->
      Ok [ Ir.Alu { op = Sub; dst; src1 = Reg src1; src2 = raw_to_ir_operand src2; set_flags = false } ]
  | ("subs", [ OpReg dst; OpReg src1; ((OpReg _ | OpImm _) as src2) ]) ->
      Ok [ Ir.Alu { op = Sub; dst; src1 = Reg src1; src2 = raw_to_ir_operand src2; set_flags = true } ]

  | ("mul", [ OpReg dst; OpReg src1; ((OpReg _ | OpImm _) as src2) ]) ->
      Ok [ Ir.Alu { op = Mul; dst; src1 = Reg src1; src2 = raw_to_ir_operand src2; set_flags = false } ]
  | ("sdiv", [ OpReg dst; OpReg src1; OpReg src2 ]) ->
      Ok [ Ir.Alu { op = Idiv; dst; src1 = Reg src1; src2 = Reg src2; set_flags = false } ]
  | ("udiv", [ OpReg dst; OpReg src1; OpReg src2 ]) ->
      Ok [ Ir.Alu { op = Div; dst; src1 = Reg src1; src2 = Reg src2; set_flags = false } ]

  (* Logic *)
  | ("and", [ OpReg dst; OpReg src1; ((OpReg _ | OpImm _) as src2) ]) ->
      Ok [ Ir.Alu { op = And; dst; src1 = Reg src1; src2 = raw_to_ir_operand src2; set_flags = false } ]
  | ("ands", [ OpReg dst; OpReg src1; ((OpReg _ | OpImm _) as src2) ]) ->
      Ok [ Ir.Alu { op = And; dst; src1 = Reg src1; src2 = raw_to_ir_operand src2; set_flags = true } ]

  | ("orr", [ OpReg dst; OpReg src1; ((OpReg _ | OpImm _) as src2) ]) ->
      Ok [ Ir.Alu { op = Or; dst; src1 = Reg src1; src2 = raw_to_ir_operand src2; set_flags = false } ]
  | ("eor", [ OpReg dst; OpReg src1; ((OpReg _ | OpImm _) as src2) ]) ->
      Ok [ Ir.Alu { op = Xor; dst; src1 = Reg src1; src2 = raw_to_ir_operand src2; set_flags = false } ]

  (* Shifts *)
  | ("lsl", [ OpReg dst; OpReg src1; OpImm shift ]) ->
      Ok [ Ir.Alu { op = Shl; dst; src1 = Reg src1; src2 = Imm shift; set_flags = false } ]
  | ("lsr", [ OpReg dst; OpReg src1; OpImm shift ]) ->
      Ok [ Ir.Alu { op = Shr; dst; src1 = Reg src1; src2 = Imm shift; set_flags = false } ]
  | ("asr", [ OpReg dst; OpReg src1; OpImm shift ]) ->
      Ok [ Ir.Alu { op = Sar; dst; src1 = Reg src1; src2 = Imm shift; set_flags = false } ]
  | ("ror", [ OpReg dst; OpReg src1; OpImm shift ]) ->
      Ok [ Ir.Alu { op = Ror; dst; src1 = Reg src1; src2 = Imm shift; set_flags = false } ]
  | ("neg", [ OpReg dst; OpReg src ]) ->
      Ok [ Ir.Unary { op = Neg; dst; src = Reg src; set_flags = false } ]

  (* Comparisons *)
  | ("cmp", [ OpReg src1; ((OpReg _ | OpImm _) as src2) ]) ->
      Ok [ Ir.Cmp { src1 = Reg src1; src2 = raw_to_ir_operand src2 } ]
  | ("tst", [ OpReg src1; ((OpReg _ | OpImm _) as src2) ]) ->
      Ok [ Ir.Test { src1 = Reg src1; src2 = raw_to_ir_operand src2 } ]

  (* Memory Load / Store *)
  | (("ldr" | "ldrb" | "ldrh" | "ldur" | "ldurb"), [ OpReg dst; OpMem m ]) ->
      Ok [ Ir.Mov { dst = Reg dst; src = raw_to_ir_operand (OpMem m) } ]
  | (("str" | "strb" | "strh" | "stur" | "sturb"), [ OpReg src; OpMem m ]) ->
      Ok [ Ir.Mov { dst = raw_to_ir_operand (OpMem m); src = Reg src } ]

  (* Pair Load / Store (stp / ldp) *)
  | ("stp", (OpReg r1 :: OpReg r2 :: _)) ->
      Ok [ Ir.Push (Reg r1); Ir.Push (Reg r2) ]
  | ("ldp", (OpReg r1 :: OpReg r2 :: _)) ->
      Ok [ Ir.Pop (Reg r2); Ir.Pop (Reg r1) ]

  (* Branches & Calls *)
  | ("b", [ OpLabel target ]) ->
      Ok [ Ir.Jmp (Label target) ]
  | ("b.eq", [ OpLabel target ]) ->
      Ok [ Ir.Jcc { cond = E; target_true = Label target; target_false = TargetImm 0L } ]
  | ("b.ne", [ OpLabel target ]) ->
      Ok [ Ir.Jcc { cond = NE; target_true = Label target; target_false = TargetImm 0L } ]
  | ("b.lt", [ OpLabel target ]) ->
      Ok [ Ir.Jcc { cond = L; target_true = Label target; target_false = TargetImm 0L } ]
  | ("b.le", [ OpLabel target ]) ->
      Ok [ Ir.Jcc { cond = LE; target_true = Label target; target_false = TargetImm 0L } ]
  | ("b.gt", [ OpLabel target ]) ->
      Ok [ Ir.Jcc { cond = G; target_true = Label target; target_false = TargetImm 0L } ]
  | ("b.ge", [ OpLabel target ]) ->
      Ok [ Ir.Jcc { cond = GE; target_true = Label target; target_false = TargetImm 0L } ]
  | ("cbz", [ OpReg r; OpLabel target ]) ->
      Ok [
        Ir.Cmp { src1 = Reg r; src2 = Imm 0L };
        Ir.Jcc { cond = E; target_true = Label target; target_false = TargetImm 0L };
      ]
  | ("cbnz", [ OpReg r; OpLabel target ]) ->
      Ok [
        Ir.Cmp { src1 = Reg r; src2 = Imm 0L };
        Ir.Jcc { cond = NE; target_true = Label target; target_false = TargetImm 0L };
      ]
  | ("bl", [ OpLabel target ]) ->
      Ok [ Ir.Call (Label target) ]
  | ("blr", _) ->
      Ok [ Ir.Call (TargetImm 0L) ]
  | ("br", _) ->
      Ok [ Ir.Jmp (TargetImm 0L) ]

  | (m, _) ->
      (* Gracefully ignore non-essential platform pseudo-ops / hints *)
      if String.starts_with ~prefix:"." m || String.starts_with ~prefix:"lloh" (String.lowercase_ascii m) then
        Ok [ Ir.Nop ]
      else
        Error (Printf.sprintf "Unsupported or invalid ARM64 instruction: %s" m)

let lift_lines ?(options = default_options) (lines : raw_line list) : (Ir.func, string) result =
  let blocks = ref [] in
  let cur_label = ref "entry" in
  let cur_instrs = ref [] in
  let cur_id = ref 0 in

  let flush_block () =
    if !cur_instrs <> [] || !blocks = [] then begin
      let b = {
        Ir.id = !cur_id;
        label = !cur_label;
        instrs = List.rev !cur_instrs;
      } in
      blocks := b :: !blocks;
      incr cur_id;
      cur_instrs := [];
      cur_label := Printf.sprintf "l_bb_%d" !cur_id
    end
  in

  let rec process = function
    | [] ->
        flush_block ();
        Ok (List.rev !blocks)
    | LineEmpty :: rest | LineDirective _ :: rest -> process rest
    | LineLabel lbl :: rest ->
        if !cur_instrs <> [] then flush_block ();
        cur_label := lbl;
        process rest
    | LineInstr (m, ops) :: rest ->
        match lift_instr m ops with
        | Error err -> Error err
        | Ok ir_list ->
            cur_instrs := List.rev ir_list @ !cur_instrs;
            let last_lifted = List.hd (List.rev ir_list) in
            if is_terminator last_lifted then flush_block ();
            process rest
  in

  match process lines with
  | Error err -> Error err
  | Ok bb_list ->
      let label_map = Hashtbl.create 16 in
      List.iter (fun (b : Ir.basic_block) -> Hashtbl.replace label_map b.label b.id) bb_list;

      (* Fix terminator and patch label targets to BlockId *)
      let patched_blocks = List.mapi (fun idx (b : Ir.basic_block) ->
        let fallthrough_id = if idx + 1 < List.length bb_list then (List.nth bb_list (idx + 1)).id else 0 in
        let patch_target = function
          | Ir.Label l ->
              (match Hashtbl.find_opt label_map l with
              | Some bid -> Ir.BlockId bid
              | None -> Ir.Label l)
          | Ir.TargetImm _ -> Ir.BlockId fallthrough_id
          | t -> t
        in
        let patched_instrs = List.map (function
          | Ir.Jmp t -> Ir.Jmp (patch_target t)
          | Ir.Jcc { cond; target_true; target_false } ->
              Ir.Jcc { cond; target_true = patch_target target_true; target_false = patch_target target_false }
          | Ir.Call t -> Ir.Call (patch_target t)
          | other -> other
        ) b.instrs in

        (* Ensure each block has a valid terminator *)
        let final_instrs =
          match List.rev patched_instrs with
          | (Ir.Jmp _ | Ir.Jcc _ | Ir.Ret | Ir.Trap _ | Ir.Vm_exit) :: _ -> patched_instrs
          | _ ->
              if idx + 1 < List.length bb_list then
                patched_instrs @ [ Ir.Jmp (Ir.BlockId fallthrough_id) ]
              else
                patched_instrs @ [ Ir.Ret ]
        in
        { b with instrs = final_instrs }
      ) bb_list in

      let cfg_tbl = Hashtbl.create (List.length patched_blocks) in
      List.iter (fun (b : Ir.basic_block) -> Hashtbl.replace cfg_tbl b.id b) patched_blocks;
      let cfg = { Ir.entry_id = 0; blocks = cfg_tbl } in
      Ok { Ir.name = options.function_name; cfg }

let lift_function ?(options = default_options) (asm : string) : (Ir.func, string) result =
  match Arm64_parser.parse_lines asm with
  | Error err -> Error err
  | Ok lines -> lift_lines ~options lines

module Literal_stitcher = Literal_stitcher
