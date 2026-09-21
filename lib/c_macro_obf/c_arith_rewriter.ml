open C_expr_lexer
open C_expr_parser

(** Detect if we're at a position that could start an expression statement.
    Rewrites expressions on the RHS of assignments and in return statements.
    Everything else is copied verbatim. *)
let rewrite_arithmetic_in_source ~prefix ~depth src =
  let toks = c_lex src in
  let n = Array.length toks in
  let src_len = String.length src in
  let out = Buffer.create (src_len * 2) in

  let emitted_char_pos = ref 0 in

  let emit_raw_until char_end =
    if char_end > !emitted_char_pos && char_end <= src_len then begin
      Buffer.add_string out (String.sub src !emitted_char_pos (char_end - !emitted_char_pos));
      emitted_char_pos := char_end
    end
  in

  let tok_start idx =
    if idx < n then let (_,s,_) = toks.(idx) in s else src_len
  in

  let ti = ref 0 in

  while !ti < n - 1 (* skip final TEOF *) do
    let (tok, _ts, te) = toks.(!ti) in
    match tok with
    | TStrLit _ | TCharLit _ ->
        (* String/char literal or comment: copy verbatim *)
        emit_raw_until te;
        incr ti
    | TIdent "return" ->
        (* emit 'return' verbatim, then a mandatory space *)
        emit_raw_until te;
        incr ti;
        let expr_char_start = tok_start !ti in
        let ti_before_expr = !ti in
        let (expr, ti_after) = parse_expr toks !ti in
        let raw_end = tok_start ti_after in
        if ti_after > ti_before_expr then begin
          let ws = String.sub src te (expr_char_start - te) in
          let ws_trimmed =
            String.concat "" (List.filter_map (fun c ->
              if c = ' ' || c = '\t' || c = '\n' || c = '\r'
              then Some (String.make 1 c)
              else None)
              (List.init (String.length ws) (String.get ws)))
          in
          Buffer.add_string out (if ws_trimmed = "" then " " else ws_trimmed);
          emitted_char_pos := expr_char_start;
          let rewritten = print_expr ~prefix ~depth ~mba:true expr in
          emitted_char_pos := raw_end;
          Buffer.add_string out rewritten;
          ti := ti_after
        end else
          incr ti
    | TEq | TAddEq | TSubEq | TAndEq | TOrEq | TXorEq | TMulEq | TDivEq ->
        emit_raw_until te;
        incr ti;
        let expr_char_start = tok_start !ti in
        let ti_before_expr = !ti in
        let (expr, ti_after) = parse_expr toks !ti in
        let raw_end = tok_start ti_after in
        if ti_after > ti_before_expr then begin
          let ws = String.sub src te (expr_char_start - te) in
          Buffer.add_string out ws;
          emitted_char_pos := expr_char_start;
          let rewritten = print_expr ~prefix ~depth ~mba:true expr in
          emitted_char_pos := raw_end;
          Buffer.add_string out rewritten;
          ti := ti_after
        end else
          incr ti
    | _ ->
        emit_raw_until te;
        incr ti
  done;
  emit_raw_until src_len;
  Buffer.contents out
