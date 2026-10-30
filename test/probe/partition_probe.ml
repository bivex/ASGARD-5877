(* Print partition report for an asm file *)
open Multi_vm
let () =
  let path = Sys.argv.(1) in
  let ic = open_in path in
  let n = in_channel_length ic in
  let asm = really_input_string ic n in
  close_in ic;
  match Arm64_lifter.lift_function asm with
  | Error e -> Printf.eprintf "lift failed: %s\n" e
  | Ok func ->
      let rep = Partitioner.partition_function func in
      Printf.printf "blocks=%d math=%d flow=%d mem=%d transitions=%d\n"
        rep.total_blocks rep.math_blocks rep.flow_blocks rep.memory_blocks rep.inter_vm_transitions;
      List.iter (fun pb ->
        Printf.printf "  B%d engine=%s entry=%b exit=%b\n"
          pb.Partitioner.block.Vm_ir.Ir.id
          (match pb.Partitioner.engine with
           | Partitioner.Engine_Math -> "MATH" | Partitioner.Engine_Flow -> "FLOW"
           | Partitioner.Engine_Memory -> "MEM")
          pb.Partitioner.is_bridge_entry pb.Partitioner.is_bridge_exit) rep.Partitioner.blocks
