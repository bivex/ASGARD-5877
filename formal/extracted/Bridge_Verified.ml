open Prims
type u64 = Obj.t FStar_UInt.uint_t
let add64 (a : u64) (b : u64) : u64= FStar_UInt.add_mod (Prims.of_int 64) a b
let sub64 (a : u64) (b : u64) : u64= FStar_UInt.sub_mod (Prims.of_int 64) a b
let mul64 (a : u64) (b : u64) : u64= FStar_UInt.mul_mod (Prims.of_int 64) a b
let xor64 (a : u64) (b : u64) : u64= FStar_UInt.logxor (Prims.of_int 64) a b
let rol64 (a : u64) (s : Prims.nat) : u64=
  FStar_UInt.rotate_left (Prims.of_int 64) a s
let ror64 (a : u64) (s : Prims.nat) : u64=
  FStar_UInt.rotate_right (Prims.of_int 64) a s
let nr_step (a : u64) (x : u64) : u64=
  mul64 x (sub64 (Prims.of_int 2) (mul64 a x))
let mod_inverse_64_iter (a : u64) : u64=
  let x0 = Prims.int_one in
  let x1 = nr_step a x0 in
  let x2 = nr_step a x1 in
  let x3 = nr_step a x2 in
  let x4 = nr_step a x3 in
  let x5 = nr_step a x4 in let x6 = nr_step a x5 in x6
let golden_ratio : u64= Prims.parse_int "0x9E3779B97F4A7C15"
let update_trace_digest (prev : u64) (opcode : u64) (vip : u64) : u64=
  let k1 = rol64 prev (Prims.of_int 13) in
  let term = add64 opcode (mul64 vip golden_ratio) in xor64 k1 term
let invert_trace_digest (next_d : u64) (opcode : u64) (vip : u64) : u64=
  let term = add64 opcode (mul64 vip golden_ratio) in
  let k1 = xor64 next_d term in ror64 k1 (Prims.of_int 13)
type vec4 = {
  v0: u64 ;
  v1: u64 ;
  v2: u64 ;
  v3: u64 }
let __proj__Mkvec4__item__v0 (projectee : vec4) : u64=
  match projectee with | { v0; v1; v2; v3;_} -> v0
let __proj__Mkvec4__item__v1 (projectee : vec4) : u64=
  match projectee with | { v0; v1; v2; v3;_} -> v1
let __proj__Mkvec4__item__v2 (projectee : vec4) : u64=
  match projectee with | { v0; v1; v2; v3;_} -> v2
let __proj__Mkvec4__item__v3 (projectee : vec4) : u64=
  match projectee with | { v0; v1; v2; v3;_} -> v3
let mask_for_channel (digest : u64) (ch : Prims.nat) : u64=
  let shift =
    (mod) ((ch * (Prims.of_int 3)) + (Prims.of_int 7)) (Prims.of_int 64) in
  rol64 digest shift
let apply_mask (v : vec4) (digest : u64) : vec4=
  {
    v0 = (xor64 v.v0 (mask_for_channel digest Prims.int_zero));
    v1 = (xor64 v.v1 (mask_for_channel digest Prims.int_one));
    v2 = (xor64 v.v2 (mask_for_channel digest (Prims.of_int 2)));
    v3 = (xor64 v.v3 (mask_for_channel digest (Prims.of_int 3)))
  }
type mat4 =
  {
  m00: u64 ;
  m01: u64 ;
  m02: u64 ;
  m03: u64 ;
  m10: u64 ;
  m11: u64 ;
  m12: u64 ;
  m13: u64 ;
  m20: u64 ;
  m21: u64 ;
  m22: u64 ;
  m23: u64 ;
  m30: u64 ;
  m31: u64 ;
  m32: u64 ;
  m33: u64 }
let __proj__Mkmat4__item__m00 (projectee : mat4) : u64=
  match projectee with
  | { m00; m01; m02; m03; m10; m11; m12; m13; m20; m21; m22; m23; m30; 
      m31; m32; m33;_} -> m00
let __proj__Mkmat4__item__m01 (projectee : mat4) : u64=
  match projectee with
  | { m00; m01; m02; m03; m10; m11; m12; m13; m20; m21; m22; m23; m30; 
      m31; m32; m33;_} -> m01
let __proj__Mkmat4__item__m02 (projectee : mat4) : u64=
  match projectee with
  | { m00; m01; m02; m03; m10; m11; m12; m13; m20; m21; m22; m23; m30; 
      m31; m32; m33;_} -> m02
let __proj__Mkmat4__item__m03 (projectee : mat4) : u64=
  match projectee with
  | { m00; m01; m02; m03; m10; m11; m12; m13; m20; m21; m22; m23; m30; 
      m31; m32; m33;_} -> m03
let __proj__Mkmat4__item__m10 (projectee : mat4) : u64=
  match projectee with
  | { m00; m01; m02; m03; m10; m11; m12; m13; m20; m21; m22; m23; m30; 
      m31; m32; m33;_} -> m10
let __proj__Mkmat4__item__m11 (projectee : mat4) : u64=
  match projectee with
  | { m00; m01; m02; m03; m10; m11; m12; m13; m20; m21; m22; m23; m30; 
      m31; m32; m33;_} -> m11
let __proj__Mkmat4__item__m12 (projectee : mat4) : u64=
  match projectee with
  | { m00; m01; m02; m03; m10; m11; m12; m13; m20; m21; m22; m23; m30; 
      m31; m32; m33;_} -> m12
let __proj__Mkmat4__item__m13 (projectee : mat4) : u64=
  match projectee with
  | { m00; m01; m02; m03; m10; m11; m12; m13; m20; m21; m22; m23; m30; 
      m31; m32; m33;_} -> m13
let __proj__Mkmat4__item__m20 (projectee : mat4) : u64=
  match projectee with
  | { m00; m01; m02; m03; m10; m11; m12; m13; m20; m21; m22; m23; m30; 
      m31; m32; m33;_} -> m20
let __proj__Mkmat4__item__m21 (projectee : mat4) : u64=
  match projectee with
  | { m00; m01; m02; m03; m10; m11; m12; m13; m20; m21; m22; m23; m30; 
      m31; m32; m33;_} -> m21
let __proj__Mkmat4__item__m22 (projectee : mat4) : u64=
  match projectee with
  | { m00; m01; m02; m03; m10; m11; m12; m13; m20; m21; m22; m23; m30; 
      m31; m32; m33;_} -> m22
let __proj__Mkmat4__item__m23 (projectee : mat4) : u64=
  match projectee with
  | { m00; m01; m02; m03; m10; m11; m12; m13; m20; m21; m22; m23; m30; 
      m31; m32; m33;_} -> m23
let __proj__Mkmat4__item__m30 (projectee : mat4) : u64=
  match projectee with
  | { m00; m01; m02; m03; m10; m11; m12; m13; m20; m21; m22; m23; m30; 
      m31; m32; m33;_} -> m30
let __proj__Mkmat4__item__m31 (projectee : mat4) : u64=
  match projectee with
  | { m00; m01; m02; m03; m10; m11; m12; m13; m20; m21; m22; m23; m30; 
      m31; m32; m33;_} -> m31
let __proj__Mkmat4__item__m32 (projectee : mat4) : u64=
  match projectee with
  | { m00; m01; m02; m03; m10; m11; m12; m13; m20; m21; m22; m23; m30; 
      m31; m32; m33;_} -> m32
let __proj__Mkmat4__item__m33 (projectee : mat4) : u64=
  match projectee with
  | { m00; m01; m02; m03; m10; m11; m12; m13; m20; m21; m22; m23; m30; 
      m31; m32; m33;_} -> m33
let mat4_mul_vec (m : mat4) (v : vec4) : vec4=
  {
    v0 =
      (add64 (mul64 m.m00 v.v0)
         (add64 (mul64 m.m01 v.v1)
            (add64 (mul64 m.m02 v.v2) (mul64 m.m03 v.v3))));
    v1 =
      (add64 (mul64 m.m10 v.v0)
         (add64 (mul64 m.m11 v.v1)
            (add64 (mul64 m.m12 v.v2) (mul64 m.m13 v.v3))));
    v2 =
      (add64 (mul64 m.m20 v.v0)
         (add64 (mul64 m.m21 v.v1)
            (add64 (mul64 m.m22 v.v2) (mul64 m.m23 v.v3))));
    v3 =
      (add64 (mul64 m.m30 v.v0)
         (add64 (mul64 m.m31 v.v1)
            (add64 (mul64 m.m32 v.v2) (mul64 m.m33 v.v3))))
  }
type affine_bridge = {
  fwd_mat: mat4 ;
  inv_mat: mat4 }
let __proj__Mkaffine_bridge__item__fwd_mat (projectee : affine_bridge) :
  mat4= match projectee with | { fwd_mat; inv_mat;_} -> fwd_mat
let __proj__Mkaffine_bridge__item__inv_mat (projectee : affine_bridge) :
  mat4= match projectee with | { fwd_mat; inv_mat;_} -> inv_mat
let forward_morph (b : affine_bridge) (v : vec4) (digest : u64) : vec4=
  let transformed = mat4_mul_vec b.fwd_mat v in apply_mask transformed digest
let inverse_morph (b : affine_bridge) (v_morph : vec4) (digest : u64) : 
  vec4=
  let unmasked = apply_mask v_morph digest in mat4_mul_vec b.inv_mat unmasked
