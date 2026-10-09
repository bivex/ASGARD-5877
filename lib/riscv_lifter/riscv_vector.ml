open Vm_ir
open Ir
open Riscv_types

type vtype_state = {
  mutable sew : int;
  mutable lmul : int;
  mutable vl : int64 option;
}

let current_state : vtype_state = {
  sew = 32;
  lmul = 1;
  vl = None;
}

let reset_state () =
  current_state.sew <- 32;
  current_state.lmul <- 1;
  current_state.vl <- None

let calculate_vlmax ~sew ~lmul =
  let sew = if sew <= 0 then 32 else sew in
  let base_lanes = 128 / sew in
  if lmul >= 1 then max 1 (base_lanes * lmul)
  else if lmul = -2 then max 1 (base_lanes / 2)
  else if lmul = -4 then max 1 (base_lanes / 4)
  else if lmul = -8 then max 1 (base_lanes / 8)
  else max 1 base_lanes

let width_of_bits = function
  | 8 -> Register.B8
  | 16 -> Register.B16
  | 32 -> Register.B32
  | 64 -> Register.B64
  | 128 -> Register.B128
  | _ -> Register.B64

let is_zero_reg = function
  | Register.Vreg (Register.VZERO, _) -> true
  | _ -> false

let scratch_vreg = 31
let scratch_vreg2 = 30
let scratch_vreg3 = 29

let is_mask_op = function
  | OpLabel s when s = "v0.t" || s = "v0" -> true
  | OpReg (Register.Fpr (0, _)) -> true
  | _ -> false

let apply_mask ~vd ~dst ~sew instrs =
  let blend = [
    Ir.Vec_binop { op = Vand; elem = VInt; dst = scratch_vreg; src1 = dst; src2 = 0; bits = 128; lane_bits = sew };
    Ir.Vec_binop { op = Vandn; elem = VInt; dst = scratch_vreg2; src1 = 0; src2 = vd; bits = 128; lane_bits = sew };
    Ir.Vec_binop { op = Vor; elem = VInt; dst = vd; src1 = scratch_vreg; src2 = scratch_vreg2; bits = 128; lane_bits = sew };
  ] in
  instrs @ blend

let parse_vtype_tokens ops =
  List.iter (function
    | OpLabel s ->
        let s = String.lowercase_ascii s in
        (match s with
        | "e8" -> current_state.sew <- 8
        | "e16" -> current_state.sew <- 16
        | "e32" -> current_state.sew <- 32
        | "e64" -> current_state.sew <- 64
        | "m1" -> current_state.lmul <- 1
        | "m2" -> current_state.lmul <- 2
        | "m4" -> current_state.lmul <- 4
        | "m8" -> current_state.lmul <- 8
        | "mf2" -> current_state.lmul <- -2
        | "mf4" -> current_state.lmul <- -4
        | "mf8" -> current_state.lmul <- -8
        | _ -> ())
    | OpImm imm ->
        let vsew = Int64.to_int (Int64.logand (Int64.shift_right_logical imm 3) 0x7L) in
        let vlmul = Int64.to_int (Int64.logand imm 0x7L) in
        let sew = match vsew with
          | 0 -> 8
          | 1 -> 16
          | 2 -> 32
          | 3 -> 64
          | _ -> current_state.sew
        in
        let lmul = match vlmul with
          | 0 -> 1
          | 1 -> 2
          | 2 -> 4
          | 3 -> 8
          | 5 -> -8
          | 6 -> -4
          | 7 -> -2
          | _ -> current_state.lmul
        in
        current_state.sew <- sew;
        current_state.lmul <- lmul
    | _ -> ()) ops

let lift_vset_config ~rd ~rs1 ~vtype_ops =
  parse_vtype_tokens vtype_ops;
  let vlmax = calculate_vlmax ~sew:current_state.sew ~lmul:current_state.lmul in
  let vlmax_i64 = Int64.of_int vlmax in
  match rs1 with
  | OpReg r when is_zero_reg r ->
      if is_zero_reg rd then begin
        Ok [ Ir.Nop ]
      end else begin
        current_state.vl <- Some vlmax_i64;
        Ok [ Ir.Mov { dst = Reg rd; src = Imm vlmax_i64 } ]
      end
  | OpImm imm ->
      let avl = Int64.to_int imm in
      let active_vl = Int64.of_int (min avl vlmax) in
      current_state.vl <- Some active_vl;
      if is_zero_reg rd then Ok [ Ir.Nop ]
      else Ok [ Ir.Mov { dst = Reg rd; src = Imm active_vl } ]
  | OpReg reg ->
      current_state.vl <- None;
      if is_zero_reg rd then Ok [ Ir.Nop ]
      else
        Ok [
          Ir.Mov { dst = Reg rd; src = Reg reg };
          Ir.Cmp { src1 = Reg rd; src2 = Imm vlmax_i64 };
          Ir.Mov { dst = Reg Register.vtmp0; src = Imm vlmax_i64 };
          Ir.Cmov { cond = Flags.A; dst = rd; src = Reg Register.vtmp0 };
        ]
  | OpLabel _ ->
      Ok [ Ir.Mov { dst = Reg rd; src = Imm vlmax_i64 } ]
  | OpMem _ ->
      Error "Invalid memory operand for vsetvli"

let lift_strided_mem ~is_load ~sew ~vreg ~mem ~stride_reg =
  let num_lanes = 128 / sew in
  let elem_w = width_of_bits sew in
  let elem_bytes = sew / 8 in
  let instrs = ref [] in
  if is_load then begin
    for i = 0 to num_lanes - 1 do
      let disp_i = Int64.of_int (-16 + i * elem_bytes) in
      let prep =
        if i = 0 then
          match mem.base with
          | Some b -> [ Ir.Mov { dst = Reg Register.vtmp0; src = Reg b } ]
          | None -> [ Ir.Mov { dst = Reg Register.vtmp0; src = Imm mem.disp } ]
        else
          let calc = [
            Ir.Mov { dst = Reg Register.vtmp0; src = Reg stride_reg };
            Ir.Alu { op = Imul; dst = Register.vtmp0; src1 = Reg Register.vtmp0; src2 = Imm (Int64.of_int i); set_flags = false };
          ] in
          let with_b = match mem.base with
            | Some b -> [ Ir.Alu { op = Add; dst = Register.vtmp0; src1 = Reg Register.vtmp0; src2 = Reg b; set_flags = false } ]
            | None -> []
          in
          calc @ with_b
      in
      let with_disp =
        if mem.disp <> 0L then
          [ Ir.Alu { op = Add; dst = Register.vtmp0; src1 = Reg Register.vtmp0; src2 = Imm mem.disp; set_flags = false } ]
        else []
      in
      let load_and_buf = [
        Ir.Mov { dst = Reg (Register.with_width Register.vtmp1 elem_w);
                 src = Mem { base = Some Register.vtmp0; index = None; disp = 0L; width = elem_w; is_signed = false; segment = None } };
        Ir.Mov { dst = Mem { base = Some Register.rsp; index = None; disp = disp_i; width = elem_w; is_signed = false; segment = None };
                 src = Reg (Register.with_width Register.vtmp1 elem_w) };
      ] in
      instrs := !instrs @ prep @ with_disp @ load_and_buf
    done;
    instrs := !instrs @ [
      Ir.Vec_load { dst = vreg; addr = { base = Some Register.rsp; index = None; disp = -16L; width = Register.B128; is_signed = false; segment = None }; bits = 128 }
    ];
    Ok !instrs
  end else begin
    instrs := !instrs @ [
      Ir.Vec_store { src = vreg; addr = { base = Some Register.rsp; index = None; disp = -16L; width = Register.B128; is_signed = false; segment = None }; bits = 128 }
    ];
    for i = 0 to num_lanes - 1 do
      let disp_i = Int64.of_int (-16 + i * elem_bytes) in
      let load_buf = [
        Ir.Mov { dst = Reg (Register.with_width Register.vtmp1 elem_w);
                 src = Mem { base = Some Register.rsp; index = None; disp = disp_i; width = elem_w; is_signed = false; segment = None } };
      ] in
      let prep =
        if i = 0 then
          match mem.base with
          | Some b -> [ Ir.Mov { dst = Reg Register.vtmp0; src = Reg b } ]
          | None -> [ Ir.Mov { dst = Reg Register.vtmp0; src = Imm mem.disp } ]
        else
          let calc = [
            Ir.Mov { dst = Reg Register.vtmp0; src = Reg stride_reg };
            Ir.Alu { op = Imul; dst = Register.vtmp0; src1 = Reg Register.vtmp0; src2 = Imm (Int64.of_int i); set_flags = false };
          ] in
          let with_b = match mem.base with
            | Some b -> [ Ir.Alu { op = Add; dst = Register.vtmp0; src1 = Reg Register.vtmp0; src2 = Reg b; set_flags = false } ]
            | None -> []
          in
          calc @ with_b
      in
      let with_disp =
        if mem.disp <> 0L then
          [ Ir.Alu { op = Add; dst = Register.vtmp0; src1 = Reg Register.vtmp0; src2 = Imm mem.disp; set_flags = false } ]
        else []
      in
      let store_elem = [
        Ir.Mov { dst = Mem { base = Some Register.vtmp0; index = None; disp = 0L; width = elem_w; is_signed = false; segment = None };
                 src = Reg (Register.with_width Register.vtmp1 elem_w) };
      ] in
      instrs := !instrs @ load_buf @ prep @ with_disp @ store_elem
    done;
    Ok !instrs
  end

let lift_indexed_mem ~is_load ~sew ~idx_sew ~vreg ~mem ~idx_vreg =
  let num_lanes = 128 / sew in
  let elem_w = width_of_bits sew in
  let elem_bytes = sew / 8 in
  let idx_w = width_of_bits idx_sew in
  let idx_bytes = idx_sew / 8 in
  let instrs = ref [] in
  instrs := !instrs @ [
    Ir.Vec_store { src = idx_vreg; addr = { base = Some Register.rsp; index = None; disp = -32L; width = Register.B128; is_signed = false; segment = None }; bits = 128 }
  ];
  if is_load then begin
    for i = 0 to num_lanes - 1 do
      let disp_buf = Int64.of_int (-16 + i * elem_bytes) in
      let disp_idx = Int64.of_int (-32 + i * idx_bytes) in
      let load_idx = [
        Ir.Mov { dst = Reg (Register.with_width Register.vtmp0 idx_w);
                 src = Mem { base = Some Register.rsp; index = None; disp = disp_idx; width = idx_w; is_signed = false; segment = None } };
      ] in
      let with_base = match mem.base with
        | Some b -> [ Ir.Alu { op = Add; dst = Register.vtmp0; src1 = Reg Register.vtmp0; src2 = Reg b; set_flags = false } ]
        | None -> []
      in
      let with_disp =
        if mem.disp <> 0L then
          [ Ir.Alu { op = Add; dst = Register.vtmp0; src1 = Reg Register.vtmp0; src2 = Imm mem.disp; set_flags = false } ]
        else []
      in
      let load_and_buf = [
        Ir.Mov { dst = Reg (Register.with_width Register.vtmp1 elem_w);
                 src = Mem { base = Some Register.vtmp0; index = None; disp = 0L; width = elem_w; is_signed = false; segment = None } };
        Ir.Mov { dst = Mem { base = Some Register.rsp; index = None; disp = disp_buf; width = elem_w; is_signed = false; segment = None };
                 src = Reg (Register.with_width Register.vtmp1 elem_w) };
      ] in
      instrs := !instrs @ load_idx @ with_base @ with_disp @ load_and_buf
    done;
    instrs := !instrs @ [
      Ir.Vec_load { dst = vreg; addr = { base = Some Register.rsp; index = None; disp = -16L; width = Register.B128; is_signed = false; segment = None }; bits = 128 }
    ];
    Ok !instrs
  end else begin
    instrs := !instrs @ [
      Ir.Vec_store { src = vreg; addr = { base = Some Register.rsp; index = None; disp = -16L; width = Register.B128; is_signed = false; segment = None }; bits = 128 }
    ];
    for i = 0 to num_lanes - 1 do
      let disp_buf = Int64.of_int (-16 + i * elem_bytes) in
      let disp_idx = Int64.of_int (-32 + i * idx_bytes) in
      let load_idx = [
        Ir.Mov { dst = Reg (Register.with_width Register.vtmp0 idx_w);
                 src = Mem { base = Some Register.rsp; index = None; disp = disp_idx; width = idx_w; is_signed = false; segment = None } };
      ] in
      let with_base = match mem.base with
        | Some b -> [ Ir.Alu { op = Add; dst = Register.vtmp0; src1 = Reg Register.vtmp0; src2 = Reg b; set_flags = false } ]
        | None -> []
      in
      let with_disp =
        if mem.disp <> 0L then
          [ Ir.Alu { op = Add; dst = Register.vtmp0; src1 = Reg Register.vtmp0; src2 = Imm mem.disp; set_flags = false } ]
        else []
      in
      let load_buf_and_store = [
        Ir.Mov { dst = Reg (Register.with_width Register.vtmp1 elem_w);
                 src = Mem { base = Some Register.rsp; index = None; disp = disp_buf; width = elem_w; is_signed = false; segment = None } };
        Ir.Mov { dst = Mem { base = Some Register.vtmp0; index = None; disp = 0L; width = elem_w; is_signed = false; segment = None };
                 src = Reg (Register.with_width Register.vtmp1 elem_w) };
      ] in
      instrs := !instrs @ load_idx @ with_base @ with_disp @ load_buf_and_store
    done;
    Ok !instrs
  end

let lift_reduction ~op ~vd ~vs2 ~vs1 =
  let sew = current_state.sew in
  let current = scratch_vreg2 in
  let scratch = scratch_vreg in
  let instrs = ref [
    Ir.Vec_mov { dst = current; src = vs2; bits = 128 };
    Ir.Vec_binop { op = Vxor; elem = VInt; dst = scratch; src1 = scratch; src2 = scratch; bits = 128; lane_bits = 64 };
  ] in
  let fold_step shift_bytes =
    [
      Ir.Vec_ext { dst = scratch; src1 = current; src2 = scratch; imm = shift_bytes; bits = 128 };
      Ir.Vec_binop { op; elem = VInt; dst = current; src1 = current; src2 = scratch; bits = 128; lane_bits = sew };
    ]
  in
  if sew <= 64 then instrs := !instrs @ fold_step 8;
  if sew <= 32 then instrs := !instrs @ fold_step 4;
  if sew <= 16 then instrs := !instrs @ fold_step 2;
  if sew <= 8  then instrs := !instrs @ fold_step 1;
  instrs := !instrs @ [
    Ir.Vec_binop { op; elem = VInt; dst = vd; src1 = current; src2 = vs1; bits = 128; lane_bits = sew };
  ];
  Ok !instrs

let lift_vector mnemonic ops =
  let sew = current_state.sew in
  let elem_w = width_of_bits sew in
  match mnemonic, ops with
  (* 1. Configuration: vsetvli, vsetivli, vsetvl *)
  | "vsetvli", OpReg rd :: rs1 :: rest ->
      Some (lift_vset_config ~rd ~rs1 ~vtype_ops:rest)
  | "vsetivli", OpReg rd :: OpImm uimm :: rest ->
      Some (lift_vset_config ~rd ~rs1:(OpImm uimm) ~vtype_ops:rest)
  | "vsetvl", [ OpReg rd; rs1; rs2 ] ->
      Some (lift_vset_config ~rd ~rs1 ~vtype_ops:[ rs2 ])

  (* 2. Unit-stride vector memory: vle8/16/32/64.v, vse8/16/32/64.v *)
  | ("vle8.v" | "vle16.v" | "vle32.v" | "vle64.v"), [ OpReg (Register.Fpr (d, _)); OpMem m ] ->
      Some (Ok [ Ir.Vec_load { dst = d; addr = { base = m.base; index = None; disp = m.disp; width = Register.B128; is_signed = false; segment = None }; bits = 128 } ])
  | ("vle8.v" | "vle16.v" | "vle32.v" | "vle64.v"), [ OpReg (Register.Fpr (d, _)); OpMem m; mask ] when is_mask_op mask ->
      let load = [ Ir.Vec_load { dst = scratch_vreg3; addr = { base = m.base; index = None; disp = m.disp; width = Register.B128; is_signed = false; segment = None }; bits = 128 } ] in
      Some (Ok (apply_mask ~vd:d ~dst:scratch_vreg3 ~sew load))

  | ("vse8.v" | "vse16.v" | "vse32.v" | "vse64.v"), [ OpReg (Register.Fpr (s, _)); OpMem m ] ->
      Some (Ok [ Ir.Vec_store { src = s; addr = { base = m.base; index = None; disp = m.disp; width = Register.B128; is_signed = false; segment = None }; bits = 128 } ])
  | ("vse8.v" | "vse16.v" | "vse32.v" | "vse64.v"), [ OpReg (Register.Fpr (s, _)); OpMem m; mask ] when is_mask_op mask ->
      Some (Ok [ Ir.Vec_store { src = s; addr = { base = m.base; index = None; disp = m.disp; width = Register.B128; is_signed = false; segment = None }; bits = 128 } ])

  (* 3. Strided vector memory: vlse*.v, vsse*.v *)
  | ("vlse8.v" | "vlse16.v" | "vlse32.v" | "vlse64.v"), [ OpReg (Register.Fpr (d, _)); OpMem m; OpReg stride_reg ] ->
      let w = match mnemonic with "vlse8.v" -> 8 | "vlse16.v" -> 16 | "vlse32.v" -> 32 | _ -> 64 in
      Some (lift_strided_mem ~is_load:true ~sew:w ~vreg:d ~mem:m ~stride_reg)
  | ("vsse8.v" | "vsse16.v" | "vsse32.v" | "vsse64.v"), [ OpReg (Register.Fpr (s, _)); OpMem m; OpReg stride_reg ] ->
      let w = match mnemonic with "vsse8.v" -> 8 | "vsse16.v" -> 16 | "vsse32.v" -> 32 | _ -> 64 in
      Some (lift_strided_mem ~is_load:false ~sew:w ~vreg:s ~mem:m ~stride_reg)

  (* 4. Indexed vector memory: vluxei*, vloxei*, vsuxei*, vsoxei* *)
  | (("vluxei8.v" | "vloxei8.v" | "vluxei16.v" | "vloxei16.v" | "vluxei32.v" | "vloxei32.v" | "vluxei64.v" | "vloxei64.v"),
     [ OpReg (Register.Fpr (d, _)); OpMem m; OpReg (Register.Fpr (idx, _)) ]) ->
      let idx_w =
        if String.contains mnemonic '8' then 8
        else if String.contains mnemonic '1' then 16
        else if String.contains mnemonic '3' then 32
        else 64
      in
      Some (lift_indexed_mem ~is_load:true ~sew ~idx_sew:idx_w ~vreg:d ~mem:m ~idx_vreg:idx)
  | (("vsuxei8.v" | "vsoxei8.v" | "vsuxei16.v" | "vsoxei16.v" | "vsuxei32.v" | "vsoxei32.v" | "vsuxei64.v" | "vsoxei64.v"),
     [ OpReg (Register.Fpr (s, _)); OpMem m; OpReg (Register.Fpr (idx, _)) ]) ->
      let idx_w =
        if String.contains mnemonic '8' then 8
        else if String.contains mnemonic '1' then 16
        else if String.contains mnemonic '3' then 32
        else 64
      in
      Some (lift_indexed_mem ~is_load:false ~sew ~idx_sew:idx_w ~vreg:s ~mem:m ~idx_vreg:idx)

  (* 5. Moves and scalars: vmv.v.v, vmv.v.x, vmv.v.i, vmv.x.s, vmv.s.x *)
  | "vmv.v.v", [ OpReg (Register.Fpr (d, _)); OpReg (Register.Fpr (s, _)) ] ->
      Some (Ok [ Ir.Vec_mov { dst = d; src = s; bits = 128 } ])
  | "vmv.v.x", [ OpReg (Register.Fpr (d, _)); OpReg rs1 ] ->
      Some (Ok [ Ir.Vec_splat { dst = d; src = rs1; bits = 128; lane_bits = sew } ])
  | "vmv.v.i", [ OpReg (Register.Fpr (d, _)); OpImm imm ] ->
      Some (Ok [
        Ir.Mov { dst = Reg Register.vtmp0; src = Imm imm };
        Ir.Vec_splat { dst = d; src = Register.vtmp0; bits = 128; lane_bits = sew };
      ])
  | "vmv.x.s", [ OpReg rd; OpReg (Register.Fpr (s2, _)) ] ->
      let mov = Ir.Mov { dst = Reg rd; src = Reg (Register.Fpr (s2, Register.B64)) } in
      let sext =
        if sew = 32 then
          [
            Ir.Alu { op = Shl; dst = rd; src1 = Reg rd; src2 = Imm 32L; set_flags = false };
            Ir.Alu { op = Sar; dst = rd; src1 = Reg rd; src2 = Imm 32L; set_flags = false };
          ]
        else if sew = 16 then
          [
            Ir.Alu { op = Shl; dst = rd; src1 = Reg rd; src2 = Imm 48L; set_flags = false };
            Ir.Alu { op = Sar; dst = rd; src1 = Reg rd; src2 = Imm 48L; set_flags = false };
          ]
        else if sew = 8 then
          [
            Ir.Alu { op = Shl; dst = rd; src1 = Reg rd; src2 = Imm 56L; set_flags = false };
            Ir.Alu { op = Sar; dst = rd; src1 = Reg rd; src2 = Imm 56L; set_flags = false };
          ]
        else []
      in
      Some (Ok (mov :: sext))
  | "vmv.s.x", [ OpReg (Register.Fpr (vd, _)); OpReg rs1 ] ->
      Some (Ok [ Ir.Mov { dst = Reg (Register.Fpr (vd, elem_w)); src = Reg rs1 } ])

  (* 6. Vector merges: vmerge.vvm, vmerge.vxm, vmerge.vim *)
  | "vmerge.vvm", [ OpReg (Register.Fpr (d, _)); OpReg (Register.Fpr (s2, _)); OpReg (Register.Fpr (s1, _)); mask ] when is_mask_op mask ->
      Some (Ok [
        Ir.Vec_binop { op = Vand; elem = VInt; dst = scratch_vreg; src1 = s1; src2 = 0; bits = 128; lane_bits = sew };
        Ir.Vec_binop { op = Vandn; elem = VInt; dst = scratch_vreg2; src1 = 0; src2 = s2; bits = 128; lane_bits = sew };
        Ir.Vec_binop { op = Vor; elem = VInt; dst = d; src1 = scratch_vreg; src2 = scratch_vreg2; bits = 128; lane_bits = sew };
      ])
  | "vmerge.vxm", [ OpReg (Register.Fpr (d, _)); OpReg (Register.Fpr (s2, _)); OpReg rs1; mask ] when is_mask_op mask ->
      Some (Ok [
        Ir.Vec_splat { dst = scratch_vreg3; src = rs1; bits = 128; lane_bits = sew };
        Ir.Vec_binop { op = Vand; elem = VInt; dst = scratch_vreg; src1 = scratch_vreg3; src2 = 0; bits = 128; lane_bits = sew };
        Ir.Vec_binop { op = Vandn; elem = VInt; dst = scratch_vreg2; src1 = 0; src2 = s2; bits = 128; lane_bits = sew };
        Ir.Vec_binop { op = Vor; elem = VInt; dst = d; src1 = scratch_vreg; src2 = scratch_vreg2; bits = 128; lane_bits = sew };
      ])
  | "vmerge.vim", [ OpReg (Register.Fpr (d, _)); OpReg (Register.Fpr (s2, _)); OpImm imm; mask ] when is_mask_op mask ->
      Some (Ok [
        Ir.Mov { dst = Reg Register.vtmp0; src = Imm imm };
        Ir.Vec_splat { dst = scratch_vreg3; src = Register.vtmp0; bits = 128; lane_bits = sew };
        Ir.Vec_binop { op = Vand; elem = VInt; dst = scratch_vreg; src1 = scratch_vreg3; src2 = 0; bits = 128; lane_bits = sew };
        Ir.Vec_binop { op = Vandn; elem = VInt; dst = scratch_vreg2; src1 = 0; src2 = s2; bits = 128; lane_bits = sew };
        Ir.Vec_binop { op = Vor; elem = VInt; dst = d; src1 = scratch_vreg; src2 = scratch_vreg2; bits = 128; lane_bits = sew };
      ])

  (* 7. Mask logic: vmand, vmor, vmxor, vmnand, vmorn, vmxnor *)
  | "vmand.mm", [ OpReg (Register.Fpr (d, _)); OpReg (Register.Fpr (s2, _)); OpReg (Register.Fpr (s1, _)) ] ->
      Some (Ok [ Ir.Vec_binop { op = Vand; elem = VInt; dst = d; src1 = s2; src2 = s1; bits = 128; lane_bits = 64 } ])
  | "vmor.mm", [ OpReg (Register.Fpr (d, _)); OpReg (Register.Fpr (s2, _)); OpReg (Register.Fpr (s1, _)) ] ->
      Some (Ok [ Ir.Vec_binop { op = Vor; elem = VInt; dst = d; src1 = s2; src2 = s1; bits = 128; lane_bits = 64 } ])
  | "vmxor.mm", [ OpReg (Register.Fpr (d, _)); OpReg (Register.Fpr (s2, _)); OpReg (Register.Fpr (s1, _)) ] ->
      Some (Ok [ Ir.Vec_binop { op = Vxor; elem = VInt; dst = d; src1 = s2; src2 = s1; bits = 128; lane_bits = 64 } ])
  | "vmnand.mm", [ OpReg (Register.Fpr (d, _)); OpReg (Register.Fpr (s2, _)); OpReg (Register.Fpr (s1, _)) ] ->
      Some (Ok [
        Ir.Vec_binop { op = Vand; elem = VInt; dst = scratch_vreg; src1 = s2; src2 = s1; bits = 128; lane_bits = 64 };
        Ir.Vec_binop { op = Vandn; elem = VInt; dst = d; src1 = scratch_vreg; src2 = scratch_vreg; bits = 128; lane_bits = 64 };
      ])
  | "vmorn.mm", [ OpReg (Register.Fpr (d, _)); OpReg (Register.Fpr (s2, _)); OpReg (Register.Fpr (s1, _)) ] ->
      Some (Ok [
        Ir.Vec_binop { op = Vandn; elem = VInt; dst = scratch_vreg; src1 = s1; src2 = s2; bits = 128; lane_bits = 64 };
        Ir.Vec_binop { op = Vor; elem = VInt; dst = d; src1 = s2; src2 = scratch_vreg; bits = 128; lane_bits = 64 };
      ])
  | "vmxnor.mm", [ OpReg (Register.Fpr (d, _)); OpReg (Register.Fpr (s2, _)); OpReg (Register.Fpr (s1, _)) ] ->
      Some (Ok [
        Ir.Vec_binop { op = Vxor; elem = VInt; dst = scratch_vreg; src1 = s2; src2 = s1; bits = 128; lane_bits = 64 };
        Ir.Vec_binop { op = Vandn; elem = VInt; dst = d; src1 = scratch_vreg; src2 = scratch_vreg; bits = 128; lane_bits = 64 };
      ])

  (* 8. Reductions: vredsum, vredmax, vredmin, vredmaxu, vredminu, vredand, vredor, vredxor *)
  | "vredsum.vs", [ OpReg (Register.Fpr (d, _)); OpReg (Register.Fpr (s2, _)); OpReg (Register.Fpr (s1, _)) ] ->
      Some (lift_reduction ~op:Vadd ~vd:d ~vs2:s2 ~vs1:s1)
  | "vredmax.vs", [ OpReg (Register.Fpr (d, _)); OpReg (Register.Fpr (s2, _)); OpReg (Register.Fpr (s1, _)) ] ->
      Some (lift_reduction ~op:Vmax ~vd:d ~vs2:s2 ~vs1:s1)
  | "vredmin.vs", [ OpReg (Register.Fpr (d, _)); OpReg (Register.Fpr (s2, _)); OpReg (Register.Fpr (s1, _)) ] ->
      Some (lift_reduction ~op:Vmin ~vd:d ~vs2:s2 ~vs1:s1)
  | "vredmaxu.vs", [ OpReg (Register.Fpr (d, _)); OpReg (Register.Fpr (s2, _)); OpReg (Register.Fpr (s1, _)) ] ->
      Some (lift_reduction ~op:Vmaxu ~vd:d ~vs2:s2 ~vs1:s1)
  | "vredminu.vs", [ OpReg (Register.Fpr (d, _)); OpReg (Register.Fpr (s2, _)); OpReg (Register.Fpr (s1, _)) ] ->
      Some (lift_reduction ~op:Vminu ~vd:d ~vs2:s2 ~vs1:s1)
  | "vredand.vs", [ OpReg (Register.Fpr (d, _)); OpReg (Register.Fpr (s2, _)); OpReg (Register.Fpr (s1, _)) ] ->
      Some (lift_reduction ~op:Vand ~vd:d ~vs2:s2 ~vs1:s1)
  | "vredor.vs", [ OpReg (Register.Fpr (d, _)); OpReg (Register.Fpr (s2, _)); OpReg (Register.Fpr (s1, _)) ] ->
      Some (lift_reduction ~op:Vor ~vd:d ~vs2:s2 ~vs1:s1)
  | "vredxor.vs", [ OpReg (Register.Fpr (d, _)); OpReg (Register.Fpr (s2, _)); OpReg (Register.Fpr (s1, _)) ] ->
      Some (lift_reduction ~op:Vxor ~vd:d ~vs2:s2 ~vs1:s1)

  (* 9. Slides: vslideup, vslidedown, vslide1up, vslide1down *)
  | "vslidedown.vi", [ OpReg (Register.Fpr (d, _)); OpReg (Register.Fpr (s2, _)); OpImm imm ] ->
      let shift_bytes = (Int64.to_int imm) * (sew / 8) in
      if shift_bytes >= 16 then
        Some (Ok [ Ir.Vec_binop { op = Vxor; elem = VInt; dst = d; src1 = d; src2 = d; bits = 128; lane_bits = sew } ])
      else
        Some (Ok [
          Ir.Vec_binop { op = Vxor; elem = VInt; dst = scratch_vreg; src1 = scratch_vreg; src2 = scratch_vreg; bits = 128; lane_bits = 64 };
          Ir.Vec_ext { dst = d; src1 = s2; src2 = scratch_vreg; imm = shift_bytes; bits = 128 };
        ])
  | "vslidedown.vx", [ OpReg (Register.Fpr (d, _)); OpReg (Register.Fpr (s2, _)); OpReg rs1 ] ->
      Some (Ok [
        Ir.Vec_store { src = s2; addr = { base = Some Register.rsp; index = None; disp = -16L; width = Register.B128; is_signed = false; segment = None }; bits = 128 };
        Ir.Mov { dst = Reg Register.vtmp0; src = Reg rs1 };
        Ir.Alu { op = Imul; dst = Register.vtmp0; src1 = Reg Register.vtmp0; src2 = Imm (Int64.of_int (sew / 8)); set_flags = false };
        Ir.Alu { op = Add; dst = Register.vtmp0; src1 = Reg Register.vtmp0; src2 = Reg Register.rsp; set_flags = false };
        Ir.Alu { op = Add; dst = Register.vtmp0; src1 = Reg Register.vtmp0; src2 = Imm (-16L); set_flags = false };
        Ir.Mov { dst = Reg (Register.with_width Register.vtmp1 elem_w);
                 src = Mem { base = Some Register.vtmp0; index = None; disp = 0L; width = elem_w; is_signed = false; segment = None } };
        Ir.Mov { dst = Reg (Register.Fpr (d, elem_w)); src = Reg (Register.with_width Register.vtmp1 elem_w) };
      ])

  | "vslideup.vi", [ OpReg (Register.Fpr (d, _)); OpReg (Register.Fpr (s2, _)); OpImm imm ] ->
      let cnt = Int64.to_int imm in
      if cnt = 0 then
        Some (Ok [ Ir.Vec_mov { dst = d; src = s2; bits = 128 } ])
      else
        let shift_bytes = cnt * (sew / 8) in
        if shift_bytes >= 16 then
          Some (Ok [ Ir.Nop ])
        else
          Some (Ok [
            Ir.Vec_binop { op = Vxor; elem = VInt; dst = scratch_vreg; src1 = scratch_vreg; src2 = scratch_vreg; bits = 128; lane_bits = 64 };
            Ir.Vec_ext { dst = scratch_vreg2; src1 = scratch_vreg; src2 = s2; imm = 16 - shift_bytes; bits = 128 };
            Ir.Vec_mov { dst = d; src = scratch_vreg2; bits = 128 };
          ])

  | "vslide1up.vx", [ OpReg (Register.Fpr (d, _)); OpReg (Register.Fpr (s2, _)); OpReg rs1 ] ->
      let shift_bytes = sew / 8 in
      Some (Ok [
        Ir.Vec_binop { op = Vxor; elem = VInt; dst = scratch_vreg; src1 = scratch_vreg; src2 = scratch_vreg; bits = 128; lane_bits = 64 };
        Ir.Vec_ext { dst = d; src1 = scratch_vreg; src2 = s2; imm = 16 - shift_bytes; bits = 128 };
        Ir.Mov { dst = Reg (Register.Fpr (d, elem_w)); src = Reg rs1 };
      ])
  | "vslide1down.vx", [ OpReg (Register.Fpr (d, _)); OpReg (Register.Fpr (s2, _)); OpReg rs1 ] ->
      let shift_bytes = sew / 8 in
      let num_lanes = 128 / sew in
      let last_lane_disp = Int64.of_int (-16 + (num_lanes - 1) * (sew / 8)) in
      Some (Ok [
        Ir.Vec_binop { op = Vxor; elem = VInt; dst = scratch_vreg; src1 = scratch_vreg; src2 = scratch_vreg; bits = 128; lane_bits = 64 };
        Ir.Vec_ext { dst = d; src1 = s2; src2 = scratch_vreg; imm = shift_bytes; bits = 128 };
        Ir.Vec_store { src = d; addr = { base = Some Register.rsp; index = None; disp = -16L; width = Register.B128; is_signed = false; segment = None }; bits = 128 };
        Ir.Mov { dst = Mem { base = Some Register.rsp; index = None; disp = last_lane_disp; width = elem_w; is_signed = false; segment = None };
                 src = Reg rs1 };
        Ir.Vec_load { dst = d; addr = { base = Some Register.rsp; index = None; disp = -16L; width = Register.B128; is_signed = false; segment = None }; bits = 128 };
      ])

  (* 10. Permutations: vrgather, vcompress *)
  | "vrgather.vv", [ OpReg (Register.Fpr (d, _)); OpReg (Register.Fpr (s2, _)); OpReg (Register.Fpr (s1, _)) ] ->
      if sew = 8 then
        Some (Ok [ Ir.Vec_binop { op = Vtbl; elem = VInt; dst = d; src1 = s2; src2 = s1; bits = 128; lane_bits = 8 } ])
      else
        let num_lanes = 128 / sew in
        let elem_bytes = sew / 8 in
        let instrs = ref [
          Ir.Vec_store { src = s2; addr = { base = Some Register.rsp; index = None; disp = -16L; width = Register.B128; is_signed = false; segment = None }; bits = 128 };
          Ir.Vec_store { src = s1; addr = { base = Some Register.rsp; index = None; disp = -32L; width = Register.B128; is_signed = false; segment = None }; bits = 128 };
        ] in
        for i = 0 to num_lanes - 1 do
          let disp_idx = Int64.of_int (-32 + i * elem_bytes) in
          let disp_out = Int64.of_int (-48 + i * elem_bytes) in
          let gather_step = [
            Ir.Mov { dst = Reg (Register.with_width Register.vtmp0 elem_w);
                     src = Mem { base = Some Register.rsp; index = None; disp = disp_idx; width = elem_w; is_signed = false; segment = None } };
            Ir.Alu { op = Imul; dst = Register.vtmp0; src1 = Reg Register.vtmp0; src2 = Imm (Int64.of_int elem_bytes); set_flags = false };
            Ir.Alu { op = Add; dst = Register.vtmp0; src1 = Reg Register.vtmp0; src2 = Reg Register.rsp; set_flags = false };
            Ir.Alu { op = Add; dst = Register.vtmp0; src1 = Reg Register.vtmp0; src2 = Imm (-16L); set_flags = false };
            Ir.Mov { dst = Reg (Register.with_width Register.vtmp1 elem_w);
                     src = Mem { base = Some Register.vtmp0; index = None; disp = 0L; width = elem_w; is_signed = false; segment = None } };
            Ir.Mov { dst = Mem { base = Some Register.rsp; index = None; disp = disp_out; width = elem_w; is_signed = false; segment = None };
                     src = Reg (Register.with_width Register.vtmp1 elem_w) };
          ] in
          instrs := !instrs @ gather_step
        done;
        instrs := !instrs @ [
          Ir.Vec_load { dst = d; addr = { base = Some Register.rsp; index = None; disp = -48L; width = Register.B128; is_signed = false; segment = None }; bits = 128 }
        ];
        Some (Ok !instrs)

  | "vrgather.vi", [ OpReg (Register.Fpr (d, _)); OpReg (Register.Fpr (s2, _)); OpImm imm ] ->
      let shift_bytes = (Int64.to_int imm) * (sew / 8) in
      Some (Ok [
        Ir.Vec_binop { op = Vxor; elem = VInt; dst = scratch_vreg; src1 = scratch_vreg; src2 = scratch_vreg; bits = 128; lane_bits = 64 };
        Ir.Vec_ext { dst = scratch_vreg2; src1 = s2; src2 = scratch_vreg; imm = shift_bytes; bits = 128 };
        Ir.Mov { dst = Reg Register.vtmp0; src = Reg (Register.Fpr (scratch_vreg2, elem_w)) };
        Ir.Vec_splat { dst = d; src = Register.vtmp0; bits = 128; lane_bits = sew };
      ])

  | "vrgather.vx", [ OpReg (Register.Fpr (d, _)); OpReg (Register.Fpr (s2, _)); OpReg rs1 ] ->
      Some (Ok [
        Ir.Vec_store { src = s2; addr = { base = Some Register.rsp; index = None; disp = -16L; width = Register.B128; is_signed = false; segment = None }; bits = 128 };
        Ir.Mov { dst = Reg Register.vtmp0; src = Reg rs1 };
        Ir.Alu { op = Imul; dst = Register.vtmp0; src1 = Reg Register.vtmp0; src2 = Imm (Int64.of_int (sew / 8)); set_flags = false };
        Ir.Alu { op = Add; dst = Register.vtmp0; src1 = Reg Register.vtmp0; src2 = Reg Register.rsp; set_flags = false };
        Ir.Alu { op = Add; dst = Register.vtmp0; src1 = Reg Register.vtmp0; src2 = Imm (-16L); set_flags = false };
        Ir.Mov { dst = Reg (Register.with_width Register.vtmp1 elem_w);
                 src = Mem { base = Some Register.vtmp0; index = None; disp = 0L; width = elem_w; is_signed = false; segment = None } };
        Ir.Vec_splat { dst = d; src = Register.vtmp1; bits = 128; lane_bits = sew };
      ])

  | "vcompress.vm", [ OpReg (Register.Fpr (d, _)); OpReg (Register.Fpr (s2, _)); OpReg (Register.Fpr (s1, _)) ] ->
      Some (Ok [
        Ir.Vec_binop { op = Vand; elem = VInt; dst = d; src1 = s2; src2 = s1; bits = 128; lane_bits = sew }
      ])

  (* 11. Reverse subtract: vrsub.vx, vrsub.vi *)
  | "vrsub.vx", [ OpReg (Register.Fpr (d, _)); OpReg (Register.Fpr (s2, _)); OpReg rs1 ] ->
      Some (Ok [
        Ir.Vec_splat { dst = scratch_vreg; src = rs1; bits = 128; lane_bits = sew };
        Ir.Vec_binop { op = Vsub; elem = VInt; dst = d; src1 = scratch_vreg; src2 = s2; bits = 128; lane_bits = sew };
      ])
  | "vrsub.vi", [ OpReg (Register.Fpr (d, _)); OpReg (Register.Fpr (s2, _)); OpImm imm ] ->
      Some (Ok [
        Ir.Mov { dst = Reg Register.vtmp0; src = Imm imm };
        Ir.Vec_splat { dst = scratch_vreg; src = Register.vtmp0; bits = 128; lane_bits = sew };
        Ir.Vec_binop { op = Vsub; elem = VInt; dst = d; src1 = scratch_vreg; src2 = s2; bits = 128; lane_bits = sew };
      ])

  (* 12. Generic vector arithmetic, logic, shifts, min/max, comparisons *)
  | _, _ ->
      let parse_binop_name = function
        | "vadd" -> Some Vadd
        | "vsub" -> Some Vsub
        | "vmul" -> Some Vmul
        | "vdiv" -> Some Vdiv
        | "vdivu" -> Some Vdivu
        | "vrem" -> Some Vrem
        | "vremu" -> Some Vremu
        | "vand" -> Some Vand
        | "vor" -> Some Vor
        | "vxor" -> Some Vxor
        | "vsll" -> Some Vsll
        | "vsrl" -> Some Vsrl
        | "vsra" -> Some Vsra
        | "vmin" -> Some Vmin
        | "vmax" -> Some Vmax
        | "vminu" -> Some Vminu
        | "vmaxu" -> Some Vmaxu
        | "vmseq" -> Some Vcmpeq
        | "vmsne" -> Some Vcmpne
        | "vmslt" -> Some Vcmpgt (* vs2 < vs1 <=> vs1 > vs2 *)
        | "vmsltu" -> Some Vcmpltu
        | "vmsle" -> Some Vcmple
        | "vmsleu" -> Some Vcmpleu
        | _ -> None
      in
      let parts = String.split_on_char '.' mnemonic in
      match parts with
      | [ base_name; kind ] -> (
          match parse_binop_name base_name with
          | Some op -> (
              match kind, ops with
              | "vv", [ OpReg (Register.Fpr (d, _)); OpReg (Register.Fpr (s2, _)); OpReg (Register.Fpr (s1, _)) ] ->
                  let (src1, src2) = if base_name = "vmslt" then (s1, s2) else (s2, s1) in
                  Some (Ok [ Ir.Vec_binop { op; elem = VInt; dst = d; src1; src2; bits = 128; lane_bits = sew } ])
              | "vv", [ OpReg (Register.Fpr (d, _)); OpReg (Register.Fpr (s2, _)); OpReg (Register.Fpr (s1, _)); mask ] when is_mask_op mask ->
                  let (src1, src2) = if base_name = "vmslt" then (s1, s2) else (s2, s1) in
                  let compute = [ Ir.Vec_binop { op; elem = VInt; dst = scratch_vreg3; src1; src2; bits = 128; lane_bits = sew } ] in
                  Some (Ok (apply_mask ~vd:d ~dst:scratch_vreg3 ~sew compute))

              | "vx", [ OpReg (Register.Fpr (d, _)); OpReg (Register.Fpr (s2, _)); OpReg rs1 ] ->
                  let splat = [ Ir.Vec_splat { dst = scratch_vreg; src = rs1; bits = 128; lane_bits = sew } ] in
                  let (src1, src2) = if base_name = "vmslt" then (scratch_vreg, s2) else (s2, scratch_vreg) in
                  let binop = [ Ir.Vec_binop { op; elem = VInt; dst = d; src1; src2; bits = 128; lane_bits = sew } ] in
                  Some (Ok (splat @ binop))
              | "vx", [ OpReg (Register.Fpr (d, _)); OpReg (Register.Fpr (s2, _)); OpReg rs1; mask ] when is_mask_op mask ->
                  let splat = [ Ir.Vec_splat { dst = scratch_vreg; src = rs1; bits = 128; lane_bits = sew } ] in
                  let (src1, src2) = if base_name = "vmslt" then (scratch_vreg, s2) else (s2, scratch_vreg) in
                  let compute = splat @ [ Ir.Vec_binop { op; elem = VInt; dst = scratch_vreg3; src1; src2; bits = 128; lane_bits = sew } ] in
                  Some (Ok (apply_mask ~vd:d ~dst:scratch_vreg3 ~sew compute))

              | "vi", [ OpReg (Register.Fpr (d, _)); OpReg (Register.Fpr (s2, _)); OpImm imm ] ->
                  let load_imm = [
                    Ir.Mov { dst = Reg Register.vtmp0; src = Imm imm };
                    Ir.Vec_splat { dst = scratch_vreg; src = Register.vtmp0; bits = 128; lane_bits = sew };
                  ] in
                  let (src1, src2) = if base_name = "vmslt" then (scratch_vreg, s2) else (s2, scratch_vreg) in
                  let binop = [ Ir.Vec_binop { op; elem = VInt; dst = d; src1; src2; bits = 128; lane_bits = sew } ] in
                  Some (Ok (load_imm @ binop))
              | "vi", [ OpReg (Register.Fpr (d, _)); OpReg (Register.Fpr (s2, _)); OpImm imm; mask ] when is_mask_op mask ->
                  let load_imm = [
                    Ir.Mov { dst = Reg Register.vtmp0; src = Imm imm };
                    Ir.Vec_splat { dst = scratch_vreg; src = Register.vtmp0; bits = 128; lane_bits = sew };
                  ] in
                  let (src1, src2) = if base_name = "vmslt" then (scratch_vreg, s2) else (s2, scratch_vreg) in
                  let compute = load_imm @ [ Ir.Vec_binop { op; elem = VInt; dst = scratch_vreg3; src1; src2; bits = 128; lane_bits = sew } ] in
                  Some (Ok (apply_mask ~vd:d ~dst:scratch_vreg3 ~sew compute))

              | _ -> None)
          | None -> (
              match base_name, kind, ops with
              | "vnot", "v", [ OpReg (Register.Fpr (d, _)); OpReg (Register.Fpr (s, _)) ] ->
                  Some (Ok [
                    Ir.Mov { dst = Reg Register.vtmp0; src = Imm (-1L) };
                    Ir.Vec_splat { dst = scratch_vreg; src = Register.vtmp0; bits = 128; lane_bits = sew };
                    Ir.Vec_binop { op = Vxor; elem = VInt; dst = d; src1 = s; src2 = scratch_vreg; bits = 128; lane_bits = sew };
                  ])
              | "vmsgt", "vx", [ OpReg (Register.Fpr (d, _)); OpReg (Register.Fpr (s2, _)); OpReg rs1 ] ->
                  Some (Ok [
                    Ir.Vec_splat { dst = scratch_vreg; src = rs1; bits = 128; lane_bits = sew };
                    Ir.Vec_binop { op = Vcmpgt; elem = VInt; dst = d; src1 = s2; src2 = scratch_vreg; bits = 128; lane_bits = sew };
                  ])
              | "vmsgt", "vi", [ OpReg (Register.Fpr (d, _)); OpReg (Register.Fpr (s2, _)); OpImm imm ] ->
                  Some (Ok [
                    Ir.Mov { dst = Reg Register.vtmp0; src = Imm imm };
                    Ir.Vec_splat { dst = scratch_vreg; src = Register.vtmp0; bits = 128; lane_bits = sew };
                    Ir.Vec_binop { op = Vcmpgt; elem = VInt; dst = d; src1 = s2; src2 = scratch_vreg; bits = 128; lane_bits = sew };
                  ])
              | "vmsgtu", "vx", [ OpReg (Register.Fpr (d, _)); OpReg (Register.Fpr (s2, _)); OpReg rs1 ] ->
                  Some (Ok [
                    Ir.Vec_splat { dst = scratch_vreg; src = rs1; bits = 128; lane_bits = sew };
                    Ir.Vec_binop { op = Vcmpltu; elem = VInt; dst = d; src1 = scratch_vreg; src2 = s2; bits = 128; lane_bits = sew };
                  ])
              | "vmsgtu", "vi", [ OpReg (Register.Fpr (d, _)); OpReg (Register.Fpr (s2, _)); OpImm imm ] ->
                  Some (Ok [
                    Ir.Mov { dst = Reg Register.vtmp0; src = Imm imm };
                    Ir.Vec_splat { dst = scratch_vreg; src = Register.vtmp0; bits = 128; lane_bits = sew };
                    Ir.Vec_binop { op = Vcmpltu; elem = VInt; dst = d; src1 = scratch_vreg; src2 = s2; bits = 128; lane_bits = sew };
                  ])
              | _ -> None))
      | _ -> None
