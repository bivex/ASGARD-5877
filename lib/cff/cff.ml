open Vm_ir

type cff_options = {
  inject_opaque_predicates : bool;
  obfuscate_states : bool;
}

let default_cff_options = {
  inject_opaque_predicates = false; (* default false, can enable explicitly *)
  obfuscate_states = true;
}

let inject_opaque_predicate ~rng ~trap_block_id (b : Ir.basic_block) =
  let _ = rng in
  (* Invariant: x & 1 and (x + 1) & 1: one is always 0, so x * (x + 1) is always even *)
  let opaque_check = [
    Ir.Mov { dst = Ir.Reg Register.vtmp0; src = Ir.Reg Register.rax };
    Ir.Alu { op = Ir.Add; dst = Register.vtmp1; src1 = Ir.Reg Register.vtmp0; src2 = Ir.Imm 1L; set_flags = false };
    Ir.Alu { op = Ir.And; dst = Register.vtmp0; src1 = Ir.Reg Register.vtmp0; src2 = Ir.Reg Register.vtmp1; set_flags = false };
    Ir.Alu { op = Ir.And; dst = Register.vtmp0; src1 = Ir.Reg Register.vtmp0; src2 = Ir.Imm 1L; set_flags = true };
    Ir.Cmp { src1 = Ir.Reg Register.vtmp0; src2 = Ir.Imm 0L };
    (* If not equal to 0 (which is mathematically impossible), jump to trap *)
    Ir.Jcc { cond = Flags.NE; target_true = Ir.BlockId trap_block_id; target_false = Ir.Label b.label };
  ] in
  { b with instrs = opaque_check @ b.instrs }

let flatten_func ?(options = default_cff_options) ~rng (func : Ir.func) =
  let original_blocks = Hashtbl.fold (fun _ b acc -> b :: acc) func.cfg.blocks [] in
  let sorted_orig = List.sort (fun (a : Ir.basic_block) (b : Ir.basic_block) -> Int.compare a.id b.id) original_blocks in
  let n = List.length sorted_orig in
  if n <= 1 then
    (* Trivial 1-block function doesn't need flattening *)
    Ok func
  else
    let max_id = List.fold_left (fun acc (b : Ir.basic_block) -> max acc b.id) 0 sorted_orig in
    let entry_block_id = max_id + 1 in
    let trap_block_id = max_id + 2 in
    let disp_base_id = max_id + 3 in

    (* Map block IDs to unique random 64-bit state keys *)
    let state_map = Hashtbl.create n in
    let used_states = Hashtbl.create n in
    List.iter
      (fun (b : Ir.basic_block) ->
        let rec gen_state () =
          let s = Int64.logand (Int64.of_int32 (Random.State.int32 rng Int32.max_int)) 0xFFFFFFFEL in
          let s = if s = 0L then 0x100L else s in
          if Hashtbl.mem used_states s then gen_state ()
          else begin
            Hashtbl.replace used_states s ();
            s
          end
        in
        Hashtbl.replace state_map b.id (gen_state ()))
      sorted_orig;

    let get_state bid =
      match Hashtbl.find_opt state_map bid with
      | Some s -> s
      | None -> 0xDEADBEEFL
    in

    (* Entry Block: sets state to func.cfg.entry_id's state and jumps to disp_base_id *)
    let initial_state = get_state func.cfg.entry_id in
    let entry_instrs = [
      Ir.Mov { dst = Ir.Reg Register.vtmp3; src = Ir.Imm initial_state };
      Ir.Jmp (Ir.BlockId disp_base_id);
    ] in
    let entry_block = Ir.make_block ~id:entry_block_id ~label:(func.name ^ "_cff_entry") ~instrs:entry_instrs in

    (* Trap Block *)
    let trap_block = Ir.make_block ~id:trap_block_id ~label:(func.name ^ "_cff_trap") ~instrs:[ Ir.Trap "CFF State Violation" ] in

    (* Dispatch Blocks Ladder: disp_base_id + i *)
    let disp_blocks = ref [] in
    for i = 0 to n - 1 do
      let cur_disp_id = disp_base_id + i in
      let next_disp_target =
        if i + 1 < n then Ir.BlockId (disp_base_id + i + 1)
        else Ir.BlockId trap_block_id
      in
      let target_b = List.nth sorted_orig i in
      let target_state = get_state target_b.id in
      let d_instrs = [
        Ir.Cmp { src1 = Ir.Reg Register.vtmp3; src2 = Ir.Imm target_state };
        Ir.Jcc { cond = Flags.E; target_true = Ir.BlockId target_b.id; target_false = next_disp_target };
      ] in
      let blk = Ir.make_block ~id:cur_disp_id ~label:(Printf.sprintf "%s_disp_%d" func.name i) ~instrs:d_instrs in
      disp_blocks := blk :: !disp_blocks
    done;

    (* Transform each original block: redirect control flow back to disp_base_id *)
    let transformed_blocks =
      List.map
        (fun (b : Ir.basic_block) ->
          let rev_instrs = List.rev b.instrs in
          let new_instrs =
            match rev_instrs with
            | [] -> [ Ir.Jmp (Ir.BlockId disp_base_id) ]
            | last :: body_rev -> (
                let body = List.rev body_rev in
                match last with
                | Ir.Jmp (Ir.BlockId target_id) ->
                    let next_state = get_state target_id in
                    body @ [
                      Ir.Mov { dst = Ir.Reg Register.vtmp3; src = Ir.Imm next_state };
                      Ir.Jmp (Ir.BlockId disp_base_id);
                    ]
                | Ir.Jcc { cond; target_true = Ir.BlockId t_id; target_false = Ir.BlockId f_id } ->
                    let state_true = get_state t_id in
                    let state_false = get_state f_id in
                    body @ [
                      Ir.Mov { dst = Ir.Reg Register.vtmp0; src = Ir.Imm state_true };
                      Ir.Mov { dst = Ir.Reg Register.vtmp1; src = Ir.Imm state_false };
                      Ir.Cmov { cond; dst = Register.vtmp1; src = Ir.Reg Register.vtmp0 };
                      Ir.Mov { dst = Ir.Reg Register.vtmp3; src = Ir.Reg Register.vtmp1 };
                      Ir.Jmp (Ir.BlockId disp_base_id);
                    ]
                | Ir.Ret | Ir.Vm_exit | Ir.Trap _ ->
                    b.instrs
                | other ->
                    body @ [ other; Ir.Jmp (Ir.BlockId disp_base_id) ])
          in
          let res_block = { b with instrs = new_instrs } in
          if options.inject_opaque_predicates && b.id <> func.cfg.entry_id then
            inject_opaque_predicate ~rng ~trap_block_id res_block
          else res_block)
        sorted_orig
    in

    let all_blocks = (entry_block :: trap_block :: !disp_blocks) @ transformed_blocks in
    let new_func = Ir.make_func ~name:func.name ~entry_id:entry_block_id ~blocks:all_blocks in
    Ok new_func

module Pop_coupler = Pop_coupler
