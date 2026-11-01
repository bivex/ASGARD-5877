open Prims
type u64 = Obj.t FStar_UInt.uint_t
let two_64 : Prims.pos= Prims.parse_int "0x10000000000000000"
let mul_mod (a : u64) (b : u64) : u64= (mod) (a * b) two_64
let add_mod (a : u64) (b : u64) : u64= (mod) (a + b) two_64
let sub_mod (a : u64) (b : u64) : u64= (mod) ((a - b) + two_64) two_64
let xor64 (a : u64) (b : u64) : u64= FStar_UInt.logxor (Prims.of_int 64) a b
let land64 (a : u64) (b : u64) : u64= FStar_UInt.logand (Prims.of_int 64) a b
let m_even : u64= Prims.parse_int "0x5555555555555555"
let m_odd : u64= Prims.parse_int "0xAAAAAAAAAAAAAAAA"
let moser_pack (v : u64) : u64=
  let x_plane = land64 v m_even in
  let y_plane = land64 v m_odd in
  add_mod x_plane (mul_mod y_plane Prims.int_one)
let moser_unpack (w : u64) : u64=
  let x_half = land64 w (Prims.parse_int "0x00000000FFFFFFFF") in
  let y_half =
    (mod) (w / (Prims.parse_int "0x100000000"))
      (Prims.parse_int "0x100000000") in
  add_mod x_half (mul_mod y_half Prims.int_one)
let is_odd (a : u64) : Prims.bool= ((mod) a (Prims.of_int 2)) = Prims.int_one
let nr_step (alpha : u64) (x : u64) : u64=
  mul_mod x (sub_mod (Prims.of_int 2) (mul_mod alpha x))
let nr_inv5 (alpha : u64) : u64=
  let x0 = nr_step alpha alpha in
  let x1 = nr_step alpha x0 in
  let x2 = nr_step alpha x1 in
  let x3 = nr_step alpha x2 in let x4 = nr_step alpha x3 in nr_step alpha x4
let nibble (packed : u64) (i : Prims.nat) : Prims.nat=
  (mod) (packed / (Prims.pow2 ((Prims.of_int 4) * i))) (Prims.of_int 16)
let indices16 : Prims.nat Prims.list=
  [Prims.int_zero;
  Prims.int_one;
  Prims.of_int 2;
  Prims.of_int 3;
  Prims.of_int 4;
  Prims.of_int 5;
  Prims.of_int 6;
  Prims.of_int 7;
  Prims.of_int 8;
  Prims.of_int 9;
  Prims.of_int 10;
  Prims.of_int 11;
  Prims.of_int 12;
  Prims.of_int 13;
  Prims.of_int 14;
  Prims.of_int 15]
let rec no_duplicates (l : Prims.nat Prims.list) : Prims.bool=
  match l with
  | [] -> true
  | x::rest ->
      (FStar_List_Tot_Base.for_all (fun y -> x <> y) rest) &&
        (no_duplicates rest)
let is_permutation16 (packed : u64) : Prims.bool=
  let ns = FStar_List_Tot_Base.map (nibble packed) indices16 in
  no_duplicates ns
let is_fix_free (packed : u64) : Prims.bool=
  FStar_List_Tot_Base.for_all (fun i -> (nibble packed i) <> i) indices16
let compose_perm (p : u64) (q : u64) (i : Prims.nat) : Prims.nat=
  nibble q (nibble p i)
let identity16 : u64= Prims.parse_int "0x76543210FEDCBA98"
let rec ctz_nat (t : Prims.pos) : Prims.nat=
  if ((mod) t (Prims.of_int 2)) = Prims.int_one
  then Prims.int_zero
  else Prims.int_one + (ctz_nat (t / (Prims.of_int 2)))
let ruler_a001511 (t : Prims.pos) : Prims.pos= Prims.int_one + (ctz_nat t)
