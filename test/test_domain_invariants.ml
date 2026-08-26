open Random_visa_domain

let test_sew_values_and_properties () =
  Alcotest.(check int) "E8 bits" 8 (Types.Sew.to_bits Types.Sew.E8);
  Alcotest.(check int) "E8 byte width" 1 (Types.Sew.byte_width Types.Sew.E8);
  Alcotest.(check string) "E8 c_type" "int8_t" (Types.Sew.c_type Types.Sew.E8);
  Alcotest.(check string) "E8 c_utype" "uint8_t" (Types.Sew.c_utype Types.Sew.E8);

  Alcotest.(check int) "E16 bits" 16 (Types.Sew.to_bits Types.Sew.E16);
  Alcotest.(check int) "E16 byte width" 2 (Types.Sew.byte_width Types.Sew.E16);
  Alcotest.(check string) "E16 c_type" "int16_t" (Types.Sew.c_type Types.Sew.E16);

  Alcotest.(check int) "E32 bits" 32 (Types.Sew.to_bits Types.Sew.E32);
  Alcotest.(check int) "E32 byte width" 4 (Types.Sew.byte_width Types.Sew.E32);
  Alcotest.(check string) "E32 c_type" "int32_t" (Types.Sew.c_type Types.Sew.E32);

  Alcotest.(check int) "E64 bits" 64 (Types.Sew.to_bits Types.Sew.E64);
  Alcotest.(check int) "E64 byte width" 8 (Types.Sew.byte_width Types.Sew.E64);
  Alcotest.(check string) "E64 c_type" "int64_t" (Types.Sew.c_type Types.Sew.E64)

let test_all_binary_and_unary_ops_present () =
  Alcotest.(check int) "binary ops count" 19 (List.length Types.Binary_op.all);
  Alcotest.(check int) "unary ops count" 6 (List.length Types.Unary_op.all);

  let expected_binary = [
    "ADD"; "SUB"; "MUL"; "DIV"; "REM";
    "AND"; "OR"; "XOR"; "SLL"; "SRL";
    "SRA"; "MIN"; "MAX"; "SADD"; "SSUB";
    "CMPEQ"; "CMPNE"; "CMPLT"; "CMPGE";
  ] in
  List.iter
    (fun name ->
      Alcotest.(check bool)
        (Printf.sprintf "binary op %s present" name)
        true
        (Option.is_some (Types.Binary_op.of_name name)))
    expected_binary;

  let expected_unary = [ "NEG"; "NOT"; "ABS"; "CLZ"; "CTZ"; "CPOP" ] in
  List.iter
    (fun name ->
      Alcotest.(check bool)
        (Printf.sprintf "unary op %s present" name)
        true
        (Option.is_some (Types.Unary_op.of_name name)))
    expected_unary

let test_vector_config_validation () =
  match Vector_config.make ~vlen:256 ~elen:64 ~num_vregs:32 ~default_sew:Types.Sew.E32 () with
  | Error err -> Alcotest.fail (Errors.to_string err)
  | Ok cfg ->
      Alcotest.(check int) "vlen_bytes" 32 (Vector_config.vlen_bytes cfg);
      Alcotest.(check int) "vlmax E32 M1" 8 (Vector_config.calculate_vlmax cfg Types.Sew.E32 Types.Lmul.M1);

      (* Invalid VLEN=32 with default elen=64 (elen > vlen) *)
      Alcotest.(check bool) "elen > vlen fails" true
        (Result.is_error (Vector_config.make ~vlen:32 ()));

      (* Invalid VLEN not power of 2 *)
      Alcotest.(check bool) "vlen=100 fails" true
        (Result.is_error (Vector_config.make ~vlen:100 ()))

let test_vector_instruction_encoding_and_invariants () =
  let inst =
    Vector_instruction.make
      ~mnemonic:"vadd_vv_0"
      ~format:Types.Instruction_format.OP_VV
      ~funct6:0b000001
      ~funct3:0b000
      ~opcode:0x57
      ~binary_op:Types.Binary_op.ADD
      ~description:"Vector Add"
      ()
  in
  let word = Vector_instruction.encode ~vd:3 ~vs2:2 ~vs1_or_rs1_or_imm:1 ~vm:1 inst in
  let opcode = Int32.to_int (Int32.logand word 0x7Fl) in
  let vd = Int32.to_int (Int32.logand (Int32.shift_right_logical word 7) 0x1Fl) in
  let funct3 = Int32.to_int (Int32.logand (Int32.shift_right_logical word 12) 0x7l) in
  let vs1 = Int32.to_int (Int32.logand (Int32.shift_right_logical word 15) 0x1Fl) in
  let vs2 = Int32.to_int (Int32.logand (Int32.shift_right_logical word 20) 0x1Fl) in
  let vm = Int32.to_int (Int32.logand (Int32.shift_right_logical word 25) 0x1l) in
  let funct6 = Int32.to_int (Int32.logand (Int32.shift_right_logical word 26) 0x3Fl) in

  Alcotest.(check int) "opcode" 0x57 opcode;
  Alcotest.(check int) "vd" 3 vd;
  Alcotest.(check int) "funct3" 0 funct3;
  Alcotest.(check int) "vs1" 1 vs1;
  Alcotest.(check int) "vs2" 2 vs2;
  Alcotest.(check int) "vm" 1 vm;
  Alcotest.(check int) "funct6" 1 funct6

let test_vector_isa_spec_collision_and_lookup () =
  let spec = Vector_isa_spec.make ~name:"TestSpec" () in
  let inst1 =
    Vector_instruction.make
      ~mnemonic:"vcustom_0"
      ~format:Types.Instruction_format.OP_VV
      ~funct6:1
      ~funct3:0
      ~opcode:0x57
      ~binary_op:Types.Binary_op.ADD
      ~description:"Custom Add"
      ()
  in
  match Vector_isa_spec.add_instruction spec inst1 with
  | Error err -> Alcotest.fail (Errors.to_string err)
  | Ok spec1 ->
      Alcotest.(check int) "one instruction" 1 (List.length spec1.instructions);
      Alcotest.(check bool) "lookup existing" true (Option.is_some (Vector_isa_spec.get_by_mnemonic spec1 "vcustom_0"));
      Alcotest.(check bool) "lookup non-existent" true (Option.is_none (Vector_isa_spec.get_by_mnemonic spec1 "non_existent"));

      (* Duplicate mnemonic collision *)
      let inst_dup_mnemonic =
        Vector_instruction.make
          ~mnemonic:"vcustom_0"
          ~format:Types.Instruction_format.OP_VV
          ~funct6:2
          ~funct3:0
          ~opcode:0x57
          ~binary_op:Types.Binary_op.SUB
          ()
      in
      Alcotest.(check bool) "duplicate mnemonic rejected" true
        (Result.is_error (Vector_isa_spec.add_instruction spec1 inst_dup_mnemonic));

      (* Duplicate encoding collision *)
      let inst_dup_encoding =
        Vector_instruction.make
          ~mnemonic:"vcustom_1"
          ~format:Types.Instruction_format.OP_VV
          ~funct6:1
          ~funct3:0
          ~opcode:0x57
          ~binary_op:Types.Binary_op.SUB
          ()
      in
      Alcotest.(check bool) "encoding collision rejected" true
        (Result.is_error (Vector_isa_spec.add_instruction spec1 inst_dup_encoding))

let test_spec_decode () =
  let spec = Vector_isa_spec.make ~name:"TestDecodeSpec" () in
  let inst =
    Vector_instruction.make
      ~mnemonic:"vmul_vv"
      ~format:Types.Instruction_format.OP_VV
      ~funct6:15
      ~funct3:0
      ~opcode:0x57
      ~binary_op:Types.Binary_op.MUL
      ()
  in
  match Vector_isa_spec.add_instruction spec inst with
  | Error err -> Alcotest.fail (Errors.to_string err)
  | Ok spec' ->
      let encoded = Vector_instruction.encode ~vd:5 ~vs2:6 ~vs1_or_rs1_or_imm:7 ~vm:1 inst in
      match Vector_isa_spec.decode spec' encoded with
      | None -> Alcotest.fail "Failed to decode instruction"
      | Some decoded ->
          Alcotest.(check string) "decoded mnemonic" "vmul_vv" decoded.mnemonic;
          Alcotest.(check int) "decoded funct6" 15 decoded.funct6

let test_sail_synthesis_operands () =
  let inst_vx =
    Vector_instruction.make
      ~mnemonic:"vadd_vx_test"
      ~format:Types.Instruction_format.OP_VX
      ~funct6:1
      ~funct3:4
      ~binary_op:Types.Binary_op.ADD
      ()
  in
  let sail_code_vx = Sail_ast.function_to_sail inst_vx.sail_function in
  Alcotest.(check bool) "rX in vx sail" true (String.contains sail_code_vx 'r' && String.contains sail_code_vx 'X');

  let inst_vi =
    Vector_instruction.make
      ~mnemonic:"vadd_vi_test"
      ~format:Types.Instruction_format.OP_VI
      ~funct6:2
      ~funct3:3
      ~binary_op:Types.Binary_op.ADD
      ()
  in
  let sail_code_vi = Sail_ast.function_to_sail inst_vi.sail_function in
  Alcotest.(check bool) "sign_extend in vi sail" true (String.contains sail_code_vi 's' && String.contains sail_code_vi 'e')

let tests = [
  Alcotest.test_case "sew_values_and_properties" `Quick test_sew_values_and_properties;
  Alcotest.test_case "all_binary_and_unary_ops_present" `Quick test_all_binary_and_unary_ops_present;
  Alcotest.test_case "vector_config_validation" `Quick test_vector_config_validation;
  Alcotest.test_case "vector_instruction_encoding_and_invariants" `Quick test_vector_instruction_encoding_and_invariants;
  Alcotest.test_case "vector_isa_spec_collision_and_lookup" `Quick test_vector_isa_spec_collision_and_lookup;
  Alcotest.test_case "spec_decode" `Quick test_spec_decode;
  Alcotest.test_case "sail_synthesis_operands" `Quick test_sail_synthesis_operands;
]
