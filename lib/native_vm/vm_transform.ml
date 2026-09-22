open Vm_ir

let reg_to_index = function
  | Register.Gpr (g, _) -> Register.gpr_index g
  | Register.Vreg (Register.VTMP0, _) -> 16
  | Register.Vreg (Register.VTMP1, _) -> 17
  | Register.Vreg (Register.VTMP2, _) -> 18
  | Register.Vreg (Register.VTMP3, _) -> 19
  | Register.Vreg (Register.VIP, _)   -> 20
  | Register.Vreg (Register.VSP, _)   -> 21
  | Register.Vreg (Register.VKEY, _)  -> 22

let cond_to_code = function
  | Flags.E -> 0 | Flags.NE -> 1 | Flags.B -> 2 | Flags.AE -> 3
  | Flags.BE -> 4 | Flags.A -> 5 | Flags.S -> 6 | Flags.NS -> 7
  | Flags.L -> 8 | Flags.GE -> 9 | Flags.LE -> 10 | Flags.G -> 11
  | Flags.O -> 12 | Flags.NO -> 13 | Flags.P -> 14 | Flags.NP -> 15
  | Flags.ALWAYS -> 0

type raw_op_kind =
  | OP_NOP
  | OP_MOV_RR
  | OP_MOV_RI
  | OP_MOV_HIGH
  | OP_ADD_RR
  | OP_ADD_RI
  | OP_SUB_RR
  | OP_SUB_RI
  | OP_IMUL_RR
  | OP_IMUL_RI
  | OP_XOR_RR
  | OP_XOR_RI
  | OP_AND_RR
  | OP_AND_RI
  | OP_OR_RR
  | OP_OR_RI
  | OP_ROL_RI
  | OP_ROR_RI
  | OP_SHL_RI
  | OP_SHR_RI
  | OP_CMP_RR
  | OP_CMP_RI
  | OP_PUSH_R
  | OP_POP_R
  | OP_JMP
  | OP_JCC
  | OP_CMOV
  | OP_SETCC
  | OP_CALL
  | OP_RET
  | OP_EXIT
  | OP_FUSED_MOV_ADD_RRI
  | OP_FUSED_ADD_IMUL_RRI
  | OP_FUSED_ADD_XOR_RRI
  | OP_FUSED_SUB_XOR_RRI
  | OP_FUSED_XOR_ADD_RRI
  | OP_FUSED_CMP_CMOV
  | OP_BRIDGE_TO_FLOW
  | OP_BRIDGE_TO_MATH
  | OP_VADD_VV
  | OP_VSUB_VV
  | OP_VMUL_VV
  | OP_VXOR_VV
  | OP_CALL_EXTERN
  | OP_LOAD_64
  | OP_LOAD_32
  | OP_LOAD_8
  | OP_STORE_64
  | OP_STORE_32
  | OP_STORE_8

let all_op_kinds = [
  OP_NOP; OP_MOV_RR; OP_MOV_RI; OP_MOV_HIGH; OP_ADD_RR; OP_ADD_RI;
  OP_SUB_RR; OP_SUB_RI; OP_IMUL_RR; OP_IMUL_RI; OP_XOR_RR; OP_XOR_RI;
  OP_AND_RR; OP_AND_RI; OP_OR_RR; OP_OR_RI; OP_ROL_RI; OP_ROR_RI; OP_SHL_RI; OP_SHR_RI;
  OP_CMP_RR; OP_CMP_RI; OP_PUSH_R;
  OP_POP_R; OP_JMP; OP_JCC; OP_CMOV; OP_SETCC; OP_CALL; OP_RET; OP_EXIT;
  OP_FUSED_MOV_ADD_RRI; OP_FUSED_ADD_IMUL_RRI; OP_FUSED_ADD_XOR_RRI;
  OP_FUSED_SUB_XOR_RRI; OP_FUSED_XOR_ADD_RRI; OP_FUSED_CMP_CMOV;
  OP_BRIDGE_TO_FLOW; OP_BRIDGE_TO_MATH;
  OP_VADD_VV; OP_VSUB_VV; OP_VMUL_VV; OP_VXOR_VV;
  OP_CALL_EXTERN; OP_LOAD_64; OP_LOAD_32; OP_LOAD_8;
  OP_STORE_64; OP_STORE_32; OP_STORE_8;
]

let op_kind_to_handler_name = function
  | OP_NOP -> "H_NOP"
  | OP_MOV_RR -> "H_MOV_RR"
  | OP_MOV_RI -> "H_MOV_RI"
  | OP_MOV_HIGH -> "H_MOV_HIGH"
  | OP_ADD_RR -> "H_ADD_RR"
  | OP_ADD_RI -> "H_ADD_RI"
  | OP_SUB_RR -> "H_SUB_RR"
  | OP_SUB_RI -> "H_SUB_RI"
  | OP_IMUL_RR -> "H_IMUL_RR"
  | OP_IMUL_RI -> "H_IMUL_RI"
  | OP_XOR_RR -> "H_XOR_RR"
  | OP_XOR_RI -> "H_XOR_RI"
  | OP_AND_RR -> "H_AND_RR"
  | OP_AND_RI -> "H_AND_RI"
  | OP_OR_RR -> "H_OR_RR"
  | OP_OR_RI -> "H_OR_RI"
  | OP_ROL_RI -> "H_ROL_RI"
  | OP_ROR_RI -> "H_ROR_RI"
  | OP_SHL_RI -> "H_SHL_RI"
  | OP_SHR_RI -> "H_SHR_RI"
  | OP_CMP_RR -> "H_CMP_RR"
  | OP_CMP_RI -> "H_CMP_RI"
  | OP_PUSH_R -> "H_PUSH_R"
  | OP_POP_R -> "H_POP_R"
  | OP_JMP -> "H_JMP"
  | OP_JCC -> "H_JCC"
  | OP_CMOV -> "H_CMOV"
  | OP_SETCC -> "H_SETCC"
  | OP_CALL -> "H_CALL"
  | OP_RET -> "H_RET"
  | OP_EXIT -> "H_EXIT"
  | OP_FUSED_MOV_ADD_RRI -> "H_FUSED_MOV_ADD_RRI"
  | OP_FUSED_ADD_IMUL_RRI -> "H_FUSED_ADD_IMUL_RRI"
  | OP_FUSED_ADD_XOR_RRI -> "H_FUSED_ADD_XOR_RRI"
  | OP_FUSED_SUB_XOR_RRI -> "H_FUSED_SUB_XOR_RRI"
  | OP_FUSED_XOR_ADD_RRI -> "H_FUSED_XOR_ADD_RRI"
  | OP_FUSED_CMP_CMOV -> "H_FUSED_CMP_CMOV"
  | OP_BRIDGE_TO_FLOW -> "H_BRIDGE_TO_FLOW"
  | OP_BRIDGE_TO_MATH -> "H_BRIDGE_TO_MATH"
  | OP_VADD_VV -> "H_VADD_VV"
  | OP_VSUB_VV -> "H_VSUB_VV"
  | OP_VMUL_VV -> "H_VMUL_VV"
  | OP_VXOR_VV -> "H_VXOR_VV"
  | OP_CALL_EXTERN -> "H_CALL_EXTERN"
  | OP_LOAD_64 -> "H_LOAD_64"
  | OP_LOAD_32 -> "H_LOAD_32"
  | OP_LOAD_8 -> "H_LOAD_8"
  | OP_STORE_64 -> "H_STORE_64"
  | OP_STORE_32 -> "H_STORE_32"
  | OP_STORE_8 -> "H_STORE_8"

type fused_op =
  | Raw of Ir.instr
  | Fused_Mov_Add of { dst : Register.t; src : Register.t; imm : int64 }
  | Fused_Add_Imul of { dst : Register.t; src : Register.t; imm : int64 }
  | Fused_Add_Xor of { dst : Register.t; src : Register.t; imm : int64 }
  | Fused_Sub_Xor of { dst : Register.t; src : Register.t; imm : int64 }
  | Fused_Xor_Add of { dst : Register.t; src : Register.t; imm : int64 }
  | Fused_Cmp_Cmov of { cmp_dst : Register.t; cmp_imm : int64; cond : Flags.condition; cmov_dst : Register.t; cmov_src : Register.t }

let extract_real_regs instrs =
  let set = Hashtbl.create 8 in
  List.iter
    (fun (i : Ir.instr) ->
      match i with
      | Ir.Mov { dst = Ir.Reg d; src = Ir.Reg s } ->
          Hashtbl.replace set d (); Hashtbl.replace set s ()
      | Ir.Mov { dst = Ir.Reg d; _ } -> Hashtbl.replace set d ()
      | Ir.Alu { dst = d; src1 = Ir.Reg s1; src2 = Ir.Reg s2; _ } ->
          Hashtbl.replace set d (); Hashtbl.replace set s1 (); Hashtbl.replace set s2 ()
      | Ir.Alu { dst = d; src1 = Ir.Reg s1; _ } ->
          Hashtbl.replace set d (); Hashtbl.replace set s1 ()
      | Ir.Cmp { src1 = Ir.Reg s1; src2 = Ir.Reg s2 } ->
          Hashtbl.replace set s1 (); Hashtbl.replace set s2 ()
      | Ir.Cmp { src1 = Ir.Reg s1; _ } -> Hashtbl.replace set s1 ()
      | Ir.Push (Ir.Reg r) | Ir.Pop (Ir.Reg r) | Ir.Cmov { dst = r; _ } -> Hashtbl.replace set r ()
      | _ -> ())
    instrs;
  Hashtbl.fold (fun r () acc ->
    match r with
    | Register.Gpr _ -> r :: acc
    | _ -> acc) set []

let generate_junk_instrs rng ~real_regs =
  let vdst = Register.Vreg (Register.VTMP2, Register.B64) in
  let imm = Int64.of_int32 (Random.State.int32 rng Int32.max_int) in
  match Random.State.int rng 5 with
  | 0 ->
      [ Ir.Mov { dst = Ir.Reg vdst; src = Ir.Imm imm } ]
  | 1 ->
      [ Ir.Alu { op = Ir.Add; dst = vdst; src1 = Ir.Reg vdst; src2 = Ir.Imm imm; set_flags = false } ]
  | 2 ->
      [
        Ir.Alu { op = Ir.Xor; dst = vdst; src1 = Ir.Reg vdst; src2 = Ir.Imm imm; set_flags = false };
        Ir.Alu { op = Ir.Imul; dst = vdst; src1 = Ir.Reg vdst; src2 = Ir.Imm 0x5877L; set_flags = false };
      ]
  | 3 ->
      if List.length real_regs > 0 then
        let r = List.nth real_regs (Random.State.int rng (List.length real_regs)) in
        [
          Ir.Mov { dst = Ir.Reg vdst; src = Ir.Reg r };
          Ir.Alu { op = Ir.Xor; dst = vdst; src1 = Ir.Reg vdst; src2 = Ir.Imm imm; set_flags = false };
        ]
      else
        [ Ir.Alu { op = Ir.Add; dst = vdst; src1 = Ir.Reg vdst; src2 = Ir.Imm imm; set_flags = false } ]
  | _ ->
      [ Ir.Alu { op = Ir.Or; dst = vdst; src1 = Ir.Reg vdst; src2 = Ir.Imm imm; set_flags = false } ]

let inject_junk_instructions ~rng instrs =
  let real_regs = extract_real_regs instrs in
  let rec aux = function
    | [] -> []
    | [Ir.Ret] -> [Ir.Ret]
    | [Ir.Vm_exit] -> [Ir.Vm_exit]
    | (Ir.Cmp _ as cmp) :: (Ir.Cmov _ as cmov) :: rest ->
        let junk = if Random.State.int rng 100 < 35 then generate_junk_instrs rng ~real_regs else [] in
        cmp :: cmov :: (junk @ aux rest)
    | (Ir.Cmp _ as cmp) :: (Ir.Jcc _ as jcc) :: rest ->
        cmp :: jcc :: aux rest
    | (Ir.Jmp _ as j) :: rest ->
        j :: aux rest
    | (Ir.Jcc _ as j) :: rest ->
        j :: aux rest
    | hd :: rest ->
        let junk = if Random.State.int rng 100 < 35 then generate_junk_instrs rng ~real_regs else [] in
        hd :: (junk @ aux rest)
  in
  aux instrs

let rec fuse_block_instructions instrs =
  let fits_i32 v = v >= -2147483648L && v <= 2147483647L in
  match instrs with
  | [] -> []
  | Ir.Mov { dst = Ir.Reg d; src = Ir.Reg s } ::
    Ir.Alu { op = Ir.Add; dst = d2; src1 = Ir.Reg d3; src2 = Ir.Imm imm; _ } :: rest
    when d = d2 && d = d3 && fits_i32 imm ->
      Fused_Mov_Add { dst = d; src = s; imm } :: fuse_block_instructions rest

  | Ir.Alu { op = Ir.Add; dst = d; src1 = Ir.Reg d1; src2 = Ir.Reg s; _ } ::
    Ir.Alu { op = Ir.Imul; dst = d2; src1 = Ir.Reg d3; src2 = Ir.Imm imm; _ } :: rest
    when d = d1 && d = d2 && d = d3 && fits_i32 imm ->
      Fused_Add_Imul { dst = d; src = s; imm } :: fuse_block_instructions rest

  | Ir.Alu { op = Ir.Add; dst = d; src1 = Ir.Reg d1; src2 = Ir.Reg s; _ } ::
    Ir.Alu { op = Ir.Xor; dst = d2; src1 = Ir.Reg d3; src2 = Ir.Imm imm; _ } :: rest
    when d = d1 && d = d2 && d = d3 && fits_i32 imm ->
      Fused_Add_Xor { dst = d; src = s; imm } :: fuse_block_instructions rest

  | Ir.Alu { op = Ir.Sub; dst = d; src1 = Ir.Reg d1; src2 = Ir.Reg s; _ } ::
    Ir.Alu { op = Ir.Xor; dst = d2; src1 = Ir.Reg d3; src2 = Ir.Imm imm; _ } :: rest
    when d = d1 && d = d2 && d = d3 && fits_i32 imm ->
      Fused_Sub_Xor { dst = d; src = s; imm } :: fuse_block_instructions rest

  | Ir.Alu { op = Ir.Xor; dst = d; src1 = Ir.Reg d1; src2 = Ir.Reg s; _ } ::
    Ir.Alu { op = Ir.Add; dst = d2; src1 = Ir.Reg d3; src2 = Ir.Imm imm; _ } :: rest
    when d = d1 && d = d2 && d = d3 && fits_i32 imm ->
      Fused_Xor_Add { dst = d; src = s; imm } :: fuse_block_instructions rest

  | Ir.Cmp { src1 = Ir.Reg d; src2 = Ir.Imm imm } ::
    Ir.Cmov { cond; dst = d2; src = Ir.Reg s } :: rest
    when d = d2 && fits_i32 imm ->
      Fused_Cmp_Cmov { cmp_dst = d; cmp_imm = imm; cond; cmov_dst = d2; cmov_src = s } :: fuse_block_instructions rest

  | hd :: rest ->
      Raw hd :: fuse_block_instructions rest
