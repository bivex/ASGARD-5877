(** Vanguard-9292: Polymorphic Dynamic Bytecode Obfuscation Layer.

    Generates unique, randomized bytecode encoding schemes derived from an
    underlying Vector ISA specification (Vector_isa_spec / Isa_grammar).

    Key concept: The ISA domain (instruction catalog, operand semantics) remains
    identical. Vanguard-9292 injects a SECOND, independent layer of randomization:
    HOW that ISA is bit-packed, permuted, and encrypted into bytes.
    The scheme is regenerated on every build of a protected binary. *)

type field_kind =
  | Opcode  (** Instruction identifier *)
  | Dst     (** Destination register index *)
  | Src1    (** First source register index *)
  | Src2    (** Second source register index *)
  | Imm     (** Immediate / literal integer *)
  | Mask    (** Masking bit (analogous to vm in RVV) *)
  | Junk    (** Decoy/junk bits ignored during execution *)

val field_kind_to_string : field_kind -> string

type field_layout = {
  kind : field_kind;
  bit_offset : int;   (** Bit offset from start of word, LSB = 0 *)
  bit_width : int;    (** Number of bits occupied *)
}

(** Non-overlapping, sorted instruction word layout invariant.
    Constructed exclusively through [make_layout]. *)
type instruction_word_layout = private {
  word_bits : int;              (** 16 | 32 | 48 | 64 *)
  fields : field_layout list;   (** Sorted by bit_offset *)
}

val fields_overlap : field_layout -> field_layout -> bool

val make_layout :
  word_bits:int ->
  fields:field_layout list ->
  (instruction_word_layout, string) result

(** Bijection between mnemonic and numeric opcode, randomized without
    frequency correlation to defeat static frequency analysis. *)
module Opcode_map : sig
  type t = {
    forward : (string, int) Hashtbl.t;
    reverse : (int, string) Hashtbl.t;
    opcode_bits : int;
  }

  val shuffle : Random.State.t -> int array -> unit

  val generate :
    rng:Random.State.t ->
    mnemonics:string list ->
    opcode_bits:int ->
    (t, string) result

  val encode : t -> string -> int option

  val decode : t -> int -> string option

  val is_junk : t -> int -> bool
end

(** Rolling XOR key dependent on the stream position of the instruction.
    Deterministic PRNG (xorshift32) that renders static opcode fingerprinting
    useless, while allowing VM runtime to reproduce the exact stream. *)
module Rolling_key : sig
  type t = { seed : int32; mutable state : int32 }

  val make : seed:int32 -> t

  val next : t -> int32

  val reset : t -> unit
end

type t = {
  layout : instruction_word_layout;
  opcodes : Opcode_map.t;
  key_seed : int32;
  junk_ratio : float;
}

val generate :
  ?word_bits:int ->
  ?min_reg_bits:int ->
  ?min_imm_bits:int ->
  rng:Random.State.t ->
  mnemonics:string list ->
  unit ->
  (t, string) result

val of_isa_spec :
  ?word_bits:int ->
  ?min_reg_bits:int ->
  ?min_imm_bits:int ->
  rng:Random.State.t ->
  Random_visa_domain.Vector_isa_spec.t ->
  (t, string) result

val encode_word :
  t ->
  mnemonic:string ->
  dst:int ->
  src1:int ->
  src2:int ->
  imm:int ->
  mask:bool ->
  key:Rolling_key.t ->
  (int64, string) result

val decode_word :
  t ->
  key:Rolling_key.t ->
  int64 ->
  ( string * [ `Dst of int ] * [ `Src1 of int ] * [ `Src2 of int ] * [ `Imm of int ] * [ `Mask of bool ],
    [ `Junk_opcode | `Unknown_opcode of int | `Corrupted_field of string ] )
  result
