open C_expr_lexer

(* ─── Simple C-expression AST (only for rewriting arithmetic) ──────────── *)
type c_expr =
  | ELit   of string           (* verbatim token *)
  | EIdent of string
  | EParen of c_expr
  | ECall  of c_expr * c_expr list
  | EIndex of c_expr * c_expr
  | EField of c_expr * string * bool   (* e.field or e->field (bool=arrow) *)
  | EPostfix of c_expr * string        (* ++ -- *)
  | EPrefix of string * c_expr         (* ++ -- & * ~ ! - + *)
  | ECast  of string * c_expr          (* (type) expr *)
  | EBinop of string * c_expr * c_expr
  | ETernary of c_expr * c_expr * c_expr

(* ─── Printer with MBA macro substitution ────────────────────────────────── *)
let rec print_expr ~prefix ~depth ~mba expr =
  let sub = print_expr ~prefix ~depth:(depth - 1) ~mba in
  match expr with
  | ELit s | EIdent s -> s
  | EParen e -> "(" ^ sub e ^ ")"
  | ECall (f, args) ->
      sub f ^ "(" ^ String.concat ", " (List.map sub args) ^ ")"
  | EIndex (e, idx) -> sub e ^ "[" ^ sub idx ^ "]"
  | EField (e, name, arrow) ->
      sub e ^ (if arrow then "->" else ".") ^ name
  | EPostfix (e, op) -> sub e ^ op
  | EPrefix (op, e) -> op ^ sub e
  | ECast (ty, e) -> "(" ^ ty ^ ")" ^ sub e
  | ETernary (cond, t, f) ->
      sub cond ^ " ? " ^ sub t ^ " : " ^ sub f
  | EBinop (op, a, b) ->
      if mba && depth > 0 then begin
        let sa = sub a and sb = sub b in
        match op with
        | "+"  -> Printf.sprintf "%sMBA_ADD(%s, %s)" prefix sa sb
        | "-"  -> Printf.sprintf "%sMBA_SUB(%s, %s)" prefix sa sb
        | "^"  -> Printf.sprintf "%sMBA_XOR(%s, %s)" prefix sa sb
        | "&"  -> Printf.sprintf "%sMBA_AND(%s, %s)" prefix sa sb
        | "|"  -> Printf.sprintf "%sMBA_OR(%s, %s)"  prefix sa sb
        | _    -> sa ^ " " ^ op ^ " " ^ sb
      end else
        sub a ^ " " ^ op ^ " " ^ sub b

(* ─── Recursive-descent parser ──────────────────────────────────────────── *)

(* Returns (expr, next_token_index) *)
let parse_expr toks start_idx =
  let n = Array.length toks in
  let pos = ref start_idx in
  let peek () = if !pos < n then let (t,_,_) = toks.(!pos) in t else TEOF in
  let advance () = incr pos in
  let consume () =
    let (t,s,e) = toks.(!pos) in
    incr pos; (t,s,e)
  in

  let tok_str tok =
    match tok with
    | TIdent s | TIntLit s | TCharLit s | TStrLit s -> s
    | TPlus -> "+" | TMinus -> "-" | TStar -> "*" | TSlash -> "/" | TPercent -> "%"
    | TAmpersand -> "&" | TPipe -> "|" | TCaret -> "^" | TTilde -> "~" | TBang -> "!"
    | TLShift -> "<<" | TRShift -> ">>" | TLt -> "<" | TGt -> ">" | TLe -> "<=" | TGe -> ">="
    | TEqEq -> "==" | TNotEq -> "!=" | TAnd -> "&&" | TOr -> "||"
    | TIncDec s -> s
    | TArrow -> "->" | TDot -> "."
    | TEq -> "=" | TAddEq -> "+=" | TSubEq -> "-=" | TAndEq -> "&=" | TOrEq -> "|=" | TXorEq -> "^=" | TMulEq -> "*=" | TDivEq -> "/="
    | TLParen -> "(" | TRParen -> ")" | TLBracket -> "[" | TRBracket -> "]" | TLBrace -> "{" | TRBrace -> "}"
    | TComma -> "," | TSemicolon -> ";" | TColon -> ":" | TQuestion -> "?"
    | TEOF -> ""
  in

  (* Check if an ident is a type keyword (for cast detection) *)
  let is_type_kw = function
    | "int" | "char" | "short" | "long" | "unsigned" | "signed"
    | "float" | "double" | "void" | "bool" | "size_t" | "ssize_t"
    | "uint8_t" | "uint16_t" | "uint32_t" | "uint64_t"
    | "int8_t"  | "int16_t"  | "int32_t"  | "int64_t"
    | "intptr_t" | "uintptr_t" | "ptrdiff_t"
    | "const" | "volatile" | "struct" | "union" | "enum" -> true
    | _ -> false
  in

  (* --- primary --- *)
  let rec parse_primary () =
    match peek () with
    | TLParen ->
        advance ();
        let saved = !pos in
        let is_cast =
          (match peek () with
          | TIdent name when is_type_kw name ->
              let j = ref !pos in
              while !j < n && (match (let (t,_,_)=toks.(!j) in t) with
                | TIdent s when is_type_kw s || s = "const" || s = "volatile" -> true
                | TStar -> true
                | _ -> false) do incr j done;
              (match (let (t,_,_)=toks.(!j) in t) with TRParen -> true | _ -> false)
          | _ -> false)
        in
        if is_cast then begin
          let type_toks = Buffer.create 16 in
          let first = ref true in
          while (match peek () with TRParen | TEOF -> false | _ -> true) do
            if not !first then Buffer.add_char type_toks ' ';
            first := false;
            let (t,_,_) = consume () in
            Buffer.add_string type_toks (tok_str t)
          done;
          let ty = Buffer.contents type_toks in
          advance ();  (* consume ) *)
          let e = parse_unary () in
          ECast (ty, e)
        end else begin
          pos := saved;
          let e = parse_ternary () in
          (match peek () with TRParen -> advance () | _ -> ());
          EParen e
        end
    | TIdent name ->
        advance ();
        EIdent name
    | TIntLit s ->
        advance (); ELit s
    | TCharLit s ->
        advance (); ELit s
    | TStrLit s ->
        let buf = Buffer.create (String.length s) in
        Buffer.add_string buf s;
        advance ();
        while (match peek () with TStrLit _ -> true | _ -> false) do
          let (t,_,_) = consume () in
          Buffer.add_char buf ' ';
          Buffer.add_string buf (tok_str t)
        done;
        ELit (Buffer.contents buf)
    | _ ->
        let (t,_,_) = consume () in
        ELit (tok_str t)

  and parse_postfix () =
    let e = ref (parse_primary ()) in
    let continue_loop = ref true in
    while !continue_loop do
      (match peek () with
      | TLParen ->
          advance ();
          let args = ref [] in
          if peek () <> TRParen then begin
            args := [parse_assignment ()];
            while peek () = TComma do
              advance ();
              args := !args @ [parse_assignment ()]
            done
          end;
          (match peek () with TRParen -> advance () | _ -> ());
          e := ECall (!e, !args)
      | TLBracket ->
          advance ();
          let idx = parse_ternary () in
          (match peek () with TRBracket -> advance () | _ -> ());
          e := EIndex (!e, idx)
      | TDot ->
          advance ();
          let name = (match peek () with
            | TIdent s -> advance (); s
            | _ -> "") in
          e := EField (!e, name, false)
      | TArrow ->
          advance ();
          let name = (match peek () with
            | TIdent s -> advance (); s
            | _ -> "") in
          e := EField (!e, name, true)
      | TIncDec s ->
          advance ();
          e := EPostfix (!e, s)
      | _ -> continue_loop := false)
    done;
    !e

  and parse_unary () =
    match peek () with
    | TMinus ->
        advance (); let e = parse_unary () in EPrefix ("-", e)
    | TPlus ->
        advance (); let e = parse_unary () in EPrefix ("+", e)
    | TTilde ->
        advance (); let e = parse_unary () in EPrefix ("~", e)
    | TBang ->
        advance (); let e = parse_unary () in EPrefix ("!", e)
    | TAmpersand ->
        advance (); let e = parse_unary () in EPrefix ("&", e)
    | TStar ->
        advance (); let e = parse_unary () in EPrefix ("*", e)
    | TIncDec s ->
        advance (); let e = parse_unary () in EPrefix (s, e)
    | _ -> parse_postfix ()

  and parse_mul () =
    let e = ref (parse_unary ()) in
    let continue_loop = ref true in
    while !continue_loop do
      (match peek () with
      | TStar ->
          advance ();
          let r = parse_unary () in
          e := EBinop ("*", !e, r)
      | TSlash ->
          advance ();
          let r = parse_unary () in
          e := EBinop ("/", !e, r)
      | TPercent ->
          advance ();
          let r = parse_unary () in
          e := EBinop ("%", !e, r)
      | _ -> continue_loop := false)
    done;
    !e

  and parse_add () =
    let e = ref (parse_mul ()) in
    let continue_loop = ref true in
    while !continue_loop do
      (match peek () with
      | TPlus ->
          advance ();
          let r = parse_mul () in
          e := EBinop ("+", !e, r)
      | TMinus ->
          advance ();
          let r = parse_mul () in
          e := EBinop ("-", !e, r)
      | _ -> continue_loop := false)
    done;
    !e

  and parse_shift () =
    let e = ref (parse_add ()) in
    let continue_loop = ref true in
    while !continue_loop do
      (match peek () with
      | TLShift ->
          advance (); let r = parse_add () in
          e := EBinop ("<<", !e, r)
      | TRShift ->
          advance (); let r = parse_add () in
          e := EBinop (">>", !e, r)
      | _ -> continue_loop := false)
    done;
    !e

  and parse_rel () =
    let e = ref (parse_shift ()) in
    let continue_loop = ref true in
    while !continue_loop do
      (match peek () with
      | TLt  -> advance (); let r = parse_shift () in e := EBinop ("<",  !e, r)
      | TGt  -> advance (); let r = parse_shift () in e := EBinop (">",  !e, r)
      | TLe  -> advance (); let r = parse_shift () in e := EBinop ("<=", !e, r)
      | TGe  -> advance (); let r = parse_shift () in e := EBinop (">=", !e, r)
      | TEqEq -> advance (); let r = parse_shift () in e := EBinop ("==", !e, r)
      | TNotEq -> advance (); let r = parse_shift () in e := EBinop ("!=", !e, r)
      | _ -> continue_loop := false)
    done;
    !e

  and parse_bitand () =
    let e = ref (parse_rel ()) in
    while (match peek () with TAmpersand -> true | _ -> false) do
      advance ();
      let r = parse_rel () in
      e := EBinop ("&", !e, r)
    done;
    !e

  and parse_bitxor () =
    let e = ref (parse_bitand ()) in
    while (match peek () with TCaret -> true | _ -> false) do
      advance ();
      let r = parse_bitand () in
      e := EBinop ("^", !e, r)
    done;
    !e

  and parse_bitor () =
    let e = ref (parse_bitxor ()) in
    while (match peek () with TPipe -> true | _ -> false) do
      advance ();
      let r = parse_bitxor () in
      e := EBinop ("|", !e, r)
    done;
    !e

  and parse_logand () =
    let e = ref (parse_bitor ()) in
    while (match peek () with TAnd -> true | _ -> false) do
      advance ();
      let r = parse_bitor () in
      e := EBinop ("&&", !e, r)
    done;
    !e

  and parse_logor () =
    let e = ref (parse_logand ()) in
    while (match peek () with TOr -> true | _ -> false) do
      advance ();
      let r = parse_logand () in
      e := EBinop ("||", !e, r)
    done;
    !e

  and parse_ternary () =
    let cond = parse_logor () in
    if peek () = TQuestion then begin
      advance ();
      let t = parse_ternary () in
      (match peek () with TColon -> advance () | _ -> ());
      let f = parse_ternary () in
      ETernary (cond, t, f)
    end else cond

  and parse_assignment () =
    let e = parse_ternary () in
    (match peek () with
    | TEq | TAddEq | TSubEq | TAndEq | TOrEq | TXorEq | TMulEq | TDivEq ->
        let (op,_,_) = consume () in
        let r = parse_assignment () in
        EBinop (tok_str op, e, r)
    | _ -> e)
  in

  let expr = parse_assignment () in
  (expr, !pos)
