open Ir

(* Per-call random 64-bit odd mask — avoids the globally-shared even_bit_mask
   / odd_bit_mask constants that appear throughout the binary and form an
   instant YARA signature. *)
let rand_u64 rng =
  let hi = Int64.of_int (Random.State.bits rng) in
  let mi = Int64.of_int (Random.State.bits rng) in
  let lo = Int64.of_int (Random.State.bits rng) in
  Int64.(logor (logor (shift_left hi 42) (shift_left mi 21)) lo)

(* Random odd 64-bit mask: used where we need a mask whose complement is also
   meaningful (no zero/all-ones degenerate case). *)
let rand_odd rng =
  Int64.logor (rand_u64 rng) 1L

(* Select the Jcc condition for a given family index.  Mixing conditions
   prevents a single-byte opcode tell from flagging 100 % of predicates. *)
let family_cond (family : int) (rng : Random.State.t) : Flags.condition =
  (* Each family maps to one of three condition classes based on its invariant
     structure; within a class we pick a semantically equivalent but
     syntactically distinct variant so the distribution is non-degenerate. *)
  match family with
  | 0 | 2 | 4 | 6 ->
      (* Zero-result families: the comparison leaves ZF=1.
         Mix E / NE on the negated branch so we use both opcodes. *)
      if Random.State.bool rng then Flags.E else Flags.NE
  | 1 ->
      (* Unsigned-below: the SplitMix high-bit test leaves CF=0 after CMP. *)
      Flags.AE
  | 3 ->
      (* Bit-0 clear → unsigned below 1 after AND+CMP or equivalently NE after
         CMP 0.  Alternate with B for variety. *)
      if Random.State.bool rng then Flags.E else Flags.AE
  | _ (* 5 *) ->
      Flags.E

(* When family_cond returns NE the predicate jumps to target_true on ZF=0,
   so the comparison must produce a non-zero result rather than zero.
   This helper flips the branch targets accordingly. *)
let directed_jcc cond ~zero_target ~nonzero_target
    ~(target_true : target) ~(target_decoy : target) : instr =
  match cond with
  | Flags.E | Flags.AE | Flags.B ->
      (* jump to target_true when condition is satisfied: zero / AE / B *)
      ignore (zero_target, nonzero_target);
      Jcc { cond; target_true; target_false = target_decoy }
  | Flags.NE ->
      (* NE means ZF=0 → non-zero result → swap targets so the always-taken
         path still leads to target_true *)
      ignore (zero_target, nonzero_target);
      Jcc { cond; target_true = target_decoy; target_false = target_true }
  | _ ->
      Jcc { cond; target_true; target_false = target_decoy }

type opaque_kind =
  | BitmaskDisjoint
  | AdditiveIdentity
  | ParityNilpotent
  | NonLinearMemoryAliasing
  | ModularExpInvariant

let generate_zero_predicate ~rng ~scratch ~target_true ~target_decoy : instr list =
  let family = Random.State.int rng 7 in
  let cond = family_cond family rng in
  match family with

  | 0 ->
      (* BitmaskDisjoint: (scratch & m) & (scratch & ~m) == 0
         Any bit of scratch lands in exactly one half of the m / ~m partition,
         so the AND of the two halves is always 0.
         m is a fresh random odd mask — disjoint from ~m by construction.
         Step 1 computes scratch & m (even-bit half).
         Step 2 ANDs that result with ~m (odd-bit mask) → 0, since no bit
         can belong to both halves.  The input value of scratch determines
         the intermediate but not the final result; abstract interpretation
         without a disjointness rule on complement masks cannot fold this. *)
      let m  = rand_odd rng in
      let nm = Int64.lognot m in
      let salt = rand_u64 rng in
      [
        Alu { op = And; dst = scratch; src1 = Reg scratch; src2 = Imm m;
              set_flags = false };
        Alu { op = And; dst = scratch; src1 = Reg scratch; src2 = Imm nm;
              set_flags = false };
        (* Mix in a unique salt+desalt to differentiate call sites in the binary *)
        Alu { op = Add; dst = scratch; src1 = Reg scratch; src2 = Imm salt;
              set_flags = false };
        Alu { op = Sub; dst = scratch; src1 = Reg scratch; src2 = Imm salt;
              set_flags = false };
        Cmp { src1 = Reg scratch; src2 = Imm 0L };
        directed_jcc cond ~zero_target:target_true ~nonzero_target:target_decoy
          ~target_true ~target_decoy;
      ]

  | 1 ->
      (* AdditiveIdentity via bijective odd-forcing:
         Let k = random odd constant.  (scratch * k) is a bijection on Z_{2^64}.
         ORing with 1 forces bit 0 = 1.  ANDing with 1 then yields 1.
         CMP 1 → E is always taken.  Single-register; abstract interpretation
         must know OR 1 guarantees bit 0 = 1 after the AND 1 step. *)
      let k = rand_odd rng in
      [
        Alu { op = Mul; dst = scratch; src1 = Reg scratch; src2 = Imm k;
              set_flags = false };
        Alu { op = Or;  dst = scratch; src1 = Reg scratch; src2 = Imm 1L;
              set_flags = false };
        Alu { op = And; dst = scratch; src1 = Reg scratch; src2 = Imm 1L;
              set_flags = false };
        Cmp { src1 = Reg scratch; src2 = Imm 1L };
        Jcc { cond = Flags.E; target_true; target_false = target_decoy };
      ]

  | 2 ->
      (* ParityNilpotent: (scratch & 1) XOR (scratch & 1) = 0 always.
         Reading the same register twice in Xor (src1=Reg scratch, src2=Reg scratch)
         forces a self-cancel regardless of what the AND produced.  The & 1 step
         creates a data-dependent sub-expression that defeats constant propagation
         on the AND output (the value is 0 or 1, runtime-dependent), while the Xor
         of any value with itself is provably 0 only if the prover tracks aliasing
         between src1 and src2.  Then a random salt add+sub keeps the stream unique. *)
      let salt = rand_u64 rng in
      [
        Alu { op = And; dst = scratch; src1 = Reg scratch; src2 = Imm 1L;
              set_flags = false };
        Alu { op = Xor; dst = scratch; src1 = Reg scratch; src2 = Reg scratch;
              set_flags = false };
        Alu { op = Add; dst = scratch; src1 = Reg scratch; src2 = Imm salt;
              set_flags = false };
        Alu { op = Sub; dst = scratch; src1 = Reg scratch; src2 = Imm salt;
              set_flags = false };
        Cmp { src1 = Reg scratch; src2 = Imm 0L };
        directed_jcc cond ~zero_target:target_true ~nonzero_target:target_decoy
          ~target_true ~target_decoy;
      ]

  | 3 ->
      (* NonLinear Polynomial: (scratch * 2^63) & 1 == 0
         scratch * 2^63 = scratch << 63.  In Z_{2^64} this always clears all bits
         except bit 63 of scratch, which lands in bit 63 of the result.
         Bit 0 of the result is always 0 regardless of scratch.
         The AND 1 then CMP 0 is always taken. *)
      [
        Alu { op = Mul; dst = scratch; src1 = Reg scratch;
              src2 = Imm 0x8000000000000000L; set_flags = false };
        Alu { op = And; dst = scratch; src1 = Reg scratch;
              src2 = Imm 1L; set_flags = false };
        Cmp { src1 = Reg scratch; src2 = Imm 0L };
        directed_jcc cond ~zero_target:target_true ~nonzero_target:target_decoy
          ~target_true ~target_decoy;
      ]

  | 4 ->
      (* 3-Variable Boolean Lattice Zero: (x | x) - (x & x) - (x ^ x)
         = x - x - 0 = 0.  Written in single-register form using the identity
         (a|b)-(a&b) == a^b, so (x^x) - (x^x) = 0.
         Unlike the old duplicate this uses two separate ALU steps with distinct
         per-call constants so the instruction stream is unique each time. *)
      let salt = rand_u64 rng in
      [
        (* Step 1: scratch = scratch ^ scratch  (always 0) *)
        Alu { op = Xor; dst = scratch; src1 = Reg scratch;
              src2 = Reg scratch; set_flags = false };
        (* Step 2: add a random salt, then subtract it: still 0 *)
        Alu { op = Add; dst = scratch; src1 = Reg scratch;
              src2 = Imm salt; set_flags = false };
        Alu { op = Sub; dst = scratch; src1 = Reg scratch;
              src2 = Imm salt; set_flags = false };
        Cmp { src1 = Reg scratch; src2 = Imm 0L };
        directed_jcc cond ~zero_target:target_true ~nonzero_target:target_decoy
          ~target_true ~target_decoy;
      ]

  | 5 ->
      (* NonLinearMemoryAliasing: write scratch to a stack slot and reload.
         The value round-trips through memory; after XOR with the original
         the result is 0.  SMT array theory must track the write then read;
         alias analysis cannot eliminate the store/load pair without proof of
         no intervening writes.  We implement this at the IR level as a Push/Pop
         pair, which the VM realises as actual stack memory operations. *)
      [
        Push (Reg scratch);      (* store scratch to stack memory *)
        Pop  (Reg scratch);      (* reload into scratch *)
        Alu { op = Xor; dst = scratch; src1 = Reg scratch;
              src2 = Reg scratch; set_flags = false }; (* x ^ x = 0 *)
        Cmp { src1 = Reg scratch; src2 = Imm 0L };
        Jcc { cond = Flags.E; target_true; target_false = target_decoy };
      ]

  | _ (* 6 *) ->
      (* ModularExpInvariant: ((scratch | 1)^2 - 1) & 7 == 0
         Let o = scratch | 1 (always odd).  o^2 - 1 = (o-1)(o+1).
         o is odd → (o-1) and (o+1) are consecutive even numbers, so one of
         them is divisible by 4.  Product divisible by 8 → bits 0..2 all 0.
         AND 7 == 0 always.  Requires the prover to know that (2k)(2k+2) = 4k(k+1)
         and k(k+1) is always even. *)
      [
        Alu { op = Or;  dst = scratch; src1 = Reg scratch;
              src2 = Imm 1L; set_flags = false };   (* o = scratch | 1 *)
        Alu { op = Mul; dst = scratch; src1 = Reg scratch;
              src2 = Reg scratch; set_flags = false }; (* o^2 *)
        Alu { op = Sub; dst = scratch; src1 = Reg scratch;
              src2 = Imm 1L; set_flags = false };   (* o^2 - 1 *)
        Alu { op = And; dst = scratch; src1 = Reg scratch;
              src2 = Imm 7L; set_flags = false };   (* & 7 *)
        Cmp { src1 = Reg scratch; src2 = Imm 0L };
        directed_jcc cond ~zero_target:target_true ~nonzero_target:target_decoy
          ~target_true ~target_decoy;
      ]
