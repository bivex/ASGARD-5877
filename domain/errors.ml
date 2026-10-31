(** Domain error types and formatting for Random V-ISA generator. *)

type t =
  | Invalid_mnemonic of string
  | Invalid_format of string
  | Invalid_weight of string * float
  | Invalid_profile of string
  | Duplicate_class of string
  | Duplicate_mnemonic of string
  | Encoding_collision of string * string * int * int
  | Invalid_config of string
  | Encoding_space_exhausted of string
  | Family_catalog_exhausted of string
  | Sail_parse_error of string
  | Code_generation_error of string
  | Compilation_error of string
  | Assembly_syntax_error of string
  | Unsupported_backend_feature of string
  | General_error of string

let to_string = function
  | Invalid_mnemonic m -> Printf.sprintf "Invalid mnemonic: %s" m
  | Invalid_format f -> Printf.sprintf "Invalid format: %s" f
  | Invalid_weight (fam, w) -> Printf.sprintf "Invalid weight for %s: %f (must be > 0)" fam w
  | Invalid_profile msg -> Printf.sprintf "Invalid profile: %s" msg
  | Duplicate_class cls -> Printf.sprintf "Duplicate instruction class: %s" cls
  | Duplicate_mnemonic m -> Printf.sprintf "Duplicate mnemonic: %s" m
  | Encoding_collision (m1, m2, f6, f3) ->
      Printf.sprintf "Instruction encoding collision between %s and %s (funct6=%d, funct3=%d)" m1 m2 f6 f3
  | Invalid_config msg -> Printf.sprintf "Invalid vector configuration: %s" msg
  | Encoding_space_exhausted fam ->
      Printf.sprintf "Encoding space exhausted: no free funct6 for family '%s'" fam
  | Family_catalog_exhausted msg ->
      Printf.sprintf "Family catalog exhausted before reaching instruction budget (%s)" msg
  | Sail_parse_error msg -> Printf.sprintf "Sail parse error: %s" msg
  | Code_generation_error msg -> Printf.sprintf "Code generation error: %s" msg
  | Compilation_error msg -> Printf.sprintf "Compilation error: %s" msg
  | Assembly_syntax_error msg -> Printf.sprintf "Assembly syntax error: %s" msg
  | Unsupported_backend_feature msg -> Printf.sprintf "Unsupported backend feature: %s" msg
  | General_error msg -> Printf.sprintf "Error: %s" msg

let pp fmt err = Format.pp_print_string fmt (to_string err)
