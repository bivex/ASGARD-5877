open Mba

let synthesize_ncfg_xor ~rng e1 e2 =
  match Random.State.int rng 9 with
  | 0 ->
      (* (x | y) - (x & y) *)
      Sub (Or (e1, e2), And (e1, e2))
  | 1 ->
      (* (x + y) - 2 * (x & y) *)
      Sub (Add (e1, e2), Mul (Const 2L, And (e1, e2)))
  | 2 ->
      (* (x & ~y) | (~x & y) *)
      Or (And (e1, Not e2), And (Not e1, e2))
  | 3 ->
      (* 2 * (x | y) - (x + y) *)
      Sub (Mul (Const 2L, Or (e1, e2)), Add (e1, e2))
  | 4 ->
      (* (x & ~y) + (~x & y) *)
      Add (And (e1, Not e2), And (Not e1, e2))
  | 5 ->
      (* ((x | y) + ~(x & y)) + 1 *)
      Add (Add (Or (e1, e2), Not (And (e1, e2))), Const 1L)
  | 6 ->
      (* (x - y) + 2 * (~x & y) *)
      Add (Sub (e1, e2), Mul (Const 2L, And (Not e1, e2)))
  | 7 ->
      (* (y - x) + 2 * (x & ~y) *)
      Add (Sub (e2, e1), Mul (Const 2L, And (e1, Not e2)))
  | _ ->
      (* ~((~x | y) & (x | ~y)) *)
      Not (And (Or (Not e1, e2), Or (e1, Not e2)))

let synthesize_ncfg_add ~rng e1 e2 =
  match Random.State.int rng 8 with
  | 0 ->
      (* (x ^ y) + 2 * (x & y) *)
      Add (Xor (e1, e2), Mul (Const 2L, And (e1, e2)))
  | 1 ->
      (* (x | y) + (x & y) *)
      Add (Or (e1, e2), And (e1, e2))
  | 2 ->
      (* 2 * (x | y) - (x ^ y) *)
      Sub (Mul (Const 2L, Or (e1, e2)), Xor (e1, e2))
  | 3 ->
      (* ((x | y) - ~(x & y)) - 1 *)
      Sub (Sub (Or (e1, e2), Not (And (e1, e2))), Const 1L)
  | 4 ->
      (* ((x & ~y) + (~x & y)) + 2 * (x & y) *)
      Add (Add (And (e1, Not e2), And (Not e1, e2)), Mul (Const 2L, And (e1, e2)))
  | 5 ->
      (* (x - ~y) - 1 *)
      Sub (Sub (e1, Not e2), Const 1L)
  | 6 ->
      (* 2 * (x | y) - ((x | y) - (x & y)) *)
      Sub (Mul (Const 2L, Or (e1, e2)), Sub (Or (e1, e2), And (e1, e2)))
  | _ ->
      (* (x + y) + zero_inv1(x, y) *)
      Add (Add (Or (e1, e2), And (e1, e2)), zero_inv1 e1 e2)

let synthesize_ncfg_sub ~rng e1 e2 =
  match Random.State.int rng 8 with
  | 0 ->
      (* (x ^ y) - 2 * (~x & y) *)
      Sub (Xor (e1, e2), Mul (Const 2L, And (Not e1, e2)))
  | 1 ->
      (* (x & ~y) - (~x & y) *)
      Sub (And (e1, Not e2), And (Not e1, e2))
  | 2 ->
      (* 2 * (x & ~y) - (x ^ y) *)
      Sub (Mul (Const 2L, And (e1, Not e2)), Xor (e1, e2))
  | 3 ->
      (* (x + ~y) + 1 *)
      Add (Add (e1, Not e2), Const 1L)
  | 4 ->
      (* (x | ~y) - (~x | y) *)
      Sub (Or (e1, Not e2), Or (Not e1, e2))
  | 5 ->
      (* (x - (x & y)) - (y - (x & y)) *)
      Sub (Sub (e1, And (e1, e2)), Sub (e2, And (e1, e2)))
  | 6 ->
      (* (x ^ y) - 2 * (y - (x & y)) *)
      Sub (Xor (e1, e2), Mul (Const 2L, Sub (e2, And (e1, e2))))
  | _ ->
      (* (x - y) + zero_inv2(x, y) *)
      Add (Sub (Or (e1, Not e2), Or (Not e1, e2)), zero_inv2 e1 e2)

let synthesize_ncfg_and ~rng e1 e2 =
  match Random.State.int rng 8 with
  | 0 ->
      (* (x + y) - (x | y) *)
      Sub (Add (e1, e2), Or (e1, e2))
  | 1 ->
      (* (x | y) - (x ^ y) *)
      Sub (Or (e1, e2), Xor (e1, e2))
  | 2 ->
      (* ~(~x | ~y) *)
      Not (Or (Not e1, Not e2))
  | 3 ->
      (* x - (x & ~y) *)
      Sub (e1, And (e1, Not e2))
  | 4 ->
      (* y - (~x & y) *)
      Sub (e2, And (Not e1, e2))
  | 5 ->
      (* ((x | y) + ~(x ^ y)) + 1 *)
      Add (Add (Or (e1, e2), Not (Xor (e1, e2))), Const 1L)
  | 6 ->
      (* ((x + y) + ~(x | y)) + 1 *)
      Add (Add (Add (e1, e2), Not (Or (e1, e2))), Const 1L)
  | _ ->
      (* (x & y) + zero_inv3(x, y) *)
      Add (Sub (Add (e1, e2), Or (e1, e2)), zero_inv3 e1 e2)

let synthesize_ncfg_or ~rng e1 e2 =
  match Random.State.int rng 8 with
  | 0 ->
      (* (x + y) - (x & y) *)
      Sub (Add (e1, e2), And (e1, e2))
  | 1 ->
      (* (x ^ y) + (x & y) *)
      Add (Xor (e1, e2), And (e1, e2))
  | 2 ->
      (* ~(~x & ~y) *)
      Not (And (Not e1, Not e2))
  | 3 ->
      (* x + (~x & y) *)
      Add (e1, And (Not e1, e2))
  | 4 ->
      (* y + (x & ~y) *)
      Add (e2, And (e1, Not e2))
  | 5 ->
      (* ((x ^ y) - ~(x & y)) - 1 *)
      Sub (Sub (Xor (e1, e2), Not (And (e1, e2))), Const 1L)
  | 6 ->
      (* ((x + y) + ~(x & y)) + 1 *)
      Add (Add (Add (e1, e2), Not (And (e1, e2))), Const 1L)
  | _ ->
      (* (x | y) + zero_inv1(x, y) *)
      Add (Add (Xor (e1, e2), And (e1, e2)), zero_inv1 e1 e2)

let synthesize_ncfg_not ~rng e =
  match Random.State.int rng 4 with
  | 0 ->
      (* x ^ -1 *)
      Xor (e, Const (-1L))
  | 1 ->
      (* -x - 1 *)
      Sub (Neg e, Const 1L)
  | 2 ->
      (* -1 - x *)
      Sub (Const (-1L), e)
  | _ ->
      (* ~x + zero_inv5_poly(x) *)
      Add (Xor (e, Const (-1L)), zero_inv5_poly e)

let synthesize_ncfg_neg ~rng e =
  match Random.State.int rng 4 with
  | 0 ->
      (* ~x + 1 *)
      Add (Not e, Const 1L)
  | 1 ->
      (* 0 - x *)
      Sub (Const 0L, e)
  | 2 ->
      (* ~(x - 1) *)
      Not (Sub (e, Const 1L))
  | _ ->
      (* ~(x + -1) *)
      Not (Add (e, Const (-1L)))

let synthesize_ncfg_mul ~rng e1 e2 =
  match Random.State.int rng 6 with
  | 0 ->
      (* (x & y) * (x | y) + (x & ~y) * (~x & y) *)
      Add (Mul (And (e1, e2), Or (e1, e2)), Mul (And (e1, Not e2), And (Not e1, e2)))
  | 1 ->
      (* (x & y) * (x + y) + (x & ~y) * (~x & y) - (x & y) * (x & y) *)
      Sub (Add (Mul (And (e1, e2), Add (e1, e2)), Mul (And (e1, Not e2), And (Not e1, e2))),
           Mul (And (e1, e2), And (e1, e2)))
  | 2 ->
      (* (x & y) * (x | y) + (x - (x & y)) * (y - (x & y)) *)
      Add (Mul (And (e1, e2), Or (e1, e2)), Mul (Sub (e1, And (e1, e2)), Sub (e2, And (e1, e2))))
  | 3 ->
      (* (x & y)^2 + (x & y) * (x ^ y) + (x & ~y) * (~x & y) *)
      Add (Add (Mul (And (e1, e2), And (e1, e2)), Mul (And (e1, e2), Xor (e1, e2))),
           Mul (And (e1, Not e2), And (Not e1, e2)))
  | 4 ->
      (* (x & ~y) * y + (x & y) * y *)
      Add (Mul (And (e1, Not e2), e2), Mul (And (e1, e2), e2))
  | _ ->
      (* x * (y & ~x) + x * (x & y) *)
      Add (Mul (e1, And (Not e1, e2)), Mul (e1, And (e1, e2)))

let rec rewrite_ncfg ~rng ~depth expr =
  if depth <= 0 then expr
  else
    let rec_ncfg = rewrite_ncfg ~rng ~depth:(depth - 1) in
    match expr with
    | Var _ | Const _ -> expr
    | Xor (e1, e2) ->
        let expanded = synthesize_ncfg_xor ~rng (rec_ncfg e1) (rec_ncfg e2) in
        if depth > 1 then rewrite_ncfg ~rng ~depth:(depth - 1) expanded else expanded
    | Add (e1, e2) ->
        let expanded = synthesize_ncfg_add ~rng (rec_ncfg e1) (rec_ncfg e2) in
        if depth > 1 then rewrite_ncfg ~rng ~depth:(depth - 1) expanded else expanded
    | Sub (e1, e2) ->
        let expanded = synthesize_ncfg_sub ~rng (rec_ncfg e1) (rec_ncfg e2) in
        if depth > 1 then rewrite_ncfg ~rng ~depth:(depth - 1) expanded else expanded
    | And (e1, e2) ->
        let expanded = synthesize_ncfg_and ~rng (rec_ncfg e1) (rec_ncfg e2) in
        if depth > 1 then rewrite_ncfg ~rng ~depth:(depth - 1) expanded else expanded
    | Or (e1, e2) ->
        let expanded = synthesize_ncfg_or ~rng (rec_ncfg e1) (rec_ncfg e2) in
        if depth > 1 then rewrite_ncfg ~rng ~depth:(depth - 1) expanded else expanded
    | Not e ->
        let expanded = synthesize_ncfg_not ~rng (rec_ncfg e) in
        if depth > 1 then rewrite_ncfg ~rng ~depth:(depth - 1) expanded else expanded
    | Neg e ->
        let expanded = synthesize_ncfg_neg ~rng (rec_ncfg e) in
        if depth > 1 then rewrite_ncfg ~rng ~depth:(depth - 1) expanded else expanded
    | Mul (e1, e2) ->
        let expanded = synthesize_ncfg_mul ~rng (rec_ncfg e1) (rec_ncfg e2) in
        if depth > 1 then rewrite_ncfg ~rng ~depth:(depth - 1) expanded else expanded

let obfuscate_alu ~rng ~depth ~dst ~src1 ~src2 op =
  let open Vm_ir in
  match op with
  | Ir.Add ->
      let tree = rewrite_ncfg ~rng ~depth (Add (Var "a", Var "b")) in
      lower_to_ir ~dst ~env:[ ("a", src1); ("b", src2) ] tree
  | Ir.Sub ->
      let tree = rewrite_ncfg ~rng ~depth (Sub (Var "a", Var "b")) in
      lower_to_ir ~dst ~env:[ ("a", src1); ("b", src2) ] tree
  | Ir.Xor ->
      let tree = rewrite_ncfg ~rng ~depth (Xor (Var "a", Var "b")) in
      lower_to_ir ~dst ~env:[ ("a", src1); ("b", src2) ] tree
  | Ir.And ->
      let tree = rewrite_ncfg ~rng ~depth (And (Var "a", Var "b")) in
      lower_to_ir ~dst ~env:[ ("a", src1); ("b", src2) ] tree
  | Ir.Or ->
      let tree = rewrite_ncfg ~rng ~depth (Or (Var "a", Var "b")) in
      lower_to_ir ~dst ~env:[ ("a", src1); ("b", src2) ] tree
  | Ir.Imul ->
      let tree = rewrite_ncfg ~rng ~depth (Mul (Var "a", Var "b")) in
      lower_to_ir ~dst ~env:[ ("a", src1); ("b", src2) ] tree
  | unsupported ->
      [ Ir.Alu { op = unsupported; dst; src1; src2; set_flags = false } ]
