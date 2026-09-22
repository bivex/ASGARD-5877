include module type of Arm64_types

val parse_line : string -> (raw_line, string) result
val parse_lines : string -> (raw_line list, string) result
val marker_mode_to_string : marker_mode -> string
val extract_constants : string -> (string * string) list
