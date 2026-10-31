open Prims
type u64 = Obj.t FStar_UInt.uint_t
let two_64 : Prims.pos= Prims.parse_int "0x10000000000000000"
let mul_mod (a : u64) (b : u64) : u64= (mod) (a * b) two_64
let add_mod (a : u64) (b : u64) : u64= (mod) (a + b) two_64
let xor64 (a : u64) (b : u64) : u64= FStar_UInt.logxor (Prims.of_int 64) a b
let or64 (a : u64) (b : u64) : u64= FStar_UInt.logor (Prims.of_int 64) a b
let shl64 (a : u64) (s : Prims.nat) : u64=
  FStar_UInt.shift_left (Prims.of_int 64) a s
let shr64 (a : u64) (s : Prims.nat) : u64=
  FStar_UInt.shift_right (Prims.of_int 64) a s
let const_M : u64= Prims.parse_int "0xBF58476D1CE4E5B9"
let const_M_inv : u64= Prims.parse_int "0x96DE1B173F119089"
let const_C : u64= Prims.parse_int "0x5877CAFE1337BEEF"
let ror23 (x : u64) : u64=
  FStar_UInt.rotate_right (Prims.of_int 64) x (Prims.of_int 23)
let rol23 (x : u64) : u64=
  FStar_UInt.rotate_left (Prims.of_int 64) x (Prims.of_int 23)
let advance_key_step (k : u64) (delta : u64) : u64=
  let x = xor64 k delta in
  let rot = ror23 x in xor64 (mul_mod rot const_M) const_C
let invert_key_step (k_next : u64) (delta : u64) : u64=
  let temp1 = xor64 k_next const_C in
  let rot = mul_mod temp1 const_M_inv in let x = rol23 rot in xor64 x delta
let ensure_odd (mixed : u64) : u64= or64 mixed Prims.int_one
