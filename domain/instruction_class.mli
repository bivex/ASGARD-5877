(** Taxonomy of vector instruction families, mirroring real V-ISA structure. *)

type t =
  | Arith
  | Saturating
  | Widening
  | Compare
  | Reduce
  | Permute
  | Memory
  | Mask_logic
  | Convert

(** [all] returns all known instruction classes in the taxonomy. *)
val all : t list

(** [supported] returns classes that can currently be synthesized end-to-end. *)
val supported : t list

(** [is_supported c] returns true if [c] is synthesizable in Stage 1/2. *)
val is_supported : t -> bool

(** [is_reserved c] returns true if [c] is declared in the taxonomy but reserved. *)
val is_reserved : t -> bool

(** [to_string c] returns canonical lower-case representation. *)
val to_string : t -> string

(** [of_string s] parses a class from string. *)
val of_string : string -> (t, Errors.t) result

(** Pretty-printer for [t]. *)
val pp : Format.formatter -> t -> unit

(** Total ordering on [t]. *)
val compare : t -> t -> int

(** Equality on [t]. *)
val equal : t -> t -> bool
