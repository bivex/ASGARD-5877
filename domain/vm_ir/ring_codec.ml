(** Affine ring automorphisms over Z_{2^64}: φ(x) = a*x + b (mod 2^64)
    with φ⁻¹(y) = a_inv*(y - b). Breaks SSA constant folding across build seeds. *)

type t = {
  a     : int64;   (** odd multiplier *)
  a_inv : int64;   (** a * a_inv = 1 mod 2^64 *)
  b     : int64;   (** additive shift *)
}

let gen ~rng () =
  (* a must be odd for invertibility in Z_{2^64} *)
  let a = Int64.logor (Random.State.int64 rng Int64.max_int) 1L in
  let a_inv = Rolling_key.mod_inverse_64 a in
  let b = Random.State.int64 rng Int64.max_int in
  { a; a_inv; b }

let encode t x = Int64.add (Int64.mul t.a x) t.b
let decode t y = Int64.mul t.a_inv (Int64.sub y t.b)

(** Homomorphic constant for encoded Add:
    Given dst = φ(x) + φ(y) computed as:
      φ(x) + φ(y) = (a*x + b) + (a*y + b) = a*(x+y) + 2b
    But φ(x + y) = a*(x+y) + b, so:
      φ(x + y) = φ(x) + φ(y) - b
    i.e., result = (encoded_src1 + encoded_src2) - b *)
let hom_add_fixup t = Int64.neg t.b

(** Homomorphic constant for encoded Sub:
    φ(x - y) = a*(x-y) + b = (a*x + b) - (a*y + b) + b = φ(x) - φ(y) + b
    i.e., result = encoded_src1 - encoded_src2 + b *)
let hom_sub_fixup t = t.b

(** Emit IR to encode dst_reg with codec t (φ(x) = a*x + b):
    tmp0 = dst_reg * a
    dst_reg = tmp0 + b *)
let emit_encode ~t ~dst =
  let open Ir in
  [
    Alu { op = Mul; dst; src1 = Reg dst; src2 = Imm t.a; set_flags = false };
    Alu { op = Add; dst; src1 = Reg dst; src2 = Imm t.b; set_flags = false };
  ]

(** Emit IR to decode src_reg with codec t (φ⁻¹(y) = a_inv*(y - b)):
    tmp0 = src_reg - b
    dst_reg = tmp0 * a_inv *)
let emit_decode ~t ~dst =
  let open Ir in
  [
    Alu { op = Sub; dst; src1 = Reg dst; src2 = Imm t.b; set_flags = false };
    Alu { op = Mul; dst; src1 = Reg dst; src2 = Imm t.a_inv; set_flags = false };
  ]
