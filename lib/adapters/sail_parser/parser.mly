%{
open Ast
%}

%token DEFAULT ORDER DEC
%token <string> INCLUDE_DIRECTIVE
%token LET TYPE REGISTER VAL FUNCTION
%token MAPPING CLAUSE ENCDEC
%token FOREACH FROM TO
%token IF THEN ELSE
%token ARROW BI_ARROW
%token ASSIGN COLON SEMICOLON COMMA
%token LPAREN RPAREN LBRACE RBRACE
%token PIPE AMP HAT PLUS MINUS STAR SLASH PERCENT
%token LSHIFT RSHIFT RSHIFT_S PLUS_SAT MINUS_SAT
%token EQ_EQ NE LT GE TILDE
%token <int> INT
%token <int> HEX
%token <int * int> BITS_LIT
%token <bool> BOOL
%token <string> ID
%token <string * string * int * int> COMMENT_ENCODING
%token EOF

%left PIPE
%left HAT
%left AMP
%left EQ_EQ NE
%left LT GE
%left LSHIFT RSHIFT RSHIFT_S
%left PLUS MINUS PLUS_SAT MINUS_SAT
%left STAR SLASH PERCENT
%nonassoc UMINUS UNOT

%start <Ast.parsed_spec> spec
%%

spec:
  | items = list(toplevel_item); EOF { items }

toplevel_item:
  | DEFAULT; ORDER; DEC { TDefaultOrder }
  | inc = INCLUDE_DIRECTIVE { TInclude inc }
  | LET; id = ID; COLON; ty = type_ref; ASSIGN; e = expr { TLetConst (id, ty, e) }
  | TYPE; id = ID; ASSIGN; _body = type_def_body { TTypeDecl id }
  | REGISTER; id = ID; COLON; ty = type_ref { TRegisterDecl (id, ty) }
  | VAL; id = ID; COLON; LPAREN; params = separated_list(COMMA, type_ref); RPAREN; ARROW; ret = type_ref { TValDecl (id, params, ret) }
  | VAL; id = ID; COLON; ty = type_ref; ARROW; ret = type_ref { TValDecl (id, [ty], ret) }
  | FUNCTION; id = ID; LPAREN; params = separated_list(COMMA, param); RPAREN; ASSIGN; LBRACE; stmts = list(stmt); RBRACE { TFunctionDef (id, params, stmts) }
  | MAPPING; CLAUSE; ENCDEC; ASSIGN; mnem = ID; BI_ARROW; LPAREN; f6 = bit_or_int; COMMA; f3 = bit_or_int; RPAREN { TMappingClause (mnem, f6, f3) }
  | enc = COMMENT_ENCODING { let (m, fmt, f6, f3) = enc in TEncodingComment (m, fmt, f6, f3) }

bit_or_int:
  | b = BITS_LIT { fst b }
  | i = INT { i }
  | h = HEX { h }

type_def_body:
  | ID; LPAREN; expr; COMMA; expr; RPAREN { () }
  | type_ref { () }

param:
  | id = ID; COLON; ty = type_ref { (id, ty) }

type_ref:
  | id = ID; LPAREN; w = INT; RPAREN { if id = "bits" then TBits w else TCustom id }
  | id = ID; LPAREN; id2 = ID; RPAREN { TCustom (id ^ "(" ^ id2 ^ ")") }
  | id = ID {
      match id with
      | "int" -> TInt
      | "nat" -> TNat
      | "bool" -> TBool
      | "unit" -> TUnit
      | s -> TCustom s
    }

stmt:
  | LET; id = ID; ty = option(preceded(COLON, type_ref)); ASSIGN; e = expr; SEMICOLON { SLet (id, ty, e) }
  | target = ID; ASSIGN; e = expr; SEMICOLON { SAssign (target, e) }
  | IF; cond = expr; THEN; LBRACE; then_s = list(stmt); RBRACE; else_s = option(preceded(ELSE, delimited(LBRACE, list(stmt), RBRACE))) {
      SIf (cond, then_s, Option.value ~default:[] else_s)
    }
  | FOREACH; LPAREN; var = ID; FROM; s = expr; TO; e = expr; RPAREN; LBRACE; body = list(stmt); RBRACE; SEMICOLON {
      let bound =
        match e with
        | EBinOp ("-", b, EInt _) -> b
        | other -> other
      in
      SForeach (var, s, bound, body)
    }
  | fn = ID; LPAREN; args = separated_list(COMMA, expr); RPAREN; SEMICOLON { SCall (fn, args) }

expr:
  | i = INT { EInt i }
  | h = HEX { EHex h }
  | b = BITS_LIT { EBits (fst b, snd b) }
  | b = BOOL { EBool b }
  | id = ID { EVar id }
  | fn = ID; LPAREN; args = separated_list(COMMA, expr); RPAREN { ECall (fn, args) }
  | e1 = expr; PLUS; e2 = expr { EBinOp ("+", e1, e2) }
  | e1 = expr; MINUS; e2 = expr { EBinOp ("-", e1, e2) }
  | e1 = expr; STAR; e2 = expr { EBinOp ("*", e1, e2) }
  | e1 = expr; SLASH; e2 = expr { EBinOp ("/", e1, e2) }
  | e1 = expr; PERCENT; e2 = expr { EBinOp ("%", e1, e2) }
  | e1 = expr; AMP; e2 = expr { EBinOp ("&", e1, e2) }
  | e1 = expr; PIPE; e2 = expr { EBinOp ("|", e1, e2) }
  | e1 = expr; HAT; e2 = expr { EBinOp ("^", e1, e2) }
  | e1 = expr; LSHIFT; e2 = expr { EBinOp ("<<", e1, e2) }
  | e1 = expr; RSHIFT; e2 = expr { EBinOp (">>", e1, e2) }
  | e1 = expr; RSHIFT_S; e2 = expr { EBinOp (">>_s", e1, e2) }
  | e1 = expr; PLUS_SAT; e2 = expr { EBinOp ("+_sat", e1, e2) }
  | e1 = expr; MINUS_SAT; e2 = expr { EBinOp ("-_sat", e1, e2) }
  | e1 = expr; EQ_EQ; e2 = expr { EBinOp ("==", e1, e2) }
  | e1 = expr; NE; e2 = expr { EBinOp ("!=", e1, e2) }
  | e1 = expr; LT; e2 = expr { EBinOp ("<", e1, e2) }
  | e1 = expr; GE; e2 = expr { EBinOp (">=", e1, e2) }
  | MINUS; e = expr %prec UMINUS { EUnOp ("-", e) }
  | TILDE; e = expr %prec UNOT { EUnOp ("~", e) }
  | LPAREN; e = expr; RPAREN { e }
  | h = HEX; COLON; ID; LPAREN; b = INT; RPAREN { EBits (h, b) }
