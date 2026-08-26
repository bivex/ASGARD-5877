open Random_visa_domain

let test_catalog_has_families_for_every_supported_class () =
  List.iter
    (fun cls ->
      let fams = Isa_grammar.families_for cls in
      Alcotest.(check bool)
        (Printf.sprintf "class %s has families" (Instruction_class.to_string cls))
        true
        (List.length fams >= 1);
      List.iter
        (fun (fam : Instruction_family.t) ->
          Alcotest.(check bool) "family class matches" true (fam.klass = cls))
        fams)
    Instruction_class.supported

let test_every_supported_family_is_well_formed () =
  List.iter
    (fun (cls, fams) ->
      List.iter
        (fun (fam : Instruction_family.t) ->
          Alcotest.(check bool) "base starts with v" true (fam.mnemonic_base.[0] = 'v');
          Alcotest.(check bool) "has op" true
            ((fam.binary_op = None && fam.unary_op <> None)
            || (fam.binary_op <> None && fam.unary_op = None));
          Alcotest.(check bool) "non-empty formats" true (List.length fam.formats >= 1);
          Alcotest.(check bool) "weight > 0" true (fam.weight > 0.0);
          Alcotest.(check bool) "widening flag matches" true
            (fam.is_widening = (cls = Instruction_class.Widening)))
        fams)
    Isa_grammar.family_catalog

let test_widening_families_use_widening_format_only () =
  let widening_fams = Isa_grammar.families_for Instruction_class.Widening in
  Alcotest.(check bool) "has widening families" true (List.length widening_fams >= 1);
  List.iter
    (fun (fam : Instruction_family.t) ->
      Alcotest.(check bool) "is widening format" true
        (fam.formats = [ Types.Instruction_format.OP_WIDENING ]);
      Alcotest.(check bool) "is_widening flag true" true fam.is_widening)
    widening_fams

let test_compare_families_carry_compare_ops () =
  let compare_fams = Isa_grammar.families_for Instruction_class.Compare in
  Alcotest.(check bool) "has compare families" true (List.length compare_fams >= 1);
  List.iter
    (fun (fam : Instruction_family.t) ->
      match fam.binary_op with
      | None -> Alcotest.fail "Compare family must have binary op"
      | Some op ->
          Alcotest.(check bool) "op is compare" true (Types.Binary_op.is_compare op))
    compare_fams

let test_base_names_unique_across_catalog () =
  let all_bases =
    List.concat_map
      (fun (_, fams) -> List.map (fun (f : Instruction_family.t) -> f.mnemonic_base) fams)
      Isa_grammar.family_catalog
  in
  let unique = List.sort_uniq String.compare all_bases in
  Alcotest.(check int) "all base names unique" (List.length all_bases) (List.length unique);
  Alcotest.(check int) "exactly 28 families" 28 (List.length all_bases)

let test_lookup_family_finds_and_misses () =
  let vwadd = Isa_grammar.lookup_family "vwadd" in
  Alcotest.(check bool) "finds vwadd" true (Option.is_some vwadd);
  Alcotest.(check bool) "vwadd is widening" true ((Option.get vwadd).is_widening);

  let vmseq = Isa_grammar.lookup_family "vmseq" in
  Alcotest.(check bool) "finds vmseq" true (Option.is_some vmseq);
  Alcotest.(check bool) "vmseq is compare" true ((Option.get vmseq).klass = Instruction_class.Compare);

  let vadd = Isa_grammar.lookup_family "vadd" in
  Alcotest.(check bool) "finds vadd" true (Option.is_some vadd);
  Alcotest.(check bool) "vadd is arith" true ((Option.get vadd).klass = Instruction_class.Arith);

  let nope = Isa_grammar.lookup_family "nope" in
  Alcotest.(check bool) "nope misses" true (Option.is_none nope)

let test_named_profiles_registered_and_valid () =
  let names = Isa_grammar.available_profiles () in
  Alcotest.(check bool) "has rvv-like" true (List.mem "rvv-like" names);
  Alcotest.(check bool) "has uniform" true (List.mem "uniform" names);
  List.iter
    (fun name ->
      match Isa_grammar.get_profile name with
      | Error err -> Alcotest.fail (Errors.to_string err)
      | Ok p ->
          Alcotest.(check bool) "enabled classes >= 1" true
            (List.length (Generation_profile.enabled_classes p) >= 1))
    names

let test_get_profile_unknown_name_raises_with_list () =
  match Isa_grammar.get_profile "does-not-exist" with
  | Ok _ -> Alcotest.fail "Expected unknown profile to error"
  | Error (Errors.Invalid_profile msg) ->
      Alcotest.(check bool) "mentions rvv-like" true (String.contains msg 'r')
  | Error err -> Alcotest.fail (Errors.to_string err)

let test_rvv_like_profile_prioritises_arith () =
  let rvv = Generation_profile.rvv_like in
  let uniform = Generation_profile.uniform in
  Alcotest.(check bool) "rvv arith > compare" true
    (Generation_profile.weight_for rvv Instruction_class.Arith > Generation_profile.weight_for rvv Instruction_class.Compare);
  Alcotest.(check (float 0.001)) "rvv arith is 55.0" 55.0 (Generation_profile.weight_for rvv Instruction_class.Arith);

  let w_arith = Generation_profile.weight_for uniform Instruction_class.Arith in
  let w_sat = Generation_profile.weight_for uniform Instruction_class.Saturating in
  let w_wide = Generation_profile.weight_for uniform Instruction_class.Widening in
  let w_cmp = Generation_profile.weight_for uniform Instruction_class.Compare in
  Alcotest.(check (float 0.001)) "uniform equal 1" w_arith w_sat;
  Alcotest.(check (float 0.001)) "uniform equal 2" w_sat w_wide;
  Alcotest.(check (float 0.001)) "uniform equal 3" w_wide w_cmp

let test_profile_rejects_unsupported_and_bad_weights () =
  Alcotest.(check bool) "unsupported Memory rejected" true
    (Result.is_error (Generation_profile.make ~name:"bad" ~class_weights:[ (Instruction_class.Memory, 1.0) ]));
  Alcotest.(check bool) "all-zero weights rejected" true
    (Result.is_error (Generation_profile.make ~name:"empty" ~class_weights:[ (Instruction_class.Arith, 0.0) ]));
  Alcotest.(check bool) "negative weight rejected" true
    (Result.is_error (Generation_profile.make ~name:"neg" ~class_weights:[ (Instruction_class.Arith, -1.0) ]));
  Alcotest.(check bool) "duplicate class rejected" true
    (Result.is_error (Generation_profile.make ~name:"dup" ~class_weights:[ (Instruction_class.Arith, 1.0); (Instruction_class.Arith, 2.0) ]))

let test_family_value_object_validates_itself () =
  Alcotest.(check bool) "missing operator rejected" true
    (Result.is_error (Instruction_family.make ~mnemonic_base:"vweird" ~klass:Instruction_class.Arith ~weight:1.0 ~formats:[ Types.Instruction_format.OP_VV ] ()));
  Alcotest.(check bool) "empty formats rejected" true
    (Result.is_error (Instruction_family.make ~mnemonic_base:"vadd2" ~klass:Instruction_class.Arith ~weight:1.0 ~formats:[] ~binary_op:Types.Binary_op.ADD ()));
  Alcotest.(check bool) "zero weight rejected" true
    (Result.is_error (Instruction_family.make ~mnemonic_base:"vadd2" ~klass:Instruction_class.Arith ~weight:0.0 ~formats:[ Types.Instruction_format.OP_VV ] ~binary_op:Types.Binary_op.ADD ()))

let tests = [
  Alcotest.test_case "catalog_has_families_for_every_supported_class" `Quick test_catalog_has_families_for_every_supported_class;
  Alcotest.test_case "every_supported_family_is_well_formed" `Quick test_every_supported_family_is_well_formed;
  Alcotest.test_case "widening_families_use_widening_format_only" `Quick test_widening_families_use_widening_format_only;
  Alcotest.test_case "compare_families_carry_compare_ops" `Quick test_compare_families_carry_compare_ops;
  Alcotest.test_case "base_names_unique_across_catalog" `Quick test_base_names_unique_across_catalog;
  Alcotest.test_case "lookup_family_finds_and_misses" `Quick test_lookup_family_finds_and_misses;
  Alcotest.test_case "named_profiles_registered_and_valid" `Quick test_named_profiles_registered_and_valid;
  Alcotest.test_case "get_profile_unknown_name_raises_with_list" `Quick test_get_profile_unknown_name_raises_with_list;
  Alcotest.test_case "rvv_like_profile_prioritises_arith" `Quick test_rvv_like_profile_prioritises_arith;
  Alcotest.test_case "profile_rejects_unsupported_and_bad_weights" `Quick test_profile_rejects_unsupported_and_bad_weights;
  Alcotest.test_case "family_value_object_validates_itself" `Quick test_family_value_object_validates_itself;
]
