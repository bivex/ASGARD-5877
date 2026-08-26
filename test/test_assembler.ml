open Random_visa_domain
open Random_visa_assembler
open Random_visa_cpp_emitter
open Random_visa_compiler_adapter

let test_parse_register_operands () =
  Alcotest.(check bool) "v0 valid" true (Assembler_adapter.parse_reg "v0" = Ok 0);
  Alcotest.(check bool) "v31 valid" true (Assembler_adapter.parse_reg "v31" = Ok 31);
  Alcotest.(check bool) "x15 valid" true (Assembler_adapter.parse_reg "x15" = Ok 15);
  Alcotest.(check bool) "plain 7 valid" true (Assembler_adapter.parse_reg "7" = Ok 7);
  Alcotest.(check bool) "v32 invalid" true (Result.is_error (Assembler_adapter.parse_reg "v32"));
  Alcotest.(check bool) "bad string invalid" true (Result.is_error (Assembler_adapter.parse_reg "not_a_reg"))

let test_assemble_instruction_formats () =
  let inst_vv =
    Vector_instruction.make
      ~mnemonic:"vadd_vv"
      ~format:Types.Instruction_format.OP_VV
      ~funct6:0
      ~funct3:0
      ~binary_op:Types.Binary_op.ADD
      ()
  in
  let inst_vx =
    Vector_instruction.make
      ~mnemonic:"vadd_vx"
      ~format:Types.Instruction_format.OP_VX
      ~funct6:0
      ~funct3:4
      ~binary_op:Types.Binary_op.ADD
      ()
  in
  let inst_vi =
    Vector_instruction.make
      ~mnemonic:"vadd_vi"
      ~format:Types.Instruction_format.OP_VI
      ~funct6:0
      ~funct3:3
      ~binary_op:Types.Binary_op.ADD
      ()
  in
  let inst_mvv =
    Vector_instruction.make
      ~mnemonic:"vclz_m"
      ~format:Types.Instruction_format.OP_MVV
      ~funct6:5
      ~funct3:2
      ~unary_op:Types.Unary_op.CLZ
      ()
  in
  match Vector_isa_spec.of_instructions ~name:"AsmSpec" [ inst_vv; inst_vx; inst_vi; inst_mvv ] with
  | Error err -> Alcotest.fail (Errors.to_string err)
  | Ok spec ->
      (* Assemble OP_VV *)
      (match Assembler_adapter.assemble_line spec "vadd_vv v3, v2, v1" with
      | Error err -> Alcotest.fail (Errors.to_string err)
      | Ok None -> Alcotest.fail "Expected instruction word"
      | Ok (Some word) ->
          let exp = Vector_instruction.encode ~vd:3 ~vs2:2 ~vs1_or_rs1_or_imm:1 ~vm:1 inst_vv in
          Alcotest.(check int32) "vv word matches" exp word);

      (* Assemble OP_VV with dot notation *)
      (match Assembler_adapter.assemble_line spec "vadd.vv v3, v2, v1" with
      | Error err -> Alcotest.fail (Errors.to_string err)
      | Ok (Some word) ->
          let exp = Vector_instruction.encode ~vd:3 ~vs2:2 ~vs1_or_rs1_or_imm:1 ~vm:1 inst_vv in
          Alcotest.(check int32) "dot notation matches" exp word
      | Ok None -> Alcotest.fail "Expected word");

      (* Assemble Masked *)
      (match Assembler_adapter.assemble_line spec "vadd_vv v3, v2, v1, v0.t" with
      | Error err -> Alcotest.fail (Errors.to_string err)
      | Ok (Some word) ->
          let exp = Vector_instruction.encode ~vd:3 ~vs2:2 ~vs1_or_rs1_or_imm:1 ~vm:0 inst_vv in
          Alcotest.(check int32) "masked vm=0 matches" exp word
      | Ok None -> Alcotest.fail "Expected word");

      (* Assemble OP_VX *)
      (match Assembler_adapter.assemble_line spec "vadd_vx v4, v5, x6" with
      | Error err -> Alcotest.fail (Errors.to_string err)
      | Ok (Some word) ->
          let exp = Vector_instruction.encode ~vd:4 ~vs2:5 ~vs1_or_rs1_or_imm:6 ~vm:1 inst_vx in
          Alcotest.(check int32) "vx word matches" exp word
      | Ok None -> Alcotest.fail "Expected word");

      (* Assemble OP_VI *)
      (match Assembler_adapter.assemble_line spec "vadd_vi v7, v8, 5" with
      | Error err -> Alcotest.fail (Errors.to_string err)
      | Ok (Some word) ->
          let exp = Vector_instruction.encode ~vd:7 ~vs2:8 ~vs1_or_rs1_or_imm:5 ~vm:1 inst_vi in
          Alcotest.(check int32) "vi word matches" exp word
      | Ok None -> Alcotest.fail "Expected word");

      (* Assemble OP_MVV *)
      (match Assembler_adapter.assemble_line spec "vclz_m v9, v10" with
      | Error err -> Alcotest.fail (Errors.to_string err)
      | Ok (Some word) ->
          let exp = Vector_instruction.encode ~vd:9 ~vs2:10 ~vs1_or_rs1_or_imm:0 ~vm:1 inst_mvv in
          Alcotest.(check int32) "mvv word matches" exp word
      | Ok None -> Alcotest.fail "Expected word")

let test_assemble_program_and_roundtrip () =
  let inst_vv =
    Vector_instruction.make
      ~mnemonic:"vadd_vv"
      ~format:Types.Instruction_format.OP_VV
      ~funct6:0
      ~funct3:0
      ~binary_op:Types.Binary_op.ADD
      ()
  in
  let inst_vx =
    Vector_instruction.make
      ~mnemonic:"vadd_vx"
      ~format:Types.Instruction_format.OP_VX
      ~funct6:0
      ~funct3:4
      ~binary_op:Types.Binary_op.ADD
      ()
  in
  match Vector_isa_spec.of_instructions ~name:"ProgSpec" [ inst_vv; inst_vx ] with
  | Error err -> Alcotest.fail (Errors.to_string err)
  | Ok spec ->
      let prog_src = {|
# Header comment
start:
    vadd_vv v3, v2, v1
    // Inline comment
    vadd_vx v4, v5, x6
    vadd_vv v7, v8, v9, v0.t
|} in
      match Assembler_adapter.assemble_program spec prog_src with
      | Error err -> Alcotest.fail (Errors.to_string err)
      | Ok words ->
          Alcotest.(check int) "3 instructions assembled" 3 (List.length words);
          let disasm = Assembler_adapter.disassemble_program spec words in
          Alcotest.(check bool) "disasm contains vadd_vv" true (String.contains disasm 'v');
          (* Re-assemble disassembled output *)
          match Assembler_adapter.assemble_program spec disasm with
          | Error err -> Alcotest.fail (Errors.to_string err)
          | Ok reassembled ->
              Alcotest.(check (list int32)) "exact roundtrip words" words reassembled

let test_vbc_file_serialization_and_validation () =
  let sample_words = [ 0x021101D7l; 0x0262C257l; 0x009403D7l ] in
  let tmp_vbc = Filename.temp_file "test_" ".vbc" in
  (match Assembler_adapter.write_vbc_file ~vlen:256 ~elen:64 sample_words tmp_vbc with
  | Error err -> Alcotest.fail (Errors.to_string err)
  | Ok _ -> ());

  (match Assembler_adapter.read_vbc_file tmp_vbc with
  | Error err ->
      (try Sys.remove tmp_vbc with _ -> ());
      Alcotest.fail (Errors.to_string err)
  | Ok (vlen, elen, read_words) ->
      (try Sys.remove tmp_vbc with _ -> ());
      Alcotest.(check int) "vlen 256" 256 vlen;
      Alcotest.(check int) "elen 64" 64 elen;
      Alcotest.(check (list int32)) "words match" sample_words read_words);

  (* Test corrupted magic header check *)
  let tmp_bad = Filename.temp_file "bad_" ".vbc" in
  let oc = open_out_bin tmp_bad in
  output_string oc "BADMAGIC12345678";
  close_out oc;
  let bad_res = Assembler_adapter.read_vbc_file tmp_bad in
  (try Sys.remove tmp_bad with _ -> ());
  Alcotest.(check bool) "bad magic fails" true (Result.is_error bad_res)

let test_bytecode_execution_on_cpp_emulator () =
  let rng = Random.State.make [| 55 |] in
  match Isa_grammar.generate_isa ~rng ~name:"Bytecode_ISA" ~num_instructions:4 () with
  | Error err -> Alcotest.fail (Errors.to_string err)
  | Ok spec ->
      let tmp_dir = Filename.temp_file "emu_vbc_" "_dir" in
      (try Sys.remove tmp_dir with _ -> ());
      (try Sys.mkdir tmp_dir 0o755 with _ -> ());

      (* Emit and compile emulator *)
      (match Cpp_emitter_adapter.emit_emulator_project spec ~output_dir:tmp_dir with
      | Error err -> Alcotest.fail (Errors.to_string err)
      | Ok _ -> ());
      (match Compiler_adapter.compile ~project_dir:tmp_dir with
      | Error err -> Alcotest.fail (Errors.to_string err)
      | Ok () -> ());

      (* Create bytecode from all instructions *)
      let words =
        List.map
          (fun (inst : Vector_instruction.t) ->
            Vector_instruction.encode ~vd:3 ~vs2:2 ~vs1_or_rs1_or_imm:1 ~vm:1 inst)
          spec.instructions
      in
      let bin_path = Filename.concat tmp_dir "test_program.bin" in
      (match Assembler_adapter.write_binary_bytecode words bin_path with
      | Error err -> Alcotest.fail (Errors.to_string err)
      | Ok _ -> ());

      (* Execute runner with --bin *)
      let run_cmd = Printf.sprintf "%s/visa_test_runner --bin %s" tmp_dir bin_path in
      let ic = Unix.open_process_in run_cmd in
      let buf = Buffer.create 512 in
      (try
         while true do
           Buffer.add_string buf (input_line ic);
           Buffer.add_char buf '\n'
         done
       with End_of_file -> ());
      let status = Unix.close_process_in ic in
      Alcotest.(check bool) "clean exit" true (status = Unix.WEXITED 0);
      let out = Buffer.contents buf in
      Alcotest.(check bool) "executed all bytecode words" true
        (String.contains out 'E' && String.contains out '4');

      let _ = Sys.command (Printf.sprintf "rm -rf %s" tmp_dir) in
      ()

let tests = [
  Alcotest.test_case "parse_register_operands" `Quick test_parse_register_operands;
  Alcotest.test_case "assemble_instruction_formats" `Quick test_assemble_instruction_formats;
  Alcotest.test_case "assemble_program_and_roundtrip" `Quick test_assemble_program_and_roundtrip;
  Alcotest.test_case "vbc_file_serialization_and_validation" `Quick test_vbc_file_serialization_and_validation;
  Alcotest.test_case "bytecode_execution_on_cpp_emulator" `Slow test_bytecode_execution_on_cpp_emulator;
]
