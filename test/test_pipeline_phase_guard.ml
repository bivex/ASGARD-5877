(* The pipeline invariant guard.

   A protection pass that breaks an invariant does not crash the build:
   the pipeline emits a protected binary that is unrunnable or whose
   bytecode decrypts into garbage.  The guard in
   lib/stack_vm/stack_phase_guard.ml is called after every phase of the
   packager; these tests pin what it accepts and what it rejects. *)

open Stack_vm.Stack_ir

module Guard = Stack_vm.Stack_phase_guard

let make_prog ?(entry = 0) ?(context_slots = 16) blocks =
  let table = Hashtbl.create 8 in
  List.iter (fun b -> Hashtbl.replace table b.id b) blocks;
  { entry_id = entry; blocks = table; context_slots }

let block id ops = { id; label = Printf.sprintf "b%d" id; ops }

let expect_failure ~name f =
  match f () with
  | () -> Alcotest.fail (Printf.sprintf "%s: the guard accepted a broken program" name)
  | exception Failure msg ->
      Alcotest.(check bool) (name ^ ": rejected with a message") true (String.length msg > 0)

let expect_accepted ~name f =
  match f () with
  | () -> Alcotest.(check bool) (name ^ ": accepted") true true
  | exception Failure msg ->
      Alcotest.fail (Printf.sprintf "%s: rejected unexpectedly: %s" name msg)

(* a well-formed program: balanced blocks, valid targets *)
let good_prog () =
  make_prog ~context_slots:16
    [
      block 0 [ PushImm 1L; PopReg 0; JmpRel 1 ];
      block 1 [ PushImm 2L; PopReg 1; Exit ];
    ]

(* a jump to a block that does not exist: no later phase repairs it *)
let broken_target_prog () =
  make_prog ~context_slots:16
    [
      block 0 [ PushImm 1L; PopReg 0; JmpRel 7 ];
      block 1 [ PushImm 2L; PopReg 1; Exit ];
    ]

(* a register slot outside the declared context *)
let bad_slot_prog () =
  make_prog ~context_slots:4
    [
      block 0 [ PushImm 1L; PopReg 9; Exit ];
    ]

(* a block that leaves a value on the stack: the balance pass repairs
   this at the end of the pipeline, so it is only fatal in the final
   phase *)
let unbalanced_prog () =
  make_prog ~context_slots:16
    [
      block 0 [ PushImm 1L; Exit ];
    ]

let test_guard () =
  expect_accepted ~name:"a well-formed program" (fun () ->
      Guard.check_phase_invariants ~phase:"1-lowered" ~final:false (good_prog ()));
  expect_failure ~name:"a missing jump target" (fun () ->
      Guard.check_phase_invariants ~phase:"1-lowered" ~final:false (broken_target_prog ()));
  expect_failure ~name:"a context slot outside the range" (fun () ->
      Guard.check_phase_invariants ~phase:"1-lowered" ~final:false (bad_slot_prog ()));
  expect_accepted ~name:"an unbalanced block before the balance pass" (fun () ->
      Guard.check_phase_invariants ~phase:"6-feedback" ~final:false (unbalanced_prog ()));
  expect_failure ~name:"an unbalanced block in the final phase" (fun () ->
      Guard.check_phase_invariants ~phase:"7-balance" ~final:true (unbalanced_prog ()))

let () =
  Alcotest.run "asgard pipeline phase guard"
    [
      ( "guard",
        [
          Alcotest.test_case "accepts and rejects as expected" `Quick
            (fun () -> test_guard ());
        ] );
    ]
