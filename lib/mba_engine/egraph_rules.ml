open Mba
open Egraph_types

type pattern =
  | PVar of string
  | PConst of int64
  | PAdd of pattern * pattern
  | PSub of pattern * pattern
  | PMul of pattern * pattern
  | PAnd of pattern * pattern
  | POr of pattern * pattern
  | PXor of pattern * pattern
  | PNot of pattern
  | PNeg of pattern

let rec match_ eg pat cid0 subst =
  let cid = find eg cid0 in
  match Hashtbl.find_opt eg.classes cid with
  | None -> [] (* stale id: class merged away mid-iteration *)
  | Some nodes ->
      let nodes = !nodes in
      match pat with
      | PVar v -> (
          match List.assoc_opt v subst with
          | Some c -> if find eg c = cid then [ subst ] else []
          | None -> [ (v, cid) :: subst ])
      | PConst c ->
          if List.exists (function EConst c' -> Int64.equal c c' | _ -> false) nodes
          then [ subst ]
          else []
      | PAdd (p1, p2) -> match_binary eg nodes (function EAdd (a, b) -> Some (a, b) | _ -> None) p1 p2 subst
      | PSub (p1, p2) -> match_binary eg nodes (function ESub (a, b) -> Some (a, b) | _ -> None) p1 p2 subst
      | PMul (p1, p2) -> match_binary eg nodes (function EMul (a, b) -> Some (a, b) | _ -> None) p1 p2 subst
      | PAnd (p1, p2) -> match_binary eg nodes (function EAnd (a, b) -> Some (a, b) | _ -> None) p1 p2 subst
      | POr (p1, p2) -> match_binary eg nodes (function EOr (a, b) -> Some (a, b) | _ -> None) p1 p2 subst
      | PXor (p1, p2) -> match_binary eg nodes (function EXor (a, b) -> Some (a, b) | _ -> None) p1 p2 subst
      | PNot p -> match_unary eg nodes (function ENot a -> Some a | _ -> None) p subst
      | PNeg p -> match_unary eg nodes (function ENeg a -> Some a | _ -> None) p subst

and match_binary eg nodes proj p1 p2 subst =
  List.filter_map proj nodes
  |> List.concat_map (fun (a, b) ->
         List.concat_map (fun s1 -> match_ eg p2 b s1) (match_ eg p1 a subst))

and match_unary eg nodes proj p subst =
  List.filter_map proj nodes |> List.concat_map (fun a -> match_ eg p a subst)

let rec instantiate eg pat subst =
  match pat with
  | PVar v -> (
      match List.assoc_opt v subst with
      | Some c -> find eg c
      | None -> invalid_arg "Egraph.instantiate: unbound pattern variable")
  | PConst c -> add_node eg (EConst c)
  | PAdd (p1, p2) -> add_node eg (EAdd (instantiate eg p1 subst, instantiate eg p2 subst))
  | PSub (p1, p2) -> add_node eg (ESub (instantiate eg p1 subst, instantiate eg p2 subst))
  | PMul (p1, p2) -> add_node eg (EMul (instantiate eg p1 subst, instantiate eg p2 subst))
  | PAnd (p1, p2) -> add_node eg (EAnd (instantiate eg p1 subst, instantiate eg p2 subst))
  | POr (p1, p2) -> add_node eg (EOr (instantiate eg p1 subst, instantiate eg p2 subst))
  | PXor (p1, p2) -> add_node eg (EXor (instantiate eg p1 subst, instantiate eg p2 subst))
  | PNot p -> add_node eg (ENot (instantiate eg p subst))
  | PNeg p -> add_node eg (ENeg (instantiate eg p subst))

(* Pattern combinators (plain functions; no operator shadowing). *)
let pX = PVar "x"
let pY = PVar "y"
let pC c = PConst c
let p2 = pC 2L
let p1c = pC 1L
let pm1 = pC (-1L)
let pMe = pC mask_even
let pMo = pC mask_odd
let pAdd a b = PAdd (a, b)
let pSub a b = PSub (a, b)
let pMul a b = PMul (a, b)
let pAnd a b = PAnd (a, b)
let pOr a b = POr (a, b)
let pXor a b = PXor (a, b)
let pNot a = PNot a
let pNeg a = PNeg a

let rules : (string * pattern * pattern) list =
  let x = pX and y = pY in
  let zero1 a b = pSub (pAdd (pOr a b) (pAnd a b)) (pAdd a b) in
  (* ((a|b)+(a&b))-(a+b) = 0 *)
  let zero2 a b = pSub (pXor a b) (pSub (pOr a b) (pAnd a b)) in
  (* (a^b)-((a|b)-(a&b)) = 0 *)
  let zero3 a b = pSub (pAdd (pAnd a b) (pAnd a (pNot b))) a in
  (* ((a&b)+(a&~b))-a = 0 *)
  let slice op a b = pAdd (op (pAnd a pMe) (pAnd b pMe)) (op (pAnd a pMo) (pAnd b pMo)) in
  [ ("xor_or_minus_and", pXor x y, pSub (pOr x y) (pAnd x y));
    ("xor_add_minus_two_and", pXor x y, pSub (pAdd x y) (pMul p2 (pAnd x y)));
    ("xor_mask_sliced", pXor x y, slice pXor x y);
    ("xor_opaque_zero", pXor x y, pAdd (pSub (pOr x y) (pAnd x y)) (zero1 x y));
    ("add_xor_plus_two_and", pAdd x y, pAdd (pXor x y) (pMul p2 (pAnd x y)));
    ("add_or_plus_and", pAdd x y, pAdd (pOr x y) (pAnd x y));
    ("add_mask_sliced", pAdd x y, slice pAdd x y);
    ("add_two_or_minus_xor_opaque", pAdd x y, pAdd (pSub (pMul p2 (pOr x y)) (pXor x y)) (zero1 x y));
    ("sub_xor_minus_two_notand", pSub x y, pSub (pXor x y) (pMul p2 (pAnd (pNot x) y)));
    ("sub_two_andnot_minus_xor", pSub x y, pSub (pMul p2 (pAnd x (pNot y))) (pXor x y));
    ("sub_mask_sliced", pSub x y, slice pSub x y);
    ("sub_bitsdiff_opaque", pSub x y, pAdd (pSub (pAnd x (pNot y)) (pAnd (pNot x) y)) (zero2 x y));
    ("and_add_minus_or", pAnd x y, pSub (pAdd x y) (pOr x y));
    ("and_mask_sliced", pAnd x y, pAdd (pAnd (pAnd x y) pMe) (pAnd (pAnd x y) pMo));
    ("and_keep_opaque", pAnd x y, pAdd (pSub x (pAnd x (pNot y))) (zero2 x y));
    ("or_xor_plus_and", pOr x y, pAdd (pXor x y) (pAnd x y));
    ("or_add_minus_and", pOr x y, pSub (pAdd x y) (pAnd x y));
    ("or_mask_sliced", pOr x y, slice pOr x y);
    ("or_sum_minus_and_opaque", pOr x y, pAdd (pSub (pAdd x y) (pAnd x y)) (zero3 x y));
    ("mul_nl_partition", pMul x y, pAdd (pMul (pAnd x y) (pOr x y)) (pMul (pAnd x (pNot y)) (pAnd (pNot x) y)));
    ("mul_nl_sum_form", pMul x y, pSub (pAdd (pMul (pAnd x y) (pAdd x y)) (pMul (pAnd x (pNot y)) (pAnd (pNot x) y))) (pMul (pAnd x y) (pAnd x y)));
    ("not_xor_all_ones", pNot x, pXor x pm1);
    ("not_sub_minus_one", pNot x, pSub pm1 x);
    ("neg_not_plus_one", pNeg x, pAdd (pNot x) p1c) ]

let rule_count = List.length rules

let rec pattern_to_expr = function
  | PVar s -> Var s
  | PConst c -> Const c
  | PAdd (a, b) -> Add (pattern_to_expr a, pattern_to_expr b)
  | PSub (a, b) -> Sub (pattern_to_expr a, pattern_to_expr b)
  | PMul (a, b) -> Mul (pattern_to_expr a, pattern_to_expr b)
  | PAnd (a, b) -> And (pattern_to_expr a, pattern_to_expr b)
  | POr (a, b) -> Or (pattern_to_expr a, pattern_to_expr b)
  | PXor (a, b) -> Xor (pattern_to_expr a, pattern_to_expr b)
  | PNot a -> Not (pattern_to_expr a)
  | PNeg a -> Neg (pattern_to_expr a)

let rec pattern_vars acc = function
  | PVar v -> if List.mem v acc then acc else v :: acc
  | PConst _ -> acc
  | PNot p | PNeg p -> pattern_vars acc p
  | PAdd (a, b) | PSub (a, b) | PMul (a, b)
  | PAnd (a, b) | POr (a, b) | PXor (a, b) ->
      pattern_vars (pattern_vars acc a) b

let verify_rules ~rng ~trials =
  let edge =
    [| 0L; 1L; -1L; 2L; Int64.min_int; Int64.max_int;
       0x5555555555555555L; -0x5555555555555556L;
       0x0F0F0F0F0F0F0F0FL; 0x123456789ABCDEFL |]
  in
  List.for_all
    (fun (_, pl, pr) ->
      let el = pattern_to_expr pl and er = pattern_to_expr pr in
      let vars = List.rev (pattern_vars [] pl) in
      let ok = ref true in
      for i = 0 to trials - 1 do
        let env = Hashtbl.create 4 in
        List.iter
          (fun v ->
            let base =
              if i < Array.length edge && v = "x" then edge.(i)
              else if i mod 4 = 0 then edge.(Random.State.int rng (Array.length edge))
              else if i mod 4 = 1 then Int64.of_int (Random.State.int rng 0x10000)
              else Random.State.int64 rng Int64.max_int
            in
            let base = if i land 1 = 1 then Int64.neg base else base in
            (* Degenerate case x = y on a third of the trials. *)
            if v = "y" && i mod 3 = 0 then
              (match Hashtbl.find_opt env "x" with
               | Some xv -> Hashtbl.replace env v xv
               | None -> Hashtbl.replace env v base)
            else Hashtbl.replace env v base)
          vars;
        let envf v = match Hashtbl.find_opt env v with Some x -> x | None -> 0L in
        if not (Int64.equal (eval envf el) (eval envf er)) then ok := false
      done;
      !ok)
    rules
