open Vm_ir

type t

val create : ?seed:int -> ?permute:bool -> unit -> t

val slot_of_reg : t -> Register.t -> int

val reg_of_slot : t -> int -> Register.t option

val alloc_scratch : t -> int

val total_slots : t -> int

val dump_mapping : t -> (int * string) list

val permute_epoch : ?seed:int -> t -> epoch:int -> t
(** [permute_epoch ?seed ctx ~epoch] creates a new context allocator where register
    slot indices are homomorphically permuted based on the execution epoch,
    preventing static context offset recovery across execution phases. *)

val slot_of_reg_epoch : t -> epoch:int -> Register.t -> int
val reg_of_slot_epoch : t -> epoch:int -> int -> Register.t option

