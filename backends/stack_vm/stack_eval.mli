open Vm_ir
open Stack_ir
open Stack_encoder

type state = {
  mutable vip : int64;
  mutable vsp : int64;
  mutable vkey : int64;
  mutable vdisp : int64;
  mutable vstack : int64 list;
  vctx : (int, int64) Hashtbl.t;
  vmem : (int64, int) Hashtbl.t;
  mutable flags : Flags.cc_op;
  mutable current_block_id : int;
  mutable halted : bool;
}

val create_state : ?stack_base:int64 -> ?seed_key:int64 -> ?initial_ctx:(int * int64) list -> unit -> state

val step_op : state -> stack_op -> unit

val run_program : ?max_steps:int -> ?initial_ctx:(int * int64) list -> program -> state

val run_bytecode : ?max_steps:int -> ?initial_ctx:(int * int64) list -> encrypted_bytecode -> state

val get_reg : state -> int -> int64

val set_reg : state -> int -> int64 -> unit

val read_mem_word : state -> int64 -> int -> int64

val write_mem_word : state -> int64 -> int64 -> int -> unit

(** The guest memory-access policy, mirroring [asg_mem_access_ok] in the
    generated C runtime. [ReadMem]/[WriteMem] halt instead of performing an
    access this rejects. *)
val mem_access_ok : int64 -> int -> bool
