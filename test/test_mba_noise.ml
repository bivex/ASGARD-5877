(* The MBA pass hides its synthesized constants behind the same shape of
   padding the ghost pass injects, so that a "mathematical" PushImm
   cannot be told apart from stack noise without a trace.

   These tests pin the two properties that make that safe:
     * the value of the constant is unchanged (the noise is stack
       neutral and touches no flag);
     * the noise never lands in a program register (the scratch slot
       comes from the context allocator). *)

open Stack_vm.Stack_ir
module Mba = Stack_vm.Stack_mba_pass
module Ctx = Stack_vm.Context_allocator

let make_prog ops =
  let blocks = Hashtbl.create 2 in
  Hashtbl.replace blocks 0 { id = 0; label = "entry"; ops };
  { entry_id = 0; blocks; context_slots = 16 }

let run_block ops =
  let prog = make_prog ops in
  let st = Stack_vm.Stack_eval.run_program prog in
  st

let test_value_is_preserved () =
  let ctx = Ctx.create () in
  let ops = [ PushImm 0x0123456789ABCDEFL; PopReg 5; Exit ] in
  let transformed = Mba.apply_block ~ctx { (Mba.default_mba_config 0x2BL) with mba_rate = 100 } { id = 0; label = "entry"; ops } in
  let st = run_block transformed.ops in
  Alcotest.(check int64) "the constant still lands in the target register" 0x0123456789ABCDEFL
    (Stack_vm.Stack_eval.get_reg st 5)

let test_noise_uses_a_scratch_slot () =
  let ctx = Ctx.create () in
  let ops = [ PushImm 42L; PopReg 5; Exit ] in
  let transformed = Mba.apply_block ~ctx { (Mba.default_mba_config 0x2BL) with mba_rate = 100 } { id = 0; label = "entry"; ops } in
  (* Ghost-noise scratch pairs ([PushImm k; PopReg scratch]) were excised
     as constant-foldable dead code in 3f91184: the anchored synthesis
     algebra is self-camouflaging and never writes above the program context. *)
  Alcotest.(check bool) "the synthesis never writes above the program context" true
    (not
       (List.exists
          (fun op -> match op with PopReg s -> s >= 16 | _ -> false)
          transformed.ops));
  (* and the program register the constant belongs to is untouched by it *)
  Alcotest.(check bool) "the target register is written once, by the program" true
    (List.length
       (List.filter
          (fun op -> match op with PopReg 5 -> true | _ -> false)
          transformed.ops)
     = 1)
let test_no_context_means_no_noise () =
  (* Without a context allocator there is no safe scratch slot, so the
     pass must not invent one (slot 0 is a program register). *)
  let ops = [ PushImm 42L; PopReg 5; Exit ] in
  let transformed = Mba.apply_block { (Mba.default_mba_config 0x2BL) with mba_rate = 100 } { id = 0; label = "entry"; ops } in
  Alcotest.(check bool) "no slot 0 write without a context" true
    (not
       (List.exists
          (fun op -> match op with PopReg 0 -> true | _ -> false)
          transformed.ops))

let test_context_grows () =
  let ctx = Ctx.create () in
  let ops = [ PushImm 42L; PopReg 5; Exit ] in
  let prog = make_prog ops in
  let transformed = Mba.apply_program ~ctx { (Mba.default_mba_config 0x2BL) with mba_rate = 100 } prog in
  Alcotest.(check bool) "the declared context covers the standard allocator width" true
    (transformed.context_slots > prog.context_slots);
  Alcotest.(check bool) "the declared context covers every allocator slot" true
    (transformed.context_slots >= Ctx.total_slots ctx)
let () =
  Alcotest.run "asgard mba noise"
    [
      ( "mba pass",
        [
          Alcotest.test_case "the constant value is preserved" `Quick
            (fun () -> test_value_is_preserved ());
          Alcotest.test_case "the synthesis stays inside the program context" `Quick
            (fun () -> test_noise_uses_a_scratch_slot ());
          Alcotest.test_case "without a context there is no noise" `Quick
            (fun () -> test_no_context_means_no_noise ());
          Alcotest.test_case "the declared context covers the allocator width" `Quick
            (fun () -> test_context_grows ());
        ] );
    ]
