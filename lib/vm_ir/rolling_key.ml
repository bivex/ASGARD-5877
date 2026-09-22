(* Anti-Pushan block-chained rolling key: canonical OCaml mirror of the C++ keystream.
   The C++ side lives in the emitted VM context (key64_for_offset / anchor_key /
   advance_key_step) and the FETCH_NEXT dispatch macro. Both sides must agree
   bit-for-bit; test/test_anti_pushan.ml pins the correspondence. *)

(* SplitMix64-style positional PRF, mirrored from the emitted key64_for_offset. *)
let key64_for_offset (seed : int32) (offset : int) : int64 =
  let s64 = Int64.logand (Int64.of_int32 seed) 0xFFFFFFFFL in
  let x0 = Int64.logxor (Int64.logor (Int64.shift_left s64 32) (Int64.logxor s64 0x9E3779B9L))
                        (Int64.mul (Int64.of_int offset) 0x517CC1B727220A95L) in
  let x1 = Int64.mul (Int64.logxor x0 (Int64.shift_right_logical x0 30)) 0xBF58476D1CE4E5B9L in
  let x2 = Int64.mul (Int64.logxor x1 (Int64.shift_right_logical x1 27)) 0x94D049BB133111EBL in
  Int64.logxor x2 (Int64.shift_right_logical x2 31)

(* Domain-separated block-entry anchor. Must NOT equal key64_for_offset itself,
   otherwise the first in-block mask (k_pos lxor anchor) collapses to zero. *)
let anchor_key (seed : int32) (offset : int) : int64 =
  key64_for_offset (Int32.logxor seed 0x5BD1E995l) (offset lxor 0x13375877)

(* One step of the in-block chain, mirroring C++ advance_key_step exactly:
   x = k ^ (op*0x9E3779B97F4A7C15 + (dst<<24) + imm); rot = ROR23(x);
   (rot * 0xBF58476D1CE4E5B9) ^ 0x5877CAFE1337BEEF.  Int64 arithmetic is
   modulo 2^64, matching uint64_t wraparound. *)
let advance_key_step (k : int64) (op : int) (dst : int) (imm : int64) : int64 =
  let x = Int64.logxor k
      (Int64.add
         (Int64.add
            (Int64.mul (Int64.of_int op) 0x9E3779B97F4A7C15L)
            (Int64.shift_left (Int64.of_int dst) 24))
         imm) in
  let rot = Int64.logor (Int64.shift_right_logical x 23) (Int64.shift_left x 41) in
  Int64.logxor (Int64.mul rot 0xBF58476D1CE4E5B9L) 0x5877CAFE1337BEEFL

let sign_extend_32 (v : int64) : int64 =
  if Int64.logand v 0x80000000L <> 0L then Int64.logor v 0xFFFFFFFF00000000L else v

(* Field extraction from a packed plaintext word, exactly as the C++ FETCH_NEXT
   macro does it.  The runtime immediate is the SIGN-EXTENDED 32-bit slice of
   bits 18..49, not the 46-bit immediate the encoder packed — chain simulation
   must use this truncated view, never the source immediate. *)
let decode_fields (w : int64) : int * int * int * int64 =
  let op = Int64.to_int (Int64.logand w 0xFFL) in
  let dst = Int64.to_int (Int64.logand (Int64.shift_right_logical w 8) 0x1FL) in
  let src = Int64.to_int (Int64.logand (Int64.shift_right_logical w 13) 0x1FL) in
  let imm = sign_extend_32 (Int64.logand (Int64.shift_right_logical w 18) 0xFFFFFFFFL) in
  (op, dst, src, imm)
