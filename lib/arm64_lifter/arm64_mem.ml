open Vm_ir
open Arm64_types
open Arm64_common

let lift (mnemonic : string) (ops : raw_op list) : Ir.instr list option =
  match (mnemonic, ops) with
  (* Memory Load with Pre/Post-Indexed Writeback *)
  | (("ldr" | "ldrb" | "ldrh" | "ldur" | "ldurb" | "ldrsb" | "ldrsh" | "ldrsw" | "ldursb" | "ldursh" | "ldursw"
     | "ldar" | "ldarb" | "ldarh" | "ldapr" | "ldaprb" | "ldaprh"
     | "ldtr" | "ldtrb" | "ldtrh" | "ldtrsw"), [ OpReg dst; OpMem m ]) ->
      let is_signed =
        match mnemonic with
        | "ldrsb" | "ldrsh" | "ldrsw" | "ldursb" | "ldursh" | "ldursw" | "ldtrsw" -> true
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
  | (("str" | "strb" | "strh" | "stur" | "sturb" | "stlr" | "stlrb" | "stlrh"
     | "sttr" | "sttrb" | "sttrh"), [ (OpReg _ | OpImm _) as src; OpMem m ]) ->
      let scratch =
        match src with
        | OpReg r when Register.to_string r = Register.to_string Register.vtmp0 -> Register.vtmp1
        | _ -> Register.vtmp0
      in
      let (m, addr_prep) = lower_mem_operand ~scratch_reg:scratch m in
      let (src_ir, src_prep) =
        match src with
        | OpImm imm ->
            (Ir.Reg scratch, [ Ir.Mov { dst = Reg scratch; src = Imm imm } ])
        | _ ->
            (raw_to_ir_operand src, [])
      in
      (match m.wb with
      | WbNone ->
          Some (addr_prep @ src_prep @ [ Ir.Mov { dst = raw_to_ir_operand (OpMem m); src = src_ir } ])
      | WbPre ->
          (match m.base with
          | Some base_reg ->
              let effective_mem = { m with disp = 0L; wb = WbNone } in
              Some (addr_prep @ src_prep @ [
                Ir.Alu { op = Add; dst = base_reg; src1 = Reg base_reg; src2 = Imm m.disp; set_flags = false };
                Ir.Mov { dst = raw_to_ir_operand (OpMem effective_mem); src = src_ir };
              ])
          | None ->
              Some (addr_prep @ src_prep @ [ Ir.Mov { dst = raw_to_ir_operand (OpMem m); src = src_ir } ]))
      | WbPost post_imm ->
          (match m.base with
          | Some base_reg ->
              let effective_mem = { m with disp = 0L; wb = WbNone } in
              Some (addr_prep @ src_prep @ [
                Ir.Mov { dst = raw_to_ir_operand (OpMem effective_mem); src = src_ir };
                Ir.Alu { op = Add; dst = base_reg; src1 = Reg base_reg; src2 = Imm post_imm; set_flags = false };
              ])
          | None ->
              Some (addr_prep @ src_prep @ [ Ir.Mov { dst = raw_to_ir_operand (OpMem m); src = src_ir } ]))
      )

  (* Pair Store (stp, stnp) with Pre/Post-Indexed Writeback *)
  | (("stp" | "stnp"), [ OpReg r1; OpReg r2; OpMem m ]) ->
      let stride = Int64.of_int (Register.width_to_bytes (Register.get_width r1)) in
      let w = Register.get_width r1 in
      let s1 = raw_to_ir_operand (OpReg r1) in
      let s2 = raw_to_ir_operand (OpReg r2) in
      (match m.wb with
      | WbPre ->
          (match m.base with
          | Some base_reg ->
              let m1 = { base = Some base_reg; index = None; disp = 0L; width = w; wb = WbNone } in
              let m2 = { base = Some base_reg; index = None; disp = stride; width = w; wb = WbNone } in
              Some [
                Ir.Alu { op = Add; dst = base_reg; src1 = Reg base_reg; src2 = Imm m.disp; set_flags = false };
                Ir.Mov { dst = raw_to_ir_operand (OpMem m1); src = s1 };
                Ir.Mov { dst = raw_to_ir_operand (OpMem m2); src = s2 };
              ]
          | None ->
              let m1 = { m with width = w } in
              let m2 = { m with disp = Int64.add m.disp stride; width = w } in
              Some [
                Ir.Mov { dst = raw_to_ir_operand (OpMem m1); src = s1 };
                Ir.Mov { dst = raw_to_ir_operand (OpMem m2); src = s2 };
              ])
      | WbPost post_imm ->
          (match m.base with
          | Some base_reg ->
              let m1 = { base = Some base_reg; index = None; disp = 0L; width = w; wb = WbNone } in
              let m2 = { base = Some base_reg; index = None; disp = stride; width = w; wb = WbNone } in
              Some [
                Ir.Mov { dst = raw_to_ir_operand (OpMem m1); src = s1 };
                Ir.Mov { dst = raw_to_ir_operand (OpMem m2); src = s2 };
                Ir.Alu { op = Add; dst = base_reg; src1 = Reg base_reg; src2 = Imm post_imm; set_flags = false };
              ]
          | None ->
              let m1 = { m with width = w } in
              let m2 = { m with disp = Int64.add m.disp stride; width = w } in
              Some [
                Ir.Mov { dst = raw_to_ir_operand (OpMem m1); src = s1 };
                Ir.Mov { dst = raw_to_ir_operand (OpMem m2); src = s2 };
              ])
      | WbNone ->
          let m1 = { m with width = w } in
          let m2 = { m with disp = Int64.add m.disp stride; width = w } in
          Some [
            Ir.Mov { dst = raw_to_ir_operand (OpMem m1); src = s1 };
            Ir.Mov { dst = raw_to_ir_operand (OpMem m2); src = s2 };
          ])
  | (("stp" | "stnp"), (OpReg r1 :: OpReg r2 :: _)) ->
      Some [ Ir.Push (Reg r1); Ir.Push (Reg r2) ]

  (* Pair Load (ldp, ldnp) with Pre/Post-Indexed Writeback *)
  | (("ldp" | "ldnp"), [ OpReg r1; OpReg r2; OpMem m ]) ->
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
  | (("ldp" | "ldnp"), (OpReg r1 :: OpReg r2 :: _)) ->
      Some [ Ir.Pop (Reg r2); Ir.Pop (Reg r1) ]

  (* ARMv8.1-A Atomics & Memory Ordering *)
  | (("ldxr" | "ldaxr" | "ldxrb" | "ldaxrb" | "ldxrh" | "ldaxrh"), [ OpReg dst; OpMem m ]) ->
      let base = match m.base with Some b -> b | None -> Register.rsp in
      Some [ Ir.Atomic_mem { op = AtLoad; dst; addr = base; src = dst; imm = m.disp } ]
  | (("stxr" | "stlxr" | "stxrb" | "stlxrb" | "stxrh" | "stlxrh"), [ OpReg res; OpReg src; OpMem m ]) ->
      let base = match m.base with Some b -> b | None -> Register.rsp in
      Some [
        Ir.Atomic_mem { op = AtStore; dst = res; addr = base; src; imm = m.disp };
        Ir.Mov { dst = Reg res; src = Imm 0L };
      ]
  | (("cas" | "casa" | "casl" | "casal"
     | "casb" | "casab" | "caslb" | "casalb"
     | "cash" | "casah" | "caslh" | "casalh"), [ OpReg expected; OpReg desired; OpMem m ]) ->
      let base = match m.base with Some b -> b | None -> Register.rsp in
      Some [ Ir.Atomic_mem { op = AtCas; dst = desired; addr = base; src = expected; imm = m.disp } ]
  | (("ldadd" | "ldadda" | "ldaddl" | "ldaddal"
     | "ldaddb" | "ldaddab" | "ldaddlb" | "ldaddalb"
     | "ldaddh" | "ldaddah" | "ldaddlh" | "ldaddalh"), [ OpReg val_reg; OpReg res_reg; OpMem m ]) ->
      let base = match m.base with Some b -> b | None -> Register.rsp in
      Some [ Ir.Atomic_mem { op = AtAdd; dst = res_reg; addr = base; src = val_reg; imm = m.disp } ]
  | (("swp" | "swpa" | "swpl" | "swpal"
     | "swpb" | "swpab" | "swplb" | "swpalb"
     | "swph" | "swpah" | "swplh" | "swpalh"), [ OpReg val_reg; OpReg res_reg; OpMem m ]) ->
      let base = match m.base with Some b -> b | None -> Register.rsp in
      Some [ Ir.Atomic_mem { op = AtSwp; dst = res_reg; addr = base; src = val_reg; imm = m.disp } ]

  | (("ldclr" | "ldclra" | "ldclrl" | "ldclral"
     | "ldclrb" | "ldclrab" | "ldclrlb" | "ldclralb"
     | "ldclrh" | "ldclrah" | "ldclrlh" | "ldclralh"), [ OpReg val_reg; OpReg res_reg; OpMem m ]) ->
      let mem_ref = { Ir.base = m.base; index = m.index; disp = m.disp; width = m.width; is_signed = false; segment = None } in
      let scratch = Register.with_width Register.vtmp0 m.width in
      let inv_s = Register.with_width Register.vtmp1 m.width in
      Some [
        Ir.Mov { dst = Reg res_reg; src = Mem mem_ref };
        Ir.Unary { op = Not; dst = inv_s; src = Reg val_reg; set_flags = false };
        Ir.Mov { dst = Reg scratch; src = Reg res_reg };
        Ir.Alu { op = And; dst = scratch; src1 = Reg scratch; src2 = Reg inv_s; set_flags = false };
        Ir.Mov { dst = Mem mem_ref; src = Reg scratch };
      ]

  | (("ldset" | "ldseta" | "ldsetl" | "ldsetal"
     | "ldsetb" | "ldsetab" | "ldsetlb" | "ldsetalb"
     | "ldseth" | "ldsetah" | "ldsetlh" | "ldsetalh"), [ OpReg val_reg; OpReg res_reg; OpMem m ]) ->
      let mem_ref = { Ir.base = m.base; index = m.index; disp = m.disp; width = m.width; is_signed = false; segment = None } in
      let scratch = Register.with_width Register.vtmp0 m.width in
      Some [
        Ir.Mov { dst = Reg res_reg; src = Mem mem_ref };
        Ir.Mov { dst = Reg scratch; src = Reg res_reg };
        Ir.Alu { op = Or; dst = scratch; src1 = Reg scratch; src2 = Reg val_reg; set_flags = false };
        Ir.Mov { dst = Mem mem_ref; src = Reg scratch };
      ]

  | (("ldeor" | "ldeora" | "ldeorl" | "ldeoral"
     | "ldeorb" | "ldeorab" | "ldeorlb" | "ldeoralb"
     | "ldeorh" | "ldeorah" | "ldeorlh" | "ldeoralh"), [ OpReg val_reg; OpReg res_reg; OpMem m ]) ->
      let mem_ref = { Ir.base = m.base; index = m.index; disp = m.disp; width = m.width; is_signed = false; segment = None } in
      let scratch = Register.with_width Register.vtmp0 m.width in
      Some [
        Ir.Mov { dst = Reg res_reg; src = Mem mem_ref };
        Ir.Mov { dst = Reg scratch; src = Reg res_reg };
        Ir.Alu { op = Xor; dst = scratch; src1 = Reg scratch; src2 = Reg val_reg; set_flags = false };
        Ir.Mov { dst = Mem mem_ref; src = Reg scratch };
      ]

  (* Store-only LSE variants *)
  | (("stadd" | "stadda" | "staddl" | "staddal"
     | "staddb" | "staddab" | "staddlb" | "staddalb"
     | "staddh" | "staddah" | "staddlh" | "staddalh"), [ OpReg val_reg; OpMem m ]) ->
      let mem_ref = { Ir.base = m.base; index = m.index; disp = m.disp; width = m.width; is_signed = false; segment = None } in
      let scratch = Register.with_width Register.vtmp0 m.width in
      Some [
        Ir.Mov { dst = Reg scratch; src = Mem mem_ref };
        Ir.Alu { op = Add; dst = scratch; src1 = Reg scratch; src2 = Reg val_reg; set_flags = false };
        Ir.Mov { dst = Mem mem_ref; src = Reg scratch };
      ]

  | (("stclr" | "stclra" | "stclrl" | "stclral"
     | "stclrb" | "stclrab" | "stclrlb" | "stclralb"
     | "stclrh" | "stclrah" | "stclrlh" | "stclralh"), [ OpReg val_reg; OpMem m ]) ->
      let mem_ref = { Ir.base = m.base; index = m.index; disp = m.disp; width = m.width; is_signed = false; segment = None } in
      let scratch = Register.with_width Register.vtmp0 m.width in
      let inv_s = Register.with_width Register.vtmp1 m.width in
      Some [
        Ir.Mov { dst = Reg scratch; src = Mem mem_ref };
        Ir.Unary { op = Not; dst = inv_s; src = Reg val_reg; set_flags = false };
        Ir.Alu { op = And; dst = scratch; src1 = Reg scratch; src2 = Reg inv_s; set_flags = false };
        Ir.Mov { dst = Mem mem_ref; src = Reg scratch };
      ]

  | (("stset" | "stseta" | "stsetl" | "stsetal"
     | "stsetb" | "stsetab" | "stsetlb" | "stsetalb"
     | "stseth" | "stsetah" | "stsetlh" | "stsetalh"), [ OpReg val_reg; OpMem m ]) ->
      let mem_ref = { Ir.base = m.base; index = m.index; disp = m.disp; width = m.width; is_signed = false; segment = None } in
      let scratch = Register.with_width Register.vtmp0 m.width in
      Some [
        Ir.Mov { dst = Reg scratch; src = Mem mem_ref };
        Ir.Alu { op = Or; dst = scratch; src1 = Reg scratch; src2 = Reg val_reg; set_flags = false };
        Ir.Mov { dst = Mem mem_ref; src = Reg scratch };
      ]

  | (("steor" | "steora" | "steorl" | "steoral"
     | "steorb" | "steorab" | "steorlb" | "steoralb"
     | "steorh" | "steorah" | "steorlh" | "steoralh"), [ OpReg val_reg; OpMem m ]) ->
      let mem_ref = { Ir.base = m.base; index = m.index; disp = m.disp; width = m.width; is_signed = false; segment = None } in
      let scratch = Register.with_width Register.vtmp0 m.width in
      Some [
        Ir.Mov { dst = Reg scratch; src = Mem mem_ref };
        Ir.Alu { op = Xor; dst = scratch; src1 = Reg scratch; src2 = Reg val_reg; set_flags = false };
        Ir.Mov { dst = Mem mem_ref; src = Reg scratch };
      ]

  | (("dmb" | "dsb" | "isb"), _) ->
      Some [ Ir.Nop ]

  | _ -> None
