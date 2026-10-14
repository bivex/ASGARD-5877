(** Stack_handlers_emitter — Typed C++ AST code generation for Stack-VM manipulation handlers. *)

open Cpp_codegen.Cpp_ast

val vm_handler_params : (ctype * string) list

val emit_h_push_imm : unit -> top_decl
val emit_h_push_imm32 : unit -> top_decl
val emit_h_push_reg : unit -> top_decl
val emit_h_pop_reg : unit -> top_decl
val emit_h_dup : unit -> top_decl
val emit_h_dup2 : unit -> top_decl
val emit_h_rot : unit -> top_decl
val emit_h_swap : unit -> top_decl

val emit_h_read_mem : unit -> top_decl
val emit_h_write_mem : unit -> top_decl
val emit_h_add : unit -> top_decl
val emit_h_sub : unit -> top_decl
val emit_h_mul : unit -> top_decl
val emit_h_nor : unit -> top_decl
val emit_h_nand : unit -> top_decl
val emit_h_shl : unit -> top_decl
val emit_h_shr : unit -> top_decl
val emit_h_sar : unit -> top_decl
val emit_h_div : unit -> top_decl
val emit_h_idiv : unit -> top_decl
val emit_h_push_flags : unit -> top_decl
val emit_h_pop_flags : unit -> top_decl

val emit_h_cmp : unit -> top_decl
val emit_h_test : unit -> top_decl
val emit_h_add_imm : unit -> top_decl
val emit_h_sub_imm : unit -> top_decl
val emit_h_add_ii : unit -> top_decl
val emit_h_sub_ii : unit -> top_decl

val emit_h_jmp_rel : unit -> top_decl
val emit_h_jcc_rel : ?target_first:bool -> unit -> top_decl
val emit_h_key_adjust : unit -> top_decl
val emit_h_exit : unit -> top_decl

val emit_h_resolve_sym : unit -> top_decl
val emit_h_setcc : unit -> top_decl
val emit_h_cmov : ?slot_first:bool -> unit -> top_decl

val emit_h_set_reg_imm : ?imm_first:bool -> unit -> top_decl
val emit_h_add_reg_imm : ?imm_first:bool -> unit -> top_decl
val emit_h_key_feedback : unit -> top_decl

val emit_push_pop_handlers : unit -> top_decl list
val emit_dup_swap_handlers : unit -> top_decl list
val emit_mem_handlers : unit -> top_decl list
val emit_alu_handlers : unit -> top_decl list
val emit_flags_handlers : unit -> top_decl list
val emit_superop_handlers : unit -> top_decl list
val emit_control_handlers : ?jcc_target_first:bool -> unit -> top_decl list
val emit_cond_handlers : ?cmov_slot_first:bool -> unit -> top_decl list
val emit_reg_imm_handlers : ?set_reg_imm_first:bool -> ?add_reg_imm_first:bool -> unit -> top_decl list
val emit_all_stack_manipulation_handlers : unit -> top_decl list

val emit_push_pop_handlers_string : unit -> string
val emit_dup_swap_handlers_string : unit -> string
val emit_mem_handlers_string : unit -> string
val emit_alu_handlers_string : unit -> string
val emit_flags_handlers_string : unit -> string
val emit_superop_handlers_string : unit -> string
val emit_control_handlers_string : ?jcc_target_first:bool -> unit -> string
val emit_cond_handlers_string : ?cmov_slot_first:bool -> unit -> string
val emit_reg_imm_handlers_string : ?set_reg_imm_first:bool -> ?add_reg_imm_first:bool -> unit -> string
val emit_all_handlers_string : unit -> string

val emit_handlers_source : Buffer.t -> unit


