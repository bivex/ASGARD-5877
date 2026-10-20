(** ASGARD-5877: compact unwind analysis for Mach-O images.

    The compact unwind information of a Mach-O image is reached through the
    [LC_ROUTINES] / [LC_ROUTINES64] load commands.  Each of them points at a
    table of routine entries that map a function address and size onto a blob
    of compact unwind information inside [__TEXT,__unwind_info].

    A routine table that no longer matches the code it describes makes the
    unwinder read foreign bytes, so this module decodes the table, checks it
    against [__TEXT,__text] and [__TEXT,__unwind_info], and can repair the
    entries whose extent overruns the following function. *)

type routine = {
  address : int64;              (** virtual address of the function *)
  size : int64;                 (** extent of the function, in bytes *)
  unwind_info_offset : int64;   (** offset into [__TEXT,__unwind_info] *)
  unwind_info_size : int64;     (** size of the unwind blob, in bytes *)
}

type issue =
  | Missing_unwind_info_section
      (** The image has no [__TEXT,__unwind_info] section, so it cannot
          unwind at all. *)
  | Missing_text_section
      (** The image has no [__TEXT,__text] section. *)
  | Unsorted_routines of { previous : int64; current : int64 }
      (** The routine table is not sorted by address. *)
  | Address_outside_text of { routine : routine; text_start : int64; text_end : int64 }
      (** A routine describes an address that is not inside [__TEXT,__text]. *)
  | Size_overruns_next_routine of { routine : routine; limit : int64 }
      (** A routine claims more bytes than it owns before the next routine. *)
  | Unwind_info_out_of_range of { routine : routine; section_size : int64 }
      (** A routine points at unwind information outside the section. *)

(** How an image stores its compact unwind information.

    A routine table is reached through [LC_ROUTINES] / [LC_ROUTINES64].  The
    section index layout is the one the current linker produces for
    executables: [__TEXT,__unwind_info] starts with an
    [unwind_info_section_header] that points at a page table instead of at a
    table of routine entries. *)
type section_index = {
  version : int32;             (** version of the [unwind_info_section_header] *)
  index_count : int;           (** number of pages in the index table *)
}

type layout =
  | Routine_table of Macho_image.routines_command list
  | Section_index of section_index
  | No_unwind_info

type report = {
  routines : routine list;
  issues : issue list;
  layout : layout;
  text_start : int64;
  text_end : int64;
  unwind_info_size : int64;
}

val decode_routines : Macho_image.t -> routine list
(** Every routine entry of every [LC_ROUTINES] / [LC_ROUTINES64] command, in
    the order the commands appear in the image. *)

val routine_for_address : Macho_image.t -> int64 -> routine option
(** The routine that covers the given virtual address, if any. *)

val check : Macho_image.t -> report
(** Consistency report of the compact unwind information. *)

val layout : Macho_image.t -> layout
(** How the image stores its compact unwind information. *)

val repair : Macho_image.t -> report -> bytes
(** Returns a copy of the image in which every routine that overruns the
    following function has its size clamped to the function extent.  The
    image layout is preserved, so no offset has to be fixed up.  Addresses and
    the number of entries are never changed. *)

val repair_to_file : Macho_image.t -> report -> string -> (unit, string) result
(** Writes the repaired image to the given path. *)

val format_layout : layout -> string
(** Human-readable rendering of the compact unwind layout. *)

val format_report : report -> string
(** Human-readable rendering of a report. *)
