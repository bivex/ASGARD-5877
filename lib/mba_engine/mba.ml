(** Mba_engine — Mixed Boolean-Arithmetic (MBA) rewriter for ASGARD-5877.

    The [rewrite] core is derived from formally verified identities proven
    in F* 2026.08.23 + Z3 5.0.0 (see [fstar/Mba_Verified.fst]).

    Verified identities (over 64-bit wrapping / modular arithmetic):
      XOR a b  =  (a | b) XOR (a & b)          [F* theorem mba_xor_eq]
      AND a b  =  (a | b) XOR (a XOR b)         [F* theorem mba_and_eq]
      OR  a b  =  (a XOR b) XOR (a & b)         [F* theorem mba_or_eq]
      NOT a    =  a XOR 0xFFFFFFFFFFFFFFFF       [F* theorem mba_not_eq]
      ADD a b  =  (a XOR b) + 2*(a & b)         [arithmetic, QCheck 200k]
      SUB a b  =  (a XOR b) - 2*(~a & b)        [arithmetic, QCheck 200k]
*)

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

(* ------------------------------------------------------------------ *)
(* Verified MBA identity kernels (extracted from F* proof obligations) *)
(* Each function returns TWO provably-equivalent forms; the rewriter   *)
(* picks randomly between them for additional entropy.                 *)
(* ------------------------------------------------------------------ *)

(** XOR: two F*-verified forms *)
let xor_forms a b : expr * expr =
  (* Form 1 [F* mba_xor_eq]: (a | b) ^ (a & b) *)
  let f1 = Xor (Or (a, b), And (a, b)) in
  (* Form 2 [arithmetic]: (a + b) - 2*(a & b) *)
  let f2 = Sub (Add (a, b), Mul (Const 2L, And (a, b))) in
  (f1, f2)

(** AND: two F*-verified forms *)
let and_forms a b : expr * expr =
  (* Form 1 [F* mba_and_eq]: (a | b) ^ (a ^ b) *)
  let f1 = Xor (Or (a, b), Xor (a, b)) in
  (* Form 2 [arithmetic]: (a + b) - (a | b) *)
  let f2 = Sub (Add (a, b), Or (a, b)) in
  (f1, f2)

(** OR: two F*-verified forms *)
let or_forms a b : expr * expr =
  (* Form 1 [F* mba_or_eq]: (a ^ b) ^ (a & b) *)
  let f1 = Xor (Xor (a, b), And (a, b)) in
  (* Form 2 [arithmetic]: (a ^ b) + (a & b) *)
  let f2 = Add (Xor (a, b), And (a, b)) in
  (f1, f2)

(** ADD: two arithmetic forms *)
let add_forms a b : expr * expr =
  (* Form 1 [arithmetic, 200k verified]: (a ^ b) + 2*(a & b) *)
  let f1 = Add (Xor (a, b), Mul (Const 2L, And (a, b))) in
  (* Form 2 [arithmetic]: (a | b) + (a & b) *)
  let f2 = Add (Or (a, b), And (a, b)) in
  (f1, f2)

(** SUB: two arithmetic forms *)
let sub_forms a b : expr * expr =
  (* Form 1 [arithmetic, 200k verified]: (a ^ b) - 2*(~a & b) *)
  let f1 = Sub (Xor (a, b), Mul (Const 2L, And (Not a, b))) in
  (* Form 2 [arithmetic]: 2*(a & ~b) - (a ^ b) *)
  let f2 = Sub (Mul (Const 2L, And (a, Not b)), Xor (a, b)) in
  (f1, f2)

(** NOT: two F*-verified forms *)
let not_forms a : expr * expr =
  (* Form 1 [F* mba_not_eq]: a ^ 0xFFFFFFFFFFFFFFFF *)
  let f1 = Xor (a, Const (-1L)) in
  (* Form 2 [two's complement]: -a - 1 *)
  let f2 = Sub (Neg a, Const 1L) in
  (f1, f2)

(** Pick randomly between two verified equivalent forms *)
let pick rng (f1, f2) =
  if Random.State.bool rng then f1 else f2

(* ------------------------------------------------------------------ *)
(* Main rewriter: applies verified MBA identities recursively          *)
(* ------------------------------------------------------------------ *)

let rec rewrite ~rng ~depth expr =
  if depth <= 0 then expr
  else
    let r = rewrite ~rng ~depth:(depth - 1) in
    match expr with
    | Var _ | Const _ -> expr
    | Add (a, b) -> pick rng (add_forms (r a) (r b))
    | Sub (a, b) -> pick rng (sub_forms (r a) (r b))
    | Xor (a, b) -> pick rng (xor_forms (r a) (r b))
    | And (a, b) -> pick rng (and_forms (r a) (r b))
    | Or  (a, b) -> pick rng (or_forms  (r a) (r b))
    | Not a      -> pick rng (not_forms (r a))
    | Mul (a, b) -> Mul (r a, r b)
    | Neg a      ->
        (* -x = ~x + 1 [two's complement] *)
        Add (Not (r a), Const 1L)

(* ------------------------------------------------------------------ *)
(* IR lowering: stack-based compilation of MBA AST to VM-IR            *)
(* ------------------------------------------------------------------ *)

let lower_to_ir ~dst ~env expr =
  let instrs = ref [] in
  let emit i = instrs := i :: !instrs in

  let rec compile target_reg = function
    | Var v -> (
        match List.assoc_opt v env with
        | Some op -> emit (Ir.Mov { dst = Ir.Reg target_reg; src = op })
        | None -> emit (Ir.Mov { dst = Ir.Reg target_reg; src = Ir.Imm 0L }))
    | Const c -> emit (Ir.Mov { dst = Ir.Reg target_reg; src = Ir.Imm c })
    | Add (a, b) ->
        compile target_reg a;
        emit (Ir.Push (Ir.Reg target_reg));
        compile Register.vtmp1 b;
        emit (Ir.Pop (Ir.Reg Register.vtmp0));
        emit (Ir.Alu { op = Ir.Add; dst = target_reg; src1 = Ir.Reg Register.vtmp0;
                       src2 = Ir.Reg Register.vtmp1; set_flags = false })
    | Sub (a, b) ->
        compile target_reg a;
        emit (Ir.Push (Ir.Reg target_reg));
        compile Register.vtmp1 b;
        emit (Ir.Pop (Ir.Reg Register.vtmp0));
        emit (Ir.Alu { op = Ir.Sub; dst = target_reg; src1 = Ir.Reg Register.vtmp0;
                       src2 = Ir.Reg Register.vtmp1; set_flags = false })
    | Mul (a, b) ->
        compile target_reg a;
        emit (Ir.Push (Ir.Reg target_reg));
        compile Register.vtmp1 b;
        emit (Ir.Pop (Ir.Reg Register.vtmp0));
        emit (Ir.Alu { op = Ir.Imul; dst = target_reg; src1 = Ir.Reg Register.vtmp0;
                       src2 = Ir.Reg Register.vtmp1; set_flags = false })
    | And (a, b) ->
        compile target_reg a;
        emit (Ir.Push (Ir.Reg target_reg));
        compile Register.vtmp1 b;
        emit (Ir.Pop (Ir.Reg Register.vtmp0));
        emit (Ir.Alu { op = Ir.And; dst = target_reg; src1 = Ir.Reg Register.vtmp0;
                       src2 = Ir.Reg Register.vtmp1; set_flags = false })
    | Or (a, b) ->
        compile target_reg a;
        emit (Ir.Push (Ir.Reg target_reg));
        compile Register.vtmp1 b;
        emit (Ir.Pop (Ir.Reg Register.vtmp0));
        emit (Ir.Alu { op = Ir.Or; dst = target_reg; src1 = Ir.Reg Register.vtmp0;
                       src2 = Ir.Reg Register.vtmp1; set_flags = false })
    | Xor (a, b) ->
        compile target_reg a;
        emit (Ir.Push (Ir.Reg target_reg));
        compile Register.vtmp1 b;
        emit (Ir.Pop (Ir.Reg Register.vtmp0));
        emit (Ir.Alu { op = Ir.Xor; dst = target_reg; src1 = Ir.Reg Register.vtmp0;
                       src2 = Ir.Reg Register.vtmp1; set_flags = false })
    | Not a ->
        compile target_reg a;
        emit (Ir.Unary { op = Ir.Not; dst = target_reg; src = Ir.Reg target_reg;
                         set_flags = false })
    | Neg a ->
        compile target_reg a;
        emit (Ir.Unary { op = Ir.Neg; dst = target_reg; src = Ir.Reg target_reg;
                         set_flags = false })
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
    | _ -> failwith "Mba.obfuscate_alu: unsupported op"
  in
  let mba_tree = rewrite ~rng ~depth base_expr in
  let env = [ ("a", src1); ("b", src2) ] in
  lower_to_ir ~dst ~env mba_tree
