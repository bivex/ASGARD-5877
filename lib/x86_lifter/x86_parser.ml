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

type raw_line =
  | LineLabel of string
  | LineInstr of string * raw_op list
  | LineDirective of string
  | LineEmpty

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
    (* Tokenize by + and - *)
    let tokens = ref [] in
    let buf = Buffer.create 16 in
    let current_sign = ref 1L in
    let push_token () =
      if Buffer.length buf > 0 then begin
        tokens := (!current_sign, Buffer.contents buf) :: !tokens;
        Buffer.clear buf
      end
    in
    for i = 0 to String.length inner - 1 do
      let c = inner.[i] in
      if c = '+' then begin
        push_token ();
        current_sign := 1L
      end else if c = '-' then begin
        push_token ();
        current_sign := -1L
      end else if c <> ' ' && c <> '\t' then
        Buffer.add_char buf c
    done;
    push_token ();
    let token_list = List.rev !tokens in

    let base = ref None in
    let index = ref None in
    let disp = ref 0L in
    let err = ref None in

    List.iter
      (fun (sign, tok) ->
        if Option.is_some !err then ()
        else
          (* Check if it's an immediate/disp *)
          match Int64.of_string_opt tok with
          | Some imm ->
              disp := Int64.add !disp (Int64.mul sign imm)
          | None -> (
              (* Check if index with scale: reg*scale or scale*reg *)
              if String.contains tok '*' then
                let parts = split_tokens tok '*' in
                match parts with
                | [ p1; p2 ] -> (
                    match Int64.of_string_opt p1, Register.of_string p2 with
                    | Some scale, Ok reg ->
                        index := Some (reg, Int64.to_int scale)
                    | _, _ -> (
                        match Register.of_string p1, Int64.of_string_opt p2 with
                        | Ok reg, Some scale ->
                            index := Some (reg, Int64.to_int scale)
                        | _, _ -> err := Some (Printf.sprintf "Invalid scaled index in '%s'" tok)))
                | _ -> err := Some (Printf.sprintf "Invalid scaled index in '%s'" tok)
              else
                (* Plain register: if base is free, set base; else set index with scale 1 *)
                match Register.of_string tok with
                | Ok reg ->
                    if Option.is_none !base then base := Some reg
                    else if Option.is_none !index then index := Some (reg, 1)
                    else err := Some (Printf.sprintf "Multiple index registers in '%s'" inner)
                | Error e -> err := Some e))
      token_list;

    match !err with
    | Some e -> Error e
    | None -> Ok { base = !base; index = !index; disp = !disp; width = default_width }

let parse_operand str default_width =
  let s = String.trim str in
  let width, stripped = parse_width_prefix s in
  let effective_width = if s <> stripped then width else default_width in
  if String.starts_with ~prefix:"[" stripped && String.ends_with ~suffix:"]" stripped then
    match parse_mem_operand stripped effective_width with
    | Ok mem -> Ok (OpMem mem)
    | Error e -> Error e
  else
    match Register.of_string stripped with
    | Ok reg -> Ok (OpReg reg)
    | Error _ -> (
        match Int64.of_string_opt stripped with
        | Some imm -> Ok (OpImm imm)
        | None ->
            (* Treat as symbolic label *)
            Ok (OpLabel (String.lowercase_ascii stripped)))

let parse_line line =
  let clean = strip_comments line in
  if clean = "" then Ok LineEmpty
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
      (* 0-operand instruction: e.g. ret, nop, vm_enter *)
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
  let rec loop line_no acc = function
    | [] -> Ok (List.rev acc)
    | l :: rest -> (
        match parse_line l with
        | Error e -> Error (Printf.sprintf "Line %d: %s" line_no e)
        | Ok parsed -> loop (line_no + 1) (parsed :: acc) rest)
  in
  loop 1 [] lines
