open Vm_ir
open Arm64_types
open Arm64_common

let get_vec_info = function
  | OpVec { reg; bits; lane_bits; lane_idx } -> Some (reg, bits, lane_bits, lane_idx)
  | OpReg (Register.Fpr (reg, width)) ->
      let (bits, lane_bits) =
        match width with
        | Register.B128 -> (128, 64)
        | Register.B64 -> (64, 64)
        | Register.B32 -> (32, 32)
        | Register.B16 -> (16, 16)
        | Register.B8 -> (8, 8)
        | _ -> (128, 64)
      in
      Some (reg, bits, lane_bits, None)
  | _ -> None

let lift (mnemonic : string) (ops : raw_op list) : Ir.instr list option =
  let mnem = String.lowercase_ascii mnemonic in
  match (mnem, ops) with
  (* Basic arithmetic vector binops: add, sub, mul *)
  | (("add" | "sub" | "mul"), [ op_dst; op_s1; op_s2 ]) -> (
      match get_vec_info op_dst, get_vec_info op_s1, get_vec_info op_s2 with
      | Some (dst, bits, lane_bits, _), Some (s1, _, _, _), Some (s2, _, _, _) ->
          let op = match mnem with "add" -> Ir.Vadd | "sub" -> Ir.Vsub | "mul" -> Ir.Vmul | _ -> assert false in
          Some [ Ir.Vec_binop { op; elem = Ir.VInt; dst; src1 = s1; src2 = s2; bits; lane_bits } ]
      | _ -> None)

  (* Bitwise vector logic: and, orr, eor *)
  | (("and" | "orr" | "eor"), [ op_dst; op_s1; op_s2 ]) -> (
      match get_vec_info op_dst, get_vec_info op_s1, get_vec_info op_s2 with
      | Some (dst, bits, lane_bits, _), Some (s1, _, _, _), Some (s2, _, _, _) ->
          let op = match mnem with "and" -> Ir.Vand | "orr" -> Ir.Vor | "eor" -> Ir.Vxor | _ -> assert false in
          Some [ Ir.Vec_binop { op; elem = Ir.VInt; dst; src1 = s1; src2 = s2; bits; lane_bits } ]
      | _ -> None)

  (* Bitwise Bit Clear: bic dst, s1, s2 is (s1 & ~s2) *)
  | ("bic", [ op_dst; op_s1; op_s2 ]) -> (
      match get_vec_info op_dst, get_vec_info op_s1, get_vec_info op_s2 with
      | Some (dst, bits, lane_bits, _), Some (s1, _, _, _), Some (s2, _, _, _) ->
          Some [ Ir.Vec_binop { op = Ir.Vandn; elem = Ir.VInt; dst; src1 = s2; src2 = s1; bits; lane_bits } ]
      | _ -> None)

  (* Vector shifts with immediate *)
  | (("shl" | "sshr" | "ushr"), [ op_dst; op_s1; OpImm imm ]) -> (
      match get_vec_info op_dst, get_vec_info op_s1 with
      | Some (dst, bits, lane_bits, _), Some (s1, _, _, _) ->
          let op = match mnem with "shl" -> Ir.Vsll | "sshr" -> Ir.Vsra | "ushr" -> Ir.Vsrl | _ -> assert false in
          Some [ Ir.Vec_imm { op; elem = Ir.VInt; dst; src = s1; imm; bits; lane_bits } ]
      | _ -> None)

  (* Vector shifts with register *)
  | (("shl" | "sshr" | "ushr"), [ op_dst; op_s1; op_s2 ]) -> (
      match get_vec_info op_dst, get_vec_info op_s1, get_vec_info op_s2 with
      | Some (dst, bits, lane_bits, _), Some (s1, _, _, _), Some (s2, _, _, _) ->
          let op = match mnem with "shl" -> Ir.Vsll | "sshr" -> Ir.Vsra | "ushr" -> Ir.Vsrl | _ -> assert false in
          Some [ Ir.Vec_binop { op; elem = Ir.VInt; dst; src1 = s1; src2 = s2; bits; lane_bits } ]
      | _ -> None)

  (* Vector min / max: smin, smax, umin, umax *)
  | (("smin" | "smax" | "umin" | "umax"), [ op_dst; op_s1; op_s2 ]) -> (
      match get_vec_info op_dst, get_vec_info op_s1, get_vec_info op_s2 with
      | Some (dst, bits, lane_bits, _), Some (s1, _, _, _), Some (s2, _, _, _) ->
          let op = match mnem with
            | "smin" -> Ir.Vmin
            | "smax" -> Ir.Vmax
            | "umin" -> Ir.Vminu
            | "umax" -> Ir.Vmaxu
            | _ -> assert false
          in
          Some [ Ir.Vec_binop { op; elem = Ir.VInt; dst; src1 = s1; src2 = s2; bits; lane_bits } ]
      | _ -> None)

  (* Absolute value *)
  | ("abs", [ op_dst; op_s1 ]) -> (
      match get_vec_info op_dst, get_vec_info op_s1 with
      | Some (dst, bits, lane_bits, _), Some (s1, _, _, _) ->
          Some [ Ir.Vec_binop { op = Ir.Vabs; elem = Ir.VInt; dst; src1 = s1; src2 = s1; bits; lane_bits } ]
      | _ -> None)

  (* Vector move between vectors *)
  | ("mov", [ op_dst; op_src ]) when (match get_vec_info op_dst, get_vec_info op_src with Some _, Some _ -> true | _ -> false) -> (
      match get_vec_info op_dst, get_vec_info op_src with
      | Some (dst, bits, _, _), Some (src, _, _, _) ->
          Some [ Ir.Vec_mov { dst; src; bits } ]
      | _ -> None)

  (* Vector move between GPR and vector lane 0 *)
  | ("mov", [ OpReg dst; op_src ]) -> (
      match get_vec_info op_src with
      | Some (src, _, _, lane_idx) ->
          let idx = Option.value ~default:0 lane_idx in
          if idx = 0 then
            Some [ Ir.Mov { dst = Reg dst; src = Reg (Register.Fpr (src, Register.get_width dst)) } ]
          else None
      | _ -> None)
  | ("mov", [ op_dst; OpReg src ]) -> (
      match get_vec_info op_dst with
      | Some (dst, _, _, lane_idx) ->
          let idx = Option.value ~default:0 lane_idx in
          if idx = 0 then
            Some [ Ir.Mov { dst = Reg (Register.Fpr (dst, Register.get_width src)); src = Reg src } ]
          else None
      | _ -> None)

  (* Vector duplicate / splat *)
  | ("dup", [ op_dst; OpReg scalar_src ]) -> (
      match get_vec_info op_dst with
      | Some (dst, bits, lane_bits, _) ->
          Some [ Ir.Vec_splat { dst; src = scalar_src; bits; lane_bits } ]
      | _ -> None)
  | ("dup", [ op_dst; op_src ]) -> (
      match get_vec_info op_dst, get_vec_info op_src with
      | Some (dst, bits, lane_bits, _), Some (src, _, _, _) ->
          Some [ Ir.Vec_splat { dst; src = Register.Fpr (src, Register.B64); bits; lane_bits } ]
      | _ -> None)

  (* NEON Permutations and Interleaving: zip1, zip2, uzp1, uzp2, trn1, trn2 *)
  | (("zip1" | "zip2"), [ op_dst; op_s1; op_s2 ]) -> (
      match get_vec_info op_dst, get_vec_info op_s1, get_vec_info op_s2 with
      | Some (dst, bits, lane_bits, _), Some (s1, _, _, _), Some (s2, _, _, _) ->
          let op = if mnem = "zip1" then Ir.Vunpckl else Ir.Vunpckh in
          Some [ Ir.Vec_binop { op; elem = Ir.VInt; dst; src1 = s1; src2 = s2; bits; lane_bits } ]
      | _ -> None)

  | (("uzp1" | "uzp2"), [ op_dst; op_s1; op_s2 ]) -> (
      match get_vec_info op_dst, get_vec_info op_s1, get_vec_info op_s2 with
      | Some (dst, bits, lane_bits, _), Some (s1, _, _, _), Some (s2, _, _, _) ->
          let op = if mnem = "uzp1" then Ir.Vuzp1 else Ir.Vuzp2 in
          Some [ Ir.Vec_binop { op; elem = Ir.VInt; dst; src1 = s1; src2 = s2; bits; lane_bits } ]
      | _ -> None)

  | (("trn1" | "trn2"), [ op_dst; op_s1; op_s2 ]) -> (
      match get_vec_info op_dst, get_vec_info op_s1, get_vec_info op_s2 with
      | Some (dst, bits, lane_bits, _), Some (s1, _, _, _), Some (s2, _, _, _) ->
          let op = if mnem = "trn1" then Ir.Vtrn1 else Ir.Vtrn2 in
          Some [ Ir.Vec_binop { op; elem = Ir.VInt; dst; src1 = s1; src2 = s2; bits; lane_bits } ]
      | _ -> None)

  (* Table lookup: tbl, tbx *)
  | (("tbl" | "tbx"), [ op_dst; op_table; op_idx ]) -> (
      match get_vec_info op_dst, get_vec_info op_table, get_vec_info op_idx with
      | Some (dst, bits, _, _), Some (s_tbl, _, _, _), Some (s_idx, _, _, _) ->
          let op = if mnem = "tbl" then Ir.Vtbl else Ir.Vtbx in
          Some [ Ir.Vec_binop { op; elem = Ir.VInt; dst; src1 = s_tbl; src2 = s_idx; bits; lane_bits = 8 } ]
      | _ -> None)

  (* Vector extract: ext *)
  | ("ext", [ op_dst; op_s1; op_s2; OpImm imm ]) -> (
      match get_vec_info op_dst, get_vec_info op_s1, get_vec_info op_s2 with
      | Some (dst, bits, _, _), Some (s1, _, _, _), Some (s2, _, _, _) ->
          Some [ Ir.Vec_ext { dst; src1 = s1; src2 = s2; imm = Int64.to_int imm; bits } ]
      | _ -> None)

  (* Vector loads: ld1, ldr (when vector target) *)
  | (("ld1" | "ldr"), [ op_dst; OpMem m ]) -> (
      match get_vec_info op_dst with
      | Some (dst, bits, _, _) ->
          let scratch = Register.vtmp0 in
          let (m, addr_prep) = lower_mem_operand ~scratch_reg:scratch m in
          let (pre_step, effective_disp) =
            match m.wb with
            | WbPre ->
                (match m.base with
                | Some base_reg ->
                    ([ Ir.Alu { op = Add; dst = base_reg; src1 = Reg base_reg; src2 = Imm m.disp; set_flags = false } ], 0L)
                | None -> ([], m.disp))
            | _ -> ([], m.disp)
          in
          let ir_mem = {
            Ir.base = m.base;
            index = m.index;
            disp = effective_disp;
            width = Register.B64;
            is_signed = false;
            segment = None;
          } in
          let load_instr = Ir.Vec_load { dst; addr = ir_mem; bits } in
          let post_step =
            match m.wb with
            | WbPost post_imm ->
                (match m.base with
                | Some base_reg -> [ Ir.Alu { op = Add; dst = base_reg; src1 = Reg base_reg; src2 = Imm post_imm; set_flags = false } ]
                | None -> [])
            | _ -> []
          in
          Some (addr_prep @ pre_step @ [ load_instr ] @ post_step)
      | _ -> None)

  (* Vector stores: st1, str (when vector source) *)
  | (("st1" | "str"), [ op_src; OpMem m ]) -> (
      match get_vec_info op_src with
      | Some (src, bits, _, _) ->
          let scratch = Register.vtmp0 in
          let (m, addr_prep) = lower_mem_operand ~scratch_reg:scratch m in
          let (pre_step, effective_disp) =
            match m.wb with
            | WbPre ->
                (match m.base with
                | Some base_reg ->
                    ([ Ir.Alu { op = Add; dst = base_reg; src1 = Reg base_reg; src2 = Imm m.disp; set_flags = false } ], 0L)
                | None -> ([], m.disp))
            | _ -> ([], m.disp)
          in
          let ir_mem = {
            Ir.base = m.base;
            index = m.index;
            disp = effective_disp;
            width = Register.B64;
            is_signed = false;
            segment = None;
          } in
          let store_instr = Ir.Vec_store { src; addr = ir_mem; bits } in
          let post_step =
            match m.wb with
            | WbPost post_imm ->
                (match m.base with
                | Some base_reg -> [ Ir.Alu { op = Add; dst = base_reg; src1 = Reg base_reg; src2 = Imm post_imm; set_flags = false } ]
                | None -> [])
            | _ -> []
          in
          Some (addr_prep @ pre_step @ [ store_instr ] @ post_step)
      | _ -> None)

  | _ -> None
