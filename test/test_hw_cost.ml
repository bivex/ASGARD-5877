open Random_visa_domain

let spec_with ?(vlen = 128) ?(elen = 64) ?(sew = Types.Sew.E32) ?(lmul = Types.Lmul.M1) insts =
  match Vector_config.make ~vlen ~elen ~default_sew:sew ~default_lmul:lmul () with
  | Error err -> failwith (Errors.to_string err)
  | Ok config ->
      match Vector_isa_spec.of_instructions ~name:"CostTest" ~config insts with
      | Error err -> failwith (Errors.to_string err)
      | Ok s -> s

let test_read_ports_reflect_two_source_instructions () =
  let inst =
    Vector_instruction.make
      ~mnemonic:"vadd_vv"
      ~format:Types.Instruction_format.OP_VV
      ~funct6:0
      ~funct3:0
      ~binary_op:Types.Binary_op.ADD
      ()
  in
  let spec = spec_with [ inst ] in
  let report = Hw_cost.evaluate spec in
  Alcotest.(check int) "read ports" 3 report.regfile_read_ports;
  Alcotest.(check int) "write ports" 1 report.regfile_write_ports;
  Alcotest.(check string) "verdict ok" "ok" (Hw_cost.verdict_to_string report.verdict);
  Alcotest.(check (list string)) "no warnings" [] report.warnings

let test_read_ports_scalar_source_needs_two_ports () =
  let inst =
    Vector_instruction.make
      ~mnemonic:"vadd_vx"
      ~format:Types.Instruction_format.OP_VX
      ~funct6:0
      ~funct3:4
      ~binary_op:Types.Binary_op.ADD
      ()
  in
  let spec = spec_with [ inst ] in
  let report = Hw_cost.evaluate spec in
  Alcotest.(check int) "scalar read ports" 2 report.regfile_read_ports

let test_decoder_footprint_counts_entries_and_funct6 () =
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
      ~mnemonic:"vadd_vx"
      ~format:Types.Instruction_format.OP_VX
      ~funct6:0
      ~funct3:4
      ~binary_op:Types.Binary_op.ADD
      ()
  in
  let inst3 =
    Vector_instruction.make
      ~mnemonic:"vsub_vv"
      ~format:Types.Instruction_format.OP_VV
      ~funct6:1
      ~funct3:0
      ~binary_op:Types.Binary_op.SUB
      ()
  in
  let spec = spec_with [ inst1; inst2; inst3 ] in
  let report = Hw_cost.evaluate spec in
  Alcotest.(check int) "decoder entries" 3 report.decoder_entries;
  Alcotest.(check int) "distinct funct6" 2 report.distinct_funct6

let test_widening_destination_width_reported () =
  let inst =
    Vector_instruction.make
      ~mnemonic:"vwadd_vv"
      ~format:Types.Instruction_format.OP_WIDENING
      ~funct6:0
      ~funct3:0
      ~binary_op:Types.Binary_op.ADD
      ~is_widening:true
      ()
  in
  let spec = spec_with [ inst ] in
  let report = Hw_cost.evaluate spec in
  Alcotest.(check int) "widening dst bits" 64 report.widening_dst_bits;
  Alcotest.(check bool) "widening dst <= elen" true (report.widening_dst_bits <= report.elen_bits);
  Alcotest.(check string) "verdict ok" "ok" (Hw_cost.verdict_to_string report.verdict)

let test_widening_beyond_elen_warns () =
  let inst =
    Vector_instruction.make
      ~mnemonic:"vwadd_vv"
      ~format:Types.Instruction_format.OP_WIDENING
      ~funct6:0
      ~funct3:0
      ~binary_op:Types.Binary_op.ADD
      ~is_widening:true
      ()
  in
  let spec = spec_with ~elen:32 [ inst ] in
  let report = Hw_cost.evaluate spec in
  Alcotest.(check string) "verdict warn" "warn" (Hw_cost.verdict_to_string report.verdict);
  Alcotest.(check bool) "has ELEN warning" true
    (List.exists (fun w -> String.contains w 'E' && String.contains w 'L') report.warnings)

let test_group_larger_than_vlen_warns () =
  let spec = spec_with ~vlen:128 ~sew:Types.Sew.E64 ~lmul:Types.Lmul.M4 [] in
  let report = Hw_cost.evaluate spec in
  Alcotest.(check string) "verdict warn" "warn" (Hw_cost.verdict_to_string report.verdict);
  Alcotest.(check bool) "has VLEN warning" true
    (List.exists (fun w -> String.contains w 'V' && String.contains w 'L') report.warnings);
  Alcotest.(check int) "max group bytes" 32 report.max_group_bytes

let tests = [
  Alcotest.test_case "read_ports_reflect_two_source_instructions" `Quick test_read_ports_reflect_two_source_instructions;
  Alcotest.test_case "read_ports_scalar_source_needs_two_ports" `Quick test_read_ports_scalar_source_needs_two_ports;
  Alcotest.test_case "decoder_footprint_counts_entries_and_funct6" `Quick test_decoder_footprint_counts_entries_and_funct6;
  Alcotest.test_case "widening_destination_width_reported" `Quick test_widening_destination_width_reported;
  Alcotest.test_case "widening_beyond_elen_warns" `Quick test_widening_beyond_elen_warns;
  Alcotest.test_case "group_larger_than_vlen_warns" `Quick test_group_larger_than_vlen_warns;
]
