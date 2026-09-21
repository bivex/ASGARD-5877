open Mba

let mask_even = 0x5555555555555555L
let mask_odd = -0x5555555555555556L (* 0xAAAAAAAAAAAAAAAA in two's complement *)

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
