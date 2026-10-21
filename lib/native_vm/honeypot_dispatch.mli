(** Decoy classic switch-case VM interpreter.
    Pattern-matches the "textbook VM dispatcher" shape that a reverse engineer
    or an automated devirtualizer (D810-style) expects to find FIRST —
    but routes to semantically inert handlers, never the real opcode path. *)

open Cpp_codegen.Cpp_ast

val default_decoy_mnemonics : (int * string) list

val synth_decoy_case :
  Random.State.t ->
  int ->
  string ->
  expr * string option * stmt list

val emit_honeypot_switch_fn :
  Random.State.t ->
  (int * string) list ->
  top_decl
