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

  let chunk_struct_def = {|
#ifndef ASGARD_BYTECODE_CHUNK_DEF
#define ASGARD_BYTECODE_CHUNK_DEF
#include <stdint.h>
#include <stddef.h>

#if defined(_MSC_VER) && !defined(__clang__)
#include <intrin.h>
#define ASG_CHUNK_BARRIER() MemoryBarrier()
#define ASG_CHUNK_TRAP() __debugbreak()
#else
#define ASG_CHUNK_BARRIER() __atomic_thread_fence(__ATOMIC_SEQ_CST)
#define ASG_CHUNK_TRAP() __builtin_trap()
#endif

#pragma pack(push, 1)
typedef struct {
    uint32_t chunk_id;
    uint32_t next_chunk_id;
    uint32_t word_offset;
    uint32_t word_count;
    uint32_t canary;
    uint32_t entropy_seed;
    uint64_t junk_pad[2];
    const uint64_t* data;
} AsgardBytecodeChunk;
#pragma pack(pop)
#endif
|} in

  let format_fragmented_bytecode name bc =
    let total_words = List.length bc in
    if total_words = 0 then
      Printf.sprintf "static uint64_t %s[1] = { 0 };\n__attribute__((unused)) static inline void %s_ensure_assembled(void) {}\n\n" name name
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
          let junk_pad0 = Int64.logxor 0x5877CAFE1337BEEFL (Int64.mul (Int64.of_int idx) 0x9E3779B97F4A7C15L) in
          let junk_pad1 = Int64.logxor 0xDEADBEEFCAFEBABEL (Int64.mul (Int64.of_int chunk_id) 0x517CC1B727220A95L) in
          let k_dyn = Int64.logxor 0x5877A56A11223344L (Int64.mul (Int64.of_int chunk_id) 0x9E3779B97F4A7C15L) in
          let masked_words =
            List.mapi (fun j w ->
              let word_key = Int64.add k_dyn (Int64.mul (Int64.of_int j) 0x100000001B3L) in
              Int64.logxor w word_key
            ) chunk_words
          in
          (idx, chunk_id, next_chunk_id, offset, count, canary, entropy_seed, junk_pad0, junk_pad1, masked_words)
        ) raw_chunks
      in
      let chunk_arrays =
        List.map (fun (idx, _, _, _, _, _, _, _, _, masked_words) ->
          let lines =
            List.map (fun w -> Printf.sprintf "    0x%016LXULL," w) masked_words
            |> String.concat "\n"
          in
          Printf.sprintf "static const uint64_t %s_chk_%04x[] = {\n%s\n};\n" name idx lines
        ) chunks_info
        |> String.concat "\n"
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
          Printf.sprintf
            "    { 0x%08xU, 0x%08xU, %d, %d, 0x%08LXU, 0x%08LXU, { 0x%016LXULL, 0x%016LXULL }, %s_chk_%04x },"
            chunk_id next_chunk_id offset count canary entropy_seed junk0 junk1 name idx
        ) permuted_chunks
        |> String.concat "\n"
      in
      Printf.sprintf
{|%s
static const AsgardBytecodeChunk %s_chunks[%d] = {
%s
};

__attribute__((unused)) static uint64_t %s[%d];
__attribute__((unused)) static volatile int %s_assembled = 0;

__attribute__((unused)) static inline void %s_ensure_assembled(void) {
    if (__builtin_expect(!%s_assembled, 0)) {
        for (size_t _idx = 0; _idx < %d; ++_idx) {
            const AsgardBytecodeChunk* c = &%s_chunks[_idx];
            if (__builtin_expect(c->canary != (((c->chunk_id * 0xDEADU) + 0xCAFEU) & 0xFFFFFFFFU), 0)) {
                ASG_CHUNK_TRAP();
            }
            uint64_t k_dyn = 0x5877A56A11223344ULL ^ ((uint64_t)c->chunk_id * 0x9E3779B97F4A7C15ULL);
            for (size_t j = 0; j < c->word_count; ++j) {
                uint64_t word_key = k_dyn + ((uint64_t)j * 0x100000001B3ULL);
                %s[c->word_offset + j] = c->data[j] ^ word_key;
            }
        }
        ASG_CHUNK_BARRIER();
        %s_assembled = 1;
    }
}

#if defined(__GNUC__) || defined(__clang__)
__attribute__((constructor, unused)) static void %s_auto_init(void) {
    %s_ensure_assembled();
}
#endif

|}
        chunk_arrays
        name num_chunks chunk_table_entries
        name total_words
        name
        name name num_chunks name
        name
        name
        name name
  in

  match marked_fns with
  | [] ->
      let bc_formatted = format_fragmented_bytecode "embedded_bytecode" bytecode in
      let bc_header =
        Printf.sprintf "\n#include \"%s\"\n\n%s\n%s\n"
          header_name chunk_struct_def bc_formatted
      in
      let oc = open_out out_path in
      output_string oc (bc_header ^ c_src);
      close_out oc

  | [ single_fn ] when (match bytecodes with Some bcs -> List.length bcs <= 1 | None -> true) ->
      (* Backward-compatible single function path *)
      let bc_formatted = format_fragmented_bytecode "embedded_bytecode" bytecode in
      let bc_header =
        Printf.sprintf "\n#include \"%s\"\n\n%s\n%s\n"
          header_name chunk_struct_def bc_formatted
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
          Printf.sprintf "\n    embedded_bytecode_ensure_assembled();\n    %s;\n    return;\n" call_str
        else if is_ptr then
          Printf.sprintf "\n    embedded_bytecode_ensure_assembled();\n    return (%s)(uintptr_t)%s;\n" single_fn.ret_type call_str
        else
          Printf.sprintf "\n    embedded_bytecode_ensure_assembled();\n    return %s;\n" call_str
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
      Buffer.add_string header_buf (Printf.sprintf "\n#include \"%s\"\n\n%s\n" header_name chunk_struct_def);

      List.iteri (fun idx fn ->
        let fn_bc = find_bc_for_fn idx fn.fn_name in
        let arr_name = Printf.sprintf "embedded_bytecode_%s" (sanitize_ident fn.fn_name) in
        Buffer.add_string header_buf (format_fragmented_bytecode arr_name fn_bc)
      ) multi_fns;

      (* Fallback alias / first bytecode for embedded_bytecode symbol search *)
      let first_bc = match multi_fns with
        | hd :: _ -> find_bc_for_fn 0 hd.fn_name
        | [] -> bytecode
      in
      Buffer.add_string header_buf (format_fragmented_bytecode "embedded_bytecode" first_bc);

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
            Printf.sprintf "\n    %s_ensure_assembled();\n    %s;\n    return;\n" arr_name call_str
          else if is_ptr then
            Printf.sprintf "\n    %s_ensure_assembled();\n    return (%s)(uintptr_t)%s;\n" arr_name fn.ret_type call_str
          else
            Printf.sprintf "\n    %s_ensure_assembled();\n    return %s;\n" arr_name call_str
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
