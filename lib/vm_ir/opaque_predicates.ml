open Ir

type opaque_kind =
  | BitmaskDisjoint
  | AdditiveIdentity
  | ParityNilpotent

let generate_zero_predicate ~rng ~scratch ~target_true ~target_decoy : instr list =
  let roll = Random.State.int rng 3 in
  match roll with
  | 0 ->
      (* Bitmask Disjoint: (scratch & 0x55..) + (scratch & 0xAA..) - scratch == 0 *)
      let mask_even = 0x5555555555555555L in
      let mask_odd  = -0x5555555555555556L in
      [
        Mov { dst = Reg scratch; src = Imm mask_even };
        Alu { op = And; dst = scratch; src1 = Reg scratch; src2 = Imm mask_odd; set_flags = true };
        Jcc { cond = Flags.E; target_true; target_false = target_decoy };
      ]
  | 1 ->
      (* Additive Identity: (scratch ^ scratch) == 0 *)
      [
        Alu { op = Xor; dst = scratch; src1 = Reg scratch; src2 = Reg scratch; set_flags = true };
        Jcc { cond = Flags.E; target_true; target_false = target_decoy };
      ]
  | _ ->
      (* Parity Zero Invariant: 0 * scratch == 0 *)
      [
        Alu { op = Mul; dst = scratch; src1 = Reg scratch; src2 = Imm 0L; set_flags = true };
        Cmp { src1 = Reg scratch; src2 = Imm 0L };
        Jcc { cond = Flags.E; target_true; target_false = target_decoy };
      ]
