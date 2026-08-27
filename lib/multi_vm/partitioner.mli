open Vm_ir

type engine_affinity =
  | Engine_Math
  | Engine_Flow
  | Engine_Memory

type partitioned_block = {
  block : Ir.basic_block;
  engine : engine_affinity;
  is_bridge_entry : bool;
  is_bridge_exit : bool;
}

type partition_report = {
  total_blocks : int;
  math_blocks : int;
  flow_blocks : int;
  memory_blocks : int;
  inter_vm_transitions : int;
  blocks : partitioned_block list;
}

val classify_block : Ir.basic_block -> engine_affinity
val partition_function : Ir.func -> partition_report
