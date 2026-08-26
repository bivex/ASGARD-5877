open Vm_ir

type expr =
  | Var of string
  | Const of int64
  | Add of expr * expr
  | Sub of expr * expr
  | Mul of expr * expr
  | And of expr * expr
  | Or of expr * expr
  | Xor of expr * expr
  | Not of expr
  | Neg of expr

let rec to_string = function
  | Var s -> s
  | Const c -> Printf.sprintf "0x%LX" c
  | Add (a, b) -> Printf.sprintf "(%s + %s)" (to_string a) (to_string b)
  | Sub (a, b) -> Printf.sprintf "(%s - %s)" (to_string a) (to_string b)
  | Mul (a, b) -> Printf.sprintf "(%s * %s)" (to_string a) (to_string b)
  | And (a, b) -> Printf.sprintf "(%s & %s)" (to_string a) (to_string b)
  | Or (a, b) -> Printf.sprintf "(%s | %s)" (to_string a) (to_string b)
  | Xor (a, b) -> Printf.sprintf "(%s ^ %s)" (to_string a) (to_string b)
  | Not a -> Printf.sprintf "(~%s)" (to_string a)
  | Neg a -> Printf.sprintf "(-%s)" (to_string a)

let rec eval env = function
  | Var s -> env s
  | Const c -> c
  | Add (a, b) -> Int64.add (eval env a) (eval env b)
  | Sub (a, b) -> Int64.sub (eval env a) (eval env b)
  | Mul (a, b) -> Int64.mul (eval env a) (eval env b)
  | And (a, b) -> Int64.logand (eval env a) (eval env b)
  | Or (a, b) -> Int64.logor (eval env a) (eval env b)
  | Xor (a, b) -> Int64.logxor (eval env a) (eval env b)
  | Not a -> Int64.lognot (eval env a)
  | Neg a -> Int64.neg (eval env a)

let rec rewrite ~rng ~depth expr =
  if depth <= 0 then expr
  else
    let r = rewrite ~rng ~depth:(depth - 1) in
    match expr with
    | Var _ | Const _ -> expr
    | Add (a, b) ->
        let a' = r a in
        let b' = r b in
        if Random.State.bool rng then
          (* x + y = (x ^ y) + 2*(x & y) *)
          Add (Xor (a', b'), Mul (Const 2L, And (a', b')))
        else
          (* x + y = (x | y) + (x & y) *)
          Add (Or (a', b'), And (a', b'))
    | Sub (a, b) ->
        let a' = r a in
        let b' = r b in
        if Random.State.bool rng then
          (* x - y = (x ^ y) - 2*(~x & y) *)
          Sub (Xor (a', b'), Mul (Const 2L, And (Not a', b')))
        else
          (* x - y = 2*(x & ~y) - (x ^ y) *)
          Sub (Mul (Const 2L, And (a', Not b')), Xor (a', b'))
    | Xor (a, b) ->
        let a' = r a in
        let b' = r b in
        if Random.State.bool rng then
          (* x ^ y = (x | y) - (x & y) *)
          Sub (Or (a', b'), And (a', b'))
        else
          (* x ^ y = (x + y) - 2*(x & y) *)
          Sub (Add (a', b'), Mul (Const 2L, And (a', b')))
    | And (a, b) ->
        let a' = r a in
        let b' = r b in
        if Random.State.bool rng then
          (* x & y = (x + y) - (x | y) *)
          Sub (Add (a', b'), Or (a', b'))
        else
          (* x & y = (x | y) - (x ^ y) *)
          Sub (Or (a', b'), Xor (a', b'))
    | Or (a, b) ->
        let a' = r a in
        let b' = r b in
        if Random.State.bool rng then
          (* x | y = (x ^ y) + (x & y) *)
          Add (Xor (a', b'), And (a', b'))
        else
          (* x | y = (x + y) - (x & y) *)
          Sub (Add (a', b'), And (a', b'))
    | Mul (a, b) ->
        Mul (r a, r b)
    | Not a ->
        let a' = r a in
        (* ~x = -x - 1 *)
        Sub (Neg a', Const 1L)
    | Neg a ->
        let a' = r a in
        (* -x = ~x + 1 *)
        Add (Not a', Const 1L)

let lower_to_ir ~dst ~env expr =
  let instrs = ref [] in
  let emit i = instrs := i :: !instrs in

  let rec compile target_reg = function
    | Var v -> (
        match List.assoc_opt v env with
        | Some op -> emit (Ir.Mov { dst = Ir.Reg target_reg; src = op })
        | None -> emit (Ir.Mov { dst = Ir.Reg target_reg; src = Ir.Imm 0L }))
    | Const c ->
        emit (Ir.Mov { dst = Ir.Reg target_reg; src = Ir.Imm c })
    | Add (a, b) ->
        compile target_reg a;
        emit (Ir.Push (Ir.Reg target_reg));
        compile Register.vtmp1 b;
        emit (Ir.Pop (Ir.Reg Register.vtmp0));
        emit (Ir.Alu { op = Ir.Add; dst = target_reg; src1 = Ir.Reg Register.vtmp0; src2 = Ir.Reg Register.vtmp1; set_flags = false })
    | Sub (a, b) ->
        compile target_reg a;
        emit (Ir.Push (Ir.Reg target_reg));
        compile Register.vtmp1 b;
        emit (Ir.Pop (Ir.Reg Register.vtmp0));
        emit (Ir.Alu { op = Ir.Sub; dst = target_reg; src1 = Ir.Reg Register.vtmp0; src2 = Ir.Reg Register.vtmp1; set_flags = false })
    | Mul (a, b) ->
        compile target_reg a;
        emit (Ir.Push (Ir.Reg target_reg));
        compile Register.vtmp1 b;
        emit (Ir.Pop (Ir.Reg Register.vtmp0));
        emit (Ir.Alu { op = Ir.Imul; dst = target_reg; src1 = Ir.Reg Register.vtmp0; src2 = Ir.Reg Register.vtmp1; set_flags = false })
    | And (a, b) ->
        compile target_reg a;
        emit (Ir.Push (Ir.Reg target_reg));
        compile Register.vtmp1 b;
        emit (Ir.Pop (Ir.Reg Register.vtmp0));
        emit (Ir.Alu { op = Ir.And; dst = target_reg; src1 = Ir.Reg Register.vtmp0; src2 = Ir.Reg Register.vtmp1; set_flags = false })
    | Or (a, b) ->
        compile target_reg a;
        emit (Ir.Push (Ir.Reg target_reg));
        compile Register.vtmp1 b;
        emit (Ir.Pop (Ir.Reg Register.vtmp0));
        emit (Ir.Alu { op = Ir.Or; dst = target_reg; src1 = Ir.Reg Register.vtmp0; src2 = Ir.Reg Register.vtmp1; set_flags = false })
    | Xor (a, b) ->
        compile target_reg a;
        emit (Ir.Push (Ir.Reg target_reg));
        compile Register.vtmp1 b;
        emit (Ir.Pop (Ir.Reg Register.vtmp0));
        emit (Ir.Alu { op = Ir.Xor; dst = target_reg; src1 = Ir.Reg Register.vtmp0; src2 = Ir.Reg Register.vtmp1; set_flags = false })
    | Not a ->
        compile target_reg a;
        emit (Ir.Unary { op = Ir.Not; dst = target_reg; src = Ir.Reg target_reg; set_flags = false })
    | Neg a ->
        compile target_reg a;
        emit (Ir.Unary { op = Ir.Neg; dst = target_reg; src = Ir.Reg target_reg; set_flags = false })
  in

  compile dst expr;
  List.rev !instrs

let obfuscate_alu ~rng ~depth ~dst ~src1 ~src2 op =
  let base_expr =
    match op with
    | Ir.Add -> Add (Var "a", Var "b")
    | Ir.Sub -> Sub (Var "a", Var "b")
    | Ir.Xor -> Xor (Var "a", Var "b")
    | Ir.And -> And (Var "a", Var "b")
    | Ir.Or  -> Or  (Var "a", Var "b")
    | _ ->
        (* Non-MBA op: fallback to single instruction *)
        failwith "Unsupported MBA op"
  in
  let mba_tree = rewrite ~rng ~depth base_expr in
  let env = [ ("a", src1); ("b", src2) ] in
  lower_to_ir ~dst ~env mba_tree
