open Random_visa_ports
open Protect_ports

let arch_name = "riscv64"
let target_arch = Riscv64

let lift_source (text : string) : (ir_func * (string * string) list, error) result =
  let constants = Riscv_lifter.Riscv_parser.extract_constants text in
  let raw_lines =
    match Riscv_lifter.Riscv_parser.parse_lines text with
    | Ok lines -> lines
    | Error _ -> []
  in
  let regions =
    if raw_lines <> [] then Riscv_lifter.extract_marked_regions ~require_markers:true raw_lines
    else []
  in
  let lift_res =
    if regions <> [] then
      let (_mode, rlines) = List.hd regions in
      Riscv_lifter.lift_lines rlines
    else
      Riscv_lifter.lift_function text
  in
  match lift_res with
  | Ok f -> Ok (wrap_ir f, constants)
  | Error err -> Error err
