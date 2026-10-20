(**
  Mba_Verified.fst — Verified MBA Engine for ASGARD-5877.
  F* 2026.08.23 + Z3 5.0.0.

  Tactics: nth_lemma + SMTPat from *_definition -> Z3 verifies bits bitwise.
  Arithmetic: Two's complement lemmas from FStar.UInt.
  Extraction: fstar.exe --codegen OCaml --extract Mba_Verified --odir . Mba_Verified.fst
*)
module Mba_Verified

open FStar.UInt
module C = FStar.Classical

let w : pos = 64
type u64 = uint_t w

(* ------------------------------------------------------------------ *)
(* Bit-extensionality                                                 *)
(* ------------------------------------------------------------------ *)

private val bit_ext : a:u64 -> b:u64 ->
  Lemma
    (requires forall (i:nat{i < w}). nth #w a i = nth #w b i)
    (ensures a = b)
let bit_ext a b = nth_lemma #w a b

(* ------------------------------------------------------------------ *)
(* Basic MBA Identities (Z3 proves each in < 0.3s)                    *)
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
(* De Morgan Laws and Bitwise Involutions                             *)
(* ------------------------------------------------------------------ *)

val mba_and_demorgan : a:u64 -> b:u64 ->
  Lemma (logand #w a b == lognot #w (logor #w (lognot #w a) (lognot #w b)))
let mba_and_demorgan a b =
  let per_bit (i:nat{i < w}) : Lemma (nth #w (logand #w a b) i =
                                       nth #w (lognot #w (logor #w (lognot #w a) (lognot #w b))) i) =
    logand_definition #w a b i;
    lognot_definition #w a i;
    lognot_definition #w b i;
    logor_definition  #w (lognot #w a) (lognot #w b) i;
    lognot_definition #w (logor #w (lognot #w a) (lognot #w b)) i
  in
  C.forall_intro per_bit;
  bit_ext (logand #w a b) (lognot #w (logor #w (lognot #w a) (lognot #w b)))

val mba_or_demorgan : a:u64 -> b:u64 ->
  Lemma (logor #w a b == lognot #w (logand #w (lognot #w a) (lognot #w b)))
let mba_or_demorgan a b =
  let per_bit (i:nat{i < w}) : Lemma (nth #w (logor #w a b) i =
                                       nth #w (lognot #w (logand #w (lognot #w a) (lognot #w b))) i) =
    logor_definition  #w a b i;
    lognot_definition #w a i;
    lognot_definition #w b i;
    logand_definition #w (lognot #w a) (lognot #w b) i;
    lognot_definition #w (logand #w (lognot #w a) (lognot #w b)) i
  in
  C.forall_intro per_bit;
  bit_ext (logor #w a b) (lognot #w (logand #w (lognot #w a) (lognot #w b)))

val mba_xor_not : a:u64 -> b:u64 ->
  Lemma (logxor #w a b == logxor #w (lognot #w a) (lognot #w b))
let mba_xor_not a b =
  let per_bit (i:nat{i < w}) : Lemma (nth #w (logxor #w a b) i =
                                       nth #w (logxor #w (lognot #w a) (lognot #w b)) i) =
    logxor_definition #w a b i;
    lognot_definition #w a i;
    lognot_definition #w b i;
    logxor_definition #w (lognot #w a) (lognot #w b) i
  in
  C.forall_intro per_bit;
  bit_ext (logxor #w a b) (logxor #w (lognot #w a) (lognot #w b))

val mba_double_not : a:u64 ->
  Lemma (lognot #w (lognot #w a) == a)
let mba_double_not a =
  let per_bit (i:nat{i < w}) : Lemma (nth #w (lognot #w (lognot #w a)) i = nth #w a i) =
    lognot_definition #w a i;
    lognot_definition #w (lognot #w a) i
  in
  C.forall_intro per_bit;
  bit_ext (lognot #w (lognot #w a)) a

val mba_not_xor : a:u64 -> b:u64 ->
  Lemma (lognot #w (logxor #w a b) == logxor #w (lognot #w a) b)
let mba_not_xor a b =
  let per_bit (i:nat{i < w}) : Lemma (nth #w (lognot #w (logxor #w a b)) i =
                                       nth #w (logxor #w (lognot #w a) b) i) =
    logxor_definition #w a b i;
    lognot_definition #w (logxor #w a b) i;
    lognot_definition #w a i;
    logxor_definition #w (lognot #w a) b i
  in
  C.forall_intro per_bit;
  bit_ext (lognot #w (logxor #w a b)) (logxor #w (lognot #w a) b)

val mba_and_not_self : a:u64 ->
  Lemma (logand #w a (lognot #w a) == 0)
let mba_and_not_self a =
  let per_bit (i:nat{i < w}) : Lemma (nth #w (logand #w a (lognot #w a)) i = nth #w 0 i) =
    logand_definition #w a (lognot #w a) i;
    lognot_definition #w a i;
    zero_nth_lemma    #w i
  in
  C.forall_intro per_bit;
  bit_ext (logand #w a (lognot #w a)) 0

val mba_or_not_self : a:u64 ->
  Lemma (logor #w a (lognot #w a) == ones w)
let mba_or_not_self a =
  let per_bit (i:nat{i < w}) : Lemma (nth #w (logor #w a (lognot #w a)) i = nth #w (ones w) i) =
    logor_definition  #w a (lognot #w a) i;
    lognot_definition #w a i;
    ones_nth_lemma    #w i
  in
  C.forall_intro per_bit;
  bit_ext (logor #w a (lognot #w a)) (ones w)

(* ------------------------------------------------------------------ *)
(* Two's Complement Arithmetic Identities                             *)
(* ------------------------------------------------------------------ *)

val mba_not_arith : a:u64 ->
  Lemma (lognot #w a == sub_mod #w (sub_mod #w 0 a) 1)
let mba_not_arith a =
  lemma_lognot_value #w a

val mba_neg_eq : a:u64 ->
  Lemma (sub_mod #w 0 a == add_mod #w (lognot #w a) 1)
let mba_neg_eq a =
  lemma_lognot_value #w a;
  lemma_add_sub_cancel #w (sub_mod #w 0 a) 1

val mba_double_neg : a:u64 ->
  Lemma (sub_mod #w 0 (sub_mod #w 0 a) == a)
let mba_double_neg a =
  lemma_add_sub_cancel #w 0 a

val mba_sub_via_not : a:u64 -> b:u64 ->
  Lemma (sub_mod #w a b == add_mod #w a (add_mod #w (lognot #w b) 1))
let mba_sub_via_not a b =
  lemma_lognot_value #w b;
  lemma_add_sub_cancel #w (sub_mod #w 0 b) 1

val mba_sub_self : a:u64 ->
  Lemma (sub_mod #w a a == 0)
let mba_sub_self a =
  lemma_sub_add_cancel #w 0 a

val mba_add_zero : a:u64 ->
  Lemma (add_mod #w a 0 == a)
let mba_add_zero a =
  lemma_add_sub_cancel #w a 0

val mba_sub_zero : a:u64 ->
  Lemma (sub_mod #w a 0 == a)
let mba_sub_zero a =
  lemma_sub_add_cancel #w a 0

(* ------------------------------------------------------------------ *)
(* AST and Semantics                                                  *)
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
  | Neg   : expr -> expr

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
  | Neg a   -> sub_mod #w 0 (eval e a)

(* ------------------------------------------------------------------ *)
(* Rewriters                                                          *)
(* ------------------------------------------------------------------ *)

(** Primary MBA rewriter: expands logic and arithmetic operations into MBA *)
val rewrite : nat -> expr -> expr
let rec rewrite depth e =
  if depth = 0 then e
  else
    let r = rewrite (depth - 1) in
    match e with
    | Var _   -> e
    | Const _ -> e
    | Add a b -> Add (r a) (r b)
    | Sub a b -> Add (r a) (Add (Not (r b)) (Const 1))
    | Xor a b -> Xor (Or  (r a) (r b)) (And (r a) (r b))
    | And a b -> Xor (Or  (r a) (r b)) (Xor (r a) (r b))
    | Or  a b -> Xor (Xor (r a) (r b)) (And (r a) (r b))
    | Not a   -> Xor (r a) (Const (ones w))
    | Neg a   -> Add (Not (r a)) (Const 1)

(** De Morgan rewriter: transforms AND/OR via double negation *)
val rewrite_demorgan : nat -> expr -> expr
let rec rewrite_demorgan depth e =
  if depth = 0 then e
  else
    let r = rewrite_demorgan (depth - 1) in
    match e with
    | Var _   -> e
    | Const _ -> e
    | Add a b -> Add (r a) (r b)
    | Sub a b -> Sub (r a) (r b)
    | Xor a b -> Xor (Not (r a)) (Not (r b))
    | And a b -> Not (Or (Not (r a)) (Not (r b)))
    | Or  a b -> Not (And (Not (r a)) (Not (r b)))
    | Not a   -> Not (r a)
    | Neg a   -> Neg (r a)

(* ------------------------------------------------------------------ *)
(* Rewriter Correctness Theorems                                      *)
(* ------------------------------------------------------------------ *)

val rewrite_sound_env : depth:nat -> e:expr -> env:env_t ->
  Lemma (eval env (rewrite depth e) == eval env e)
let rec rewrite_sound_env depth e env =
  if depth = 0 then ()
  else match e with
  | Var _ -> ()
  | Const _ -> ()
  | Add a b ->
    rewrite_sound_env (depth-1) a env;
    rewrite_sound_env (depth-1) b env
  | Sub a b ->
    rewrite_sound_env (depth-1) a env;
    rewrite_sound_env (depth-1) b env;
    mba_sub_via_not (eval env (rewrite (depth-1) a)) (eval env (rewrite (depth-1) b))
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
  | Neg a ->
    rewrite_sound_env (depth-1) a env;
    mba_neg_eq (eval env (rewrite (depth-1) a))

val rewrite_sound : depth:nat -> e:expr ->
  Lemma (forall (env:env_t). eval env (rewrite depth e) == eval env e)
let rewrite_sound depth e =
  C.forall_intro (rewrite_sound_env depth e)

val rewrite_demorgan_sound_env : depth:nat -> e:expr -> env:env_t ->
  Lemma (eval env (rewrite_demorgan depth e) == eval env e)
let rec rewrite_demorgan_sound_env depth e env =
  if depth = 0 then ()
  else match e with
  | Var _ -> ()
  | Const _ -> ()
  | Add a b ->
    rewrite_demorgan_sound_env (depth-1) a env;
    rewrite_demorgan_sound_env (depth-1) b env
  | Sub a b ->
    rewrite_demorgan_sound_env (depth-1) a env;
    rewrite_demorgan_sound_env (depth-1) b env
  | Xor a b ->
    rewrite_demorgan_sound_env (depth-1) a env;
    rewrite_demorgan_sound_env (depth-1) b env;
    mba_xor_not (eval env (rewrite_demorgan (depth-1) a)) (eval env (rewrite_demorgan (depth-1) b))
  | And a b ->
    rewrite_demorgan_sound_env (depth-1) a env;
    rewrite_demorgan_sound_env (depth-1) b env;
    mba_and_demorgan (eval env (rewrite_demorgan (depth-1) a)) (eval env (rewrite_demorgan (depth-1) b))
  | Or a b ->
    rewrite_demorgan_sound_env (depth-1) a env;
    rewrite_demorgan_sound_env (depth-1) b env;
    mba_or_demorgan (eval env (rewrite_demorgan (depth-1) a)) (eval env (rewrite_demorgan (depth-1) b))
  | Not a ->
    rewrite_demorgan_sound_env (depth-1) a env
  | Neg a ->
    rewrite_demorgan_sound_env (depth-1) a env

val rewrite_demorgan_sound : depth:nat -> e:expr ->
  Lemma (forall (env:env_t). eval env (rewrite_demorgan depth e) == eval env e)
let rewrite_demorgan_sound depth e =
  C.forall_intro (rewrite_demorgan_sound_env depth e)
