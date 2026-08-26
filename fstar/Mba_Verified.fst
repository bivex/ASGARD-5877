(**
  Mba_Verified.fst — Верифицированный MBA-движок ASGARD-5877.
  F* 2026.08.23 + Z3 5.0.0.

  Тактика: nth_lemma + SMTPat из *_definition → Z3 закрывает биты побитово.
  Экстракция: fstar.exe --codegen OCaml --odir . Mba_Verified.fst
*)
module Mba_Verified

open FStar.UInt
module C = FStar.Classical

let w : pos = 64
type u64 = uint_t w

(* ------------------------------------------------------------------ *)
(* Bit-extensionality                                                   *)
(* ------------------------------------------------------------------ *)

private val bit_ext : a:u64 -> b:u64 ->
  Lemma
    (requires forall (i:nat{i < w}). nth #w a i = nth #w b i)
    (ensures a = b)
let bit_ext a b = nth_lemma #w a b

(* ------------------------------------------------------------------ *)
(* MBA-тождества (Z3 доказывает каждое за < 0.3s)                     *)
(* ------------------------------------------------------------------ *)

val mba_xor_eq : a:u64 -> b:u64 ->
  Lemma (logxor #w a b == logxor #w (logor #w a b) (logand #w a b))
let mba_xor_eq a b =
  let per_bit (i:nat{i < w}) : Lemma (nth #w (logxor #w a b) i =
                                       nth #w (logxor #w (logor #w a b) (logand #w a b)) i) =
    logxor_definition #w a b i;
    logor_definition  #w a b i;
    logand_definition #w a b i;
    logxor_definition #w (logor #w a b) (logand #w a b) i
  in
  C.forall_intro per_bit;
  bit_ext (logxor #w a b) (logxor #w (logor #w a b) (logand #w a b))

val mba_and_eq : a:u64 -> b:u64 ->
  Lemma (logand #w a b == logxor #w (logor #w a b) (logxor #w a b))
let mba_and_eq a b =
  let per_bit (i:nat{i < w}) : Lemma (nth #w (logand #w a b) i =
                                       nth #w (logxor #w (logor #w a b) (logxor #w a b)) i) =
    logand_definition #w a b i;
    logor_definition  #w a b i;
    logxor_definition #w a b i;
    logxor_definition #w (logor #w a b) (logxor #w a b) i
  in
  C.forall_intro per_bit;
  bit_ext (logand #w a b) (logxor #w (logor #w a b) (logxor #w a b))

val mba_or_eq : a:u64 -> b:u64 ->
  Lemma (logor #w a b == logxor #w (logxor #w a b) (logand #w a b))
let mba_or_eq a b =
  let per_bit (i:nat{i < w}) : Lemma (nth #w (logor #w a b) i =
                                       nth #w (logxor #w (logxor #w a b) (logand #w a b)) i) =
    logor_definition  #w a b i;
    logxor_definition #w a b i;
    logand_definition #w a b i;
    logxor_definition #w (logxor #w a b) (logand #w a b) i
  in
  C.forall_intro per_bit;
  bit_ext (logor #w a b) (logxor #w (logxor #w a b) (logand #w a b))

val mba_not_eq : a:u64 ->
  Lemma (lognot #w a == logxor #w a (ones w))
let mba_not_eq a =
  let per_bit (i:nat{i < w}) : Lemma (nth #w (lognot #w a) i =
                                       nth #w (logxor #w a (ones w)) i) =
    lognot_definition #w a i;
    ones_nth_lemma    #w i;
    logxor_definition #w a (ones w) i
  in
  C.forall_intro per_bit;
  bit_ext (lognot #w a) (logxor #w a (ones w))

(* ------------------------------------------------------------------ *)
(* AST и семантика                                                     *)
(* ------------------------------------------------------------------ *)

type expr =
  | Var   : string -> expr
  | Const : u64 -> expr
  | Add   : expr -> expr -> expr
  | Sub   : expr -> expr -> expr
  | Xor   : expr -> expr -> expr
  | And   : expr -> expr -> expr
  | Or    : expr -> expr -> expr
  | Not   : expr -> expr

type env_t = string -> u64

val eval : env_t -> expr -> u64
let rec eval e = function
  | Var s   -> e s
  | Const c -> c
  | Add a b -> add_mod #w (eval e a) (eval e b)
  | Sub a b -> sub_mod #w (eval e a) (eval e b)
  | Xor a b -> logxor  #w (eval e a) (eval e b)
  | And a b -> logand  #w (eval e a) (eval e b)
  | Or  a b -> logor   #w (eval e a) (eval e b)
  | Not a   -> lognot  #w (eval e a)

(* ------------------------------------------------------------------ *)
(* Реврайтер                                                           *)
(* ------------------------------------------------------------------ *)

val rewrite : nat -> expr -> expr
let rec rewrite depth e =
  if depth = 0 then e
  else
    let r = rewrite (depth - 1) in
    match e with
    | Xor a b -> Xor (Or  (r a) (r b)) (And (r a) (r b))
    | And a b -> Xor (Or  (r a) (r b)) (Xor (r a) (r b))
    | Or  a b -> Xor (Xor (r a) (r b)) (And (r a) (r b))
    | Not a   -> Xor (r a) (Const (ones w))
    | _       -> e

(* ------------------------------------------------------------------ *)
(* Теорема корректности реврайтера                                     *)
(* ------------------------------------------------------------------ *)

(* Shorthand: для конкретного env *)
val rewrite_sound_env : depth:nat -> e:expr -> env:env_t ->
  Lemma (eval env (rewrite depth e) == eval env e)
let rec rewrite_sound_env depth e env =
  if depth = 0 then ()
  else match e with
  | Xor a b ->
    rewrite_sound_env (depth-1) a env;
    rewrite_sound_env (depth-1) b env;
    mba_xor_eq (eval env (rewrite (depth-1) a)) (eval env (rewrite (depth-1) b))
  | And a b ->
    rewrite_sound_env (depth-1) a env;
    rewrite_sound_env (depth-1) b env;
    mba_and_eq (eval env (rewrite (depth-1) a)) (eval env (rewrite (depth-1) b))
  | Or a b ->
    rewrite_sound_env (depth-1) a env;
    rewrite_sound_env (depth-1) b env;
    mba_or_eq  (eval env (rewrite (depth-1) a)) (eval env (rewrite (depth-1) b))
  | Not a ->
    rewrite_sound_env (depth-1) a env;
    mba_not_eq (eval env (rewrite (depth-1) a))
  | _ -> ()

val rewrite_sound : depth:nat -> e:expr ->
  Lemma (forall (env:env_t). eval env (rewrite depth e) == eval env e)
let rewrite_sound depth e =
  C.forall_intro (rewrite_sound_env depth e)
