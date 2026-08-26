module Sew = struct
  type t = E8 | E16 | E32 | E64

  let to_bits = function
    | E8 -> 8
    | E16 -> 16
    | E32 -> 32
    | E64 -> 64

  let byte_width t = to_bits t / 8

  let c_type t = Printf.sprintf "int%d_t" (to_bits t)

  let c_utype t = Printf.sprintf "uint%d_t" (to_bits t)

  let of_bits = function
    | 8 -> Ok E8
    | 16 -> Ok E16
    | 32 -> Ok E32
    | 64 -> Ok E64
    | n -> Error (Errors.Invalid_config (Printf.sprintf "Unsupported SEW bit width: %d" n))

  let to_string t = Printf.sprintf "e%d" (to_bits t)

  let all = [ E8; E16; E32; E64 ]
end

module Lmul = struct
  type t = MF8 | MF4 | MF2 | M1 | M2 | M4 | M8

  let multiplier_val = function
    | MF8 -> 0.125
    | MF4 -> 0.25
    | MF2 -> 0.5
    | M1 -> 1.0
    | M2 -> 2.0
    | M4 -> 4.0
    | M8 -> 8.0

  let num_registers t = max 1 (int_of_float (multiplier_val t))

  let to_string = function
    | MF8 -> "mf8"
    | MF4 -> "mf4"
    | MF2 -> "mf2"
    | M1 -> "m1"
    | M2 -> "m2"
    | M4 -> "m4"
    | M8 -> "m8"

  let all = [ MF8; MF4; MF2; M1; M2; M4; M8 ]
end

module Element_kind = struct
  type t = Int | Uint | Float | Bits

  let to_string = function
    | Int -> "int"
    | Uint -> "uint"
    | Float -> "float"
    | Bits -> "bits"

  let of_string = function
    | "int" -> Ok Int
    | "uint" -> Ok Uint
    | "float" -> Ok Float
    | "bits" -> Ok Bits
    | other -> Error (Errors.General_error ("Unknown element kind: " ^ other))
end

module Instruction_format = struct
  type t =
    | OP_VV
    | OP_VX
    | OP_VI
    | OP_MVV
    | OP_RED
    | OP_WIDENING
    | OP_MEM_LOAD
    | OP_MEM_STORE

  let to_string = function
    | OP_VV -> "OPIVV"
    | OP_VX -> "OPIVX"
    | OP_VI -> "OPIVI"
    | OP_MVV -> "OPMVV"
    | OP_RED -> "OPRED"
    | OP_WIDENING -> "OPWVV"
    | OP_MEM_LOAD -> "VLE"
    | OP_MEM_STORE -> "VSE"

  let to_suffix = function
    | OP_VV -> "vv"
    | OP_VX -> "vx"
    | OP_VI -> "vi"
    | OP_MVV -> "m"
    | OP_RED -> "vs"
    | OP_WIDENING -> "vv"
    | OP_MEM_LOAD -> "vle"
    | OP_MEM_STORE -> "vse"

  let to_funct3 = function
    | OP_VV -> 0b000
    | OP_VX -> 0b100
    | OP_VI -> 0b011
    | OP_MVV -> 0b010
    | OP_RED -> 0b001
    | OP_WIDENING -> 0b000
    | OP_MEM_LOAD -> 0b000
    | OP_MEM_STORE -> 0b000

  let of_string = function
    | "OPIVV" | "vv" -> Ok OP_VV
    | "OPIVX" | "vx" -> Ok OP_VX
    | "OPIVI" | "vi" -> Ok OP_VI
    | "OPMVV" | "m" -> Ok OP_MVV
    | "OPRED" | "vs" -> Ok OP_RED
    | "OPWVV" | "w" -> Ok OP_WIDENING
    | "VLE" -> Ok OP_MEM_LOAD
    | "VSE" -> Ok OP_MEM_STORE
    | other -> Error (Errors.Invalid_format other)

  let all = [ OP_VV; OP_VX; OP_VI; OP_MVV; OP_RED; OP_WIDENING; OP_MEM_LOAD; OP_MEM_STORE ]

  let equal (a : t) (b : t) = a = b
end

module Binary_op = struct
  type t =
    | ADD
    | SUB
    | MUL
    | DIV
    | REM
    | AND
    | OR
    | XOR
    | SLL
    | SRL
    | SRA
    | MIN
    | MAX
    | SADD
    | SSUB
    | CMPEQ
    | CMPNE
    | CMPLT
    | CMPGE

  let name = function
    | ADD -> "ADD"
    | SUB -> "SUB"
    | MUL -> "MUL"
    | DIV -> "DIV"
    | REM -> "REM"
    | AND -> "AND"
    | OR -> "OR"
    | XOR -> "XOR"
    | SLL -> "SLL"
    | SRL -> "SRL"
    | SRA -> "SRA"
    | MIN -> "MIN"
    | MAX -> "MAX"
    | SADD -> "SADD"
    | SSUB -> "SSUB"
    | CMPEQ -> "CMPEQ"
    | CMPNE -> "CMPNE"
    | CMPLT -> "CMPLT"
    | CMPGE -> "CMPGE"

  let symbol = function
    | ADD -> "+"
    | SUB -> "-"
    | MUL -> "*"
    | DIV -> "/"
    | REM -> "%"
    | AND -> "&"
    | OR -> "|"
    | XOR -> "^"
    | SLL -> "<<"
    | SRL -> ">>"
    | SRA -> ">>_s"
    | MIN -> "min"
    | MAX -> "max"
    | SADD -> "+_sat"
    | SSUB -> "-_sat"
    | CMPEQ -> "=="
    | CMPNE -> "!="
    | CMPLT -> "<"
    | CMPGE -> ">="

  let is_compare = function
    | CMPEQ | CMPNE | CMPLT | CMPGE -> true
    | _ -> false

  let of_name = function
    | "ADD" -> Some ADD
    | "SUB" -> Some SUB
    | "MUL" -> Some MUL
    | "DIV" -> Some DIV
    | "REM" -> Some REM
    | "AND" -> Some AND
    | "OR" -> Some OR
    | "XOR" -> Some XOR
    | "SLL" -> Some SLL
    | "SRL" -> Some SRL
    | "SRA" -> Some SRA
    | "MIN" -> Some MIN
    | "MAX" -> Some MAX
    | "SADD" -> Some SADD
    | "SSUB" -> Some SSUB
    | "CMPEQ" -> Some CMPEQ
    | "CMPNE" -> Some CMPNE
    | "CMPLT" -> Some CMPLT
    | "CMPGE" -> Some CMPGE
    | _ -> None

  let all = [
    ADD; SUB; MUL; DIV; REM; AND; OR; XOR;
    SLL; SRL; SRA; MIN; MAX; SADD; SSUB;
    CMPEQ; CMPNE; CMPLT; CMPGE;
  ]
end

module Unary_op = struct
  type t =
    | NEG
    | NOT
    | ABS
    | CLZ
    | CTZ
    | CPOP

  let name = function
    | NEG -> "NEG"
    | NOT -> "NOT"
    | ABS -> "ABS"
    | CLZ -> "CLZ"
    | CTZ -> "CTZ"
    | CPOP -> "CPOP"

  let symbol = function
    | NEG -> "-"
    | NOT -> "~"
    | ABS -> "abs"
    | CLZ -> "clz"
    | CTZ -> "ctz"
    | CPOP -> "cpop"

  let of_name = function
    | "NEG" -> Some NEG
    | "NOT" -> Some NOT
    | "ABS" -> Some ABS
    | "CLZ" -> Some CLZ
    | "CTZ" -> Some CTZ
    | "CPOP" -> Some CPOP
    | _ -> None

  let all = [ NEG; NOT; ABS; CLZ; CTZ; CPOP ]
end

module Tail_policy = struct
  type t = Undisturbed | Agnostic

  let to_string = function
    | Undisturbed -> "tu"
    | Agnostic -> "ta"
end

module Mask_policy = struct
  type t = Undisturbed | Agnostic

  let to_string = function
    | Undisturbed -> "mu"
    | Agnostic -> "ma"
end
