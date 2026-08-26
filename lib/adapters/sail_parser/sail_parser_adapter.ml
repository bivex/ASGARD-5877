open Random_visa_domain
open Ast

let rec conv_type = function
  | TBits w -> Sail_ast.Bits w
  | TInt -> Sail_ast.Int true
  | TNat -> Sail_ast.Int false
  | TBool -> Sail_ast.Bool
  | TUnit -> Sail_ast.Unit
  | TVector (l, t) -> Sail_ast.Vector (l, conv_type t)
  | TCustom s -> Sail_ast.Var_type s

let rec conv_expr = function
  | EInt i -> Sail_ast.Literal_int (i, None)
  | EHex h -> Sail_ast.Literal_int (h, None)
  | EBits (v, w) -> Sail_ast.Literal_int (v, Some w)
  | EBool b -> Sail_ast.Literal_bool b
  | EVar v -> Sail_ast.Var v
  | EBinOp (op_str, left, right) ->
      let op =
        match op_str with
        | "+" -> Types.Binary_op.ADD
        | "-" -> Types.Binary_op.SUB
        | "*" -> Types.Binary_op.MUL
        | "/" -> Types.Binary_op.DIV
        | "%" -> Types.Binary_op.REM
        | "&" -> Types.Binary_op.AND
        | "|" -> Types.Binary_op.OR
        | "^" -> Types.Binary_op.XOR
        | "<<" -> Types.Binary_op.SLL
        | ">>" -> Types.Binary_op.SRL
        | ">>_s" -> Types.Binary_op.SRA
        | "+_sat" -> Types.Binary_op.SADD
        | "-_sat" -> Types.Binary_op.SSUB
        | "==" -> Types.Binary_op.CMPEQ
        | "!=" -> Types.Binary_op.CMPNE
        | "<" -> Types.Binary_op.CMPLT
        | ">=" -> Types.Binary_op.CMPGE
        | _ -> Types.Binary_op.ADD
      in
      Sail_ast.Binary (conv_expr left, op, conv_expr right, Types.Element_kind.Int)
  | EUnOp (op_str, opnd) ->
      let op =
        match op_str with
        | "-" -> Types.Unary_op.NEG
        | "~" -> Types.Unary_op.NOT
        | _ -> Types.Unary_op.NEG
      in
      Sail_ast.Unary (op, conv_expr opnd)
  | ECall ("get_velem", [ EVar reg; idx; EInt sew ]) ->
      Sail_ast.Vector_elem (reg, conv_expr idx, sew)
  | ECall ("min", [ l; r ]) ->
      Sail_ast.Binary (conv_expr l, Types.Binary_op.MIN, conv_expr r, Types.Element_kind.Int)
  | ECall ("max", [ l; r ]) ->
      Sail_ast.Binary (conv_expr l, Types.Binary_op.MAX, conv_expr r, Types.Element_kind.Int)
  | ECall ("eq", [ l; r ]) ->
      Sail_ast.Binary (conv_expr l, Types.Binary_op.CMPEQ, conv_expr r, Types.Element_kind.Int)
  | ECall ("ne", [ l; r ]) ->
      Sail_ast.Binary (conv_expr l, Types.Binary_op.CMPNE, conv_expr r, Types.Element_kind.Int)
  | ECall ("lt", [ l; r ]) ->
      Sail_ast.Binary (conv_expr l, Types.Binary_op.CMPLT, conv_expr r, Types.Element_kind.Int)
  | ECall ("ge", [ l; r ]) ->
      Sail_ast.Binary (conv_expr l, Types.Binary_op.CMPGE, conv_expr r, Types.Element_kind.Int)
  | ECall ("clz", [ a ]) ->
      Sail_ast.Unary (Types.Unary_op.CLZ, conv_expr a)
  | ECall ("ctz", [ a ]) ->
      Sail_ast.Unary (Types.Unary_op.CTZ, conv_expr a)
  | ECall ("cpop", [ a ]) ->
      Sail_ast.Unary (Types.Unary_op.CPOP, conv_expr a)
  | ECall (fn, args) ->
      Sail_ast.Call (fn, List.map conv_expr args)

let rec conv_stmt = function
  | SLet (var, ty_opt, e) ->
      Sail_ast.Let (var, conv_expr e, Option.map conv_type ty_opt)
  | SAssign (target, e) ->
      Sail_ast.Assign (target, conv_expr e)
  | SIf (cond, then_s, else_s) ->
      Sail_ast.If (conv_expr cond, List.map conv_stmt then_s, List.map conv_stmt else_s)
  | SForeach (var, _start, bound, body) ->
      Sail_ast.Vector_loop (var, conv_expr bound, List.map conv_stmt body)
  | SCall ("set_velem", [ EVar reg; idx; EInt sew; val_e ]) ->
      Sail_ast.Set_vector_elem (reg, conv_expr idx, conv_expr val_e, sew)
  | SCall (fn, args) ->
      Sail_ast.Assign ("_", Sail_ast.Call (fn, List.map conv_expr args))

let analyze_instruction_semantics mnemonic =
  let parts = String.split_on_char '_' mnemonic in
  let base =
    match parts with
    | b :: _ -> b
    | [] -> mnemonic
  in
  let family_opt = Isa_grammar.lookup_family base in
  let fmt =
    if List.mem "vx" parts then Types.Instruction_format.OP_VX
    else if List.mem "vi" parts then Types.Instruction_format.OP_VI
    else if List.mem "m" parts then Types.Instruction_format.OP_MVV
    else if List.mem "vs" parts then Types.Instruction_format.OP_RED
    else
      match family_opt with
      | Some (f : Instruction_family.t) when f.klass = Instruction_class.Widening ->
          Types.Instruction_format.OP_WIDENING
      | _ -> Types.Instruction_format.OP_VV
  in
  let bin_op, un_op, is_widening =
    match family_opt with
    | Some (f : Instruction_family.t) -> (f.binary_op, f.unary_op, f.is_widening)
    | None ->
        let b =
          if String.ends_with ~suffix:"add" base then Some Types.Binary_op.ADD
          else if String.ends_with ~suffix:"sub" base then Some Types.Binary_op.SUB
          else if String.ends_with ~suffix:"mul" base then Some Types.Binary_op.MUL
          else if String.ends_with ~suffix:"div" base then Some Types.Binary_op.DIV
          else if String.ends_with ~suffix:"rem" base then Some Types.Binary_op.REM
          else if String.ends_with ~suffix:"and" base then Some Types.Binary_op.AND
          else if String.ends_with ~suffix:"or" base then Some Types.Binary_op.OR
          else if String.ends_with ~suffix:"xor" base then Some Types.Binary_op.XOR
          else if String.ends_with ~suffix:"sll" base then Some Types.Binary_op.SLL
          else if String.ends_with ~suffix:"srl" base then Some Types.Binary_op.SRL
          else if String.ends_with ~suffix:"sra" base then Some Types.Binary_op.SRA
          else if String.ends_with ~suffix:"min" base then Some Types.Binary_op.MIN
          else if String.ends_with ~suffix:"max" base then Some Types.Binary_op.MAX
          else if String.ends_with ~suffix:"sadd" base then Some Types.Binary_op.SADD
          else if String.ends_with ~suffix:"ssub" base then Some Types.Binary_op.SSUB
          else None
        in
        let u =
          if String.ends_with ~suffix:"neg" base then Some Types.Unary_op.NEG
          else if String.ends_with ~suffix:"not" base then Some Types.Unary_op.NOT
          else if String.ends_with ~suffix:"abs" base then Some Types.Unary_op.ABS
          else if String.ends_with ~suffix:"clz" base then Some Types.Unary_op.CLZ
          else if String.ends_with ~suffix:"ctz" base then Some Types.Unary_op.CTZ
          else if String.ends_with ~suffix:"cpop" base then Some Types.Unary_op.CPOP
          else None
        in
        (b, u, String.starts_with ~prefix:"vw" base)
  in
  (fmt, bin_op, un_op, is_widening)

let parse_source ?(spec_name = "Parsed_Sail_ISA") source_text =
  try
    let lexbuf = Lexing.from_string source_text in
    let items = Parser.spec Lexer.token lexbuf in

    let vlen = ref 128 in
    let elen = ref 64 in
    let num_vregs = ref 32 in
    let encodings = Hashtbl.create 32 in

    List.iter
      (function
        | TLetConst ("VLEN", _, EInt v) -> vlen := v
        | TLetConst ("ELEN", _, EInt e) -> elen := e
        | TLetConst ("NUM_VREGS", _, EInt n) -> num_vregs := n
        | TMappingClause (mnem, f6, f3) ->
            Hashtbl.replace encodings mnem (f6, f3)
        | TEncodingComment (mnem, _fmt, f6, f3) ->
            if not (Hashtbl.mem encodings mnem) then
              Hashtbl.replace encodings mnem (f6, f3)
        | _ -> ())
      items;

    let f6_alloc = ref 0 in
    let instructions = ref [] in

    List.iter
      (function
        | TFunctionDef (fn_name, params, stmts) ->
            let mnemonic =
              if String.starts_with ~prefix:"execute_" fn_name then
                String.sub fn_name 8 (String.length fn_name - 8)
              else fn_name
            in
            let fmt, bin_op, un_op, is_widening = analyze_instruction_semantics mnemonic in
            let f6, f3 =
              match Hashtbl.find_opt encodings mnemonic with
              | Some (funct6, funct3) -> (funct6, funct3)
              | None ->
                  let candidate = !f6_alloc in
                  incr f6_alloc;
                  (candidate, Types.Instruction_format.to_funct3 fmt)
            in
            let sail_fn = {
              Sail_ast.name = fn_name;
              params = List.map (fun (id, ty) -> (id, conv_type ty)) params;
              return_type = Sail_ast.Unit;
              body = List.map conv_stmt stmts;
            } in
            let inst =
              Vector_instruction.make
                ~mnemonic
                ~format:fmt
                ~funct6:f6
                ~funct3:f3
                ~opcode:0x57
                ?binary_op:bin_op
                ?unary_op:un_op
                ~element_kind:Types.Element_kind.Int
                ~is_widening
                ~description:(Printf.sprintf "Parsed from Sail function %s" fn_name)
                ~sail_function:sail_fn
                ()
            in
            instructions := !instructions @ [ inst ]
        | _ -> ())
      items;

    match Vector_config.make ~vlen:!vlen ~elen:!elen ~num_vregs:!num_vregs () with
    | Error err -> Error err
    | Ok config ->
        Vector_isa_spec.of_instructions
          ~name:spec_name
          ~version:"1.0-parsed"
          ~config
          !instructions
  with exn ->
    Error (Errors.Sail_parse_error (Printexc.to_string exn))

let parse ?(spec_name = "Parsed_Sail_ISA") source_text =
  parse_source ~spec_name source_text

let parse_file ?(spec_name = "Parsed_Sail_ISA") file_path =
  try
    let ic = open_in_bin file_path in
    let len = in_channel_length ic in
    let content = really_input_string ic len in
    close_in ic;
    parse ~spec_name content
  with exn ->
    Error (Errors.General_error (Printf.sprintf "Cannot read sail file %s: %s" file_path (Printexc.to_string exn)))
