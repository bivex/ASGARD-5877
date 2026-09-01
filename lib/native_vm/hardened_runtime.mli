(** Hardened_runtime — Direct Syscalls, Dual-Mapping W^X memory aliasing, and Anti-Emulation hypervisor timing probes. *)

type target_os = [ `Darwin | `Linux | `Windows | `Auto ]

val emit_direct_syscalls_header : ?target_os:target_os -> unit -> string

val emit_dual_mapping_header : unit -> string

val emit_anti_emulation_probes : unit -> string

val emit_introspective_smc_header : unit -> string

val emit_memory_integrity_scanner_header : unit -> string
