open Mba

let synthesize_ncfg_xor ~rng e1 e2 =
  match Random.State.int rng 3 with
  | 0 ->
      (* (x | y) - (x & y) *)
      Sub (Or (e1, e2), And (e1, e2))
  | 1 ->
      (* (x + y) - 2 * (x & y) *)
      Sub (Add (e1, e2), Mul (Const 2L, And (e1, e2)))
  | _ ->
      (* (x & ~y) | (~x & y) *)
      Or (And (e1, Not e2), And (Not e1, e2))

let synthesize_ncfg_add ~rng e1 e2 =
  match Random.State.int rng 3 with
  | 0 ->
      (* (x ^ y) + 2 * (x & y) *)
      Add (Xor (e1, e2), Mul (Const 2L, And (e1, e2)))
  | 1 ->
      (* (x | y) + (x & y) *)
      Add (Or (e1, e2), And (e1, e2))
  | _ ->
      (* 2 * (x | y) - (x ^ y) *)
      Sub (Mul (Const 2L, Or (e1, e2)), Xor (e1, e2))

let synthesize_ncfg_sub ~rng e1 e2 =
  match Random.State.int rng 2 with
  | 0 ->
      (* (x ^ y) - 2 * (~x & y) *)
      Sub (Xor (e1, e2), Mul (Const 2L, And (Not e1, e2)))
  | _ ->
      (* (x & ~y) - (~x & y) *)
      Sub (And (e1, Not e2), And (Not e1, e2))

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
    | Mul (e1, e2) -> Mul (rec_ncfg e1, rec_ncfg e2)
    | And (e1, e2) -> And (rec_ncfg e1, rec_ncfg e2)
    | Or (e1, e2) -> Or (rec_ncfg e1, rec_ncfg e2)
    | Not e -> Not (rec_ncfg e)
    | Neg e -> Neg (rec_ncfg e)
