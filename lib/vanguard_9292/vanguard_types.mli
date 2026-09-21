(** Layout, opcode mapping, rolling keys, and word codecs for Vanguard-9292. *)

type field_kind =
  | Opcode
  | Dst
  | Src1
  | Src2
  | Imm
  | Mask
  | Junk

val field_kind_to_string : field_kind -> string

type field_layout = {
  kind : field_kind;
  bit_offset : int;
  bit_width : int;
}

type instruction_word_layout = {
  word_bits : int;
  fields : field_layout list;
}

val fields_overlap : field_layout -> field_layout -> bool

val make_layout :
  word_bits:int ->
  fields:field_layout list ->
  (instruction_word_layout, string) result

module Opcode_map : sig
  type t = {
    forward : (string, int) Hashtbl.t;
    reverse : (int, string) Hashtbl.t;
    opcode_bits : int;
  }

  val shuffle : Random.State.t -> 'a array -> unit

  val generate :
    rng:Random.State.t ->
    mnemonics:string list ->
    opcode_bits:int ->
    (t, string) result

  val encode : t -> string -> int option

  val decode : t -> int -> string option

  val is_junk : t -> int -> bool
end

module Rolling_key : sig
  type t = { seed : int32; mutable state : int32; mutable counter : int32 }

  val make : seed:int32 -> t

  val next : t -> int32

  val next64 : t -> int64

  val reset : t -> unit
end

type t = {
  layout : instruction_word_layout;
  opcodes : Opcode_map.t;
  key_seed : int32;
  junk_ratio : float;
}

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
  (string * [ `Dst of int ] * [ `Src1 of int ] * [ `Src2 of int ] * [ `Imm of int ] * [ `Mask of bool ],
   [ `Corrupted_field of string | `Junk_opcode | `Unknown_opcode of int ]) result
