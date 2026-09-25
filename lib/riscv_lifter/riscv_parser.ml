open Vm_ir
include Riscv_types
open Riscv_regs

let strip_comments line =
  let len = String.length line in
  let rec find_start i in_str =
    if i >= len then len
    else
      let c = line.[i] in
      if in_str && c = '\\' && i + 1 < len then
        find_start (i + 2) in_str
      else if c = '"' then find_start (i + 1) (not in_str)
      else if not in_str && (c = '#' || c = ';' || (c = '/' && i + 1 < len && line.[i + 1] = '/')) then i
      else find_start (i + 1) in_str
  in
  String.trim (String.sub line 0 (find_start 0 false))

let find_string_bounds s =
  let len = String.length s in
  match String.index_opt s '"' with
  | None -> None
  | Some q1 ->
      let rec find_close i =
        if i >= len then None
        else if s.[i] = '\\' && i + 1 < len then find_close (i + 2)
        else if s.[i] = '"' then Some i
        else find_close (i + 1)
      in
      match find_close (q1 + 1) with
      | Some q2 -> Some (q1, q2)
      | None -> None

let parse_mem str width is_signed =
  let s = String.trim str in
  if String.ends_with ~suffix:")" s && String.contains s '(' then
    let lparen = String.index s '(' in
    let rparen = String.rindex s ')' in
    let disp_str = String.sub s 0 lparen |> String.trim in
    let base_str = String.sub s (lparen + 1) (rparen - lparen - 1) |> String.trim in
    let disp =
      if disp_str = "" then 0L
      else match parse_imm disp_str with Ok i -> i | Error _ -> 0L
    in
    match map_riscv_reg base_str with
    | Ok b -> Ok { base = Some b; disp; width; is_signed }
    | Error err -> Error err
  else if String.starts_with ~prefix:"[" s && String.ends_with ~suffix:"]" s then
    let inner = String.sub s 1 (String.length s - 2) |> String.trim in
    let parts = String.split_on_char ',' inner |> List.map String.trim |> List.filter (fun x -> x <> "") in
    match parts with
    | [ base_str ] -> (
        match map_riscv_reg base_str with
        | Ok b -> Ok { base = Some b; disp = 0L; width; is_signed }
        | Error err -> Error err)
    | [ base_str; disp_str ] -> (
        match map_riscv_reg base_str with
        | Ok b ->
            let disp = match parse_imm disp_str with Ok i -> i | Error _ -> 0L in
            Ok { base = Some b; disp; width; is_signed }
        | Error err -> Error err)
    | _ -> Error (Printf.sprintf "Invalid memory operand '%s'" str)
  else
    Error (Printf.sprintf "Invalid memory operand '%s'" str)

let is_mem_operand s =
  (String.ends_with ~suffix:")" s && String.contains s '(') ||
  (String.starts_with ~prefix:"[" s && String.ends_with ~suffix:"]" s)

let parse_operand str default_width is_signed =
  let s = String.trim str in
  if is_mem_operand s then
    match parse_mem s default_width is_signed with
    | Ok m -> Ok (OpMem m)
    | Error err -> Error err
  else
    match map_riscv_reg ~width:default_width s with
    | Ok r -> Ok (OpReg r)
    | Error _ -> (
        match parse_imm s with
        | Ok i -> Ok (OpImm i)
        | Error _ -> Ok (OpLabel s))

let parse_line raw =
  let line = strip_comments raw in
  if line = "" then Ok LineEmpty
  else if String.ends_with ~suffix:":" line then
    let lbl = String.sub line 0 (String.length line - 1) |> String.trim in
    Ok (LineLabel lbl)
  else if String.starts_with ~prefix:"." line then
    Ok (LineDirective line)
  else
    let first_space =
      match String.index_opt line '\t' with
      | Some i -> (
          match String.index_opt line ' ' with
          | Some j -> min i j
          | None -> i)
      | None -> (
          match String.index_opt line ' ' with
          | Some j -> j
          | None -> String.length line)
    in
    let mnemonic = String.sub line 0 first_space |> String.trim |> String.lowercase_ascii in
    let args_str =
      if first_space < String.length line then
        String.sub line first_space (String.length line - first_space) |> String.trim
      else ""
    in
    if args_str = "" then
      Ok (LineInstr (mnemonic, []))
    else
      let raw_args =
        let len = String.length args_str in
        let rec scan i start in_paren in_bracket acc =
          if i >= len then
            let piece = String.trim (String.sub args_str start (len - start)) in
            List.rev (if piece = "" then acc else piece :: acc)
          else
            match args_str.[i] with
            | '(' -> scan (i + 1) start true in_bracket acc
            | ')' -> scan (i + 1) start false in_bracket acc
            | '[' -> scan (i + 1) start in_paren true acc
            | ']' -> scan (i + 1) start in_paren false acc
            | ',' when not in_paren && not in_bracket ->
                let piece = String.trim (String.sub args_str start (i - start)) in
                let acc' = if piece = "" then acc else piece :: acc in
                scan (i + 1) (i + 1) false false acc'
            | _ -> scan (i + 1) start in_paren in_bracket acc
        in
        scan 0 0 false false []
      in

      let def_width, is_signed =
        match mnemonic with
        | "lb" -> Register.B8, true
        | "lbu" | "sb" -> Register.B8, false
        | "lh" -> Register.B16, true
        | "lhu" | "sh" -> Register.B16, false
        | "lw" -> Register.B32, true
        | "lwu" | "sw" | "flw" | "fsw" -> Register.B32, false
        | "ld" | "sd" | "fld" | "fsd" -> Register.B64, false
        | m when String.ends_with ~suffix:"w" m -> Register.B32, true
        | _ -> Register.B64, false
      in

      let rec parse_all acc = function
        | [] -> Ok (LineInstr (mnemonic, List.rev acc))
        | a :: rest ->
            match parse_operand a def_width is_signed with
            | Ok op -> parse_all (op :: acc) rest
            | Error err -> Error err
      in
      parse_all [] raw_args

let parse_lines text =
  let lines = String.split_on_char '\n' text in
  let contains_sub haystack needle =
    let hlen = String.length haystack and nlen = String.length needle in
    if nlen > hlen then false
    else
      let rec at i j =
        if j >= nlen then true
        else if String.unsafe_get haystack (i + j) <> String.unsafe_get needle j then false
        else at i (j + 1)
      in
      let rec check i =
        if i + nlen > hlen then false
        else if at i 0 then true
        else check (i + 1)
      in
      check 0
  in
  let rec loop acc = function
    | [] -> Ok (List.rev acc)
    | l :: rest ->
        let clean = strip_comments l in
        if clean = "" then loop (LineEmpty :: acc) rest
        else if contains_sub clean "ASGARD_" || contains_sub clean "asgard_" then
          let upper = String.uppercase_ascii clean in
          if contains_sub upper "ASGARD_BEG_V" || contains_sub upper "ASGARD_BEGIN_V" then
            let acc' = match acc with
              | LineInstr ("j", _) :: prev | LineInstr ("jal", _) :: prev -> prev
              | _ -> acc
            in
            loop (LineMarkerBegin (ModeVirtualize "region") :: acc') rest
          else if contains_sub upper "ASGARD_BEG_M" || contains_sub upper "ASGARD_BEGIN_M" then
            let acc' = match acc with
              | LineInstr ("j", _) :: prev | LineInstr ("jal", _) :: prev -> prev
              | _ -> acc
            in
            loop (LineMarkerBegin (ModeMutation "region") :: acc') rest
          else if contains_sub upper "ASGARD_BEG" || contains_sub upper "ASGARD_BEGIN" then
            let acc' = match acc with
              | LineInstr ("j", _) :: prev | LineInstr ("jal", _) :: prev -> prev
              | _ -> acc
            in
            loop (LineMarkerBegin (ModeUltra "region") :: acc') rest
          else if contains_sub upper "ASGARD_END" then
            let acc' = match acc with
              | LineInstr ("j", _) :: prev | LineInstr ("jal", _) :: prev -> prev
              | _ -> acc
            in
            loop (LineMarkerEnd :: acc') rest
          else
            match parse_line l with
            | Ok res -> loop (res :: acc) rest
            | Error err -> Error err
        else
          match parse_line l with
          | Ok res -> loop (res :: acc) rest
          | Error err -> Error err
  in
  loop [] lines

let unescape_asm_str s =
  let len = String.length s in
  let buf = Buffer.create len in
  let i = ref 0 in
  while !i < len do
    if s.[!i] = '\\' && !i + 1 < len then begin
      incr i;
      match s.[!i] with
      | '0' .. '7' ->
          let oct_str = Buffer.create 3 in
          Buffer.add_char oct_str s.[!i];
          if !i + 1 < len && (let c = s.[!i + 1] in c >= '0' && c <= '7') then (
            incr i; Buffer.add_char oct_str s.[!i];
            if !i + 1 < len && (let c = s.[!i + 1] in c >= '0' && c <= '7') then (
              incr i; Buffer.add_char oct_str s.[!i]
            )
          );
          let oct_val = try int_of_string ("0o" ^ Buffer.contents oct_str) with _ -> 0 in
          Buffer.add_char buf (Char.chr (oct_val land 0xFF));
          incr i
      | 'b' -> Buffer.add_char buf '\b'; incr i
      | 'f' -> Buffer.add_char buf '\012'; incr i
      | 'v' -> Buffer.add_char buf '\011'; incr i
      | 'a' -> Buffer.add_char buf '\007'; incr i
      | 'n' -> Buffer.add_char buf '\n'; incr i
      | 't' -> Buffer.add_char buf '\t'; incr i
      | 'r' -> Buffer.add_char buf '\r'; incr i
      | '\\' -> Buffer.add_char buf '\\'; incr i
      | '"' -> Buffer.add_char buf '"'; incr i
      | '\'' -> Buffer.add_char buf '\''; incr i
      | '?' -> Buffer.add_char buf '?'; incr i
      | 'x' when !i + 2 < len &&
                 (let is_hex c = (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F') in
                  is_hex s.[!i + 1] && is_hex s.[!i + 2]) ->
          let v = int_of_string ("0x" ^ String.sub s (!i + 1) 2) in
          Buffer.add_char buf (Char.chr (v land 0xFF));
          i := !i + 3
      | other -> Buffer.add_char buf other; incr i
    end else begin
      Buffer.add_char buf s.[!i];
      incr i
    end
  done;
  Buffer.contents buf

let extract_constants text =
  let lines = String.split_on_char '\n' text in
  let constants = ref [] in
  let cur_label = ref None in
  List.iter
    (fun l ->
      let clean = strip_comments l in
      if String.ends_with ~suffix:":" clean then (
        let lbl = String.trim (String.sub clean 0 (String.length clean - 1)) in
        cur_label := Some lbl
      ) else (
        match !cur_label with
        | None -> ()
        | Some lbl ->
            let trimmed = String.trim clean in
            if String.starts_with ~prefix:".ascii" trimmed || String.starts_with ~prefix:".asciz" trimmed || String.starts_with ~prefix:".string" trimmed then (
              let is_asciz = String.starts_with ~prefix:".asciz" trimmed || String.starts_with ~prefix:".string" trimmed in
              match find_string_bounds trimmed with
              | Some (q1, q2) ->
                  let raw_str = String.sub trimmed (q1 + 1) (q2 - q1 - 1) in
                  let unescaped = unescape_asm_str raw_str in
                  let data = if is_asciz then unescaped ^ "\000" else unescaped in
                  constants := (lbl, data) :: !constants;
                  cur_label := None
              | None -> ()
            ) else if String.starts_with ~prefix:".byte" trimmed then (
              let rest = String.sub trimmed 5 (String.length trimmed - 5) in
              let parts = String.split_on_char ',' rest |> List.map String.trim in
              let buf = Buffer.create (List.length parts) in
              List.iter
                (fun p ->
                  let v = try int_of_string p land 0xFF with _ -> 0 in
                  Buffer.add_char buf (Char.chr v))
                parts;
              constants := (lbl, Buffer.contents buf) :: !constants;
              cur_label := None
            ) else if String.starts_with ~prefix:"." trimmed && not (String.starts_with ~prefix:".p2align" trimmed || String.starts_with ~prefix:".align" trimmed) then (
              ()
            )
      ))
    lines;
  List.rev !constants
