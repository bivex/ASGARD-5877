type t =
  | Arith
  | Saturating
  | Widening
  | Compare
  | Reduce
  | Permute
  | Memory
  | Mask_logic
  | Convert

let all = [
  Arith; Saturating; Widening; Compare;
  Reduce; Permute; Memory; Mask_logic; Convert;
]

let supported = [ Arith; Saturating; Widening; Compare ]

let is_supported = function
  | Arith | Saturating | Widening | Compare -> true
  | Reduce | Permute | Memory | Mask_logic | Convert -> false

let is_reserved c = not (is_supported c)

let to_string = function
  | Arith -> "arith"
  | Saturating -> "saturating"
  | Widening -> "widening"
  | Compare -> "compare"
  | Reduce -> "reduce"
  | Permute -> "permute"
  | Memory -> "memory"
  | Mask_logic -> "mask-logic"
  | Convert -> "convert"

let of_string s =
  match String.lowercase_ascii (String.trim s) with
  | "arith" -> Ok Arith
  | "saturating" -> Ok Saturating
  | "widening" -> Ok Widening
  | "compare" -> Ok Compare
  | "reduce" -> Ok Reduce
  | "permute" -> Ok Permute
  | "memory" -> Ok Memory
  | "mask-logic" | "mask_logic" -> Ok Mask_logic
  | "convert" -> Ok Convert
  | other -> Error (Errors.General_error ("Unknown instruction class: " ^ other))

let pp fmt c = Format.pp_print_string fmt (to_string c)

let compare = Stdlib.compare

let equal a b = compare a b = 0
