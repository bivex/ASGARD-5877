open Random_visa_ports
open Random_visa_constants.Magic_numbers

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
    ?decoy_bytecode
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
                        List.filter (fun t ->
                          t <> "static" && t <> "inline" && t <> "__inline__" && t <> "extern"
                          && t <> "\"C\"" && t <> "\"C++\"" && t <> "constexpr" && t <> "consteval"
                          && not (String.starts_with ~prefix:"__" t)
                        ) tokens
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
                              let is_ref = String.contains p_no_default '&' in
                              let is_ptr = String.contains p_no_default '*' in
                              let normalized = String.map (fun c -> if is_space c then ' ' else c) p_no_array in
                              let tokens = String.split_on_char ' ' normalized |> List.map String.trim |> List.filter (fun s -> s <> "" && s <> "*" && s <> "&" && s <> "const" && s <> "volatile") in
                              match List.rev tokens with
                              | last :: _ ->
                                  let clean = String.trim (String.map (function '*' | '&' -> ' ' | c -> c) last) in
                                  if clean = "" then None
                                  else if is_ref then
                                    Some (Printf.sprintf "(uint64_t)(uintptr_t)&%s" clean)
                                  else if is_ptr then
                                    Some (Printf.sprintf "(uint64_t)(uintptr_t)%s" clean)
                                  else
                                    Some (Printf.sprintf "(uint64_t)%s" clean)
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

  let chunk_struct_decl =
    Cpp_codegen.Cpp_ast.StructDecl {
      align_as = None;
      name = "AsgardBytecodeChunk";
      fields = [
        (Cpp_codegen.Cpp_ast.UInt32, "chunk_id");
        (Cpp_codegen.Cpp_ast.UInt32, "next_chunk_id");
        (Cpp_codegen.Cpp_ast.UInt32, "word_offset");
        (Cpp_codegen.Cpp_ast.UInt32, "word_count");
        (Cpp_codegen.Cpp_ast.UInt32, "canary");
        (Cpp_codegen.Cpp_ast.UInt32, "entropy_seed");
        (Cpp_codegen.Cpp_ast.Array (Cpp_codegen.Cpp_ast.UInt64, 2), "junk_pad");
        (Cpp_codegen.Cpp_ast.ConstPtr Cpp_codegen.Cpp_ast.UInt64, "data");
      ];
    }
  in
  let chunk_struct_decls =
    let open Cpp_codegen.Cpp_ast in
    let open Cpp_codegen.Cpp_dsl in
    [
      include_local header_name;
      preproc_ifndef "ASGARD_BYTECODE_CHUNK_DEF" [
        macro_def "ASGARD_BYTECODE_CHUNK_DEF";
        include_sys "stdint.h";
        include_sys "stddef.h";
        preproc_if "defined(__APPLE__)" [
          include_sys "sys/sysctl.h";
          include_sys "unistd.h";
        ] ~else_decls:[
          preproc_if "defined(__linux__)" [
            include_sys "unistd.h";
          ] ~else_decls:[];
        ];
        preproc_if "defined(_MSC_VER) && !defined(__clang__)"
          [
            include_sys "intrin.h";
            macro_def ~value:(call "MemoryBarrier" []) "ASG_CHUNK_BARRIER()";
            macro_def ~value:(call "__debugbreak" []) "ASG_CHUNK_TRAP()";
          ]
          ~else_decls:[
            macro_def ~value:(call "__atomic_thread_fence" [var "__ATOMIC_SEQ_CST"]) "ASG_CHUNK_BARRIER()";
            macro_def ~value:(call "__builtin_trap" []) "ASG_CHUNK_TRAP()";
          ];
        pragma "pack(push, 1)";
        chunk_struct_decl;
        typedef (StructType "struct AsgardBytecodeChunk") "AsgardBytecodeChunk";
        pragma "pack(pop)";
      ];
    ]
  in
  let chunk_struct_def = Cpp_codegen.Cpp_printer.render_top_decls chunk_struct_decls in
  let effective_decoy_bc =
    match decoy_bytecode with
    | Some dbc -> dbc
    | None ->
        let rng = Random.State.make [| 0xDEC01337; List.length bytecode |] in
        Native_vm.Decoy_synth.synth_decoy_bytecode ~rng ~seed:salt_xwcafe_leetbeef ~name:"decoy_payload"
  in

  let format_fragmented_bytecode name bc =
    let open Cpp_codegen.Cpp_ast in
    let open Cpp_codegen.Cpp_dsl in
    let open Cpp_codegen.Cpp_printer in
    let total_words = List.length bc in
    if total_words = 0 then
      let empty_arr =
        global_var ~is_static:true
          (Array (UInt64, 1))
          name
          ~init:(init_list [ u64 0L ])
      in
      render_top_decls [ empty_arr ]
      ^ Printf.sprintf "\n__attribute__((unused)) static inline void %s_ensure_assembled(void) {}\n\n" name
    else
      let chunk_size = 64 in
      let rec split idx offset acc remaining =
        if remaining = [] then List.rev acc
        else
          let rec take n l taken =
            match (n, l) with
            | 0, _ | _, [] -> (List.rev taken, l)
            | n, x :: xs -> take (n - 1) xs (x :: taken)
          in
          let chunk_words, rest = take chunk_size remaining [] in
          let count = List.length chunk_words in
          split (idx + 1) (offset + count) ((idx, offset, count, chunk_words) :: acc) rest
      in
      let raw_chunks = split 0 0 [] bc in
      let num_chunks = List.length raw_chunks in
      let chunks_info =
        List.map (fun (idx, offset, count, chunk_words) ->
          let chunk_id = (idx * 0x1337 + 0x5877) land 0x7FFFFFFF in
          let next_chunk_id =
            if idx < num_chunks - 1 then ((idx + 1) * 0x1337 + 0x5877) land 0x7FFFFFFF
            else 0xFFFFFFFF
          in
          let canary = Int64.logand (Int64.add (Int64.mul (Int64.of_int chunk_id) 0xDEADL) 0xCAFEL) 0xFFFFFFFFL in
          let entropy_seed = Int64.logand (Int64.add (Int64.mul (Int64.of_int idx) 0x6A09L) 0xBEEFL) 0xFFFFFFFFL in
          let junk_pad0 = Int64.logxor salt_xwcafe_leetbeef (Int64.mul (Int64.of_int idx) golden_ratio_64) in
          let junk_pad1 = Int64.logxor salt_deadbeef_cafebabe (Int64.mul (Int64.of_int chunk_id) sqrt2_fraction_64) in
          let k_dyn = Int64.logxor salt_chunk_kdyn_seed (Int64.mul (Int64.of_int chunk_id) golden_ratio_64) in
          let masked_words =
            List.mapi (fun j w ->
              let word_key = Int64.add k_dyn (Int64.mul (Int64.of_int j) fnv1a_64_prime) in
              Int64.logxor w word_key
            ) chunk_words
          in
          (idx, chunk_id, next_chunk_id, offset, count, canary, entropy_seed, junk_pad0, junk_pad1, masked_words)
        ) raw_chunks
      in
      let chunk_array_decls =
        List.map (fun (idx, _, _, _, _, _, _, _, _, masked_words) ->
          global_var ~is_static:true ~is_const:true
            (Array (UInt64, 0))
            (Printf.sprintf "%s_chk_%04x" name idx)
            ~init:(init_list (List.map u64 masked_words))
        ) chunks_info
      in
      let permuted_chunks =
        let arr = Array.of_list chunks_info in
        let n = Array.length arr in
        let rng = Random.State.make [| 0x5877; n; 0xA56A |] in
        for i = n - 1 downto 1 do
          let j = Random.State.int rng (i + 1) in
          let tmp = arr.(i) in
          arr.(i) <- arr.(j);
          arr.(j) <- tmp
        done;
        Array.to_list arr
      in
      let chunk_table_entries =
        List.map (fun (idx, chunk_id, next_chunk_id, offset, count, canary, entropy_seed, junk0, junk1, _) ->
          init_list [
            u32 (Int32.of_int chunk_id);
            u32 (Int32.of_int next_chunk_id);
            i32 offset;
            i32 count;
            u64 canary;
            u64 entropy_seed;
            init_list [ u64 junk0; u64 junk1 ];
            var (Printf.sprintf "%s_chk_%04x" name idx);
          ]
        ) permuted_chunks
      in
      let chunks_decl =
        global_var ~is_static:true ~is_const:true
          (Array (StructType "AsgardBytecodeChunk", num_chunks))
          (Printf.sprintf "%s_chunks" name)
          ~init:(init_list chunk_table_entries)
      in
      let assembled_var =
        global_var ~is_static:true ~is_volatile:true
          Int32 (Printf.sprintf "%s_assembled" name) ~init:(i32 0)
      in
      let target_array =
        global_var ~is_static:true
          (Array (UInt64, total_words)) name
      in
      let ensure_assembled_fn =
        func_decl
          ~attrs:[StaticFn; NoInline]
          Void
          (Printf.sprintf "%s_ensure_assembled" name)
          []
          [
            if_then (log_not (var (Printf.sprintf "%s_assembled" name))) [
              for_range "_idx" (i32 0) (i32 num_chunks) [
                decl_var (ConstPtr (StructType "AsgardBytecodeChunk")) "c"
                  ~init:(addr_of (idx (var (Printf.sprintf "%s_chunks" name)) (var "_idx")));
                if_then (ne (var "c" $-> "canary") (c_cast UInt64 ((((var "c" $-> "chunk_id") *~ u32 0xDEADl) +~ u32 0xCAFEl) &~ u32 0xFFFFFFFFl))) [
                  expr_stmt (call "ASG_CHUNK_TRAP" []);
                ];
                let_u64 "k_dyn" (u64 salt_chunk_kdyn_seed ^~ (c_cast UInt64 (var "c" $-> "chunk_id") *~ u64 golden_ratio_64));
                for_range "j" (i32 0) (c_cast Int32 (var "c" $-> "word_count")) [
                  let_u64 "word_key" (var "k_dyn" +~ (c_cast UInt64 (var "j") *~ u64 fnv1a_64_prime));
                  idx (var name) ((var "c" $-> "word_offset") +~ var "j") :=
                    (idx (var "c" $-> "data") (var "j") ^~ var "word_key");
                ];
              ];
              expr_stmt (call "ASG_CHUNK_BARRIER" []);
              (var (Printf.sprintf "%s_assembled" name)) := i32 1;
            ];
          ]
      in
      let auto_init_fn =
        func_decl
          ~attrs:[StaticFn; Constructor]
          Void
          (Printf.sprintf "%s_auto_init" name)
          []
          [
            expr_stmt (call (Printf.sprintf "%s_ensure_assembled" name) []);
          ]
      in
      render_top_decls (
        chunk_array_decls
        @ [ chunks_decl; target_array; assembled_var; ensure_assembled_fn; auto_init_fn ]
      )
  in

  let salt_of_name is_multi name =
    let clean = if String.starts_with ~prefix:"_" name then String.sub name 1 (String.length name - 1) else name in
    if not is_multi || clean = "" || clean = "main" || clean = "target_func" then 0
    else
      let h = Hashtbl.hash clean in
      (h land 0xFE) lor 1
  in
  let build_trampoline_body is_multi arr_name ret_type args_to_pass fn_name =
    let open Cpp_codegen.Cpp_ast in
    let open Cpp_codegen.Cpp_dsl in
    let open Cpp_codegen.Cpp_printer in
    let macro_salt = salt_of_name is_multi fn_name in
    let decoy_arr_name = arr_name ^ "_decoy" in
    let is_void = ret_type = "void" in
    let is_ptr = String.contains ret_type '*' in

    let ensure_real = expr_stmt (call (Printf.sprintf "%s_ensure_assembled" arr_name) []) in
    let ensure_decoy = expr_stmt (call (Printf.sprintf "%s_ensure_assembled" decoy_arr_name) []) in

    let decl_penalty = decl_var UInt64 "_penalty" ~init:(u64 0L) in

    let apple_check =
      preproc_if_stmt "defined(__APPLE__)" [
        decl_var (Array (Int32, 4)) "_mib"
          ~init:(init_list [ var "CTL_KERN"; var "KERN_PROC"; var "KERN_PROC_PID"; call "getpid" [] ]);
        decl_var (StructType "struct kinfo_proc") "_kinfo"
          ~init:(init_list []);
        decl_var SizeT "_ksize"
          ~init:(sizeof_ty (StructType "struct kinfo_proc"));
        if_then (
          Binary (LogAnd,
            Binary (Eq,
              call "sysctl" [var "_mib"; i32 4; addr_of (var "_kinfo"); addr_of (var "_ksize"); cast (Ptr Void) (u64 0L); i32 0],
              i32 0),
            Binary (Ne,
              Binary (BitAnd, (var "_kinfo" $. "kp_proc.p_flag"), var "P_TRACED"),
              u64 0L))
        ) [
          (var "_penalty" ^= u64 salt_xwcafe_leetbeef);
        ];
      ] ~elifs:[
        ("defined(__linux__)", [
          decl_var (Ptr (StructType "FILE")) "_fp_stat"
            ~init:(call "fopen" [str_lit "/proc/self/status"; str_lit "r"]);
          if_then (var "_fp_stat" <>~ nullptr) [
            decl_var (Array (Int8, 128)) "_line";
            while_loop (call "fgets" [var "_line"; call "sizeof" [var "_line"]; var "_fp_stat"]) [
              if_then (Binary (Eq, call "strncmp" [var "_line"; str_lit "TracerPid:"; i32 10], i32 0)) [
                decl_var Int32 "_pid" ~init:(call "atoi" [Binary (Add, var "_line", i32 10)]);
                if_then (var "_pid" >~ i32 0) [
                  (var "_penalty" ^= u64 salt_xwcafe_leetbeef);
                ];
                break_stmt;
              ];
            ];
            expr_stmt (call "fclose" [var "_fp_stat"]);
          ];
        ])
      ]
    in

    let mask_init =
      c_cast UIntPtr (neg (c_cast (StructType "intptr_t") (var "_penalty" <>~ u64 0L)))
    in
    let decl_mask = decl_var UIntPtr "_mask" ~init:mask_init in

    let active_bc_init =
      c_cast (ConstPtr UInt64) (
        Binary (BitOr,
          Binary (BitAnd, c_cast UIntPtr (var arr_name), bit_not (var "_mask")),
          Binary (BitAnd, c_cast UIntPtr (var decoy_arr_name), var "_mask"))
      )
    in
    let decl_active_bc = decl_var (ConstPtr UInt64) "_active_bc" ~init:active_bc_init in

    let active_len_init =
      Binary (BitOr,
        Binary (BitAnd,
          Binary (Div, call "sizeof" [var arr_name], call "sizeof" [idx (var arr_name) (i32 0)]),
          bit_not (var "_mask")),
        Binary (BitAnd,
          Binary (Div, call "sizeof" [var decoy_arr_name], call "sizeof" [idx (var decoy_arr_name) (i32 0)]),
          var "_mask"))
    in
    let decl_active_len = decl_var SizeT "_active_len" ~init:active_len_init in

    let parsed_args =
      if args_to_pass = "" then []
      else
        String.split_on_char ',' args_to_pass
        |> List.map String.trim
        |> List.filter (fun s -> s <> "")
        |> List.map (fun a -> var a)
    in
    let base_call_args = var "_active_bc" :: var "_active_len" :: parsed_args in
    let call_expr =
      if macro_salt = 0 then
        call "vanguard_threaded_vm::asgard_vm_call" base_call_args
      else
        call "vanguard_threaded_vm::asgard_vm_call_with_salt" (u8 macro_salt :: base_call_args)
    in

    let ret_stmts =
      if is_void then [ expr_stmt call_expr; ret_void ]
      else if is_ptr then [ ret (c_cast (StructType ret_type) (c_cast UIntPtr call_expr)) ]
      else [ ret (c_cast (StructType ret_type) call_expr) ]
    in

    let all_stmts = [
      ensure_real;
      ensure_decoy;
      decl_penalty;
      apple_check;
      decl_mask;
      decl_active_bc;
      decl_active_len;
    ] @ ret_stmts in
    let rendered = string_of_stmts all_stmts in
    "\n    " ^ String.concat "\n    " (String.split_on_char '\n' (String.trim rendered)) ^ "\n"
  in

  match marked_fns with
  | [] ->
      Logger.warn ~section:"TRAMPOLINE" "No functions marked with ASGARD_BEGIN / ASGARD_END found; embedding raw bytecode only";
      let bc_formatted = format_fragmented_bytecode "embedded_bytecode" bytecode in
      let decoy_bc_formatted = format_fragmented_bytecode "embedded_bytecode_decoy" effective_decoy_bc in
      let bc_header =
        Printf.sprintf "\n%s\n%s\n%s\n"
          chunk_struct_def bc_formatted decoy_bc_formatted
      in
      let oc = open_out out_path in
      output_string oc (bc_header ^ c_src);
      close_out oc

  | [ single_fn ] when (match bytecodes with Some bcs -> List.length bcs <= 1 | None -> true) ->
      Logger.infof ~loc:__LOC__ ~section:"TRAMPOLINE" "Embedding zero-native trampoline for function '%s' (ret=%s, args='%s')"
        single_fn.fn_name single_fn.ret_type single_fn.args_to_pass;
      Logger.infof ~loc:__LOC__ ~section:"TRAMPOLINE" "  ├─ Zero-Native Dispatch: 56-byte inline jump stub replaces function body";
      Logger.infof ~loc:__LOC__ ~section:"TRAMPOLINE" "  ├─ Fragmented Bytecode Storage: word chunks guarded with canary & entropy seeds";
      Logger.infof ~loc:__LOC__ ~section:"TRAMPOLINE" "  └─ Decoy VM Manifold: dual dummy bytecode stream embedded (%d words)" (List.length effective_decoy_bc);
      (* Backward-compatible single function path *)
      let bc_formatted = format_fragmented_bytecode "embedded_bytecode" bytecode in
      let decoy_bc_formatted = format_fragmented_bytecode "embedded_bytecode_decoy" effective_decoy_bc in
      let bc_header =
        Printf.sprintf "\n%s\n%s\n%s\n"
          chunk_struct_def bc_formatted decoy_bc_formatted
      in
      let before_body = String.sub c_src 0 (single_fn.open_brace_idx + 1) in
      let after_body = String.sub c_src single_fn.close_brace_idx (len - single_fn.close_brace_idx) in
      let trampoline_body = build_trampoline_body false "embedded_bytecode" single_fn.ret_type single_fn.args_to_pass single_fn.fn_name in
      let full_out = bc_header ^ before_body ^ trampoline_body ^ after_body in
      let oc = open_out out_path in
      output_string oc full_out;
      close_out oc

  | multi_fns ->
      Logger.infof ~loc:__LOC__ ~section:"TRAMPOLINE" "Embedding zero-native trampolines for %d functions: [%s]"
        (List.length multi_fns) (String.concat ", " (List.map (fun f -> f.fn_name) multi_fns));
      Logger.infof ~loc:__LOC__ ~section:"TRAMPOLINE" "  ├─ Zero-Native Dispatch: per-function jump stubs with isolated macro salts";
      Logger.infof ~loc:__LOC__ ~section:"TRAMPOLINE" "  ├─ Fragmented Bytecode Storage: word chunks guarded with canary & entropy seeds";
      Logger.infof ~loc:__LOC__ ~section:"TRAMPOLINE" "  └─ Decoy VM Manifold: dual dummy bytecode stream embedded (%d words)" (List.length effective_decoy_bc);
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
      Buffer.add_string header_buf (Printf.sprintf "\n%s\n" chunk_struct_def);

      List.iteri (fun idx fn ->
        let fn_bc = find_bc_for_fn idx fn.fn_name in
        let arr_name = Printf.sprintf "embedded_bytecode_%s" (sanitize_ident fn.fn_name) in
        Buffer.add_string header_buf (format_fragmented_bytecode arr_name fn_bc);
        Buffer.add_string header_buf (format_fragmented_bytecode (arr_name ^ "_decoy") effective_decoy_bc)
      ) multi_fns;

      (* Fallback alias / first bytecode for embedded_bytecode symbol search *)
      let first_bc = match multi_fns with
        | hd :: _ -> find_bc_for_fn 0 hd.fn_name
        | [] -> bytecode
      in
      Buffer.add_string header_buf (format_fragmented_bytecode "embedded_bytecode" first_bc);
      Buffer.add_string header_buf (format_fragmented_bytecode "embedded_bytecode_decoy" effective_decoy_bc);

      let body_buf = Buffer.create (len + 2048) in
      Buffer.add_string body_buf (Buffer.contents header_buf);

      let last_pos = ref 0 in
      List.iter (fun fn ->
        let arr_name = Printf.sprintf "embedded_bytecode_%s" (sanitize_ident fn.fn_name) in
        Buffer.add_string body_buf (String.sub c_src !last_pos (fn.open_brace_idx + 1 - !last_pos));
        let trampoline_body = build_trampoline_body (List.length multi_fns > 1) arr_name fn.ret_type fn.args_to_pass fn.fn_name in
        Buffer.add_string body_buf trampoline_body;
        last_pos := fn.close_brace_idx
      ) multi_fns;

      Buffer.add_string body_buf (String.sub c_src !last_pos (len - !last_pos));
      let oc = open_out out_path in
      output_string oc (Buffer.contents body_buf);
      close_out oc;
      Logger.debugf ~section:"TRAMPOLINE" "Virtualized source with trampolines written to '%s' (decoy_words=%d)"
        out_path (List.length effective_decoy_bc);

module C_trampoline_engine : Protect_ports.Trampoline_engine = struct
  let embed_vm_trampoline = embed_vm_trampoline
end
