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
  | Register.Vreg (Register.VX18, _)  -> 23
  | Register.Vreg (Register.VX19, _)  -> 24
  | Register.Vreg (Register.VX20, _)  -> 25
  | Register.Vreg (Register.VX21, _)  -> 26
  | Register.Vreg (Register.VX22, _)  -> 27
  | Register.Vreg (Register.VX23, _)  -> 28
  | Register.Vreg (Register.VX24, _)  -> 29
  | Register.Vreg (Register.VX25, _)  -> 30
  | Register.Vreg (Register.VX26, _)  -> 31
  | Register.Vreg (Register.VZERO, _) -> 16
  | Register.Fpr (i, _) -> (23 + (i mod 9)) mod 32

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
  | OP_NEG_RR
  | OP_NOT_RR
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
  | OP_SAR_RI
  | OP_DIV_RR
  | OP_IDIV_RR
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
  | OP_VEC_MOV
  | OP_VEC_BINOP
  | OP_VEC_LOAD
  | OP_VEC_STORE
  | OP_CALL_EXTERN
  | OP_LOAD_64
  | OP_LOAD_32
  | OP_LOAD_16
  | OP_LOAD_8
  | OP_LOAD_S32
  | OP_LOAD_S16
  | OP_LOAD_S8
  | OP_STORE_64
  | OP_STORE_32
  | OP_STORE_16
  | OP_STORE_8
  | OP_RESOLVE_SYM
  | OP_FADD_DD
  | OP_FSUB_DD
  | OP_FMUL_DD
  | OP_FDIV_DD
  | OP_FCMP_DD
  | OP_FCVTZS
  | OP_SCVTF
  | OP_ATOMIC_LOAD
  | OP_ATOMIC_STORE
  | OP_ATOMIC_CAS
  | OP_ATOMIC_ADD
  | OP_ATOMIC_SWP

let all_op_kinds = [
  OP_NOP; OP_MOV_RR; OP_MOV_RI; OP_MOV_HIGH; OP_ADD_RR; OP_ADD_RI;
  OP_SUB_RR; OP_SUB_RI; OP_IMUL_RR; OP_IMUL_RI; OP_XOR_RR; OP_XOR_RI;
  OP_AND_RR; OP_AND_RI; OP_OR_RR; OP_OR_RI; OP_ROL_RI; OP_ROR_RI; OP_SHL_RI; OP_SHR_RI;
  OP_SAR_RI; OP_DIV_RR; OP_IDIV_RR;
  OP_NEG_RR; OP_NOT_RR;
  OP_CMP_RR; OP_CMP_RI; OP_PUSH_R;
  OP_POP_R; OP_JMP; OP_JCC; OP_CMOV; OP_SETCC; OP_CALL; OP_RET; OP_EXIT;
  OP_FUSED_MOV_ADD_RRI; OP_FUSED_ADD_IMUL_RRI; OP_FUSED_ADD_XOR_RRI;
  OP_FUSED_SUB_XOR_RRI; OP_FUSED_XOR_ADD_RRI; OP_FUSED_CMP_CMOV;
  OP_BRIDGE_TO_FLOW; OP_BRIDGE_TO_MATH;
  OP_VADD_VV; OP_VSUB_VV; OP_VMUL_VV; OP_VXOR_VV;
  OP_VEC_MOV; OP_VEC_BINOP; OP_VEC_LOAD; OP_VEC_STORE;
  OP_CALL_EXTERN; OP_LOAD_64; OP_LOAD_32; OP_LOAD_16; OP_LOAD_8;
  OP_LOAD_S32; OP_LOAD_S16; OP_LOAD_S8;
  OP_STORE_64; OP_STORE_32; OP_STORE_16; OP_STORE_8;
  OP_RESOLVE_SYM;
  OP_FADD_DD; OP_FSUB_DD; OP_FMUL_DD; OP_FDIV_DD; OP_FCMP_DD;
  OP_FCVTZS; OP_SCVTF;
  OP_ATOMIC_LOAD; OP_ATOMIC_STORE; OP_ATOMIC_CAS; OP_ATOMIC_ADD; OP_ATOMIC_SWP;
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
  | OP_NEG_RR -> "H_NEG_RR"
  | OP_NOT_RR -> "H_NOT_RR"
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
  | OP_SAR_RI -> "H_SAR_RI"
  | OP_DIV_RR -> "H_DIV_RR"
  | OP_IDIV_RR -> "H_IDIV_RR"
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
  | OP_VEC_MOV -> "H_VEC_MOV"
  | OP_VEC_BINOP -> "H_VEC_BINOP"
  | OP_VEC_LOAD -> "H_VEC_LOAD"
  | OP_VEC_STORE -> "H_VEC_STORE"
  | OP_CALL_EXTERN -> "H_CALL_EXTERN"
  | OP_LOAD_64 -> "H_LOAD_64"
  | OP_LOAD_32 -> "H_LOAD_32"
  | OP_LOAD_16 -> "H_LOAD_16"
  | OP_LOAD_8 -> "H_LOAD_8"
  | OP_LOAD_S32 -> "H_LOAD_S32"
  | OP_LOAD_S16 -> "H_LOAD_S16"
  | OP_LOAD_S8 -> "H_LOAD_S8"
  | OP_STORE_64 -> "H_STORE_64"
  | OP_STORE_32 -> "H_STORE_32"
  | OP_STORE_16 -> "H_STORE_16"
  | OP_STORE_8 -> "H_STORE_8"
  | OP_RESOLVE_SYM -> "H_RESOLVE_SYM"
  | OP_FADD_DD -> "H_FADD_DD"
  | OP_FSUB_DD -> "H_FSUB_DD"
  | OP_FMUL_DD -> "H_FMUL_DD"
  | OP_FDIV_DD -> "H_FDIV_DD"
  | OP_FCMP_DD -> "H_FCMP_DD"
  | OP_FCVTZS -> "H_FCVTZS"
  | OP_SCVTF -> "H_SCVTF"
  | OP_ATOMIC_LOAD -> "H_ATOMIC_LOAD"
  | OP_ATOMIC_STORE -> "H_ATOMIC_STORE"
  | OP_ATOMIC_CAS -> "H_ATOMIC_CAS"
  | OP_ATOMIC_ADD -> "H_ATOMIC_ADD"
  | OP_ATOMIC_SWP -> "H_ATOMIC_SWP"

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
  let vdst = Register.Vreg (Register.VX26, Register.B64) in
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

let is_commutative_alu_op = function
  | Ir.Add | Ir.Imul | Ir.Mul | Ir.Xor | Ir.And | Ir.Or -> true
  | _ -> false

let pick_scratch_reg (d : Register.t) (s : Register.t) : Register.t =
  let d_str = Register.to_string d in
  let s_str = Register.to_string s in
  let w = Register.get_width d in
  let candidates = [ Register.vtmp0; Register.vtmp1; Register.vtmp2 ] in
  let chosen =
    List.find
      (fun cand ->
        let c_str = Register.to_string cand in
        c_str <> d_str && c_str <> s_str)
      candidates
  in
  Register.with_width chosen w

let rec canonicalize_instr (instr : Ir.instr) : Ir.instr list =
  match instr with
  | Ir.Alu { op; dst; src1 = Ir.Reg s1; src2 = Ir.Imm imm; set_flags } ->
      if Register.to_string s1 = Register.to_string dst then
        [ Ir.Alu { op; dst; src1 = Ir.Reg dst; src2 = Ir.Imm imm; set_flags } ]
      else
        [
          Ir.Mov { dst = Ir.Reg dst; src = Ir.Reg s1 };
          Ir.Alu { op; dst; src1 = Ir.Reg dst; src2 = Ir.Imm imm; set_flags };
        ]

  | Ir.Alu { op; dst; src1 = Ir.Reg s1; src2 = Ir.Reg s2; set_flags } ->
      let d_str = Register.to_string dst in
      let s1_str = Register.to_string s1 in
      let s2_str = Register.to_string s2 in
      if s1_str = d_str then
        (* Already 2-address: dst = dst OP s2 *)
        [ Ir.Alu { op; dst; src1 = Ir.Reg dst; src2 = Ir.Reg s2; set_flags } ]
      else if s2_str = d_str then
        (* Hazard case: dst = s1 OP dst *)
        if is_commutative_alu_op op then
          (* Commutative: s1 OP dst == dst OP s1 *)
          [ Ir.Alu { op; dst; src1 = Ir.Reg dst; src2 = Ir.Reg s1; set_flags } ]
        else
          (* Non-commutative: e.g. dst = s1 - dst. Must not clobber dst when loading s1. *)
          let scratch = pick_scratch_reg dst s1 in
          [
            Ir.Mov { dst = Ir.Reg scratch; src = Ir.Reg dst };
            Ir.Mov { dst = Ir.Reg dst; src = Ir.Reg s1 };
            Ir.Alu { op; dst; src1 = Ir.Reg dst; src2 = Ir.Reg scratch; set_flags };
          ]
      else
        (* Normal 3-address: dst = s1 OP s2, where dst != s1 and dst != s2 *)
        [
          Ir.Mov { dst = Ir.Reg dst; src = Ir.Reg s1 };
          Ir.Alu { op; dst; src1 = Ir.Reg dst; src2 = Ir.Reg s2; set_flags };
        ]

  | Ir.Alu { op; dst; src1 = Ir.Reg s1; src2 = Ir.Mem m; set_flags } ->
      let scratch = pick_scratch_reg dst s1 in
      let load_m = Ir.Mov { dst = Ir.Reg scratch; src = Ir.Mem m } in
      let alu = Ir.Alu { op; dst; src1 = Ir.Reg s1; src2 = Ir.Reg scratch; set_flags } in
      load_m :: canonicalize_instr alu

  | Ir.Alu { op; dst; src1 = Ir.Imm imm; src2; set_flags } ->
      if is_commutative_alu_op op then
        canonicalize_instr (Ir.Alu { op; dst; src1 = src2; src2 = Ir.Imm imm; set_flags })
      else
        (match src2 with
        | Ir.Reg s2 when Register.to_string s2 = Register.to_string dst ->
            let scratch = pick_scratch_reg dst dst in
            [
              Ir.Mov { dst = Ir.Reg scratch; src = Ir.Reg dst };
              Ir.Mov { dst = Ir.Reg dst; src = Ir.Imm imm };
              Ir.Alu { op; dst; src1 = Ir.Reg dst; src2 = Ir.Reg scratch; set_flags };
            ]
        | _ ->
            [
              Ir.Mov { dst = Ir.Reg dst; src = Ir.Imm imm };
              Ir.Alu { op; dst; src1 = Ir.Reg dst; src2; set_flags };
            ])

  | Ir.Unary { op; dst; src = Ir.Reg s; set_flags } ->
      if Register.to_string s = Register.to_string dst then
        [ Ir.Unary { op; dst; src = Ir.Reg dst; set_flags } ]
      else
        [
          Ir.Mov { dst = Ir.Reg dst; src = Ir.Reg s };
          Ir.Unary { op; dst; src = Ir.Reg dst; set_flags };
        ]
  | Ir.Unary { op; dst; src; set_flags } ->
      [
        Ir.Mov { dst = Ir.Reg dst; src };
        Ir.Unary { op; dst; src = Ir.Reg dst; set_flags };
      ]

  | Ir.Lea { dst; addr } ->
      let scratch = pick_scratch_reg dst dst in
      let prep = ref [] in
      (match addr.base with
      | Some b -> prep := [ Ir.Mov { dst = Ir.Reg dst; src = Ir.Reg b } ]
      | None ->
          match addr.index with
          | Some (idx, scale) ->
              prep := [ Ir.Mov { dst = Ir.Reg dst; src = Ir.Reg idx } ];
              if scale = 2 then prep := !prep @ [ Ir.Alu { op = Ir.Shl; dst; src1 = Ir.Reg dst; src2 = Ir.Imm 1L; set_flags = false } ]
              else if scale = 4 then prep := !prep @ [ Ir.Alu { op = Ir.Shl; dst; src1 = Ir.Reg dst; src2 = Ir.Imm 2L; set_flags = false } ]
              else if scale = 8 then prep := !prep @ [ Ir.Alu { op = Ir.Shl; dst; src1 = Ir.Reg dst; src2 = Ir.Imm 3L; set_flags = false } ]
              else if scale <> 1 then prep := !prep @ [ Ir.Alu { op = Ir.Imul; dst; src1 = Ir.Reg dst; src2 = Ir.Imm (Int64.of_int scale); set_flags = false } ]
          | None -> prep := [ Ir.Mov { dst = Ir.Reg dst; src = Ir.Imm addr.disp } ]);
      (if addr.base <> None then
        match addr.index with
        | Some (idx, scale) ->
            let term = ref [ Ir.Mov { dst = Ir.Reg scratch; src = Ir.Reg idx } ] in
            if scale = 2 then term := !term @ [ Ir.Alu { op = Ir.Shl; dst = scratch; src1 = Ir.Reg scratch; src2 = Ir.Imm 1L; set_flags = false } ]
            else if scale = 4 then term := !term @ [ Ir.Alu { op = Ir.Shl; dst = scratch; src1 = Ir.Reg scratch; src2 = Ir.Imm 2L; set_flags = false } ]
            else if scale = 8 then term := !term @ [ Ir.Alu { op = Ir.Shl; dst = scratch; src1 = Ir.Reg scratch; src2 = Ir.Imm 3L; set_flags = false } ]
            else if scale <> 1 then term := !term @ [ Ir.Alu { op = Ir.Imul; dst = scratch; src1 = Ir.Reg scratch; src2 = Ir.Imm (Int64.of_int scale); set_flags = false } ];
            term := !term @ [ Ir.Alu { op = Ir.Add; dst; src1 = Ir.Reg dst; src2 = Ir.Reg scratch; set_flags = false } ];
            prep := !prep @ !term
        | None -> ());
      if (addr.base <> None || addr.index <> None) && addr.disp <> 0L then
        prep := !prep @ [ Ir.Alu { op = Ir.Add; dst; src1 = Ir.Reg dst; src2 = Ir.Imm addr.disp; set_flags = false } ];
      !prep

  | Ir.Mov { dst = Ir.Reg d; src = Ir.Mem m } when m.index <> None || m.base = None ->
      (match m.index with
      | Some (idx, scale) ->
          let scratch = pick_scratch_reg d idx in
          let term = ref [ Ir.Mov { dst = Ir.Reg scratch; src = Ir.Reg idx } ] in
          if scale = 2 then term := !term @ [ Ir.Alu { op = Ir.Shl; dst = scratch; src1 = Ir.Reg scratch; src2 = Ir.Imm 1L; set_flags = false } ]
          else if scale = 4 then term := !term @ [ Ir.Alu { op = Ir.Shl; dst = scratch; src1 = Ir.Reg scratch; src2 = Ir.Imm 2L; set_flags = false } ]
          else if scale = 8 then term := !term @ [ Ir.Alu { op = Ir.Shl; dst = scratch; src1 = Ir.Reg scratch; src2 = Ir.Imm 3L; set_flags = false } ]
          else if scale <> 1 then term := !term @ [ Ir.Alu { op = Ir.Imul; dst = scratch; src1 = Ir.Reg scratch; src2 = Ir.Imm (Int64.of_int scale); set_flags = false } ];
          (match m.base with
          | Some b -> term := !term @ [ Ir.Alu { op = Ir.Add; dst = scratch; src1 = Ir.Reg scratch; src2 = Ir.Reg b; set_flags = false } ]
          | None -> ());
          let m_simple = { m with base = Some scratch; index = None } in
          !term @ [ Ir.Mov { dst = Ir.Reg d; src = Ir.Mem m_simple } ]
      | None ->
          let scratch = pick_scratch_reg d d in
          [ Ir.Mov { dst = Ir.Reg scratch; src = Ir.Imm m.disp };
            Ir.Mov { dst = Ir.Reg d; src = Ir.Mem { m with base = Some scratch; disp = 0L } } ])

  | Ir.Mov { dst = Ir.Mem m; src = Ir.Reg s } when m.index <> None || m.base = None ->
      (match m.index with
      | Some (idx, scale) ->
          let scratch = pick_scratch_reg s idx in
          let term = ref [ Ir.Mov { dst = Ir.Reg scratch; src = Ir.Reg idx } ] in
          if scale = 2 then term := !term @ [ Ir.Alu { op = Ir.Shl; dst = scratch; src1 = Ir.Reg scratch; src2 = Ir.Imm 1L; set_flags = false } ]
          else if scale = 4 then term := !term @ [ Ir.Alu { op = Ir.Shl; dst = scratch; src1 = Ir.Reg scratch; src2 = Ir.Imm 2L; set_flags = false } ]
          else if scale = 8 then term := !term @ [ Ir.Alu { op = Ir.Shl; dst = scratch; src1 = Ir.Reg scratch; src2 = Ir.Imm 3L; set_flags = false } ]
          else if scale <> 1 then term := !term @ [ Ir.Alu { op = Ir.Imul; dst = scratch; src1 = Ir.Reg scratch; src2 = Ir.Imm (Int64.of_int scale); set_flags = false } ];
          (match m.base with
          | Some b -> term := !term @ [ Ir.Alu { op = Ir.Add; dst = scratch; src1 = Ir.Reg scratch; src2 = Ir.Reg b; set_flags = false } ]
          | None -> ());
          let m_simple = { m with base = Some scratch; index = None } in
          !term @ [ Ir.Mov { dst = Ir.Mem m_simple; src = Ir.Reg s } ]
      | None ->
          let scratch = pick_scratch_reg s s in
          [ Ir.Mov { dst = Ir.Reg scratch; src = Ir.Imm m.disp };
            Ir.Mov { dst = Ir.Mem { m with base = Some scratch; disp = 0L }; src = Ir.Reg s } ])

  | Ir.Test { src1 = Ir.Reg s1; src2 = Ir.Reg s2 } ->
      let scratch = pick_scratch_reg s1 s2 in
      [ Ir.Mov { dst = Ir.Reg scratch; src = Ir.Reg s1 };
        Ir.Alu { op = Ir.And; dst = scratch; src1 = Ir.Reg scratch; src2 = Ir.Reg s2; set_flags = false };
        Ir.Cmp { src1 = Ir.Reg scratch; src2 = Ir.Imm 0L } ]

  | Ir.Test { src1 = Ir.Reg s1; src2 = Ir.Imm imm } ->
      let scratch = pick_scratch_reg s1 s1 in
      [ Ir.Mov { dst = Ir.Reg scratch; src = Ir.Reg s1 };
        Ir.Alu { op = Ir.And; dst = scratch; src1 = Ir.Reg scratch; src2 = Ir.Imm imm; set_flags = false };
        Ir.Cmp { src1 = Ir.Reg scratch; src2 = Ir.Imm 0L } ]

  | Ir.Xchg (Ir.Reg a, Ir.Reg b) ->
      let scratch = pick_scratch_reg a b in
      [ Ir.Mov { dst = Ir.Reg scratch; src = Ir.Reg a };
        Ir.Mov { dst = Ir.Reg a; src = Ir.Reg b };
        Ir.Mov { dst = Ir.Reg b; src = Ir.Reg scratch } ]

  | Ir.Push (Ir.Imm imm) ->
      let scratch = Register.vtmp0 in
      [ Ir.Mov { dst = Ir.Reg scratch; src = Ir.Imm imm };
        Ir.Push (Ir.Reg scratch) ]

  | Ir.Push (Ir.Mem m) ->
      let scratch = Register.vtmp0 in
      canonicalize_instr (Ir.Mov { dst = Ir.Reg scratch; src = Ir.Mem m }) @ [ Ir.Push (Ir.Reg scratch) ]

  | Ir.Pop (Ir.Mem m) ->
      let scratch = Register.vtmp0 in
      [ Ir.Pop (Ir.Reg scratch) ] @ canonicalize_instr (Ir.Mov { dst = Ir.Mem m; src = Ir.Reg scratch })

  | other -> [ other ]

let canonicalize_3addr_alu (instrs : Ir.instr list) : Ir.instr list =
  List.concat_map canonicalize_instr instrs

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
