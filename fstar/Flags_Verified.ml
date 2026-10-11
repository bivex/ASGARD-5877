open Prims
let w : Prims.pos= Prims.of_int 64
type u64 = Obj.t FStar_UInt.uint_t
let to_signed (x : u64) : Prims.int=
  if x >= (Prims.pow2 (Prims.of_int 63))
  then x - (Prims.pow2 (Prims.of_int 64))
  else x
let min_int64 : Prims.int= - (Prims.pow2 (Prims.of_int 63))
let max_int64 : Prims.int= (Prims.pow2 (Prims.of_int 63)) - Prims.int_one
let hw_cf_add (a : u64) (b : u64) : Prims.bool=
  (a + b) >= (Prims.pow2 (Prims.of_int 64))
let lazy_cf_add (a : u64) (b : u64) : Prims.bool=
  (FStar_UInt.add_mod w a b) < a
let hw_cf_sub (a : u64) (b : u64) : Prims.bool= a < b
let lazy_cf_sub (a : u64) (b : u64) : Prims.bool= a < b
let compute_zf (res : u64) : Prims.bool= res = Prims.int_zero
let compute_sf (res : u64) : Prims.bool= FStar_UInt.msb w res
let hw_of_add (a : u64) (b : u64) : Prims.bool=
  let sa = to_signed a in
  let sb = to_signed b in
  let sum = sa + sb in (sum < min_int64) || (sum > max_int64)
let lazy_of_add (a : u64) (b : u64) : Prims.bool=
  let dst = FStar_UInt.add_mod w a b in
  FStar_UInt.msb w
    (FStar_UInt.logand w (FStar_UInt.logxor w a dst)
       (FStar_UInt.logxor w b dst))
let hw_of_sub (a : u64) (b : u64) : Prims.bool=
  let sa = to_signed a in
  let sb = to_signed b in
  let diff = sa - sb in (diff < min_int64) || (diff > max_int64)
let lazy_of_sub (a : u64) (b : u64) : Prims.bool=
  let dst = FStar_UInt.sub_mod w a b in
  FStar_UInt.msb w
    (FStar_UInt.logand w (FStar_UInt.logxor w a b)
       (FStar_UInt.logxor w a dst))
let cond_l (sf : Prims.bool) (of_ : Prims.bool) : Prims.bool= sf <> of_
let cond_ge (sf : Prims.bool) (of_ : Prims.bool) : Prims.bool= sf = of_
let cond_le (zf : Prims.bool) (sf : Prims.bool) (of_ : Prims.bool) :
  Prims.bool= zf || (sf <> of_)
let cond_g (zf : Prims.bool) (sf : Prims.bool) (of_ : Prims.bool) :
  Prims.bool= (Prims.not zf) && (sf = of_)
let cond_b (cf : Prims.bool) : Prims.bool= cf
let cond_ae (cf : Prims.bool) : Prims.bool= Prims.not cf
let cond_be (cf : Prims.bool) (zf : Prims.bool) : Prims.bool= cf || zf
let cond_a (cf : Prims.bool) (zf : Prims.bool) : Prims.bool=
  (Prims.not cf) && (Prims.not zf)
