open Prims
let w : Prims.pos= Prims.of_int 64
type u64 = Obj.t FStar_UInt.uint_t
type expr =
  | Var of Prims.string 
  | Const of u64 
  | Add of expr * expr 
  | Sub of expr * expr 
  | Xor of expr * expr 
  | And of expr * expr 
  | Or of expr * expr 
  | Not of expr 
let uu___is_Var (projectee : expr) : Prims.bool=
  match projectee with | Var _0 -> true | uu___ -> false
let __proj__Var__item___0 (projectee : expr) : Prims.string=
  match projectee with | Var _0 -> _0
let uu___is_Const (projectee : expr) : Prims.bool=
  match projectee with | Const _0 -> true | uu___ -> false
let __proj__Const__item___0 (projectee : expr) : u64=
  match projectee with | Const _0 -> _0
let uu___is_Add (projectee : expr) : Prims.bool=
  match projectee with | Add (_0, _1) -> true | uu___ -> false
let __proj__Add__item___0 (projectee : expr) : expr=
  match projectee with | Add (_0, _1) -> _0
let __proj__Add__item___1 (projectee : expr) : expr=
  match projectee with | Add (_0, _1) -> _1
let uu___is_Sub (projectee : expr) : Prims.bool=
  match projectee with | Sub (_0, _1) -> true | uu___ -> false
let __proj__Sub__item___0 (projectee : expr) : expr=
  match projectee with | Sub (_0, _1) -> _0
let __proj__Sub__item___1 (projectee : expr) : expr=
  match projectee with | Sub (_0, _1) -> _1
let uu___is_Xor (projectee : expr) : Prims.bool=
  match projectee with | Xor (_0, _1) -> true | uu___ -> false
let __proj__Xor__item___0 (projectee : expr) : expr=
  match projectee with | Xor (_0, _1) -> _0
let __proj__Xor__item___1 (projectee : expr) : expr=
  match projectee with | Xor (_0, _1) -> _1
let uu___is_And (projectee : expr) : Prims.bool=
  match projectee with | And (_0, _1) -> true | uu___ -> false
let __proj__And__item___0 (projectee : expr) : expr=
  match projectee with | And (_0, _1) -> _0
let __proj__And__item___1 (projectee : expr) : expr=
  match projectee with | And (_0, _1) -> _1
let uu___is_Or (projectee : expr) : Prims.bool=
  match projectee with | Or (_0, _1) -> true | uu___ -> false
let __proj__Or__item___0 (projectee : expr) : expr=
  match projectee with | Or (_0, _1) -> _0
let __proj__Or__item___1 (projectee : expr) : expr=
  match projectee with | Or (_0, _1) -> _1
let uu___is_Not (projectee : expr) : Prims.bool=
  match projectee with | Not _0 -> true | uu___ -> false
let __proj__Not__item___0 (projectee : expr) : expr=
  match projectee with | Not _0 -> _0
type env_t = Prims.string -> u64
let rec eval (e : env_t) (uu___ : expr) : u64=
  match uu___ with
  | Var s -> e s
  | Const c -> c
  | Add (a, b) -> FStar_UInt.add_mod w (eval e a) (eval e b)
  | Sub (a, b) -> FStar_UInt.sub_mod w (eval e a) (eval e b)
  | Xor (a, b) -> FStar_UInt.logxor w (eval e a) (eval e b)
  | And (a, b) -> FStar_UInt.logand w (eval e a) (eval e b)
  | Or (a, b) -> FStar_UInt.logor w (eval e a) (eval e b)
  | Not a -> FStar_UInt.lognot w (eval e a)
let rec rewrite (depth : Prims.nat) (e : expr) : expr=
  if depth = Prims.int_zero
  then e
  else
    (let r = rewrite (depth - Prims.int_one) in
     match e with
     | Xor (a, b) -> Xor ((Or ((r a), (r b))), (And ((r a), (r b))))
     | And (a, b) -> Xor ((Or ((r a), (r b))), (Xor ((r a), (r b))))
     | Or (a, b) -> Xor ((Xor ((r a), (r b))), (And ((r a), (r b))))
     | Not a -> Xor ((r a), (Const (FStar_UInt.ones w)))
     | uu___ -> e)
