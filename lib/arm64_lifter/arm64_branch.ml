open Vm_ir
open Arm64_types
open Flags
open Arm64_common

let lift (mnemonic : string) (ops : raw_op list) : Ir.instr list option =
  match (mnemonic, ops) with
  | ("nop", []) -> Some [ Ir.Nop ]
  | ("ret", _) -> Some [ Ir.Ret ]

  (* Branches & Calls *)
  | ("b", [ target ]) ->
      Some [ Ir.Jmp (target_of_op target) ]
  | ("b.al", [ target ]) ->
      Some [ Ir.Jmp (target_of_op target) ]
  | ("b.nv", _) ->
      Some [ Ir.Nop ]
  | ("b.eq", [ target ]) ->
      Some [ Ir.Jcc { cond = E; target_true = target_of_op target; target_false = TargetImm 0L } ]
  | ("b.ne", [ target ]) ->
      Some [ Ir.Jcc { cond = NE; target_true = target_of_op target; target_false = TargetImm 0L } ]
  | ("b.lt", [ target ]) ->
      Some [ Ir.Jcc { cond = L; target_true = target_of_op target; target_false = TargetImm 0L } ]
  | ("b.le", [ target ]) ->
      Some [ Ir.Jcc { cond = LE; target_true = target_of_op target; target_false = TargetImm 0L } ]
  | ("b.gt", [ target ]) ->
      Some [ Ir.Jcc { cond = G; target_true = target_of_op target; target_false = TargetImm 0L } ]
  | ("b.ge", [ target ]) ->
      Some [ Ir.Jcc { cond = GE; target_true = target_of_op target; target_false = TargetImm 0L } ]
  | ("b.hi", [ target ]) ->
      Some [ Ir.Jcc { cond = A; target_true = target_of_op target; target_false = TargetImm 0L } ]
  | ("b.ls", [ target ]) ->
      Some [ Ir.Jcc { cond = BE; target_true = target_of_op target; target_false = TargetImm 0L } ]
  | (("b.hs" | "b.cs"), [ target ]) ->
      Some [ Ir.Jcc { cond = AE; target_true = target_of_op target; target_false = TargetImm 0L } ]
  | (("b.lo" | "b.cc"), [ target ]) ->
      Some [ Ir.Jcc { cond = B; target_true = target_of_op target; target_false = TargetImm 0L } ]
  | ("b.mi", [ target ]) ->
      Some [ Ir.Jcc { cond = S; target_true = target_of_op target; target_false = TargetImm 0L } ]
  | ("b.pl", [ target ]) ->
      Some [ Ir.Jcc { cond = NS; target_true = target_of_op target; target_false = TargetImm 0L } ]
  | ("b.vs", [ target ]) ->
      Some [ Ir.Jcc { cond = O; target_true = target_of_op target; target_false = TargetImm 0L } ]
  | ("b.vc", [ target ]) ->
      Some [ Ir.Jcc { cond = NO; target_true = target_of_op target; target_false = TargetImm 0L } ]
  | ("cbz", [ OpReg r; target ]) ->
      Some [
        Ir.Cmp { src1 = Reg r; src2 = Imm 0L };
        Ir.Jcc { cond = E; target_true = target_of_op target; target_false = TargetImm 0L };
      ]
  | ("cbnz", [ OpReg r; target ]) ->
      Some [
        Ir.Cmp { src1 = Reg r; src2 = Imm 0L };
        Ir.Jcc { cond = NE; target_true = target_of_op target; target_false = TargetImm 0L };
      ]
  | ("tbz", [ OpReg r; OpImm bit; target ]) ->
      let mask = Int64.shift_left 1L (Int64.to_int (Int64.logand bit 63L)) in
      Some [
        Ir.Test { src1 = Reg r; src2 = Imm mask };
        Ir.Jcc { cond = E; target_true = target_of_op target; target_false = TargetImm 0L };
      ]
  | ("tbnz", [ OpReg r; OpImm bit; target ]) ->
      let mask = Int64.shift_left 1L (Int64.to_int (Int64.logand bit 63L)) in
      Some [
        Ir.Test { src1 = Reg r; src2 = Imm mask };
        Ir.Jcc { cond = NE; target_true = target_of_op target; target_false = TargetImm 0L };
      ]
  | ("bl", [ target ]) ->
      Some [ Ir.Call (target_of_op target) ]
  | ("blr", [ OpReg r ]) ->
      Some [ Ir.Call (TargetReg r) ]
  | ("blr", _) ->
      Some [ Ir.Call (TargetImm 0L) ]
  | ("br", [ OpReg r ]) ->
      Some [ Ir.Jmp (TargetReg r) ]
  | ("br", _) ->
      Some [ Ir.Jmp (TargetImm 0L) ]
  | ("eret", _) ->
      Some [ Ir.Trap "eret" ]

  (* Floating-Point & Scalar FP (SIMD) Instructions *)
  | ("fadd", [ OpReg (Register.Fpr (d, _)); OpReg (Register.Fpr (s1, _)); OpReg (Register.Fpr (s2, _)) ]) ->
      Some [ Ir.Fp_binop { op = Fadd; dst = d; src1 = s1; src2 = s2 } ]
  | ("fsub", [ OpReg (Register.Fpr (d, _)); OpReg (Register.Fpr (s1, _)); OpReg (Register.Fpr (s2, _)) ]) ->
      Some [ Ir.Fp_binop { op = Fsub; dst = d; src1 = s1; src2 = s2 } ]
  | ("fmul", [ OpReg (Register.Fpr (d, _)); OpReg (Register.Fpr (s1, _)); OpReg (Register.Fpr (s2, _)) ]) ->
      Some [ Ir.Fp_binop { op = Fmul; dst = d; src1 = s1; src2 = s2 } ]
  | ("fdiv", [ OpReg (Register.Fpr (d, _)); OpReg (Register.Fpr (s1, _)); OpReg (Register.Fpr (s2, _)) ]) ->
      Some [ Ir.Fp_binop { op = Fdiv; dst = d; src1 = s1; src2 = s2 } ]
  | ("fsqrt", [ OpReg (Register.Fpr (d, _)); OpReg (Register.Fpr (s, _)) ]) ->
      Some [ Ir.Fp_binop { op = Fsqrt; dst = d; src1 = s; src2 = s } ]
  | ("fmadd", [ OpReg (Register.Fpr (d, _)); OpReg (Register.Fpr (n, _)); OpReg (Register.Fpr (m, _)); OpReg (Register.Fpr (a, _)) ]) ->
      Some [
        Ir.Fp_binop { op = Fmul; dst = 31; src1 = n; src2 = m };
        Ir.Fp_binop { op = Fadd; dst = d; src1 = a; src2 = 31 };
      ]
  | ("fmsub", [ OpReg (Register.Fpr (d, _)); OpReg (Register.Fpr (n, _)); OpReg (Register.Fpr (m, _)); OpReg (Register.Fpr (a, _)) ]) ->
      Some [
        Ir.Fp_binop { op = Fmul; dst = 31; src1 = n; src2 = m };
        Ir.Fp_binop { op = Fsub; dst = d; src1 = a; src2 = 31 };
      ]
  | ("fnmadd", [ OpReg (Register.Fpr (d, _)); OpReg (Register.Fpr (n, _)); OpReg (Register.Fpr (m, _)); OpReg (Register.Fpr (a, _)) ]) ->
      Some [
        Ir.Fp_binop { op = Fmul; dst = 31; src1 = n; src2 = m };
        Ir.Fp_binop { op = Fadd; dst = 31; src1 = a; src2 = 31 };
        Ir.Mov { dst = Reg (Register.Fpr (30, Register.B64)); src = Imm 0L };
        Ir.Fp_binop { op = Fsub; dst = d; src1 = 30; src2 = 31 };
      ]
  | ("fnmsub", [ OpReg (Register.Fpr (d, _)); OpReg (Register.Fpr (n, _)); OpReg (Register.Fpr (m, _)); OpReg (Register.Fpr (a, _)) ]) ->
      Some [
        Ir.Fp_binop { op = Fmul; dst = 31; src1 = n; src2 = m };
        Ir.Fp_binop { op = Fsub; dst = d; src1 = 31; src2 = a };
      ]
  | ("fneg", [ OpReg (Register.Fpr (d, _)); OpReg (Register.Fpr (s, _)) ]) ->
      Some [
        Ir.Mov { dst = Reg (Register.Fpr (31, Register.B64)); src = Imm 0L };
        Ir.Fp_binop { op = Fsub; dst = d; src1 = 31; src2 = s };
      ]
  | ("fabs", [ OpReg (Register.Fpr (d, _)); OpReg (Register.Fpr (s, _)) ]) ->
      Some [
        Ir.Mov { dst = Reg Register.vtmp0; src = Reg (Register.Fpr (s, Register.B64)) };
        Ir.Alu { op = Ir.And; dst = Register.vtmp0; src1 = Reg Register.vtmp0; src2 = Imm 0x7fffffffffffffffL; set_flags = false };
        Ir.Mov { dst = Reg (Register.Fpr (d, Register.B64)); src = Reg Register.vtmp0 };
      ]
  | ("fmin", [ OpReg (Register.Fpr (d, dw)); OpReg (Register.Fpr (s1, _)); OpReg (Register.Fpr (s2, _)) ]) ->
      let instrs =
        if d = s2 then
          [
            Ir.Fp_cmp { src1 = s1; src2 = s2 };
            Ir.Cmov { cond = Flags.L; dst = Register.Fpr (d, dw); src = Reg (Register.Fpr (s1, dw)) };
          ]
        else if d = s1 then
          [
            Ir.Fp_cmp { src1 = s1; src2 = s2 };
            Ir.Cmov { cond = Flags.G; dst = Register.Fpr (d, dw); src = Reg (Register.Fpr (s2, dw)) };
          ]
        else
          [
            Ir.Fp_cmp { src1 = s1; src2 = s2 };
            Ir.Mov { dst = Reg (Register.Fpr (d, dw)); src = Reg (Register.Fpr (s2, dw)) };
            Ir.Cmov { cond = Flags.L; dst = Register.Fpr (d, dw); src = Reg (Register.Fpr (s1, dw)) };
          ]
      in
      Some instrs
  | ("fmax", [ OpReg (Register.Fpr (d, dw)); OpReg (Register.Fpr (s1, _)); OpReg (Register.Fpr (s2, _)) ]) ->
      let instrs =
        if d = s2 then
          [
            Ir.Fp_cmp { src1 = s1; src2 = s2 };
            Ir.Cmov { cond = Flags.G; dst = Register.Fpr (d, dw); src = Reg (Register.Fpr (s1, dw)) };
          ]
        else if d = s1 then
          [
            Ir.Fp_cmp { src1 = s1; src2 = s2 };
            Ir.Cmov { cond = Flags.L; dst = Register.Fpr (d, dw); src = Reg (Register.Fpr (s2, dw)) };
          ]
        else
          [
            Ir.Fp_cmp { src1 = s1; src2 = s2 };
            Ir.Mov { dst = Reg (Register.Fpr (d, dw)); src = Reg (Register.Fpr (s2, dw)) };
            Ir.Cmov { cond = Flags.G; dst = Register.Fpr (d, dw); src = Reg (Register.Fpr (s1, dw)) };
          ]
      in
      Some instrs
  | ("fcmp", [ OpReg (Register.Fpr (s1, _)); OpReg (Register.Fpr (s2, _)) ]) ->
      Some [ Ir.Fp_cmp { src1 = s1; src2 = s2 } ]
  | ("fcmp", [ OpReg (Register.Fpr (s1, _)); OpImm 0L ]) ->
      Some [
        Ir.Mov { dst = Reg (Register.Fpr (31, Register.B64)); src = Imm 0L };
        Ir.Fp_cmp { src1 = s1; src2 = 31 };
      ]
  | ("fmov", [ OpReg dst; OpReg src ]) ->
      Some [ Ir.Mov { dst = Reg dst; src = Reg src } ]
  | ("fmov", [ OpReg dst; OpImm imm ]) ->
      Some [ Ir.Mov { dst = Reg dst; src = Imm imm } ]
  | ("fcvtzs", [ OpReg dst; OpReg (Register.Fpr (s, _)) ]) ->
      Some [ Ir.Fp_conv { op = Fcvtzs; dst; src = Register.Fpr (s, Register.B64) } ]
  | ("fcvtzu", [ OpReg dst; OpReg (Register.Fpr (s, _)) ]) ->
      Some [ Ir.Fp_conv { op = Fcvtzu; dst; src = Register.Fpr (s, Register.B64) } ]
  | ("scvtf", [ OpReg (Register.Fpr (d, _)); OpReg src ]) ->
      Some [ Ir.Fp_conv { op = Scvtf; dst = Register.Fpr (d, Register.B64); src } ]
  | ("ucvtf", [ OpReg (Register.Fpr (d, _)); OpReg src ]) ->
      Some [ Ir.Fp_conv { op = Ucvtf; dst = Register.Fpr (d, Register.B64); src } ]
  | ("fcvt", [ OpReg dst; OpReg src ]) ->
      Some [ Ir.Fp_conv { op = Fcvt; dst; src } ]

  | _ -> None
