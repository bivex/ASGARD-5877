type target_os = [ `Darwin | `Linux | `Windows | `Auto ]

val emit_direct_syscalls_header : ?target_os:target_os -> unit -> string
