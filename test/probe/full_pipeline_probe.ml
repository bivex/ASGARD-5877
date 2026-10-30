(* Replicate the full pipeline: lift_source on app_arm64.s → partition → package *)
open Multi_vm
let () =
  let path = Sys.argv.(1) in
  let ic = open_in path in
  let text = really_input_string ic (in_channel_length ic) in
  close_in ic;
  match Protect_adapters.Arm64_lifter_adapter.lift_source text with
  | Error e -> Printf.eprintf "lift_source failed: %s\n" e; exit 1
  | Ok (wrapped, _constants) ->
      let funcs = Random_visa_ports.Protect_ports.unwrap_multi_ir wrapped in
      List.iter (fun (n, (func : Vm_ir.Ir.func)) -> Printf.printf "func: %s\n" n) funcs;
      let func : Vm_ir.Ir.func = (snd (List.hd funcs)) in
      Printf.printf "lifted '%s': %d blocks\n" func.Vm_ir.Ir.name (Hashtbl.length func.Vm_ir.Ir.cfg.blocks);
      let rep = Partitioner.partition_function func in
      Printf.printf "partition: math=%d flow=%d mem=%d transitions=%d\n"
        rep.Partitioner.math_blocks rep.Partitioner.flow_blocks rep.Partitioner.memory_blocks rep.Partitioner.inter_vm_transitions;
      List.iter (fun pb ->
        Printf.printf "  B%d %s entry=%b exit=%b\n" pb.Partitioner.block.Vm_ir.Ir.id
          (match pb.Partitioner.engine with
           | Partitioner.Engine_Math -> "MATH" | Partitioner.Engine_Flow -> "FLOW" | Partitioner.Engine_Memory -> "MEM")
          pb.Partitioner.is_bridge_entry pb.Partitioner.is_bridge_exit) rep.Partitioner.blocks;
      let digest = Bridge.initial_digest (Bridge.generate_bridge (Random.State.make [| 1337 |])) in
      let block_engine = Hashtbl.create 16 in
      List.iter (fun (pb : Partitioner.partitioned_block) ->
        Hashtbl.replace block_engine pb.Partitioner.block.Vm_ir.Ir.id pb.Partitioner.engine) rep.Partitioner.blocks;
      let bridged = ref func.Vm_ir.Ir.cfg.blocks and actual = ref 0 in
      if rep.Partitioner.inter_vm_transitions = 0 then begin
        actual := 2;
        let nb = Hashtbl.create (Hashtbl.length func.Vm_ir.Ir.cfg.blocks) in
        Hashtbl.iter (fun id (b : Vm_ir.Ir.basic_block) ->
          let instrs = match List.rev b.Vm_ir.Ir.instrs with
            | (Vm_ir.Ir.Ret as ret) :: rest ->
                List.rev (ret :: Vm_ir.Ir.Bridge_to_math digest :: Vm_ir.Ir.Bridge_to_flow digest :: rest)
            | other -> other @ [ Vm_ir.Ir.Bridge_to_flow digest; Vm_ir.Ir.Bridge_to_math digest ]
          in Hashtbl.replace nb id { b with Vm_ir.Ir.instrs }) func.Vm_ir.Ir.cfg.blocks;
        bridged := nb
      end else begin
        let nb = Hashtbl.create (Hashtbl.length func.Vm_ir.Ir.cfg.blocks) in
        Hashtbl.iter (fun id (b : Vm_ir.Ir.basic_block) ->
          let cur_eng = Hashtbl.find_opt block_engine id in
          let is_math = cur_eng = Some Partitioner.Engine_Math in
          let rev_acc = ref [] in
          List.iter (fun (instr : Vm_ir.Ir.instr) ->
            match instr with
            | Vm_ir.Ir.Jmp (Vm_ir.Ir.BlockId target_id) ->
                let target_eng = Hashtbl.find_opt block_engine target_id in
                if target_eng <> cur_eng && cur_eng <> None && target_eng <> None then begin
                  incr actual;
                  if is_math then rev_acc := Vm_ir.Ir.Bridge_to_flow digest :: !rev_acc
                  else rev_acc := Vm_ir.Ir.Bridge_to_math digest :: !rev_acc
                end;
                rev_acc := instr :: !rev_acc
            | Vm_ir.Ir.Jcc { target_true = Vm_ir.Ir.BlockId tid; target_false = Vm_ir.Ir.BlockId fid; _ } ->
                let t_eng = Hashtbl.find_opt block_engine tid in
                let f_eng = Hashtbl.find_opt block_engine fid in
                if (t_eng <> cur_eng || f_eng <> cur_eng) && cur_eng <> None then begin
                  incr actual;
                  if is_math then rev_acc := Vm_ir.Ir.Bridge_to_flow digest :: !rev_acc
                  else rev_acc := Vm_ir.Ir.Bridge_to_math digest :: !rev_acc
                end;
                rev_acc := instr :: !rev_acc
            | _ -> rev_acc := instr :: !rev_acc) b.Vm_ir.Ir.instrs;
          Hashtbl.replace nb id { b with Vm_ir.Ir.instrs = List.rev !rev_acc }) func.Vm_ir.Ir.cfg.blocks;
        bridged := nb
      end;
      Hashtbl.iter (fun id (b : Vm_ir.Ir.basic_block) ->
        let ops = List.filter_map (fun (i : Vm_ir.Ir.instr) ->
          match i with
          | Vm_ir.Ir.Bridge_to_flow _ -> Some "BRIDGE_TO_FLOW"
          | Vm_ir.Ir.Bridge_to_math _ -> Some "BRIDGE_TO_MATH"
          | _ -> None) b.Vm_ir.Ir.instrs in
        if ops <> [] then Printf.printf "  B%d contains: %s\n" id (String.concat ", " ops))
        !bridged;
      Printf.printf "actual transitions after inject: %d\n" !actual
