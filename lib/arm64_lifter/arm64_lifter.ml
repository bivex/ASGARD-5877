open Vm_ir
open Arm64_types
open Arm64_common

type options = {
  function_name : string;
}

let default_options = {
  function_name = "arm64_lifted_func";
}

let lift_instr (mnemonic : string) (ops : raw_op list) : (Ir.instr list, string) result =
  match Arm64_alu.lift mnemonic ops with
  | Some instrs -> Ok instrs
  | None ->
      match Arm64_mem.lift mnemonic ops with
      | Some instrs -> Ok instrs
      | None ->
          match Arm64_branch.lift mnemonic ops with
          | Some instrs -> Ok instrs
          | None ->
              if String.starts_with ~prefix:"." mnemonic || String.starts_with ~prefix:"lloh" (String.lowercase_ascii mnemonic) then
                Ok [ Ir.Nop ]
              else
                Error (Printf.sprintf "Unsupported or invalid ARM64 instruction: %s" mnemonic)

let lift_lines ?(options = default_options) (lines : raw_line list) : (Ir.func, string) result =
  let blocks = ref [] in
  let label_aliases = Hashtbl.create 32 in
  let cur_labels = ref [ "entry" ] in
  let cur_instrs = ref [] in
  let cur_id = ref 0 in

  let flush_block () =
    if !cur_instrs <> [] || !blocks = [] then begin
      let primary_label = match !cur_labels with hd :: _ -> hd | [] -> Printf.sprintf "l_bb_%d" !cur_id in
      List.iter (fun l -> Hashtbl.replace label_aliases l !cur_id) !cur_labels;
      let b = {
        Ir.id = !cur_id;
        label = primary_label;
        instrs = List.rev !cur_instrs;
      } in
      blocks := b :: !blocks;
      incr cur_id;
      cur_instrs := [];
      cur_labels := [ Printf.sprintf "l_bb_%d" !cur_id ]
    end
  in

  let rec process = function
    | [] ->
        flush_block ();
        Ok (List.rev !blocks)
    | LineEmpty :: rest | LineDirective _ :: rest | LineMarkerBegin _ :: rest | LineMarkerEnd :: rest -> process rest
    | LineLabel lbl :: rest ->
        if !cur_instrs <> [] then (
          flush_block ();
          cur_labels := [ lbl ]
        ) else (
          cur_labels := lbl :: !cur_labels
        );
        process rest
    | LineInstr (m, ops) :: rest ->
        match lift_instr m ops with
        | Error err -> Error err
        | Ok ir_list ->
            cur_instrs := List.rev ir_list @ !cur_instrs;
            let last_lifted = List.hd (List.rev ir_list) in
            if is_terminator last_lifted then flush_block ();
            process rest
  in

  match process lines with
  | Error err -> Error err
  | Ok bb_list ->
      let label_map = label_aliases in
      List.iter (fun (b : Ir.basic_block) -> Hashtbl.replace label_map b.label b.id) bb_list;

      (* Fix terminator and patch label targets to BlockId *)
      let patched_blocks = List.mapi (fun idx (b : Ir.basic_block) ->
        let fallthrough_id = if idx + 1 < List.length bb_list then (List.nth bb_list (idx + 1)).id else 0 in
        let patch_target = function
          | Ir.Label l ->
              (match Hashtbl.find_opt label_map l with
              | Some bid -> Ir.BlockId bid
              | None -> Ir.Label l)
          | Ir.TargetImm _ -> Ir.BlockId fallthrough_id
          | t -> t
        in
        let patched_instrs = List.map (function
          | Ir.Jmp t -> Ir.Jmp (patch_target t)
          | Ir.Jcc { cond; target_true; target_false } ->
              Ir.Jcc { cond; target_true = patch_target target_true; target_false = patch_target target_false }
          | Ir.Call t -> Ir.Call (patch_target t)
          | other -> other
        ) b.instrs in

        (* Ensure each block has a valid terminator *)
        let final_instrs =
          match List.rev patched_instrs with
          | (Ir.Jmp _ | Ir.Jcc _ | Ir.Ret | Ir.Trap _ | Ir.Vm_exit) :: _ -> patched_instrs
          | _ ->
              if idx + 1 < List.length bb_list then
                patched_instrs @ [ Ir.Jmp (Ir.BlockId fallthrough_id) ]
              else
                patched_instrs @ [ Ir.Ret ]
        in
        { b with instrs = final_instrs }
      ) bb_list in

      let cfg_tbl = Hashtbl.create (List.length patched_blocks) in
      List.iter (fun (b : Ir.basic_block) -> Hashtbl.replace cfg_tbl b.id b) patched_blocks;
      let cfg = { Ir.entry_id = 0; blocks = cfg_tbl } in
      Ok { Ir.name = options.function_name; cfg }

let lift_function ?(options = default_options) (asm : string) : (Ir.func, string) result =
  match Arm64_parser.parse_lines asm with
  | Error err -> Error err
  | Ok lines -> lift_lines ~options lines

let extract_marked_regions ?(require_markers = false) (raw_lines : Arm64_parser.raw_line list) =
  let has_markers =
    List.exists
      (function
        | Arm64_parser.LineMarkerBegin _ | Arm64_parser.LineMarkerEnd -> true
        | _ -> false)
      raw_lines
  in
  if not has_markers then
    if require_markers then []
    else [ (Arm64_parser.ModeUltra "main", raw_lines) ]
  else
    let regions = ref [] in
    let current_mode = ref None in
    let fn_lines = ref [] in
    let last_label = ref "main" in
    let seen_begin = ref false in
    let seen_end = ref false in

    List.iter
      (function
        | Arm64_parser.LineLabel lbl when not (String.starts_with ~prefix:"L" lbl) && not (String.starts_with ~prefix:"." lbl) ->
            (match !current_mode with
            | Some m when !seen_begin ->
                regions := (m, Arm64_parser.LineLabel !last_label :: List.rev !fn_lines) :: !regions;
                current_mode := None;
                seen_begin := false;
                seen_end := false;
                fn_lines := []
            | _ ->
                fn_lines := []);
            last_label := lbl

        | Arm64_parser.LineMarkerBegin mode ->
            current_mode := Some mode;
            seen_begin := true

        | Arm64_parser.LineMarkerEnd ->
            seen_end := true

        | Arm64_parser.LineInstr (mnem, _) as instr ->
            if !seen_begin then begin
              if not !seen_end then
                fn_lines := instr :: !fn_lines
              else begin
                fn_lines := instr :: !fn_lines;
                if mnem = "ret" then begin
                  (match !current_mode with
                  | Some m ->
                      regions := (m, Arm64_parser.LineLabel !last_label :: List.rev !fn_lines) :: !regions;
                      current_mode := None;
                      seen_begin := false;
                      seen_end := false;
                      fn_lines := []
                  | None -> ())
                end
              end
            end else begin
              fn_lines := instr :: !fn_lines
            end

        | (Arm64_parser.LineLabel _ | Arm64_parser.LineDirective _) as line ->
            fn_lines := line :: !fn_lines
        | Arm64_parser.LineEmpty -> ())
      raw_lines;

    (match !current_mode with
    | Some m when !seen_begin ->
        regions := (m, Arm64_parser.LineLabel !last_label :: List.rev !fn_lines) :: !regions
    | _ -> ());

    if !regions = [] then
      [ (Arm64_parser.ModeUltra "main", raw_lines) ]
    else
      List.rev !regions

module Arm64_parser = Arm64_parser
module Literal_stitcher = Literal_stitcher
