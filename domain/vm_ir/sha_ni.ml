(* The x86 SHA extensions (SHA-NI).

   Every instruction works on the four 32-bit words of a 128-bit vector
   register.  The words are little-endian: word 0 is the low half of lane 0,
   word 1 the high half of lane 0, word 2 the low half of lane 1 and word 3
   the high half of lane 1.

   The operations follow the Intel SDM (the "SHA" CPUID feature). *)

let mask32 = 0xFFFFFFFFL

let w32 x = Int64.logand x mask32

let add32 a b = w32 (Int64.add a b)

let rol32 x n =
  let n = n land 31 in
  let x = w32 x in
  if n = 0 then x
  else w32 (Int64.logor (Int64.shift_left x n) (Int64.shift_right_logical x (32 - n)))

let ror32 x n =
  let n = n land 31 in
  let x = w32 x in
  if n = 0 then x
  else w32 (Int64.logor (Int64.shift_right_logical x n) (Int64.shift_left x (32 - n)))

(* The four SHA-1 functions and their round constants.  The immediate of
   SHA1RNDS4 selects the pair: 0 covers the rounds 0..19, 1 the rounds
   20..39, 2 the rounds 40..59 and 3 the rounds 60..79. *)
let sha1_f round b c d =
  match round with
  | 0 -> Int64.logor (Int64.logand b c) (Int64.logand (Int64.lognot b) d)
  | 1 | 3 -> Int64.logxor (Int64.logxor b c) d
  | _ -> Int64.logxor (Int64.logxor (Int64.logand b c) (Int64.logand b d)) (Int64.logand c d)

let sha1_k round =
  match round with
  | 0 -> 0x5A827999L
  | 1 -> 0x6ED9EBA1L
  | 2 -> 0x8F1BBCDCL
  | _ -> 0xCA62C1D6L

let sha256_ch x y z = Int64.logxor (Int64.logand x y) (Int64.logand (Int64.lognot x) z)

let sha256_maj x y z =
  Int64.logxor (Int64.logxor (Int64.logand x y) (Int64.logand x z)) (Int64.logand y z)

let sha256_sigma0 x = Int64.logxor (Int64.logxor (ror32 x 2) (ror32 x 13)) (ror32 x 22)

let sha256_sigma1 x = Int64.logxor (Int64.logxor (ror32 x 6) (ror32 x 11)) (ror32 x 25)

(* SHA1RNDS4: four SHA-1 rounds.  The destination holds the state (A, B, C,
   D), the source the four pre-computed message words (the first one already
   carries the previous E) and the immediate selects the round function and
   its constant. *)
let sha1rnds4 (imm : int) (dst : int64 array) (src : int64 array) =
  let round = imm land 3 in
  let f = sha1_f round in
  let k = sha1_k round in
  let a = ref dst.(0) and b = ref dst.(1) and c = ref dst.(2) and d = ref dst.(3) in
  let e = ref 0L in
  for i = 0 to 3 do
    let wi = src.(i) in
    let a_new = add32 (add32 (f !b !c !d) (rol32 !a 5)) (add32 (add32 wi !e) k) in
    let b_new = !a and c_new = rol32 !b 30 and d_new = !c and e_new = !d in
    a := a_new;
    b := b_new;
    c := c_new;
    d := d_new;
    e := e_new
  done;
  [| !a; !b; !c; !d |]

(* SHA1NEXTE: the state variable E after four rounds, added to the scheduled
   message words. *)
let sha1nexte (dst : int64 array) (src : int64 array) =
  let tmp = rol32 dst.(0) 30 in
  [| add32 src.(0) tmp; src.(1); src.(2); src.(3) |]

(* SHA1MSG1: the intermediate calculation of the next four message words. *)
let sha1msg1 (dst : int64 array) (src : int64 array) =
  [|
    w32 (Int64.logxor dst.(2) dst.(0));
    w32 (Int64.logxor dst.(3) dst.(1));
    w32 (Int64.logxor src.(0) dst.(2));
    w32 (Int64.logxor src.(1) dst.(3));
  |]

(* SHA1MSG2: the final calculation of the next four message words. *)
let sha1msg2 (dst : int64 array) (src : int64 array) =
  let w13 = src.(1) and w14 = src.(2) and w15 = src.(3) in
  let w16 = rol32 (w32 (Int64.logxor dst.(0) w13)) 1 in
  let w17 = rol32 (w32 (Int64.logxor dst.(1) w14)) 1 in
  let w18 = rol32 (w32 (Int64.logxor dst.(2) w15)) 1 in
  let w19 = rol32 (w32 (Int64.logxor dst.(3) w16)) 1 in
  [| w16; w17; w18; w19 |]

(* SHA256RNDS2: two SHA-256 rounds.  The destination holds the state
   (C, D, G, H), the source the state (A, B, E, F) and [wk] the two round
   constants from the implicit XMM0. *)
let sha256rnds2 (dst : int64 array) (src : int64 array) (wk : int64 array) =
  let a = ref src.(0) and b = ref src.(1) and c = ref dst.(0) and d = ref dst.(1) in
  let e = ref src.(2) and f = ref src.(3) and g = ref dst.(2) and h = ref dst.(3) in
  for i = 0 to 1 do
    let wki = wk.(i) in
    let ch = sha256_ch !e !f !g in
    let a_new =
      add32
        (add32 (add32 (add32 ch (sha256_sigma1 !e)) (add32 wki !h))
           (sha256_maj !a !b !c))
        (sha256_sigma0 !a)
    in
    let e_new = add32 (add32 (add32 ch (sha256_sigma1 !e)) (add32 wki !h)) !d in
    let b_new = !a and c_new = !b and d_new = !c in
    let f_new = !e and g_new = !f and h_new = !g in
    a := a_new;
    b := b_new;
    c := c_new;
    d := d_new;
    e := e_new;
    f := f_new;
    g := g_new;
    h := h_new
  done;
  [| !a; !b; !e; !f |]

(* SHA256MSG1: the intermediate calculation of the next four message words. *)
let sha256msg1 (dst : int64 array) (src : int64 array) =
  let w4 = src.(0) in
  [|
    add32 dst.(3) (sha256_sigma0 dst.(2));
    add32 dst.(2) (sha256_sigma0 dst.(1));
    add32 dst.(1) (sha256_sigma0 dst.(0));
    add32 dst.(0) (sha256_sigma0 w4);
  |]

(* SHA256MSG2: the final calculation of the next four message words. *)
let sha256msg2 (dst : int64 array) (src : int64 array) =
  let w14 = src.(1) and w15 = src.(0) in
  let w16 = add32 dst.(3) (sha256_sigma1 w14) in
  let w17 = add32 dst.(2) (sha256_sigma1 w15) in
  let w18 = add32 dst.(1) (sha256_sigma1 w16) in
  let w19 = add32 dst.(0) (sha256_sigma1 w17) in
  [| w16; w17; w18; w19 |]

(* The 128-bit vector register of the VM holds two 64-bit lanes; the four
   32-bit words of a SHA-NI register live in the two low lanes. *)
let words_of_lanes (l0, l1) =
  [| w32 l0; w32 (Int64.shift_right_logical l0 32); w32 l1; w32 (Int64.shift_right_logical l1 32) |]

let lanes_of_words (w : int64 array) =
  (Int64.logor w.(0) (Int64.shift_left w.(1) 32), Int64.logor w.(2) (Int64.shift_left w.(3) 32))
