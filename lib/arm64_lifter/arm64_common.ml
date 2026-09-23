open Vm_ir
open Arm64_types

let is_terminator = function
  | Ir.Jmp _ | Ir.Jcc _ | Ir.Ret | Ir.Trap _ | Ir.Vm_exit -> true
  | _ -> false

let raw_to_ir_operand ?(is_signed = false) = function
  | OpReg (Register.Vreg (Register.VZERO, _)) -> Ir.Imm 0L
  | OpReg r -> Ir.Reg r
  | OpImm i -> Ir.Imm i
  | OpMem m ->
      Ir.Mem {
        base = m.base;
        index = m.index;
        disp = m.disp;
        width = m.width;
        is_signed;
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
