(** examples/amplifier_demo/demo_amplifier.ml
    Standalone smoke-demo for Bytecode_amplifier.
    Собирается через build_amplifier.sh; никаких зависимостей от
    тестового фреймворка — только Stack_vm + Mba_engine.

    Программа:
      ┌──────────────────────────────────────────────────────────┐
      │  ctx[0] = 0xDEAD_BEEF__CAFE_BABEn                        │
      │  ctx[1] = 0x0102_0304_0506_0708n                         │
      │                                                          │
      │  entry:                                                   │
      │    PushImm 0xCAFE_0000n        ; скрытая константа        │
      │    PushReg 0                   ; ctx[0]                   │
      │    PushReg 1                   ; ctx[1]                   │
      │    Add                         ; ctx[0] + ctx[1]          │
      │    Sub                         ; PushImm - (sum)          │
      │    Mul                         ; * ctx[0] -- нужен Mul→tw │
      │    PopReg 2                    ; ctx[2] = result          │
      │    PushReg 0                   ; флаги живут после Add→Sub│
      │    PushReg 1                   ;                          │
      │    Add                         ; ← flag-unsafe: Setcc за  │
      │    Setcc Vm_ir.Flags.G         ; ← ним                    │
      │    PopReg 3                    ; ctx[3] = G-flag result    │
      │    Exit                                                   │
      └──────────────────────────────────────────────────────────┘

    После амплификации:
      • ctx[2] и ctx[3] должны совпасть с оригиналом.
      • Число опкодов вырастает (expansion ratio печатается).
      • Детерминизм: два прогона с одним seed дают одинаковый листинг.
*)

open Stack_vm.Stack_ir
open Stack_vm.Stack_eval
module Amp = Stack_vm.Bytecode_amplifier

(* ------------------------------------------------------------------ *)
(* Построение demo-программы                                           *)
(* ------------------------------------------------------------------ *)

let ctx0 = 0xDEADBEEFCAFEBABEL
let ctx1 = 0x0102030405060708L

let make_demo_program () : program =
  let ops =
    [ PushImm 0xCAFE0000L
    ; PushReg 0
    ; PushReg 1
    ; Add
    ; Sub
    ; PushReg 0
    ; Mul
    ; PopReg 2          (* ctx[2] = result *)
    ; PushReg 0
    ; PushReg 1
    ; Add               (* флаги живы: Setcc сразу после *)
    ; Setcc Vm_ir.Flags.G
    ; PopReg 3          (* ctx[3] = G-flag *)
    ; Exit
    ]
  in
  let blocks = Hashtbl.create 1 in
  Hashtbl.replace blocks 0 { id = 0; label = "entry"; ops };
  { entry_id = 0; blocks; context_slots = 16 }

(* ------------------------------------------------------------------ *)
(* Вспомогательные функции                                             *)
(* ------------------------------------------------------------------ *)

let run_prog prog =
  run_program ~initial_ctx:[(0, ctx0); (1, ctx1)] prog

let sep () = print_endline (String.make 60 '-')

let print_prog label prog =
  Printf.printf "\n=== %s ===\n" label;
  print_endline (program_to_string prog)

(* ------------------------------------------------------------------ *)
(* Сценарии                                                            *)
(* ------------------------------------------------------------------ *)

let scenario_correctness () =
  sep ();
  print_endline "SCENARIO 1 — Correctness across all profiles";
  sep ();
  let orig = make_demo_program () in
  let st0  = run_prog orig in
  let r2   = get_reg st0 2 in
  let r3   = get_reg st0 3 in
  Printf.printf "Original  ctx[2]=0x%Lx  ctx[3]=0x%Lx\n" r2 r3;

  let profiles =
    [ ("heavy",    Amp.default_heavy_profile)
    ; ("balanced", Amp.balanced_profile)
    ; ("light",    Amp.light_profile)
    ; ("adaptive", Amp.adaptive_profile ())
    ]
  in
  let all_ok = ref true in
  List.iter (fun (name, profile) ->
    let rng = Random.State.make [| 0x5877; Hashtbl.hash name; 0xABCD |] in
    let amp  = Amp.amplify_stack_program rng ~profile orig in
    let st   = run_prog amp in
    let ar2  = get_reg st 2 in
    let ar3  = get_reg st 3 in
    let ok   = ar2 = r2 && ar3 = r3 in
    if not ok then all_ok := false;
    Printf.printf "%-10s ctx[2]=0x%Lx ctx[3]=0x%Lx  %s\n"
      name ar2 ar3
      (if ok then "[OK]" else "[FAIL] ← MISMATCH")
  ) profiles;
  if !all_ok
  then print_endline "\n✓ All profiles preserved semantics."
  else (print_endline "\n✗ Semantic violation detected!"; exit 1)

let scenario_expansion () =
  sep ();
  print_endline "SCENARIO 2 — Expansion ratio";
  sep ();
  let orig = make_demo_program () in
  let rng  = Random.State.make [| 0x5877; 42 |] in
  let amp  = Amp.amplify_stack_program rng ~profile:Amp.default_heavy_profile orig in
  print_endline (Amp.amplifier_stats orig amp)

let scenario_determinism () =
  sep ();
  print_endline "SCENARIO 3 — Seed-determinism (same seed ⇒ identical listing)";
  sep ();
  let orig  = make_demo_program () in
  let build () =
    let rng = Random.State.make [| 0x5877; 99; 0xDEAD |] in
    program_to_string (Amp.amplify_stack_program rng ~profile:Amp.default_heavy_profile orig)
  in
  let a = build () in
  let b = build () in
  if a = b
  then print_endline "✓ Deterministic output confirmed."
  else (print_endline "✗ Non-determinism detected!"; exit 1)

let scenario_listing () =
  sep ();
  print_endline "SCENARIO 4 — Heavy profile listing (truncated to 40 ops)";
  sep ();
  let orig = make_demo_program () in
  print_prog "Original" orig;
  let rng = Random.State.make [| 0x5877; 7 |] in
  let amp = Amp.amplify_stack_program rng ~profile:Amp.default_heavy_profile orig in
  let block = Hashtbl.find amp.blocks 0 in
  let ops40 = List.filteri (fun i _ -> i < 40) block.ops in
  let trunc_block = { block with ops = ops40 } in
  let trunc_prog  = { amp with blocks =
    (let t = Hashtbl.create 1 in Hashtbl.replace t 0 trunc_block; t) } in
  print_prog "Amplified (first 40 ops)" trunc_prog;
  Printf.printf "  ... (%d ops total in amplified block)\n"
    (List.length block.ops)

(* ------------------------------------------------------------------ *)
(* Entry point                                                         *)
(* ------------------------------------------------------------------ *)

let () =
  Printf.printf "\nAsgard-5877 Bytecode Amplifier — demo runner\n";
  Printf.printf "ctx[0]=0x%Lx  ctx[1]=0x%Lx\n\n" ctx0 ctx1;
  scenario_correctness ();
  scenario_expansion ();
  scenario_determinism ();
  scenario_listing ();
  sep ();
  print_endline "All scenarios passed."
