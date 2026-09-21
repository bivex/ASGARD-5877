open Random_visa_domain
open Vanguard_types

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

let parse_reg reg_str =
  let s = String.trim (String.lowercase_ascii reg_str) in
  let body =
    if String.length s > 0 && (s.[0] = 'v' || s.[0] = 'x') then
      String.sub s 1 (String.length s - 1)
    else s
  in
  match int_of_string_opt body with
  | Some idx when idx >= 0 && idx <= 31 -> Ok idx
  | _ -> Error (Printf.sprintf "Invalid register '%s'" reg_str)

let parse_imm imm_str =
  match int_of_string_opt (String.trim imm_str) with
  | Some v -> Ok v
  | None -> Error (Printf.sprintf "Invalid immediate '%s'" imm_str)

let strip_comments line =
  let rec find_comment i =
    if i >= String.length line then String.length line
    else if line.[i] = '#' then i
    else if i + 1 < String.length line && line.[i] = '/' && line.[i + 1] = '/' then i
    else find_comment (i + 1)
  in
  String.trim (String.sub line 0 (find_comment 0))

let assemble_program (t : t) (spec : Vector_isa_spec.t) source_text =
  let key = Rolling_key.make ~seed:t.key_seed in
  let lines = String.split_on_char '\n' source_text in
  let rec loop line_no acc = function
    | [] -> Ok (List.rev acc)
    | raw_line :: rest ->
        let line = strip_comments raw_line in
        if line = "" || String.ends_with ~suffix:":" line then
          loop (line_no + 1) acc rest
        else
          match split_tokens line with
          | [] -> loop (line_no + 1) acc rest
          | mnem_raw :: operands -> (
              let mnem = String.lowercase_ascii mnem_raw in
              match Vector_isa_spec.get_by_mnemonic spec mnem with
              | None -> Error (Printf.sprintf "Line %d: Unknown instruction '%s'" line_no mnem_raw)
              | Some inst -> (
                  let mask = ref true in
                  let ops = ref operands in
                  if !ops <> [] then begin
                    let last = String.lowercase_ascii (List.hd (List.rev !ops)) in
                    if last = "v0.t" || last = "masked" then begin
                      mask := false;
                      let rec drop_last = function [] | [ _ ] -> [] | x :: xs -> x :: drop_last xs in
                      ops := drop_last !ops
                    end
                  end;
                  let parse_ops =
                    match inst.format with
                    | Types.Instruction_format.OP_VV
                    | Types.Instruction_format.OP_RED
                    | Types.Instruction_format.OP_WIDENING -> (
                        match !ops with
                        | [ d; s2; s1 ] -> (
                            match parse_reg d, parse_reg s2, parse_reg s1 with
                            | Ok rd, Ok rs2, Ok rs1 -> Ok (rd, rs1, rs2, 0)
                            | Error e, _, _ | _, Error e, _ | _, _, Error e -> Error e)
                        | _ -> Error (Printf.sprintf "Line %d: %s expects 3 operands" line_no mnem))
                    | Types.Instruction_format.OP_VX -> (
                        match !ops with
                        | [ d; s2; s1 ] -> (
                            match parse_reg d, parse_reg s2, parse_reg s1 with
                            | Ok rd, Ok rs2, Ok rs1 -> Ok (rd, rs1, rs2, 0)
                            | Error e, _, _ | _, Error e, _ | _, _, Error e -> Error e)
                        | _ -> Error (Printf.sprintf "Line %d: %s expects 3 operands" line_no mnem))
                    | Types.Instruction_format.OP_VI -> (
                        match !ops with
                        | [ d; s2; imm_str ] -> (
                            match parse_reg d, parse_reg s2, parse_imm imm_str with
                            | Ok rd, Ok rs2, Ok imm -> Ok (rd, 0, rs2, imm)
                            | Error e, _, _ | _, Error e, _ | _, _, Error e -> Error e)
                        | _ -> Error (Printf.sprintf "Line %d: %s expects vd, vs2, simm" line_no mnem))
                    | Types.Instruction_format.OP_MVV -> (
                        match !ops with
                        | [ d; s2 ] -> (
                            match parse_reg d, parse_reg s2 with
                            | Ok rd, Ok rs2 -> Ok (rd, 0, rs2, 0)
                            | Error e, _ | _, Error e -> Error e)
                        | _ -> Error (Printf.sprintf "Line %d: %s expects vd, vs2" line_no mnem))
                    | _ -> Error (Printf.sprintf "Line %d: Unsupported format" line_no)
                  in
                  match parse_ops with
                  | Error err -> Error err
                  | Ok (dst, src1, src2, imm) -> (
                      match encode_word t ~mnemonic:inst.mnemonic ~dst ~src1 ~src2 ~imm ~mask:!mask ~key with
                      | Error err -> Error (Printf.sprintf "Line %d: %s" line_no err)
                      | Ok word -> loop (line_no + 1) (word :: acc) rest)))
  in
  loop 1 [] lines

let write_bytecode_file words filepath =
  try
    let oc = open_out_bin filepath in
    List.iter
      (fun w ->
        for byte_idx = 0 to 7 do
          let shift = byte_idx * 8 in
          let b = Int64.to_int (Int64.logand (Int64.shift_right_logical w shift) 0xFFL) in
          output_byte oc b
        done)
      words;
    close_out oc;
    Ok filepath
  with exn ->
    Error (Printf.sprintf "Failed to write bytecode to %s: %s" filepath (Printexc.to_string exn))

let read_bytecode_file filepath =
  try
    let ic = open_in_bin filepath in
    let len = in_channel_length ic in
    let bytes = really_input_string ic len in
    close_in ic;
    let count = len / 8 in
    let words = ref [] in
    for i = 0 to count - 1 do
      let offset = i * 8 in
      let w = ref 0L in
      for byte_idx = 0 to 7 do
        let b = Int64.of_int (Char.code bytes.[offset + byte_idx]) in
        w := Int64.logor !w (Int64.shift_left b (byte_idx * 8))
      done;
      words := !w :: !words
    done;
    Ok (List.rev !words)
  with exn ->
    Error (Printf.sprintf "Failed to read bytecode from %s: %s" filepath (Printexc.to_string exn))
