open Random_visa_ports

let embed_vm_trampoline ~c_src ~bytecode ~out_path =
  let bc_buf = Buffer.create (List.length bytecode * 25 + 200) in
  Buffer.add_string bc_buf "\n#include \"threaded_vm.hpp\"\n\n";
  Buffer.add_string bc_buf "static uint64_t embedded_bytecode[] = {\n";
  List.iter
    (fun w -> Buffer.add_string bc_buf (Printf.sprintf "    0x%016LXULL,\n" w))
    bytecode;
  Buffer.add_string bc_buf "};\n\n";
  let bc_header = Buffer.contents bc_buf in

  let find_marker str =
    let len = String.length str in
    let in_line_comment = ref false in
    let in_block_comment = ref false in
    let in_string = ref false in
    let result = ref None in
    let i = ref 0 in
    while !i < len && !result = None do
      if !in_line_comment then (
        if str.[!i] = '\n' then in_line_comment := false;
        incr i
      ) else if !in_block_comment then (
        if !i + 1 < len && str.[!i] = '*' && str.[!i + 1] = '/' then (
          in_block_comment := false;
          i := !i + 2
        ) else incr i
      ) else if !in_string then (
        if str.[!i] = '\\' then i := !i + 2
        else if str.[!i] = '"' then (in_string := false; incr i)
        else incr i
      ) else (
        if !i + 1 < len && str.[!i] = '/' && str.[!i + 1] = '/' then (
          in_line_comment := true;
          i := !i + 2
        ) else if !i + 1 < len && str.[!i] = '/' && str.[!i + 1] = '*' then (
          in_block_comment := true;
          i := !i + 2
        ) else if str.[!i] = '"' then (
          in_string := true;
          incr i
        ) else if !i + 12 <= len && String.sub str !i 12 = "ASGARD_BEGIN" then (
          result := Some !i
        ) else incr i
      )
    done;
    !result
  in

  let rec rfind_char str c start =
    if start < 0 then None
    else if str.[start] = c then Some start
    else rfind_char str c (start - 1)
  in

  match find_marker c_src with
  | None ->
      let oc = open_out out_path in
      output_string oc (bc_header ^ c_src);
      close_out oc
  | Some beg_idx ->
      (match rfind_char c_src '{' beg_idx with
      | None ->
          let oc = open_out out_path in
          output_string oc (bc_header ^ c_src);
          close_out oc
      | Some open_brace_idx ->
          let sig_end = open_brace_idx in
          let rparen_opt = rfind_char c_src ')' sig_end in
          let args_to_pass, ret_type =
            match rparen_opt with
            | None -> ("", "")
            | Some rparen ->
                (match rfind_char c_src '(' rparen with
                | None -> ("", "")
                | Some lparen ->
                    let is_space = function ' ' | '\t' | '\r' | '\n' -> true | _ -> false in
                    let p = ref (lparen - 1) in
                    while !p >= 0 && is_space c_src.[!p] do
                      decr p
                    done;
                    while !p >= 0 && (let c = c_src.[!p] in (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c = '_') do
                      decr p
                    done;
                    while !p >= 0 && is_space c_src.[!p] do
                      decr p
                    done;
                    let type_end = !p in
                    while !p >= 0 && c_src.[!p] <> '\n' && c_src.[!p] <> ';' && c_src.[!p] <> '}' && c_src.[!p] <> '>' do
                      decr p
                    done;
                    let prefix = if type_end >= !p + 1 then String.sub c_src (!p + 1) (type_end - !p) |> String.trim else "" in
                    let norm = String.map (fun c -> if is_space c then ' ' else c) prefix in
                    let tokens = String.split_on_char ' ' norm |> List.map String.trim |> List.filter (fun s -> s <> "") in
                    let clean_type =
                      List.filter (fun t -> t <> "static" && t <> "inline" && t <> "__inline__" && t <> "extern") tokens
                      |> String.concat " "
                    in
                    let param_str = String.sub c_src (lparen + 1) (rparen - lparen - 1) |> String.trim in
                    let args =
                      if param_str = "" || param_str = "void" then ""
                      else
                        let raw_params = String.split_on_char ',' param_str |> List.map String.trim in
                        let arg_names = List.filter_map
                          (fun p ->
                            let p_no_default = match String.index_opt p '=' with Some i -> String.sub p 0 i | None -> p in
                            let p_no_array = match String.index_opt p_no_default '[' with Some i -> String.sub p_no_default 0 i | None -> p_no_default in
                            let normalized = String.map (fun c -> if is_space c then ' ' else c) p_no_array in
                            let tokens = String.split_on_char ' ' normalized |> List.map String.trim |> List.filter (fun s -> s <> "" && s <> "*" && s <> "const" && s <> "volatile") in
                            match List.rev tokens with
                            | last :: _ ->
                                let clean = String.trim (String.map (function '*' -> ' ' | c -> c) last) in
                                if clean = "" then None else Some (Printf.sprintf "(uint64_t)%s" clean)
                            | [] -> None)
                          raw_params
                        in
                        String.concat ", " arg_names
                    in
                    (args, clean_type))
          in
          let len = String.length c_src in
          let rec find_closing depth in_str in_char in_line_comm in_blk_comm i =
            if i >= len then len - 1
            else if in_line_comm then
              if c_src.[i] = '\n' then find_closing depth in_str in_char false in_blk_comm (i + 1)
              else find_closing depth in_str in_char true in_blk_comm (i + 1)
            else if in_blk_comm then
              if i + 1 < len && c_src.[i] = '*' && c_src.[i + 1] = '/' then
                find_closing depth in_str in_char false false (i + 2)
              else find_closing depth in_str in_char false true (i + 1)
            else if in_str then
              if c_src.[i] = '\\' && i + 1 < len then find_closing depth true false false false (i + 2)
              else if c_src.[i] = '"' then find_closing depth false false false false (i + 1)
              else find_closing depth true false false false (i + 1)
            else if in_char then
              if c_src.[i] = '\\' && i + 1 < len then find_closing depth false true false false (i + 2)
              else if c_src.[i] = '\'' then find_closing depth false false false false (i + 1)
              else find_closing depth false true false false (i + 1)
            else if i + 1 < len && c_src.[i] = '/' && c_src.[i + 1] = '/' then
              find_closing depth false false true false (i + 2)
            else if i + 1 < len && c_src.[i] = '/' && c_src.[i + 1] = '*' then
              find_closing depth false false false true (i + 2)
            else if c_src.[i] = '"' then
              find_closing depth true false false false (i + 1)
            else if c_src.[i] = '\'' then
              find_closing depth false true false false (i + 1)
            else if c_src.[i] = '{' then
              find_closing (depth + 1) false false false false (i + 1)
            else if c_src.[i] = '}' then
              if depth = 1 then i
              else find_closing (depth - 1) false false false false (i + 1)
            else find_closing depth false false false false (i + 1)
          in
          let close_brace_idx = find_closing 1 false false false false (open_brace_idx + 1) in
          let before_body = String.sub c_src 0 (open_brace_idx + 1) in
          let after_body = String.sub c_src close_brace_idx (len - close_brace_idx) in
          let is_void = ret_type = "void" in
          let is_ptr = String.contains ret_type '*' in
          let comma_args = if args_to_pass = "" then "" else ", " ^ args_to_pass in
          let call_str =
            Printf.sprintf "vanguard_threaded_vm::asgard_vm_call(embedded_bytecode, sizeof(embedded_bytecode) / sizeof(embedded_bytecode[0])%s)" comma_args
          in
          let trampoline_body =
            if is_void then
              Printf.sprintf "\n    %s;\n    return;\n" call_str
            else if is_ptr then
              Printf.sprintf "\n    return (%s)(uintptr_t)%s;\n" ret_type call_str
            else
              Printf.sprintf "\n    return %s;\n" call_str
          in
          let full_out = bc_header ^ before_body ^ trampoline_body ^ after_body in
          let oc = open_out out_path in
          output_string oc full_out;
          close_out oc)

module C_trampoline_engine : Protect_ports.Trampoline_engine = struct
  let embed_vm_trampoline = embed_vm_trampoline
end
