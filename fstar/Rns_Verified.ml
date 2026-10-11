open Prims
let m1 : Prims.pos= Prims.of_int 65537
let m2 : Prims.pos= Prims.of_int 65521
let m3 : Prims.pos= Prims.of_int 65519
let m4 : Prims.pos= Prims.of_int 65497
let dynamic_range_M : Prims.pos= ((m1 * m2) * m3) * m4
let inv_m1_m2 : Prims.pos= Prims.of_int 61426
let inv_m1_m3 : Prims.pos= Prims.of_int 3640
let inv_m1_m4 : Prims.pos= Prims.of_int 11462
let inv_m2_m3 : Prims.pos= Prims.of_int 32760
let inv_m2_m4 : Prims.pos= Prims.of_int 62768
let inv_m3_m4 : Prims.pos= Prims.of_int 20840
type rns_val = {
  r1: Prims.nat ;
  r2: Prims.nat ;
  r3: Prims.nat ;
  r4: Prims.nat }
let __proj__Mkrns_val__item__r1 (projectee : rns_val) : Prims.nat=
  match projectee with | { r1; r2; r3; r4;_} -> r1
let __proj__Mkrns_val__item__r2 (projectee : rns_val) : Prims.nat=
  match projectee with | { r1; r2; r3; r4;_} -> r2
let __proj__Mkrns_val__item__r3 (projectee : rns_val) : Prims.nat=
  match projectee with | { r1; r2; r3; r4;_} -> r3
let __proj__Mkrns_val__item__r4 (projectee : rns_val) : Prims.nat=
  match projectee with | { r1; r2; r3; r4;_} -> r4
let mod_pos (a : Prims.int) (m : Prims.pos) : Prims.nat=
  (mod) (((mod) a m) + m) m
let encode (x : Prims.nat) : rns_val=
  {
    r1 = ((mod) x m1);
    r2 = ((mod) x m2);
    r3 = ((mod) x m3);
    r4 = ((mod) x m4)
  }
let add (a : rns_val) (b : rns_val) : rns_val=
  {
    r1 = ((mod) (a.r1 + b.r1) m1);
    r2 = ((mod) (a.r2 + b.r2) m2);
    r3 = ((mod) (a.r3 + b.r3) m3);
    r4 = ((mod) (a.r4 + b.r4) m4)
  }
let sub (a : rns_val) (b : rns_val) : rns_val=
  {
    r1 = (mod_pos (a.r1 - b.r1) m1);
    r2 = (mod_pos (a.r2 - b.r2) m2);
    r3 = (mod_pos (a.r3 - b.r3) m3);
    r4 = (mod_pos (a.r4 - b.r4) m4)
  }
let mul (a : rns_val) (b : rns_val) : rns_val=
  {
    r1 = ((mod) (a.r1 * b.r1) m1);
    r2 = ((mod) (a.r2 * b.r2) m2);
    r3 = ((mod) (a.r3 * b.r3) m3);
    r4 = ((mod) (a.r4 * b.r4) m4)
  }
let garner_v1 (r : rns_val) : Prims.nat= (mod) r.r1 m1
let garner_v2 (r : rns_val) : Prims.nat=
  let v1 = garner_v1 r in
  let diff = mod_pos (r.r2 - v1) m2 in (mod) (diff * inv_m1_m2) m2
let garner_v3 (r : rns_val) : Prims.nat=
  let v1 = garner_v1 r in
  let v2 = garner_v2 r in
  let diff1 = mod_pos (r.r3 - v1) m3 in
  let term1 = (mod) (diff1 * inv_m1_m3) m3 in
  let diff2 = mod_pos (term1 - v2) m3 in (mod) (diff2 * inv_m2_m3) m3
let garner_v4 (r : rns_val) : Prims.nat=
  let v1 = garner_v1 r in
  let v2 = garner_v2 r in
  let v3 = garner_v3 r in
  let diff1 = mod_pos (r.r4 - v1) m4 in
  let term1 = (mod) (diff1 * inv_m1_m4) m4 in
  let diff2 = mod_pos (term1 - v2) m4 in
  let term2 = (mod) (diff2 * inv_m2_m4) m4 in
  let diff3 = mod_pos (term2 - v3) m4 in (mod) (diff3 * inv_m3_m4) m4
let decode (r : rns_val) : Prims.nat=
  let v1 = garner_v1 r in
  let v2 = garner_v2 r in
  let v3 = garner_v3 r in
  let v4 = garner_v4 r in v1 + (m1 * (v2 + (m2 * (v3 + (m3 * v4)))))
