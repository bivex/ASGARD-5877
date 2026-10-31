open C_expr_lexer
open C_expr_parser

(* ─── FP-name collection ────────────────────────────────────────────────────
   Collects every identifier declared with a floating-point type in the
   translation unit: variables, struct/class members, parameters, plus
   `auto` names whose initializer mentions an already-known FP name or an
   FP literal (iterated a few times to follow short auto chains). The set
   feeds expr_may_be_fp so MBA rewriting skips FP-tainted expressions. *)
let collect_fp_names (toks : (c_tok * int * int) array) : (string, unit) Hashtbl.t =
  let n = Array.length toks in
  let fp = Hashtbl.create 64 in
  let is_kw = function
    | TIdent s ->
        s = "double" || s = "float" || s = "long" || s = "const"
        || s = "volatile" || s = "auto" || s = "static" || s = "extern"
        || s = "register" || s = "inline" || s = "restrict" || s = "constexpr"
        || s = "signed" || s = "unsigned" || s = "struct" || s = "union"
        || s = "enum" || s = "typename" || s = "mutable"
    | _ -> false
  in
  let is_fp_kw = function
    | TIdent s -> s = "double" || s = "float"
    | _ -> false
  in
  let is_decl_end = function
    | TSemicolon | TEq | TLParen | TLBrace | TRParen -> true
    | _ -> false
  in
  (* Pass A: declarator names following double/float.
     Stops at '=' so initializer expressions are not harvested; each
     declaration site (including each parameter) triggers its own scan. *)
  for i = 0 to n - 1 do
    if is_fp_kw (let (t, _, _) = toks.(i) in t) then begin
      let j = ref (i + 1) in
      (* skip pointer/reference/qualifier decoration *)
      while !j < n && (match (let (t, _, _) = toks.(!j) in t) with
        | TStar | TAmpersand -> true
        | t -> is_kw t && not (is_fp_kw t)) do incr j done;
      while !j < n do
        match (let (t, _, _) = toks.(!j) in t) with
        | TIdent name when not (is_kw (TIdent name)) ->
            Hashtbl.replace fp name ();
            incr j;
            (* arrays: skip [N] then continue for `double a[4], b;` *)
            (match (let (t, _, _) = toks.(!j) in t) with
             | TLBracket ->
                 while !j < n && (let (t, _, _) = toks.(!j) in t) <> TRBracket do incr j done;
                 if !j < n then incr j
             | _ -> ());
            if !j < n && (let (t, _, _) = toks.(!j) in t) = TComma then incr j
            else j := n
        | _ -> j := n
      done
    end
  done;
  (* Pass B: propagate through `auto name = <init>;` (few fixed-point rounds) *)
  for _round = 1 to 3 do
    for i = 0 to n - 2 do
      let t0 = let (t, _, _) = toks.(i) in t in
      let t1 = let (t, _, _) = toks.(i + 1) in t in
      match t0, t1 with
      | TIdent "auto", TIdent name when not (Hashtbl.mem fp name) ->
          let j = ref (i + 2) in
          while !j < n && (match (let (t, _, _) = toks.(!j) in t) with
            | TEq | TStar | TAmpersand -> true | _ -> false) do incr j done;
          if !j < n && (let (t, _, _) = toks.(!j) in t) = TEq then begin
            let tainted = ref false in
            while !j < n && not (is_decl_end (let (t, _, _) = toks.(!j) in t)) do
              match toks.(!j) with
              | (TIntLit lit, _, _) -> if is_float_literal lit then tainted := true
              | (TIdent id, _, _) -> if Hashtbl.mem fp id then tainted := true
              | _ -> ()
              ; incr j
            done;
            if !tainted then Hashtbl.replace fp name ()
          end
      | _ -> ()
    done
  done;
  fp

let can_rewrite_range toks start_idx end_idx n =
  if start_idx >= end_idx || start_idx >= n then false
  else
    let (first_tok, _, _) = toks.(start_idx) in
    match first_tok with
    | TLBracket -> false (* C++ lambda introduction [&] or attribute [[...]] *)
    | _ ->
        let has_braces = ref false in
        for i = start_idx to end_idx - 1 do
          let (t, _, _) = toks.(i) in
          match t with
          | TLBrace | TRBrace -> has_braces := true
          | _ -> ()
        done;
        if !has_braces then false
        else if end_idx < n then
          let (tok_after, _, _) = toks.(end_idx) in
          match tok_after with
          | TSemicolon | TComma | TRParen | TRBracket -> true
          | _ -> false
        else true

(** Detect if we're at a position that could start an expression statement.
    Rewrites expressions on the RHS of assignments and in return statements.
    Everything else is copied verbatim. *)
let rewrite_arithmetic_in_source ~prefix ~depth src =
  let toks = c_lex src in
  let n = Array.length toks in
  let src_len = String.length src in
  let out = Buffer.create (src_len * 2) in
  let fp_names = collect_fp_names toks in

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
        if ti_after > ti_before_expr && can_rewrite_range toks ti_before_expr ti_after n then begin
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
          let mba_ok = not (expr_may_be_fp fp_names expr) in
          let rewritten = print_expr ~prefix ~depth ~mba:mba_ok expr in
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
        if ti_after > ti_before_expr && can_rewrite_range toks ti_before_expr ti_after n then begin
          let ws = String.sub src te (expr_char_start - te) in
          Buffer.add_string out ws;
          emitted_char_pos := expr_char_start;
          let mba_ok = not (expr_may_be_fp fp_names expr) in
          let rewritten = print_expr ~prefix ~depth ~mba:mba_ok expr in
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
