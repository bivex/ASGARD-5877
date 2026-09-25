(** C_macro_obf — C/C++ Preprocessor & Source-Level Macro Obfuscation Engine. *)

type config = C_macro_config.config = {
  seed : int;
  mba_depth : int;
  obfuscate_strings : bool;
  obfuscate_constants : bool;
  obfuscate_arithmetic : bool;
  inject_opaque_predicates : bool;
  api_hashing : bool;
  anti_debug : bool;
  signal_dispatch : bool;
  nanomites : bool;
  timing_guard : bool;
  timing_threshold_ticks : int64;
  macro_prefix : string;
}

let default_config = C_macro_config.default_config
type feature_usage = C_macro_header.feature_usage = {
  has_api_hashing : bool;
  has_anti_debug : bool;
  has_signal_dispatch : bool;
  has_timing_guard : bool;
  has_nanomites : bool;
}
let detect_features = C_macro_header.detect_features
let generate_header = C_macro_header.generate_header

let obfuscate_string_literal ~prefix ~seed s =
  let len = String.length s in
  let key = (C_macro_config.xorshift32 (seed + len * 31)) land 0x7FFFFFFF in
  let bytes = Buffer.create (len * 6 + 10) in
  Buffer.add_string bytes "{ ";
  for i = 0 to len - 1 do
    let orig_byte = Char.code s.[i] in
    let k = ((key lxor (i * 0x5D)) land 0xFF) in
    let enc_byte = orig_byte lxor k in
    if i > 0 then Buffer.add_string bytes ", ";
    Buffer.add_string bytes (Printf.sprintf "0x%02X" enc_byte)
  done;
  if len = 0 then Buffer.add_string bytes "0x00";
  Buffer.add_string bytes " }";
  Printf.sprintf "%sSTR(((const uint8_t[])%s), %d, 0x%XU)" prefix (Buffer.contents bytes) len key

let obfuscate_constant_i64 ~prefix ~seed n =
  let rng = Random.State.make [| seed; Int64.to_int (Int64.logand n 0x7FFFFFFFL) |] in
  let k1 = C_macro_config.rand_u64 rng in
  let k2 = C_macro_config.rand_u64 rng in
  let c1 = Int64.logxor n k1 in
  Printf.sprintf "%sBLIND_I64(0x%LXULL, 0x%LXULL, 0x%LXULL)" prefix c1 k1 k2

let lift_nanomites_in_source = C_nanomites.lift_nanomites_in_source
let rewrite_arithmetic_in_source = C_arith_rewriter.rewrite_arithmetic_in_source

(** Transform a complete C source code string *)
let obfuscate_source ?(config = default_config) src =
  let p = config.macro_prefix in
  let (lifted_src, nanomite_preamble) =
    if config.nanomites then
      lift_nanomites_in_source ~config src
    else
      (src, "")
  in

  let arith_rewritten =
    if config.obfuscate_arithmetic then
      rewrite_arithmetic_in_source ~prefix:p ~depth:config.mba_depth lifted_src
    else
      lifted_src
  in

  let len = String.length arith_rewritten in
  let buf = Buffer.create (len * 2) in
  let seed_seq = ref config.seed in

  let next_seed () =
    seed_seq := C_macro_config.xorshift32 !seed_seq;
    !seed_seq
  in

  Buffer.add_string buf "/* Protected by ASGARD-5877 C Macro Obfuscator */\n";
  Buffer.add_string buf "#include \"asgard_obf.h\"\n\n";
  if nanomite_preamble <> "" then
    Buffer.add_string buf nanomite_preamble;

  let src = arith_rewritten in

  let i = ref 0 in
  while !i < len do
    let c = src.[!i] in
    if c = '/' && !i + 1 < len && src.[!i + 1] = '/' then begin
      while !i < len && src.[!i] <> '\n' do
        Buffer.add_char buf src.[!i];
        incr i
      done
    end
    else if c = '/' && !i + 1 < len && src.[!i + 1] = '*' then begin
      Buffer.add_char buf src.[!i];
      Buffer.add_char buf src.[!i + 1];
      i := !i + 2;
      while !i + 1 < len && not (src.[!i] = '*' && src.[!i + 1] = '/') do
        Buffer.add_char buf src.[!i];
        incr i
      done;
      if !i + 1 < len then begin
        Buffer.add_char buf src.[!i];
        Buffer.add_char buf src.[!i + 1];
        i := !i + 2
      end
    end
    else if c = '#' then begin
      let in_dir = ref true in
      while !i < len && !in_dir do
        let ch = src.[!i] in
        Buffer.add_char buf ch;
        incr i;
        if ch = '\n' then begin
          let p = ref (!i - 2) in
          while !p >= 0 && (src.[!p] = ' ' || src.[!p] = '\t' || src.[!p] = '\r') do
            decr p
          done;
          if !p < 0 || src.[!p] <> '\\' then
            in_dir := false
        end
      done
    end
    else if c = '\'' then begin
      Buffer.add_char buf c;
      incr i;
      let escaped = ref false in
      let closed = ref false in
      while !i < len && not !closed do
        let sc = src.[!i] in
        Buffer.add_char buf sc;
        if !escaped then begin
          escaped := false;
          incr i
        end
        else if sc = '\\' then begin
          escaped := true;
          incr i
        end
        else if sc = '\'' then begin
          closed := true;
          incr i
        end
        else incr i
      done
    end
    else if c = '"' && config.obfuscate_strings then begin
      let is_marker_tag () =
        let p = ref (!i - 1) in
        while !p >= 0 && (src.[!p] = ' ' || src.[!p] = '\t' || src.[!p] = '\n' || src.[!p] = '\r' || src.[!p] = '(') do
          decr p
        done;
        let end_id = !p in
        while !p >= 0 && (let ch = src.[!p] in (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9') || ch = '_') do
          decr p
        done;
        let start_id = !p + 1 in
        if end_id >= start_id then
          let id = String.sub src start_id (end_id - start_id + 1) in
          String.starts_with ~prefix:"ASGARD_BEGIN" id
        else false
      in
      if is_marker_tag () then begin
        Buffer.add_char buf c;
        incr i;
        let escaped = ref false in
        let closed = ref false in
        while !i < len && not !closed do
          let sc = src.[!i] in
          Buffer.add_char buf sc;
          if !escaped then begin
            escaped := false;
            incr i
          end
          else if sc = '\\' then begin
            escaped := true;
            incr i
          end
          else if sc = '"' then begin
            closed := true;
            incr i
          end
          else incr i
        done
      end else begin
        incr i;
        let str_buf = Buffer.create 32 in
        let closed = ref false in
        while !i < len && not !closed do
          let sc = src.[!i] in
          if sc = '"' then begin
            closed := true;
            incr i
          end else if sc = '\\' then begin
            incr i;
            if !i < len then begin
              let esc = src.[!i] in
              match esc with
              | 'n' -> Buffer.add_char str_buf '\n'; incr i
              | 't' -> Buffer.add_char str_buf '\t'; incr i
              | 'r' -> Buffer.add_char str_buf '\r'; incr i
              | 'b' -> Buffer.add_char str_buf '\b'; incr i
              | 'f' -> Buffer.add_char str_buf '\012'; incr i
              | 'v' -> Buffer.add_char str_buf '\011'; incr i
              | 'a' -> Buffer.add_char str_buf '\007'; incr i
              | '\\' -> Buffer.add_char str_buf '\\'; incr i
              | '"' -> Buffer.add_char str_buf '"'; incr i
              | '\'' -> Buffer.add_char str_buf '\''; incr i
              | '?' -> Buffer.add_char str_buf '?'; incr i
              | '0' .. '7' ->
                  let oct_str = Buffer.create 3 in
                  Buffer.add_char oct_str esc;
                  incr i;
                  if !i < len && (let ch = src.[!i] in ch >= '0' && ch <= '7') then begin
                    Buffer.add_char oct_str src.[!i];
                    incr i;
                    if !i < len && (let ch = src.[!i] in ch >= '0' && ch <= '7') then begin
                      Buffer.add_char oct_str src.[!i];
                      incr i
                    end
                  end;
                  let oct_val = try int_of_string ("0o" ^ Buffer.contents oct_str) with _ -> 0 in
                  Buffer.add_char str_buf (Char.chr (oct_val land 0xFF))
              | 'x' when !i + 1 < len &&
                         (let is_hex ch = (ch >= '0' && ch <= '9') || (ch >= 'a' && ch <= 'f') || (ch >= 'A' && ch <= 'F') in
                          is_hex src.[!i + 1]) ->
                  incr i;
                  let hex_str = Buffer.create 2 in
                  Buffer.add_char hex_str src.[!i];
                  incr i;
                  if !i < len && (let ch = src.[!i] in (ch >= '0' && ch <= '9') || (ch >= 'a' && ch <= 'f') || (ch >= 'A' && ch <= 'F')) then begin
                    Buffer.add_char hex_str src.[!i];
                    incr i
                  end;
                  let v = try int_of_string ("0x" ^ Buffer.contents hex_str) with _ -> 0 in
                  Buffer.add_char str_buf (Char.chr (v land 0xFF))
              | other ->
                  Buffer.add_char str_buf other;
                  incr i
            end
          end else begin
            Buffer.add_char str_buf sc;
            incr i
          end
        done;
        let raw_str = Buffer.contents str_buf in
        let obf_str = obfuscate_string_literal ~prefix:p ~seed:(next_seed ()) raw_str in
        Buffer.add_string buf obf_str
      end
    end
    else begin
      Buffer.add_char buf c;
      incr i
    end
  done;
  Buffer.contents buf

(** Transform a C source file on disk *)
let transform_file ?(config = default_config) ~in_file ~out_file ~header_file () =
  try
    let ensure_dir p =
      let d = Filename.dirname p in
      if d <> "" && d <> "." && not (Sys.file_exists d) then
        try Sys.mkdir d 0o755 with Sys_error _ -> ()
    in
    ensure_dir out_file;
    (match header_file with Some h -> ensure_dir h | None -> ());

    let ic = open_in in_file in
    let len = in_channel_length ic in
    let content = really_input_string ic len in
    close_in ic;

    let obf_content = obfuscate_source ~config content in
    let oc = open_out out_file in
    output_string oc obf_content;
    close_out oc;

    (match header_file with
    | Some h_path ->
        let hoc = open_out h_path in
        output_string hoc (generate_header ~config ~source:obf_content ());
        close_out hoc
    | None -> ());

    Ok ()
  with exn ->
    Error (Printexc.to_string exn)
