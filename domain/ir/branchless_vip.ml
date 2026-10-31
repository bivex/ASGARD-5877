open Int64

type branch_cond =
  | CondEq
  | CondNe
  | CondUlt
  | CondUge
  | CondSlt
  | CondSge

let eval_is_zero_branchless ?(variant = 0) (d : int64) : int64 =
  match variant mod 5 with
  | 0 ->
      (* Formula 0: Two's complement sign-bit: 1 - ((d | -d) >> 63) *)
      let non_zero_bit = shift_right_logical (logor d (neg d)) 63 in
      sub 1L non_zero_bit
  | 1 ->
      (* Formula 1: Warren borrow from zero: ((~d) & (d - 1)) >> 63 *)
      let not_d = lognot d in
      let d_minus_1 = sub d 1L in
      shift_right_logical (logand not_d d_minus_1) 63
  | 2 ->
      (* Formula 2: MBA OR decomposition: 1 - (((d ^ -d) + (d & -d)) >> 63) *)
      let neg_d = neg d in
      let val_or = add (logxor d neg_d) (logand d neg_d) in
      sub 1L (shift_right_logical val_or 63)
  | 3 ->
      (* Formula 3: De Morgan sign extraction: (~(d | -d) >> 63) & 1 *)
      let not_or = lognot (logor d (neg d)) in
      logand (shift_right_logical not_or 63) 1L
  | _ ->
      (* Formula 4: Boolean XOR bit flipping: ((d | -d) >> 63) ^ 1 *)
      let non_zero_bit = shift_right_logical (logor d (neg d)) 63 in
      logxor non_zero_bit 1L
let eval_ult_branchless (x : int64) (y : int64) : int64 =
  (* Unsigned borrow (borrow / Carry Flag for x - y):
     Warren's formula (Hacker's Delight): borrow = (~x & y) | ((~x | y) & (x - y))
     Bit 63 equals 1 if and only if x <u y *)
  let diff = sub x y in
  let not_x = lognot x in
  let borrow = logor (logand not_x y) (logand (logor not_x y) diff) in
  shift_right_logical borrow 63

let eval_slt_branchless (x : int64) (y : int64) : int64 =
  (* Signed comparison x <s y reduces to an unsigned one by flipping the sign bit 2^63 *)
  let sign_flip = 0x8000000000000000L in
  eval_ult_branchless (logxor x sign_flip) (logxor y sign_flip)

let eval_cond_branchless (cond : branch_cond) (x : int64) (y : int64) : int64 =
  match cond with
  | CondEq  -> eval_is_zero_branchless (sub x y)
  | CondNe  -> logxor 1L (eval_is_zero_branchless (sub x y))
  | CondUlt -> eval_ult_branchless x y
  | CondUge -> logxor 1L (eval_ult_branchless x y)
  | CondSlt -> eval_slt_branchless x y
  | CondSge -> logxor 1L (eval_slt_branchless x y)

let compute_next_vip_branchless
    ~(cond : branch_cond) ~(lhs : int64) ~(rhs : int64)
    ~(target_vip : int64) ~(fallthrough_vip : int64) : int64 =
  let b = eval_cond_branchless cond lhs rhs in
  let delta = sub target_vip fallthrough_vip in
  add fallthrough_vip (mul b delta)

let compute_vip_and_key_branchless
    ~(cond : branch_cond) ~(lhs : int64) ~(rhs : int64)
    ~(target_vip : int64) ~(fallthrough_vip : int64)
    ~(base_key : int64) ~(key_delta_taken : int64) ~(key_delta_fallthrough : int64)
    : int64 * int64 =
  let b = eval_cond_branchless cond lhs rhs in
  let not_b = sub 1L b in
  let next_vip = add fallthrough_vip (mul b (sub target_vip fallthrough_vip)) in
  (* We select the key delta with a branchless arithmetic multiplexer *)
  let active_delta = add (mul b key_delta_taken) (mul not_b key_delta_fallthrough) in
  let next_key = mul (logxor base_key active_delta) 0x9E3779B97F4A7C15L in
  (next_vip, next_key)

