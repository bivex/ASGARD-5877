open Random_visa_domain

let parse_reg reg_str =
  let s = String.trim (String.lowercase_ascii reg_str) in
  let body =
    if String.length s > 0 && (s.[0] = 'v' || s.[0] = 'x' || s.[0] = 'f') then
      String.sub s 1 (String.length s - 1)
    else s
  in
  match int_of_string_opt body with
  | Some idx when idx >= 0 && idx <= 31 -> Ok idx
  | _ ->
      Error (Errors.Assembly_syntax_error (Printf.sprintf "Invalid register operand '%s' (expected v0-v31 or x0-x31)" reg_str))

let parse_imm imm_str =
  let s = String.trim imm_str in
  match int_of_string_opt s with
  | Some v -> Ok (v land 0x1F)
  | None ->
      Error (Errors.Assembly_syntax_error (Printf.sprintf "Invalid immediate operand '%s'" imm_str))

let strip_comments_and_whitespace line =
  let rec find_comment i =
    if i >= String.length line then String.length line
    else if line.[i] = '#' then i
    else if i + 1 < String.length line && line.[i] = '/' && line.[i + 1] = '/' then i
    else find_comment (i + 1)
  in
  let clean = String.sub line 0 (find_comment 0) in
  String.trim clean

let split_tokens str =
  let parts = ref [] in
  let buf = Buffer.create 16 in
  let push () =
    if Buffer.length buf > 0 then begin
      parts := Buffer.contents buf :: !parts;
      Buffer.clear buf
    end
  in
  for i = 0 to String.length str - 1 do
    let c = str.[i] in
    if c = ' ' || c = '\t' || c = ',' then push ()
    else Buffer.add_char buf c
  done;
  push ();
  List.rev !parts

let assemble_line (spec : Vector_isa_spec.t) raw_line =
  let line = strip_comments_and_whitespace raw_line in
  if line = "" then Ok None
  else if String.ends_with ~suffix:":" line then Ok None (* Label *)
  else
    match split_tokens line with
    | [] -> Ok None
    | raw_mnem :: raw_operands ->
        let mnem_clean = String.lowercase_ascii raw_mnem in
        let mnem_alt = String.map (fun c -> if c = '.' then '_' else c) mnem_clean in
        let inst_opt =
          match Vector_isa_spec.get_by_mnemonic spec mnem_clean with
          | Some i -> Some i
          | None -> Vector_isa_spec.get_by_mnemonic spec mnem_alt
        in
        match inst_opt with
        | None ->
            Error (Errors.Assembly_syntax_error (Printf.sprintf "Unknown instruction mnemonic '%s' in ISA '%s'" raw_mnem spec.name))
        | Some (inst : Vector_instruction.t) ->
            let operands = ref raw_operands in
            let vm = ref 1 in
            if !operands <> [] then begin
              let last = String.lowercase_ascii (List.hd (List.rev !operands)) in
              if last = "v0.t" || last = "vm=0" || last = "masked" then begin
                vm := 0;
                let rec drop_last = function
                  | [] | [ _ ] -> []
                  | x :: xs -> x :: drop_last xs
                in
                operands := drop_last !operands
              end
            end;

            let vd = ref 0 in
            let vs2 = ref 0 in
            let vs1 = ref 0 in

            let ops = !operands in
            let res =
              match inst.format with
              | Types.Instruction_format.OP_VV
              | Types.Instruction_format.OP_RED
              | Types.Instruction_format.OP_WIDENING -> (
                  match ops with
                  | [ r_vd; r_vs2; r_vs1 ] -> (
                      match parse_reg r_vd with
                      | Error err -> Error err
                      | Ok d -> (
                          match parse_reg r_vs2 with
                          | Error err -> Error err
                          | Ok s2 -> (
                              match parse_reg r_vs1 with
                              | Error err -> Error err
                              | Ok s1 ->
                                  vd := d; vs2 := s2; vs1 := s1; Ok ())))
                  | _ ->
                      Error (Errors.Assembly_syntax_error (Printf.sprintf "Instruction %s expects 3 operands: vd, vs2, vs1" inst.mnemonic)))

              | Types.Instruction_format.OP_VX -> (
                  match ops with
                  | [ r_vd; r_vs2; r_rs1 ] -> (
                      match parse_reg r_vd with
                      | Error err -> Error err
                      | Ok d -> (
                          match parse_reg r_vs2 with
                          | Error err -> Error err
                          | Ok s2 -> (
                              match parse_reg r_rs1 with
                              | Error err -> Error err
                              | Ok s1 ->
                                  vd := d; vs2 := s2; vs1 := s1; Ok ())))
                  | _ ->
                      Error (Errors.Assembly_syntax_error (Printf.sprintf "Instruction %s expects 3 operands: vd, vs2, rs1" inst.mnemonic)))

              | Types.Instruction_format.OP_VI -> (
                  match ops with
                  | [ r_vd; r_vs2; imm_str ] -> (
                      match parse_reg r_vd with
                      | Error err -> Error err
                      | Ok d -> (
                          match parse_reg r_vs2 with
                          | Error err -> Error err
                          | Ok s2 -> (
                              match parse_imm imm_str with
                              | Error err -> Error err
                              | Ok imm ->
                                  vd := d; vs2 := s2; vs1 := imm; Ok ())))
                  | _ ->
                      Error (Errors.Assembly_syntax_error (Printf.sprintf "Instruction %s expects 3 operands: vd, vs2, simm5" inst.mnemonic)))

              | Types.Instruction_format.OP_MVV -> (
                  match ops with
                  | [ r_vd; r_vs2 ] -> (
                      match parse_reg r_vd with
                      | Error err -> Error err
                      | Ok d -> (
                          match parse_reg r_vs2 with
                          | Error err -> Error err
                          | Ok s2 ->
                              vd := d; vs2 := s2; vs1 := 0; Ok ()))
                  | [ r_vd; r_vs2; _ ] -> (
                      match parse_reg r_vd with
                      | Error err -> Error err
                      | Ok d -> (
                          match parse_reg r_vs2 with
                          | Error err -> Error err
                          | Ok s2 ->
                              vd := d; vs2 := s2; vs1 := 0; Ok ()))
                  | _ ->
                      Error (Errors.Assembly_syntax_error (Printf.sprintf "Instruction %s expects 2 operands: vd, vs2" inst.mnemonic)))
              | _ ->
                  Error (Errors.Unsupported_backend_feature (Printf.sprintf "Assembler does not support format: %s" (Types.Instruction_format.to_string inst.format)))
            in
            match res with
            | Error err -> Error err
            | Ok () ->
                let word = Vector_instruction.encode ~vd:!vd ~vs2:!vs2 ~vs1_or_rs1_or_imm:!vs1 ~vm:!vm inst in
                Ok (Some word)

let assemble_program spec source_text =
  let lines = String.split_on_char '\n' source_text in
  let rec loop line_no acc = function
    | [] -> Ok (List.rev acc)
    | l :: rest -> (
        match assemble_line spec l with
        | Error (Errors.Assembly_syntax_error msg) ->
            Error (Errors.Assembly_syntax_error (Printf.sprintf "Line %d: %s" line_no msg))
        | Error err -> Error err
        | Ok None -> loop (line_no + 1) acc rest
        | Ok (Some w) -> loop (line_no + 1) (w :: acc) rest)
  in
  loop 1 [] lines

let disassemble_word (spec : Vector_isa_spec.t) word =
  match Vector_isa_spec.decode spec word with
  | None ->
      Error (Errors.Assembly_syntax_error (Printf.sprintf "Unknown 32-bit instruction word: 0x%08lX" word))
  | Some (inst : Vector_instruction.t) ->
      let vd = Int32.to_int (Int32.logand (Int32.shift_right_logical word 7) 0x1Fl) in
      let vs1 = Int32.to_int (Int32.logand (Int32.shift_right_logical word 15) 0x1Fl) in
      let vs2 = Int32.to_int (Int32.logand (Int32.shift_right_logical word 20) 0x1Fl) in
      let vm = Int32.to_int (Int32.logand (Int32.shift_right_logical word 25) 0x1l) in

      let mask_suffix = if vm = 0 then ", v0.t" else "" in

      let asm =
        match inst.format with
        | Types.Instruction_format.OP_VV
        | Types.Instruction_format.OP_RED
        | Types.Instruction_format.OP_WIDENING ->
            Printf.sprintf "%s v%d, v%d, v%d%s" inst.mnemonic vd vs2 vs1 mask_suffix
        | Types.Instruction_format.OP_VX ->
            Printf.sprintf "%s v%d, v%d, x%d%s" inst.mnemonic vd vs2 vs1 mask_suffix
        | Types.Instruction_format.OP_VI ->
            let imm = if vs1 land 0x10 <> 0 then vs1 - 32 else vs1 in
            Printf.sprintf "%s v%d, v%d, %d%s" inst.mnemonic vd vs2 imm mask_suffix
        | Types.Instruction_format.OP_MVV ->
            Printf.sprintf "%s v%d, v%d%s" inst.mnemonic vd vs2 mask_suffix
        | _ ->
            Printf.sprintf "%s v%d, v%d, v%d%s" inst.mnemonic vd vs2 vs1 mask_suffix
      in
      Ok asm

let disassemble_program spec words =
  let lines =
    List.map
      (fun w ->
        match disassemble_word spec w with
        | Ok s -> s
        | Error _ -> Printf.sprintf ".word 0x%08lX" w)
      words
  in
  String.concat "\n" lines

let vbc_magic = "\x7fVBC"

let write_binary_bytecode words filepath =
  try
    let oc = open_out_bin filepath in
    List.iter
      (fun w ->
        let b0 = Char.chr (Int32.to_int (Int32.logand w 0xFFl)) in
        let b1 = Char.chr (Int32.to_int (Int32.logand (Int32.shift_right_logical w 8) 0xFFl)) in
        let b2 = Char.chr (Int32.to_int (Int32.logand (Int32.shift_right_logical w 16) 0xFFl)) in
        let b3 = Char.chr (Int32.to_int (Int32.logand (Int32.shift_right_logical w 24) 0xFFl)) in
        output_char oc b0;
        output_char oc b1;
        output_char oc b2;
        output_char oc b3)
      words;
    close_out oc;
    Ok filepath
  with exn ->
    Error (Errors.General_error (Printf.sprintf "Failed to write bytecode to %s: %s" filepath (Printexc.to_string exn)))

let read_binary_bytecode filepath =
  try
    let ic = open_in_bin filepath in
    let len = in_channel_length ic in
    let bytes = really_input_string ic len in
    close_in ic;
    let count = len / 4 in
    let words = ref [] in
    for i = 0 to count - 1 do
      let offset = i * 4 in
      let b0 = Char.code bytes.[offset] in
      let b1 = Char.code bytes.[offset + 1] in
      let b2 = Char.code bytes.[offset + 2] in
      let b3 = Char.code bytes.[offset + 3] in
      let w =
        Int32.logor
          (Int32.of_int b0)
          (Int32.logor
             (Int32.shift_left (Int32.of_int b1) 8)
             (Int32.logor
                (Int32.shift_left (Int32.of_int b2) 16)
                (Int32.shift_left (Int32.of_int b3) 24)))
      in
      words := w :: !words
    done;
    Ok (List.rev !words)
  with exn ->
    Error (Errors.General_error (Printf.sprintf "Failed to read bytecode from %s: %s" filepath (Printexc.to_string exn)))

let write_vbc_file ?(vlen = 128) ?(elen = 64) words filepath =
  try
    let oc = open_out_bin filepath in
    output_string oc vbc_magic; (* 0..3 *)
    output_byte oc 1; (* 4: version 1 *)
    output_byte oc 0; (* 5: reserved *)
    output_byte oc (vlen land 0xFF); (* 6..7: VLEN le *)
    output_byte oc ((vlen lsr 8) land 0xFF);
    output_byte oc (elen land 0xFF); (* 8..9: ELEN le *)
    output_byte oc ((elen lsr 8) land 0xFF);
    output_byte oc 0; (* 10..11: reserved *)
    output_byte oc 0;
    let count = List.length words in
    output_byte oc (count land 0xFF); (* 12..15: count le *)
    output_byte oc ((count lsr 8) land 0xFF);
    output_byte oc ((count lsr 16) land 0xFF);
    output_byte oc ((count lsr 24) land 0xFF);

    List.iter
      (fun w ->
        let b0 = Char.chr (Int32.to_int (Int32.logand w 0xFFl)) in
        let b1 = Char.chr (Int32.to_int (Int32.logand (Int32.shift_right_logical w 8) 0xFFl)) in
        let b2 = Char.chr (Int32.to_int (Int32.logand (Int32.shift_right_logical w 16) 0xFFl)) in
        let b3 = Char.chr (Int32.to_int (Int32.logand (Int32.shift_right_logical w 24) 0xFFl)) in
        output_char oc b0;
        output_char oc b1;
        output_char oc b2;
        output_char oc b3)
      words;
    close_out oc;
    Ok filepath
  with exn ->
    Error (Errors.General_error (Printf.sprintf "Failed to write VBC file %s: %s" filepath (Printexc.to_string exn)))

let read_vbc_file filepath =
  try
    let ic = open_in_bin filepath in
    let len = in_channel_length ic in
    if len < 16 then begin
      close_in ic;
      Error (Errors.Assembly_syntax_error "File is too short to contain a valid VBC header (minimum 16 bytes)")
    end else begin
      let header = really_input_string ic 16 in
      let magic = String.sub header 0 4 in
      if magic <> vbc_magic then begin
        close_in ic;
        Error (Errors.Assembly_syntax_error (Printf.sprintf "Invalid VBC magic '%s' (expected '\\x7fVBC')" (String.escaped magic)))
      end else begin
        let version = Char.code header.[4] in
        if version <> 1 then begin
          close_in ic;
          Error (Errors.Assembly_syntax_error (Printf.sprintf "Unsupported VBC version %d (supported: 1)" version))
        end else begin
          let vlen = Char.code header.[6] lor (Char.code header.[7] lsl 8) in
          let elen = Char.code header.[8] lor (Char.code header.[9] lsl 8) in
          let count =
            Char.code header.[12]
            lor (Char.code header.[13] lsl 8)
            lor (Char.code header.[14] lsl 16)
            lor (Char.code header.[15] lsl 24)
          in
          let body = really_input_string ic (len - 16) in
          close_in ic;
          if String.length body / 4 < count then
            Error (Errors.Assembly_syntax_error (Printf.sprintf "Truncated VBC file: expected %d words, found %d" count (String.length body / 4)))
          else
            let words = ref [] in
            for i = 0 to count - 1 do
              let offset = i * 4 in
              let b0 = Char.code body.[offset] in
              let b1 = Char.code body.[offset + 1] in
              let b2 = Char.code body.[offset + 2] in
              let b3 = Char.code body.[offset + 3] in
              let w =
                Int32.logor
                  (Int32.of_int b0)
                  (Int32.logor
                     (Int32.shift_left (Int32.of_int b1) 8)
                     (Int32.logor
                        (Int32.shift_left (Int32.of_int b2) 16)
                        (Int32.shift_left (Int32.of_int b3) 24)))
              in
              words := w :: !words
            done;
            Ok (vlen, elen, List.rev !words)
        end
      end
    end
  with exn ->
    Error (Errors.General_error (Printf.sprintf "Failed to read VBC file %s: %s" filepath (Printexc.to_string exn)))
