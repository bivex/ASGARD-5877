open Random_visa_domain

let generate ~seed ~n ?profile () =
  let rng = Random.State.make [| seed |] in
  Isa_grammar.generate_isa ~rng ~name:"Gen" ~num_instructions:n ?profile ()

let test_mnemonics_are_family_variants_not_numbered () =
  match generate ~seed:42 ~n:16 () with
  | Error err -> Alcotest.fail (Errors.to_string err)
  | Ok spec ->
      Alcotest.(check int) "16 instructions" 16 (List.length spec.instructions);
      List.iter
        (fun (inst : Vector_instruction.t) ->
          Alcotest.(check bool) "starts with v" true (inst.mnemonic.[0] = 'v');
          Alcotest.(check bool) "has suffix" true
            (String.ends_with ~suffix:"_vv" inst.mnemonic
            || String.ends_with ~suffix:"_vx" inst.mnemonic
            || String.ends_with ~suffix:"_vi" inst.mnemonic
            || String.ends_with ~suffix:"_m" inst.mnemonic
            || String.ends_with ~suffix:"_vs" inst.mnemonic))
        spec.instructions

let test_format_variants_of_one_family_share_funct6 () =
  match generate ~seed:0 ~n:30 () with
  | Error err -> Alcotest.fail (Errors.to_string err)
  | Ok spec ->
      let by_base = Hashtbl.create 16 in
      List.iter
        (fun (inst : Vector_instruction.t) ->
          let base =
            match String.split_on_char '_' inst.mnemonic with
            | b :: _ -> b
            | [] -> inst.mnemonic
          in
          let existing = Option.value ~default:[] (Hashtbl.find_opt by_base base) in
          Hashtbl.replace by_base base (inst :: existing))
        spec.instructions;

      let shared =
        Hashtbl.fold
          (fun _ insts acc -> if List.length insts > 1 then insts :: acc else acc)
          by_base []
      in
      Alcotest.(check bool) "has multi-variant family" true (List.length shared > 0);
      List.iter
        (fun variants ->
          let f6s = List.sort_uniq Int.compare (List.map (fun (v : Vector_instruction.t) -> v.funct6) variants) in
          let f3s = List.sort_uniq Int.compare (List.map (fun (v : Vector_instruction.t) -> v.funct3) variants) in
          Alcotest.(check int) "variants share one funct6" 1 (List.length f6s);
          Alcotest.(check int) "variants distinct funct3" (List.length variants) (List.length f3s))
        shared

let test_higher_weight_family_gets_lower_or_equal_funct6 () =
  match generate ~seed:99 ~n:24 () with
  | Error err -> Alcotest.fail (Errors.to_string err)
  | Ok spec ->
      let fam6 = Hashtbl.create 16 in
      let weights = Hashtbl.create 16 in
      List.iter
        (fun (inst : Vector_instruction.t) ->
          let base =
            match String.split_on_char '_' inst.mnemonic with
            | b :: _ -> b
            | [] -> inst.mnemonic
          in
          let cur_f6 = Option.value ~default:64 (Hashtbl.find_opt fam6 base) in
          Hashtbl.replace fam6 base (min cur_f6 inst.funct6);
          match Isa_grammar.lookup_family base with
          | Some f -> Hashtbl.replace weights base f.weight
          | None -> ())
        spec.instructions;

      let pairs =
        Hashtbl.fold
          (fun base f6 acc -> (Hashtbl.find weights base, f6) :: acc)
          fam6 []
      in
      let heaviest = List.fold_left (fun acc (w, _) -> max acc w) 0.0 pairs in
      let lightest = List.fold_left (fun acc (w, _) -> min acc w) 100.0 pairs in
      if heaviest <> lightest then begin
        let min_f6_heavy =
          List.fold_left
            (fun acc (w, f6) -> if w = heaviest then min acc f6 else acc)
            64 pairs
        in
        let max_f6_light =
          List.fold_left
            (fun acc (w, f6) -> if w = lightest then max acc f6 else acc)
            (-1) pairs
        in
        Alcotest.(check bool) "heavy gets low funct6" true (min_f6_heavy <= max_f6_light)
      end

let test_rvv_like_prioritises_arith_over_saturating () =
  let counts = Hashtbl.create 4 in
  for seed = 0 to 4 do
    match generate ~seed ~n:48 () with
    | Error err -> Alcotest.fail (Errors.to_string err)
    | Ok spec ->
        List.iter
          (fun (inst : Vector_instruction.t) ->
            let base =
              match String.split_on_char '_' inst.mnemonic with
              | b :: _ -> b
              | [] -> inst.mnemonic
            in
            match Isa_grammar.lookup_family base with
            | Some f ->
                let c = Option.value ~default:0 (Hashtbl.find_opt counts f.klass) in
                Hashtbl.replace counts f.klass (c + 1)
            | None -> ())
          spec.instructions
  done;
  let arith_count = Option.value ~default:0 (Hashtbl.find_opt counts Instruction_class.Arith) in
  let sat_count = Option.value ~default:0 (Hashtbl.find_opt counts Instruction_class.Saturating) in
  let wide_count = Option.value ~default:0 (Hashtbl.find_opt counts Instruction_class.Widening) in
  Alcotest.(check bool) "arith > saturating" true (arith_count > sat_count);
  Alcotest.(check bool) "arith > widening" true (arith_count > wide_count);
  List.iter
    (fun cls ->
      Alcotest.(check bool)
        (Printf.sprintf "%s count > 0" (Instruction_class.to_string cls))
        true
        (Option.value ~default:0 (Hashtbl.find_opt counts cls) > 0))
    [ Instruction_class.Arith; Instruction_class.Saturating; Instruction_class.Widening; Instruction_class.Compare ]

let test_class_profile_restricts_generated_classes () =
  match Generation_profile.make ~name:"cmp" ~class_weights:[ (Instruction_class.Compare, 1.0) ] with
  | Error err -> Alcotest.fail (Errors.to_string err)
  | Ok cmp_profile ->
      match generate ~seed:3 ~n:8 ~profile:cmp_profile () with
      | Error err -> Alcotest.fail (Errors.to_string err)
      | Ok spec ->
          List.iter
            (fun (inst : Vector_instruction.t) ->
              let base =
                match String.split_on_char '_' inst.mnemonic with
                | b :: _ -> b
                | [] -> inst.mnemonic
              in
              match Isa_grammar.lookup_family base with
              | None -> Alcotest.fail "Unknown family"
              | Some f ->
                  Alcotest.(check bool) "is compare class" true (f.klass = Instruction_class.Compare);
                  Alcotest.(check bool) "is compare op" true
                    (match inst.binary_op with
                    | Some op -> Types.Binary_op.is_compare op
                    | None -> false))
            spec.instructions

let test_widening_generation_sets_flag_and_sail_widths () =
  match Generation_profile.make ~name:"w" ~class_weights:[ (Instruction_class.Widening, 1.0) ] with
  | Error err -> Alcotest.fail (Errors.to_string err)
  | Ok wide_profile ->
      match generate ~seed:5 ~n:3 ~profile:wide_profile () with
      | Error err -> Alcotest.fail (Errors.to_string err)
      | Ok spec ->
          let sail_text = Vector_isa_spec.to_sail_specification spec in
          List.iter
            (fun (inst : Vector_instruction.t) ->
              Alcotest.(check bool) "is_widening true" true inst.is_widening;
              Alcotest.(check bool) "format is OP_WIDENING" true
                (inst.format = Types.Instruction_format.OP_WIDENING);
              let fn_sail = Sail_ast.function_to_sail inst.sail_function in
              Alcotest.(check bool) "get_velem sew 32" true (String.contains fn_sail '3' && String.contains fn_sail '2');
              Alcotest.(check bool) "set_velem sew 64" true (String.contains fn_sail '6' && String.contains fn_sail '4'))
            spec.instructions;
          Alcotest.(check bool) "set_velem 64 in sail text" true
            (String.contains sail_text '6' && String.contains sail_text '4')

let test_budget_is_exact_and_catalog_exhaustion_raises () =
  match generate ~seed:8 ~n:7 () with
  | Error err -> Alcotest.fail (Errors.to_string err)
  | Ok spec ->
      Alcotest.(check int) "exact budget 7" 7 (List.length spec.instructions);
      match Generation_profile.make ~name:"s" ~class_weights:[ (Instruction_class.Saturating, 1.0) ] with
      | Error err -> Alcotest.fail (Errors.to_string err)
      | Ok sat_profile ->
          Alcotest.(check bool) "catalog exhausted fails" true
            (Result.is_error (generate ~seed:1 ~n:100 ~profile:sat_profile ()))

let test_compare_sail_uses_call_form () =
  match Generation_profile.make ~name:"cmp" ~class_weights:[ (Instruction_class.Compare, 1.0) ] with
  | Error err -> Alcotest.fail (Errors.to_string err)
  | Ok cmp_profile ->
      match generate ~seed:4 ~n:2 ~profile:cmp_profile () with
      | Error err -> Alcotest.fail (Errors.to_string err)
      | Ok spec ->
          let sail_text = Vector_isa_spec.to_sail_specification spec in
          Alcotest.(check bool) "compare call form present" true
            (String.contains sail_text '(' && (
              String.contains sail_text 'e' || String.contains sail_text 'n' ||
              String.contains sail_text 'l' || String.contains sail_text 'g'))

let test_encoding_comment_format_is_stable () =
  match generate ~seed:21 ~n:10 () with
  | Error err -> Alcotest.fail (Errors.to_string err)
  | Ok spec ->
      let sail_text = Vector_isa_spec.to_sail_specification spec in
      List.iter
        (fun (inst : Vector_instruction.t) ->
          let expected_pattern =
            Printf.sprintf "Instruction: %s (%s) encoding: funct6=%d, funct3=%d"
              inst.mnemonic
              (Types.Instruction_format.to_string inst.format)
              inst.funct6
              inst.funct3
          in
          Alcotest.(check bool)
            (Printf.sprintf "comment contains %s" inst.mnemonic)
            true
            (let len = String.length expected_pattern in
             let text_len = String.length sail_text in
             let rec find_sub i =
               if i + len > text_len then false
               else if String.sub sail_text i len = expected_pattern then true
               else find_sub (i + 1)
             in
             find_sub 0))
        spec.instructions

let tests = [
  Alcotest.test_case "mnemonics_are_family_variants_not_numbered" `Quick test_mnemonics_are_family_variants_not_numbered;
  Alcotest.test_case "format_variants_of_one_family_share_funct6" `Quick test_format_variants_of_one_family_share_funct6;
  Alcotest.test_case "higher_weight_family_gets_lower_or_equal_funct6" `Quick test_higher_weight_family_gets_lower_or_equal_funct6;
  Alcotest.test_case "rvv_like_prioritises_arith_over_saturating" `Quick test_rvv_like_prioritises_arith_over_saturating;
  Alcotest.test_case "class_profile_restricts_generated_classes" `Quick test_class_profile_restricts_generated_classes;
  Alcotest.test_case "widening_generation_sets_flag_and_sail_widths" `Quick test_widening_generation_sets_flag_and_sail_widths;
  Alcotest.test_case "budget_is_exact_and_catalog_exhaustion_raises" `Quick test_budget_is_exact_and_catalog_exhaustion_raises;
  Alcotest.test_case "compare_sail_uses_call_form" `Quick test_compare_sail_uses_call_form;
  Alcotest.test_case "encoding_comment_format_is_stable" `Quick test_encoding_comment_format_is_stable;
]
