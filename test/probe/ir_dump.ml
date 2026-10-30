open Multi_vm

let inject_fixed (digest : int64) (rep : Partitioner.partition_report) (f : Vm_ir.Ir.func) : Vm_ir.Ir.func =
  if rep.Partitioner.inter_vm_transitions = 0 then
    let new_blocks = Hashtbl.create (Hashtbl.length f.Vm_ir.Ir.cfg.blocks) in
    Hashtbl.iter (fun id (b : Vm_ir.Ir.basic_block) ->
      let instrs =
        match List.rev b.Vm_ir.Ir.instrs with
        | (Vm_ir.Ir.Ret as ret) :: rest ->
            List.rev (ret :: Vm_ir.Ir.Bridge_to_math digest :: Vm_ir.Ir.Bridge_to_flow digest :: rest)
        | (Vm_ir.Ir.Vm_exit as ex) :: rest ->
            List.rev (ex :: Vm_ir.Ir.Bridge_to_math digest :: Vm_ir.Ir.Bridge_to_flow digest :: rest)
        | other ->
            List.rev other @ [ Vm_ir.Ir.Bridge_to_flow digest; Vm_ir.Ir.Bridge_to_math digest ]
      in Hashtbl.replace new_blocks id { b with Vm_ir.Ir.instrs }) f.Vm_ir.Ir.cfg.blocks;
    { f with Vm_ir.Ir.cfg = { f.Vm_ir.Ir.cfg with blocks = new_blocks } }
  else
    let block_engine = Hashtbl.create 16 in
    List.iter (fun (pb : Partitioner.partitioned_block) ->
      Hashtbl.replace block_engine pb.Partitioner.block.Vm_ir.Ir.id pb.Partitioner.engine) rep.Partitioner.blocks;
    let new_blocks = Hashtbl.create (Hashtbl.length f.Vm_ir.Ir.cfg.blocks) in
    Hashtbl.iter (fun id (b : Vm_ir.Ir.basic_block) ->
      let cur_eng = Hashtbl.find_opt block_engine id in
      let is_math = cur_eng = Some Partitioner.Engine_Math in
      let rev_acc = ref [] in
      List.iter (fun (instr : Vm_ir.Ir.instr) ->
        match instr with
        | Vm_ir.Ir.Jmp (Vm_ir.Ir.BlockId target_id) ->
            let target_eng = Hashtbl.find_opt block_engine target_id in
            if target_eng <> cur_eng && cur_eng <> None && target_eng <> None then begin
              if is_math then rev_acc := Vm_ir.Ir.Bridge_to_math digest :: Vm_ir.Ir.Bridge_to_flow digest :: !rev_acc
              else rev_acc := Vm_ir.Ir.Bridge_to_flow digest :: Vm_ir.Ir.Bridge_to_math digest :: !rev_acc
            end;
            rev_acc := instr :: !rev_acc
        | Vm_ir.Ir.Jcc { target_true = Vm_ir.Ir.BlockId tid; target_false = Vm_ir.Ir.BlockId fid; _ } ->
            let t_eng = Hashtbl.find_opt block_engine tid in
            let f_eng = Hashtbl.find_opt block_engine fid in
            if (t_eng <> cur_eng || f_eng <> cur_eng) && cur_eng <> None then begin
              if is_math then rev_acc := Vm_ir.Ir.Bridge_to_math digest :: Vm_ir.Ir.Bridge_to_flow digest :: !rev_acc
              else rev_acc := Vm_ir.Ir.Bridge_to_flow digest :: Vm_ir.Ir.Bridge_to_math digest :: !rev_acc
            end;
            rev_acc := instr :: !rev_acc
        | _ -> rev_acc := instr :: !rev_acc) b.Vm_ir.Ir.instrs;
      Hashtbl.replace new_blocks id { b with Vm_ir.Ir.instrs = List.rev !rev_acc }) f.Vm_ir.Ir.cfg.blocks;
    { f with Vm_ir.Ir.cfg = { f.Vm_ir.Ir.cfg with blocks = new_blocks } }

let () =
  let asm = {|
    mov x0, #42
    cmp x0, #40
    b.gt .Lgreater
    mov x0, #1
    ret
.Lgreater:
    add x0, x0, #8
    ret
  |} in
  match Arm64_lifter.lift_function asm with
  | Error e -> Printf.eprintf "lift failed: %s\n" e; exit 1
  | Ok func ->
      let rep = Partitioner.partition_function func in
      Printf.printf "== PARTITION == math=%d flow=%d mem=%d trans=%d\n"
        rep.Partitioner.math_blocks rep.Partitioner.flow_blocks rep.Partitioner.memory_blocks
        rep.Partitioner.inter_vm_transitions;
      Printf.printf "== LIFTED IR ==\n%s\n" (Vm_ir.Ir.func_to_string func);
      let digest = Bridge.initial_digest (Bridge.generate_bridge (Random.State.make [| 9292 |])) in
      let bridged = inject_fixed digest rep func in
      Printf.printf "== POST-INJECT IR ==\n%s\n" (Vm_ir.Ir.func_to_string bridged)
