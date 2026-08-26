(** C_macro_obf — C/C++ Preprocessor & Source-Level Macro Obfuscation Engine.

    Provides compile-time and source-level hardening through:
    1. Polymorphic standalone header generation ([asgard_obf.h]).
    2. Stack-based XOR encrypted string literals with rolling keys.
    3. Multi-layer Mixed Boolean-Arithmetic (MBA) macro expansions.
    4. Compile-time constant blinding.
    5. Invariant number-theoretic opaque predicates.
    6. Macro-based Control-Flow Flattening (CFF) primitives.
*)

type config = {
  seed : int;
  mba_depth : int;
  obfuscate_strings : bool;
  obfuscate_constants : bool;
  obfuscate_arithmetic : bool;
  inject_opaque_predicates : bool;
  macro_prefix : string;
}

val default_config : config

(** Generate a polymorphic, standalone C/C++ header containing all obfuscation macros. *)
val generate_header : ?config:config -> unit -> string

(** Obfuscate a raw string into an inline stack-decrypted C macro expression. *)
val obfuscate_string_literal : prefix:string -> seed:int -> string -> string

(** Obfuscate an integer constant into an algebraically blinded C macro expression. *)
val obfuscate_constant_i64 : prefix:string -> seed:int -> int64 -> string

(** Transform a complete C source code string using macro replacements. *)
val obfuscate_source : ?config:config -> string -> string

(** Transform a C source file on disk and optionally emit the companion header file. *)
val transform_file :
  ?config:config ->
  in_file:string ->
  out_file:string ->
  header_file:string option ->
  unit ->
  (unit, string) result

