open Random_visa_ports
open Protect_ports

let arch_name = "riscv64"
let target_arch = Riscv64

let extract_fn_name rlines =
  match rlines with
  | Riscv_lifter.Riscv_parser.LineLabel lbl :: _ ->
      if String.starts_with ~prefix:"_" lbl then String.sub lbl 1 (String.length lbl - 1)
      else lbl
  | _ -> "target_func"

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
      let lifted_regions =
        List.filter_map
          (fun (_mode, rlines) ->
            let fn_name = extract_fn_name rlines in
            match Riscv_lifter.lift_lines ~options:{ Riscv_lifter.function_name = fn_name } rlines with
            | Ok f -> Some (fn_name, f)
            | Error _ -> None)
          regions
      in
      match lifted_regions with
      | [] ->
          (match Riscv_lifter.lift_function text with
          | Ok f -> Ok (wrap_ir f)
          | Error err -> Error err)
      | [ (_name, f) ] ->
          Ok (wrap_ir f)
      | multi ->
          Ok (wrap_multi_ir multi)
    else
      match Riscv_lifter.lift_function text with
      | Ok f -> Ok (wrap_ir f)
      | Error err -> Error err
  in
  match lift_res with
  | Ok ir -> Ok (ir, constants)
  | Error err -> Error err
