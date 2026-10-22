(** Structured Logger for ASGARD-5877 VM-Protector Pipeline.
    Supports granular severity levels, subsystem tagging, caller file:line
    source location, step/phase progress tracking, ANSI colorization on TTY,
    custom sink routing, and zero-allocation evaluation when messages are
    filtered below the active threshold. *)

type level =
  | Debug
  | Info
  | Warn
  | Error
  | Quiet

type sink = {
  write : level -> string option -> string -> string -> unit;
  flush : unit -> unit;
}

val set_level : level -> unit
val get_level : unit -> level
val is_enabled : level -> bool

val set_color_enabled : bool -> unit
val is_color_enabled : unit -> bool

val set_sink : sink -> unit
val reset_sink : unit -> unit

val level_to_string : level -> string
val level_of_string : string -> level option

val format_loc : string -> string

val log : ?loc:string -> ?file:string -> ?line:int -> ?section:string -> level -> string -> unit
val logf : ?loc:string -> ?file:string -> ?line:int -> ?section:string -> level -> ('a, unit, string, unit) format4 -> 'a

val debug : ?loc:string -> ?file:string -> ?line:int -> ?section:string -> string -> unit
val debugf : ?loc:string -> ?file:string -> ?line:int -> ?section:string -> ('a, unit, string, unit) format4 -> 'a

val info : ?loc:string -> ?file:string -> ?line:int -> ?section:string -> string -> unit
val infof : ?loc:string -> ?file:string -> ?line:int -> ?section:string -> ('a, unit, string, unit) format4 -> 'a

val warn : ?loc:string -> ?file:string -> ?line:int -> ?section:string -> string -> unit
val warnf : ?loc:string -> ?file:string -> ?line:int -> ?section:string -> ('a, unit, string, unit) format4 -> 'a

val error : ?loc:string -> ?file:string -> ?line:int -> ?section:string -> string -> unit
val errorf : ?loc:string -> ?file:string -> ?line:int -> ?section:string -> ('a, unit, string, unit) format4 -> 'a

val step : ?loc:string -> ?file:string -> ?line:int -> ?section:string -> step:int -> total:int -> string -> unit
val stepf : ?loc:string -> ?file:string -> ?line:int -> ?section:string -> step:int -> total:int -> ('a, unit, string, unit) format4 -> 'a
