open Vm_ir

let map_arm64_reg str =
  let s = String.lowercase_ascii (String.trim str) in
  match s with
  (* 64-bit general purpose registers *)
  | "x0"  | "r0"  -> Ok (Register.Gpr (Register.RAX, Register.B64))
  | "x1"  | "r1"  -> Ok (Register.Gpr (Register.RCX, Register.B64))
  | "x2"  | "r2"  -> Ok (Register.Gpr (Register.RDX, Register.B64))
  | "x3"  | "r3"  -> Ok (Register.Gpr (Register.RBX, Register.B64))
  | "x4"  | "r4"  -> Ok (Register.Gpr (Register.RSI, Register.B64))
  | "x5"  | "r5"  -> Ok (Register.Gpr (Register.RDI, Register.B64))
  | "x6"  | "r6"  -> Ok (Register.Gpr (Register.R8,  Register.B64))
  | "x7"  | "r7"  -> Ok (Register.Gpr (Register.R9,  Register.B64))
  | "x8"  | "r8"  -> Ok (Register.Gpr (Register.R10, Register.B64))
  | "x9"  | "r9"  -> Ok (Register.Gpr (Register.R11, Register.B64))
  | "x10" | "r10" -> Ok (Register.Gpr (Register.R12, Register.B64))
  | "x11" | "r11" -> Ok (Register.Gpr (Register.R13, Register.B64))
  | "x12" | "r12" -> Ok (Register.Gpr (Register.R14, Register.B64))
  | "x13" | "r13" -> Ok (Register.Gpr (Register.R15, Register.B64))
  | "x14" -> Ok (Register.Vreg (Register.VTMP0, Register.B64))
  | "x15" -> Ok (Register.Vreg (Register.VTMP1, Register.B64))
  | "x16" | "x17" -> Ok (Register.Vreg (Register.VTMP2, Register.B64))
  | "x18" -> Ok (Register.Vreg (Register.VX18, Register.B64))
  | "x19" -> Ok (Register.Vreg (Register.VX19, Register.B64))
  | "x20" -> Ok (Register.Vreg (Register.VX20, Register.B64))
  | "x21" -> Ok (Register.Vreg (Register.VX21, Register.B64))
  | "x22" -> Ok (Register.Vreg (Register.VX22, Register.B64))
  | "x23" -> Ok (Register.Vreg (Register.VX23, Register.B64))
  | "x24" -> Ok (Register.Vreg (Register.VX24, Register.B64))
  | "x25" -> Ok (Register.Vreg (Register.VX25, Register.B64))
  | "x26" | "x27" | "x28" -> Ok (Register.Vreg (Register.VX26, Register.B64))
  | "x29" | "fp"  -> Ok (Register.Gpr (Register.RBP, Register.B64))
  | "x30" | "lr"  -> Ok (Register.Vreg (Register.VTMP3, Register.B64))
  | "sp"  | "wsp" -> Ok (Register.Gpr (Register.RSP, Register.B64))
  | "xzr"         -> Ok (Register.Vreg (Register.VZERO, Register.B64))
  
  (* 32-bit registers *)
  | "w0"  -> Ok (Register.Gpr (Register.RAX, Register.B32))
  | "w1"  -> Ok (Register.Gpr (Register.RCX, Register.B32))
  | "w2"  -> Ok (Register.Gpr (Register.RDX, Register.B32))
  | "w3"  -> Ok (Register.Gpr (Register.RBX, Register.B32))
  | "w4"  -> Ok (Register.Gpr (Register.RSI, Register.B32))
  | "w5"  -> Ok (Register.Gpr (Register.RDI, Register.B32))
  | "w6"  -> Ok (Register.Gpr (Register.R8,  Register.B32))
  | "w7"  -> Ok (Register.Gpr (Register.R9,  Register.B32))
  | "w8"  -> Ok (Register.Gpr (Register.R10, Register.B32))
  | "w9"  -> Ok (Register.Gpr (Register.R11, Register.B32))
  | "w10" -> Ok (Register.Gpr (Register.R12, Register.B32))
  | "w11" -> Ok (Register.Gpr (Register.R13, Register.B32))
  | "w12" -> Ok (Register.Gpr (Register.R14, Register.B32))
  | "w13" -> Ok (Register.Gpr (Register.R15, Register.B32))
  | "w14" -> Ok (Register.Vreg (Register.VTMP0, Register.B32))
  | "w15" -> Ok (Register.Vreg (Register.VTMP1, Register.B32))
  | "w16" | "w17" -> Ok (Register.Vreg (Register.VTMP2, Register.B32))
  | "w18" -> Ok (Register.Vreg (Register.VX18, Register.B32))
  | "w19" -> Ok (Register.Vreg (Register.VX19, Register.B32))
  | "w20" -> Ok (Register.Vreg (Register.VX20, Register.B32))
  | "w21" -> Ok (Register.Vreg (Register.VX21, Register.B32))
  | "w22" -> Ok (Register.Vreg (Register.VX22, Register.B32))
  | "w23" -> Ok (Register.Vreg (Register.VX23, Register.B32))
  | "w24" -> Ok (Register.Vreg (Register.VX24, Register.B32))
  | "w25" -> Ok (Register.Vreg (Register.VX25, Register.B32))
  | "w26" | "w27" | "w28" -> Ok (Register.Vreg (Register.VX26, Register.B32))
  | "w29" -> Ok (Register.Gpr (Register.RBP, Register.B32))
  | "w30" -> Ok (Register.Vreg (Register.VTMP3, Register.B32))
  | "wzr" -> Ok (Register.Vreg (Register.VZERO, Register.B32))
  | s when String.length s >= 2 && s.[0] = 'd' -> (
      match int_of_string_opt (String.sub s 1 (String.length s - 1)) with
      | Some i when i >= 0 && i < 32 -> Ok (Register.Fpr (i, Register.B64))
      | _ -> Error (Printf.sprintf "Unknown ARM64 register '%s'" str))
  | s when String.length s >= 2 && s.[0] = 's' && s <> "sp" && s <> "si" -> (
      match int_of_string_opt (String.sub s 1 (String.length s - 1)) with
      | Some i when i >= 0 && i < 32 -> Ok (Register.Fpr (i, Register.B32))
      | _ -> Error (Printf.sprintf "Unknown ARM64 register '%s'" str))
  | _ -> Error (Printf.sprintf "Unknown ARM64 register '%s'" str)

let parse_imm str =
  let s = String.trim str in
  let s = if String.starts_with ~prefix:"#" s then String.sub s 1 (String.length s - 1) else s in
  if String.contains s '@' || String.starts_with ~prefix:"_" s ||
     String.starts_with ~prefix:"L" s || String.starts_with ~prefix:"." s then
    Error (Printf.sprintf "Not an immediate: %s" s)
  else
    try
      if String.starts_with ~prefix:"0x" (String.lowercase_ascii s) ||
         String.starts_with ~prefix:"-0x" (String.lowercase_ascii s) then
        Ok (Int64.of_string s)
      else
        Ok (Int64.of_string s)
    with _ -> Error (Printf.sprintf "Invalid immediate '%s'" str)
