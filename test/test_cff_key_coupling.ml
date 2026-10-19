(* The VPC-coupled key edges.

   The CFF dispatcher writes the token of the target block into the VPC
   before jumping to it, so on entry to that block the VPC provably holds
   the token.  Coupling the rolling key to that value makes the key
   depend on the path the program took: a block harvested in isolation
   carries no key of its own any more, because the coupling that unlocks
   the next block is missing.

   These tests pin the three properties the coupling relies on:
     * the coupling is the first operation of the block, so a later
       splitting pass cannot separate it from the state it needs;
     * the coupled value is the block's own token (statically known, so
       the encryptor can reproduce the key schedule);
     * the encryptor accepts the resulting program. *)

open Stack_vm.Stack_ir
module Cff = Stack_vm.Stack_cff_pass
module Ctx = Stack_vm.Context_allocator

let make_prog () =
  let blocks = Hashtbl.create 3 in
  Hashtbl.replace blocks 0
    { id = 0; label = "entry"; ops = [ PushImm 1L; JmpRel 1 ] };
  Hashtbl.replace blocks 1
    { id = 1; label = "a"; ops = [ PushImm 2L; PopReg 0; Exit ] };
  Hashtbl.replace blocks 2
    { id = 2; label = "b"; ops = [ PushImm 3L; PopReg 1; JmpRel 1 ] };
  { entry_id = 0; blocks; context_slots = 16 }

let test_coupling_is_first () =
  let ctx = Ctx.create () in
  let prog, info = Cff.apply_program_with_info (Cff.default_cff_config 0x2CL) ctx (make_prog ()) in
  (* the entry block is not reached through the dispatcher: no coupling *)
  let entry = Hashtbl.find prog.blocks 0 in
  Alcotest.(check bool) "the entry block has no coupling" true
    (not (List.exists (fun op -> match op with KeyFeedback _ -> true | _ -> false) entry.ops));
  (* every other real block starts with the coupling *)
  List.iter
    (fun id ->
      let b = Hashtbl.find prog.blocks id in
      Alcotest.(check bool)
        (Printf.sprintf "block %d starts with the key coupling" id) true
        (match b.ops with
        | KeyFeedback (slot, value) :: _ ->
            slot = info.vpc_slot
            && (match Hashtbl.find_opt info.block_tokens id with
                | Some t -> t = value
                | None -> false)
        | _ -> false))
    [ 1; 2 ]

let test_coupling_can_be_disabled () =
  let ctx = Ctx.create () in
  let cfg = { (Cff.default_cff_config 0x2CL) with couple_key = false } in
  let prog, _ = Cff.apply_program_with_info cfg ctx (make_prog ()) in
  let couplings =
    Hashtbl.fold
      (fun _ b acc ->
        acc + List.length (List.filter (fun op -> match op with KeyFeedback _ -> true | _ -> false) b.ops))
      prog.blocks 0
  in
  Alcotest.(check int) "no coupling when it is switched off" 0 couplings

let test_encoder_accepts_the_program () =
  let ctx = Ctx.create () in
  (* the encryptor has to be told the dispatcher state, otherwise it
     cannot prove the coupled value and refuses the program *)
  let prog, info = Cff.apply_program_with_info (Cff.default_cff_config 0x2CL) ctx (make_prog ()) in
  let tokens = Hashtbl.create 8 in
  Hashtbl.iter
    (fun id token -> Hashtbl.replace tokens id (info.vpc_slot, token))
    info.block_tokens;
  let enc =
    Stack_vm.Stack_encoder.encode_program ~seed_key:0x1234L ~dispatcher_tokens:tokens prog
  in
  Alcotest.(check bool) "the encryptor accepts the coupled program" true
    (Bytes.length enc.bytes > 0)

let () =
  Alcotest.run "asgard cff key coupling"
    [
      ( "vpc coupling",
        [
          Alcotest.test_case "the coupling is the first operation" `Quick
            (fun () -> test_coupling_is_first ());
          Alcotest.test_case "the coupling can be switched off" `Quick
            (fun () -> test_coupling_can_be_disabled ());
          Alcotest.test_case "the encryptor accepts the program" `Quick
            (fun () -> test_encoder_accepts_the_program ());
        ] );
    ]
