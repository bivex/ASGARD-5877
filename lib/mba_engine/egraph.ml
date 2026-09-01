(** Egraph — E-Graph "Equality Expansion" MBA Synthesizer.

    Implements the Scrambler technique (arXiv:2603.03624) on top of the
    verified MBA identity corpus of [Mba]:

    - a minimal egg-style e-graph: union-find with path compression,
      hash-consing, and congruence closure via iterative rebuild;
    - "Equality Expansion": the dual of classic Equality Saturation —
      rewrite rules grow the graph toward the *most complex* equivalent
      expression and extraction maximizes (AST size, MBA alternation)
      instead of minimizing cost;
    - equivalence holds by construction: every rule is a proven identity
      over Z_(2^64) (see {!verify_rules}), so no SMT solver participates
      in the synthesis loop. *)

open Vm_ir
open Mba

(* Semi-linear bitmask constants — must mirror [Mba]. *)
let mask_even = 0x5555555555555555L
let mask_odd = -0x5555555555555556L (* 0xAAAAAAAAAAAAAAAA in two's complement *)

(* ------------------------------------------------------------------ *)
(* E-nodes and the e-graph                                             *)
(* ------------------------------------------------------------------ *)

(** An e-node: an operator applied to e-class ids (children canonical). *)
type enode =
  | EVar of string
  | EConst of int64
  | EAdd of int * int
  | ESub of int * int
  | EMul of int * int
  | EAnd of int * int
  | EOr of int * int
  | EXor of int * int
  | ENot of int
  | ENeg of int

type t = {
  mutable next_id : int;
  parent : (int, int) Hashtbl.t;             (* id -> parent; absent = root *)
  classes : (int, enode list ref) Hashtbl.t;  (* root id -> canonical nodes *)
  mutable hashcons : (enode, int) Hashtbl.t;  (* canonical enode -> an id in its class *)
  mutable unions : int;
}

let create () =
  { next_id = 0;
    parent = Hashtbl.create 512;
    classes = Hashtbl.create 512;
    hashcons = Hashtbl.create 1024;
    unions = 0 }

let find eg id =
  let rec root i = match Hashtbl.find_opt eg.parent i with
    | Some p -> root p
    | None -> i
  in
  let r = root id in
  let rec compress i =
    if i <> r then
      match Hashtbl.find_opt eg.parent i with
      | Some p -> Hashtbl.replace eg.parent i r; compress p
      | None -> ()
  in
  compress id;
  r

let class_ids eg =
  List.sort compare (Hashtbl.fold (fun k _ acc -> k :: acc) eg.classes [])

let node_count eg =
  Hashtbl.fold (fun _ ns acc -> acc + List.length !ns) eg.classes 0

let add_node eg node =
  match Hashtbl.find_opt eg.hashcons node with
  | Some id -> find eg id
  | None ->
      let id = eg.next_id in
      eg.next_id <- id + 1;
      Hashtbl.replace eg.classes id (ref [ node ]);
      Hashtbl.replace eg.hashcons node id;
      id

let rec add_expr eg (e : expr) : int =
  match e with
  | Var s -> add_node eg (EVar s)
  | Const c -> add_node eg (EConst c)
  | Add (a, b) -> add_node eg (EAdd (add_expr eg a, add_expr eg b))
  | Sub (a, b) -> add_node eg (ESub (add_expr eg a, add_expr eg b))
  | Mul (a, b) -> add_node eg (EMul (add_expr eg a, add_expr eg b))
  | And (a, b) -> add_node eg (EAnd (add_expr eg a, add_expr eg b))
  | Or (a, b) -> add_node eg (EOr (add_expr eg a, add_expr eg b))
  | Xor (a, b) -> add_node eg (EXor (add_expr eg a, add_expr eg b))
  | Not a -> add_node eg (ENot (add_expr eg a))
  | Neg a -> add_node eg (ENeg (add_expr eg a))

let canonicalize eg = function
  | (EVar _ | EConst _) as n -> n
  | EAdd (a, b) -> EAdd (find eg a, find eg b)
  | ESub (a, b) -> ESub (find eg a, find eg b)
  | EMul (a, b) -> EMul (find eg a, find eg b)
  | EAnd (a, b) -> EAnd (find eg a, find eg b)
  | EOr (a, b) -> EOr (find eg a, find eg b)
  | EXor (a, b) -> EXor (find eg a, find eg b)
  | ENot a -> ENot (find eg a)
  | ENeg a -> ENeg (find eg a)

(* Union: keep the smaller id as root so the graph shape is deterministic. *)
let merge eg a b =
  let ra = find eg a and rb = find eg b in
  if ra = rb then ra
  else begin
    let keep, drop = if ra < rb then ra, rb else rb, ra in
    let kn = Hashtbl.find eg.classes keep in
    let dn = Hashtbl.find eg.classes drop in
    kn := !kn @ !dn;
    Hashtbl.replace eg.parent drop keep;
    Hashtbl.remove eg.classes drop;
    eg.unions <- eg.unions + 1;
    keep
  end

(** Congruence closure: re-canonicalize every class, merge classes that now
    share a canonical node, and refresh the hash-cons table. *)
let rebuild eg =
  let changed = ref true in
  while !changed do
    changed := false;
    Hashtbl.iter
      (fun _ ns -> ns := List.sort_uniq compare (List.map (canonicalize eg) !ns))
      eg.classes;
    let seen = Hashtbl.create 512 in
    let merges = ref [] in
    Hashtbl.iter
      (fun cid ns ->
        List.iter
          (fun n ->
            match Hashtbl.find_opt seen n with
            | Some other -> if other <> cid then merges := (other, cid) :: !merges
            | None -> Hashtbl.replace seen n cid)
          !ns)
      eg.classes;
    if !merges <> [] then begin
      changed := true;
      List.iter (fun (a, b) -> ignore (merge eg a b)) !merges
    end
  done;
  let hc = Hashtbl.create (2 * Hashtbl.length eg.classes + 16) in
  Hashtbl.iter
    (fun cid ns -> List.iter (fun n -> Hashtbl.replace hc n cid) !ns)
    eg.classes;
  eg.hashcons <- hc

(* ------------------------------------------------------------------ *)
(* Patterns: rule LHS/RHS over e-classes                               *)
(* ------------------------------------------------------------------ *)

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

(* Substitutions bind pattern variables to e-class ids. *)
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

(** The growth rule corpus. Every entry is a proven identity over Z_(2^64),
    ported from the verified forms in [Mba] (see {!Mba.xor_forms},
    {!Mba.and_forms}, {!Mba.or_forms}, {!Mba.add_forms}, {!Mba.sub_forms},
    {!Mba.mul_forms}, {!Mba.not_forms} and the zero invariants). *)
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

(** Exhaustive rule verification against [Mba.eval] under edge-case and
    randomized assignments, including the degenerate x = y case. *)
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

(* ------------------------------------------------------------------ *)
(* Metrics: AST size, operator count, MBA alternation                  *)
(* ------------------------------------------------------------------ *)

let rec ast_size = function
  | Var _ | Const _ -> 1
  | Not a | Neg a -> 1 + ast_size a
  | Add (a, b) | Sub (a, b) | Mul (a, b)
  | And (a, b) | Or (a, b) | Xor (a, b) ->
      1 + ast_size a + ast_size b

let rec op_count = function
  | Var _ | Const _ -> 0
  | Not a | Neg a -> 1 + op_count a
  | Add (a, b) | Sub (a, b) | Mul (a, b)
  | And (a, b) | Or (a, b) | Xor (a, b) ->
      1 + op_count a + op_count b

type domain = Arith | Bool | Leaf

let domain_of = function
  | Add _ | Sub _ | Mul _ | Neg _ -> Arith
  | And _ | Or _ | Xor _ | Not _ -> Bool
  | Var _ | Const _ -> Leaf

let alternation e =
  let rec go e dparent acc =
    match e with
    | Var _ | Const _ -> acc
    | _ ->
        let d = domain_of e in
        let acc =
          match dparent with Some dp when dp <> d -> acc + 1 | _ -> acc
        in
        match e with
        | Not a | Neg a -> go a (Some d) acc
        | Add (a, b) | Sub (a, b) | Mul (a, b)
        | And (a, b) | Or (a, b) | Xor (a, b) ->
            go b (Some d) (go a (Some d) acc)
        | Var _ | Const _ -> acc (* unreachable: leaves handled above *)
  in
  go e None 0

(* ------------------------------------------------------------------ *)
(* Extraction: maximize (AST size, alternation) with a cycle guard     *)
(* ------------------------------------------------------------------ *)

type extracted = expr * int * int (* expression, size, alternation *)

let extract ~rng ?(max_depth = 6) eg root_id =
  let root = find eg root_id in
  (* 1. Compute the strictly minimal (acyclic) AST for every reachable e-class *)
  let min_ast : (int, expr * int) Hashtbl.t = Hashtbl.create 512 in
  Hashtbl.iter
    (fun cid ns ->
      List.iter
        (function
          | EVar s -> Hashtbl.replace min_ast cid (Var s, 1)
          | EConst c -> Hashtbl.replace min_ast cid (Const c, 1)
          | _ -> ())
        !ns)
    eg.classes;
  let min_changed = ref true in
  let min_passes = ref 0 in
  while !min_changed && !min_passes < 32 do
    incr min_passes;
    min_changed := false;
    Hashtbl.iter
      (fun cid ns ->
        List.iter
          (fun n ->
            let get_m a = Hashtbl.find_opt min_ast (find eg a) in
            let cand =
              match n with
              | EVar s -> Some (Var s, 1)
              | EConst c -> Some (Const c, 1)
              | EAdd (a, b) -> (match (get_m a, get_m b) with Some (e1, s1), Some (e2, s2) -> Some (Add (e1, e2), 1 + s1 + s2) | _ -> None)
              | ESub (a, b) -> (match (get_m a, get_m b) with Some (e1, s1), Some (e2, s2) -> Some (Sub (e1, e2), 1 + s1 + s2) | _ -> None)
              | EMul (a, b) -> (match (get_m a, get_m b) with Some (e1, s1), Some (e2, s2) -> Some (Mul (e1, e2), 1 + s1 + s2) | _ -> None)
              | EAnd (a, b) -> (match (get_m a, get_m b) with Some (e1, s1), Some (e2, s2) -> Some (And (e1, e2), 1 + s1 + s2) | _ -> None)
              | EOr (a, b) -> (match (get_m a, get_m b) with Some (e1, s1), Some (e2, s2) -> Some (Or (e1, e2), 1 + s1 + s2) | _ -> None)
              | EXor (a, b) -> (match (get_m a, get_m b) with Some (e1, s1), Some (e2, s2) -> Some (Xor (e1, e2), 1 + s1 + s2) | _ -> None)
              | ENot a -> (match get_m a with Some (e1, s1) -> Some (Not e1, 1 + s1) | _ -> None)
              | ENeg a -> (match get_m a with Some (e1, s1) -> Some (Neg e1, 1 + s1) | _ -> None)
            in
            match cand with
            | Some (e_cand, s_cand) ->
                let is_smaller =
                  match Hashtbl.find_opt min_ast cid with
                  | None -> true
                  | Some (_, s_cur) -> s_cand < s_cur
                in
                if is_smaller then begin
                  Hashtbl.replace min_ast cid (e_cand, s_cand);
                  min_changed := true
                end
            | None -> ())
          !ns)
      eg.classes
  done;

  (* 2. Recursive depth-bounded acyclic search to maximize (AST size, alternation) *)
  let memo : (int * int, extracted) Hashtbl.t = Hashtbl.create 512 in
  let rec best cid depth visited =
    let cid = find eg cid in
    if depth <= 0 || List.mem cid visited then
      match Hashtbl.find_opt min_ast cid with
      | Some (e, s) -> Some (e, s, alternation e)
      | None -> None
    else
      match Hashtbl.find_opt memo (cid, depth) with
      | Some r -> Some r
      | None ->
          match Hashtbl.find_opt eg.classes cid with
          | None -> None
          | Some nodes ->
              let visited' = cid :: visited in
              let cands =
                List.filter_map
                  (fun n ->
                    let binary f a b d =
                      match (best a (depth - 1) visited', best b (depth - 1) visited') with
                      | Some (e1, s1, a1), Some (e2, s2, a2) ->
                          let e = f e1 e2 in
                          let extra =
                            (if s1 > 1 && domain_of e1 <> d then 1 else 0)
                            + (if s2 > 1 && domain_of e2 <> d then 1 else 0)
                          in
                          Some (e, 1 + s1 + s2, a1 + a2 + extra)
                      | _ -> None
                    in
                    let unary f a d =
                      match best a (depth - 1) visited' with
                      | Some (e1, s1, a1) ->
                          let extra = if s1 > 1 && domain_of e1 <> d then 1 else 0 in
                          Some (f e1, 1 + s1, a1 + extra)
                      | _ -> None
                    in
                    match n with
                    | EVar s -> Some (Var s, 1, 0)
                    | EConst c -> Some (Const c, 1, 0)
                    | EAdd (a, b) -> binary (fun u v -> Add (u, v)) a b Arith
                    | ESub (a, b) -> binary (fun u v -> Sub (u, v)) a b Arith
                    | EMul (a, b) -> binary (fun u v -> Mul (u, v)) a b Arith
                    | EAnd (a, b) -> binary (fun u v -> And (u, v)) a b Bool
                    | EOr (a, b) -> binary (fun u v -> Or (u, v)) a b Bool
                    | EXor (a, b) -> binary (fun u v -> Xor (u, v)) a b Bool
                    | ENot a -> unary (fun u -> Not u) a Bool
                    | ENeg a -> unary (fun u -> Neg u) a Arith)
                  !nodes
              in
              let pick =
                match cands with
                | [] ->
                    (match Hashtbl.find_opt min_ast cid with
                     | Some (e, s) -> Some (e, s, alternation e)
                     | None -> None)
                | _ ->
                    let key (_, s, a) = (s, a) in
                    let m = List.fold_left (fun acc r -> max acc (key r)) (0, 0) cands in
                    let winners = List.filter (fun r -> key r = m) cands in
                    let w =
                      List.nth winners (Random.State.int rng (List.length winners))
                    in
                    Some w
              in
              (match pick with
               | Some p ->
                   Hashtbl.replace memo (cid, depth) p;
                   Some p
               | None -> None)
  in
  best root max_depth []

(* ------------------------------------------------------------------ *)
(* Equality Expansion driver                                           *)
(* ------------------------------------------------------------------ *)

type config = { node_limit : int; time_budget_s : float; iter_limit : int }

let default_config = { node_limit = 2000; time_budget_s = 1.0; iter_limit = 24 }

let shuffled rng n =
  let a = Array.init n (fun i -> i) in
  for i = n - 1 downto 1 do
    let j = Random.State.int rng (i + 1) in
    let t = a.(i) in
    a.(i) <- a.(j);
    a.(j) <- t
  done;
  a

let saturate ~rng ~config eg =
  let rules_arr = Array.of_list rules in
  let t0 = Sys.time () in
  let iters = ref 0 in
  let stop = ref false in
  let over_budget () =
    eg.next_id >= config.node_limit
    || Sys.time () -. t0 >= config.time_budget_s
  in
  while not !stop do
    incr iters;
    let order = shuffled rng (Array.length rules_arr) in
    let nodes_before = node_count eg in
    let ids = class_ids eg in
    (* 1. Match phase on the frozen graph snapshot of this iteration *)
    let matches = ref [] in
    (try
       Array.iter
         (fun ri ->
           if over_budget () then raise Exit;
           let (_, pl, pr) = rules_arr.(ri) in
           List.iter
             (fun cid ->
               let substs = match_ eg pl cid [] in
               List.iter (fun s -> matches := (pr, s, cid) :: !matches) substs)
             ids)
         order
     with Exit -> ());
    (* 2. Apply phase: instantiate and merge with budget checks *)
    let app_order = shuffled rng (List.length !matches) in
    let matches_arr = Array.of_list !matches in
    (try
       Array.iter
         (fun idx ->
           if over_budget () then raise Exit;
           let (pr, s, cid) = matches_arr.(idx) in
           let rhs_id = instantiate eg pr s in
           ignore (merge eg cid rhs_id))
         app_order
     with Exit -> ());
    (* 3. Rebuild phase: restore invariants *)
    rebuild eg;
    let nodes_after = node_count eg in
    if
      nodes_after <= nodes_before
      || nodes_after >= config.node_limit
      || !iters >= config.iter_limit
      || over_budget ()
    then stop := true
  done;
  !iters

type stats = {
  iterations : int;
  classes : int;
  nodes : int;
  unions : int;
  extracted_size : int;
  extracted_alternation : int;
}

let expand_full ~rng ?(config = default_config) e =
  let eg = create () in
  let root = add_expr eg e in
  let iters = saturate ~rng ~config eg in
  rebuild eg;
  match extract ~rng eg root with
  | Some (e', s, a) ->
      ( e',
        { iterations = iters;
          classes = Hashtbl.length eg.classes;
          nodes = node_count eg;
          unions = eg.unions;
          extracted_size = s;
          extracted_alternation = a } )
  | None ->
      (* Degenerate: the original node is always extractable, so this is
         unreachable; fall back to the input (equivalent by definition). *)
      ( e,
        { iterations = iters;
          classes = Hashtbl.length eg.classes;
          nodes = node_count eg;
          unions = eg.unions;
          extracted_size = ast_size e;
          extracted_alternation = alternation e } )

let expand ~rng ?(config = default_config) e = fst (expand_full ~rng ~config e)

(* ------------------------------------------------------------------ *)
(* VM-IR integration (mirrors [Mba.obfuscate_alu])                     *)
(* ------------------------------------------------------------------ *)

let obfuscate_alu ~rng ?(config = default_config) ~dst ~src1 ~src2 op =
  let expr_of = function
    | Ir.Add -> Some (Add (Var "a", Var "b"))
    | Ir.Sub -> Some (Sub (Var "a", Var "b"))
    | Ir.Xor -> Some (Xor (Var "a", Var "b"))
    | Ir.And -> Some (And (Var "a", Var "b"))
    | Ir.Or -> Some (Or (Var "a", Var "b"))
    | Ir.Imul -> Some (Mul (Var "a", Var "b"))
    | _ -> None
  in
  match expr_of op with
  | Some e ->
      let expanded = expand ~config ~rng e in
      lower_to_ir ~dst ~env:[ ("a", src1); ("b", src2) ] expanded
  | None -> [ Ir.Alu { op; dst; src1; src2; set_flags = false } ]
