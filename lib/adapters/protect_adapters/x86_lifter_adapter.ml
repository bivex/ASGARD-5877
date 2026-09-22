open Random_visa_ports
open Protect_ports

let arch_name = "x86_64"
let target_arch = X86_64

let lift_source (text : string) : (ir_func * (string * string) list, error) result =
  let raw_lines =
    match X86_lifter.X86_parser.parse_lines text with
    | Ok lines -> lines
    | Error _ -> []
  in
  let has_markers =
    raw_lines <> [] && X86_lifter.Lifter.extract_marked_regions ~require_markers:true raw_lines <> []
  in
  let regions =
    if raw_lines <> [] then X86_lifter.Lifter.extract_marked_regions raw_lines
    else []
  in
  let lift_res =
    if has_markers && regions <> [] then
      let (_mode, rlines) = List.hd regions in
      X86_lifter.Lifter.lift_lines rlines
    else
      X86_lifter.Lifter.lift_function text
  in
  match lift_res with
  | Ok f -> Ok (wrap_ir f, [])
  | Error err -> Error err
