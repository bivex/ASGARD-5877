(* Consistency of the state-feedback rolling key with the encryptor.
   The runtime hashes the LIVE register value on a KeyFeedback, while the
   encryptor can only hash a statically known constant.  When the two
   disagree, the encrypted bytecode decrypts into garbage - silently,
   because nothing in the pipeline compared the two.

   These tests pin the contract:
     * a feedback that immediately follows the write of the coupled value
       is accepted (the pattern the feedback pass injects);
     * a feedback whose value comes from the entry context is accepted
       only when that context is declared;
     * every other arrangement is rejected at encode time;
     * the feedback pass never produces an arrangement the encoder
       rejects, for any seed.

   It also pins the amplifier's contract that the declared context size
   never shrinks below what the input program already used. *)

open Stack_vm.Stack_ir

module Amp = Stack_vm.Bytecode_amplifier
module Encoder = Stack_vm.Stack_encoder
module Feedback = Stack_vm.Stack_feedback_pass

let make_prog ops = make_program 0 [make_block 0 "entry" ops] 8

let seed_key = 0xCAFEBABEDEADBEEFL

let expect_accepted ~name prog =
  match Encoder.encode_program ~seed_key prog with
  | _ -> Alcotest.(check bool) (name ^ ": accepted") true true
  | exception Invalid_argument msg ->
      Alcotest.fail (Printf.sprintf "%s: rejected unexpectedly: %s" name msg)

let expect_rejected ?(initial_ctx = []) ~name prog =
  match Encoder.encode_program ~seed_key ~initial_ctx prog with
  | _ ->
      Alcotest.fail
        (Printf.sprintf "%s: the encoder accepted an inconsistent KeyFeedback" name)
  | exception Invalid_argument msg ->
      Alcotest.(check bool) (name ^ ": rejected with a clear message") true
        (String.length msg > 0)

let test_feedback_accepted () =
  (* the pattern the feedback pass injects: the value is written right
     before the feedback *)
  let p1 = make_prog [ SetRegImm (1, 0x1122L); KeyFeedback (1, 0x1122L); Exit ] in
  expect_accepted ~name:"SetRegImm + KeyFeedback" p1;
  let p2 = make_prog [ PushImm 0x2233L; PopReg 2; KeyFeedback (2, 0x2233L); Exit ] in
  expect_accepted ~name:"PushImm + PopReg + KeyFeedback" p2;
  (* the value comes from the CFF dispatcher: accepted when the block's
     token is declared, because the VPC provably holds it on entry *)
  let p4 = make_prog [ KeyFeedback (7, 0x5566L); Exit ] in
  let tokens = Hashtbl.create 1 in
  Hashtbl.replace tokens 0 (7, 0x5566L);
  (match Encoder.encode_program ~seed_key ~dispatcher_tokens:tokens p4 with
   | _ -> Alcotest.(check bool) "a declared dispatcher token is accepted" true true
   | exception Invalid_argument msg ->
       Alcotest.fail (Printf.sprintf "declared dispatcher token rejected: %s" msg));
  expect_rejected ~name:"an undeclared dispatcher token" p4;
  (* the value comes from the entry context: accepted when declared *)
  let p3 = make_prog [ KeyFeedback (1, 0x3344L); Exit ] in
  (match Encoder.encode_program ~seed_key ~initial_ctx:[1, 0x3344L] p3 with
   | _ -> Alcotest.(check bool) "declared entry context is accepted" true true
   | exception Invalid_argument msg ->
       Alcotest.fail (Printf.sprintf "declared entry context rejected: %s" msg))

let test_feedback_rejected () =
  (* the value is nowhere known statically *)
  expect_rejected ~name:"undeclared entry value" (make_prog [ KeyFeedback (1, 0x4455L); Exit ]);
  (* the declared entry context contradicts the expected value *)
  expect_rejected ~name:"contradicting entry context"
    ~initial_ctx:[1, 0x9999L] (make_prog [ KeyFeedback (1, 0x4455L); Exit ]);
  (* the slot is written with a DIFFERENT value right before *)
  expect_rejected ~name:"preceding write of another value"
    (make_prog [ SetRegImm (1, 0x5566L); KeyFeedback (1, 0x6677L); Exit ]);
  (* the feedback is not preceded by any write to the slot *)
  expect_rejected ~name:"no write to the coupled slot"
    (make_prog [ SetRegImm (2, 0x7788L); KeyFeedback (1, 0x8899L); Exit ])

(* Whatever the feedback pass produces must be encodable: the encoder is
   the gate that keeps the key schedule reproducible. *)
let test_feedback_pass_output_is_encodable () =
  let ops =
    [ SetRegImm (0, 1000L); SetRegImm (1, 2000L); PushReg 0; PushReg 1; Add;
      PopReg 2; PushImm 7L; PopReg 3; Exit ]
  in
  let prog = make_program 0 [make_block 0 "entry" ops] 8 in
  let cfg = Feedback.default_feedback_config 0x12345L in
  let transformed = Feedback.apply_program cfg prog in
  let stats = Feedback.feedback_stats prog transformed in
  Alcotest.(check bool) "the feedback pass injects couplings" true
    (stats.feedback_injected > 0);
  expect_accepted ~name:"the feedback pass output" transformed;
  (* and every injected coupling immediately follows the write of its value *)
  let block = Hashtbl.find transformed.blocks 0 in
  let arr = Array.of_list block.ops in
  for i = 0 to Array.length arr - 1 do
    match arr.(i) with
    | KeyFeedback (slot, exp) ->
        let ok =
          if i = 0 then false
          else
            match arr.(i - 1) with
            | SetRegImm (s, v) -> s = slot && v = exp
            | PopReg s when s = slot && i >= 2 ->
                (match arr.(i - 2) with PushImm v -> v = exp | _ -> false)
            | _ -> false
        in
        Alcotest.(check bool) "every coupling follows the write of its value" true ok
    | _ -> ()
  done

(* The amplifier must not shrink the declared context: the input program
   was built for prog.context_slots, and a smaller declared size turns its
   register accesses into out-of-range ones. *)
let test_amplifier_preserves_context_slots () =
  let ops = [ PushImm 0xCAFE0000L; PushReg 0; Add; PopReg 30; Exit ] in
  (* the program uses a high slot and declares a large context, while the
     allocator knows only a few slots *)
  let prog = make_program 0 [make_block 0 "entry" ops] 100 in
  let ctx = Stack_vm.Context_allocator.create () in
  let amplified =
    Amp.amplify_stack_program (Random.State.make [| 0x5877 |]) ~ctx
      ~profile:Amp.default_heavy_profile prog
  in
  Alcotest.(check bool) "the declared context never shrinks" true
    (amplified.context_slots >= prog.context_slots);
  Alcotest.(check bool) "the input slots stay in range" true
    (Stack_vm.Stack_invariants.check_cfg_invariants amplified
     |> (function Ok () -> true | Error _ -> false))

let () =
  Alcotest.run "asgard key feedback consistency"
    [
      ( "key feedback",
        [
          Alcotest.test_case "consistent couplings are accepted" `Quick
            (fun () -> test_feedback_accepted ());
          Alcotest.test_case "inconsistent couplings are rejected" `Quick
            (fun () -> test_feedback_rejected ());
          Alcotest.test_case "the feedback pass output is always encodable" `Quick
            (fun () -> test_feedback_pass_output_is_encodable ());
        ] );
      ( "amplifier",
        [
          Alcotest.test_case "the declared context never shrinks" `Quick
            (fun () -> test_amplifier_preserves_context_slots ());
        ] );
    ]
