(** Structured Logger for ASGARD-5877 VM-Protector Pipeline.
    Supports granular severity levels, subsystem tagging, step/phase progress
    tracking, ANSI colorization on TTY, custom sink routing, and zero-allocation
    evaluation when messages are filtered below the active threshold. *)

type level =
  | Debug
  | Info
  | Warn
  | Error
  | Quiet

type sink = {
  write : level -> string option -> string -> unit;
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

val log : ?section:string -> level -> string -> unit
val logf : ?section:string -> level -> ('a, unit, string, unit) format4 -> 'a

val debug : ?section:string -> string -> unit
val debugf : ?section:string -> ('a, unit, string, unit) format4 -> 'a

val info : ?section:string -> string -> unit
val infof : ?section:string -> ('a, unit, string, unit) format4 -> 'a

val warn : ?section:string -> string -> unit
val warnf : ?section:string -> ('a, unit, string, unit) format4 -> 'a

val error : ?section:string -> string -> unit
val errorf : ?section:string -> ('a, unit, string, unit) format4 -> 'a

val step : ?section:string -> step:int -> total:int -> string -> unit
val stepf : ?section:string -> step:int -> total:int -> ('a, unit, string, unit) format4 -> 'a
