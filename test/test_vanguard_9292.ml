open Vanguard_9292

let test_layout_validation () =
  let f1 = { kind = Opcode; bit_offset = 0; bit_width = 8 } in
  let f2 = { kind = Dst; bit_offset = 8; bit_width = 5 } in
  let f3 = { kind = Src1; bit_offset = 13; bit_width = 5 } in
  let f4 = { kind = Src2; bit_offset = 18; bit_width = 5 } in
  let f5 = { kind = Imm; bit_offset = 23; bit_width = 8 } in
  let f6 = { kind = Mask; bit_offset = 31; bit_width = 1 } in

  (* Valid 32-bit layout *)
  let valid_res = make_layout ~word_bits:32 ~fields:[ f1; f2; f3; f4; f5; f6 ] in
  Alcotest.(check bool) "valid layout" true (Result.is_ok valid_res);

  (* Overlapping layout: f2 and f_bad overlap *)
  let f_bad = { kind = Src1; bit_offset = 10; bit_width = 5 } in
  let overlap_res = make_layout ~word_bits:32 ~fields:[ f1; f2; f_bad ] in
  Alcotest.(check bool) "overlap fails" true (Result.is_error overlap_res);

  (* Exceeds word_bits *)
  let overflow_res = make_layout ~word_bits:24 ~fields:[ f1; f2; f3; f4; f5; f6 ] in
  Alcotest.(check bool) "overflow fails" true (Result.is_error overflow_res)

let test_opcode_map_and_junk () =
  let rng = Random.State.make [| 42 |] in
  let mnemonics = [ "vadd"; "vsub"; "vmul"; "vand" ] in
  match Opcode_map.generate ~rng ~mnemonics ~opcode_bits:6 with
  | Error err -> Alcotest.fail err
  | Ok map ->
      Alcotest.(check int) "opcode bits is 6" 6 map.opcode_bits;
      (* Verify bijection *)
      List.iter
        (fun mnem ->
          match Opcode_map.encode map mnem with
          | None -> Alcotest.fail (Printf.sprintf "Missing opcode for %s" mnem)
          | Some code ->
              Alcotest.(check (option string)) "reverse lookup matches" (Some mnem) (Opcode_map.decode map code))
        mnemonics;

      (* Check junk opcodes (space is 64, mnemonics is 4, 60 junk opcodes exist) *)
      let junk_count = ref 0 in
      for c = 0 to 63 do
        if Opcode_map.is_junk map c then incr junk_count
      done;
      Alcotest.(check int) "60 junk opcodes found" 60 !junk_count

let test_rolling_key () =
  let key = Rolling_key.make ~seed:0x12345678l in
  let val1 = Rolling_key.next key in
  let val2 = Rolling_key.next key in
  let val3 = Rolling_key.next key in
  Alcotest.(check bool) "val1 <> val2" true (val1 <> val2);
  Alcotest.(check bool) "val2 <> val3" true (val2 <> val3);

  (* Reset restores identical stream *)
  Rolling_key.reset key;
  let val1_again = Rolling_key.next key in
  let val2_again = Rolling_key.next key in
  Alcotest.(check int32) "val1 matches" val1 val1_again;
  Alcotest.(check int32) "val2 matches" val2 val2_again

let test_encode_decode_roundtrip () =
  let rng = Random.State.make [| 999 |] in
  let mnemonics = [ "vadd_vv"; "vsub_vx"; "vmul_vi"; "vand_vv"; "vor_vv" ] in
  match generate ~word_bits:48 ~rng ~mnemonics () with
  | Error err -> Alcotest.fail err
  | Ok scheme ->
      let key_enc = Rolling_key.make ~seed:scheme.key_seed in
      let key_dec = Rolling_key.make ~seed:scheme.key_seed in

      (* Test stream of 5 instructions *)
      let instructions = [
        ("vadd_vv", 3, 2, 1, 0, true);
        ("vsub_vx", 4, 2, 5, 0, false);
        ("vmul_vi", 7, 6, 0, 15, true);
        ("vand_vv", 10, 8, 9, 0, false);
        ("vor_vv", 15, 12, 14, 0, true);
      ] in

      List.iter
        (fun (mnem, dst, s1, s2, imm, mask) ->
          match encode_word scheme ~mnemonic:mnem ~dst ~src1:s1 ~src2:s2 ~imm ~mask ~key:key_enc with
          | Error err -> Alcotest.fail err
          | Ok raw -> (
              match decode_word scheme ~key:key_dec raw with
              | Error `Junk_opcode -> Alcotest.fail "Decoded as junk opcode"
              | Error (`Unknown_opcode code) -> Alcotest.fail (Printf.sprintf "Decoded unknown opcode %d" code)
              | Error (`Corrupted_field msg) -> Alcotest.fail msg
              | Ok (dec_mnem, `Dst dec_dst, `Src1 dec_s1, `Src2 dec_s2, `Imm dec_imm, `Mask dec_mask) ->
                  Alcotest.(check string) "mnemonic matches" mnem dec_mnem;
                  Alcotest.(check int) "dst matches" dst dec_dst;
                  Alcotest.(check int) "src1 matches" s1 dec_s1;
                  Alcotest.(check int) "src2 matches" s2 dec_s2;
                  Alcotest.(check int) "imm matches" imm dec_imm;
                  Alcotest.(check bool) "mask matches" mask dec_mask))
        instructions

let test_junk_opcode_detection () =
  let rng = Random.State.make [| 12345 |] in
  let mnemonics = [ "vadd"; "vsub" ] in
  match generate ~word_bits:32 ~rng ~mnemonics () with
  | Error err -> Alcotest.fail err
  | Ok scheme ->
      let key_enc = Rolling_key.make ~seed:scheme.key_seed in
      let key_dec = Rolling_key.make ~seed:scheme.key_seed in
      (* Encode a valid word *)
      let raw = Result.get_ok (encode_word scheme ~mnemonic:"vadd" ~dst:1 ~src1:2 ~src2:3 ~imm:4 ~mask:true ~key:key_enc) in
      (* Now decode without key XOR (or with corrupted word) *)
      let corrupt = Int64.logxor raw 0x7FFFFFFFFFFFFFFFL in
      let dec_res = decode_word scheme ~key:key_dec corrupt in
      Alcotest.(check bool) "corrupted word is rejected" true (Result.is_error dec_res)

(** Property test: 1,000 random seeds for arbitrary instruction counts *)
let prop_vanguard_roundtrip =
  QCheck.Test.make
    ~name:"vanguard_randomized_scheme_1000_seeds"
    ~count:1000
    QCheck.int
    (fun seed ->
      let rng = Random.State.make [| seed |] in
      let count = 4 + (abs seed mod 16) in (* 4 to 19 mnemonics *)
      let mnemonics = List.init count (fun i -> Printf.sprintf "v_inst_%d" i) in
      match generate ~rng ~mnemonics () with
      | Error _ -> false
      | Ok scheme ->
          let key_enc = Rolling_key.make ~seed:scheme.key_seed in
          let key_dec = Rolling_key.make ~seed:scheme.key_seed in
          let mnem = List.hd mnemonics in
          let dst = abs seed mod 32 in
          let s1 = (abs seed / 32) mod 32 in
          let s2 = (abs seed / 1024) mod 32 in
          let imm = abs seed mod 16 in
          let mask = (seed land 1) = 1 in
          match encode_word scheme ~mnemonic:mnem ~dst ~src1:s1 ~src2:s2 ~imm ~mask ~key:key_enc with
          | Error _ -> false
          | Ok raw -> (
              match decode_word scheme ~key:key_dec raw with
              | Ok (dec_m, `Dst d, `Src1 s_1, `Src2 s_2, `Imm im, `Mask mk) ->
                  dec_m = mnem && d = dst && s_1 = s1 && s_2 = s2 && im = imm && mk = mask
              | Error _ -> false))

let tests = [
  Alcotest.test_case "layout_validation" `Quick test_layout_validation;
  Alcotest.test_case "opcode_map_and_junk" `Quick test_opcode_map_and_junk;
  Alcotest.test_case "rolling_key" `Quick test_rolling_key;
  Alcotest.test_case "encode_decode_roundtrip" `Quick test_encode_decode_roundtrip;
  Alcotest.test_case "junk_opcode_detection" `Quick test_junk_opcode_detection;
  QCheck_alcotest.to_alcotest prop_vanguard_roundtrip;
]
