include module type of Riscv_types

val parse_line : string -> (raw_line, string) result
val parse_lines : string -> (raw_line list, string) result
val extract_constants : string -> (string * string) list
