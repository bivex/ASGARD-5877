open Vm_ir

let map_gpr_by_index idx width =
  match idx with
  | 0 -> Register.Vreg (Register.VZERO, width)
  | 1 -> Register.Vreg (Register.VTMP3, width)
  | 2 -> Register.Gpr (Register.RSP, width)
  | 3 -> Register.Vreg (Register.VTMP0, width)
  | 4 -> Register.Vreg (Register.VTMP1, width)
  | 5 -> Register.Vreg (Register.VTMP2, width)
  | 6 -> Register.Gpr (Register.R10, width)
  | 7 -> Register.Gpr (Register.R11, width)
  | 8 -> Register.Gpr (Register.RBP, width)
  | 9 -> Register.Gpr (Register.RBX, width)
  | 10 -> Register.Gpr (Register.RAX, width)
  | 11 -> Register.Gpr (Register.RDX, width)
  | 12 -> Register.Gpr (Register.RCX, width)
  | 13 -> Register.Gpr (Register.RSI, width)
  | 14 -> Register.Gpr (Register.RDI, width)
  | 15 -> Register.Gpr (Register.R8, width)
  | 16 -> Register.Gpr (Register.R9, width)
  | 17 -> Register.Gpr (Register.R12, width)
  | 18 -> Register.Vreg (Register.VX18, width)
  | 19 -> Register.Vreg (Register.VX19, width)
  | 20 -> Register.Vreg (Register.VX20, width)
  | 21 -> Register.Vreg (Register.VX21, width)
  | 22 -> Register.Vreg (Register.VX22, width)
  | 23 -> Register.Vreg (Register.VX23, width)
  | 24 -> Register.Vreg (Register.VX24, width)
  | 25 -> Register.Vreg (Register.VX25, width)
  | 26 -> Register.Vreg (Register.VX26, width)
  | 27 -> Register.Gpr (Register.R13, width)
  | 28 -> Register.Gpr (Register.R14, width)
  | 29 -> Register.Gpr (Register.R15, width)
  | 30 -> Register.Vreg (Register.VTMP0, width)
  | 31 -> Register.Vreg (Register.VTMP1, width)
  | _ -> failwith "Invalid RISC-V register index"

let map_riscv_reg ?(width = Register.B64) str =
  let s = String.lowercase_ascii (String.trim str) in
  match s with
  | "zero" | "x0" -> Ok (map_gpr_by_index 0 width)
  | "ra"   | "x1" -> Ok (map_gpr_by_index 1 width)
  | "sp"   | "x2" -> Ok (map_gpr_by_index 2 width)
  | "gp"   | "x3" -> Ok (map_gpr_by_index 3 width)
  | "tp"   | "x4" -> Ok (map_gpr_by_index 4 width)
  | "t0"   | "x5" -> Ok (map_gpr_by_index 5 width)
  | "t1"   | "x6" -> Ok (map_gpr_by_index 6 width)
  | "t2"   | "x7" -> Ok (map_gpr_by_index 7 width)
  | "s0" | "fp" | "x8" -> Ok (map_gpr_by_index 8 width)
  | "s1"   | "x9" -> Ok (map_gpr_by_index 9 width)
  | "a0"   | "x10" -> Ok (map_gpr_by_index 10 width)
  | "a1"   | "x11" -> Ok (map_gpr_by_index 11 width)
  | "a2"   | "x12" -> Ok (map_gpr_by_index 12 width)
  | "a3"   | "x13" -> Ok (map_gpr_by_index 13 width)
  | "a4"   | "x14" -> Ok (map_gpr_by_index 14 width)
  | "a5"   | "x15" -> Ok (map_gpr_by_index 15 width)
  | "a6"   | "x16" -> Ok (map_gpr_by_index 16 width)
  | "a7"   | "x17" -> Ok (map_gpr_by_index 17 width)
  | "s2"   | "x18" -> Ok (map_gpr_by_index 18 width)
  | "s3"   | "x19" -> Ok (map_gpr_by_index 19 width)
  | "s4"   | "x20" -> Ok (map_gpr_by_index 20 width)
  | "s5"   | "x21" -> Ok (map_gpr_by_index 21 width)
  | "s6"   | "x22" -> Ok (map_gpr_by_index 22 width)
  | "s7"   | "x23" -> Ok (map_gpr_by_index 23 width)
  | "s8"   | "x24" -> Ok (map_gpr_by_index 24 width)
  | "s9"   | "x25" -> Ok (map_gpr_by_index 25 width)
  | "s10"  | "x26" -> Ok (map_gpr_by_index 26 width)
  | "s11"  | "x27" -> Ok (map_gpr_by_index 27 width)
  | "t3"   | "x28" -> Ok (map_gpr_by_index 28 width)
  | "t4"   | "x29" -> Ok (map_gpr_by_index 29 width)
  | "t5"   | "x30" -> Ok (map_gpr_by_index 30 width)
  | "t6"   | "x31" -> Ok (map_gpr_by_index 31 width)
  (* Floating-point registers *)
  | s when String.length s >= 2 && s.[0] = 'f' && (s.[1] >= '0' && s.[1] <= '9') -> (
      match int_of_string_opt (String.sub s 1 (String.length s - 1)) with
      | Some i when i >= 0 && i < 32 -> Ok (Register.Fpr (i, width))
      | _ -> Error (Printf.sprintf "Unknown RISC-V register '%s'" str))
  | "ft0" -> Ok (Register.Fpr (0, width))
  | "ft1" -> Ok (Register.Fpr (1, width))
  | "ft2" -> Ok (Register.Fpr (2, width))
  | "ft3" -> Ok (Register.Fpr (3, width))
  | "ft4" -> Ok (Register.Fpr (4, width))
  | "ft5" -> Ok (Register.Fpr (5, width))
  | "ft6" -> Ok (Register.Fpr (6, width))
  | "ft7" -> Ok (Register.Fpr (7, width))
  | "fs0" -> Ok (Register.Fpr (8, width))
  | "fs1" -> Ok (Register.Fpr (9, width))
  | "fa0" -> Ok (Register.Fpr (10, width))
  | "fa1" -> Ok (Register.Fpr (11, width))
  | "fa2" -> Ok (Register.Fpr (12, width))
  | "fa3" -> Ok (Register.Fpr (13, width))
  | "fa4" -> Ok (Register.Fpr (14, width))
  | "fa5" -> Ok (Register.Fpr (15, width))
  | "fa6" -> Ok (Register.Fpr (16, width))
  | "fa7" -> Ok (Register.Fpr (17, width))
  | "fs2" -> Ok (Register.Fpr (18, width))
  | "fs3" -> Ok (Register.Fpr (19, width))
  | "fs4" -> Ok (Register.Fpr (20, width))
  | "fs5" -> Ok (Register.Fpr (21, width))
  | "fs6" -> Ok (Register.Fpr (22, width))
  | "fs7" -> Ok (Register.Fpr (23, width))
  | "fs8" -> Ok (Register.Fpr (24, width))
  | "fs9" -> Ok (Register.Fpr (25, width))
  | "fs10" -> Ok (Register.Fpr (26, width))
  | "fs11" -> Ok (Register.Fpr (27, width))
  | "ft8" -> Ok (Register.Fpr (28, width))
  | "ft9" -> Ok (Register.Fpr (29, width))
  | "ft10" -> Ok (Register.Fpr (30, width))
  | "ft11" -> Ok (Register.Fpr (31, width))
  (* Vector registers v0-v31 *)
  | s when String.length s >= 2 && s.[0] = 'v' && (s.[1] >= '0' && s.[1] <= '9') -> (
      match int_of_string_opt (String.sub s 1 (String.length s - 1)) with
      | Some i when i >= 0 && i < 32 -> Ok (Register.Fpr (i, width))
      | _ -> Error (Printf.sprintf "Unknown RISC-V register '%s'" str))
  | _ -> Error (Printf.sprintf "Unknown RISC-V register '%s'" str)

let reg_to_vreg_index = function
  | Register.Fpr (i, _) -> Some i
  | _ -> None

let parse_imm str =
  let s = String.trim str in
  let s = if String.starts_with ~prefix:"#" s then String.sub s 1 (String.length s - 1) else s in
  let s = if String.starts_with ~prefix:"$" s then String.sub s 1 (String.length s - 1) else s in
  if String.contains s '@' || String.starts_with ~prefix:"_" s ||
     String.starts_with ~prefix:"L" s || String.starts_with ~prefix:"." s then
    Error (Printf.sprintf "Not an immediate: %s" s)
  else
    try
      Ok (Int64.of_string s)
    with _ -> Error (Printf.sprintf "Invalid immediate '%s'" str)
