let stitch_arm64_literal_payload ~rng ~payload =
  let tag = Random.State.int rng 0xFFFFF in
  let w_low = Int64.logand payload 0xFFFFFFFFL in
  let w_high = Int64.logand (Int64.shift_right_logical payload 32) 0xFFFFFFFFL in
  Printf.sprintf
    "    adr x16, _asgard_lit_lbl_%d\n    br x16\n    .inst 0x%08LX\n    .inst 0x%08LX\n_asgard_lit_lbl_%d:\n"
    tag w_low w_high tag

let obfuscate_arm64_asm_sequence ~rng (asm_code : string) =
  let lines = String.split_on_char '\n' asm_code in
  let buf = Buffer.create (String.length asm_code * 2) in
  List.iter
    (fun line ->
      let trimmed = String.trim line in
      if String.length trimmed > 0 && not (String.starts_with ~prefix:"." trimmed) && not (String.ends_with ~suffix:":" trimmed) then begin
        if Random.State.int rng 5 = 0 then begin
          let dummy_payload = Int64.logor 0x5877000000000000L (Int64.of_int (Random.State.int rng 0xFFFFFFF)) in
          Buffer.add_string buf (stitch_arm64_literal_payload ~rng ~payload:dummy_payload)
        end
      end;
      Buffer.add_string buf line;
      Buffer.add_char buf '\n')
    lines;
  Buffer.contents buf
