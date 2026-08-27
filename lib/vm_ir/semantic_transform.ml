open Ir

let transform_instr (rng : Random.State.t) (instr : instr) : instr list =
  match instr with
  | Mov { dst = Reg r; src = Imm c } ->
      let roll = Random.State.int rng 3 in
      if roll = 0 then
        let k = Int64.of_int (Random.State.bits rng) in
        let c_k = Int64.logxor c k in
        [
          Mov { dst = Reg r; src = Imm c_k };
          Alu { op = Xor; dst = r; src1 = Reg r; src2 = Imm k; set_flags = false };
        ]
      else if roll = 1 then
        let k = Int64.of_int (Random.State.bits rng) in
        let c_k = Int64.sub c k in
        [
          Mov { dst = Reg r; src = Imm c_k };
          Alu { op = Add; dst = r; src1 = Reg r; src2 = Imm k; set_flags = false };
        ]
      else
        [ instr ]
  | Alu { op = Add; dst; src1; src2 = Imm c; set_flags = false } when c <> 0L ->
      let roll = Random.State.int rng 2 in
      if roll = 0 then
        let neg_c = Int64.neg c in
        [ Alu { op = Sub; dst; src1; src2 = Imm neg_c; set_flags = false } ]
      else
        [ instr ]
  | _ -> [ instr ]

let transform_block ~rng (b : basic_block) : basic_block =
  let new_instrs = List.concat_map (transform_instr rng) b.instrs in
  { b with instrs = new_instrs }

let transform_func ~(seed : Seed.t) (f : func) : func =
  let rng = Seed.make_rng seed.mba_seed in
  let new_blocks = Hashtbl.create (Hashtbl.length f.cfg.blocks) in
  Hashtbl.iter (fun id b ->
    let tb = transform_block ~rng b in
    Hashtbl.replace new_blocks id tb
  ) f.cfg.blocks;
  { f with cfg = { f.cfg with blocks = new_blocks } }
