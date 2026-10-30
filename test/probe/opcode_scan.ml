(* Count bridge opcodes actually emitted into the bytecode *)
open Multi_vm
let () =
  let asm_path = Sys.argv.(1) in
  let ic = open_in asm_path in
  let asm = really_input_string ic (in_channel_length ic) in
  close_in ic;
  match Arm64_lifter.lift_function asm with
  | Error e -> Printf.eprintf "lift failed: %s\n" e; exit 1
  | Ok func ->
      let rng = Random.State.make [| 1337 |] in
      let cfg = Native_vm.Protection_config.default in
      let pkg = Multi_vm_emitter.compile_and_package
        ~rng ~enable_cff:false ~enable_mba:cfg.mba.enabled
        ~mba_depth:cfg.mba.depth ~config:cfg func in
      (* bridge IR instructions present? *)
      let bridge_count = Hashtbl.fold (fun _ (b : Vm_ir.Ir.basic_block) acc ->
        List.fold_left (fun n (i : Vm_ir.Ir.instr) ->
          match i with Vm_ir.Ir.Bridge_to_flow _ | Vm_ir.Ir.Bridge_to_math _ -> n+1 | _ -> n)
          acc b.Vm_ir.Ir.instrs) func.Vm_ir.Ir.cfg.blocks 0 in
      (* injected version: replicate what compile_and_package did *)
      let partition = Partitioner.partition_function func in
      let (bridged, actual) = Multi_vm_emitter.inject_bridge_transitions pkg.bridge partition func in
      let bridge_after = Hashtbl.fold (fun _ (b : Vm_ir.Ir.basic_block) acc ->
        List.fold_left (fun n (i : Vm_ir.Ir.instr) ->
          match i with Vm_ir.Ir.Bridge_to_flow _ | Vm_ir.Ir.Bridge_to_math _ -> n+1 | _ -> n)
          acc b.Vm_ir.Ir.instrs) bridged.Vm_ir.Ir.cfg.blocks 0 in
      Printf.printf "IR bridge instrs: original=%d after_inject=%d (transitions=%d)\n"
        bridge_count bridge_after actual;
      Printf.printf "bytecode words: %d\n" (List.length pkg.bytecode);
      (* decode opcodes: how does encode_raw_word place opcode? try each plausible lane *)
      let lane_counts h = List.fold_left (fun acc w ->
        let op = Int64.to_int (Int64.logand (Int64.shift_right_logical w (8*h)) 0xFFL) in
        let k = Int64.to_int (Int64.logand (Int64.shift_right_logical w (8*h)) 0xFFL) in
        acc) 0 pkg.bytecode in
      ignore lane_counts;
      (* use vm_transform opcode map directly *)
      let get_op i = Native_vm.Vm_transform.opcode_of_index i in
      ignore get_op;
      ()
