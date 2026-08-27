open Ir

let mod_inv64 (k : int64) : int64 =
  let odd_k = Int64.logor k 1L in
  let rec newton x iters =
    if iters = 0 then x
    else
      let kx = Int64.mul odd_k x in
      let two_minus_kx = Int64.sub 2L kx in
      let next_x = Int64.mul x two_minus_kx in
      newton next_x (iters - 1)
  in
  newton odd_k 6

let transform_instr (rng : Random.State.t) (instr : instr) : instr list =
  match instr with
  | Mov { dst = Reg r; src = Imm c } ->
      let roll = Random.State.int rng 5 in
      if roll = 0 then
        (* XOR split: r = (c ^ k) ^ k *)
        let k = Int64.of_int (Random.State.bits rng) in
        let c_k = Int64.logxor c k in
        [
          Mov { dst = Reg r; src = Imm c_k };
          Alu { op = Xor; dst = r; src1 = Reg r; src2 = Imm k; set_flags = false };
        ]
      else if roll = 1 then
        (* ADD split: r = (c - k) + k *)
        let k = Int64.of_int (Random.State.bits rng) in
        let c_k = Int64.sub c k in
        [
          Mov { dst = Reg r; src = Imm c_k };
          Alu { op = Add; dst = r; src1 = Reg r; src2 = Imm k; set_flags = false };
        ]
      else if roll = 2 then
        (* Modular Multiplicative Split: r = (c * k) * k^(-1) mod 2^64 *)
        let raw_k = Int64.logor (Int64.of_int (Random.State.bits rng)) 1L in
        let inv_k = mod_inv64 raw_k in
        let c_scaled = Int64.mul c raw_k in
        [
          Mov { dst = Reg r; src = Imm c_scaled };
          Alu { op = Mul; dst = r; src1 = Reg r; src2 = Imm inv_k; set_flags = false };
        ]
      else if roll = 3 then
        (* Negation Split: r = -(-c) *)
        let neg_c = Int64.neg c in
        [
          Mov { dst = Reg r; src = Imm neg_c };
          Unary { op = Neg; dst = r; src = Reg r; set_flags = false };
        ]
      else
        [ instr ]

  | Alu { op = Add; dst; src1; src2 = Imm c; set_flags = false } when c <> 0L ->
      let roll = Random.State.int rng 3 in
      if roll = 0 then
        (* Add c == Sub (-c) *)
        let neg_c = Int64.neg c in
        [ Alu { op = Sub; dst; src1; src2 = Imm neg_c; set_flags = false } ]
      else if roll = 1 then
        (* 2-Stage additive split: Add c1, Add (c - c1) *)
        let c1 = Int64.shift_right_logical c 1 in
        let c2 = Int64.sub c c1 in
        [
          Alu { op = Add; dst; src1; src2 = Imm c1; set_flags = false };
          Alu { op = Add; dst; src1 = Reg dst; src2 = Imm c2; set_flags = false };
        ]
      else
        [ instr ]

  | Alu { op = Sub; dst; src1; src2 = Imm c; set_flags = false } when c <> 0L ->
      let roll = Random.State.int rng 2 in
      if roll = 0 then
        (* Sub c == Add (-c) *)
        let neg_c = Int64.neg c in
        [ Alu { op = Add; dst; src1; src2 = Imm neg_c; set_flags = false } ]
      else
        [ instr ]

  | Alu { op = Xor; dst; src1; src2 = Imm c; set_flags = false } when c <> 0L ->
      let roll = Random.State.int rng 2 in
      if roll = 0 then
        (* Xor c == Xor c1, Xor (c ^ c1) *)
        let c1 = Int64.of_int (Random.State.bits rng) in
        let c2 = Int64.logxor c c1 in
        [
          Alu { op = Xor; dst; src1; src2 = Imm c1; set_flags = false };
          Alu { op = Xor; dst; src1 = Reg dst; src2 = Imm c2; set_flags = false };
        ]
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
