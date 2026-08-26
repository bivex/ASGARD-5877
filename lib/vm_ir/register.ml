type width =
  | B8
  | B16
  | B32
  | B64

let width_to_bytes = function
  | B8 -> 1
  | B16 -> 2
  | B32 -> 4
  | B64 -> 8

let width_to_bits = function
  | B8 -> 8
  | B16 -> 16
  | B32 -> 32
  | B64 -> 64

type gpr =
  | RAX
  | RCX
  | RDX
  | RBX
  | RSP
  | RBP
  | RSI
  | RDI
  | R8
  | R9
  | R10
  | R11
  | R12
  | R13
  | R14
  | R15

type vreg =
  | VIP
  | VSP
  | VKEY
  | VTMP0
  | VTMP1
  | VTMP2
  | VTMP3

type t =
  | Gpr of gpr * width
  | Vreg of vreg * width

let rax = Gpr (RAX, B64)
let rcx = Gpr (RCX, B64)
let rdx = Gpr (RDX, B64)
let rbx = Gpr (RBX, B64)
let rsp = Gpr (RSP, B64)
let rbp = Gpr (RBP, B64)
let rsi = Gpr (RSI, B64)
let rdi = Gpr (RDI, B64)
let r8  = Gpr (R8,  B64)
let r9  = Gpr (R9,  B64)
let r10 = Gpr (R10, B64)
let r11 = Gpr (R11, B64)
let r12 = Gpr (R12, B64)
let r13 = Gpr (R13, B64)
let r14 = Gpr (R14, B64)
let r15 = Gpr (R15, B64)

let vip   = Vreg (VIP,   B64)
let vsp   = Vreg (VSP,   B64)
let vkey  = Vreg (VKEY,  B64)
let vtmp0 = Vreg (VTMP0, B64)
let vtmp1 = Vreg (VTMP1, B64)
let vtmp2 = Vreg (VTMP2, B64)
let vtmp3 = Vreg (VTMP3, B64)

let gpr_to_string g w =
  match g, w with
  | RAX, B64 -> "rax" | RAX, B32 -> "eax"  | RAX, B16 -> "ax"   | RAX, B8 -> "al"
  | RCX, B64 -> "rcx" | RCX, B32 -> "ecx"  | RCX, B16 -> "cx"   | RCX, B8 -> "cl"
  | RDX, B64 -> "rdx" | RDX, B32 -> "edx"  | RDX, B16 -> "dx"   | RDX, B8 -> "dl"
  | RBX, B64 -> "rbx" | RBX, B32 -> "ebx"  | RBX, B16 -> "bx"   | RBX, B8 -> "bl"
  | RSP, B64 -> "rsp" | RSP, B32 -> "esp"  | RSP, B16 -> "sp"   | RSP, B8 -> "spl"
  | RBP, B64 -> "rbp" | RBP, B32 -> "ebp"  | RBP, B16 -> "bp"   | RBP, B8 -> "bpl"
  | RSI, B64 -> "rsi" | RSI, B32 -> "esi"  | RSI, B16 -> "si"   | RSI, B8 -> "sil"
  | RDI, B64 -> "rdi" | RDI, B32 -> "edi"  | RDI, B16 -> "di"   | RDI, B8 -> "dil"
  | R8,  B64 -> "r8"  | R8,  B32 -> "r8d"  | R8,  B16 -> "r8w"  | R8,  B8 -> "r8b"
  | R9,  B64 -> "r9"  | R9,  B32 -> "r9d"  | R9,  B16 -> "r9w"  | R9,  B8 -> "r9b"
  | R10, B64 -> "r10" | R10, B32 -> "r10d" | R10, B16 -> "r10w" | R10, B8 -> "r10b"
  | R11, B64 -> "r11" | R11, B32 -> "r11d" | R11, B16 -> "r11w" | R11, B8 -> "r11b"
  | R12, B64 -> "r12" | R12, B32 -> "r12d" | R12, B16 -> "r12w" | R12, B8 -> "r12b"
  | R13, B64 -> "r13" | R13, B32 -> "r13d" | R13, B16 -> "r13w" | R13, B8 -> "r13b"
  | R14, B64 -> "r14" | R14, B32 -> "r14d" | R14, B16 -> "r14w" | R14, B8 -> "r14b"
  | R15, B64 -> "r15" | R15, B32 -> "r15d" | R15, B16 -> "r15w" | R15, B8 -> "r15b"

let vreg_to_string v w =
  let prefix = match v with
    | VIP -> "vip"
    | VSP -> "vsp"
    | VKEY -> "vkey"
    | VTMP0 -> "vtmp0"
    | VTMP1 -> "vtmp1"
    | VTMP2 -> "vtmp2"
    | VTMP3 -> "vtmp3"
  in
  match w with
  | B64 -> prefix
  | B32 -> prefix ^ "d"
  | B16 -> prefix ^ "w"
  | B8  -> prefix ^ "b"

let to_string = function
  | Gpr (g, w) -> gpr_to_string g w
  | Vreg (v, w) -> vreg_to_string v w

let of_string str =
  match String.lowercase_ascii (String.trim str) with
  | "rax" -> Ok rax | "eax" -> Ok (Gpr (RAX, B32)) | "ax" -> Ok (Gpr (RAX, B16)) | "al" -> Ok (Gpr (RAX, B8))
  | "rcx" -> Ok rcx | "ecx" -> Ok (Gpr (RCX, B32)) | "cx" -> Ok (Gpr (RCX, B16)) | "cl" -> Ok (Gpr (RCX, B8))
  | "rdx" -> Ok rdx | "edx" -> Ok (Gpr (RDX, B32)) | "dx" -> Ok (Gpr (RDX, B16)) | "dl" -> Ok (Gpr (RDX, B8))
  | "rbx" -> Ok rbx | "ebx" -> Ok (Gpr (RBX, B32)) | "bx" -> Ok (Gpr (RBX, B16)) | "bl" -> Ok (Gpr (RBX, B8))
  | "rsp" -> Ok rsp | "esp" -> Ok (Gpr (RSP, B32)) | "sp" -> Ok (Gpr (RSP, B16)) | "spl" -> Ok (Gpr (RSP, B8))
  | "rbp" -> Ok rbp | "ebp" -> Ok (Gpr (RBP, B32)) | "bp" -> Ok (Gpr (RBP, B16)) | "bpl" -> Ok (Gpr (RBP, B8))
  | "rsi" -> Ok rsi | "esi" -> Ok (Gpr (RSI, B32)) | "si" -> Ok (Gpr (RSI, B16)) | "sil" -> Ok (Gpr (RSI, B8))
  | "rdi" -> Ok rdi | "edi" -> Ok (Gpr (RDI, B32)) | "di" -> Ok (Gpr (RDI, B16)) | "dil" -> Ok (Gpr (RDI, B8))
  | "r8"  -> Ok r8  | "r8d" -> Ok (Gpr (R8, B32))  | "r8w" -> Ok (Gpr (R8, B16))  | "r8b" -> Ok (Gpr (R8, B8))
  | "r9"  -> Ok r9  | "r9d" -> Ok (Gpr (R9, B32))  | "r9w" -> Ok (Gpr (R9, B16))  | "r9b" -> Ok (Gpr (R9, B8))
  | "r10" -> Ok r10 | "r10d" -> Ok (Gpr (R10, B32))| "r10w" -> Ok (Gpr (R10, B16))| "r10b" -> Ok (Gpr (R10, B8))
  | "r11" -> Ok r11 | "r11d" -> Ok (Gpr (R11, B32))| "r11w" -> Ok (Gpr (R11, B16))| "r11b" -> Ok (Gpr (R11, B8))
  | "r12" -> Ok r12 | "r12d" -> Ok (Gpr (R12, B32))| "r12w" -> Ok (Gpr (R12, B16))| "r12b" -> Ok (Gpr (R12, B8))
  | "r13" -> Ok r13 | "r13d" -> Ok (Gpr (R13, B32))| "r13w" -> Ok (Gpr (R13, B16))| "r13b" -> Ok (Gpr (R13, B8))
  | "r14" -> Ok r14 | "r14d" -> Ok (Gpr (R14, B32))| "r14w" -> Ok (Gpr (R14, B16))| "r14b" -> Ok (Gpr (R14, B8))
  | "r15" -> Ok r15 | "r15d" -> Ok (Gpr (R15, B32))| "r15w" -> Ok (Gpr (R15, B16))| "r15b" -> Ok (Gpr (R15, B8))
  | "vip" | "rip" -> Ok vip | "vsp" -> Ok vsp | "vkey" -> Ok vkey
  | "vtmp0" -> Ok vtmp0 | "vtmp1" -> Ok vtmp1 | "vtmp2" -> Ok vtmp2 | "vtmp3" -> Ok vtmp3
  | other -> Error (Printf.sprintf "Unknown register '%s'" other)


let gpr_index = function
  | RAX -> 0 | RCX -> 1 | RDX -> 2 | RBX -> 3
  | RSP -> 4 | RBP -> 5 | RSI -> 6 | RDI -> 7
  | R8  -> 8 | R9  -> 9 | R10 -> 10 | R11 -> 11
  | R12 -> 12 | R13 -> 13 | R14 -> 14 | R15 -> 15

let gpr_of_index = function
  | 0 -> Ok RAX | 1 -> Ok RCX | 2 -> Ok RDX | 3 -> Ok RBX
  | 4 -> Ok RSP | 5 -> Ok RBP | 6 -> Ok RSI | 7 -> Ok RDI
  | 8 -> Ok R8  | 9 -> Ok R9  | 10 -> Ok R10 | 11 -> Ok R11
  | 12 -> Ok R12 | 13 -> Ok R13 | 14 -> Ok R14 | 15 -> Ok R15
  | idx -> Error (Printf.sprintf "Invalid GPR index %d (expected 0..15)" idx)

let get_width = function
  | Gpr (_, w) -> w
  | Vreg (_, w) -> w

let with_width reg w =
  match reg with
  | Gpr (g, _) -> Gpr (g, w)
  | Vreg (v, _) -> Vreg (v, w)
