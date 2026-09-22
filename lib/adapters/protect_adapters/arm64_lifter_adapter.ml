open Random_visa_ports
open Protect_ports
open Vm_ir

let arch_name = "arm64"
let target_arch = Arm64

let lift_source (text : string) : (Ir.func * (string * string) list, error) result =
  let constants = Arm64_lifter.Arm64_parser.extract_constants text in
  let raw_lines =
    match Arm64_lifter.Arm64_parser.parse_lines text with
    | Ok lines -> lines
    | Error _ -> []
  in
  let regions =
    if raw_lines <> [] then Arm64_lifter.extract_marked_regions ~require_markers:true raw_lines
    else []
  in
  let lift_res =
    if regions <> [] then
      let (_mode, rlines) = List.hd regions in
      Arm64_lifter.lift_lines rlines
    else
      Arm64_lifter.lift_function text
  in
  match lift_res with
  | Ok f -> Ok (f, constants)
  | Error err -> Error err
