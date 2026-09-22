open Vm_ir
open Arm64_types

val is_terminator : Ir.instr -> bool
val raw_to_ir_operand : raw_op -> Ir.operand
val map_cond_str : string -> Flags.condition
val strip_page_suffix : string -> string
val emit_3addr_alu :
  op:Ir.alu_op ->
  dst:Register.t ->
  src1:Register.t ->
  src2:raw_op ->
  set_flags:bool ->
  Ir.instr list
val lower_mem_operand :
  scratch_reg:Register.t ->
  raw_mem ->
  raw_mem * Ir.instr list
