open Vm_ir

type t

val create : ?seed:int -> ?permute:bool -> unit -> t

val slot_of_reg : t -> Register.t -> int

val reg_of_slot : t -> int -> Register.t option

val alloc_scratch : t -> int

val total_slots : t -> int

val dump_mapping : t -> (int * string) list
