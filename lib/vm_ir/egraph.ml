type expr =
  | Const of int64
  | Var of Register.t
  | Add of expr * expr
  | Sub of expr * expr
  | Mul of expr * expr
  | Xor of expr * expr
  | And of expr * expr
  | Or of expr * expr
  | Neg of expr
  | Not of expr

type eclass_id = int

type enode =
  | EConst of int64
  | EVar of Register.t
  | EAdd of eclass_id * eclass_id
  | ESub of eclass_id * eclass_id
  | EMul of eclass_id * eclass_id
  | EXor of eclass_id * eclass_id
  | EAnd of eclass_id * eclass_id
  | EOr of eclass_id * eclass_id
  | ENeg of eclass_id
  | ENot of eclass_id

type eclass = {
  id : eclass_id;
  mutable nodes : enode list;
}

type t = {
  mutable next_id : int;
  union_find : (eclass_id, eclass_id) Hashtbl.t;
  classes : (eclass_id, eclass) Hashtbl.t;
  hashcons : (enode, eclass_id) Hashtbl.t;
}

let create () : t =
  {
    next_id = 0;
    union_find = Hashtbl.create 64;
    classes = Hashtbl.create 64;
    hashcons = Hashtbl.create 64;
  }

let rec find (t : t) (id : eclass_id) : eclass_id =
  match Hashtbl.find_opt t.union_find id with
  | None -> id
  | Some parent ->
      if parent = id then id
      else
        let root = find t parent in
        Hashtbl.replace t.union_find id root;
        root

let canonicalize_node (t : t) = function
  | (EConst _ | EVar _) as n -> n
  | EAdd (a, b) -> EAdd (find t a, find t b)
  | ESub (a, b) -> ESub (find t a, find t b)
  | EMul (a, b) -> EMul (find t a, find t b)
  | EXor (a, b) -> EXor (find t a, find t b)
  | EAnd (a, b) -> EAnd (find t a, find t b)
  | EOr (a, b)  -> EOr (find t a, find t b)
  | ENeg a      -> ENeg (find t a)
  | ENot a      -> ENot (find t a)

let add_node (t : t) (n : enode) : eclass_id =
  let canon = canonicalize_node t n in
  match Hashtbl.find_opt t.hashcons canon with
  | Some id -> find t id
  | None ->
      let id = t.next_id in
      t.next_id <- t.next_id + 1;
      let cls = { id; nodes = [ canon ] } in
      Hashtbl.replace t.classes id cls;
      Hashtbl.replace t.hashcons canon id;
      id

let rec add (t : t) = function
  | Const c -> add_node t (EConst c)
  | Var v -> add_node t (EVar v)
  | Add (a, b) -> add_node t (EAdd (add t a, add t b))
  | Sub (a, b) -> add_node t (ESub (add t a, add t b))
  | Mul (a, b) -> add_node t (EMul (add t a, add t b))
  | Xor (a, b) -> add_node t (EXor (add t a, add t b))
  | And (a, b) -> add_node t (EAnd (add t a, add t b))
  | Or (a, b)  -> add_node t (EOr (add t a, add t b))
  | Neg a      -> add_node t (ENeg (add t a))
  | Not a      -> add_node t (ENot (add t a))

let union (t : t) (id1 : eclass_id) (id2 : eclass_id) : unit =
  let root1 = find t id1 in
  let root2 = find t id2 in
  if root1 <> root2 then begin
    Hashtbl.replace t.union_find root2 root1;
    let cls1 = Hashtbl.find t.classes root1 in
    let cls2 = Hashtbl.find t.classes root2 in
    (* Deduplicating merge *)
    let rec merge_unique acc = function
      | [] -> acc
      | n :: rest ->
          if List.mem n acc then merge_unique acc rest
          else merge_unique (n :: acc) rest
    in
    cls1.nodes <- merge_unique cls1.nodes cls2.nodes
  end

let rebuild (t : t) : unit =
  Hashtbl.clear t.hashcons;
  Hashtbl.iter (fun id cls ->
    cls.nodes <- List.map (canonicalize_node t) cls.nodes;
    List.iter (fun n -> Hashtbl.replace t.hashcons n id) cls.nodes
  ) t.classes

(** Equality saturation with MBA & modular algebraic expansion rules *)
let saturate ?(max_iters = 3) ?rng (t : t) : unit =
  ignore rng;
  let applied_rules = Hashtbl.create 64 in
  for _ = 1 to max_iters do
    let pending_unions = ref [] in
    Hashtbl.iter (fun id cls ->
      List.iter (fun node ->
        let key = (id, node) in
        if not (Hashtbl.mem applied_rules key) then begin
          Hashtbl.replace applied_rules key true;
          match node with
          | EXor (a, b) ->
              (* Rule: a ^ b == (a | b) - (a & b) *)
              let or_node = add_node t (EOr (a, b)) in
              let and_node = add_node t (EAnd (a, b)) in
              let sub_node = add_node t (ESub (or_node, and_node)) in
              pending_unions := (id, sub_node) :: !pending_unions
          | EAdd (a, b) ->
              (* Rule: a + b == (a ^ b) + 2 * (a & b) *)
              let xor_node = add_node t (EXor (a, b)) in
              let and_node = add_node t (EAnd (a, b)) in
              let two_node = add_node t (EConst 2L) in
              let mul_node = add_node t (EMul (two_node, and_node)) in
              let add_node = add_node t (EAdd (xor_node, mul_node)) in
              pending_unions := (id, add_node) :: !pending_unions
          | _ -> ()
        end
      ) cls.nodes
    ) t.classes;
    if !pending_unions <> [] then begin
      List.iter (fun (id1, id2) -> union t id1 id2) !pending_unions;
      rebuild t
    end
  done

(** Cost metric maximizing AST complexity (inverted cost function) *)
let rec complexity_of_expr = function
  | Const _ | Var _ -> 1
  | Neg a | Not a -> 1 + complexity_of_expr a
  | Add (a, b) | Sub (a, b) | Mul (a, b) | Xor (a, b) | And (a, b) | Or (a, b) ->
      2 + complexity_of_expr a + complexity_of_expr b

let extract_max_complexity (t : t) (root : eclass_id) : expr =
  let visited = Hashtbl.create 32 in
  let rec extract id =
    let can_id = find t id in
    match Hashtbl.find_opt visited can_id with
    | Some e -> e
    | None ->
        let cls = Hashtbl.find t.classes can_id in
        let best = ref (Const 0L) in
        let best_cost = ref (-1) in
        List.iter (fun node ->
          let exp = match node with
            | EConst c -> Const c
            | EVar v -> Var v
            | EAdd (a, b) -> Add (extract a, extract b)
            | ESub (a, b) -> Sub (extract a, extract b)
            | EMul (a, b) -> Mul (extract a, extract b)
            | EXor (a, b) -> Xor (extract a, extract b)
            | EAnd (a, b) -> And (extract a, extract b)
            | EOr (a, b)  -> Or (extract a, extract b)
            | ENeg a      -> Neg (extract a)
            | ENot a      -> Not (extract a)
          in
          let cost = complexity_of_expr exp in
          if cost > !best_cost then begin
            best_cost := cost;
            best := exp
          end
        ) cls.nodes;
        Hashtbl.replace visited can_id !best;
        !best
  in
  extract root
