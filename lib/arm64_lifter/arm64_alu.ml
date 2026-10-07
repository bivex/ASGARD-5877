open Vm_ir
open Arm64_types
open Arm64_common

(* Shifted-register ALU operand (e.g. `add w8, w8, w0, lsr #16`): materialise the
   shifted source into vtmp1, then apply the op through [emit_3addr_alu] so the
   src1 = dst emitter convention holds even for 3-operand forms. *)
let emit_shifted_alu ~op ~dst ~src1 ~src2 ~shift_op ~shift =
  [
    Ir.Mov { dst = Reg Register.vtmp1; src = Reg src2 };
    Ir.Alu { op = shift_op; dst = Register.vtmp1; src1 = Reg Register.vtmp1; src2 = Imm shift; set_flags = false };
  ]
  @ emit_3addr_alu ~op ~dst ~src1 ~src2:(OpReg Register.vtmp1) ~set_flags:false

let shift_op_of_label = function
  | "lsl" | "LSL" -> Ir.Shl
  | "asr" | "ASR" -> Ir.Sar
  | "ror" | "ROR" -> Ir.Ror
  | _ -> Ir.Shr

let lift (mnemonic : string) (ops : raw_op list) : Ir.instr list option =
  match (mnemonic, ops) with
  (* Moves & Loads of Constants *)
  | ("mov", [ OpReg dst; (OpReg _ | OpImm _ | OpMem _) as src ]) ->
      Some [ Ir.Mov { dst = Reg dst; src = raw_to_ir_operand src } ]
  | ("movz", (OpReg dst :: OpImm imm :: rest)) ->
      let shift = match rest with
        | (OpLabel ("lsl" | "LSL") :: OpImm s :: _) -> Int64.to_int s
        | [ OpLabel shift_s ] when String.contains shift_s '#' ->
            (match String.split_on_char '#' shift_s with
            | [ _; sh ] -> (match int_of_string_opt (String.trim sh) with Some s -> s | None -> 0)
            | _ -> 0)
        | _ -> 0
      in
      let full_imm = Int64.shift_left (Int64.logand imm 0xFFFFL) shift in
      Some [ Ir.Mov { dst = Reg dst; src = Imm full_imm } ]
  | ("movk", (OpReg dst :: OpImm imm :: rest)) ->
      let shift = match rest with
        | (OpLabel ("lsl" | "LSL") :: OpImm s :: _) -> Int64.to_int s
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
        Some [
          Ir.Alu { op = And; dst; src1 = Reg dst; src2 = Imm mask_val; set_flags = false };
          Ir.Alu { op = Or; dst; src1 = Reg dst; src2 = Imm shifted_imm; set_flags = false };
        ]
      else
        Some [
          Ir.Mov { dst = Reg Register.vtmp0; src = Imm mask };
          Ir.Alu { op = And; dst; src1 = Reg dst; src2 = Reg Register.vtmp0; set_flags = false };
          Ir.Mov { dst = Reg Register.vtmp0; src = Imm shifted_imm };
          Ir.Alu { op = Or; dst; src1 = Reg dst; src2 = Reg Register.vtmp0; set_flags = false };
        ]
  | ("mvn", [ OpReg dst; OpReg src ]) ->
      Some [
        Ir.Mov { dst = Reg dst; src = Reg src };
        Ir.Unary { op = Not; dst; src = Reg dst; set_flags = false };
      ]
  | (("adr" | "adrp"), [ OpReg dst; OpLabel sym_lbl ]) ->
      let sym = strip_page_suffix sym_lbl in
      Some [ Ir.Load_symbol { dst; sym; addend = 0L } ]
  | (("adr" | "adrp"), [ OpReg dst; _ ]) ->
      Some [ Ir.Mov { dst = Reg dst; src = Imm 0x100000000L } ]

  (* Arithmetic *)
  | ("add", [ OpReg dst; OpReg src1; ((OpReg _ | OpImm _) as src2) ]) ->
      Some (emit_3addr_alu ~op:Add ~dst ~src1 ~src2 ~set_flags:false)
  | ("add", [ OpReg dst; OpReg src1; OpLabel sym_lbl ]) ->
      let sym = strip_page_suffix sym_lbl in
      if Register.to_string dst = Register.to_string src1 then
        Some [ Ir.Nop ]
      else
        Some [ Ir.Load_symbol { dst; sym; addend = 0L } ]
  | ("add", (OpReg dst :: OpReg src1 :: OpReg src2 :: OpLabel (("lsl" | "LSL" | "lsr" | "LSR" | "asr" | "ASR" | "ror" | "ROR") as sh) :: OpImm shift :: _)) ->
      Some (emit_shifted_alu ~op:Add ~dst ~src1 ~src2 ~shift_op:(shift_op_of_label sh) ~shift)
  | ("adds", (OpReg dst :: OpReg src1 :: OpReg src2 :: OpLabel (("lsl" | "LSL" | "lsr" | "LSR" | "asr" | "ASR" | "ror" | "ROR") as sh) :: OpImm shift :: _)) ->
      let instrs = emit_shifted_alu ~op:Add ~dst ~src1 ~src2 ~shift_op:(shift_op_of_label sh) ~shift in
      Some (List.mapi (fun i ins ->
        if i = List.length instrs - 1 then
          match ins with Ir.Alu a -> Ir.Alu { a with set_flags = true } | other -> other
        else ins
      ) instrs)
  | ("add", (OpReg dst :: OpReg src1 :: _)) ->
      Some (emit_3addr_alu ~op:Add ~dst ~src1 ~src2:(OpImm 0L) ~set_flags:false)
  | ("adds", [ OpReg dst; OpReg src1; ((OpReg _ | OpImm _) as src2) ]) ->
      Some (emit_3addr_alu ~op:Add ~dst ~src1 ~src2 ~set_flags:true)

  | ("sub", (OpReg dst :: OpReg src1 :: OpReg src2 :: OpLabel (("lsl" | "LSL" | "lsr" | "LSR" | "asr" | "ASR" | "ror" | "ROR") as sh) :: OpImm shift :: _)) ->
      Some (emit_shifted_alu ~op:Sub ~dst ~src1 ~src2 ~shift_op:(shift_op_of_label sh) ~shift)
  | ("subs", (OpReg dst :: OpReg src1 :: OpReg src2 :: OpLabel (("lsl" | "LSL" | "lsr" | "LSR" | "asr" | "ASR" | "ror" | "ROR") as sh) :: OpImm shift :: _)) ->
      let instrs = emit_shifted_alu ~op:Sub ~dst ~src1 ~src2 ~shift_op:(shift_op_of_label sh) ~shift in
      Some (List.mapi (fun i ins ->
        if i = List.length instrs - 1 then
          match ins with Ir.Alu a -> Ir.Alu { a with set_flags = true } | other -> other
        else ins
      ) instrs)
  | ("sub", [ OpReg dst; OpReg src1; ((OpReg _ | OpImm _) as src2) ]) ->
      Some (emit_3addr_alu ~op:Sub ~dst ~src1 ~src2 ~set_flags:false)
  | ("subs", [ OpReg dst; OpReg src1; ((OpReg _ | OpImm _) as src2) ]) ->
      Some (emit_3addr_alu ~op:Sub ~dst ~src1 ~src2 ~set_flags:true)
  | ("adc", [ OpReg dst; OpReg src1; ((OpReg _ | OpImm _) as src2) ]) ->
      Some (emit_3addr_alu ~op:Adc ~dst ~src1 ~src2 ~set_flags:false)
  | ("adcs", [ OpReg dst; OpReg src1; ((OpReg _ | OpImm _) as src2) ]) ->
      Some (emit_3addr_alu ~op:Adc ~dst ~src1 ~src2 ~set_flags:true)
  | ("sbc", [ OpReg dst; OpReg src1; ((OpReg _ | OpImm _) as src2) ]) ->
      Some (emit_3addr_alu ~op:Sbb ~dst ~src1 ~src2 ~set_flags:false)
  | ("sbcs", [ OpReg dst; OpReg src1; ((OpReg _ | OpImm _) as src2) ]) ->
      Some (emit_3addr_alu ~op:Sbb ~dst ~src1 ~src2 ~set_flags:true)
  | ("ngc", [ OpReg dst; ((OpReg _ | OpImm _) as src) ]) ->
      let w = Register.get_width dst in
      Some (emit_3addr_alu ~op:Sbb ~dst ~src1:(Register.Vreg (Register.VZERO, w)) ~src2:src ~set_flags:false)
  | ("ngcs", [ OpReg dst; ((OpReg _ | OpImm _) as src) ]) ->
      let w = Register.get_width dst in
      Some (emit_3addr_alu ~op:Sbb ~dst ~src1:(Register.Vreg (Register.VZERO, w)) ~src2:src ~set_flags:true)

  | ("mul", [ OpReg dst; OpReg src1; ((OpReg _ | OpImm _) as src2) ]) ->
      Some (emit_3addr_alu ~op:Mul ~dst ~src1 ~src2 ~set_flags:false)
  | ("madd", [ OpReg dst; OpReg src1; OpReg src2; OpReg src3 ]) ->
      Some [
        Ir.Alu { op = Mul; dst; src1 = Reg src1; src2 = Reg src2; set_flags = false };
        Ir.Alu { op = Add; dst; src1 = Reg dst; src2 = Reg src3; set_flags = false };
      ]
  | ("msub", [ OpReg dst; OpReg src1; OpReg src2; OpReg src3 ]) ->
      Some [
        Ir.Alu { op = Mul; dst; src1 = Reg src1; src2 = Reg src2; set_flags = false };
        Ir.Alu { op = Sub; dst; src1 = Reg src3; src2 = Reg dst; set_flags = false };
      ]
  | ("sdiv", [ OpReg dst; OpReg src1; OpReg src2 ]) ->
      Some [ Ir.Alu { op = Idiv; dst; src1 = Reg src1; src2 = Reg src2; set_flags = false } ]
  | ("udiv", [ OpReg dst; OpReg src1; OpReg src2 ]) ->
      Some [ Ir.Alu { op = Div; dst; src1 = Reg src1; src2 = Reg src2; set_flags = false } ]
  | ("smulh", [ OpReg dst; OpReg src1; OpReg src2 ]) ->
      Some [ Ir.Alu { op = Imulh; dst; src1 = Reg src1; src2 = Reg src2; set_flags = false } ]
  | ("umulh", [ OpReg dst; OpReg src1; OpReg src2 ]) ->
      Some [ Ir.Alu { op = Mulh; dst; src1 = Reg src1; src2 = Reg src2; set_flags = false } ]
  | ("smaddl", [ OpReg dst; OpReg src1; OpReg src2; OpReg src3 ]) ->
      Some [
        Ir.Mov { dst = Reg Register.vtmp0; src = Reg src1 };
        Ir.Alu { op = Shl; dst = Register.vtmp0; src1 = Reg Register.vtmp0; src2 = Imm 32L; set_flags = false };
        Ir.Alu { op = Sar; dst = Register.vtmp0; src1 = Reg Register.vtmp0; src2 = Imm 32L; set_flags = false };
        Ir.Mov { dst = Reg Register.vtmp1; src = Reg src2 };
        Ir.Alu { op = Shl; dst = Register.vtmp1; src1 = Reg Register.vtmp1; src2 = Imm 32L; set_flags = false };
        Ir.Alu { op = Sar; dst = Register.vtmp1; src1 = Reg Register.vtmp1; src2 = Imm 32L; set_flags = false };
        Ir.Alu { op = Imul; dst = Register.vtmp0; src1 = Reg Register.vtmp0; src2 = Reg Register.vtmp1; set_flags = false };
        Ir.Alu { op = Add; dst; src1 = Reg src3; src2 = Reg Register.vtmp0; set_flags = false };
      ]
  | ("umaddl", [ OpReg dst; OpReg src1; OpReg src2; OpReg src3 ]) ->
      Some [
        Ir.Mov { dst = Reg Register.vtmp0; src = Reg src1 };
        Ir.Alu { op = And; dst = Register.vtmp0; src1 = Reg Register.vtmp0; src2 = Imm 0xFFFFFFFFL; set_flags = false };
        Ir.Mov { dst = Reg Register.vtmp1; src = Reg src2 };
        Ir.Alu { op = And; dst = Register.vtmp1; src1 = Reg Register.vtmp1; src2 = Imm 0xFFFFFFFFL; set_flags = false };
        Ir.Alu { op = Mul; dst = Register.vtmp0; src1 = Reg Register.vtmp0; src2 = Reg Register.vtmp1; set_flags = false };
        Ir.Alu { op = Add; dst; src1 = Reg src3; src2 = Reg Register.vtmp0; set_flags = false };
      ]
  | ("smsubl", [ OpReg dst; OpReg src1; OpReg src2; OpReg src3 ]) ->
      Some [
        Ir.Mov { dst = Reg Register.vtmp0; src = Reg src1 };
        Ir.Alu { op = Shl; dst = Register.vtmp0; src1 = Reg Register.vtmp0; src2 = Imm 32L; set_flags = false };
        Ir.Alu { op = Sar; dst = Register.vtmp0; src1 = Reg Register.vtmp0; src2 = Imm 32L; set_flags = false };
        Ir.Mov { dst = Reg Register.vtmp1; src = Reg src2 };
        Ir.Alu { op = Shl; dst = Register.vtmp1; src1 = Reg Register.vtmp1; src2 = Imm 32L; set_flags = false };
        Ir.Alu { op = Sar; dst = Register.vtmp1; src1 = Reg Register.vtmp1; src2 = Imm 32L; set_flags = false };
        Ir.Alu { op = Imul; dst = Register.vtmp0; src1 = Reg Register.vtmp0; src2 = Reg Register.vtmp1; set_flags = false };
        Ir.Alu { op = Sub; dst; src1 = Reg src3; src2 = Reg Register.vtmp0; set_flags = false };
      ]
  | ("umsubl", [ OpReg dst; OpReg src1; OpReg src2; OpReg src3 ]) ->
      Some [
        Ir.Mov { dst = Reg Register.vtmp0; src = Reg src1 };
        Ir.Alu { op = And; dst = Register.vtmp0; src1 = Reg Register.vtmp0; src2 = Imm 0xFFFFFFFFL; set_flags = false };
        Ir.Mov { dst = Reg Register.vtmp1; src = Reg src2 };
        Ir.Alu { op = And; dst = Register.vtmp1; src1 = Reg Register.vtmp1; src2 = Imm 0xFFFFFFFFL; set_flags = false };
        Ir.Alu { op = Mul; dst = Register.vtmp0; src1 = Reg Register.vtmp0; src2 = Reg Register.vtmp1; set_flags = false };
        Ir.Alu { op = Sub; dst; src1 = Reg src3; src2 = Reg Register.vtmp0; set_flags = false };
      ]
  | ("smull", [ OpReg dst; OpReg src1; OpReg src2 ]) ->
      Some [
        Ir.Mov { dst = Reg Register.vtmp0; src = Reg src1 };
        Ir.Alu { op = Shl; dst = Register.vtmp0; src1 = Reg Register.vtmp0; src2 = Imm 32L; set_flags = false };
        Ir.Alu { op = Sar; dst = Register.vtmp0; src1 = Reg Register.vtmp0; src2 = Imm 32L; set_flags = false };
        Ir.Mov { dst = Reg Register.vtmp1; src = Reg src2 };
        Ir.Alu { op = Shl; dst = Register.vtmp1; src1 = Reg Register.vtmp1; src2 = Imm 32L; set_flags = false };
        Ir.Alu { op = Sar; dst = Register.vtmp1; src1 = Reg Register.vtmp1; src2 = Imm 32L; set_flags = false };
        Ir.Alu { op = Imul; dst; src1 = Reg Register.vtmp0; src2 = Reg Register.vtmp1; set_flags = false };
      ]
  | ("umull", [ OpReg dst; OpReg src1; OpReg src2 ]) ->
      Some [
        Ir.Mov { dst = Reg Register.vtmp0; src = Reg src1 };
        Ir.Alu { op = And; dst = Register.vtmp0; src1 = Reg Register.vtmp0; src2 = Imm 0xFFFFFFFFL; set_flags = false };
        Ir.Mov { dst = Reg Register.vtmp1; src = Reg src2 };
        Ir.Alu { op = And; dst = Register.vtmp1; src1 = Reg Register.vtmp1; src2 = Imm 0xFFFFFFFFL; set_flags = false };
        Ir.Alu { op = Mul; dst; src1 = Reg Register.vtmp0; src2 = Reg Register.vtmp1; set_flags = false };
      ]

  (* Logic & Shifted Register Operands *)
  | ("and", (OpReg dst :: OpReg src1 :: OpReg src2 :: OpLabel (("lsl" | "LSL" | "lsr" | "LSR" | "asr" | "ASR" | "ror" | "ROR") as sh) :: OpImm shift :: _)) ->
      Some (emit_shifted_alu ~op:And ~dst ~src1 ~src2 ~shift_op:(shift_op_of_label sh) ~shift)
  | ("ands", (OpReg dst :: OpReg src1 :: OpReg src2 :: OpLabel (("lsl" | "LSL" | "lsr" | "LSR" | "asr" | "ASR" | "ror" | "ROR") as sh) :: OpImm shift :: _)) ->
      let instrs = emit_shifted_alu ~op:And ~dst ~src1 ~src2 ~shift_op:(shift_op_of_label sh) ~shift in
      Some (List.mapi (fun i ins ->
        if i = List.length instrs - 1 then
          match ins with Ir.Alu a -> Ir.Alu { a with set_flags = true } | other -> other
        else ins
      ) instrs)
  | ("orr", (OpReg dst :: OpReg src1 :: OpReg src2 :: OpLabel (("lsl" | "LSL" | "lsr" | "LSR" | "asr" | "ASR" | "ror" | "ROR") as sh) :: OpImm shift :: _)) ->
      Some (emit_shifted_alu ~op:Or ~dst ~src1 ~src2 ~shift_op:(shift_op_of_label sh) ~shift)
  | ("eor", (OpReg dst :: OpReg src1 :: OpReg src2 :: OpLabel (("lsl" | "LSL" | "lsr" | "LSR" | "asr" | "ASR" | "ror" | "ROR") as sh) :: OpImm shift :: _)) ->
      Some (emit_shifted_alu ~op:Xor ~dst ~src1 ~src2 ~shift_op:(shift_op_of_label sh) ~shift)
  | ("bic", (OpReg dst :: OpReg src1 :: OpReg src2 :: OpLabel (("lsl" | "LSL" | "lsr" | "LSR" | "asr" | "ASR" | "ror" | "ROR") as sh) :: OpImm shift :: _)) ->
      Some [
        Ir.Mov { dst = Reg Register.vtmp1; src = Reg src2 };
        Ir.Alu { op = shift_op_of_label sh; dst = Register.vtmp1; src1 = Reg Register.vtmp1; src2 = Imm shift; set_flags = false };
        Ir.Unary { op = Not; dst = Register.vtmp1; src = Reg Register.vtmp1; set_flags = false };
        Ir.Alu { op = And; dst; src1 = Reg src1; src2 = Reg Register.vtmp1; set_flags = false };
      ]
  | ("bics", (OpReg dst :: OpReg src1 :: OpReg src2 :: OpLabel (("lsl" | "LSL" | "lsr" | "LSR" | "asr" | "ASR" | "ror" | "ROR") as sh) :: OpImm shift :: _)) ->
      Some [
        Ir.Mov { dst = Reg Register.vtmp1; src = Reg src2 };
        Ir.Alu { op = shift_op_of_label sh; dst = Register.vtmp1; src1 = Reg Register.vtmp1; src2 = Imm shift; set_flags = false };
        Ir.Unary { op = Not; dst = Register.vtmp1; src = Reg Register.vtmp1; set_flags = false };
        Ir.Alu { op = And; dst; src1 = Reg src1; src2 = Reg Register.vtmp1; set_flags = true };
      ]
  | ("and", (OpReg dst :: OpReg src1 :: ((OpReg _ | OpImm _) as src2) :: _)) ->
      Some (emit_3addr_alu ~op:And ~dst ~src1 ~src2 ~set_flags:false)
  | ("ands", (OpReg dst :: OpReg src1 :: ((OpReg _ | OpImm _) as src2) :: _)) ->
      Some (emit_3addr_alu ~op:And ~dst ~src1 ~src2 ~set_flags:true)

  | ("orr", (OpReg dst :: OpReg src1 :: ((OpReg _ | OpImm _) as src2) :: _)) ->
      Some (emit_3addr_alu ~op:Or ~dst ~src1 ~src2 ~set_flags:false)
  | ("eor", (OpReg dst :: OpReg src1 :: ((OpReg _ | OpImm _) as src2) :: _)) ->
      Some (emit_3addr_alu ~op:Xor ~dst ~src1 ~src2 ~set_flags:false)
  | ("bic", (OpReg dst :: OpReg src1 :: ((OpReg _ | OpImm _) as src2) :: _)) ->
      Some [
        Ir.Mov { dst = Reg Register.vtmp1; src = raw_to_ir_operand src2 };
        Ir.Unary { op = Not; dst = Register.vtmp1; src = Reg Register.vtmp1; set_flags = false };
        Ir.Alu { op = And; dst; src1 = Reg src1; src2 = Reg Register.vtmp1; set_flags = false };
      ]
  | ("bics", (OpReg dst :: OpReg src1 :: ((OpReg _ | OpImm _) as src2) :: _)) ->
      Some [
        Ir.Mov { dst = Reg Register.vtmp1; src = raw_to_ir_operand src2 };
        Ir.Unary { op = Not; dst = Register.vtmp1; src = Reg Register.vtmp1; set_flags = false };
        Ir.Alu { op = And; dst; src1 = Reg src1; src2 = Reg Register.vtmp1; set_flags = true };
      ]
  | ("orn", (OpReg dst :: OpReg src1 :: ((OpReg _ | OpImm _) as src2) :: _)) ->
      Some [
        Ir.Mov { dst = Reg Register.vtmp1; src = raw_to_ir_operand src2 };
        Ir.Unary { op = Not; dst = Register.vtmp1; src = Reg Register.vtmp1; set_flags = false };
        Ir.Alu { op = Or; dst; src1 = Reg src1; src2 = Reg Register.vtmp1; set_flags = false };
      ]
  | ("eon", (OpReg dst :: OpReg src1 :: ((OpReg _ | OpImm _) as src2) :: _)) ->
      Some [
        Ir.Mov { dst = Reg Register.vtmp1; src = raw_to_ir_operand src2 };
        Ir.Unary { op = Not; dst = Register.vtmp1; src = Reg Register.vtmp1; set_flags = false };
        Ir.Alu { op = Xor; dst; src1 = Reg src1; src2 = Reg Register.vtmp1; set_flags = false };
      ]

  (* Shifts & Bitfields *)
  | ("lsl", [ OpReg dst; OpReg src1; OpImm shift ]) ->
      Some (emit_3addr_alu ~op:Shl ~dst ~src1 ~src2:(OpImm shift) ~set_flags:false)
  | ("lsr", [ OpReg dst; OpReg src1; OpImm shift ]) ->
      Some (emit_3addr_alu ~op:Shr ~dst ~src1 ~src2:(OpImm shift) ~set_flags:false)
  | ("asr", [ OpReg dst; OpReg src1; OpImm shift ]) ->
      Some (emit_3addr_alu ~op:Sar ~dst ~src1 ~src2:(OpImm shift) ~set_flags:false)
  | ("ror", [ OpReg dst; OpReg src1; OpImm shift ]) ->
      Some (emit_3addr_alu ~op:Ror ~dst ~src1 ~src2:(OpImm shift) ~set_flags:false)
  | ("ubfx", (OpReg dst :: OpReg src :: OpImm lsb :: OpImm width :: _)) ->
      let w = min 64 (max 1 (Int64.to_int width)) in
      let mask = if w = 64 then -1L else Int64.sub (Int64.shift_left 1L w) 1L in
      Some [
        Ir.Mov { dst = Reg dst; src = Reg src };
        Ir.Alu { op = Shr; dst; src1 = Reg dst; src2 = Imm lsb; set_flags = false };
        Ir.Alu { op = And; dst; src1 = Reg dst; src2 = Imm mask; set_flags = false };
      ]
  | ("sbfx", (OpReg dst :: OpReg src :: OpImm lsb :: OpImm width :: _)) ->
      let w = min 64 (max 1 (Int64.to_int width)) in
      let shift_left_amt = max 0 (64 - (Int64.to_int lsb + w)) in
      let shift_right_amt = 64 - w in
      Some [
        Ir.Mov { dst = Reg dst; src = Reg src };
        Ir.Alu { op = Shl; dst; src1 = Reg dst; src2 = Imm (Int64.of_int shift_left_amt); set_flags = false };
        Ir.Alu { op = Sar; dst; src1 = Reg dst; src2 = Imm (Int64.of_int shift_right_amt); set_flags = false };
      ]
  | ("ubfm", (OpReg dst :: OpReg src :: OpImm immr :: OpImm imms :: _)) ->
      let reg_bits = match Register.get_width dst with Register.B32 -> 32 | _ -> 64 in
      let immr_i = Int64.to_int immr in
      let imms_i = Int64.to_int imms in
      if imms_i >= immr_i then
        let w = min reg_bits (imms_i - immr_i + 1) in
        let mask = if w >= 64 then -1L else Int64.sub (Int64.shift_left 1L w) 1L in
        Some [
          Ir.Mov { dst = Reg dst; src = Reg src };
          Ir.Alu { op = Shr; dst; src1 = Reg dst; src2 = Imm immr; set_flags = false };
          Ir.Alu { op = And; dst; src1 = Reg dst; src2 = Imm mask; set_flags = false };
        ]
      else
        let w = min reg_bits (imms_i + 1) in
        let lshift = Int64.of_int (reg_bits - immr_i) in
        let mask = if w >= 64 then -1L else Int64.sub (Int64.shift_left 1L w) 1L in
        Some [
          Ir.Mov { dst = Reg dst; src = Reg src };
          Ir.Alu { op = And; dst; src1 = Reg dst; src2 = Imm mask; set_flags = false };
          Ir.Alu { op = Shl; dst; src1 = Reg dst; src2 = Imm lshift; set_flags = false };
        ]
  | ("sbfm", (OpReg dst :: OpReg src :: OpImm immr :: OpImm imms :: _)) ->
      let reg_bits = match Register.get_width dst with Register.B32 -> 32 | _ -> 64 in
      let immr_i = Int64.to_int immr in
      let imms_i = Int64.to_int imms in
      if imms_i >= immr_i then
        let w = min reg_bits (imms_i - immr_i + 1) in
        let shift_left_amt = max 0 (64 - (immr_i + w)) in
        let shift_right_amt = 64 - w in
        Some [
          Ir.Mov { dst = Reg dst; src = Reg src };
          Ir.Alu { op = Shl; dst; src1 = Reg dst; src2 = Imm (Int64.of_int shift_left_amt); set_flags = false };
          Ir.Alu { op = Sar; dst; src1 = Reg dst; src2 = Imm (Int64.of_int shift_right_amt); set_flags = false };
        ]
      else
        let w = min reg_bits (imms_i + 1) in
        let lshift = Int64.of_int (reg_bits - immr_i) in
        let mask = if w >= 64 then -1L else Int64.sub (Int64.shift_left 1L w) 1L in
        Some [
          Ir.Mov { dst = Reg dst; src = Reg src };
          Ir.Alu { op = And; dst; src1 = Reg dst; src2 = Imm mask; set_flags = false };
          Ir.Alu { op = Shl; dst; src1 = Reg dst; src2 = Imm lshift; set_flags = false };
        ]
  | ("bfi", (OpReg dst :: OpReg src :: OpImm lsb :: OpImm width :: _)) ->
      let w = min 64 (max 1 (Int64.to_int width)) in
      let lsb_i = Int64.to_int lsb in
      let base_mask = if w = 64 then -1L else Int64.sub (Int64.shift_left 1L w) 1L in
      let field_mask = Int64.shift_left base_mask lsb_i in
      let inv_mask = Int64.lognot field_mask in
      Some [
        Ir.Mov { dst = Reg Register.vtmp0; src = Imm inv_mask };
        Ir.Alu { op = And; dst; src1 = Reg dst; src2 = Reg Register.vtmp0; set_flags = false };
        Ir.Mov { dst = Reg Register.vtmp1; src = Reg src };
        Ir.Mov { dst = Reg Register.vtmp0; src = Imm base_mask };
        Ir.Alu { op = And; dst = Register.vtmp1; src1 = Reg Register.vtmp1; src2 = Reg Register.vtmp0; set_flags = false };
        Ir.Alu { op = Shl; dst = Register.vtmp1; src1 = Reg Register.vtmp1; src2 = Imm lsb; set_flags = false };
        Ir.Alu { op = Or; dst; src1 = Reg dst; src2 = Reg Register.vtmp1; set_flags = false };
      ]
  | ("bfxil", (OpReg dst :: OpReg src :: OpImm lsb :: OpImm width :: _)) ->
      let w = min 64 (max 1 (Int64.to_int width)) in
      let base_mask = if w = 64 then -1L else Int64.sub (Int64.shift_left 1L w) 1L in
      let inv_mask = Int64.lognot base_mask in
      Some [
        Ir.Mov { dst = Reg Register.vtmp0; src = Imm inv_mask };
        Ir.Alu { op = And; dst; src1 = Reg dst; src2 = Reg Register.vtmp0; set_flags = false };
        Ir.Mov { dst = Reg Register.vtmp1; src = Reg src };
        Ir.Alu { op = Shr; dst = Register.vtmp1; src1 = Reg Register.vtmp1; src2 = Imm lsb; set_flags = false };
        Ir.Mov { dst = Reg Register.vtmp0; src = Imm base_mask };
        Ir.Alu { op = And; dst = Register.vtmp1; src1 = Reg Register.vtmp1; src2 = Reg Register.vtmp0; set_flags = false };
        Ir.Alu { op = Or; dst; src1 = Reg dst; src2 = Reg Register.vtmp1; set_flags = false };
      ]
  | ("extr", (OpReg dst :: OpReg src1 :: OpReg src2 :: OpImm shift :: _)) ->
      let total_bits = if Register.get_width dst = Register.B32 then 32 else 64 in
      let sh = Int64.to_int shift in
      if sh = 0 then
        Some [ Ir.Mov { dst = Reg dst; src = Reg src2 } ]
      else if Register.to_string src1 = Register.to_string src2 then
        Some [
          Ir.Mov { dst = Reg dst; src = Reg src1 };
          Ir.Alu { op = Ror; dst; src1 = Reg dst; src2 = Imm shift; set_flags = false };
        ]
      else
        let sh_hi = Int64.of_int (total_bits - sh) in
        Some [
          Ir.Mov { dst = Reg dst; src = Reg src2 };
          Ir.Alu { op = Shr; dst; src1 = Reg dst; src2 = Imm shift; set_flags = false };
          Ir.Mov { dst = Reg Register.vtmp1; src = Reg src1 };
          Ir.Alu { op = Shl; dst = Register.vtmp1; src1 = Reg Register.vtmp1; src2 = Imm sh_hi; set_flags = false };
          Ir.Alu { op = Or; dst; src1 = Reg dst; src2 = Reg Register.vtmp1; set_flags = false };
        ]
  | ("neg", [ OpReg dst; OpReg src ]) ->
      Some [ Ir.Unary { op = Neg; dst; src = Reg src; set_flags = false } ]
  | ("clz", [ OpReg dst; OpReg src ]) ->
      Some [ Ir.Unary { op = Clz; dst; src = Reg src; set_flags = false } ]
  | ("cls", [ OpReg dst; OpReg src ]) ->
      Some [ Ir.Unary { op = Clz; dst; src = Reg src; set_flags = false } ]
  | ("rbit", [ OpReg dst; OpReg src ]) ->
      Some [ Ir.Unary { op = Rbit; dst; src = Reg src; set_flags = false } ]
  | ("rev", [ OpReg dst; OpReg src ]) ->
      Some [ Ir.Unary { op = Bswap; dst; src = Reg src; set_flags = false } ]
  | ("rev16", [ OpReg dst; OpReg src ]) ->
      let d_b16 = Register.with_width dst Register.B16 in
      Some [ Ir.Unary { op = Bswap; dst = d_b16; src = Reg src; set_flags = false } ]
  | ("rev32", [ OpReg dst; OpReg src ]) ->
      let d_b32 = Register.with_width dst Register.B32 in
      Some [ Ir.Unary { op = Bswap; dst = d_b32; src = Reg src; set_flags = false } ]

  (* Comparisons & Extended Register Comparisons *)
  | ("cmp", (OpReg src1 :: OpReg src2 :: OpLabel ("uxth" | "UXTH") :: _)) ->
      Some [
        Ir.Mov { dst = Reg Register.vtmp0; src = Reg src2 };
        Ir.Alu { op = And; dst = Register.vtmp0; src1 = Reg Register.vtmp0; src2 = Imm 0xFFFFL; set_flags = false };
        Ir.Cmp { src1 = Reg src1; src2 = Reg Register.vtmp0 };
      ]
  | ("cmp", (OpReg src1 :: OpReg src2 :: OpLabel ("uxtb" | "UXTB") :: _)) ->
      Some [
        Ir.Mov { dst = Reg Register.vtmp0; src = Reg src2 };
        Ir.Alu { op = And; dst = Register.vtmp0; src1 = Reg Register.vtmp0; src2 = Imm 0xFFL; set_flags = false };
        Ir.Cmp { src1 = Reg src1; src2 = Reg Register.vtmp0 };
      ]
  | ("cmp", (OpReg src1 :: OpReg src2 :: OpLabel ("uxtw" | "UXTW") :: _)) ->
      Some [
        Ir.Mov { dst = Reg Register.vtmp0; src = Reg src2 };
        Ir.Alu { op = And; dst = Register.vtmp0; src1 = Reg Register.vtmp0; src2 = Imm 0xFFFFFFFFL; set_flags = false };
        Ir.Cmp { src1 = Reg src1; src2 = Reg Register.vtmp0 };
      ]
  | ("cmp", (OpReg src1 :: OpReg src2 :: OpLabel (("lsl" | "LSL" | "lsr" | "LSR" | "asr" | "ASR" | "ror" | "ROR") as sh) :: OpImm shift :: _)) ->
      Some [
        Ir.Mov { dst = Reg Register.vtmp1; src = Reg src2 };
        Ir.Alu { op = shift_op_of_label sh; dst = Register.vtmp1; src1 = Reg Register.vtmp1; src2 = Imm shift; set_flags = false };
        Ir.Cmp { src1 = Reg src1; src2 = Reg Register.vtmp1 };
      ]
  | ("cmn", (OpReg src1 :: OpReg src2 :: OpLabel (("lsl" | "LSL" | "lsr" | "LSR" | "asr" | "ASR" | "ror" | "ROR") as sh) :: OpImm shift :: _)) ->
      Some [
        Ir.Mov { dst = Reg Register.vtmp1; src = Reg src2 };
        Ir.Alu { op = shift_op_of_label sh; dst = Register.vtmp1; src1 = Reg Register.vtmp1; src2 = Imm shift; set_flags = false };
        Ir.Alu { op = Add; dst = Register.vtmp0; src1 = Reg src1; src2 = Reg Register.vtmp1; set_flags = true };
      ]
  | ("tst", (OpReg src1 :: OpReg src2 :: OpLabel (("lsl" | "LSL" | "lsr" | "LSR" | "asr" | "ASR" | "ror" | "ROR") as sh) :: OpImm shift :: _)) ->
      Some [
        Ir.Mov { dst = Reg Register.vtmp1; src = Reg src2 };
        Ir.Alu { op = shift_op_of_label sh; dst = Register.vtmp1; src1 = Reg Register.vtmp1; src2 = Imm shift; set_flags = false };
        Ir.Test { src1 = Reg src1; src2 = Reg Register.vtmp1 };
      ]
  | ("cmp", (OpReg src1 :: ((OpReg _ | OpImm _) as src2) :: _)) ->
      Some [ Ir.Cmp { src1 = Reg src1; src2 = raw_to_ir_operand src2 } ]
  | ("cmn", (OpReg src1 :: ((OpReg _ | OpImm _) as src2) :: _)) ->
      Some [ Ir.Alu { op = Add; dst = Register.vtmp0; src1 = Reg src1; src2 = raw_to_ir_operand src2; set_flags = true } ]
  | ("tst", (OpReg src1 :: ((OpReg _ | OpImm _) as src2) :: _)) ->
      Some [ Ir.Test { src1 = Reg src1; src2 = raw_to_ir_operand src2 } ]
  | ("ccmp", (OpReg src1 :: OpReg src2 :: OpImm nzcv :: cond_op :: _)) ->
      let c_str = match cond_op with OpLabel s -> s | OpReg r -> Register.to_string r | _ -> "al" in
      Some [ Ir.Ccmp { cond = map_cond_str c_str; src1 = Reg src1; src2 = Reg src2; nzcv = Int64.to_int nzcv } ]
  | ("ccmp", (OpReg src1 :: OpImm imm :: OpImm nzcv :: cond_op :: _)) ->
      let c_str = match cond_op with OpLabel s -> s | OpReg r -> Register.to_string r | _ -> "al" in
      Some [ Ir.Ccmp { cond = map_cond_str c_str; src1 = Reg src1; src2 = Imm imm; nzcv = Int64.to_int nzcv } ]
  | ("ccmn", (OpReg src1 :: OpReg src2 :: OpImm nzcv :: cond_op :: _)) ->
      let c_str = match cond_op with OpLabel s -> s | OpReg r -> Register.to_string r | _ -> "al" in
      Some [ Ir.Ccmn { cond = map_cond_str c_str; src1 = Reg src1; src2 = Reg src2; nzcv = Int64.to_int nzcv } ]
  | ("ccmn", (OpReg src1 :: OpImm imm :: OpImm nzcv :: cond_op :: _)) ->
      let c_str = match cond_op with OpLabel s -> s | OpReg r -> Register.to_string r | _ -> "al" in
      Some [ Ir.Ccmn { cond = map_cond_str c_str; src1 = Reg src1; src2 = Imm imm; nzcv = Int64.to_int nzcv } ]

  (* Conditional Set / Select *)
  | ("cset", [ OpReg dst; cond_op ]) ->
      let c_str = match cond_op with OpLabel s -> s | OpReg r -> Register.to_string r | _ -> "eq" in
      Some [
        Ir.Mov { dst = Reg dst; src = Imm 0L };
        Ir.Setcc { cond = map_cond_str c_str; dst = Reg dst };
      ]
  | ("cset", (OpReg dst :: _)) ->
      Some [
        Ir.Mov { dst = Reg dst; src = Imm 0L };
        Ir.Setcc { cond = E; dst = Reg dst };
      ]
  | ("fcsel", (OpReg (Register.Fpr (d, dw)) :: src1_op :: src2_op :: cond_op :: _)) ->
      let c_str = match cond_op with OpLabel s -> s | OpReg r -> Register.to_string r | _ -> "eq" in
      let cond = map_cond_str c_str in
      (match src1_op, src2_op with
      | OpReg (Register.Fpr (s1, _)), OpReg (Register.Fpr (s2, _)) ->
          if d = s2 then
            Some [
              Ir.Cmov { cond; dst = Register.Fpr (d, dw); src = Reg (Register.Fpr (s1, dw)) };
            ]
          else if d = s1 then
            Some [
              Ir.Cmov { cond = Flags.condition_negate cond; dst = Register.Fpr (d, dw); src = Reg (Register.Fpr (s2, dw)) };
            ]
          else
            Some [
              Ir.Mov { dst = Reg (Register.Fpr (d, dw)); src = Reg (Register.Fpr (s2, dw)) };
              Ir.Cmov { cond; dst = Register.Fpr (d, dw); src = Reg (Register.Fpr (s1, dw)) };
            ]
      | _ -> None)
  | ("csel", (OpReg dst :: src1_op :: src2_op :: cond_op :: _)) ->
      let c_str = match cond_op with OpLabel s -> s | OpReg r -> Register.to_string r | _ -> "eq" in
      let is_zero = function
        | OpReg (Register.Vreg (Register.VZERO, _)) -> true
        | OpImm 0L -> true
        | _ -> false
      in
      if is_zero src2_op && (match src1_op with OpReg r -> r = dst | _ -> false) then
        Some [
          Ir.Mov { dst = Reg Register.vtmp1; src = Imm 0L };
          Ir.Cmov { cond = Flags.condition_negate (map_cond_str c_str); dst; src = Reg Register.vtmp1 };
        ]
      else if is_zero src1_op && (match src2_op with OpReg r -> r = dst | _ -> false) then
        Some [
          Ir.Mov { dst = Reg Register.vtmp1; src = Imm 0L };
          Ir.Cmov { cond = map_cond_str c_str; dst; src = Reg Register.vtmp1 };
        ]
      else
        Some [
          Ir.Mov { dst = Reg dst; src = raw_to_ir_operand src2_op };
          Ir.Mov { dst = Reg Register.vtmp1; src = raw_to_ir_operand src1_op };
          Ir.Cmov { cond = map_cond_str c_str; dst; src = Reg Register.vtmp1 };
        ]
  | ("cinc", (OpReg dst :: OpReg src :: cond_op :: _)) ->
      let c_str = match cond_op with OpLabel s -> s | OpReg r -> Register.to_string r | _ -> "eq" in
      Some [
        Ir.Mov { dst = Reg dst; src = Reg src };
        Ir.Alu { op = Add; dst; src1 = Reg dst; src2 = Imm 1L; set_flags = false };
        Ir.Cmov { cond = Flags.condition_negate (map_cond_str c_str); dst; src = Reg src };
      ]
  | ("csinc", (OpReg dst :: OpReg src1 :: OpReg src2 :: cond_op :: _)) ->
      let c_str = match cond_op with OpLabel s -> s | OpReg r -> Register.to_string r | _ -> "eq" in
      let cond = map_cond_str c_str in
      Some [
        Ir.Mov { dst = Reg dst; src = Reg src2 };
        Ir.Alu { op = Add; dst; src1 = Reg dst; src2 = Imm 1L; set_flags = false };
        Ir.Cmov { cond; dst; src = Reg src1 };
      ]
  | ("cinv", (OpReg dst :: OpReg src :: cond_op :: _)) ->
      let c_str = match cond_op with OpLabel s -> s | OpReg r -> Register.to_string r | _ -> "eq" in
      let cond = Flags.condition_negate (map_cond_str c_str) in
      Some [
        Ir.Mov { dst = Reg dst; src = Reg src };
        Ir.Unary { op = Not; dst; src = Reg dst; set_flags = false };
        Ir.Cmov { cond; dst; src = Reg src };
      ]
  | ("csinv", (OpReg dst :: OpReg src1 :: OpReg src2 :: cond_op :: _)) ->
      let c_str = match cond_op with OpLabel s -> s | OpReg r -> Register.to_string r | _ -> "eq" in
      let cond = map_cond_str c_str in
      Some [
        Ir.Mov { dst = Reg dst; src = Reg src2 };
        Ir.Unary { op = Not; dst; src = Reg dst; set_flags = false };
        Ir.Cmov { cond; dst; src = Reg src1 };
      ]
  | ("cneg", (OpReg dst :: OpReg src :: cond_op :: _)) ->
      let c_str = match cond_op with OpLabel s -> s | OpReg r -> Register.to_string r | _ -> "eq" in
      let cond = Flags.condition_negate (map_cond_str c_str) in
      Some [
        Ir.Mov { dst = Reg dst; src = Reg src };
        Ir.Unary { op = Neg; dst; src = Reg dst; set_flags = false };
        Ir.Cmov { cond; dst; src = Reg src };
      ]
  | ("csneg", (OpReg dst :: OpReg src1 :: OpReg src2 :: cond_op :: _)) ->
      let c_str = match cond_op with OpLabel s -> s | OpReg r -> Register.to_string r | _ -> "eq" in
      let cond = map_cond_str c_str in
      Some [
        Ir.Mov { dst = Reg dst; src = Reg src2 };
        Ir.Unary { op = Neg; dst; src = Reg dst; set_flags = false };
        Ir.Cmov { cond; dst; src = Reg src1 };
      ]
  | (("dmb" | "dsb" | "isb" | "prfm"), _) ->
      Some [ Ir.Nop ]
  | (("cnt" | "cnt.8b" | "cnt.16b"), [ OpReg dst; OpReg src ]) ->
      Some [ Ir.Unary { op = Ir.Popcnt; dst; src = Reg src; set_flags = false } ]
  | (("uaddlv" | "uaddlv.8b" | "uaddlv.16b"), [ OpReg dst; OpReg src ]) ->
      Some [ Ir.Mov { dst = Reg dst; src = Reg src } ]

  | _ -> None
