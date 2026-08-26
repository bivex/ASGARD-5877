open Random_visa_domain
open Random_visa_sail_export
open Random_visa_sail_parser

let test_parse_manual_sail_snippet () =
  let snippet = {|
default Order dec
$include <prelude.sail>

let VLEN : int = 256
let ELEN : int = 64
let NUM_VREGS : int = 32

type vreg_idx = range(0, 31)
type vreg_t = bits(VLEN)

register v0 : vreg_t
register vl : bits(64)

val execute_vadd_vv_0 : (bits(5), bits(5), bits(5), bits(1)) -> unit
function execute_vadd_vv_0(vd_idx: bits(5), vs2_idx: bits(5), vs1_or_imm: bits(5), vm: bits(1)) = {
  foreach (i from 0 to (vl - 1)) {
    if (vm == 1 | get_vmask_bit(v0, i) == 1) then {
      let op2 = get_velem(vs2, i, 32);
      let op1 = get_velem(vs1, i, 32);
      let res_elem = (op2 + op1);
      set_velem(vd, i, 32, res_elem);
    }
  };
}

val execute_vclz_m_1 : (bits(5), bits(5), bits(5), bits(1)) -> unit
function execute_vclz_m_1(vd_idx: bits(5), vs2_idx: bits(5), vs1_or_imm: bits(5), vm: bits(1)) = {
  foreach (i from 0 to (vl - 1)) {
    if (vm == 1 | get_vmask_bit(v0, i) == 1) then {
      let op2 = get_velem(vs2, i, 32);
      let res_elem = clz(op2);
      set_velem(vd, i, 32, res_elem);
    }
  };
}
|} in
  match Sail_parser_adapter.parse ~spec_name:"TestSailSpec" snippet with
  | Error err -> Alcotest.fail (Errors.to_string err)
  | Ok spec ->
      Alcotest.(check string) "spec name" "TestSailSpec" spec.name;
      Alcotest.(check int) "vlen" 256 spec.config.vlen;
      Alcotest.(check int) "elen" 64 spec.config.elen;
      Alcotest.(check int) "instructions count" 2 (List.length spec.instructions);

      let inst1 = List.nth spec.instructions 0 in
      Alcotest.(check string) "inst1 mnemonic" "vadd_vv_0" inst1.mnemonic;
      Alcotest.(check bool) "inst1 format" true (inst1.format = Types.Instruction_format.OP_VV);
      Alcotest.(check bool) "inst1 add op" true (inst1.binary_op = Some Types.Binary_op.ADD);

      let inst2 = List.nth spec.instructions 1 in
      Alcotest.(check string) "inst2 mnemonic" "vclz_m_1" inst2.mnemonic;
      Alcotest.(check bool) "inst2 format" true (inst2.format = Types.Instruction_format.OP_MVV);
      Alcotest.(check bool) "inst2 clz op" true (inst2.unary_op = Some Types.Unary_op.CLZ)

let test_sail_generation_and_parsing_roundtrip () =
  let rng = Random.State.make [| 4242 |] in
  match Vector_config.make ~vlen:256 () with
  | Error err -> Alcotest.fail (Errors.to_string err)
  | Ok config ->
      match Isa_grammar.generate_isa ~rng ~name:"RoundTrip_ISA" ~config ~num_instructions:16 () with
      | Error err -> Alcotest.fail (Errors.to_string err)
      | Ok spec ->
          Alcotest.(check int) "orig 16 insts" 16 (List.length spec.instructions);
          Alcotest.(check int) "orig vlen 256" 256 spec.config.vlen;

          let tmp_file = Filename.temp_file "roundtrip_" ".sail" in
          (match Sail_export_adapter.write_spec spec ~target_file_path:tmp_file with
          | Error err -> Alcotest.fail (Errors.to_string err)
          | Ok _ -> ());

          (match Sail_parser_adapter.parse_file ~spec_name:"RoundTrip_ISA" tmp_file with
          | Error err ->
              (try Sys.remove tmp_file with _ -> ());
              Alcotest.fail (Errors.to_string err)
          | Ok parsed_spec ->
              (try Sys.remove tmp_file with _ -> ());
              Alcotest.(check string) "name matches" spec.name parsed_spec.name;
              Alcotest.(check int) "vlen matches" spec.config.vlen parsed_spec.config.vlen;
              Alcotest.(check int) "count matches" (List.length spec.instructions) (List.length parsed_spec.instructions);

              List.iter2
                (fun (orig : Vector_instruction.t) (parsed : Vector_instruction.t) ->
                  Alcotest.(check string) "mnemonic match" orig.mnemonic parsed.mnemonic;
                  Alcotest.(check bool) "format match" true (orig.format = parsed.format);
                  Alcotest.(check int) "funct6 match" orig.funct6 parsed.funct6;
                  Alcotest.(check int) "funct3 match" orig.funct3 parsed.funct3;
                  Alcotest.(check bool) "widening match" orig.is_widening parsed.is_widening;
                  if Option.is_some orig.binary_op then
                    Alcotest.(check bool) "binary op match" true (orig.binary_op = parsed.binary_op);
                  if Option.is_some orig.unary_op then
                    Alcotest.(check bool) "unary op match" true (orig.unary_op = parsed.unary_op))
                spec.instructions
                parsed_spec.instructions)

let test_new_classes_roundtrip_through_sail () =
  let rng = Random.State.make [| 13 |] in
  match
    Generation_profile.make
      ~name:"mix"
      ~class_weights:[
        (Instruction_class.Widening, 1.0);
        (Instruction_class.Compare, 1.0);
        (Instruction_class.Saturating, 1.0);
      ]
  with
  | Error err -> Alcotest.fail (Errors.to_string err)
  | Ok mixed_profile ->
      match Isa_grammar.generate_isa ~rng ~name:"RT" ~profile:mixed_profile ~num_instructions:9 () with
      | Error err -> Alcotest.fail (Errors.to_string err)
      | Ok spec ->
          let sail_text = Vector_isa_spec.to_sail_specification spec in
          match Sail_parser_adapter.parse ~spec_name:"RT" sail_text with
          | Error err -> Alcotest.fail (Errors.to_string err)
          | Ok parsed ->
              Alcotest.(check int) "len match" (List.length spec.instructions) (List.length parsed.instructions);
              List.iter2
                (fun (orig : Vector_instruction.t) (got : Vector_instruction.t) ->
                  Alcotest.(check string) "mnemonic" orig.mnemonic got.mnemonic;
                  Alcotest.(check bool) "format" true (orig.format = got.format);
                  Alcotest.(check int) "funct6" orig.funct6 got.funct6;
                  Alcotest.(check int) "funct3" orig.funct3 got.funct3;
                  Alcotest.(check bool) "widening" orig.is_widening got.is_widening;
                  Alcotest.(check bool) "binary op" true (orig.binary_op = got.binary_op))
                spec.instructions
                parsed.instructions

let test_sail_roundtrip_is_fixed_point () =
  let rng = Random.State.make [| 33 |] in
  match Isa_grammar.generate_isa ~rng ~name:"FP" ~num_instructions:12 () with
  | Error err -> Alcotest.fail (Errors.to_string err)
  | Ok spec ->
      let text1 = Vector_isa_spec.to_sail_specification spec in
      match Sail_parser_adapter.parse ~spec_name:"FP" text1 with
      | Error err -> Alcotest.fail (Errors.to_string err)
      | Ok first ->
          let text2 = Vector_isa_spec.to_sail_specification first in
          match Sail_parser_adapter.parse ~spec_name:"FP" text2 with
          | Error err -> Alcotest.fail (Errors.to_string err)
          | Ok second ->
              List.iter2
                (fun (f : Vector_instruction.t) (s : Vector_instruction.t) ->
                  Alcotest.(check string) "fp mnemonic" f.mnemonic s.mnemonic;
                  Alcotest.(check bool) "fp format" true (f.format = s.format);
                  Alcotest.(check int) "fp funct6" f.funct6 s.funct6;
                  Alcotest.(check int) "fp funct3" f.funct3 s.funct3;
                  Alcotest.(check bool) "fp widening" f.is_widening s.is_widening;
                  Alcotest.(check bool) "fp bin op" true (f.binary_op = s.binary_op))
                first.instructions
                second.instructions

let tests = [
  Alcotest.test_case "parse_manual_sail_snippet" `Quick test_parse_manual_sail_snippet;
  Alcotest.test_case "sail_generation_and_parsing_roundtrip" `Quick test_sail_generation_and_parsing_roundtrip;
  Alcotest.test_case "new_classes_roundtrip_through_sail" `Quick test_new_classes_roundtrip_through_sail;
  Alcotest.test_case "sail_roundtrip_is_fixed_point" `Quick test_sail_roundtrip_is_fixed_point;
]
