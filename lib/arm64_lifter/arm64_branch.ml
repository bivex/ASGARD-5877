open Vm_ir
open Arm64_types
open Flags

let lift (mnemonic : string) (ops : raw_op list) : Ir.instr list option =
  match (mnemonic, ops) with
  | ("nop", []) -> Some [ Ir.Nop ]
  | ("ret", _) -> Some [ Ir.Ret ]

  (* Branches & Calls *)
  | ("b", [ OpLabel target ]) ->
      Some [ Ir.Jmp (Label target) ]
  | ("b.eq", [ OpLabel target ]) ->
      Some [ Ir.Jcc { cond = E; target_true = Label target; target_false = TargetImm 0L } ]
  | ("b.ne", [ OpLabel target ]) ->
      Some [ Ir.Jcc { cond = NE; target_true = Label target; target_false = TargetImm 0L } ]
  | ("b.lt", [ OpLabel target ]) ->
      Some [ Ir.Jcc { cond = L; target_true = Label target; target_false = TargetImm 0L } ]
  | ("b.le", [ OpLabel target ]) ->
      Some [ Ir.Jcc { cond = LE; target_true = Label target; target_false = TargetImm 0L } ]
  | ("b.gt", [ OpLabel target ]) ->
      Some [ Ir.Jcc { cond = G; target_true = Label target; target_false = TargetImm 0L } ]
  | ("b.ge", [ OpLabel target ]) ->
      Some [ Ir.Jcc { cond = GE; target_true = Label target; target_false = TargetImm 0L } ]
  | ("b.hi", [ OpLabel target ]) ->
      Some [ Ir.Jcc { cond = A; target_true = Label target; target_false = TargetImm 0L } ]
  | ("b.ls", [ OpLabel target ]) ->
      Some [ Ir.Jcc { cond = BE; target_true = Label target; target_false = TargetImm 0L } ]
  | (("b.hs" | "b.cs"), [ OpLabel target ]) ->
      Some [ Ir.Jcc { cond = AE; target_true = Label target; target_false = TargetImm 0L } ]
  | (("b.lo" | "b.cc"), [ OpLabel target ]) ->
      Some [ Ir.Jcc { cond = B; target_true = Label target; target_false = TargetImm 0L } ]
  | ("b.mi", [ OpLabel target ]) ->
      Some [ Ir.Jcc { cond = S; target_true = Label target; target_false = TargetImm 0L } ]
  | ("b.pl", [ OpLabel target ]) ->
      Some [ Ir.Jcc { cond = NS; target_true = Label target; target_false = TargetImm 0L } ]
  | ("b.vs", [ OpLabel target ]) ->
      Some [ Ir.Jcc { cond = O; target_true = Label target; target_false = TargetImm 0L } ]
  | ("b.vc", [ OpLabel target ]) ->
      Some [ Ir.Jcc { cond = NO; target_true = Label target; target_false = TargetImm 0L } ]
  | ("cbz", [ OpReg r; OpLabel target ]) ->
      Some [
        Ir.Cmp { src1 = Reg r; src2 = Imm 0L };
        Ir.Jcc { cond = E; target_true = Label target; target_false = TargetImm 0L };
      ]
  | ("cbnz", [ OpReg r; OpLabel target ]) ->
      Some [
        Ir.Cmp { src1 = Reg r; src2 = Imm 0L };
        Ir.Jcc { cond = NE; target_true = Label target; target_false = TargetImm 0L };
      ]
  | ("bl", [ OpLabel target ]) ->
      Some [ Ir.Call (Label target) ]
  | ("blr", _) ->
      Some [ Ir.Call (TargetImm 0L) ]
  | ("br", _) ->
      Some [ Ir.Jmp (TargetImm 0L) ]

  (* Floating-Point & Scalar FP (SIMD) Instructions *)
  | ("fadd", [ OpReg (Register.Fpr (d, _)); OpReg (Register.Fpr (s1, _)); OpReg (Register.Fpr (s2, _)) ]) ->
      Some [ Ir.Fp_binop { op = Fadd; dst = d; src1 = s1; src2 = s2 } ]
  | ("fsub", [ OpReg (Register.Fpr (d, _)); OpReg (Register.Fpr (s1, _)); OpReg (Register.Fpr (s2, _)) ]) ->
      Some [ Ir.Fp_binop { op = Fsub; dst = d; src1 = s1; src2 = s2 } ]
  | ("fmul", [ OpReg (Register.Fpr (d, _)); OpReg (Register.Fpr (s1, _)); OpReg (Register.Fpr (s2, _)) ]) ->
      Some [ Ir.Fp_binop { op = Fmul; dst = d; src1 = s1; src2 = s2 } ]
  | ("fdiv", [ OpReg (Register.Fpr (d, _)); OpReg (Register.Fpr (s1, _)); OpReg (Register.Fpr (s2, _)) ]) ->
      Some [ Ir.Fp_binop { op = Fdiv; dst = d; src1 = s1; src2 = s2 } ]
  | ("fcmp", [ OpReg (Register.Fpr (s1, _)); OpReg (Register.Fpr (s2, _)) ]) ->
      Some [ Ir.Fp_cmp { src1 = s1; src2 = s2 } ]
  | ("fmov", [ OpReg (Register.Fpr (d, _)); OpReg (Register.Fpr (s, _)) ]) ->
      Some [ Ir.Fp_binop { op = Fadd; dst = d; src1 = s; src2 = 31 } ]
  | ("fmov", [ OpReg (Register.Fpr (d, _)); OpImm imm ]) ->
      Some [ Ir.Mov { dst = Reg (Register.Fpr (d, Register.B64)); src = Imm imm } ]
  | ("fcvtzs", [ OpReg dst; OpReg (Register.Fpr (s, _)) ]) ->
      Some [ Ir.Fp_conv { op = Fcvtzs; dst; src = Register.Fpr (s, Register.B64) } ]
  | ("scvtf", [ OpReg (Register.Fpr (d, _)); OpReg src ]) ->
      Some [ Ir.Fp_conv { op = Scvtf; dst = Register.Fpr (d, Register.B64); src } ]

  | _ -> None
