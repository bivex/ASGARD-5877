(** Cpp_validator — Fast pre-flight structural syntax validation and compiler check for generated C++20/C11 code. *)

type validation_error = {
  line : int;
  col  : int;
  msg  : string;
}

val pp_validation_error : Format.formatter -> validation_error -> unit
val validation_error_to_string : validation_error -> string

(** Performs fast, zero-dependency in-process structural analysis:
    - Balanced braces, brackets, and parentheses with line/col tracking
    - Correctly skips string literals, raw strings, char literals, and comments
    - Detects unclosed quotes and comments
    - Detects leftover/unexpanded Jingoo template markers ({{, }}, {%, %}) *)
val validate_structural : ?check_templates:bool -> string -> (unit, validation_error) result

(** Invokes clang++ / g++ with -fsyntax-only on a temporary file. *)
val validate_with_compiler :
  ?compiler:string ->
  ?std:string ->
  ?extra_includes:string list ->
  string ->
  (unit, string) result

(** Complete pre-flight validation:
    Runs [validate_structural] first, and optionally [validate_with_compiler] if [use_compiler] is true. *)
val validate_cpp_syntax :
  ?check_templates:bool ->
  ?use_compiler:bool ->
  ?compiler:string ->
  ?std:string ->
  ?extra_includes:string list ->
  string ->
  (unit, string) result
