type sail_type =
  | Bits of int
  | Int of bool
  | Bool
  | Unit
  | Vector of int * sail_type
  | Var_type of string

type sail_expr =
  | Literal_int of int * int option
  | Literal_bool of bool
  | Var of string
  | Binary of sail_expr * Types.Binary_op.t * sail_expr * Types.Element_kind.t
  | Unary of Types.Unary_op.t * sail_expr
  | Vector_elem of string * sail_expr * int
  | Mask_check of string * sail_expr * sail_expr
  | Call of string * sail_expr list

type sail_stmt =
  | Let of string * sail_expr * sail_type option
  | Assign of string * sail_expr
  | Set_vector_elem of string * sail_expr * sail_expr * int
  | If of sail_expr * sail_stmt list * sail_stmt list
  | Vector_loop of string * sail_expr * sail_stmt list

type function_def = {
  name : string;
  params : (string * sail_type) list;
  return_type : sail_type;
  body : sail_stmt list;
}

type encoding_clause = {
  mnemonic : string;
  funct6 : int;
  funct3 : int;
  format_name : string;
}

let rec type_to_sail = function
  | Bits w -> Printf.sprintf "bits(%d)" w
  | Int true -> "int"
  | Int false -> "nat"
  | Bool -> "bool"
  | Unit -> "unit"
  | Vector (len, t) -> Printf.sprintf "vector(%d, %s)" len (type_to_sail t)
  | Var_type s -> s

let rec expr_to_sail = function
  | Literal_int (v, Some b) -> Printf.sprintf "0x%x : bits(%d)" v b
  | Literal_int (v, None) -> string_of_int v
  | Literal_bool true -> "true"
  | Literal_bool false -> "false"
  | Var name -> name
  | Binary (left, op, right, _kind) ->
      if Types.Binary_op.is_compare op then
        let func =
          match op with
          | Types.Binary_op.CMPEQ -> "eq"
          | Types.Binary_op.CMPNE -> "ne"
          | Types.Binary_op.CMPLT -> "lt"
          | Types.Binary_op.CMPGE -> "ge"
          | _ -> "eq"
        in
        Printf.sprintf "%s(%s, %s)" func (expr_to_sail left) (expr_to_sail right)
      else if op = Types.Binary_op.MIN || op = Types.Binary_op.MAX then
        Printf.sprintf "%s(%s, %s)" (Types.Binary_op.symbol op) (expr_to_sail left) (expr_to_sail right)
      else
        Printf.sprintf "(%s %s %s)" (expr_to_sail left) (Types.Binary_op.symbol op) (expr_to_sail right)
  | Unary (op, operand) -> (
      match op with
      | Types.Unary_op.NEG -> Printf.sprintf "(-%s)" (expr_to_sail operand)
      | Types.Unary_op.NOT -> Printf.sprintf "(~%s)" (expr_to_sail operand)
      | other -> Printf.sprintf "%s(%s)" (Types.Unary_op.symbol other) (expr_to_sail operand))
  | Vector_elem (reg, idx, sew) ->
      Printf.sprintf "get_velem(%s, %s, %d)" reg (expr_to_sail idx) sew
  | Mask_check (mask_reg, idx, vm_unmasked) ->
      Printf.sprintf "(%s == 1 | get_vmask_bit(%s, %s) == 1)" (expr_to_sail vm_unmasked) mask_reg (expr_to_sail idx)
  | Call (fn, args) ->
      let args_str = String.concat ", " (List.map expr_to_sail args) in
      Printf.sprintf "%s(%s)" fn args_str

let rec stmt_to_sail ?(indent = 0) =
  let pad = String.make indent ' ' in
  function
  | Let (var, expr, None) ->
      Printf.sprintf "%slet %s = %s;" pad var (expr_to_sail expr)
  | Let (var, expr, Some ty) ->
      Printf.sprintf "%slet %s : %s = %s;" pad var (type_to_sail ty) (expr_to_sail expr)
  | Assign (target, expr) ->
      Printf.sprintf "%s%s = %s;" pad target (expr_to_sail expr)
  | Set_vector_elem (reg, idx, value, sew) ->
      Printf.sprintf "%sset_velem(%s, %s, %d, %s);" pad reg (expr_to_sail idx) sew (expr_to_sail value)
  | If (cond, then_stmts, else_stmts) ->
      let b = Buffer.create 128 in
      Buffer.add_string b (Printf.sprintf "%sif %s then {\n" pad (expr_to_sail cond));
      List.iter (fun s ->
        Buffer.add_string b (stmt_to_sail ~indent:(indent + 2) s);
        Buffer.add_char b '\n') then_stmts;
      if else_stmts <> [] then begin
        Buffer.add_string b (Printf.sprintf "%s} else {\n" pad);
        List.iter (fun s ->
          Buffer.add_string b (stmt_to_sail ~indent:(indent + 2) s);
          Buffer.add_char b '\n') else_stmts;
      end;
      Buffer.add_string b (Printf.sprintf "%s}" pad);
      Buffer.contents b
  | Vector_loop (var, bound, body) ->
      let b = Buffer.create 128 in
      Buffer.add_string b (Printf.sprintf "%sforeach (%s from 0 to (%s - 1)) {\n" pad var (expr_to_sail bound));
      List.iter (fun s ->
        Buffer.add_string b (stmt_to_sail ~indent:(indent + 2) s);
        Buffer.add_char b '\n') body;
      Buffer.add_string b (Printf.sprintf "%s};" pad);
      Buffer.contents b

let function_to_sail ?(indent = 0) fn =
  let pad = String.make indent ' ' in
  let params_decl =
    String.concat ", " (List.map (fun (_, ty) -> type_to_sail ty) fn.params)
  in
  let params_def =
    String.concat ", " (List.map (fun (name, ty) -> Printf.sprintf "%s: %s" name (type_to_sail ty)) fn.params)
  in
  let b = Buffer.create 256 in
  Buffer.add_string b (Printf.sprintf "%sval %s : (%s) -> %s\n" pad fn.name params_decl (type_to_sail fn.return_type));
  Buffer.add_string b (Printf.sprintf "%sfunction %s(%s) = {\n" pad fn.name params_def);
  List.iter (fun s ->
    Buffer.add_string b (stmt_to_sail ~indent:(indent + 2) s);
    Buffer.add_char b '\n') fn.body;
  Buffer.add_string b (Printf.sprintf "%s}" pad);
  Buffer.contents b

let to_binary_string width v =
  let s = Bytes.make width '0' in
  for i = 0 to width - 1 do
    let bit = (v lsr (width - 1 - i)) land 1 in
    if bit = 1 then Bytes.set s i '1'
  done;
  Bytes.to_string s

let encoding_clause_to_sail c =
  Printf.sprintf "mapping clause encdec = %s <-> (0b%s, 0b%s)"
    c.mnemonic
    (to_binary_string 6 c.funct6)
    (to_binary_string 3 c.funct3)
