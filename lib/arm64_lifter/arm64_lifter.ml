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
  | OpReg (Register.Vreg (Register.VZERO, _)) -> Ir.Imm 0L
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

let map_cond_str s =
  match String.lowercase_ascii (String.trim s) with
  | "eq" -> Flags.E
  | "ne" -> Flags.NE
  | "lt" -> Flags.L
  | "le" -> Flags.LE
  | "gt" -> Flags.G
  | "ge" -> Flags.GE
  | "hi" -> Flags.A
  | "ls" -> Flags.BE
  | "hs" | "cs" -> Flags.AE
  | "lo" | "cc" -> Flags.B
  | "mi" -> Flags.S
  | "pl" -> Flags.NS
  | "vs" -> Flags.O
  | "vc" -> Flags.NO
  | _ -> Flags.E

let strip_page_suffix s =
  if String.ends_with ~suffix:"@PAGE" s then String.sub s 0 (String.length s - 5)
  else if String.ends_with ~suffix:"@PAGEOFF" s then String.sub s 0 (String.length s - 8)
  else if String.ends_with ~suffix:"@GOTPAGE" s then String.sub s 0 (String.length s - 8)
  else if String.ends_with ~suffix:"@GOTPAGEOFF" s then String.sub s 0 (String.length s - 11)
  else s

let emit_3addr_alu ~op ~dst ~src1 ~src2 ~set_flags =
  if Register.to_string dst = Register.to_string src1 then
    [ Ir.Alu { op; dst; src1 = Reg dst; src2 = raw_to_ir_operand src2; set_flags } ]
  else
    match raw_to_ir_operand src2 with
    | Ir.Reg r2 when Register.to_string dst = Register.to_string r2 ->
        (match op with
        | Ir.Add | Ir.Imul | Ir.Xor | Ir.And | Ir.Or ->
            [ Ir.Alu { op; dst; src1 = Reg dst; src2 = Reg src1; set_flags } ]
        | _ ->
            [
              Ir.Mov { dst = Reg Register.vtmp0; src = Reg dst };
              Ir.Mov { dst = Reg dst; src = Reg src1 };
              Ir.Alu { op; dst; src1 = Reg dst; src2 = Reg Register.vtmp0; set_flags };
            ])
    | ir_op2 ->
        [
          Ir.Mov { dst = Reg dst; src = Reg src1 };
          Ir.Alu { op; dst; src1 = Reg dst; src2 = ir_op2; set_flags };
        ]

let lower_mem_operand ~scratch_reg (m : raw_mem) =
  match m.index with
  | None -> (m, [])
  | Some (idx_reg, scale) ->
      let addr_reg = Register.with_width scratch_reg Register.B64 in
      let shift_instrs =
        let mov = Ir.Mov { dst = Reg addr_reg; src = Reg idx_reg } in
        if scale <= 1 then [ mov ]
        else
          let shift =
            match scale with
            | 2 -> 1L
            | 4 -> 2L
            | 8 -> 3L
            | _ -> 0L
          in
          if shift > 0L then
            [ mov; Ir.Alu { op = Shl; dst = addr_reg; src1 = Reg addr_reg; src2 = Imm shift; set_flags = false } ]
          else
            [ mov; Ir.Alu { op = Imul; dst = addr_reg; src1 = Reg addr_reg; src2 = Imm (Int64.of_int scale); set_flags = false } ]
      in
      let add_base_instrs =
        match m.base with
        | Some base_reg ->
            [ Ir.Alu { op = Add; dst = addr_reg; src1 = Reg addr_reg; src2 = Reg base_reg; set_flags = false } ]
        | None -> []
      in
      let effective_m = { m with base = Some addr_reg; index = None } in
      (effective_m, shift_instrs @ add_base_instrs)

let lift_instr (mnemonic : string) (ops : raw_op list) : (Ir.instr list, string) result =
  match (mnemonic, ops) with
  | ("nop", []) -> Ok [ Ir.Nop ]
  | ("ret", _) -> Ok [ Ir.Ret ]

  (* Moves & Loads of Constants *)
  | ("mov", [ OpReg dst; (OpReg _ | OpImm _ | OpMem _) as src ]) ->
      Ok [ Ir.Mov { dst = Reg dst; src = raw_to_ir_operand src } ]
  | ("movz", (OpReg dst :: OpImm imm :: rest)) ->
      let shift = match rest with
        | [ OpLabel shift_s ] when String.contains shift_s '#' ->
            (match String.split_on_char '#' shift_s with
            | [ _; sh ] -> (match int_of_string_opt (String.trim sh) with Some s -> s | None -> 0)
            | _ -> 0)
        | _ -> 0
      in
      let full_imm = Int64.shift_left (Int64.logand imm 0xFFFFL) shift in
      Ok [ Ir.Mov { dst = Reg dst; src = Imm full_imm } ]
  | ("movk", (OpReg dst :: OpImm imm :: rest)) ->
      let shift = match rest with
        | [ OpLabel shift_s ] when String.contains shift_s '#' ->
            (match String.split_on_char '#' shift_s with
            | [ _; sh ] -> (match int_of_string_opt (String.trim sh) with Some s -> s | None -> 0)
            | _ -> 0)
        | _ -> 0
      in
      let mask = Int64.lognot (Int64.shift_left 0xFFFFL shift) in
      let shifted_imm = Int64.shift_left (Int64.logand imm 0xFFFFL) shift in
      if Register.get_width dst = Register.B32 || shift < 32 then
        let mask_val = if Register.get_width dst = Register.B32 then Int64.logand mask 0xFFFFFFFFL else mask in
        Ok [
          Ir.Alu { op = And; dst; src1 = Reg dst; src2 = Imm mask_val; set_flags = false };
          Ir.Alu { op = Or; dst; src1 = Reg dst; src2 = Imm shifted_imm; set_flags = false };
        ]
      else
        Ok [
          Ir.Mov { dst = Reg Register.vtmp0; src = Imm mask };
          Ir.Alu { op = And; dst; src1 = Reg dst; src2 = Reg Register.vtmp0; set_flags = false };
          Ir.Mov { dst = Reg Register.vtmp0; src = Imm shifted_imm };
          Ir.Alu { op = Or; dst; src1 = Reg dst; src2 = Reg Register.vtmp0; set_flags = false };
        ]
  | ("mvn", [ OpReg dst; OpReg src ]) ->
      Ok [
        Ir.Mov { dst = Reg dst; src = Reg src };
        Ir.Unary { op = Not; dst; src = Reg dst; set_flags = false };
      ]
  | (("adr" | "adrp"), [ OpReg dst; OpLabel sym_lbl ]) ->
      let sym = strip_page_suffix sym_lbl in
      Ok [ Ir.Load_symbol { dst; sym; addend = 0L } ]
  | (("adr" | "adrp"), [ OpReg dst; _ ]) ->
      Ok [ Ir.Mov { dst = Reg dst; src = Imm 0x100000000L } ]

  (* Arithmetic *)
  | ("add", [ OpReg dst; OpReg src1; ((OpReg _ | OpImm _) as src2) ]) ->
      Ok (emit_3addr_alu ~op:Add ~dst ~src1 ~src2 ~set_flags:false)
  | ("add", [ OpReg dst; OpReg src1; OpLabel sym_lbl ]) ->
      let sym = strip_page_suffix sym_lbl in
      if Register.to_string dst = Register.to_string src1 then
        Ok [ Ir.Nop ]
      else
        Ok [ Ir.Load_symbol { dst; sym; addend = 0L } ]
  | ("add", (OpReg dst :: OpReg src1 :: _)) ->
      Ok (emit_3addr_alu ~op:Add ~dst ~src1 ~src2:(OpImm 0L) ~set_flags:false)
  | ("adds", [ OpReg dst; OpReg src1; ((OpReg _ | OpImm _) as src2) ]) ->
      Ok (emit_3addr_alu ~op:Add ~dst ~src1 ~src2 ~set_flags:true)

  | ("sub", [ OpReg dst; OpReg src1; ((OpReg _ | OpImm _) as src2) ]) ->
      Ok (emit_3addr_alu ~op:Sub ~dst ~src1 ~src2 ~set_flags:false)
  | ("subs", [ OpReg dst; OpReg src1; ((OpReg _ | OpImm _) as src2) ]) ->
      Ok (emit_3addr_alu ~op:Sub ~dst ~src1 ~src2 ~set_flags:true)

  | ("mul", [ OpReg dst; OpReg src1; ((OpReg _ | OpImm _) as src2) ]) ->
      Ok (emit_3addr_alu ~op:Mul ~dst ~src1 ~src2 ~set_flags:false)
  | ("madd", [ OpReg dst; OpReg src1; OpReg src2; OpReg src3 ]) ->
      Ok [
        Ir.Alu { op = Mul; dst; src1 = Reg src1; src2 = Reg src2; set_flags = false };
        Ir.Alu { op = Add; dst; src1 = Reg dst; src2 = Reg src3; set_flags = false };
      ]
  | ("msub", [ OpReg dst; OpReg src1; OpReg src2; OpReg src3 ]) ->
      Ok [
        Ir.Alu { op = Mul; dst; src1 = Reg src1; src2 = Reg src2; set_flags = false };
        Ir.Alu { op = Sub; dst; src1 = Reg src3; src2 = Reg dst; set_flags = false };
      ]
  | ("sdiv", [ OpReg dst; OpReg src1; OpReg src2 ]) ->
      Ok [ Ir.Alu { op = Idiv; dst; src1 = Reg src1; src2 = Reg src2; set_flags = false } ]
  | ("udiv", [ OpReg dst; OpReg src1; OpReg src2 ]) ->
      Ok [ Ir.Alu { op = Div; dst; src1 = Reg src1; src2 = Reg src2; set_flags = false } ]

  (* Logic & Shifted Register Operands *)
  | ("orr", (OpReg dst :: OpReg src1 :: OpReg src2 :: OpLabel ("lsl" | "LSL") :: OpImm shift :: _)) ->
      Ok [
        Ir.Mov { dst = Reg Register.vtmp1; src = Reg src2 };
        Ir.Alu { op = Shl; dst = Register.vtmp1; src1 = Reg Register.vtmp1; src2 = Imm shift; set_flags = false };
        Ir.Alu { op = Or; dst; src1 = Reg src1; src2 = Reg Register.vtmp1; set_flags = false };
      ]
  | ("orr", (OpReg dst :: OpReg src1 :: OpReg src2 :: OpLabel ("lsr" | "LSR") :: OpImm shift :: _)) ->
      Ok [
        Ir.Mov { dst = Reg Register.vtmp1; src = Reg src2 };
        Ir.Alu { op = Shr; dst = Register.vtmp1; src1 = Reg Register.vtmp1; src2 = Imm shift; set_flags = false };
        Ir.Alu { op = Or; dst; src1 = Reg src1; src2 = Reg Register.vtmp1; set_flags = false };
      ]
  | ("eor", (OpReg dst :: OpReg src1 :: OpReg src2 :: OpLabel ("lsl" | "LSL") :: OpImm shift :: _)) ->
      Ok [
        Ir.Mov { dst = Reg Register.vtmp1; src = Reg src2 };
        Ir.Alu { op = Shl; dst = Register.vtmp1; src1 = Reg Register.vtmp1; src2 = Imm shift; set_flags = false };
        Ir.Alu { op = Xor; dst; src1 = Reg src1; src2 = Reg Register.vtmp1; set_flags = false };
      ]
  | ("eor", (OpReg dst :: OpReg src1 :: OpReg src2 :: OpLabel ("lsr" | "LSR") :: OpImm shift :: _)) ->
      Ok [
        Ir.Mov { dst = Reg Register.vtmp1; src = Reg src2 };
        Ir.Alu { op = Shr; dst = Register.vtmp1; src1 = Reg Register.vtmp1; src2 = Imm shift; set_flags = false };
        Ir.Alu { op = Xor; dst; src1 = Reg src1; src2 = Reg Register.vtmp1; set_flags = false };
      ]
  | ("and", (OpReg dst :: OpReg src1 :: ((OpReg _ | OpImm _) as src2) :: _)) ->
      Ok (emit_3addr_alu ~op:And ~dst ~src1 ~src2 ~set_flags:false)
  | ("ands", (OpReg dst :: OpReg src1 :: ((OpReg _ | OpImm _) as src2) :: _)) ->
      Ok (emit_3addr_alu ~op:And ~dst ~src1 ~src2 ~set_flags:true)

  | ("orr", (OpReg dst :: OpReg src1 :: ((OpReg _ | OpImm _) as src2) :: _)) ->
      Ok (emit_3addr_alu ~op:Or ~dst ~src1 ~src2 ~set_flags:false)
  | ("eor", (OpReg dst :: OpReg src1 :: ((OpReg _ | OpImm _) as src2) :: _)) ->
      Ok (emit_3addr_alu ~op:Xor ~dst ~src1 ~src2 ~set_flags:false)
  | ("bic", (OpReg dst :: OpReg src1 :: ((OpReg _ | OpImm _) as src2) :: _)) ->
      Ok [
        Ir.Unary { op = Not; dst = Register.vtmp1; src = raw_to_ir_operand src2; set_flags = false };
        Ir.Alu { op = And; dst; src1 = Reg src1; src2 = Reg Register.vtmp1; set_flags = false };
      ]
  | ("bics", (OpReg dst :: OpReg src1 :: ((OpReg _ | OpImm _) as src2) :: _)) ->
      Ok [
        Ir.Unary { op = Not; dst = Register.vtmp1; src = raw_to_ir_operand src2; set_flags = false };
        Ir.Alu { op = And; dst; src1 = Reg src1; src2 = Reg Register.vtmp1; set_flags = true };
      ]
  | ("orn", (OpReg dst :: OpReg src1 :: ((OpReg _ | OpImm _) as src2) :: _)) ->
      Ok [
        Ir.Unary { op = Not; dst = Register.vtmp1; src = raw_to_ir_operand src2; set_flags = false };
        Ir.Alu { op = Or; dst; src1 = Reg src1; src2 = Reg Register.vtmp1; set_flags = false };
      ]
  | ("eon", (OpReg dst :: OpReg src1 :: ((OpReg _ | OpImm _) as src2) :: _)) ->
      Ok [
        Ir.Unary { op = Not; dst = Register.vtmp1; src = raw_to_ir_operand src2; set_flags = false };
        Ir.Alu { op = Xor; dst; src1 = Reg src1; src2 = Reg Register.vtmp1; set_flags = false };
      ]

  (* Shifts & Bitfields *)
  | ("lsl", [ OpReg dst; OpReg src1; OpImm shift ]) ->
      Ok (emit_3addr_alu ~op:Shl ~dst ~src1 ~src2:(OpImm shift) ~set_flags:false)
  | ("lsr", [ OpReg dst; OpReg src1; OpImm shift ]) ->
      Ok (emit_3addr_alu ~op:Shr ~dst ~src1 ~src2:(OpImm shift) ~set_flags:false)
  | ("asr", [ OpReg dst; OpReg src1; OpImm shift ]) ->
      Ok (emit_3addr_alu ~op:Sar ~dst ~src1 ~src2:(OpImm shift) ~set_flags:false)
  | ("ror", [ OpReg dst; OpReg src1; OpImm shift ]) ->
      Ok (emit_3addr_alu ~op:Ror ~dst ~src1 ~src2:(OpImm shift) ~set_flags:false)
  | ("ubfx", (OpReg dst :: OpReg src :: OpImm lsb :: OpImm width :: _)) ->
      let w = min 64 (max 1 (Int64.to_int width)) in
      let mask = if w = 64 then -1L else Int64.sub (Int64.shift_left 1L w) 1L in
      Ok [
        Ir.Mov { dst = Reg dst; src = Reg src };
        Ir.Alu { op = Shr; dst; src1 = Reg dst; src2 = Imm lsb; set_flags = false };
        Ir.Alu { op = And; dst; src1 = Reg dst; src2 = Imm mask; set_flags = false };
      ]
  | ("sbfx", (OpReg dst :: OpReg src :: OpImm lsb :: OpImm width :: _)) ->
      let w = min 64 (max 1 (Int64.to_int width)) in
      let shift_left_amt = max 0 (64 - (Int64.to_int lsb + w)) in
      let shift_right_amt = 64 - w in
      Ok [
        Ir.Mov { dst = Reg dst; src = Reg src };
        Ir.Alu { op = Shl; dst; src1 = Reg dst; src2 = Imm (Int64.of_int shift_left_amt); set_flags = false };
        Ir.Alu { op = Sar; dst; src1 = Reg dst; src2 = Imm (Int64.of_int shift_right_amt); set_flags = false };
      ]
  | ("extr", (OpReg dst :: OpReg src1 :: OpReg _ :: OpImm shift :: _)) ->
      Ok [
        Ir.Mov { dst = Reg dst; src = Reg src1 };
        Ir.Alu { op = Ror; dst; src1 = Reg dst; src2 = Imm shift; set_flags = false };
      ]
  | ("neg", [ OpReg dst; OpReg src ]) ->
      Ok [ Ir.Unary { op = Neg; dst; src = Reg src; set_flags = false } ]

  (* Comparisons & Extended Register Comparisons *)
  | ("cmp", (OpReg src1 :: OpReg src2 :: OpLabel ("uxth" | "UXTH") :: _)) ->
      Ok [
        Ir.Mov { dst = Reg Register.vtmp0; src = Reg src2 };
        Ir.Alu { op = And; dst = Register.vtmp0; src1 = Reg Register.vtmp0; src2 = Imm 0xFFFFL; set_flags = false };
        Ir.Cmp { src1 = Reg src1; src2 = Reg Register.vtmp0 };
      ]
  | ("cmp", (OpReg src1 :: OpReg src2 :: OpLabel ("uxtb" | "UXTB") :: _)) ->
      Ok [
        Ir.Mov { dst = Reg Register.vtmp0; src = Reg src2 };
        Ir.Alu { op = And; dst = Register.vtmp0; src1 = Reg Register.vtmp0; src2 = Imm 0xFFL; set_flags = false };
        Ir.Cmp { src1 = Reg src1; src2 = Reg Register.vtmp0 };
      ]
  | ("cmp", (OpReg src1 :: OpReg src2 :: OpLabel ("uxtw" | "UXTW") :: _)) ->
      Ok [
        Ir.Mov { dst = Reg Register.vtmp0; src = Reg src2 };
        Ir.Alu { op = And; dst = Register.vtmp0; src1 = Reg Register.vtmp0; src2 = Imm 0xFFFFFFFFL; set_flags = false };
        Ir.Cmp { src1 = Reg src1; src2 = Reg Register.vtmp0 };
      ]
  | ("cmp", (OpReg src1 :: ((OpReg _ | OpImm _) as src2) :: _)) ->
      Ok [ Ir.Cmp { src1 = Reg src1; src2 = raw_to_ir_operand src2 } ]
  | ("tst", (OpReg src1 :: ((OpReg _ | OpImm _) as src2) :: _)) ->
      Ok [ Ir.Test { src1 = Reg src1; src2 = raw_to_ir_operand src2 } ]

  (* Conditional Set / Select *)
  | ("cset", [ OpReg dst; cond_op ]) ->
      let c_str = match cond_op with OpLabel s -> s | OpReg r -> Register.to_string r | _ -> "eq" in
      Ok [
        Ir.Mov { dst = Reg dst; src = Imm 0L };
        Ir.Setcc { cond = map_cond_str c_str; dst = Reg dst };
      ]
  | ("cset", (OpReg dst :: _)) ->
      Ok [
        Ir.Mov { dst = Reg dst; src = Imm 0L };
        Ir.Setcc { cond = E; dst = Reg dst };
      ]
  | ("csel", (OpReg dst :: src1_op :: src2_op :: cond_op :: _)) ->
      let c_str = match cond_op with OpLabel s -> s | OpReg r -> Register.to_string r | _ -> "eq" in
      let is_zero = function
        | OpReg (Register.Vreg (Register.VZERO, _)) -> true
        | OpImm 0L -> true
        | _ -> false
      in
      if is_zero src2_op && (match src1_op with OpReg r -> r = dst | _ -> false) then
        Ok [
          Ir.Mov { dst = Reg Register.vtmp1; src = Imm 0L };
          Ir.Cmov { cond = Flags.condition_negate (map_cond_str c_str); dst; src = Reg Register.vtmp1 };
        ]
      else if is_zero src1_op && (match src2_op with OpReg r -> r = dst | _ -> false) then
        Ok [
          Ir.Mov { dst = Reg Register.vtmp1; src = Imm 0L };
          Ir.Cmov { cond = map_cond_str c_str; dst; src = Reg Register.vtmp1 };
        ]
      else
        Ok [
          Ir.Mov { dst = Reg dst; src = raw_to_ir_operand src2_op };
          Ir.Mov { dst = Reg Register.vtmp1; src = raw_to_ir_operand src1_op };
          Ir.Cmov { cond = map_cond_str c_str; dst; src = Reg Register.vtmp1 };
        ]
  | ("cinc", (OpReg dst :: OpReg src :: cond_op :: _)) ->
      let c_str = match cond_op with OpLabel s -> s | OpReg r -> Register.to_string r | _ -> "eq" in
      Ok [
        Ir.Mov { dst = Reg dst; src = Reg src };
        Ir.Alu { op = Add; dst; src1 = Reg dst; src2 = Imm 1L; set_flags = false };
        Ir.Cmov { cond = Flags.condition_negate (map_cond_str c_str); dst; src = Reg src };
      ]

  (* Memory Load / Store with Pre/Post-Indexed Writeback *)
  | (("ldr" | "ldrb" | "ldrh" | "ldur" | "ldurb" | "ldrsb" | "ldrsh"), [ OpReg dst; OpMem m ]) -> (
      let scratch =
        if Register.to_string dst = Register.to_string Register.vtmp0 then Register.vtmp1
        else Register.vtmp0
      in
      let (m, addr_prep) = lower_mem_operand ~scratch_reg:scratch m in
      match m.wb with
      | WbNone ->
          Ok (addr_prep @ [ Ir.Mov { dst = Reg dst; src = raw_to_ir_operand (OpMem m) } ])
      | WbPre ->
          (match m.base with
          | Some base_reg ->
              let effective_mem = { m with disp = 0L; wb = WbNone } in
              Ok (addr_prep @ [
                Ir.Alu { op = Add; dst = base_reg; src1 = Reg base_reg; src2 = Imm m.disp; set_flags = false };
                Ir.Mov { dst = Reg dst; src = raw_to_ir_operand (OpMem effective_mem) };
              ])
          | None ->
              Ok (addr_prep @ [ Ir.Mov { dst = Reg dst; src = raw_to_ir_operand (OpMem m) } ]))
      | WbPost post_imm ->
          (match m.base with
          | Some base_reg ->
              let effective_mem = { m with disp = 0L; wb = WbNone } in
              Ok (addr_prep @ [
                Ir.Mov { dst = Reg dst; src = raw_to_ir_operand (OpMem effective_mem) };
                Ir.Alu { op = Add; dst = base_reg; src1 = Reg base_reg; src2 = Imm post_imm; set_flags = false };
              ])
          | None ->
              Ok (addr_prep @ [ Ir.Mov { dst = Reg dst; src = raw_to_ir_operand (OpMem m) } ]))
    )
  | (("str" | "strb" | "strh" | "stur" | "sturb"), [ (OpReg _ | OpImm _) as src; OpMem m ]) -> (
      let scratch =
        match src with
        | OpReg r when Register.to_string r = Register.to_string Register.vtmp0 -> Register.vtmp1
        | _ -> Register.vtmp0
      in
      let (m, addr_prep) = lower_mem_operand ~scratch_reg:scratch m in
      match m.wb with
      | WbNone ->
          Ok (addr_prep @ [ Ir.Mov { dst = raw_to_ir_operand (OpMem m); src = raw_to_ir_operand src } ])
      | WbPre ->
          (match m.base with
          | Some base_reg ->
              let effective_mem = { m with disp = 0L; wb = WbNone } in
              Ok (addr_prep @ [
                Ir.Alu { op = Add; dst = base_reg; src1 = Reg base_reg; src2 = Imm m.disp; set_flags = false };
                Ir.Mov { dst = raw_to_ir_operand (OpMem effective_mem); src = raw_to_ir_operand src };
              ])
          | None ->
              Ok (addr_prep @ [ Ir.Mov { dst = raw_to_ir_operand (OpMem m); src = raw_to_ir_operand src } ]))
      | WbPost post_imm ->
          (match m.base with
          | Some base_reg ->
              let effective_mem = { m with disp = 0L; wb = WbNone } in
              Ok (addr_prep @ [
                Ir.Mov { dst = raw_to_ir_operand (OpMem effective_mem); src = raw_to_ir_operand src };
                Ir.Alu { op = Add; dst = base_reg; src1 = Reg base_reg; src2 = Imm post_imm; set_flags = false };
              ])
          | None ->
              Ok (addr_prep @ [ Ir.Mov { dst = raw_to_ir_operand (OpMem m); src = raw_to_ir_operand src } ]))
    )

  (* Pair Load / Store (stp / ldp) with Pre/Post-Indexed Writeback *)
  | ("stp", [ OpReg r1; OpReg r2; OpMem m ]) ->
      let stride = Int64.of_int (Register.width_to_bytes (Register.get_width r1)) in
      let w = Register.get_width r1 in
      (match m.wb with
      | WbPre ->
          (match m.base with
          | Some base_reg ->
              let m1 = { base = Some base_reg; index = None; disp = 0L; width = w; wb = WbNone } in
              let m2 = { base = Some base_reg; index = None; disp = stride; width = w; wb = WbNone } in
              Ok [
                Ir.Alu { op = Add; dst = base_reg; src1 = Reg base_reg; src2 = Imm m.disp; set_flags = false };
                Ir.Mov { dst = raw_to_ir_operand (OpMem m1); src = Reg r1 };
                Ir.Mov { dst = raw_to_ir_operand (OpMem m2); src = Reg r2 };
              ]
          | None ->
              let m1 = { m with width = w } in
              let m2 = { m with disp = Int64.add m.disp stride; width = w } in
              Ok [
                Ir.Mov { dst = raw_to_ir_operand (OpMem m1); src = Reg r1 };
                Ir.Mov { dst = raw_to_ir_operand (OpMem m2); src = Reg r2 };
              ])
      | WbPost post_imm ->
          (match m.base with
          | Some base_reg ->
              let m1 = { base = Some base_reg; index = None; disp = 0L; width = w; wb = WbNone } in
              let m2 = { base = Some base_reg; index = None; disp = stride; width = w; wb = WbNone } in
              Ok [
                Ir.Mov { dst = raw_to_ir_operand (OpMem m1); src = Reg r1 };
                Ir.Mov { dst = raw_to_ir_operand (OpMem m2); src = Reg r2 };
                Ir.Alu { op = Add; dst = base_reg; src1 = Reg base_reg; src2 = Imm post_imm; set_flags = false };
              ]
          | None ->
              let m1 = { m with width = w } in
              let m2 = { m with disp = Int64.add m.disp stride; width = w } in
              Ok [
                Ir.Mov { dst = raw_to_ir_operand (OpMem m1); src = Reg r1 };
                Ir.Mov { dst = raw_to_ir_operand (OpMem m2); src = Reg r2 };
              ])
      | WbNone ->
          let m1 = { m with width = w } in
          let m2 = { m with disp = Int64.add m.disp stride; width = w } in
          Ok [
            Ir.Mov { dst = raw_to_ir_operand (OpMem m1); src = Reg r1 };
            Ir.Mov { dst = raw_to_ir_operand (OpMem m2); src = Reg r2 };
          ])
  | ("stp", (OpReg r1 :: OpReg r2 :: _)) ->
      Ok [ Ir.Push (Reg r1); Ir.Push (Reg r2) ]

  | ("ldp", [ OpReg r1; OpReg r2; OpMem m ]) ->
      let stride = Int64.of_int (Register.width_to_bytes (Register.get_width r1)) in
      let w = Register.get_width r1 in
      (match m.wb with
      | WbPre ->
          (match m.base with
          | Some base_reg ->
              let m1 = { base = Some base_reg; index = None; disp = 0L; width = w; wb = WbNone } in
              let m2 = { base = Some base_reg; index = None; disp = stride; width = w; wb = WbNone } in
              Ok [
                Ir.Alu { op = Add; dst = base_reg; src1 = Reg base_reg; src2 = Imm m.disp; set_flags = false };
                Ir.Mov { dst = Reg r1; src = raw_to_ir_operand (OpMem m1) };
                Ir.Mov { dst = Reg r2; src = raw_to_ir_operand (OpMem m2) };
              ]
          | None ->
              let m1 = { m with width = w } in
              let m2 = { m with disp = Int64.add m.disp stride; width = w } in
              Ok [
                Ir.Mov { dst = Reg r1; src = raw_to_ir_operand (OpMem m1) };
                Ir.Mov { dst = Reg r2; src = raw_to_ir_operand (OpMem m2) };
              ])
      | WbPost post_imm ->
          (match m.base with
          | Some base_reg ->
              let m1 = { base = Some base_reg; index = None; disp = 0L; width = w; wb = WbNone } in
              let m2 = { base = Some base_reg; index = None; disp = stride; width = w; wb = WbNone } in
              Ok [
                Ir.Mov { dst = Reg r1; src = raw_to_ir_operand (OpMem m1) };
                Ir.Mov { dst = Reg r2; src = raw_to_ir_operand (OpMem m2) };
                Ir.Alu { op = Add; dst = base_reg; src1 = Reg base_reg; src2 = Imm post_imm; set_flags = false };
              ]
          | None ->
              let m1 = { m with width = w } in
              let m2 = { m with disp = Int64.add m.disp stride; width = w } in
              Ok [
                Ir.Mov { dst = Reg r1; src = raw_to_ir_operand (OpMem m1) };
                Ir.Mov { dst = Reg r2; src = raw_to_ir_operand (OpMem m2) };
              ])
      | WbNone ->
          let m1 = { m with width = w } in
          let m2 = { m with disp = Int64.add m.disp stride; width = w } in
          Ok [
            Ir.Mov { dst = Reg r1; src = raw_to_ir_operand (OpMem m1) };
            Ir.Mov { dst = Reg r2; src = raw_to_ir_operand (OpMem m2) };
          ])
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
  | ("b.hi", [ OpLabel target ]) ->
      Ok [ Ir.Jcc { cond = A; target_true = Label target; target_false = TargetImm 0L } ]
  | ("b.ls", [ OpLabel target ]) ->
      Ok [ Ir.Jcc { cond = BE; target_true = Label target; target_false = TargetImm 0L } ]
  | (("b.hs" | "b.cs"), [ OpLabel target ]) ->
      Ok [ Ir.Jcc { cond = AE; target_true = Label target; target_false = TargetImm 0L } ]
  | (("b.lo" | "b.cc"), [ OpLabel target ]) ->
      Ok [ Ir.Jcc { cond = B; target_true = Label target; target_false = TargetImm 0L } ]
  | ("b.mi", [ OpLabel target ]) ->
      Ok [ Ir.Jcc { cond = S; target_true = Label target; target_false = TargetImm 0L } ]
  | ("b.pl", [ OpLabel target ]) ->
      Ok [ Ir.Jcc { cond = NS; target_true = Label target; target_false = TargetImm 0L } ]
  | ("b.vs", [ OpLabel target ]) ->
      Ok [ Ir.Jcc { cond = O; target_true = Label target; target_false = TargetImm 0L } ]
  | ("b.vc", [ OpLabel target ]) ->
      Ok [ Ir.Jcc { cond = NO; target_true = Label target; target_false = TargetImm 0L } ]
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

  (* Floating-Point & Scalar FP (SIMD) Instructions *)
  | ("fadd", [ OpReg (Register.Fpr (d, _)); OpReg (Register.Fpr (s1, _)); OpReg (Register.Fpr (s2, _)) ]) ->
      Ok [ Ir.Fp_binop { op = Fadd; dst = d; src1 = s1; src2 = s2 } ]
  | ("fsub", [ OpReg (Register.Fpr (d, _)); OpReg (Register.Fpr (s1, _)); OpReg (Register.Fpr (s2, _)) ]) ->
      Ok [ Ir.Fp_binop { op = Fsub; dst = d; src1 = s1; src2 = s2 } ]
  | ("fmul", [ OpReg (Register.Fpr (d, _)); OpReg (Register.Fpr (s1, _)); OpReg (Register.Fpr (s2, _)) ]) ->
      Ok [ Ir.Fp_binop { op = Fmul; dst = d; src1 = s1; src2 = s2 } ]
  | ("fdiv", [ OpReg (Register.Fpr (d, _)); OpReg (Register.Fpr (s1, _)); OpReg (Register.Fpr (s2, _)) ]) ->
      Ok [ Ir.Fp_binop { op = Fdiv; dst = d; src1 = s1; src2 = s2 } ]
  | ("fcmp", [ OpReg (Register.Fpr (s1, _)); OpReg (Register.Fpr (s2, _)) ]) ->
      Ok [ Ir.Fp_cmp { src1 = s1; src2 = s2 } ]
  | ("fmov", [ OpReg (Register.Fpr (d, _)); OpReg (Register.Fpr (s, _)) ]) ->
      Ok [ Ir.Fp_binop { op = Fadd; dst = d; src1 = s; src2 = 31 } ]
  | ("fmov", [ OpReg (Register.Fpr (d, _)); OpImm imm ]) ->
      Ok [ Ir.Mov { dst = Reg (Register.Fpr (d, Register.B64)); src = Imm imm } ]
  | ("fcvtzs", [ OpReg dst; OpReg (Register.Fpr (s, _)) ]) ->
      Ok [ Ir.Fp_conv { op = Fcvtzs; dst; src = Register.Fpr (s, Register.B64) } ]
  | ("scvtf", [ OpReg (Register.Fpr (d, _)); OpReg src ]) ->
      Ok [ Ir.Fp_conv { op = Scvtf; dst = Register.Fpr (d, Register.B64); src } ]

  (* ARMv8.1-A Atomics & Memory Ordering *)
  | (("ldxr" | "ldaxr"), [ OpReg dst; OpMem m ]) ->
      let base = match m.base with Some b -> b | None -> Register.rsp in
      Ok [ Ir.Atomic_mem { op = AtLoad; dst; addr = base; src = dst; imm = m.disp } ]
  | (("stxr" | "stlxr"), [ OpReg res; OpReg src; OpMem m ]) ->
      let base = match m.base with Some b -> b | None -> Register.rsp in
      Ok [ Ir.Atomic_mem { op = AtStore; dst = res; addr = base; src; imm = m.disp } ]
  | (("cas" | "casa" | "casl" | "casal"), [ OpReg expected; OpReg desired; OpMem m ]) ->
      let base = match m.base with Some b -> b | None -> Register.rsp in
      Ok [ Ir.Atomic_mem { op = AtCas; dst = desired; addr = base; src = expected; imm = m.disp } ]
  | (("ldadd" | "ldadda" | "ldaddl" | "ldaddal"), [ OpReg val_reg; OpReg res_reg; OpMem m ]) ->
      let base = match m.base with Some b -> b | None -> Register.rsp in
      Ok [ Ir.Atomic_mem { op = AtAdd; dst = res_reg; addr = base; src = val_reg; imm = m.disp } ]
  | (("swp" | "swpa" | "swpl" | "swpal"), [ OpReg val_reg; OpReg res_reg; OpMem m ]) ->
      let base = match m.base with Some b -> b | None -> Register.rsp in
      Ok [ Ir.Atomic_mem { op = AtSwp; dst = res_reg; addr = base; src = val_reg; imm = m.disp } ]
  | (("dmb" | "dsb" | "isb"), _) ->
      Ok [ Ir.Nop ]

  | (m, _) ->
      (* Gracefully ignore non-essential platform pseudo-ops / hints *)
      if String.starts_with ~prefix:"." m || String.starts_with ~prefix:"lloh" (String.lowercase_ascii m) then
        Ok [ Ir.Nop ]
      else
        Error (Printf.sprintf "Unsupported or invalid ARM64 instruction: %s" m)

let lift_lines ?(options = default_options) (lines : raw_line list) : (Ir.func, string) result =
  let blocks = ref [] in
  let label_aliases = Hashtbl.create 32 in
  let cur_labels = ref [ "entry" ] in
  let cur_instrs = ref [] in
  let cur_id = ref 0 in

  let flush_block () =
    if !cur_instrs <> [] || !blocks = [] then begin
      let primary_label = match !cur_labels with hd :: _ -> hd | [] -> Printf.sprintf "l_bb_%d" !cur_id in
      List.iter (fun l -> Hashtbl.replace label_aliases l !cur_id) !cur_labels;
      let b = {
        Ir.id = !cur_id;
        label = primary_label;
        instrs = List.rev !cur_instrs;
      } in
      blocks := b :: !blocks;
      incr cur_id;
      cur_instrs := [];
      cur_labels := [ Printf.sprintf "l_bb_%d" !cur_id ]
    end
  in

  let rec process = function
    | [] ->
        flush_block ();
        Ok (List.rev !blocks)
    | LineEmpty :: rest | LineDirective _ :: rest | LineMarkerBegin _ :: rest | LineMarkerEnd :: rest -> process rest
    | LineLabel lbl :: rest ->
        if !cur_instrs <> [] then (
          flush_block ();
          cur_labels := [ lbl ]
        ) else (
          cur_labels := lbl :: !cur_labels
        );
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
      let label_map = label_aliases in
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

let extract_marked_regions ?(require_markers = false) (raw_lines : Arm64_parser.raw_line list) =
  let has_markers =
    List.exists
      (function
        | Arm64_parser.LineMarkerBegin _ | Arm64_parser.LineMarkerEnd -> true
        | _ -> false)
      raw_lines
  in
  if not has_markers then
    if require_markers then []
    else [ (Arm64_parser.ModeUltra "main", raw_lines) ]
  else
    let regions = ref [] in
    let current_mode = ref None in
    let fn_lines = ref [] in
    let last_label = ref "main" in
    let seen_begin = ref false in
    let seen_end = ref false in

    List.iter
      (function
        | Arm64_parser.LineLabel lbl when not (String.starts_with ~prefix:"L" lbl) && not (String.starts_with ~prefix:"." lbl) ->
            (match !current_mode with
            | Some m when !seen_begin ->
                regions := (m, Arm64_parser.LineLabel !last_label :: List.rev !fn_lines) :: !regions;
                current_mode := None;
                seen_begin := false;
                seen_end := false;
                fn_lines := []
            | _ ->
                fn_lines := []);
            last_label := lbl

        | Arm64_parser.LineMarkerBegin mode ->
            current_mode := Some mode;
            seen_begin := true

        | Arm64_parser.LineMarkerEnd ->
            seen_end := true

        | Arm64_parser.LineInstr (mnem, _) as instr ->
            if !seen_begin then begin
              if not !seen_end then
                fn_lines := instr :: !fn_lines
              else begin
                fn_lines := instr :: !fn_lines;
                if mnem = "ret" then begin
                  (match !current_mode with
                  | Some m ->
                      regions := (m, Arm64_parser.LineLabel !last_label :: List.rev !fn_lines) :: !regions;
                      current_mode := None;
                      seen_begin := false;
                      seen_end := false;
                      fn_lines := []
                  | None -> ())
                end
              end
            end else begin
              fn_lines := instr :: !fn_lines
            end

        | (Arm64_parser.LineLabel _ | Arm64_parser.LineDirective _) as line ->
            fn_lines := line :: !fn_lines
        | Arm64_parser.LineEmpty -> ())
      raw_lines;

    (match !current_mode with
    | Some m when !seen_begin ->
        regions := (m, Arm64_parser.LineLabel !last_label :: List.rev !fn_lines) :: !regions
    | _ -> ());

    if !regions = [] then
      [ (Arm64_parser.ModeUltra "main", raw_lines) ]
    else
      List.rev !regions

module Arm64_parser = Arm64_parser
module Literal_stitcher = Literal_stitcher
