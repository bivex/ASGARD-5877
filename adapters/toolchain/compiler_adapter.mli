open Random_visa_ports

(** Compiler adapter invoking C++ compiler and running native test harness. *)

include Ports.Compiler

val get_compiler_cmd : unit -> string
