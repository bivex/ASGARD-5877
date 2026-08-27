open Vm_ir

type scramble_level = Light | Aggressive | SOTA

type defuse_config = {
  level : scramble_level;
  alias_depth : int;
  opaque_alias_mask : int64;
}

let default_defuse_config = {
  level = SOTA;
  alias_depth = 2;
  opaque_alias_mask = 0x5877A5A5CAFEBEEFL;
}

let scramble_instr ~config ~rng (instr : Ir.instr) : Ir.instr list =
  match instr with
  | Ir.Mov { dst; src } ->
      let _ = rng in
      let k = Int64.logand config.opaque_alias_mask 0xFFFFFFFFL in
      (match dst with
      | Ir.Reg d_reg ->
          [
            (* Blind write through intermediate temporary *)
            Ir.Mov { dst = Ir.Reg Register.vtmp0; src };
            Ir.Alu { op = Ir.Xor; dst = Register.vtmp0; src1 = Ir.Reg Register.vtmp0; src2 = Ir.Imm k; set_flags = false };
            Ir.Mov { dst = Ir.Reg d_reg; src = Ir.Reg Register.vtmp0 };
            Ir.Alu { op = Ir.Xor; dst = d_reg; src1 = Ir.Reg d_reg; src2 = Ir.Imm k; set_flags = false };
          ]
      | _ -> [ instr ])
  | Ir.Alu { op; dst; src1; src2; set_flags } ->
      if set_flags then [ instr ]
      else
        let r_dummy = Register.vtmp1 in
        [
          (* Insert aliased side-effect computation to break LLVM dataflow graph *)
          Ir.Mov { dst = Ir.Reg r_dummy; src = src1 };
          Ir.Alu { op; dst; src1; src2; set_flags = false };
          Ir.Alu { op = Ir.And; dst = r_dummy; src1 = Ir.Reg r_dummy; src2 = Ir.Imm 0L; set_flags = false };
        ]
  | other -> [ other ]

let scramble_func_defuse ?(config = default_defuse_config) ~rng (func : Ir.func) =
  let orig_blocks = Hashtbl.fold (fun _ b acc -> b :: acc) func.cfg.blocks [] in
  let sorted_orig = List.sort (fun (a : Ir.basic_block) (b : Ir.basic_block) -> Int.compare a.id b.id) orig_blocks in

  let transformed_blocks =
    List.map
      (fun (b : Ir.basic_block) ->
        let new_instrs =
          List.concat_map (fun instr -> scramble_instr ~config ~rng instr) b.instrs
        in
        { b with instrs = new_instrs })
      sorted_orig
  in

  Ir.make_func ~name:func.name ~entry_id:func.cfg.entry_id ~blocks:transformed_blocks
