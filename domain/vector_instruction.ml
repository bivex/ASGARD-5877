type t = {
  mnemonic : string;
  format : Types.Instruction_format.t;
  funct6 : int;
  funct3 : int;
  opcode : int;
  binary_op : Types.Binary_op.t option;
  unary_op : Types.Unary_op.t option;
  element_kind : Types.Element_kind.t;
  is_widening : bool;
  is_reduction : bool;
  description : string;
  sail_function : Sail_ast.function_def;
}

let synthesize_sail_function ~mnemonic ~format ~binary_op ~unary_op ~element_kind ~is_widening ?(sew = Types.Sew.E32) () =
  let fn_name = Printf.sprintf "execute_%s" mnemonic in
  let params = [
    ("vd_idx", Sail_ast.Bits 5);
    ("vs2_idx", Sail_ast.Bits 5);
    ("vs1_or_imm", Sail_ast.Bits 5);
    ("vm", Sail_ast.Bits 1);
  ] in
  let src_bits = Types.Sew.to_bits sew in
  let dst_bits = if is_widening then src_bits * 2 else src_bits in
  let loop_var = "i" in
  let mask_cond = Sail_ast.Mask_check ("v0", Sail_ast.Var loop_var, Sail_ast.Var "vm") in
  let elem_vs2 = Sail_ast.Vector_elem ("vs2", Sail_ast.Var loop_var, src_bits) in
  let loop_body = ref [ Sail_ast.Let ("op2", elem_vs2, None) ] in

  let rhs_expr =
    match format with
    | Types.Instruction_format.OP_VV ->
        let elem_vs1 = Sail_ast.Vector_elem ("vs1", Sail_ast.Var loop_var, src_bits) in
        loop_body := !loop_body @ [ Sail_ast.Let ("op1", elem_vs1, None) ];
        Sail_ast.Var "op1"
    | Types.Instruction_format.OP_VX ->
        let call_rx = Sail_ast.Call ("rX", [ Sail_ast.Var "vs1_or_imm" ]) in
        loop_body := !loop_body @ [
          Sail_ast.Let ("rs1_val", call_rx, None);
          Sail_ast.Let ("op1", Sail_ast.Var "rs1_val", None);
        ];
        Sail_ast.Var "op1"
    | Types.Instruction_format.OP_VI ->
        let call_ext = Sail_ast.Call ("sign_extend", [ Sail_ast.Var "vs1_or_imm" ]) in
        loop_body := !loop_body @ [
          Sail_ast.Let ("simm5", call_ext, None);
          Sail_ast.Let ("op1", Sail_ast.Var "simm5", None);
        ];
        Sail_ast.Var "op1"
    | _ ->
        let elem_vs1 = Sail_ast.Vector_elem ("vs1", Sail_ast.Var loop_var, src_bits) in
        loop_body := !loop_body @ [ Sail_ast.Let ("op1", elem_vs1, None) ];
        Sail_ast.Var "op1"
  in

  let compute_expr =
    match binary_op with
    | Some op -> Sail_ast.Binary (Sail_ast.Var "op2", op, rhs_expr, element_kind)
    | None -> (
        match unary_op with
        | Some op -> Sail_ast.Unary (op, Sail_ast.Var "op2")
        | None -> Sail_ast.Var "op2")
  in

  loop_body := !loop_body @ [
    Sail_ast.Let ("res_elem", compute_expr, None);
    Sail_ast.Set_vector_elem ("vd", Sail_ast.Var loop_var, Sail_ast.Var "res_elem", dst_bits);
  ];

  let masked_if = Sail_ast.If (mask_cond, !loop_body, []) in
  let vector_loop = Sail_ast.Vector_loop (loop_var, Sail_ast.Var "vl", [ masked_if ]) in
  {
    Sail_ast.name = fn_name;
    params;
    return_type = Sail_ast.Unit;
    body = [ vector_loop ];
  }

let make
    ~mnemonic
    ~format
    ~funct6
    ~funct3
    ?(opcode = 0x57)
    ?binary_op
    ?unary_op
    ?(element_kind = Types.Element_kind.Int)
    ?(is_widening = false)
    ?(is_reduction = false)
    ?(description = "")
    ?sail_function
    ?(sew = Types.Sew.E32)
    () =
  let sail_fn =
    match sail_function with
    | Some fn -> fn
    | None ->
        synthesize_sail_function ~mnemonic ~format ~binary_op ~unary_op ~element_kind ~is_widening ~sew ()
  in
  {
    mnemonic;
    format;
    funct6;
    funct3;
    opcode;
    binary_op;
    unary_op;
    element_kind;
    is_widening;
    is_reduction;
    description;
    sail_function = sail_fn;
  }

let encode ?(vm = 1) ?(vd = 0) ?(vs2 = 0) ?(vs1_or_rs1_or_imm = 0) t =
  let f6 = Int32.shift_left (Int32.of_int (t.funct6 land 0x3F)) 26 in
  let m = Int32.shift_left (Int32.of_int (vm land 0x1)) 25 in
  let v2 = Int32.shift_left (Int32.of_int (vs2 land 0x1F)) 20 in
  let v1 = Int32.shift_left (Int32.of_int (vs1_or_rs1_or_imm land 0x1F)) 15 in
  let f3 = Int32.shift_left (Int32.of_int (t.funct3 land 0x7)) 12 in
  let d = Int32.shift_left (Int32.of_int (vd land 0x1F)) 7 in
  let op = Int32.of_int (t.opcode land 0x7F) in
  Int32.logor f6 (
    Int32.logor m (
      Int32.logor v2 (
        Int32.logor v1 (
          Int32.logor f3 (
            Int32.logor d op
          )
        )
      )
    )
  )
