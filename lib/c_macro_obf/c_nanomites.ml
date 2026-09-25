open C_macro_config

(** Skip whitespace forward from position [i] in [s], return new index. *)
let skip_ws s i =
  let len = String.length s in
  let j = ref i in
  while !j < len && (s.[!j] = ' ' || s.[!j] = '\t' || s.[!j] = '\n' || s.[!j] = '\r') do
    incr j
  done;
  !j

(** Scan balanced braces starting at [i] (which must be '{').
    Returns the index just AFTER the matching '}'. *)
let scan_balanced_braces s i =
  let len = String.length s in
  let depth = ref 0 in
  let j = ref i in
  let in_str = ref false in
  let in_char = ref false in
  let escape = ref false in
  while !j < len && (not (!depth = 0 && !j > i)) do
    let c = s.[!j] in
    (if !escape then escape := false
     else match c with
       | '\\' when !in_str || !in_char -> escape := true
       | '"' when not !in_char -> in_str := not !in_str
       | '\'' when not !in_str -> in_char := not !in_char
       | '{' when not !in_str && not !in_char -> incr depth
       | '}' when not !in_str && not !in_char -> decr depth
       | _ -> ());
    incr j
  done;
  if !depth = 0 then !j else -1

(** Scan balanced parentheses starting at [i] (which must be '(').
    Returns the index just AFTER the matching ')'. *)
let scan_balanced_parens s i =
  let len = String.length s in
  let depth = ref 0 in
  let j = ref i in
  let in_str = ref false in
  let escape = ref false in
  while !j < len && (not (!depth = 0 && !j > i)) do
    let c = s.[!j] in
    (if !escape then escape := false
     else match c with
       | '\\' when !in_str -> escape := true
       | '"' -> in_str := not !in_str
       | '(' when not !in_str -> incr depth
       | ')' when not !in_str -> decr depth
       | _ -> ());
    incr j
  done;
  if !depth = 0 then !j else -1

(** One parsed nanomite site. *)
type nanomite_site = {
  ns_id         : int;
  ns_cond       : string;
  ns_then_fn    : string;
  ns_else_fn    : string;
  ns_then_src   : string;
  ns_else_src   : string;
  ns_key        : int;
  ns_has_return : bool;
}

(** Try to parse one [if (cond) { then } [else { else }]] starting at [pos].
    Returns (site, end_pos) or None. *)
let try_parse_if src pos rng_state seed_ref prefix =
  let len = String.length src in
  if pos + 2 > len then None
  else if not (String.sub src pos 2 = "if") then None
  else
    let before_ok =
      pos = 0 ||
      (let c = src.[pos-1] in
       not (c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || c >= '0' && c <= '9' || c = '_'))
    in
    if not before_ok then None
    else
      let after = skip_ws src (pos + 2) in
      if after >= len || src.[after] <> '(' then None
      else
        let cond_end = scan_balanced_parens src after in
        if cond_end < 0 then None
        else
          let cond_text = String.sub src (after + 1) (cond_end - after - 2) in
          let body_start = skip_ws src cond_end in
          if body_start >= len || src.[body_start] <> '{' then None
          else
            let then_end = scan_balanced_braces src body_start in
            if then_end < 0 then None
            else
              let then_body = String.sub src (body_start + 1) (then_end - body_start - 2) in
              let after_then = skip_ws src then_end in
              let else_body, total_end =
                if after_then + 4 <= len && String.sub src after_then 4 = "else" &&
                   (after_then + 4 >= len ||
                    (let c = src.[after_then + 4] in
                     c = ' ' || c = '\t' || c = '\n' || c = '\r' || c = '{'))
                then
                  let else_brace = skip_ws src (after_then + 4) in
                  if else_brace >= len || src.[else_brace] <> '{' then ("", then_end)
                  else
                    let else_end = scan_balanced_braces src else_brace in
                    if else_end < 0 then ("", then_end)
                    else
                      let eb = String.sub src (else_brace + 1) (else_end - else_brace - 2) in
                      (eb, else_end)
                else ("", then_end)
              in
              let id = (xorshift32 !seed_ref) land 0xFFFF in
              seed_ref := xorshift32 !seed_ref;
              let key = Int64.to_int (Int64.logand (rand_u64 rng_state) 0x7FFFFFFFL) in
              let idx = !seed_ref land 0x7FFFF in
              let then_fn = Printf.sprintf "%sasgbranch_t_%d" prefix idx in
              let else_fn = Printf.sprintf "%sasgbranch_f_%d" prefix idx in
              let contains_return body =
                let blen = String.length body in
                let found = ref false in
                let bi = ref 0 in
                while !bi + 6 <= blen && not !found do
                  if String.sub body !bi 6 = "return" then
                    let before_ok = !bi = 0 ||
                      (let c = body.[!bi - 1] in
                       not (c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || c >= '0' && c <= '9' || c = '_'))
                    in
                    let after_idx = !bi + 6 in
                    let after_ok = after_idx >= blen ||
                      (let c = body.[after_idx] in
                       not (c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || c >= '0' && c <= '9' || c = '_'))
                    in
                    if before_ok && after_ok then found := true else incr bi
                  else incr bi
                done;
                !found
              in
              let has_return = contains_return then_body || contains_return else_body in
              Some ({
                ns_id         = id;
                ns_cond       = cond_text;
                ns_then_fn    = then_fn;
                ns_else_fn    = else_fn;
                ns_then_src   = then_body;
                ns_else_src   = else_body;
                ns_key        = key;
                ns_has_return = has_return;
              }, total_end)

(** Lift all if-statements in [src] to nanomites.
    Returns (transformed_src, list_of_sites). *)
let lift_ifs_to_nanomites ?(config = default_config) src =
  let p = config.macro_prefix in
  let rng = Random.State.make [| config.seed lxor 0xDEADC0DE |] in
  let seed_ref = ref (config.seed lxor 0x5A5A5A5A) in
  let len = String.length src in
  let buf = Buffer.create (len * 2) in
  let sites = ref [] in
  let in_marker = ref false in
  let i = ref 0 in
  while !i < len do
    let c = src.[!i] in
    (* Marker detection: preserve VM virtualization regions *)
    if !i + 12 <= len && String.sub src !i 12 = "ASGARD_BEGIN" then begin
      in_marker := true;
      Buffer.add_char buf c;
      incr i
    end
    else if !i + 10 <= len && String.sub src !i 10 = "ASGARD_END" then begin
      in_marker := false;
      Buffer.add_char buf c;
      incr i
    end
    else if c = '/' && !i + 1 < len && src.[!i + 1] = '/' then begin
      while !i < len && src.[!i] <> '\n' do
        Buffer.add_char buf src.[!i]; incr i
      done
    end
    else if c = '/' && !i + 1 < len && src.[!i + 1] = '*' then begin
      Buffer.add_char buf src.[!i];
      Buffer.add_char buf src.[!i + 1];
      i := !i + 2;
      while !i + 1 < len && not (src.[!i] = '*' && src.[!i + 1] = '/') do
        Buffer.add_char buf src.[!i]; incr i
      done;
      if !i + 1 < len then begin
        Buffer.add_char buf src.[!i];
        Buffer.add_char buf src.[!i + 1];
        i := !i + 2
      end
    end
    else if c = '"' then begin
      Buffer.add_char buf c; incr i;
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
        else begin
          incr i
        end
      done
    end
    else if c = '#' then begin
      while !i < len && src.[!i] <> '\n' do
        Buffer.add_char buf src.[!i]; incr i
      done
    end
    else if (not !in_marker) && c = 'i' && !i + 1 < len && src.[!i + 1] = 'f' then begin
      match try_parse_if src !i rng seed_ref p with
      | None ->
        Buffer.add_char buf c; incr i
      | Some (site, end_pos) ->
        if site.ns_has_return then
          Buffer.add_string buf
            (Printf.sprintf "ASG_NANOMITE_DISPATCH(%d, (%s)); ASG_NANOMITE_CHECK_RET();" site.ns_id site.ns_cond)
        else
          Buffer.add_string buf
            (Printf.sprintf "ASG_NANOMITE_DISPATCH(%d, (%s));" site.ns_id site.ns_cond);
        sites := site :: !sites;
        i := end_pos
    end
    else begin
      Buffer.add_char buf c; incr i
    end
  done;
  (Buffer.contents buf, List.rev !sites)

(** Strip [return expr;] and bare [return;] from a C body string.
    Branch functions are [void], so we replace:
    - [return <expr>;] → [(void)(<expr>);]
    - [return;]        → [(void)0;] *)
let strip_returns_from_body body =
  let len = String.length body in
  let buf = Buffer.create (len + 16) in
  let i = ref 0 in
  while !i < len do
    (* Look for "return" keyword *)
    if !i + 6 <= len && String.sub body !i 6 = "return" &&
       (!i = 0 ||
        (let c = body.[!i - 1] in
         not (c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || c >= '0' && c <= '9' || c = '_')))
    then begin
      let after = ref (!i + 6) in
      (* skip optional whitespace *)
      while !after < len && (body.[!after] = ' ' || body.[!after] = '\t') do incr after done;
      if !after < len && body.[!after] = ';' then begin
        (* bare return; → _asg_nanomite_returned = 1; return; *)
        Buffer.add_string buf "_asg_nanomite_returned = 1; return;";
        i := !after + 1
      end else begin
        (* return <expr>; — find the matching semicolon at depth 0 *)
        let depth = ref 0 in
        let expr_start = !after in
        let sc_pos = ref (-1) in
        let j = ref expr_start in
        while !j < len && !sc_pos = -1 do
          let c = body.[!j] in
          (match c with
           | '(' | '[' | '{' -> incr depth
           | ')' | ']' | '}' -> decr depth
           | ';' when !depth = 0 -> sc_pos := !j
           | _ -> ());
          incr j
        done;
        if !sc_pos >= 0 then begin
          let expr = String.sub body expr_start (!sc_pos - expr_start) in
          let trimmed = String.trim expr in
          if trimmed = "" then
            Buffer.add_string buf "_asg_nanomite_returned = 1; return;"
          else
            Buffer.add_string buf (Printf.sprintf "_asg_nanomite_retval = (uint64_t)(%s); _asg_nanomite_returned = 1; return;" trimmed);
          i := !sc_pos + 1
        end else begin
          (* malformed: copy verbatim *)
          Buffer.add_string buf "return";
          i := !i + 6
        end
      end
    end
    else begin
      Buffer.add_char buf body.[!i];
      incr i
    end
  done;
  Buffer.contents buf

(** Extract a leading block of preprocessor directives (#include, #define, etc.)
    from the beginning of a source string.
    Returns (directives_block, rest_of_source). *)
let split_leading_directives src =
  let len = String.length src in
  let i = ref 0 in
  let end_of_directives = ref 0 in
  (* Walk through any leading lines that are blank or start with '#' *)
  let continue_scan = ref true in
  while !continue_scan && !i < len do
    (* skip whitespace/blank lines *)
    while !i < len && (src.[!i] = ' ' || src.[!i] = '\t' || src.[!i] = '\n' || src.[!i] = '\r') do
      incr i
    done;
    if !i < len && src.[!i] = '#' then begin
      (* consume until end of line *)
      while !i < len && src.[!i] <> '\n' do incr i done;
      if !i < len then incr i;  (* consume the newline *)
      end_of_directives := !i
    end else
      continue_scan := false
  done;
  let directives = String.sub src 0 !end_of_directives in
  let rest = String.sub src !end_of_directives (len - !end_of_directives) in
  (directives, rest)

(** Given nanomite sites, emit branch functions + __attribute__((constructor))
    auto-registration block. *)
let emit_nanomite_preamble ?(config = default_config) sites =
  let p = config.macro_prefix in
  let buf = Buffer.create 1024 in
  Buffer.add_string buf "static volatile int _asg_nanomite_returned = 0;\n";
  Buffer.add_string buf "static volatile uint64_t _asg_nanomite_retval = 0;\n";
  Buffer.add_string buf "#define ASG_NANOMITE_CHECK_RET() do { if (_asg_nanomite_returned) { int _asg_r = (int)_asg_nanomite_retval; _asg_nanomite_returned = 0; return _asg_r; } } while(0)\n\n";
  List.iter (fun s ->
    let then_body = strip_returns_from_body s.ns_then_src in
    Buffer.add_string buf
      (Printf.sprintf "static void __attribute__((noinline)) %s(void) {\n%s\n}\n"
         s.ns_then_fn then_body);
    let else_raw = if String.trim s.ns_else_src = "" then "    (void)0;" else s.ns_else_src in
    let else_body = strip_returns_from_body else_raw in
    Buffer.add_string buf
      (Printf.sprintf "static void __attribute__((noinline)) %s(void) {\n%s\n}\n"
         s.ns_else_fn else_body);
  ) sites;
  Buffer.add_char buf '\n';
  Buffer.add_string buf "__attribute__((constructor)) static void _asg_nanomite_auto_init_(void) {\n";
  Buffer.add_string buf (Printf.sprintf "    %sNANOMITE_INIT();\n" p);
  List.iter (fun s ->
    Buffer.add_string buf
      (Printf.sprintf "    %sNANOMITE_REGISTER(%d, %s, %s, 0x%Xu);\n"
         p s.ns_id s.ns_then_fn s.ns_else_fn s.ns_key)
  ) sites;
  Buffer.add_string buf "}\n\n";
  Buffer.contents buf

(** Fully lift a C source string: if/else blocks → nanomites.
    Returns (transformed_body, preamble_to_prepend).
    The preamble already includes the leading #include/#define block from the
    original source so that branch functions compile without missing declarations. *)
let lift_nanomites_in_source ?(config = default_config) src =
  (* Split off leading preprocessor directives so branch functions can see them *)
  let (leading_directives, body) = split_leading_directives src in
  let (transformed_body, sites) = lift_ifs_to_nanomites ~config body in
  if sites = [] then
    (* No if found: return full source unchanged, no preamble *)
    (src, "")
  else begin
    let fn_preamble = emit_nanomite_preamble ~config sites in
    (* Preamble = leading directives + branch functions + constructor *)
    let preamble = leading_directives ^ "\n" ^ fn_preamble in
    (* transformed is the directives-stripped body with if→dispatch *)
    (transformed_body, preamble)
  end
