open Vm_ir

type raw_mem = {
  base : Register.t option;
  index : (Register.t * int) option;
  disp : int64;
  width : Register.width;
}

type raw_op =
  | OpReg of Register.t
  | OpImm of int64
  | OpMem of raw_mem
  | OpLabel of string

type marker_mode =
  | ModeVirtualize of string
  | ModeMutation of string
  | ModeUltra of string

type raw_line =
  | LineLabel of string
  | LineInstr of string * raw_op list
  | LineDirective of string
  | LineMarkerBegin of marker_mode
  | LineMarkerEnd
  | LineEmpty

let marker_mode_to_string = function
  | ModeVirtualize tag -> Printf.sprintf "VIRTUALIZE(%s)" tag
  | ModeMutation tag -> Printf.sprintf "MUTATION(%s)" tag
  | ModeUltra tag -> Printf.sprintf "ULTRA(%s)" tag

let strip_comments line =
  let len = String.length line in
  let rec find_start i in_str =
    if i >= len then len
    else
      let c = line.[i] in
      if c = '"' then find_start (i + 1) (not in_str)
      else if not in_str && (c = ';' || c = '#' || (c = '/' && i + 1 < len && line.[i + 1] = '/')) then i
      else find_start (i + 1) in_str
  in
  String.trim (String.sub line 0 (find_start 0 false))

let split_tokens str delim =
  String.split_on_char delim str
  |> List.map String.trim
  |> List.filter (fun s -> s <> "")

let parse_width_prefix str =
  let s = String.lowercase_ascii (String.trim str) in
  if String.starts_with ~prefix:"qword ptr" s then
    (Register.B64, String.trim (String.sub s 9 (String.length s - 9)))
  else if String.starts_with ~prefix:"dword ptr" s then
    (Register.B32, String.trim (String.sub s 9 (String.length s - 9)))
  else if String.starts_with ~prefix:"word ptr" s then
    (Register.B16, String.trim (String.sub s 8 (String.length s - 8)))
  else if String.starts_with ~prefix:"byte ptr" s then
    (Register.B8, String.trim (String.sub s 8 (String.length s - 8)))
  else (Register.B64, s)

let parse_mem_operand body default_width =
  let s = String.trim body in
  let len = String.length s in
  if not (String.starts_with ~prefix:"[" s && String.ends_with ~suffix:"]" s) then
    Error (Printf.sprintf "Invalid memory syntax '%s'" body)
  else
    let inner = String.trim (String.sub s 1 (len - 2)) in
    let tokens = ref [] in
    let buf = Buffer.create 16 in
    let sign = ref 1L in

    let flush is_pos =
      let t = String.trim (Buffer.contents buf) in
      Buffer.clear buf;
      if t <> "" then tokens := (!sign, t) :: !tokens;
      sign := if is_pos then 1L else -1L
    in

    for i = 0 to String.length inner - 1 do
      let c = inner.[i] in
      if c = '+' then flush true
      else if c = '-' then flush false
      else Buffer.add_char buf c
    done;
    flush true;

    let base_reg = ref None in
    let index_reg = ref None in
    let total_disp = ref 0L in
    let err = ref None in

    List.iter
      (fun (s_sign, tok) ->
        if !err <> None then ()
        else if String.contains tok '*' then (
          let parts = split_tokens tok '*' in
          match parts with
          | [ r_str; scale_str ] -> (
              match Register.of_string r_str with
              | Ok r -> (
                  try
                    let scale = int_of_string scale_str in
                    if scale = 1 || scale = 2 || scale = 4 || scale = 8 then
                      index_reg := Some (r, scale)
                    else err := Some (Printf.sprintf "Invalid SIB scale %d" scale)
                  with _ -> err := Some (Printf.sprintf "Invalid scale number '%s'" scale_str))
              | Error _ -> err := Some (Printf.sprintf "Invalid index register '%s'" r_str))
          | _ -> err := Some (Printf.sprintf "Malformed indexed term '%s'" tok))
        else
          match Register.of_string tok with
          | Ok r ->
              if !base_reg = None then base_reg := Some r
              else if !index_reg = None then index_reg := Some (r, 1)
              else err := Some "Multiple base/index registers in memory operand"
          | Error _ -> (
              try
                let v = Int64.of_string tok in
                let signed_v = Int64.mul (Int64.of_int (Int64.to_int s_sign)) v in
                total_disp := Int64.add !total_disp signed_v
              with _ ->
                (* Symbolic displacement like [rip + _symbol]: accept as label reference *)
                total_disp := Int64.add !total_disp 0L))
      (List.rev !tokens);



    match !err with
    | Some e -> Error e
    | None ->
        Ok
          {
            base = !base_reg;
            index = !index_reg;
            disp = !total_disp;
            width = default_width;
          }

let parse_operand str default_width =
  let width, stripped = parse_width_prefix str in
  let w = if width <> Register.B64 then width else default_width in
  if String.starts_with ~prefix:"[" stripped && String.ends_with ~suffix:"]" stripped then
    match parse_mem_operand stripped w with
    | Ok m -> Ok (OpMem m)
    | Error e -> Error e
  else
    match Register.of_string stripped with
    | Ok reg -> Ok (OpReg reg)
    | Error _ -> (
        try
          let v = Int64.of_string stripped in
          Ok (OpImm v)
        with _ ->
          if String.starts_with ~prefix:"offset " (String.lowercase_ascii stripped) then
            let lbl = String.trim (String.sub stripped 7 (String.length stripped - 7)) in
            Ok (OpLabel (String.lowercase_ascii lbl))
          else
            Ok (OpLabel (String.lowercase_ascii stripped)))

let contains_sub s sub =
  let len_s = String.length s in
  let len_sub = String.length sub in
  if len_sub > len_s then false
  else
    let found = ref false in
    for i = 0 to len_s - len_sub do
      if not !found && String.sub s i len_sub = sub then found := true
    done;
    !found

let normalize_alphas s =
  let b = Buffer.create (String.length s) in
  String.iter
    (fun c ->
      if (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || c = '_' then
        Buffer.add_char b (Char.uppercase_ascii c))
    s;
  Buffer.contents b


let is_asgard_marker s =
  let len = String.length s in
  if len < 6 then false
  else
    let rec check i =
      if i + 6 > len then false
      else if (s.[i] = 'A' || s.[i] = 'a') &&
              (s.[i+1] = 'S' || s.[i+1] = 's') &&
              (s.[i+2] = 'G' || s.[i+2] = 'g') &&
              (s.[i+3] = 'A' || s.[i+3] = 'a') &&
              (s.[i+4] = 'R' || s.[i+4] = 'r') &&
              (s.[i+5] = 'D' || s.[i+5] = 'd') then true
      else check (i + 1)
    in
    check 0

let parse_line line =
  let clean = strip_comments line in
  if clean = "" then Ok LineEmpty
  else if is_asgard_marker clean then begin
    let norm = normalize_alphas clean in
    (* Marker detection *)
    if contains_sub norm "BEG" || contains_sub norm "BEGIN" then
      if contains_sub norm "_V" || contains_sub norm "VIRTUAL" then
        Ok (LineMarkerBegin (ModeVirtualize "region"))
      else if contains_sub norm "_M" || contains_sub norm "MUTAT" then
        Ok (LineMarkerBegin (ModeMutation "region"))
      else
        Ok (LineMarkerBegin (ModeUltra "region"))
    else if contains_sub norm "END" then
      Ok LineMarkerEnd
    else
      Ok (LineDirective clean)
  end
  else if String.starts_with ~prefix:"." clean && not (String.contains clean ':') && not (String.starts_with ~prefix:".L" clean) && not (String.starts_with ~prefix:".l" clean) then
    Ok (LineDirective clean)
  else if String.ends_with ~suffix:":" clean then
    let lbl = String.lowercase_ascii (String.trim (String.sub clean 0 (String.length clean - 1))) in
    Ok (LineLabel lbl)
  else
    (* Instruction line *)
    let first_space =
      let rec find i =
        if i >= String.length clean then -1
        else if clean.[i] = ' ' || clean.[i] = '\t' then i
        else find (i + 1)
      in
      find 0
    in
    if first_space = -1 then
      Ok (LineInstr (String.lowercase_ascii clean, []))
    else
      let mnem = String.lowercase_ascii (String.trim (String.sub clean 0 first_space)) in
      let ops_part = String.trim (String.sub clean first_space (String.length clean - first_space)) in
      let op_strings = split_tokens ops_part ',' in
      let rec parse_ops acc = function
        | [] -> Ok (LineInstr (mnem, List.rev acc))
        | s :: rest -> (
            match parse_operand s Register.B64 with
            | Error e -> Error (Printf.sprintf "In instruction '%s': %s" clean e)
            | Ok op -> parse_ops (op :: acc) rest)
      in
      parse_ops [] op_strings

let parse_lines text =
  let lines = String.split_on_char '\n' text in
  let rec loop line_no acc pending_bytes = function
    | [] -> Ok (List.rev acc)
    | l :: rest ->
        let clean = strip_comments l in
        let upper = String.uppercase_ascii clean in
        if String.starts_with ~prefix:".BYTE" upper
           || String.starts_with ~prefix:".ASCII" upper
           || String.starts_with ~prefix:".ASCIZ" upper
           || String.starts_with ~prefix:".STRING" upper then
          let str =
            if String.starts_with ~prefix:".BYTE" upper then
              let parts = split_tokens (String.sub clean 5 (String.length clean - 5)) ',' in
              let new_bytes =
                List.filter_map
                  (fun p ->
                    let p = String.trim p in
                    if String.starts_with ~prefix:"'" p && String.ends_with ~suffix:"'" p && String.length p = 3 then
                      Some (Char.uppercase_ascii p.[1])
                    else
                      try
                        let v = int_of_string p in
                        if v >= 32 && v <= 126 then Some (Char.uppercase_ascii (Char.chr v)) else None
                      with _ -> None)
                  parts
              in
              let total_chars = pending_bytes @ new_bytes in
              String.of_seq (List.to_seq total_chars)
            else upper
          in
          if contains_sub str "ASGARD_BEG_V" || contains_sub str "ASGARD_BEGIN_V" then
            loop (line_no + 1) (LineMarkerBegin (ModeVirtualize "region") :: acc) [] rest
          else if contains_sub str "ASGARD_BEG_M" || contains_sub str "ASGARD_BEGIN_M" then
            loop (line_no + 1) (LineMarkerBegin (ModeMutation "region") :: acc) [] rest
          else if contains_sub str "ASGARD_BEG" || contains_sub str "ASGARD_BEGIN" then
            loop (line_no + 1) (LineMarkerBegin (ModeUltra "region") :: acc) [] rest
          else if contains_sub str "ASGARD_END" then
            loop (line_no + 1) (LineMarkerEnd :: acc) [] rest
          else
            loop (line_no + 1) acc [] rest

        else
          match parse_line l with
          | Error e -> Error (Printf.sprintf "Line %d: %s" line_no e)
          | Ok parsed -> loop (line_no + 1) (parsed :: acc) [] rest
  in
  loop 1 [] [] lines

