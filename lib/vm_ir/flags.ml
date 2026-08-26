open Register

type flag =
  | CF
  | ZF
  | SF
  | OF
  | PF
  | AF

type condition =
  | E
  | NE
  | B
  | AE
  | BE
  | A
  | S
  | NS
  | P
  | NP
  | L
  | GE
  | LE
  | G
  | O
  | NO
  | ALWAYS

type cc_op =
  | CC_OP_RAW of int64
  | CC_OP_ADD of { src1 : int64; src2 : int64; dst : int64; width : width }
  | CC_OP_ADC of { src1 : int64; src2 : int64; carry_in : bool; dst : int64; width : width }
  | CC_OP_SUB of { src1 : int64; src2 : int64; dst : int64; width : width }
  | CC_OP_SBB of { src1 : int64; src2 : int64; borrow_in : bool; dst : int64; width : width }
  | CC_OP_LOGIC of { dst : int64; width : width }
  | CC_OP_INC of { old_dst : int64; new_dst : int64; prev_cf : bool; width : width }
  | CC_OP_DEC of { old_dst : int64; new_dst : int64; prev_cf : bool; width : width }

let empty_flags = CC_OP_RAW 0x02L (* x86 bit 1 is always 1 *)

let get_mask = function
  | B8  -> 0xFFL
  | B16 -> 0xFFFFL
  | B32 -> 0xFFFFFFFFL
  | B64 -> -1L

let get_sign_bit = function
  | B8  -> 0x80L
  | B16 -> 0x8000L
  | B32 -> 0x80000000L
  | B64 -> Int64.min_int (* 0x8000000000000000L *)

let popcount8 b =
  let v = ref (b land 0xFF) in
  let count = ref 0 in
  while !v > 0 do
    if !v land 1 = 1 then incr count;
    v := !v lsr 1
  done;
  !count

let compute_pf_val dst =
  let low8 = Int64.to_int (Int64.logand dst 0xFFL) in
  (popcount8 low8 land 1) = 0

let compute_cf = function
  | CC_OP_RAW raw -> Int64.logand raw 0x01L <> 0L
  | CC_OP_ADD { src1; dst; width; _ } ->
      let mask = get_mask width in
      let u_dst = Int64.logand dst mask in
      let u_s1 = Int64.logand src1 mask in
      Int64.unsigned_compare u_dst u_s1 < 0
  | CC_OP_ADC { src1; carry_in; dst; width; _ } ->
      let mask = get_mask width in
      let u_dst = Int64.logand dst mask in
      let u_s1 = Int64.logand src1 mask in
      if not carry_in then
        Int64.unsigned_compare u_dst u_s1 < 0
      else
        Int64.unsigned_compare u_dst u_s1 <= 0
  | CC_OP_SUB { src1; src2; width; _ } ->
      let mask = get_mask width in
      let u_s1 = Int64.logand src1 mask in
      let u_s2 = Int64.logand src2 mask in
      Int64.unsigned_compare u_s1 u_s2 < 0
  | CC_OP_SBB { src1; src2; borrow_in; width; _ } ->
      let mask = get_mask width in
      let u_s1 = Int64.logand src1 mask in
      let u_s2 = Int64.logand src2 mask in
      if not borrow_in then
        Int64.unsigned_compare u_s1 u_s2 < 0
      else
        Int64.unsigned_compare u_s1 u_s2 <= 0
  | CC_OP_LOGIC _ -> false
  | CC_OP_INC { prev_cf; _ } | CC_OP_DEC { prev_cf; _ } -> prev_cf

let compute_zf = function
  | CC_OP_RAW raw -> Int64.logand raw 0x40L <> 0L
  | CC_OP_ADD { dst; width; _ }
  | CC_OP_ADC { dst; width; _ }
  | CC_OP_SUB { dst; width; _ }
  | CC_OP_SBB { dst; width; _ }
  | CC_OP_LOGIC { dst; width }
  | CC_OP_INC { new_dst = dst; width; _ }
  | CC_OP_DEC { new_dst = dst; width; _ } ->
      Int64.logand dst (get_mask width) = 0L

let compute_sf = function
  | CC_OP_RAW raw -> Int64.logand raw 0x80L <> 0L
  | CC_OP_ADD { dst; width; _ }
  | CC_OP_ADC { dst; width; _ }
  | CC_OP_SUB { dst; width; _ }
  | CC_OP_SBB { dst; width; _ }
  | CC_OP_LOGIC { dst; width }
  | CC_OP_INC { new_dst = dst; width; _ }
  | CC_OP_DEC { new_dst = dst; width; _ } ->
      Int64.logand dst (get_sign_bit width) <> 0L

let compute_of = function
  | CC_OP_RAW raw -> Int64.logand raw 0x800L <> 0L
  | CC_OP_ADD { src1; src2; dst; width }
  | CC_OP_ADC { src1; src2; dst; width; _ } ->
      let sign = get_sign_bit width in
      let s1_xor_dst = Int64.logxor src1 dst in
      let s2_xor_dst = Int64.logxor src2 dst in
      Int64.logand (Int64.logand s1_xor_dst s2_xor_dst) sign <> 0L
  | CC_OP_SUB { src1; src2; dst; width }
  | CC_OP_SBB { src1; src2; dst; width; _ } ->
      let sign = get_sign_bit width in
      let s1_xor_s2 = Int64.logxor src1 src2 in
      let s1_xor_dst = Int64.logxor src1 dst in
      Int64.logand (Int64.logand s1_xor_s2 s1_xor_dst) sign <> 0L
  | CC_OP_LOGIC _ -> false
  | CC_OP_INC { old_dst; new_dst; width; _ } ->
      (* INC overflows if old_dst was 0x7FFF... and new_dst is 0x8000... *)
      let sign = get_sign_bit width in
      Int64.logand old_dst sign = 0L && Int64.logand new_dst sign <> 0L
  | CC_OP_DEC { old_dst; new_dst; width; _ } ->
      (* DEC overflows if old_dst was 0x8000... and new_dst is 0x7FFF... *)
      let sign = get_sign_bit width in
      Int64.logand old_dst sign <> 0L && Int64.logand new_dst sign = 0L

let compute_pf = function
  | CC_OP_RAW raw -> Int64.logand raw 0x04L <> 0L
  | CC_OP_ADD { dst; _ }
  | CC_OP_ADC { dst; _ }
  | CC_OP_SUB { dst; _ }
  | CC_OP_SBB { dst; _ }
  | CC_OP_LOGIC { dst; _ }
  | CC_OP_INC { new_dst = dst; _ }
  | CC_OP_DEC { new_dst = dst; _ } ->
      compute_pf_val dst

let compute_af = function
  | CC_OP_RAW raw -> Int64.logand raw 0x10L <> 0L
  | CC_OP_ADD { src1; src2; _ }
  | CC_OP_ADC { src1; src2; _ } ->
      let s1_low4 = Int64.to_int (Int64.logand src1 0x0FL) in
      let s2_low4 = Int64.to_int (Int64.logand src2 0x0FL) in
      (s1_low4 + s2_low4) > 0x0F
  | CC_OP_SUB { src1; src2; _ }
  | CC_OP_SBB { src1; src2; _ } ->
      let s1_low4 = Int64.to_int (Int64.logand src1 0x0FL) in
      let s2_low4 = Int64.to_int (Int64.logand src2 0x0FL) in
      s1_low4 < s2_low4
  | CC_OP_LOGIC _ -> false
  | CC_OP_INC { old_dst; _ } -> Int64.logand old_dst 0x0FL = 0x0FL
  | CC_OP_DEC { old_dst; _ } -> Int64.logand old_dst 0x0FL = 0L

let compute_flag op = function
  | CF -> compute_cf op
  | ZF -> compute_zf op
  | SF -> compute_sf op
  | OF -> compute_of op
  | PF -> compute_pf op
  | AF -> compute_af op

let evaluate_condition op = function
  | E      -> compute_zf op
  | NE     -> not (compute_zf op)
  | B      -> compute_cf op
  | AE     -> not (compute_cf op)
  | BE     -> compute_cf op || compute_zf op
  | A      -> not (compute_cf op) && not (compute_zf op)
  | S      -> compute_sf op
  | NS     -> not (compute_sf op)
  | P      -> compute_pf op
  | NP     -> not (compute_pf op)
  | L      -> compute_sf op <> compute_of op
  | GE     -> compute_sf op = compute_of op
  | LE     -> compute_zf op || (compute_sf op <> compute_of op)
  | G      -> not (compute_zf op) && (compute_sf op = compute_of op)
  | O      -> compute_of op
  | NO     -> not (compute_of op)
  | ALWAYS -> true

let materialize_rflags op =
  match op with
  | CC_OP_RAW raw -> Int64.logor raw 0x02L
  | _ ->
      let cf = if compute_cf op then 1L else 0L in
      let pf = if compute_pf op then 4L else 0L in
      let af = if compute_af op then 16L else 0L in
      let zf = if compute_zf op then 64L else 0L in
      let sf = if compute_sf op then 128L else 0L in
      let of_ = if compute_of op then 2048L else 0L in
      let reserved = 2L in
      Int64.logor (Int64.logor (Int64.logor cf pf) (Int64.logor af zf))
                  (Int64.logor (Int64.logor sf of_) reserved)

let of_rflags raw = CC_OP_RAW raw

let condition_to_string = function
  | E -> "e" | NE -> "ne" | B -> "b" | AE -> "ae" | BE -> "be" | A -> "a"
  | S -> "s" | NS -> "ns" | P -> "p" | NP -> "np" | L -> "l" | GE -> "ge"
  | LE -> "le" | G -> "g" | O -> "o" | NO -> "no" | ALWAYS -> "always"

let condition_of_string str =
  match String.lowercase_ascii (String.trim str) with
  | "e" | "z" -> Ok E
  | "ne" | "nz" -> Ok NE
  | "b" | "c" | "nae" -> Ok B
  | "ae" | "nb" | "nc" -> Ok AE
  | "be" | "na" -> Ok BE
  | "a" | "nbe" -> Ok A
  | "s" -> Ok S
  | "ns" -> Ok NS
  | "p" | "pe" -> Ok P
  | "np" | "po" -> Ok NP
  | "l" | "nge" -> Ok L
  | "ge" | "nl" -> Ok GE
  | "le" | "ng" -> Ok LE
  | "g" | "nle" -> Ok G
  | "o" -> Ok O
  | "no" -> Ok NO
  | "always" | "mp" -> Ok ALWAYS
  | other -> Error (Printf.sprintf "Unknown condition code '%s'" other)

let condition_negate = function
  | E -> NE | NE -> E
  | B -> AE | AE -> B
  | BE -> A | A -> BE
  | S -> NS | NS -> S
  | P -> NP | NP -> P
  | L -> GE | GE -> L
  | LE -> G | G -> LE
  | O -> NO | NO -> O
  | ALWAYS -> ALWAYS
