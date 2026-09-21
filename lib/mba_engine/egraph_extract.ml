open Mba
open Egraph_types

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
                    match n with
                    | EVar s -> Some (Var s, 1, 0)
                    | EConst c -> Some (Const c, 1, 0)
                    | EAdd (a, b) -> (
                        match (best a (depth - 1) visited', best b (depth - 1) visited') with
                        | Some (e1, s1, _), Some (e2, s2, _) ->
                            let e = Add (e1, e2) in
                            Some (e, 1 + s1 + s2, alternation e)
                        | _ -> None)
                    | ESub (a, b) -> (
                        match (best a (depth - 1) visited', best b (depth - 1) visited') with
                        | Some (e1, s1, _), Some (e2, s2, _) ->
                            let e = Sub (e1, e2) in
                            Some (e, 1 + s1 + s2, alternation e)
                        | _ -> None)
                    | EMul (a, b) -> (
                        match (best a (depth - 1) visited', best b (depth - 1) visited') with
                        | Some (e1, s1, _), Some (e2, s2, _) ->
                            let e = Mul (e1, e2) in
                            Some (e, 1 + s1 + s2, alternation e)
                        | _ -> None)
                    | EAnd (a, b) -> (
                        match (best a (depth - 1) visited', best b (depth - 1) visited') with
                        | Some (e1, s1, _), Some (e2, s2, _) ->
                            let e = And (e1, e2) in
                            Some (e, 1 + s1 + s2, alternation e)
                        | _ -> None)
                    | EOr (a, b) -> (
                        match (best a (depth - 1) visited', best b (depth - 1) visited') with
                        | Some (e1, s1, _), Some (e2, s2, _) ->
                            let e = Or (e1, e2) in
                            Some (e, 1 + s1 + s2, alternation e)
                        | _ -> None)
                    | EXor (a, b) -> (
                        match (best a (depth - 1) visited', best b (depth - 1) visited') with
                        | Some (e1, s1, _), Some (e2, s2, _) ->
                            let e = Xor (e1, e2) in
                            Some (e, 1 + s1 + s2, alternation e)
                        | _ -> None)
                    | ENot a -> (
                        match best a (depth - 1) visited' with
                        | Some (e1, s1, _) ->
                            let e = Not e1 in
                            Some (e, 1 + s1, alternation e)
                        | None -> None)
                    | ENeg a -> (
                        match best a (depth - 1) visited' with
                        | Some (e1, s1, _) ->
                            let e = Neg e1 in
                            Some (e, 1 + s1, alternation e)
                        | None -> None))
                  !nodes
              in
              let pick = function
                | [] -> (
                    match Hashtbl.find_opt min_ast cid with
                    | Some (e, s) -> Some (e, s, alternation e)
                    | None -> None)
                | [ single ] -> Some single
                | cs ->
                    (* Rank candidate nodes by (alternation, size); randomize ties *)
                    let sorted =
                      List.sort
                        (fun (_, s1, a1) (_, s2, a2) ->
                          if a1 <> a2 then compare a2 a1 else compare s2 s1)
                        cs
                    in
                    let top_alt = match sorted with (_, _, a) :: _ -> a | [] -> 0 in
                    let top_size = match sorted with (_, s, _) :: _ -> s | [] -> 0 in
                    let best_group =
                      List.filter
                        (fun (_, s, a) -> a = top_alt && s = top_size)
                        sorted
                    in
                    let idx = Random.State.int rng (List.length best_group) in
                    Some (List.nth best_group idx)
              in
              let res = pick cands in
              (match res with Some r -> Hashtbl.replace memo (cid, depth) r | None -> ());
              res
  in
  match best root max_depth [] with
  | Some res -> res
  | None -> (
      match Hashtbl.find_opt min_ast root with
      | Some (e, s) -> (e, s, alternation e)
      | None -> (Var "x", 1, 0))
