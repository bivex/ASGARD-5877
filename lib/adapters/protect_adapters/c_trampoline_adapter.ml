open Random_visa_ports

type marked_fn = {
  fn_name : string;
  ret_type : string;
  args_to_pass : string;
  open_brace_idx : int;
  close_brace_idx : int;
}

let sanitize_ident name =
  let s = String.map (function 'a'..'z' | 'A'..'Z' | '0'..'9' | '_' as c -> c | _ -> '_') name in
  if s = "" then "fn" else s

let contains_sub s sub =
  let len_s = String.length s in
  let len_sub = String.length sub in
  if len_sub > len_s || len_sub = 0 then false
  else
    let found = ref false in
    for i = 0 to len_s - len_sub do
      if not !found && String.sub s i len_sub = sub then found := true
    done;
    !found

let strip_attributes s =
  let len = String.length s in
  let buf = Buffer.create len in
  let i = ref 0 in
  while !i < len do
    if !i + 13 <= len && String.sub s !i 13 = "__attribute__" then (
      i := !i + 13;
      while !i < len && (s.[!i] = ' ' || s.[!i] = '\t') do incr i done;
      if !i < len && s.[!i] = '(' then (
        incr i;
        let depth = ref 1 in
        while !i < len && !depth > 0 do
          if s.[!i] = '(' then incr depth
          else if s.[!i] = ')' then decr depth;
          incr i
        done
      )
    ) else if !i + 10 <= len && String.sub s !i 10 = "__declspec" then (
      i := !i + 10;
      while !i < len && (s.[!i] = ' ' || s.[!i] = '\t') do incr i done;
      if !i < len && s.[!i] = '(' then (
        incr i;
        let depth = ref 1 in
        while !i < len && !depth > 0 do
          if s.[!i] = '(' then incr depth
          else if s.[!i] = ')' then decr depth;
          incr i
        done
      )
    ) else (
      Buffer.add_char buf s.[!i];
      incr i
    )
  done;
  Buffer.contents buf

let embed_vm_trampoline
    ?(header_name = "threaded_vm.hpp")
    ~c_src
    ?bytecodes
    ~bytecode
    ~out_path
    () =

  let find_all_markers str =
    let len = String.length str in
    let in_line_comment = ref false in
    let in_block_comment = ref false in
    let in_string = ref false in
    let results = ref [] in
    let i = ref 0 in
    while !i < len do
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
          results := !i :: !results;
          i := !i + 12
        ) else incr i
      )
    done;
    List.rev !results
  in

  let rec rfind_char str c start =
    if start < 0 then None
    else if str.[start] = c then Some start
    else rfind_char str c (start - 1)
  in

  let len = String.length c_src in

  let find_closing depth in_str in_char in_line_comm in_blk_comm start_idx =
    let rec loop d s ch lc bc i =
      if i >= len then len - 1
      else if lc then
        if c_src.[i] = '\n' then loop d s ch false bc (i + 1)
        else loop d s ch true bc (i + 1)
      else if bc then
        if i + 1 < len && c_src.[i] = '*' && c_src.[i + 1] = '/' then
          loop d s ch false false (i + 2)
        else loop d s ch false true (i + 1)
      else if s then
        if c_src.[i] = '\\' && i + 1 < len then loop d true false false false (i + 2)
        else if c_src.[i] = '"' then loop d false false false false (i + 1)
        else loop d true false false false (i + 1)
      else if ch then
        if c_src.[i] = '\\' && i + 1 < len then loop d false true false false (i + 2)
        else if c_src.[i] = '\'' then loop d false false false false (i + 1)
        else loop d false true false false (i + 1)
      else if i + 1 < len && c_src.[i] = '/' && c_src.[i + 1] = '/' then
        loop d false false true false (i + 2)
      else if i + 1 < len && c_src.[i] = '/' && c_src.[i + 1] = '*' then
        loop d false false false true (i + 2)
      else if c_src.[i] = '"' then
        loop d true false false false (i + 1)
      else if c_src.[i] = '\'' then
        loop d false true false false (i + 1)
      else if c_src.[i] = '{' then
        loop (d + 1) false false false false (i + 1)
      else if c_src.[i] = '}' then
        if d = 1 then i
        else loop (d - 1) false false false false (i + 1)
      else loop d false false false false (i + 1)
    in
    loop depth in_str in_char in_line_comm in_blk_comm start_idx
  in

  let marker_indices = find_all_markers c_src in

  let marked_fns =
    let acc = ref [] in
    let last_closed = ref (-1) in
    List.iter (fun beg_idx ->
      if beg_idx > !last_closed then (
        match rfind_char c_src '{' beg_idx with
        | None -> ()
        | Some open_brace_idx ->
            let sig_end = open_brace_idx in
            let rparen_opt = rfind_char c_src ')' sig_end in
            let args_to_pass, ret_type, fn_name =
              match rparen_opt with
              | None -> ("", "", "target_func")
              | Some rparen ->
                  (match rfind_char c_src '(' rparen with
                  | None -> ("", "", "target_func")
                  | Some lparen ->
                      let is_space = function ' ' | '\t' | '\r' | '\n' -> true | _ -> false in
                      let p = ref (lparen - 1) in
                      while !p >= 0 && is_space c_src.[!p] do
                        decr p
                      done;
                      let name_end = !p in
                      while !p >= 0 && (let c = c_src.[!p] in (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c = '_') do
                        decr p
                      done;
                      let fn_name =
                        if name_end >= !p + 1 then String.sub c_src (!p + 1) (name_end - !p) |> String.trim
                        else "target_func"
                      in
                      while !p >= 0 && is_space c_src.[!p] do
                        decr p
                      done;
                      let type_end = !p in
                      while !p >= 0 && c_src.[!p] <> '\n' && c_src.[!p] <> ';' && c_src.[!p] <> '}' && c_src.[!p] <> '>' do
                        decr p
                      done;
                      let raw_prefix = if type_end >= !p + 1 then String.sub c_src (!p + 1) (type_end - !p) |> String.trim else "" in
                      let prefix = strip_attributes raw_prefix in
                      let norm = String.map (fun c -> if is_space c then ' ' else c) prefix in
                      let tokens = String.split_on_char ' ' norm |> List.map String.trim |> List.filter (fun s -> s <> "") in
                      let clean_type =
                        List.filter (fun t -> t <> "static" && t <> "inline" && t <> "__inline__" && t <> "extern" && not (String.starts_with ~prefix:"__" t)) tokens
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
                      (args, clean_type, fn_name))
            in
            let close_brace_idx = find_closing 1 false false false false (open_brace_idx + 1) in
            last_closed := close_brace_idx;
            acc := { fn_name; ret_type; args_to_pass; open_brace_idx; close_brace_idx } :: !acc
      )
    ) marker_indices;
    List.rev !acc
  in

  let format_bc_array name bc =
    let bc_lines =
      List.map (fun w -> Printf.sprintf "    0x%016LXULL," w) bc
      |> String.concat "\n"
    in
    Printf.sprintf "static uint64_t %s[] = {\n%s\n};\n\n" name bc_lines
  in

  match marked_fns with
  | [] ->
      let bc_lines =
        List.map (fun w -> Printf.sprintf "    0x%016LXULL," w) bytecode
        |> String.concat "\n"
      in
      let bc_header =
        Printf.sprintf "\n#include \"%s\"\n\nstatic uint64_t embedded_bytecode[] = {\n%s\n};\n\n"
          header_name bc_lines
      in
      let oc = open_out out_path in
      output_string oc (bc_header ^ c_src);
      close_out oc

  | [ single_fn ] when (match bytecodes with Some bcs -> List.length bcs <= 1 | None -> true) ->
      (* Backward-compatible single function path *)
      let bc_lines =
        List.map (fun w -> Printf.sprintf "    0x%016LXULL," w) bytecode
        |> String.concat "\n"
      in
      let bc_header =
        Printf.sprintf "\n#include \"%s\"\n\nstatic uint64_t embedded_bytecode[] = {\n%s\n};\n\n"
          header_name bc_lines
      in
      let before_body = String.sub c_src 0 (single_fn.open_brace_idx + 1) in
      let after_body = String.sub c_src single_fn.close_brace_idx (len - single_fn.close_brace_idx) in
      let is_void = single_fn.ret_type = "void" in
      let is_ptr = String.contains single_fn.ret_type '*' in
      let comma_args = if single_fn.args_to_pass = "" then "" else ", " ^ single_fn.args_to_pass in
      let call_str =
        Printf.sprintf "vanguard_threaded_vm::asgard_vm_call(embedded_bytecode, sizeof(embedded_bytecode) / sizeof(embedded_bytecode[0])%s)" comma_args
      in
      let trampoline_body =
        if is_void then
          Printf.sprintf "\n    %s;\n    return;\n" call_str
        else if is_ptr then
          Printf.sprintf "\n    return (%s)(uintptr_t)%s;\n" single_fn.ret_type call_str
        else
          Printf.sprintf "\n    return %s;\n" call_str
      in
      let full_out = bc_header ^ before_body ^ trampoline_body ^ after_body in
      let oc = open_out out_path in
      output_string oc full_out;
      close_out oc

  | multi_fns ->
      (* Multi-function path *)
      let bcs_list = match bytecodes with Some bcs -> bcs | None -> [] in
      let find_bc_for_fn idx fn_name =
        let strip_lead s = if String.starts_with ~prefix:"_" s then String.sub s 1 (String.length s - 1) else s in
        let s_name = strip_lead fn_name in
        match List.find_opt (fun (n, _) ->
          let sn = strip_lead n in
          n = fn_name || sn = s_name || contains_sub sn s_name || contains_sub s_name sn
        ) bcs_list with
        | Some (_, bc) -> bc
        | None ->
            (match List.nth_opt bcs_list idx with
            | Some (_, bc) -> bc
            | None -> bytecode)
      in

      let header_buf = Buffer.create 2048 in
      Buffer.add_string header_buf (Printf.sprintf "\n#include \"%s\"\n\n" header_name);

      List.iteri (fun idx fn ->
        let fn_bc = find_bc_for_fn idx fn.fn_name in
        let arr_name = Printf.sprintf "embedded_bytecode_%s" (sanitize_ident fn.fn_name) in
        Buffer.add_string header_buf (format_bc_array arr_name fn_bc)
      ) multi_fns;

      (* Fallback alias / first bytecode for embedded_bytecode symbol search *)
      let first_bc = match multi_fns with
        | hd :: _ -> find_bc_for_fn 0 hd.fn_name
        | [] -> bytecode
      in
      Buffer.add_string header_buf (format_bc_array "embedded_bytecode" first_bc);

      let body_buf = Buffer.create (len + 2048) in
      Buffer.add_string body_buf (Buffer.contents header_buf);

      let last_pos = ref 0 in
      List.iter (fun fn ->
        let arr_name = Printf.sprintf "embedded_bytecode_%s" (sanitize_ident fn.fn_name) in
        Buffer.add_string body_buf (String.sub c_src !last_pos (fn.open_brace_idx + 1 - !last_pos));
        let is_void = fn.ret_type = "void" in
        let is_ptr = String.contains fn.ret_type '*' in
        let comma_args = if fn.args_to_pass = "" then "" else ", " ^ fn.args_to_pass in
        let call_str =
          Printf.sprintf "vanguard_threaded_vm::asgard_vm_call(%s, sizeof(%s) / sizeof(%s[0])%s)" arr_name arr_name arr_name comma_args
        in
        let trampoline_body =
          if is_void then
            Printf.sprintf "\n    %s;\n    return;\n" call_str
          else if is_ptr then
            Printf.sprintf "\n    return (%s)(uintptr_t)%s;\n" fn.ret_type call_str
          else
            Printf.sprintf "\n    return %s;\n" call_str
        in
        Buffer.add_string body_buf trampoline_body;
        last_pos := fn.close_brace_idx
      ) multi_fns;

      Buffer.add_string body_buf (String.sub c_src !last_pos (len - !last_pos));
      let oc = open_out out_path in
      output_string oc (Buffer.contents body_buf);
      close_out oc

module C_trampoline_engine : Protect_ports.Trampoline_engine = struct
  let embed_vm_trampoline = embed_vm_trampoline
end
