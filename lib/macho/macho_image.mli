(** ASGARD-5877: Mach-O container reader.

    Parses 32-bit and 64-bit Mach-O images and exposes their load commands,
    segments and sections.  Compact unwind information is reached through the
    [LC_ROUTINES] (0x22) and [LC_ROUTINES64] (0x33) load commands, which
    carry the table of routine entries pointing into [__TEXT,__unwind_info]. *)

type magic =
  | MH_MAGIC        (** 0xfeedface, 32-bit, host order *)
  | MH_MAGIC_64     (** 0xfeedfacf, 64-bit, host order *)
  | MH_CIGAM        (** byte-swapped 32-bit *)
  | MH_CIGAM_64     (** byte-swapped 64-bit *)

type section = {
  sectname : string;
  segname : string;
  addr : int64;                (** virtual address of the section *)
  size : int64;                (** size in bytes *)
  offset : int64;              (** file offset of the section contents *)
  flags : int32;
}

type segment = {
  is_64 : bool;                (** true for [LC_SEGMENT_64] *)
  segname : string;
  vmaddr : int64;
  vmsize : int64;
  fileoff : int64;
  filesize : int64;
  nsects : int;
  flags : int32;
  sections : section list;
}

(** [LC_ROUTINES] and [LC_ROUTINES64].  [routines_offset] is a file offset of
    the routine table; [routines_size] is its size in bytes. *)
type routines_command = {
  is_64 : bool;                (** true for [LC_ROUTINES64] *)
  cmd : int32;
  cmdsize : int32;
  init_address : int64;
  init_size : int64;
  routines_offset : int64;
  routines_size : int64;
}

type other_command = {
  cmd_value : int32;            (** raw load command value *)
  cmd_size : int32;             (** size of the load command, in bytes *)
  file_offset : int;            (** offset of the load command in the image *)
}

type load_command =
  | Segment of segment
  | Routines of routines_command
  | Other of other_command

type t = {
  bytes : bytes;               (** the whole image *)
  magic : magic;
  is_64 : bool;
  cpu_type : int32;
  cpu_subtype : int32;
  file_type : int32;
  flags : int32;
  ncmds : int;
  sizeofcmds : int;
  load_commands : load_command list;
}

exception Parse_error of string

val of_file : string -> t
(** [Parse_error] is raised when the file cannot be read or is not a Mach-O
    image. *)

val of_bytes : bytes -> t
(** [Parse_error] is raised when the buffer is not a Mach-O image. *)

val load_commands : t -> load_command list

val segments : t -> segment list

val segment : t -> string -> segment option
(** [segment img "__TEXT"] returns the segment with that name. *)

val section : t -> string -> string -> section option
(** [section img "__TEXT" "__text"] returns the section with that segment and
    section name. *)

val routines_commands : t -> routines_command list
(** Every [LC_ROUTINES] / [LC_ROUTINES64] command found in the image. *)

val section_data : t -> section -> bytes
(** The raw contents of a section.  Raises [Parse_error] when the section
    extends past the end of the image. *)
