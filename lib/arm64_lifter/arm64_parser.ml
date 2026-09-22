open Vm_ir
include Arm64_types
open Arm64_regs

let strip_comments line =
  let len = String.length line in
  let rec find_start i in_str =
    if i >= len then len
    else
      let c = line.[i] in
      if c = '"' then find_start (i + 1) (not in_str)
      else if not in_str && (c = ';' || (c = '/' && i + 1 < len && line.[i + 1] = '/')) then i
      else find_start (i + 1) in_str
  in
  String.trim (String.sub line 0 (find_start 0 false))

let parse_mem str width =
  let s = String.trim str in
  if not (String.starts_with ~prefix:"[" s) then
    Error (Printf.sprintf "Invalid memory operand '%s'" str)
  else
    let wb =
      if String.ends_with ~suffix:"]!" s then WbPre
      else WbNone
    in
    let end_idx =
      match String.index_opt s ']' with
      | Some i -> i
      | None -> String.length s
    in
    let inner = String.sub s 1 (end_idx - 1) |> String.trim in
    let parts = String.split_on_char ',' inner |> List.map String.trim |> List.filter (fun x -> x <> "") in
    match parts with
    | [ base_str ] ->
        (match map_arm64_reg base_str with
        | Ok b -> Ok { base = Some b; index = None; disp = 0L; width; wb }
        | Error err -> Error err)
    | [ base_str; disp_str ] ->
        (match map_arm64_reg base_str with
        | Error err -> Error err
        | Ok b ->
            (match map_arm64_reg disp_str with
            | Ok idx_reg -> Ok { base = Some b; index = Some (idx_reg, 1); disp = 0L; width; wb }
            | Error _ ->
                let d = match parse_imm disp_str with Ok i -> i | Error _ -> 0L in
                Ok { base = Some b; index = None; disp = d; width; wb }))
    | [ base_str; idx_str; shift_str ] ->
        (match map_arm64_reg base_str, map_arm64_reg idx_str with
        | Ok b, Ok idx_reg ->
            let scale =
              if String.contains shift_str '#' then
                let sh_parts = String.split_on_char '#' shift_str in
                match List.rev sh_parts with
                | sh :: _ ->
                    (match int_of_string_opt (String.trim sh) with
                    | Some 1 -> 2
                    | Some 2 -> 4
                    | Some 3 -> 8
                    | _ -> 1)
                | _ -> 1
              else 1
            in
            Ok { base = Some b; index = Some (idx_reg, scale); disp = 0L; width; wb }
        | _ -> Ok { base = Some (Register.Gpr (Register.RSP, Register.B64)); index = None; disp = 0L; width; wb })
    | _ -> Ok { base = Some (Register.Gpr (Register.RSP, Register.B64)); index = None; disp = 0L; width; wb }

let parse_operand str default_width =
  let s = String.trim str in
  let s_low = String.lowercase_ascii s in
  if s_low = "xzr" || s_low = "wzr" then Ok (OpImm 0L)
  else if String.starts_with ~prefix:"[" s then
    match parse_mem s default_width with
    | Ok m -> Ok (OpMem m)
    | Error err -> Error err
  else if String.starts_with ~prefix:"#" s then
    match parse_imm s with
    | Ok i -> Ok (OpImm i)
    | Error _ -> Ok (OpLabel s)
  else
    match map_arm64_reg s with
    | Ok r -> Ok (OpReg r)
    | Error _ ->
        if String.contains s '@' || String.starts_with ~prefix:"_" s ||
           String.starts_with ~prefix:"L" s || String.starts_with ~prefix:"." s then
          Ok (OpLabel s)
        else
          match parse_imm s with
          | Ok i -> Ok (OpImm i)
          | Error _ -> Ok (OpLabel s)

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
      | Some i ->
          (match String.index_opt line ' ' with
          | Some j -> min i j
          | None -> i)
      | None ->
          match String.index_opt line ' ' with
          | Some j -> j
          | None -> String.length line
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
        let rec scan i start in_bracket acc =
          if i >= len then
            let piece = String.trim (String.sub args_str start (len - start)) in
            List.rev (if piece = "" then acc else piece :: acc)
          else
            match args_str.[i] with
            | '[' -> scan (i + 1) start true acc
            | ']' -> scan (i + 1) start false acc
            | ',' when not in_bracket ->
                let piece = String.trim (String.sub args_str start (i - start)) in
                let acc' = if piece = "" then acc else piece :: acc in
                scan (i + 1) (i + 1) false acc'
            | _ -> scan (i + 1) start in_bracket acc
        in
        scan 0 0 false []
      in

      let def_width =
        if String.ends_with ~suffix:"b" mnemonic || mnemonic = "ldrsb" then Register.B8
        else if String.ends_with ~suffix:"h" mnemonic || mnemonic = "ldrsh" then Register.B16
        else if String.starts_with ~prefix:"w" args_str then Register.B32
        else Register.B64
      in

      let normalize_post_index ops =
        match ops with
        | [OpReg r; OpMem m; OpImm disp] ->
            [OpReg r; OpMem { m with wb = WbPost disp }]
        | [OpReg r1; OpReg r2; OpMem m; OpImm disp] ->
            [OpReg r1; OpReg r2; OpMem { m with wb = WbPost disp }]
        | other -> other
      in
      let rec parse_all acc = function
        | [] -> Ok (LineInstr (mnemonic, normalize_post_index (List.rev acc)))
        | a :: rest ->
            match parse_operand a def_width with
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
              | LineInstr ("b", _) :: prev -> prev
              | _ -> acc
            in
            loop (LineMarkerBegin (ModeVirtualize "region") :: acc') rest
          else if contains_sub upper "ASGARD_BEG_M" || contains_sub upper "ASGARD_BEGIN_M" then
            let acc' = match acc with
              | LineInstr ("b", _) :: prev -> prev
              | _ -> acc
            in
            loop (LineMarkerBegin (ModeMutation "region") :: acc') rest
          else if contains_sub upper "ASGARD_BEG" || contains_sub upper "ASGARD_BEGIN" then
            let acc' = match acc with
              | LineInstr ("b", _) :: prev -> prev
              | _ -> acc
            in
            loop (LineMarkerBegin (ModeUltra "region") :: acc') rest
          else if contains_sub upper "ASGARD_END" then
            let acc' = match acc with
              | LineInstr ("b", _) :: prev -> prev
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
              match String.index_opt trimmed '"' with
              | Some q1 ->
                  (match String.rindex_opt trimmed '"' with
                  | Some q2 when q2 > q1 ->
                      let raw_str = String.sub trimmed (q1 + 1) (q2 - q1 - 1) in
                      let unescaped = unescape_asm_str raw_str in
                      let data = if is_asciz then unescaped ^ "\000" else unescaped in
                      constants := (lbl, data) :: !constants;
                      cur_label := None
                  | _ -> ())
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
