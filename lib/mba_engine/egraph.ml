open Vm_ir
open Mba
include Egraph_types
include Egraph_rules

let ast_size = Egraph_extract.ast_size
let op_count = Egraph_extract.op_count
let alternation = Egraph_extract.alternation
let extract = Egraph_extract.extract

type config = { node_limit : int; time_budget_s : float; iter_limit : int }

let default_config = { node_limit = 2000; time_budget_s = 1.0; iter_limit = 24 }

let shuffle_inplace rng a n =
  (* Reset indices 0..n-1, then Fisher-Yates in-place — no allocation *)
  for i = 0 to n - 1 do a.(i) <- i done;
  for i = n - 1 downto 1 do
    let j = Random.State.int rng (i + 1) in
    let t = a.(i) in
    a.(i) <- a.(j);
    a.(j) <- t
  done

let saturate ~rng ~config eg =
  let rules_arr = Array.of_list rules in
  let n_rules = Array.length rules_arr in
  let t0 = Sys.time () in
  let iters = ref 0 in
  let stop = ref false in
  (* Pre-allocate scratch arrays: no heap allocation inside the loop *)
  let rule_order = Array.make n_rules 0 in
  let over_budget () =
    eg.next_id >= config.node_limit
    || Sys.time () -. t0 >= config.time_budget_s
  in
  while not !stop do
    incr iters;
    shuffle_inplace rng rule_order n_rules;
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
         rule_order
     with Exit -> ());
    (* 2. Apply phase: instantiate and merge with budget checks *)
    let matches_arr = Array.of_list !matches in
    let n_matches = Array.length matches_arr in
    let app_order = Array.make n_matches 0 in
    shuffle_inplace rng app_order n_matches;
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
  let (e', s, a) = extract ~rng eg root in
  ( e',
    { iterations = iters;
      classes = Hashtbl.length eg.classes;
      nodes = node_count eg;
      unions = eg.unions;
      extracted_size = s;
      extracted_alternation = a } )

let expand ~rng ?(config = default_config) e = fst (expand_full ~rng ~config e)

let default_op_config = { node_limit = 80; time_budget_s = 0.05; iter_limit = 4 }

let obfuscate_alu ~rng ?(config = default_op_config) ~dst ~src1 ~src2 op =
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
