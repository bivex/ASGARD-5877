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
let normalize_mnemonic m =
  let m_low = String.lowercase_ascii m in
  match String.split_on_char '.' m_low with
  | [ base; suf ] -> (base, Some suf)
  | _ -> (m_low, None)

let vec_dims_of_suffix = function
  | "16b" -> Some (128, 8)
  | "8b"  -> Some (64, 8)
  | "8h"  -> Some (128, 16)
  | "4h"  -> Some (64, 16)
  | "4s"  -> Some (128, 32)
  | "2s"  -> Some (64, 32)
  | "2d"  -> Some (128, 64)
  | "1d" | "d" -> Some (64, 64)
  | "s"   -> Some (32, 32)
  | "h"   -> Some (16, 16)
  | "b"   -> Some (8, 8)
  | "q"   -> Some (128, 128)
  | _ -> None

let apply_suffix_to_ops suf ops =
  match vec_dims_of_suffix suf with
  | None -> ops
  | Some (s_bits, s_lane_bits) ->
      List.map (function
        | OpVec v -> OpVec { v with bits = s_bits; lane_bits = s_lane_bits }
        | other -> other
      ) ops


let lift (mnemonic : string) (ops : raw_op list) : Ir.instr list option =
  let (base_mnem, suf_opt) = normalize_mnemonic mnemonic in
  let ops = match suf_opt with Some s -> apply_suffix_to_ops s ops | None -> ops in
  let mnem = base_mnem in
  match (mnem, ops) with
  | (("add" | "sub" | "mul" | "sqadd" | "sqsub" | "sqrdmulh"), [ op_dst; op_s1; op_s2 ]) -> (
      match get_vec_info op_dst, get_vec_info op_s1, get_vec_info op_s2 with
      | Some (dst, bits, lane_bits, _), Some (s1, _, _, _), Some (s2, _, _, _) ->
          let op = match mnem with
            | "add" -> Ir.Vadd
            | "sub" -> Ir.Vsub
            | "mul" -> Ir.Vmul
            | "sqadd" -> Ir.Vsqadd
            | "sqsub" -> Ir.Vsqsub
            | "sqrdmulh" -> Ir.Vsqrdmulh
            | _ -> assert false
          in
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

  (* Vector element-to-element insert: ins Vd.T[i], Vn.T[j] or mov Vd.T[i], Vn.T[j] *)
  | (("ins" | "mov"), [ op_dst; op_src ]) when (match get_vec_info op_dst, get_vec_info op_src with
      | Some (_, _, _, Some _), Some (_, _, _, Some _) -> true
      | _ -> false) -> (
      match get_vec_info op_dst, get_vec_info op_src with
      | Some (dst, _, dst_lane_bits, Some dst_idx), Some (src, _, _, Some src_idx) ->
          let width = match dst_lane_bits with
            | 8 -> Register.B8
            | 16 -> Register.B16
            | 32 -> Register.B32
            | 64 -> Register.B64
            | _ -> Register.B64
          in
          let tmp = Register.with_width Register.vtmp0 width in
          Some [
            Ir.Pextr { dst = Ir.Reg tmp; src; imm = src_idx; width };
            Ir.Pinsr { dst; src1 = dst; src2 = Ir.Reg tmp; imm = dst_idx; width };
          ]
      | _ -> None)

  (* Vector element insert: ins Vd.T[i], Wn/Xn or mov Vd.T[i], Wn/Xn *)
  | (("ins" | "mov"), [ op_dst; OpReg src ]) -> (
      match get_vec_info op_dst with
      | Some (dst, _, lane_bits, lane_idx) ->
          let idx = Option.value ~default:0 lane_idx in
          let width = match lane_bits with
            | 8 -> Register.B8
            | 16 -> Register.B16
            | 32 -> Register.B32
            | 64 -> Register.B64
            | _ -> Register.get_width src
          in
          Some [ Ir.Pinsr { dst; src1 = dst; src2 = Ir.Reg src; imm = idx; width } ]
      | _ -> None)

  (* Vector unsigned move / extract: umov Wd, Vn.T[i] or mov Wd, Vn.T[i] *)
  | (("umov" | "mov"), [ OpReg dst; op_src ]) -> (
      match get_vec_info op_src with
      | Some (src, _, lane_bits, Some idx) ->
          let width = match lane_bits with
            | 8 -> Register.B8
            | 16 -> Register.B16
            | 32 -> Register.B32
            | 64 -> Register.B64
            | _ -> Register.get_width dst
          in
          Some [ Ir.Pextr { dst = Ir.Reg dst; src; imm = idx; width } ]
      | Some (src, _, _, None) ->
          Some [ Ir.Mov { dst = Reg dst; src = Reg (Register.Fpr (src, Register.get_width dst)) } ]
      | _ -> None)

  (* Vector signed move / extract: smov Wd/Xd, Vn.T[i] *)
  | ("smov", [ OpReg dst; op_src ]) -> (
      match get_vec_info op_src with
      | Some (src, _, lane_bits, Some idx) ->
          let width = match lane_bits with
            | 8 -> Register.B8
            | 16 -> Register.B16
            | 32 -> Register.B32
            | 64 -> Register.B64
            | _ -> Register.get_width dst
          in
          let dst_bits = Register.width_to_bits (Register.get_width dst) in
          let shift = Int64.of_int (dst_bits - lane_bits) in
          if shift > 0L then
            Some [
              Ir.Pextr { dst = Ir.Reg dst; src; imm = idx; width };
              Ir.Alu { op = Shl; dst; src1 = Reg dst; src2 = Imm shift; set_flags = false };
              Ir.Alu { op = Sar; dst; src1 = Reg dst; src2 = Imm shift; set_flags = false };
            ]
          else
            Some [ Ir.Pextr { dst = Ir.Reg dst; src; imm = idx; width } ]
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

  (* Vector Immediate Move: movi, movi.2d, movi.16b, movi.4s, etc. *)
  | (m, [ op_dst; OpImm imm ]) when String.starts_with ~prefix:"movi" m -> (
      match get_vec_info op_dst with
      | Some (dst, bits, lane_bits, _) ->
          let (bits, lane_bits) =
            if String.contains m '.' then
              let parts = String.split_on_char '.' m in
              match List.nth_opt parts 1 with
              | Some "16b" -> (128, 8)
              | Some "8b" -> (64, 8)
              | Some "8h" -> (128, 16)
              | Some "4h" -> (64, 16)
              | Some "4s" -> (128, 32)
              | Some "2s" -> (64, 32)
              | Some "2d" -> (128, 64)
              | Some ("1d" | "d") -> (64, 64)
              | _ -> (bits, lane_bits)
            else (bits, lane_bits)
          in
          if imm = 0L then
            Some [ Ir.Vec_splat { dst; src = Register.Vreg (Register.VZERO, Register.B64); bits; lane_bits } ]
          else
            let t_reg = Register.Vreg (Register.VTMP0, Register.B64) in
            Some [
              Ir.Mov { dst = Reg t_reg; src = Imm imm };
              Ir.Vec_splat { dst; src = t_reg; bits; lane_bits }
            ]
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
  | (("ld1" | "ldr" | "ldur"), [ op_dst; OpMem m ]) -> (
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
  | (("st1" | "str" | "stur"), [ op_src; OpMem m ]) -> (
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
