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
  | "x29" | "fp"  -> Ok (Register.Gpr (Register.RBP, Register.B64))
  | "x30" | "lr"  -> Ok (Register.Vreg (Register.VTMP3, Register.B64))
  | "sp"          -> Ok (Register.Gpr (Register.RSP, Register.B64))
  | "xzr"         -> Ok (Register.Vreg (Register.VTMP0, Register.B64))
  
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
  | "wzr" -> Ok (Register.Vreg (Register.VTMP0, Register.B32))
  | _ -> Error (Printf.sprintf "Unknown ARM64 register '%s'" str)

let parse_imm str =
  let s = String.trim str in
  let s = if String.starts_with ~prefix:"#" s then String.sub s 1 (String.length s - 1) else s in
  try
    if String.starts_with ~prefix:"0x" (String.lowercase_ascii s) ||
       String.starts_with ~prefix:"-0x" (String.lowercase_ascii s) then
      Ok (Int64.of_string s)
    else
      Ok (Int64.of_string s)
  with _ -> Error (Printf.sprintf "Invalid immediate '%s'" str)

let parse_mem str =
  let s = String.trim str in
  let len = String.length s in
  if not (String.starts_with ~prefix:"[" s) then
    Error (Printf.sprintf "Not memory operand: %s" str)
  else
    (* Strip '[' and ']' or trailing '!' *)
    let end_idx = match String.index_opt s ']' with
      | Some idx -> idx
      | None -> len - 1
    in
    let inner = String.trim (String.sub s 1 (end_idx - 1)) in
    let parts = String.split_on_char ',' inner |> List.map String.trim in
    match parts with
    | [ base_str ] ->
        (match map_arm64_reg base_str with
        | Ok b -> Ok { base = Some b; index = None; disp = 0L; width = Register.B64 }
        | Error err -> Error err)
    | [ base_str; disp_str ] ->
        (match map_arm64_reg base_str with
        | Error err -> Error err
        | Ok b ->
            (match parse_imm disp_str with
            | Ok d -> Ok { base = Some b; index = None; disp = d; width = Register.B64 }
            | Error _ ->
                (match map_arm64_reg disp_str with
                | Ok idx_reg -> Ok { base = Some b; index = Some (idx_reg, 1); disp = 0L; width = Register.B64 }
                | Error err -> Error err)))
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
            Ok { base = Some b; index = Some (idx_reg, scale); disp = 0L; width = Register.B64 }
        | _ -> Error (Printf.sprintf "Invalid 3-operand memory syntax: %s" str))
    | _ -> Error (Printf.sprintf "Invalid ARM64 memory syntax '%s'" str)

let parse_operand str =
  let s = String.trim str in
  if String.starts_with ~prefix:"[" s then
    match parse_mem s with
    | Ok m -> Ok (OpMem m)
    | Error err -> Error err
  else if String.starts_with ~prefix:"#" s then
    match parse_imm s with
    | Ok i -> Ok (OpImm i)
    | Error err -> Error err
  else
    match map_arm64_reg s with
    | Ok r -> Ok (OpReg r)
    | Error _ ->
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
    (* Instruction *)
    let first_space =
      match String.index_opt line ' ' with
      | Some i -> i
      | None ->
          match String.index_opt line '\t' with
          | Some i -> i
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
      let raw_args = String.split_on_char ',' args_str |> List.map String.trim |> List.filter (fun s -> s <> "") in
      let rec parse_all acc = function
        | [] -> Ok (LineInstr (mnemonic, List.rev acc))
        | a :: rest ->
            match parse_operand a with
            | Ok op -> parse_all (op :: acc) rest
            | Error err -> Error err
      in
      parse_all [] raw_args

let parse_lines text =
  let lines = String.split_on_char '\n' text in
  let rec loop acc = function
    | [] -> Ok (List.rev acc)
    | l :: rest ->
        match parse_line l with
        | Ok res -> loop (res :: acc) rest
        | Error err -> Error err
  in
  loop [] lines
