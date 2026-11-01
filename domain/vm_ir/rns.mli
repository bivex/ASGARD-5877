(** Residue Number System (RNS) Representation Engine.
    Encodes 64-bit integer values into a 4-tuple of modular residues over pairwise coprime
    moduli (m1, m2, m3, m4) where M = prod(m_i) > 2^64.
    Eliminates carry-chain flag leakage and forces DSE/SMT solvers to solve non-linear Diophantine systems. *)

type rns_val = {
  r1 : int64;
  r2 : int64;
  r3 : int64;
  r4 : int64;
}

val m1 : int64
val m2 : int64
val m3 : int64
val m4 : int64

(** Garner mixed-radix precomputed inverses: inv_mi mod mj, consumed by the
    RNS C++ codegen and the decoded-CRT reconstruction. *)
val inv_m1_mod_m2 : int64
val inv_m1_mod_m3 : int64
val inv_m1_mod_m4 : int64
val inv_m2_mod_m3 : int64
val inv_m2_mod_m4 : int64
val inv_m3_mod_m4 : int64

val encode : int64 -> rns_val
val decode : rns_val -> int64

val add : rns_val -> rns_val -> rns_val
val sub : rns_val -> rns_val -> rns_val
val mul : rns_val -> rns_val -> rns_val
