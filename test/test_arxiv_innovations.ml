(** ASGARD-5877 Test Suite: arXiv Innovations
    Tests for the 4 new OCaml modules from academic research:
    1. Cff.Pop_coupler        (arXiv:1908.01549) - Path-Oriented Protections
    2. Native_vm.Defuse_scrambler (arXiv:2601.12916) - Def-Use Chain Scrambler
    3. Mba_engine.Ncfg_synth  (arXiv:2506.23634) - NCFG Transformer-Resistant MBA
    4. Arm64_lifter.Literal_stitcher (arXiv:2407.08924) - ARM64 Disassembler Disrupter *)

open Alcotest
open Vm_ir
open Mba_engine

(* -------------------------------------------------------------------------- *)
(* 1. POP Path Coupler (arXiv:1908.01549)                                     *)
(* -------------------------------------------------------------------------- *)

let test_pop_digest_determinism () =
  let seed = 0x5877CAFEBABE1337L in
  let d1 = Cff.Pop_coupler.advance_digest seed 0 1L in
  let d2 = Cff.Pop_coupler.advance_digest seed 0 1L in
  check int64 "POP advance_digest: same inputs → same digest" d1 d2

let test_pop_digest_sensitivity () =
  let seed = 0x5877CAFEBABE1337L in
  let d0 = Cff.Pop_coupler.advance_digest seed 0 1L in
  let d1 = Cff.Pop_coupler.advance_digest seed 1 1L in
  let d2 = Cff.Pop_coupler.advance_digest seed 0 2L in
  check bool "POP: different block IDs yield different digest" (d0 <> d1) true;
  check bool "POP: different cond_tags yield different digest" (d0 <> d2) true

let test_pop_ir_transform () =
  let rng = Random.State.make [| 42 |] in
  let b1 = Ir.make_block ~id:0 ~label:"entry" ~instrs:[
    Ir.Mov { dst = Ir.Reg Register.rax; src = Ir.Imm 100L };
    Ir.Ret;
  ] in
  let f = Ir.make_func ~name:"test_fn" ~entry_id:0 ~blocks:[b1] in
  let f_pop = Cff.Pop_coupler.apply_pop_transform ~rng f in
  let b_out = Hashtbl.find f_pop.cfg.blocks 0 in
  check bool "POP transform: digest update prepended to entry block"
    (List.length b_out.instrs > 2) true

(* -------------------------------------------------------------------------- *)
(* 2. Def-Use Scrambler (arXiv:2601.12916)                                    *)
(* -------------------------------------------------------------------------- *)

let test_defuse_scrambler_expands () =
  let rng = Random.State.make [| 123 |] in
  let b = Ir.make_block ~id:0 ~label:"entry" ~instrs:[
    Ir.Mov { dst = Ir.Reg Register.rax; src = Ir.Imm 42L };
    Ir.Alu { op = Ir.Add; dst = Register.rax;
             src1 = Ir.Reg Register.rax; src2 = Ir.Imm 8L; set_flags = false };
    Ir.Ret;
  ] in
  let f = Ir.make_func ~name:"defuse_test" ~entry_id:0 ~blocks:[b] in
  let f_scrambled = Native_vm.Defuse_scrambler.scramble_func_defuse ~rng f in
  let b_out = Hashtbl.find f_scrambled.cfg.blocks 0 in
  check bool "DefUse: Mov and ALU instructions expanded via aliasing"
    (List.length b_out.instrs >= 5) true

let test_defuse_scrambler_ret_preserved () =
  let rng = Random.State.make [| 456 |] in
  let b = Ir.make_block ~id:0 ~label:"entry" ~instrs:[ Ir.Ret ] in
  let f = Ir.make_func ~name:"ret_only" ~entry_id:0 ~blocks:[b] in
  let f_s = Native_vm.Defuse_scrambler.scramble_func_defuse ~rng f in
  let b_out = Hashtbl.find f_s.cfg.blocks 0 in
  check bool "DefUse: Ret instruction passes through unmodified"
    (b_out.instrs = [ Ir.Ret ]) true

(* -------------------------------------------------------------------------- *)
(* 3. NCFG MBA Synthesizer (arXiv:2506.23634)                                 *)
(* -------------------------------------------------------------------------- *)

let test_ncfg_xor_soundness () =
  let rng = Random.State.make [| 2026 |] in
  for _ = 1 to 2000 do
    let x = Random.State.int64 rng 0x7FFFFFFFFFFFFFFFL in
    let y = Random.State.int64 rng 0x7FFFFFFFFFFFFFFFL in
    let env var = if var = "x" then x else if var = "y" then y else 0L in
    let e = Ncfg_synth.synthesize_ncfg_xor ~rng (Mba.Var "x") (Mba.Var "y") in
    let res = Mba.eval env e in
    let exp = Int64.logxor x y in
    if res <> exp then
      failwith (Printf.sprintf "NCFG XOR unsound: x=%LX y=%LX got=%LX exp=%LX" x y res exp)
  done

let test_ncfg_add_soundness () =
  let rng = Random.State.make [| 1337 |] in
  for _ = 1 to 2000 do
    let x = Random.State.int64 rng 0x3FFFFFFFFFFFFFFFL in
    let y = Random.State.int64 rng 0x3FFFFFFFFFFFFFFFL in
    let env var = if var = "x" then x else if var = "y" then y else 0L in
    let e = Ncfg_synth.synthesize_ncfg_add ~rng (Mba.Var "x") (Mba.Var "y") in
    let res = Mba.eval env e in
    let exp = Int64.add x y in
    if res <> exp then
      failwith (Printf.sprintf "NCFG ADD unsound: x=%LX y=%LX got=%LX exp=%LX" x y res exp)
  done

let test_ncfg_sub_soundness () =
  let rng = Random.State.make [| 5877 |] in
  for _ = 1 to 2000 do
    let x = Random.State.int64 rng 0x7FFFFFFFFFFFFFFFL in
    let y = Random.State.int64 rng 0x7FFFFFFFFFFFFFFFL in
    let env var = if var = "x" then x else if var = "y" then y else 0L in
    let e = Ncfg_synth.synthesize_ncfg_sub ~rng (Mba.Var "x") (Mba.Var "y") in
    let res = Mba.eval env e in
    let exp = Int64.sub x y in
    if res <> exp then
      failwith (Printf.sprintf "NCFG SUB unsound: x=%LX y=%LX got=%LX exp=%LX" x y res exp)
  done

let test_ncfg_rewrite_depth2 () =
  let rng = Random.State.make [| 999 |] in
  for _ = 1 to 500 do
    let x = Random.State.int64 rng 0x3FFFFFFFFFFFFFFFL in
    let y = Random.State.int64 rng 0x3FFFFFFFFFFFFFFFL in
    let env var = if var = "x" then x else if var = "y" then y else 0L in
    let e_orig = Mba.Xor (Mba.Var "x", Mba.Var "y") in
    let e_ncfg = Ncfg_synth.rewrite_ncfg ~rng ~depth:2 e_orig in
    let res = Mba.eval env e_ncfg in
    let exp = Int64.logxor x y in
    if res <> exp then
      failwith (Printf.sprintf "NCFG depth-2 rewrite unsound: got=%LX exp=%LX" res exp)
  done

(* -------------------------------------------------------------------------- *)
(* 4. ARM64 Literal Stitcher (arXiv:2407.08924 & 2507.07246)                 *)
(* -------------------------------------------------------------------------- *)

let test_literal_stitcher_structure () =
  let rng = Random.State.make [| 777 |] in
  let payload = 0xDEADBEEFCAFEBEEFL in
  let stitched = Arm64_lifter.Literal_stitcher.stitch_arm64_literal_payload ~rng ~payload in
  let n = String.length stitched in
  let found_adr = ref false in
  for i = 0 to n - 3 do
    if String.sub stitched i 3 = "adr" then found_adr := true
  done;
  check bool "Stitcher: output contains 'adr' instruction" !found_adr true

let test_literal_stitcher_obfuscates () =
  let rng = Random.State.make [| 12345 |] in
  let raw = "    mov x0, #42\n    add x0, x0, #1\n    ret\n" in
  let obf = Arm64_lifter.Literal_stitcher.obfuscate_arm64_asm_sequence ~rng raw in
  check bool "Stitcher: obfuscated listing is at least as long as original"
    (String.length obf >= String.length raw) true

let tests = [
  ("POP: advance_digest determinism",      `Quick, test_pop_digest_determinism);
  ("POP: digest sensitivity to inputs",    `Quick, test_pop_digest_sensitivity);
  ("POP: IR transform prepends digest",    `Quick, test_pop_ir_transform);
  ("DefUse: Mov/ALU expansion via alias",  `Quick, test_defuse_scrambler_expands);
  ("DefUse: Ret passthrough",              `Quick, test_defuse_scrambler_ret_preserved);
  ("NCFG XOR: 2000-vector soundness",      `Quick, test_ncfg_xor_soundness);
  ("NCFG ADD: 2000-vector soundness",      `Quick, test_ncfg_add_soundness);
  ("NCFG SUB: 2000-vector soundness",      `Quick, test_ncfg_sub_soundness);
  ("NCFG depth-2 rewrite soundness",       `Quick, test_ncfg_rewrite_depth2);
  ("ARM64 Stitcher: structure check",      `Quick, test_literal_stitcher_structure);
  ("ARM64 Stitcher: listing obfuscation",  `Quick, test_literal_stitcher_obfuscates);
]
