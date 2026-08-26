open Random_visa_domain
open Random_visa_sail_parser

(** Property 1: For any random seed, synthesized ISA has strictly zero encoding collisions. *)
let prop_no_encoding_collisions =
  QCheck.Test.make
    ~name:"generation_has_no_encoding_collisions"
    ~count:1000
    QCheck.int
    (fun seed ->
      let rng = Random.State.make [| seed |] in
      match Isa_grammar.generate_isa ~rng ~num_instructions:16 () with
      | Error _ -> false
      | Ok spec ->
          let encodings =
            List.map
              (fun (i : Vector_instruction.t) -> (i.funct6, i.funct3, i.opcode))
              spec.instructions
          in
          let unique = List.sort_uniq Stdlib.compare encodings in
          List.length encodings = List.length unique && List.length encodings = 16)

(** Property 2: For any random seed, synthesize |> export_sail |> parse is exact identity on all encoding and semantic fields. *)
let prop_sail_roundtrip_identity =
  QCheck.Test.make
    ~name:"synthesize_export_parse_roundtrip_1000_seeds"
    ~count:1000
    QCheck.int
    (fun seed ->
      let rng = Random.State.make [| seed |] in
      let num_insts = 10 + (abs seed mod 15) in (* between 10 and 24 *)
      match Isa_grammar.generate_isa ~rng ~name:"PropSpec" ~num_instructions:num_insts () with
      | Error _ -> false
      | Ok orig_spec ->
          let sail_text = Vector_isa_spec.to_sail_specification orig_spec in
          match Sail_parser_adapter.parse ~spec_name:"PropSpec" sail_text with
          | Error _ -> false
          | Ok parsed_spec ->
              let count_ok = List.length orig_spec.instructions = List.length parsed_spec.instructions in
              let instructions_ok =
                List.for_all2
                  (fun (orig : Vector_instruction.t) (parsed : Vector_instruction.t) ->
                    orig.mnemonic = parsed.mnemonic
                    && orig.format = parsed.format
                    && orig.funct6 = parsed.funct6
                    && orig.funct3 = parsed.funct3
                    && orig.is_widening = parsed.is_widening
                    && orig.binary_op = parsed.binary_op
                    && orig.unary_op = parsed.unary_op)
                  orig_spec.instructions
                  parsed_spec.instructions
              in
              count_ok && instructions_ok)

(** Property 3: For any random seed, every funct6 is strictly dedicated to a single family,
    and all funct3 values within that funct6 are strictly unique. *)
let prop_per_funct6_single_family_and_unique_funct3 =
  QCheck.Test.make
    ~name:"per_funct6_single_family_and_unique_funct3"
    ~count:1000
    QCheck.int
    (fun seed ->
      let rng = Random.State.make [| seed |] in
      match Isa_grammar.generate_isa ~rng ~num_instructions:20 () with
      | Error _ -> false
      | Ok spec ->
          let by_f6 = Hashtbl.create 16 in
          List.iter
            (fun (inst : Vector_instruction.t) ->
              let prev = try Hashtbl.find by_f6 inst.funct6 with Not_found -> [] in
              Hashtbl.replace by_f6 inst.funct6 (inst :: prev))
            spec.instructions;
          Hashtbl.fold
            (fun _f6 insts acc ->
              if not acc then false
              else
                let f3s = List.map (fun (i : Vector_instruction.t) -> i.funct3) insts in
                let uniq_f3s = List.sort_uniq Stdlib.compare f3s in
                let f3_ok = List.length f3s = List.length uniq_f3s in
                let base_names =
                  List.map
                    (fun (i : Vector_instruction.t) ->
                      match String.split_on_char '_' i.mnemonic with
                      | [] -> i.mnemonic
                      | base :: _ -> base)
                    insts
                in
                let uniq_bases = List.sort_uniq Stdlib.compare base_names in
                let single_base_ok = List.length uniq_bases = 1 in
                f3_ok && single_base_ok)
            by_f6
            true)

let qcheck_tests = [
  prop_no_encoding_collisions;
  prop_sail_roundtrip_identity;
  prop_per_funct6_single_family_and_unique_funct3;
]

let tests = List.map QCheck_alcotest.to_alcotest qcheck_tests
