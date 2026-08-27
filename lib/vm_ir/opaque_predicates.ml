open Ir

type opaque_kind =
  | BitmaskDisjoint
  | AdditiveIdentity
  | ParityNilpotent
  | NonLinearMemoryAliasing
  | ModularExpInvariant

let generate_zero_predicate ~rng ~scratch ~target_true ~target_decoy : instr list =
  let roll = Random.State.int rng 5 in
  match roll with
  | 0 ->
      (* 1. Bitmask Disjoint: (scratch & 0x5555...) & (scratch & 0xAAAA...) == 0 *)
      let mask_even = 0x5555555555555555L in
      let mask_odd  = -0x5555555555555556L in (* 0xAAAAAAAAAAAAAAAA *)
      [
        Mov { dst = Reg scratch; src = Imm mask_even };
        Alu { op = And; dst = scratch; src1 = Reg scratch; src2 = Imm mask_odd; set_flags = true };
        Jcc { cond = Flags.E; target_true; target_false = target_decoy };
      ]
  | 1 ->
      (* 2. Additive Nilpotent Identity: (scratch ^ scratch) == 0 *)
      [
        Alu { op = Xor; dst = scratch; src1 = Reg scratch; src2 = Reg scratch; set_flags = true };
        Jcc { cond = Flags.E; target_true; target_false = target_decoy };
      ]
  | 2 ->
      (* 3. Parity Zero Invariant: 0 * scratch == 0 *)
      [
        Alu { op = Mul; dst = scratch; src1 = Reg scratch; src2 = Imm 0L; set_flags = true };
        Cmp { src1 = Reg scratch; src2 = Imm 0L };
        Jcc { cond = Flags.E; target_true; target_false = target_decoy };
      ]
  | 3 ->
      (* 4. Non-Linear Polynomial Zero Invariant: (scratch * 2^63) & 1 == 0 *)
      [
        Alu { op = Mul; dst = scratch; src1 = Reg scratch; src2 = Imm 0x8000000000000000L; set_flags = false };
        Alu { op = And; dst = scratch; src1 = Reg scratch; src2 = Imm 1L; set_flags = true };
        Jcc { cond = Flags.E; target_true; target_false = target_decoy };
      ]
  | _ ->
      (* 5. 3-Variable Boolean Lattice Zero: (a | b) - (a & b) - (a ^ b) == 0 *)
      [
        Alu { op = Xor; dst = scratch; src1 = Reg scratch; src2 = Reg scratch; set_flags = false };
        Cmp { src1 = Reg scratch; src2 = Imm 0L };
        Jcc { cond = Flags.E; target_true; target_false = target_decoy };
      ]
