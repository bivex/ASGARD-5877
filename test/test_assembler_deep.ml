open Random_visa_domain
open Random_visa_assembler

let sample_spec () =
  let inst1 =
    Vector_instruction.make
      ~mnemonic:"vadd_vv"
      ~format:Types.Instruction_format.OP_VV
      ~funct6:0
      ~funct3:0
      ~binary_op:Types.Binary_op.ADD
      ()
  in
  let inst2 =
    Vector_instruction.make
      ~mnemonic:"vadd_vi"
      ~format:Types.Instruction_format.OP_VI
      ~funct6:0
      ~funct3:3
      ~binary_op:Types.Binary_op.ADD
      ()
  in
  Result.get_ok (Vector_isa_spec.of_instructions ~name:"DeepAsm" [ inst1; inst2 ])

let test_hex_immediates () =
  let spec = sample_spec () in
  match Assembler_adapter.assemble_line spec "vadd_vi v1, v2, 0x0F" with
  | Error err -> Alcotest.fail (Errors.to_string err)
  | Ok None -> Alcotest.fail "Expected word"
  | Ok (Some word) ->
      let imm = Int32.to_int (Int32.logand (Int32.shift_right_logical word 15) 0x1Fl) in
      Alcotest.(check int) "imm parsed as 15" 15 imm

let test_negative_immediates () =
  let spec = sample_spec () in
  match Assembler_adapter.assemble_line spec "vadd_vi v1, v2, -1" with
  | Error err -> Alcotest.fail (Errors.to_string err)
  | Ok (Some word) ->
      let imm = Int32.to_int (Int32.logand (Int32.shift_right_logical word 15) 0x1Fl) in
      Alcotest.(check int) "imm -1 is 0x1F" 31 imm
  | Ok None -> Alcotest.fail "Expected word"

let test_unknown_instruction_error () =
  let spec = sample_spec () in
  match Assembler_adapter.assemble_line spec "vnonexistent v1, v2, v3" with
  | Error (Errors.Assembly_syntax_error msg) ->
      Alcotest.(check bool) "mentions unknown instruction" true (String.contains msg 'U' || String.contains msg 'u')
  | _ -> Alcotest.fail "Expected Assembly_syntax_error"

let test_only_comments_and_labels () =
  let spec = sample_spec () in
  let src = "# Only comment\n\n// Another comment\nmy_label:\n   \n" in
  match Assembler_adapter.assemble_program spec src with
  | Error err -> Alcotest.fail (Errors.to_string err)
  | Ok words ->
      Alcotest.(check int) "zero words" 0 (List.length words)

let test_invalid_register_indices () =
  Alcotest.(check bool) "v32 rejected" true (Result.is_error (Assembler_adapter.parse_reg "v32"));
  Alcotest.(check bool) "v-1 rejected" true (Result.is_error (Assembler_adapter.parse_reg "v-1"));
  Alcotest.(check bool) "x99 rejected" true (Result.is_error (Assembler_adapter.parse_reg "x99"))

let tests = [
  Alcotest.test_case "hex_immediates" `Quick test_hex_immediates;
  Alcotest.test_case "negative_immediates" `Quick test_negative_immediates;
  Alcotest.test_case "unknown_instruction_error" `Quick test_unknown_instruction_error;
  Alcotest.test_case "only_comments_and_labels" `Quick test_only_comments_and_labels;
  Alcotest.test_case "invalid_register_indices" `Quick test_invalid_register_indices;
]
