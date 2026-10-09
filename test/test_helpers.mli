(** Test_helpers — Shared test utilities for ASGARD-5877 verification suite. *)

val create_dir : string -> unit
val delete_dir : string -> unit
val with_temp_dir : (string -> 'a) -> 'a
val with_temp_file : ?suffix:string -> (string -> 'a) -> 'a
val read_file_string : string -> string
val write_file_string : string -> string -> unit
val write_bytecode_bin : string -> int64 list -> unit
val run_command_capture : string -> Unix.process_status * string
val string_contains : string -> string -> bool
val compile_and_prepare_vm : string -> Native_vm.Vm_emitter.vm_package -> string
val run_custom_vm : name:string -> string -> Native_vm.Vm_emitter.vm_package -> string -> unit
