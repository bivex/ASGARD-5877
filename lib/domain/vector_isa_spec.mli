(** Vector ISA Specification Aggregate Root. *)

type t = private {
  name : string;
  version : string;
  config : Vector_config.t;
  instructions : Vector_instruction.t list;
  metadata : (string * string) list;
}

(** Constructs an empty specification without instructions. *)
val make :
  name:string ->
  ?version:string ->
  ?config:Vector_config.t ->
  ?metadata:(string * string) list ->
  unit ->
  t

(** [add_instruction spec inst] adds an instruction, checking encoding collision
    on [(funct6, funct3, opcode)] and duplicate mnemonics. *)
val add_instruction : t -> Vector_instruction.t -> (t, Errors.t) result

(** [of_instructions name ?version ?config ?metadata insts] constructs a specification,
    verifying all collision and duplicate invariants at construction time. *)
val of_instructions :
  name:string ->
  ?version:string ->
  ?config:Vector_config.t ->
  ?metadata:(string * string) list ->
  Vector_instruction.t list ->
  (t, Errors.t) result

(** Find instruction by exact or case-insensitive mnemonic. *)
val get_by_mnemonic : t -> string -> Vector_instruction.t option

(** Decode a 32-bit instruction word into a matching [Vector_instruction.t]. *)
val decode : t -> int32 -> Vector_instruction.t option

(** Render the formal Sail specification file text. *)
val to_sail_specification : t -> string
