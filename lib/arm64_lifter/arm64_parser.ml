open Vm_ir
include Arm64_types
open Arm64_regs

let strip_comments line =
  let len = String.length line in
  let rec find_start i in_str =
    if i >= len then len
    else
      let c = line.[i] in
      if in_str && c = '\\' && i + 1 < len then
        find_start (i + 2) in_str
      else if c = '"' then find_start (i + 1) (not in_str)
      else if not in_str && (c = ';' || (c = '/' && i + 1 < len && line.[i + 1] = '/')) then i
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
        | Ok b -> Ok { base = Some b; index = None; disp = 0L; symbol = None; width; wb }
        | Error err -> Error err)
    | [ base_str; disp_str ] ->
        (match map_arm64_reg base_str with
        | Error err -> Error err
        | Ok b ->
            (match map_arm64_reg disp_str with
            | Ok idx_reg -> Ok { base = Some b; index = Some (idx_reg, 1); disp = 0L; symbol = None; width; wb }
            | Error _ ->
                let sym_opt =
                  if String.contains disp_str '@' || String.starts_with ~prefix:"_" disp_str then
                    Some disp_str
                  else None
                in
                let d = match parse_imm disp_str with Ok i -> i | Error _ -> 0L in
                Ok { base = Some b; index = None; disp = d; symbol = sym_opt; width; wb }))
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
            Ok { base = Some b; index = Some (idx_reg, scale); disp = 0L; symbol = None; width; wb }
        | _ -> Ok { base = Some (Register.Gpr (Register.RSP, Register.B64)); index = None; disp = 0L; symbol = None; width; wb })
    | _ -> Ok { base = Some (Register.Gpr (Register.RSP, Register.B64)); index = None; disp = 0L; symbol = None; width; wb }

let parse_vec_operand str =
  let s = String.trim str in
  let s =
    if String.starts_with ~prefix:"{" s && String.ends_with ~suffix:"}" s then
      String.trim (String.sub s 1 (String.length s - 2))
    else s
  in
  let s_low = String.lowercase_ascii s in
  if String.length s_low >= 2 && s_low.[0] = 'v' then
    let (reg_part, suffix_part, direct_bracket) =
      match String.index_opt s_low '[' with
      | Some b_open when not (String.contains s_low '.') ->
          let r = String.sub s_low 0 b_open in
          let rest = String.sub s_low (b_open + 1) (String.length s_low - b_open - 1) in
          let idx = match String.index_opt rest ']' with
            | Some b_close -> int_of_string_opt (String.trim (String.sub rest 0 b_close))
            | None -> None
          in
          (r, None, idx)
      | _ ->
          match String.index_opt s_low '.' with
          | Some dot ->
              let r = String.sub s_low 0 dot in
              let suf = String.sub s_low (dot + 1) (String.length s_low - dot - 1) in
              (r, Some suf, None)
          | None -> (s_low, None, None)
    in
    match int_of_string_opt (String.sub reg_part 1 (String.length reg_part - 1)) with
    | Some reg when reg >= 0 && reg < 32 -> (
        match direct_bracket with
        | Some idx ->
            Some (OpVec { reg; bits = 128; lane_bits = 64; lane_idx = Some idx })
        | None ->
            match suffix_part with
            | None -> Some (OpVec { reg; bits = 128; lane_bits = 64; lane_idx = None })
            | Some suf ->
            let (arr, lane_idx) =
              match String.index_opt suf '[' with
              | Some b_open ->
                  let arr = String.sub suf 0 b_open in
                  let rest = String.sub suf (b_open + 1) (String.length suf - b_open - 1) in
                  let idx = match String.index_opt rest ']' with
                    | Some b_close -> int_of_string_opt (String.trim (String.sub rest 0 b_close))
                    | None -> None
                  in
                  (arr, idx)
              | None -> (suf, None)
            in
            let (bits, lane_bits) =
              match arr with
              | "16b" -> (128, 8)
              | "8b"  -> (64, 8)
              | "8h"  -> (128, 16)
              | "4h"  -> (64, 16)
              | "4s"  -> (128, 32)
              | "2s"  -> (64, 32)
              | "2d"  -> (128, 64)
              | "1d" | "d" -> (64, 64)
              | "s"   -> (32, 32)
              | "h"   -> (16, 16)
              | "b"   -> (8, 8)
              | "q"   -> (128, 128)
              | _ -> (128, 64)
            in
            Some (OpVec { reg; bits; lane_bits; lane_idx }))
    | _ -> None
  else if String.length s_low >= 2 && s_low.[0] = 'q' then
    match int_of_string_opt (String.sub s_low 1 (String.length s_low - 1)) with
    | Some reg when reg >= 0 && reg < 32 ->
        Some (OpVec { reg; bits = 128; lane_bits = 64; lane_idx = None })
    | _ -> None
  else None

let parse_operand str default_width =
  let s = String.trim str in
  match parse_vec_operand s with
  | Some op -> Ok op
  | None ->
      if String.starts_with ~prefix:"[" s then
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

      let args_str_low = String.lowercase_ascii args_str in
      let def_width =
        if String.ends_with ~suffix:"b" mnemonic || mnemonic = "ldrsb" || mnemonic = "ldursb" then Register.B8
        else if String.ends_with ~suffix:"h" mnemonic || mnemonic = "ldrsh" || mnemonic = "ldursh" then Register.B16
        else if mnemonic = "ldrsw" || mnemonic = "ldursw" || mnemonic = "ldtrsw" then Register.B32
        else if String.starts_with ~prefix:"w" args_str_low then Register.B32
        else Register.B64
      in

      let normalize_post_index ops =
        match ops with
        | [(OpReg _ | OpVec _) as r; OpMem m; OpImm disp] ->
            [r; OpMem { m with wb = WbPost disp }]
        | [OpReg r1; OpReg r2; OpMem m; OpImm disp] ->
            [OpReg r1; OpReg r2; OpMem { m with wb = WbPost disp }]
        | other -> other
      in
      let split_shift_spec a =
        let s = String.trim a in
        let s_low = String.lowercase_ascii s in
        if String.starts_with ~prefix:"lsl" s_low ||
           String.starts_with ~prefix:"lsr" s_low ||
           String.starts_with ~prefix:"asr" s_low ||
           String.starts_with ~prefix:"ror" s_low then
          let sh = String.sub s_low 0 3 in
          let rest = String.trim (String.sub s 3 (String.length s - 3)) in
          let imm_str = if String.starts_with ~prefix:"#" rest then String.sub rest 1 (String.length rest - 1) else rest in
          match Int64.of_string_opt (String.trim imm_str) with
          | Some shift -> Some (sh, shift)
          | None -> None
        else None
      in
      let rec parse_all acc = function
        | [] -> Ok (LineInstr (mnemonic, normalize_post_index (List.rev acc)))
        | a :: rest ->
            match split_shift_spec a with
            | Some (sh, shift) ->
                parse_all (OpImm shift :: OpLabel sh :: acc) rest
            | None ->
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
  let cur_buf = Buffer.create 256 in

  let commit_current () =
    match !cur_label with
    | Some lbl when Buffer.length cur_buf > 0 ->
        if not (String.starts_with ~prefix:"ASGARD_BEG" lbl ||
                String.starts_with ~prefix:"ASGARD_END" lbl) then
          constants := (lbl, Buffer.contents cur_buf) :: !constants;
        Buffer.clear cur_buf;
        cur_label := None
    | _ ->
        Buffer.clear cur_buf;
        cur_label := None
  in

  let parse_asm_int s =
    let clean = String.trim s in
    try Int64.of_string clean
    with _ -> 0L
  in

  List.iter
    (fun l ->
      let clean = strip_comments l in
      let trimmed = String.trim clean in
      if String.ends_with ~suffix:":" clean then (
        commit_current ();
        let lbl = String.trim (String.sub clean 0 (String.length clean - 1)) in
        cur_label := Some lbl
      ) else if String.starts_with ~prefix:".section" trimmed ||
                String.starts_with ~prefix:".text" trimmed ||
                String.starts_with ~prefix:".data" trimmed ||
                String.starts_with ~prefix:".globl" trimmed ||
                String.starts_with ~prefix:".global" trimmed ||
                String.starts_with ~prefix:".cfi_" trimmed then (
        commit_current ()
      ) else (
        match !cur_label with
        | None -> ()
        | Some _lbl ->
            if String.starts_with ~prefix:".ascii" trimmed ||
               String.starts_with ~prefix:".asciz" trimmed ||
               String.starts_with ~prefix:".string" trimmed then (
              let is_asciz = String.starts_with ~prefix:".asciz" trimmed ||
                             String.starts_with ~prefix:".string" trimmed in
              match find_string_bounds trimmed with
              | Some (q1, q2) ->
                  let raw_str = String.sub trimmed (q1 + 1) (q2 - q1 - 1) in
                  let unescaped = unescape_asm_str raw_str in
                  if String.starts_with ~prefix:"ASGARD_BEG" unescaped ||
                     String.starts_with ~prefix:"ASGARD_END" unescaped then (
                    Buffer.clear cur_buf;
                    cur_label := None
                  ) else (
                    Buffer.add_string cur_buf unescaped;
                    if is_asciz then Buffer.add_char cur_buf '\000'
                  )
              | None -> ()
            ) else if String.starts_with ~prefix:".byte" trimmed then (
              let rest = String.sub trimmed 5 (String.length trimmed - 5) in
              let parts = String.split_on_char ',' rest |> List.map String.trim in
              List.iter
                (fun p ->
                  let v = parse_asm_int p in
                  Buffer.add_char cur_buf (Char.chr (Int64.to_int (Int64.logand v 0xFFL))))
                parts
            ) else if String.starts_with ~prefix:".short" trimmed ||
                      String.starts_with ~prefix:".hword" trimmed ||
                      String.starts_with ~prefix:".2byte" trimmed then (
              let kw_len = 6 in
              let rest = String.sub trimmed kw_len (String.length trimmed - kw_len) in
              let parts = String.split_on_char ',' rest |> List.map String.trim in
              List.iter
                (fun p ->
                  let v = parse_asm_int p in
                  for i = 0 to 1 do
                    let b = Int64.to_int (Int64.logand (Int64.shift_right_logical v (i * 8)) 0xFFL) in
                    Buffer.add_char cur_buf (Char.chr b)
                  done)
                parts
            ) else if String.starts_with ~prefix:".long" trimmed ||
                      String.starts_with ~prefix:".word" trimmed ||
                      String.starts_with ~prefix:".4byte" trimmed then (
              let kw_len = 5 in
              let rest = String.sub trimmed kw_len (String.length trimmed - kw_len) in
              let parts = String.split_on_char ',' rest |> List.map String.trim in
              List.iter
                (fun p ->
                  let v = parse_asm_int p in
                  for i = 0 to 3 do
                    let b = Int64.to_int (Int64.logand (Int64.shift_right_logical v (i * 8)) 0xFFL) in
                    Buffer.add_char cur_buf (Char.chr b)
                  done)
                parts
            ) else if String.starts_with ~prefix:".quad" trimmed ||
                      String.starts_with ~prefix:".8byte" trimmed ||
                      String.starts_with ~prefix:".xword" trimmed then (
              let kw_len = if String.starts_with ~prefix:".8byte" trimmed then 6 else 5 in
              let rest = String.sub trimmed kw_len (String.length trimmed - kw_len) in
              let parts = String.split_on_char ',' rest |> List.map String.trim in
              List.iter
                (fun p ->
                  let v = parse_asm_int p in
                  for i = 0 to 7 do
                    let b = Int64.to_int (Int64.logand (Int64.shift_right_logical v (i * 8)) 0xFFL) in
                    Buffer.add_char cur_buf (Char.chr b)
                  done)
                parts
            ) else if String.starts_with ~prefix:".zero" trimmed ||
                      String.starts_with ~prefix:".space" trimmed ||
                      String.starts_with ~prefix:".skip" trimmed then (
              let kw_len = 5 in
              let rest = String.sub trimmed kw_len (String.length trimmed - kw_len) in
              let parts = String.split_on_char ',' rest |> List.map String.trim in
              let count = match parts with c :: _ -> (try int_of_string c with _ -> 0) | [] -> 0 in
              let fill = match parts with _ :: f :: _ -> (try int_of_string f land 0xFF with _ -> 0) | _ -> 0 in
              for _ = 1 to count do
                Buffer.add_char cur_buf (Char.chr fill)
              done
            ) else if String.starts_with ~prefix:"." trimmed &&
                      (String.starts_with ~prefix:".p2align" trimmed || String.starts_with ~prefix:".align" trimmed) then (
              ()
            ) else if trimmed <> "" && not (String.starts_with ~prefix:"." trimmed) then (
              commit_current ()
            )
      ))
    lines;
  commit_current ();
  List.rev !constants
