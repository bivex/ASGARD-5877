open Vm_ir

type writeback =
  | WbNone
  | WbPre
  | WbPost of int64

type raw_mem = {
  base : Register.t option;
  index : (Register.t * int) option;
  disp : int64;
  width : Register.width;
  wb : writeback;
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
  | ModeVirtualize s -> "VIRTUALIZE(" ^ s ^ ")"
  | ModeMutation s -> "MUTATION(" ^ s ^ ")"
  | ModeUltra s -> "ULTRA(" ^ s ^ ")"

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

let map_arm64_reg str =
  let s = String.lowercase_ascii (String.trim str) in
  match s with
  (* 64-bit general purpose registers *)
  | "x0"  | "r0"  -> Ok (Register.Gpr (Register.RAX, Register.B64))
  | "x1"  | "r1"  -> Ok (Register.Gpr (Register.RCX, Register.B64))
  | "x2"  | "r2"  -> Ok (Register.Gpr (Register.RDX, Register.B64))
  | "x3"  | "r3"  -> Ok (Register.Gpr (Register.RBX, Register.B64))
  | "x4"  | "r4"  -> Ok (Register.Gpr (Register.RSI, Register.B64))
  | "x5"  | "r5"  -> Ok (Register.Gpr (Register.RDI, Register.B64))
  | "x6"  | "r6"  -> Ok (Register.Gpr (Register.R8,  Register.B64))
  | "x7"  | "r7"  -> Ok (Register.Gpr (Register.R9,  Register.B64))
  | "x8"  | "r8"  -> Ok (Register.Gpr (Register.R10, Register.B64))
  | "x9"  | "r9"  -> Ok (Register.Gpr (Register.R11, Register.B64))
  | "x10" | "r10" -> Ok (Register.Gpr (Register.R12, Register.B64))
  | "x11" | "r11" -> Ok (Register.Gpr (Register.R13, Register.B64))
  | "x12" | "r12" -> Ok (Register.Gpr (Register.R14, Register.B64))
  | "x13" | "r13" -> Ok (Register.Gpr (Register.R15, Register.B64))
  | "x14" -> Ok (Register.Vreg (Register.VTMP0, Register.B64))
  | "x15" -> Ok (Register.Vreg (Register.VTMP1, Register.B64))
  | "x16" | "x17" -> Ok (Register.Vreg (Register.VTMP2, Register.B64))
  | "x18" -> Ok (Register.Vreg (Register.VX18, Register.B64))
  | "x19" -> Ok (Register.Vreg (Register.VX19, Register.B64))
  | "x20" -> Ok (Register.Vreg (Register.VX20, Register.B64))
  | "x21" -> Ok (Register.Vreg (Register.VX21, Register.B64))
  | "x22" -> Ok (Register.Vreg (Register.VX22, Register.B64))
  | "x23" -> Ok (Register.Vreg (Register.VX23, Register.B64))
  | "x24" -> Ok (Register.Vreg (Register.VX24, Register.B64))
  | "x25" -> Ok (Register.Vreg (Register.VX25, Register.B64))
  | "x26" | "x27" | "x28" -> Ok (Register.Vreg (Register.VX26, Register.B64))
  | "x29" | "fp"  -> Ok (Register.Gpr (Register.RBP, Register.B64))
  | "x30" | "lr"  -> Ok (Register.Vreg (Register.VTMP3, Register.B64))
  | "sp"  | "wsp" -> Ok (Register.Gpr (Register.RSP, Register.B64))
  | "xzr"         -> Ok (Register.Vreg (Register.VZERO, Register.B64))
  
  (* 32-bit registers *)
  | "w0"  -> Ok (Register.Gpr (Register.RAX, Register.B32))
  | "w1"  -> Ok (Register.Gpr (Register.RCX, Register.B32))
  | "w2"  -> Ok (Register.Gpr (Register.RDX, Register.B32))
  | "w3"  -> Ok (Register.Gpr (Register.RBX, Register.B32))
  | "w4"  -> Ok (Register.Gpr (Register.RSI, Register.B32))
  | "w5"  -> Ok (Register.Gpr (Register.RDI, Register.B32))
  | "w6"  -> Ok (Register.Gpr (Register.R8,  Register.B32))
  | "w7"  -> Ok (Register.Gpr (Register.R9,  Register.B32))
  | "w8"  -> Ok (Register.Gpr (Register.R10, Register.B32))
  | "w9"  -> Ok (Register.Gpr (Register.R11, Register.B32))
  | "w10" -> Ok (Register.Gpr (Register.R12, Register.B32))
  | "w11" -> Ok (Register.Gpr (Register.R13, Register.B32))
  | "w12" -> Ok (Register.Gpr (Register.R14, Register.B32))
  | "w13" -> Ok (Register.Gpr (Register.R15, Register.B32))
  | "w14" -> Ok (Register.Vreg (Register.VTMP0, Register.B32))
  | "w15" -> Ok (Register.Vreg (Register.VTMP1, Register.B32))
  | "w16" | "w17" -> Ok (Register.Vreg (Register.VTMP2, Register.B32))
  | "w18" -> Ok (Register.Vreg (Register.VX18, Register.B32))
  | "w19" -> Ok (Register.Vreg (Register.VX19, Register.B32))
  | "w20" -> Ok (Register.Vreg (Register.VX20, Register.B32))
  | "w21" -> Ok (Register.Vreg (Register.VX21, Register.B32))
  | "w22" -> Ok (Register.Vreg (Register.VX22, Register.B32))
  | "w23" -> Ok (Register.Vreg (Register.VX23, Register.B32))
  | "w24" -> Ok (Register.Vreg (Register.VX24, Register.B32))
  | "w25" -> Ok (Register.Vreg (Register.VX25, Register.B32))
  | "w26" | "w27" | "w28" -> Ok (Register.Vreg (Register.VX26, Register.B32))
  | "w29" -> Ok (Register.Gpr (Register.RBP, Register.B32))
  | "w30" -> Ok (Register.Vreg (Register.VTMP3, Register.B32))
  | "wzr" -> Ok (Register.Vreg (Register.VZERO, Register.B32))
  | s when String.length s >= 2 && s.[0] = 'd' -> (
      match int_of_string_opt (String.sub s 1 (String.length s - 1)) with
      | Some i when i >= 0 && i < 32 -> Ok (Register.Fpr (i, Register.B64))
      | _ -> Error (Printf.sprintf "Unknown ARM64 register '%s'" str))
  | s when String.length s >= 2 && s.[0] = 's' && s <> "sp" && s <> "si" -> (
      match int_of_string_opt (String.sub s 1 (String.length s - 1)) with
      | Some i when i >= 0 && i < 32 -> Ok (Register.Fpr (i, Register.B32))
      | _ -> Error (Printf.sprintf "Unknown ARM64 register '%s'" str))
  | _ -> Error (Printf.sprintf "Unknown ARM64 register '%s'" str)

let parse_imm str =
  let s = String.trim str in
  let s = if String.starts_with ~prefix:"#" s then String.sub s 1 (String.length s - 1) else s in
  if String.contains s '@' || String.starts_with ~prefix:"_" s ||
     String.starts_with ~prefix:"L" s || String.starts_with ~prefix:"." s then
    Error (Printf.sprintf "Not an immediate: %s" s)
  else
    try
      if String.starts_with ~prefix:"0x" (String.lowercase_ascii s) ||
         String.starts_with ~prefix:"-0x" (String.lowercase_ascii s) then
        Ok (Int64.of_string s)
      else
        Ok (Int64.of_string s)
    with _ -> Error (Printf.sprintf "Invalid immediate '%s'" str)

let parse_mem str width =
  let s = String.trim str in
  let is_pre_wb = String.ends_with ~suffix:"!" s in
  let s = if is_pre_wb then String.trim (String.sub s 0 (String.length s - 1)) else s in
  let wb = if is_pre_wb then WbPre else WbNone in
  let len = String.length s in
  if not (String.starts_with ~prefix:"[" s) then
    Error (Printf.sprintf "Not memory operand: %s" str)
  else
    let end_idx = match String.index_opt s ']' with
      | Some idx -> idx
      | None -> len - 1
    in
    let inner = String.trim (String.sub s 1 (end_idx - 1)) in
    let parts = String.split_on_char ',' inner |> List.map String.trim in
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
      let rec group_brackets acc in_bracket cur = function
        | [] -> List.rev (if cur = "" then acc else String.trim cur :: acc)
        | ',' :: rest when not in_bracket ->
            group_brackets (String.trim cur :: acc) false "" rest
        | '[' :: rest ->
            group_brackets acc true (cur ^ "[") rest
        | ']' :: rest ->
            group_brackets acc false (cur ^ "]") rest
        | c :: rest ->
            group_brackets acc in_bracket (cur ^ String.make 1 c) rest
      in
      let chars = List.init (String.length args_str) (String.get args_str) in
      let raw_args = group_brackets [] false "" chars |> List.filter (fun s -> s <> "") in

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
      let rec check i =
        if i + nlen > hlen then false
        else if String.sub haystack i nlen = needle then true
        else check (i + 1)
      in
      check 0
  in
  let rec loop acc = function
    | [] -> Ok (List.rev acc)
    | l :: rest ->
        let clean = strip_comments l in
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

