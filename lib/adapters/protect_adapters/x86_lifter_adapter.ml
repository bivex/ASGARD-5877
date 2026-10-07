open Random_visa_ports
open Protect_ports

let arch_name = "x86_64"
let target_arch = X86_64

let extract_fn_name rlines =
  match rlines with
  | X86_lifter.X86_parser.LineLabel lbl :: _ ->
      if String.starts_with ~prefix:"_" lbl then String.sub lbl 1 (String.length lbl - 1)
      else lbl
  | _ -> "target_func"

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
      let lifted_regions =
        List.filter_map
          (fun (_mode, rlines) ->
            let fn_name = extract_fn_name rlines in
            match X86_lifter.Lifter.lift_lines rlines with
            | Ok f -> Some (fn_name, { f with Vm_ir.Ir.name = fn_name })
            | Error _ -> None)
          regions
      in
      match lifted_regions with
      | [] ->
          (match X86_lifter.Lifter.lift_function text with
          | Ok f -> Ok (wrap_ir f)
          | Error err -> Error err)
      | [ (_name, f) ] ->
          Ok (wrap_ir f)
      | multi ->
          Ok (wrap_multi_ir multi)
    else
      match X86_lifter.Lifter.lift_function text with
      | Ok f -> Ok (wrap_ir f)
      | Error err -> Error err
  in
  match lift_res with
  | Ok ir -> Ok (ir, [])
  | Error err -> Error err
