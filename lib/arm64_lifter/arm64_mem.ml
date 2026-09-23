open Vm_ir
open Arm64_types
open Arm64_common

let lift (mnemonic : string) (ops : raw_op list) : Ir.instr list option =
  match (mnemonic, ops) with
  (* Memory Load with Pre/Post-Indexed Writeback *)
  | (("ldr" | "ldrb" | "ldrh" | "ldur" | "ldurb" | "ldrsb" | "ldrsh" | "ldrsw" | "ldursb" | "ldursh" | "ldursw"), [ OpReg dst; OpMem m ]) ->
      let is_signed =
        match mnemonic with
        | "ldrsb" | "ldrsh" | "ldrsw" | "ldursb" | "ldursh" | "ldursw" -> true
        | _ -> false
      in
      let scratch =
        if Register.to_string dst = Register.to_string Register.vtmp0 then Register.vtmp1
        else Register.vtmp0
      in
      let (m, addr_prep) = lower_mem_operand ~scratch_reg:scratch m in
      (match m.wb with
      | WbNone ->
          Some (addr_prep @ [ Ir.Mov { dst = Reg dst; src = raw_to_ir_operand ~is_signed (OpMem m) } ])
      | WbPre ->
          (match m.base with
          | Some base_reg ->
              let effective_mem = { m with disp = 0L; wb = WbNone } in
              Some (addr_prep @ [
                Ir.Alu { op = Add; dst = base_reg; src1 = Reg base_reg; src2 = Imm m.disp; set_flags = false };
                Ir.Mov { dst = Reg dst; src = raw_to_ir_operand ~is_signed (OpMem effective_mem) };
              ])
          | None ->
              Some (addr_prep @ [ Ir.Mov { dst = Reg dst; src = raw_to_ir_operand ~is_signed (OpMem m) } ]))
      | WbPost post_imm ->
          (match m.base with
          | Some base_reg ->
              let effective_mem = { m with disp = 0L; wb = WbNone } in
              Some (addr_prep @ [
                Ir.Mov { dst = Reg dst; src = raw_to_ir_operand ~is_signed (OpMem effective_mem) };
                Ir.Alu { op = Add; dst = base_reg; src1 = Reg base_reg; src2 = Imm post_imm; set_flags = false };
              ])
          | None ->
              Some (addr_prep @ [ Ir.Mov { dst = Reg dst; src = raw_to_ir_operand ~is_signed (OpMem m) } ]))
      )

  (* Memory Store with Pre/Post-Indexed Writeback *)
  | (("str" | "strb" | "strh" | "stur" | "sturb"), [ (OpReg _ | OpImm _) as src; OpMem m ]) ->
      let scratch =
        match src with
        | OpReg r when Register.to_string r = Register.to_string Register.vtmp0 -> Register.vtmp1
        | _ -> Register.vtmp0
      in
      let (m, addr_prep) = lower_mem_operand ~scratch_reg:scratch m in
      (match m.wb with
      | WbNone ->
          Some (addr_prep @ [ Ir.Mov { dst = raw_to_ir_operand (OpMem m); src = raw_to_ir_operand src } ])
      | WbPre ->
          (match m.base with
          | Some base_reg ->
              let effective_mem = { m with disp = 0L; wb = WbNone } in
              Some (addr_prep @ [
                Ir.Alu { op = Add; dst = base_reg; src1 = Reg base_reg; src2 = Imm m.disp; set_flags = false };
                Ir.Mov { dst = raw_to_ir_operand (OpMem effective_mem); src = raw_to_ir_operand src };
              ])
          | None ->
              Some (addr_prep @ [ Ir.Mov { dst = raw_to_ir_operand (OpMem m); src = raw_to_ir_operand src } ]))
      | WbPost post_imm ->
          (match m.base with
          | Some base_reg ->
              let effective_mem = { m with disp = 0L; wb = WbNone } in
              Some (addr_prep @ [
                Ir.Mov { dst = raw_to_ir_operand (OpMem effective_mem); src = raw_to_ir_operand src };
                Ir.Alu { op = Add; dst = base_reg; src1 = Reg base_reg; src2 = Imm post_imm; set_flags = false };
              ])
          | None ->
              Some (addr_prep @ [ Ir.Mov { dst = raw_to_ir_operand (OpMem m); src = raw_to_ir_operand src } ]))
      )

  (* Pair Store (stp) with Pre/Post-Indexed Writeback *)
  | ("stp", [ OpReg r1; OpReg r2; OpMem m ]) ->
      let stride = Int64.of_int (Register.width_to_bytes (Register.get_width r1)) in
      let w = Register.get_width r1 in
      (match m.wb with
      | WbPre ->
          (match m.base with
          | Some base_reg ->
              let m1 = { base = Some base_reg; index = None; disp = 0L; width = w; wb = WbNone } in
              let m2 = { base = Some base_reg; index = None; disp = stride; width = w; wb = WbNone } in
              Some [
                Ir.Alu { op = Add; dst = base_reg; src1 = Reg base_reg; src2 = Imm m.disp; set_flags = false };
                Ir.Mov { dst = raw_to_ir_operand (OpMem m1); src = Reg r1 };
                Ir.Mov { dst = raw_to_ir_operand (OpMem m2); src = Reg r2 };
              ]
          | None ->
              let m1 = { m with width = w } in
              let m2 = { m with disp = Int64.add m.disp stride; width = w } in
              Some [
                Ir.Mov { dst = raw_to_ir_operand (OpMem m1); src = Reg r1 };
                Ir.Mov { dst = raw_to_ir_operand (OpMem m2); src = Reg r2 };
              ])
      | WbPost post_imm ->
          (match m.base with
          | Some base_reg ->
              let m1 = { base = Some base_reg; index = None; disp = 0L; width = w; wb = WbNone } in
              let m2 = { base = Some base_reg; index = None; disp = stride; width = w; wb = WbNone } in
              Some [
                Ir.Mov { dst = raw_to_ir_operand (OpMem m1); src = Reg r1 };
                Ir.Mov { dst = raw_to_ir_operand (OpMem m2); src = Reg r2 };
                Ir.Alu { op = Add; dst = base_reg; src1 = Reg base_reg; src2 = Imm post_imm; set_flags = false };
              ]
          | None ->
              let m1 = { m with width = w } in
              let m2 = { m with disp = Int64.add m.disp stride; width = w } in
              Some [
                Ir.Mov { dst = raw_to_ir_operand (OpMem m1); src = Reg r1 };
                Ir.Mov { dst = raw_to_ir_operand (OpMem m2); src = Reg r2 };
              ])
      | WbNone ->
          let m1 = { m with width = w } in
          let m2 = { m with disp = Int64.add m.disp stride; width = w } in
          Some [
            Ir.Mov { dst = raw_to_ir_operand (OpMem m1); src = Reg r1 };
            Ir.Mov { dst = raw_to_ir_operand (OpMem m2); src = Reg r2 };
          ])
  | ("stp", (OpReg r1 :: OpReg r2 :: _)) ->
      Some [ Ir.Push (Reg r1); Ir.Push (Reg r2) ]

  (* Pair Load (ldp) with Pre/Post-Indexed Writeback *)
  | ("ldp", [ OpReg r1; OpReg r2; OpMem m ]) ->
      let stride = Int64.of_int (Register.width_to_bytes (Register.get_width r1)) in
      let w = Register.get_width r1 in
      (match m.wb with
      | WbPre ->
          (match m.base with
          | Some base_reg ->
              let m1 = { base = Some base_reg; index = None; disp = 0L; width = w; wb = WbNone } in
              let m2 = { base = Some base_reg; index = None; disp = stride; width = w; wb = WbNone } in
              Some [
                Ir.Alu { op = Add; dst = base_reg; src1 = Reg base_reg; src2 = Imm m.disp; set_flags = false };
                Ir.Mov { dst = Reg r1; src = raw_to_ir_operand (OpMem m1) };
                Ir.Mov { dst = Reg r2; src = raw_to_ir_operand (OpMem m2) };
              ]
          | None ->
              let m1 = { m with width = w } in
              let m2 = { m with disp = Int64.add m.disp stride; width = w } in
              Some [
                Ir.Mov { dst = Reg r1; src = raw_to_ir_operand (OpMem m1) };
                Ir.Mov { dst = Reg r2; src = raw_to_ir_operand (OpMem m2) };
              ])
      | WbPost post_imm ->
          (match m.base with
          | Some base_reg ->
              let m1 = { base = Some base_reg; index = None; disp = 0L; width = w; wb = WbNone } in
              let m2 = { base = Some base_reg; index = None; disp = stride; width = w; wb = WbNone } in
              Some [
                Ir.Mov { dst = Reg r1; src = raw_to_ir_operand (OpMem m1) };
                Ir.Mov { dst = Reg r2; src = raw_to_ir_operand (OpMem m2) };
                Ir.Alu { op = Add; dst = base_reg; src1 = Reg base_reg; src2 = Imm post_imm; set_flags = false };
              ]
          | None ->
              let m1 = { m with width = w } in
              let m2 = { m with disp = Int64.add m.disp stride; width = w } in
              Some [
                Ir.Mov { dst = Reg r1; src = raw_to_ir_operand (OpMem m1) };
                Ir.Mov { dst = Reg r2; src = raw_to_ir_operand (OpMem m2) };
              ])
      | WbNone ->
          let m1 = { m with width = w } in
          let m2 = { m with disp = Int64.add m.disp stride; width = w } in
          Some [
            Ir.Mov { dst = Reg r1; src = raw_to_ir_operand (OpMem m1) };
            Ir.Mov { dst = Reg r2; src = raw_to_ir_operand (OpMem m2) };
          ])
  | ("ldp", (OpReg r1 :: OpReg r2 :: _)) ->
      Some [ Ir.Pop (Reg r2); Ir.Pop (Reg r1) ]

  (* ARMv8.1-A Atomics & Memory Ordering *)
  | (("ldxr" | "ldaxr"), [ OpReg dst; OpMem m ]) ->
      let base = match m.base with Some b -> b | None -> Register.rsp in
      Some [ Ir.Atomic_mem { op = AtLoad; dst; addr = base; src = dst; imm = m.disp } ]
  | (("stxr" | "stlxr"), [ OpReg res; OpReg src; OpMem m ]) ->
      let base = match m.base with Some b -> b | None -> Register.rsp in
      Some [ Ir.Atomic_mem { op = AtStore; dst = res; addr = base; src; imm = m.disp } ]
  | (("cas" | "casa" | "casl" | "casal"), [ OpReg expected; OpReg desired; OpMem m ]) ->
      let base = match m.base with Some b -> b | None -> Register.rsp in
      Some [ Ir.Atomic_mem { op = AtCas; dst = desired; addr = base; src = expected; imm = m.disp } ]
  | (("ldadd" | "ldadda" | "ldaddl" | "ldaddal"), [ OpReg val_reg; OpReg res_reg; OpMem m ]) ->
      let base = match m.base with Some b -> b | None -> Register.rsp in
      Some [ Ir.Atomic_mem { op = AtAdd; dst = res_reg; addr = base; src = val_reg; imm = m.disp } ]
  | (("swp" | "swpa" | "swpl" | "swpal"), [ OpReg val_reg; OpReg res_reg; OpMem m ]) ->
      let base = match m.base with Some b -> b | None -> Register.rsp in
      Some [ Ir.Atomic_mem { op = AtSwp; dst = res_reg; addr = base; src = val_reg; imm = m.disp } ]
  | (("dmb" | "dsb" | "isb"), _) ->
      Some [ Ir.Nop ]

  | _ -> None
