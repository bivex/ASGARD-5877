{
open Parser

let parse_bits_lit str =
  let body = String.sub str 2 (String.length str - 2) in
  let width = String.length body in
  let rec to_int acc i =
    if i >= String.length body then acc
    else
      let bit = if body.[i] = '1' then 1 else 0 in
      to_int ((acc lsl 1) lor bit) (i + 1)
  in
  (to_int 0 0, width)
}

let digit = ['0'-'9']
let hex_digit = ['0'-'9' 'a'-'f' 'A'-'F']
let ident = ['a'-'z' 'A'-'Z' '_'] ['a'-'z' 'A'-'Z' '0'-'9' '_']*

rule token = parse
  | [' ' '\t' '\r' '\n']+ { token lexbuf }
  | "//" [^ '\n']* { token lexbuf }
  | "/*" { comment_start lexbuf }
  | "$include" [' ' '\t']* '<' [^ '>']* '>' as inc { INCLUDE_DIRECTIVE inc }
  | "default" { DEFAULT }
  | "Order" { ORDER }
  | "dec" { DEC }
  | "let" { LET }
  | "type" { TYPE }
  | "register" { REGISTER }
  | "val" { VAL }
  | "function" { FUNCTION }
  | "mapping" { MAPPING }
  | "clause" { CLAUSE }
  | "encdec" { ENCDEC }
  | "foreach" { FOREACH }
  | "from" { FROM }
  | "to" { TO }
  | "if" { IF }
  | "then" { THEN }
  | "else" { ELSE }
  | "true" { BOOL true }
  | "false" { BOOL false }
  | "->" { ARROW }
  | "<->" { BI_ARROW }
  | "==" { EQ_EQ }
  | "!=" { NE }
  | "<=" { LT (* or LE *) }
  | ">=" { GE }
  | "<<" { LSHIFT }
  | ">>_s" { RSHIFT_S }
  | ">>" { RSHIFT }
  | "+_sat" { PLUS_SAT }
  | "-_sat" { MINUS_SAT }
  | '<' { LT }
  | '+' { PLUS }
  | '-' { MINUS }
  | '*' { STAR }
  | '/' { SLASH }
  | '%' { PERCENT }
  | '&' { AMP }
  | '|' { PIPE }
  | '^' { HAT }
  | '~' { TILDE }
  | '=' { ASSIGN }
  | ':' { COLON }
  | ';' { SEMICOLON }
  | ',' { COMMA }
  | '(' { LPAREN }
  | ')' { RPAREN }
  | '{' { LBRACE }
  | '}' { RBRACE }
  | "0b" ['0' '1']+ as b { BITS_LIT (parse_bits_lit b) }
  | "0x" hex_digit+ as h { HEX (int_of_string h) }
  | digit+ as d { INT (int_of_string d) }
  | ident as id { ID id }
  | eof { EOF }
  | _ as c { failwith (Printf.sprintf "Unexpected character in Sail lexer: %c" c) }

and comment_start = parse
  | [' ' '\t']* "Instruction:" [' ' '\t']* (ident as mnem) [' ' '\t']* '(' (ident as fmt) ')' [' ' '\t']* "encoding:" [' ' '\t']* "funct6=" (digit+ as f6) [',']? [' ' '\t']* "funct3=" (digit+ as f3) [' ' '\t']* "*/"
    { COMMENT_ENCODING (mnem, fmt, int_of_string f6, int_of_string f3) }
  | "*/" { token lexbuf }
  | '\n' { comment_start lexbuf }
  | eof { EOF }
  | _ { comment_rest lexbuf }

and comment_rest = parse
  | "*/" { token lexbuf }
  | '\n' { comment_rest lexbuf }
  | eof { EOF }
  | _ { comment_rest lexbuf }
