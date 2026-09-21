(* ─── Lexer tokens ──────────────────────────────────────────────────────── *)
type c_tok =
  | TPlus | TMinus | TStar | TSlash | TPercent
  | TAmpersand | TPipe | TCaret | TTilde | TBang
  | TLShift | TRShift
  | TLParen | TRParen | TLBracket | TRBracket | TLBrace | TRBrace
  | TComma | TSemicolon | TColon | TQuestion
  | TEq | TAddEq | TSubEq | TAndEq | TOrEq | TXorEq | TMulEq | TDivEq
  | TArrow | TDot
  | TEqEq | TNotEq | TLe | TGe | TLt | TGt
  | TAnd | TOr  (* && || *)
  | TIdent of string
  | TIntLit of string   (* keep verbatim so we never lose suffixes, covers floats too *)
  | TCharLit of string
  | TStrLit of string   (* content including quotes *)
  | TIncDec of string   (* ++ or -- *)
  | TEOF

let c_lex src =
  (* Returns array of (token, start_pos, end_pos) for whole src *)
  let len = String.length src in
  let result = ref [] in
  let push tok s e = result := (tok, s, e) :: !result in
  let i = ref 0 in
  let read_while pred =
    let start = !i in
    while !i < len && pred src.[!i] do incr i done;
    String.sub src start (!i - start)
  in
  let is_ident_start c = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c = '_' in
  let is_ident c = is_ident_start c || (c >= '0' && c <= '9') in
  let is_digit c = c >= '0' && c <= '9' in
  let is_hex c = is_digit c || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F') in
  while !i < len do
    let start = !i in
    let c = src.[!i] in
    if c = ' ' || c = '\t' || c = '\n' || c = '\r' then incr i
    else if c = '/' && !i + 1 < len && src.[!i + 1] = '/' then begin
      (* line comment *)
      while !i < len && src.[!i] <> '\n' do incr i done;
      push (TStrLit (String.sub src start (!i - start))) start !i
    end
    else if c = '/' && !i + 1 < len && src.[!i + 1] = '*' then begin
      i := !i + 2;
      while !i + 1 < len && not (src.[!i] = '*' && src.[!i+1] = '/') do incr i done;
      if !i + 1 < len then i := !i + 2;
      push (TStrLit (String.sub src start (!i - start))) start !i
    end
    else if c = '"' then begin
      incr i;
      let escaped = ref false in
      while !i < len && (src.[!i] <> '"' || !escaped) do
        if !escaped then escaped := false
        else if src.[!i] = '\\' then escaped := true;
        incr i
      done;
      if !i < len then incr i;
      push (TStrLit (String.sub src start (!i - start))) start !i
    end
    else if c = '\'' then begin
      incr i;
      let escaped = ref false in
      while !i < len && (src.[!i] <> '\'' || !escaped) do
        if !escaped then escaped := false
        else if src.[!i] = '\\' then escaped := true;
        incr i
      done;
      if !i < len then incr i;
      push (TCharLit (String.sub src start (!i - start))) start !i
    end
    else if c = '#' then begin
      (* preprocessor line: consume to end of logical line *)
      while !i < len && src.[!i] <> '\n' do incr i done;
      push (TStrLit (String.sub src start (!i - start))) start !i
    end
    else if is_ident_start c then begin
      let name = read_while is_ident in
      push (TIdent name) start !i
    end
    else if is_digit c || (c = '.' && !i + 1 < len && is_digit src.[!i+1]) then begin
      (* integer or float literal with optional suffixes *)
      let is_0x = c = '0' && !i + 1 < len && (src.[!i+1] = 'x' || src.[!i+1] = 'X') in
      if is_0x then begin
        i := !i + 2;
        let _ = read_while is_hex in ()
      end else begin
        let _ = read_while is_digit in
        if !i < len && src.[!i] = '.' then begin
          incr i;
          let _ = read_while is_digit in ()
        end;
        if !i < len && (src.[!i] = 'e' || src.[!i] = 'E') then begin
          incr i;
          if !i < len && (src.[!i] = '+' || src.[!i] = '-') then incr i;
          let _ = read_while is_digit in ()
        end
      end;
      (* consume suffixes u U l L f F *)
      while !i < len && (let ch = src.[!i] in
        ch='u'||ch='U'||ch='l'||ch='L'||ch='f'||ch='F') do incr i done;
      let lit = String.sub src start (!i - start) in
      push (TIntLit lit) start !i
    end
    else begin
      (* operators and punctuation *)
      let tok, advance =
        match c with
        | '+' when !i+1 < len && src.[!i+1] = '+' -> TIncDec "++", 2
        | '+' when !i+1 < len && src.[!i+1] = '=' -> TAddEq, 2
        | '+' -> TPlus, 1
        | '-' when !i+1 < len && src.[!i+1] = '-' -> TIncDec "--", 2
        | '-' when !i+1 < len && src.[!i+1] = '=' -> TSubEq, 2
        | '-' when !i+1 < len && src.[!i+1] = '>' -> TArrow, 2
        | '-' -> TMinus, 1
        | '*' when !i+1 < len && src.[!i+1] = '=' -> TMulEq, 2
        | '*' -> TStar, 1
        | '/' when !i+1 < len && src.[!i+1] = '=' -> TDivEq, 2
        | '/' -> TSlash, 1
        | '%' -> TPercent, 1
        | '&' when !i+1 < len && src.[!i+1] = '&' -> TAnd, 2
        | '&' when !i+1 < len && src.[!i+1] = '=' -> TAndEq, 2
        | '&' -> TAmpersand, 1
        | '|' when !i+1 < len && src.[!i+1] = '|' -> TOr, 2
        | '|' when !i+1 < len && src.[!i+1] = '=' -> TOrEq, 2
        | '|' -> TPipe, 1
        | '^' when !i+1 < len && src.[!i+1] = '=' -> TXorEq, 2
        | '^' -> TCaret, 1
        | '~' -> TTilde, 1
        | '!' when !i+1 < len && src.[!i+1] = '=' -> TNotEq, 2
        | '!' -> TBang, 1
        | '<' when !i+1 < len && src.[!i+1] = '<' -> TLShift, 2
        | '<' when !i+1 < len && src.[!i+1] = '=' -> TLe, 2
        | '<' -> TLt, 1
        | '>' when !i+1 < len && src.[!i+1] = '>' -> TRShift, 2
        | '>' when !i+1 < len && src.[!i+1] = '=' -> TGe, 2
        | '>' -> TGt, 1
        | '=' when !i+1 < len && src.[!i+1] = '=' -> TEqEq, 2
        | '=' -> TEq, 1
        | '(' -> TLParen, 1
        | ')' -> TRParen, 1
        | '[' -> TLBracket, 1
        | ']' -> TRBracket, 1
        | '{' -> TLBrace, 1
        | '}' -> TRBrace, 1
        | ',' -> TComma, 1
        | ';' -> TSemicolon, 1
        | ':' -> TColon, 1
        | '?' -> TQuestion, 1
        | '.' -> TDot, 1
        | _ -> TIdent (String.make 1 c), 1
      in
      i := !i + advance;
      push tok start !i
    end
  done;
  push TEOF !i !i;
  Array.of_list (List.rev !result)
