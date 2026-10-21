(** Decoy VM Manifold — Believable Decoy Logic Synthesizer.
    ─────────────────────────────────────────────────────────────────
    Synthesizes semantically believable, structurally complex decoy
    validation routines (ARX / Feistel rounds, bitwise permutations,
    polynomial accumulators) to serve as the executable payload for
    the Decoy VM under analysis pressure. *)

open Vm_ir

let synth_decoy_validator_func ~(seed : int64) ~(name : string) : Ir.func =
  let c1 = Int64.logxor seed 0x5877CAFE1337BEEFL in
  let c2 = Int64.logxor (Int64.mul seed 0x9E3779B97F4A7C15L) 0xDEADBEEF5A5A5A5AL in
  let c3 = 0xBF58476D1CE4E5B9L in

  let b1_instrs = [
    Ir.Mov { dst = Reg Register.rax; src = Imm c1 };
    Ir.Mov { dst = Reg Register.vtmp0; src = Reg Register.rdi };
    Ir.Alu { op = Add; dst = Register.rax; src1 = Reg Register.rax; src2 = Reg Register.vtmp0; set_flags = false };
    Ir.Jmp (BlockId 2);
  ] in
  let b1 = Ir.make_block ~id:1 ~label:(name ^ "_decoy_entry") ~instrs:b1_instrs in

  let b2_instrs = [
    Ir.Alu { op = Xor; dst = Register.vtmp1; src1 = Reg Register.rsi; src2 = Imm c2; set_flags = false };
    Ir.Alu { op = Add; dst = Register.rax; src1 = Reg Register.rax; src2 = Reg Register.vtmp1; set_flags = false };
    Ir.Alu { op = Mul; dst = Register.rax; src1 = Reg Register.rax; src2 = Imm c3; set_flags = false };
    Ir.Jmp (BlockId 3);
  ] in
  let b2 = Ir.make_block ~id:2 ~label:(name ^ "_decoy_feistel") ~instrs:b2_instrs in

  let b3_instrs = [
    Ir.Alu { op = Shr; dst = Register.vtmp0; src1 = Reg Register.rax; src2 = Imm 17L; set_flags = false };
    Ir.Alu { op = Shl; dst = Register.vtmp1; src1 = Reg Register.rax; src2 = Imm 47L; set_flags = false };
    Ir.Alu { op = Xor; dst = Register.rax; src1 = Reg Register.vtmp0; src2 = Reg Register.vtmp1; set_flags = false };
    Ir.Alu { op = And; dst = Register.vtmp2; src1 = Reg Register.rax; src2 = Imm 1L; set_flags = true };
    Ir.Jcc { cond = Flags.E; target_true = BlockId 4; target_false = BlockId 5 };
  ] in
  let b3 = Ir.make_block ~id:3 ~label:(name ^ "_decoy_permute") ~instrs:b3_instrs in

  let b4_instrs = [
    (* Plausible validation success path *)
    Ir.Mov { dst = Reg Register.rax; src = Imm (Int64.logxor (Int64.add seed 0x1337L) 0x5877L) };
    Ir.Ret;
  ] in
  let b4 = Ir.make_block ~id:4 ~label:(name ^ "_decoy_success") ~instrs:b4_instrs in

  let b5_instrs = [
    (* Plausible validation fallback path *)
    Ir.Mov { dst = Reg Register.rax; src = Imm 0L };
    Ir.Ret;
  ] in
  let b5 = Ir.make_block ~id:5 ~label:(name ^ "_decoy_fallback") ~instrs:b5_instrs in

  Ir.make_func ~name ~entry_id:1 ~blocks:[ b1; b2; b3; b4; b5 ]

let synth_decoy_bytecode ~(rng : Random.State.t) ~(seed : int64) ~(name : string) : int64 list =
  let func = synth_decoy_validator_func ~seed ~name in
  let pkg = Vm_emitter.compile_and_package ~rng func in
  pkg.bytecode
