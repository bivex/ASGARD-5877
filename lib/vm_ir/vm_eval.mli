open Register
open Flags
open Ir

type state = {
  vregs : (Register.t, int64) Hashtbl.t;
  memory : (int64, int) Hashtbl.t;
  mutable flags : cc_op;
  mutable vsp : int64;
  mutable vip : int64;
  mutable halted : bool;
  mutable trapped : string option;
}

val make_state : ?stack_base:int64 -> unit -> state

val get_reg : state -> Register.t -> int64
val set_reg : state -> Register.t -> int64 -> unit

val read_mem : state -> int64 -> width -> int64
val write_mem : state -> int64 -> width -> int64 -> unit

val eval_operand : state -> operand -> int64
val eval_mem_addr : state -> mem_ref -> int64

val step : state -> instr -> (target option, string) result
val run_block : state -> basic_block -> (target option, string) result
val run_func : ?max_steps:int -> state -> func -> (unit, string) result
