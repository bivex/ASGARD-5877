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

val to_string : t -> string

val pp : Format.formatter -> t -> unit
