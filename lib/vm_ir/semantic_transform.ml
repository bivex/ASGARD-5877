open Ir
open Register

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

(** Generates a nilpotent zero polynomial term N(z)^32 == 0 mod 2^64
    to inject phantom data dependencies into the expression tree. *)
let make_nilpotent_zero (rng : Random.State.t) (scratch : Register.t) : instr list =
  let rand_imm = Int64.of_int (Random.State.bits rng) in
  [
    Mov { dst = Reg scratch; src = Imm rand_imm };
    Alu { op = Mul; dst = scratch; src1 = Reg scratch; src2 = Imm 0x8000000000000000L; set_flags = false };
  ]

let transform_instr (rng : Random.State.t) (instr : instr) : instr list =
  match instr with
  | Mov { dst = Reg r; src = Imm c } ->
      let roll = Random.State.int rng 6 in
      if roll = 0 then
        (* 1. XOR Split: r = (c ^ k) ^ k *)
        let k = Int64.of_int (Random.State.bits rng) in
        let c_k = Int64.logxor c k in
        [
          Mov { dst = Reg r; src = Imm c_k };
          Alu { op = Xor; dst = r; src1 = Reg r; src2 = Imm k; set_flags = false };
        ]
      else if roll = 1 then
        (* 2. Additive Split: r = (c - k) + k *)
        let k = Int64.of_int (Random.State.bits rng) in
        let c_k = Int64.sub c k in
        [
          Mov { dst = Reg r; src = Imm c_k };
          Alu { op = Add; dst = r; src1 = Reg r; src2 = Imm k; set_flags = false };
        ]
      else if roll = 2 then
        (* 3. Modular Multiplicative Inverses in Z/2^64Z: r = (c * k) * k^(-1) mod 2^64 *)
        let raw_k = Int64.logor (Int64.of_int (Random.State.bits rng)) 1L in
        let inv_k = mod_inv64 raw_k in
        let c_scaled = Int64.mul c raw_k in
        [
          Mov { dst = Reg r; src = Imm c_scaled };
          Alu { op = Mul; dst = r; src1 = Reg r; src2 = Imm inv_k; set_flags = false };
        ]
      else if roll = 3 then
        (* 4. Negation Split: r = -(-c) *)
        let neg_c = Int64.neg c in
        [
          Mov { dst = Reg r; src = Imm neg_c };
          Unary { op = Neg; dst = r; src = Reg r; set_flags = false };
        ]
      else if roll = 4 then
        (* 5. Nilpotent Zero Phantom Dependency: r = c + N(z)^32 *)
        let scratch = vtmp0 in
        if r <> scratch then
          make_nilpotent_zero rng scratch @
          [
            Mov { dst = Reg r; src = Imm c };
            Alu { op = Add; dst = r; src1 = Reg r; src2 = Reg scratch; set_flags = false };
          ]
        else
          [ instr ]
      else
        [ instr ]

  | Alu { op = Add; dst; src1; src2 = Imm c; set_flags = false } when c <> 0L ->
      let roll = Random.State.int rng 4 in
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
      else if roll = 2 then
        (* Modular multiplication scale *)
        let raw_k = Int64.logor (Int64.of_int (Random.State.bits rng)) 1L in
        let inv_k = mod_inv64 raw_k in
        [
          Alu { op = Add; dst; src1; src2 = Imm c; set_flags = false };
          Alu { op = Mul; dst; src1 = Reg dst; src2 = Imm raw_k; set_flags = false };
          Alu { op = Mul; dst; src1 = Reg dst; src2 = Imm inv_k; set_flags = false };
        ]
      else
        [ instr ]

  | Alu { op = Sub; dst; src1; src2 = Imm c; set_flags = false } when c <> 0L ->
      let roll = Random.State.int rng 3 in
      if roll = 0 then
        (* Sub c == Add (-c) *)
        let neg_c = Int64.neg c in
        [ Alu { op = Add; dst; src1; src2 = Imm neg_c; set_flags = false } ]
      else if roll = 1 then
        (* 2-Stage subtractive split: Sub c1, Sub (c - c1) *)
        let c1 = Int64.shift_right_logical c 1 in
        let c2 = Int64.sub c c1 in
        [
          Alu { op = Sub; dst; src1; src2 = Imm c1; set_flags = false };
          Alu { op = Sub; dst; src1 = Reg dst; src2 = Imm c2; set_flags = false };
        ]
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
