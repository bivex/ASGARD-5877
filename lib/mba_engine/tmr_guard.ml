(* ASGARD-5877: Triple Modular Redundancy (TMR) Majority Voting & Anti-Patching *)

open Vm_ir
open Mba

let evaluate_tmr_majority (a : int64) (b : int64) (c : int64) : int64 =
  let ab = Int64.logand a b in
  let bc = Int64.logand b c in
  let ac = Int64.logand a c in
  Int64.logor (Int64.logor ab bc) ac

let emit_tmr_majority
    ~(r1 : Register.t)
    ~(r2 : Register.t)
    ~(r3 : Register.t)
    ~(dst : Register.t)
    ~(scratch1 : Register.t)
    ~(scratch2 : Register.t) : Ir.instr list =
  [
    (* scratch1 = r1 & r2 *)
    Ir.Alu { op = Ir.And; dst = scratch1; src1 = Ir.Reg r1; src2 = Ir.Reg r2; set_flags = false };
    (* scratch2 = r2 & r3 *)
    Ir.Alu { op = Ir.And; dst = scratch2; src1 = Ir.Reg r2; src2 = Ir.Reg r3; set_flags = false };
    (* scratch1 = (r1 & r2) | (r2 & r3) *)
    Ir.Alu { op = Ir.Or; dst = scratch1; src1 = Ir.Reg scratch1; src2 = Ir.Reg scratch2; set_flags = false };
    (* scratch2 = r1 & r3 *)
    Ir.Alu { op = Ir.And; dst = scratch2; src1 = Ir.Reg r1; src2 = Ir.Reg r3; set_flags = false };
    (* dst = ((r1 & r2) | (r2 & r3)) | (r1 & r3) *)
    Ir.Alu { op = Ir.Or; dst = dst; src1 = Ir.Reg scratch1; src2 = Ir.Reg scratch2; set_flags = false };
  ]

let emit_tmr_evaluation
    ~(e1 : expr)
    ~(e2 : expr)
    ~(e3 : expr)
    ~(env : (string * Ir.operand) list)
    ~(dst : Register.t)
    ~(r1 : Register.t)
    ~(r2 : Register.t)
    ~(r3 : Register.t)
    ~(scratch1 : Register.t)
    ~(scratch2 : Register.t) : Ir.instr list =
  let instrs1 = Mba.lower_to_ir ~dst:r1 ~env e1 in
  let instrs2 = Mba.lower_to_ir ~dst:r2 ~env e2 in
  let instrs3 = Mba.lower_to_ir ~dst:r3 ~env e3 in
  let vote_instrs = emit_tmr_majority ~r1 ~r2 ~r3 ~dst ~scratch1 ~scratch2 in
  instrs1 @ instrs2 @ instrs3 @ vote_instrs
