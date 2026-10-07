open Register
open Flags
open Ir

type state = {
  vregs : (Register.t, int64) Hashtbl.t;
  vectors : (int, int64 array) Hashtbl.t;
  memory : (int64, int) Hashtbl.t;
  mutable flags : cc_op;
  mutable vsp : int64;
  mutable vip : int64;
  mutable halted : bool;
  mutable trapped : string option;
}

let is_sp_reg = function
  | Gpr (RSP, _) | Vreg (VSP, _) -> true
  | _ -> false

let sync_sp state value =
  state.vsp <- value;
  Hashtbl.replace state.vregs (Register.with_width Register.rsp Register.B64) value;
  Hashtbl.replace state.vregs (Register.with_width Register.vsp Register.B64) value

let make_state ?(stack_base = 0x7FFFFFFF0000L) () =
  let s = {
    vregs = Hashtbl.create 32;
    vectors = Hashtbl.create 32;
    memory = Hashtbl.create 1024;
    flags = empty_flags;
    vsp = stack_base;
    vip = 0x80000000L;
    halted = false;
    trapped = None;
  } in
  Hashtbl.replace s.vregs (Register.with_width Register.rsp Register.B64) stack_base;
  Hashtbl.replace s.vregs (Register.with_width Register.vsp Register.B64) stack_base;
  s

let get_mask = function
  | B8  -> 0xFFL
  | B16 -> 0xFFFFL
  | B32 -> 0xFFFFFFFFL
  | B64 | B128 | B256 | B512 -> -1L

let truncate_val w v =
  Int64.logand v (get_mask w)

let sign_extend w v =
  let v_masked = truncate_val w v in
  match w with
  | B8 -> if Int64.logand v_masked 0x80L <> 0L then Int64.logor v_masked (Int64.lognot 0xFFL) else v_masked
  | B16 -> if Int64.logand v_masked 0x8000L <> 0L then Int64.logor v_masked (Int64.lognot 0xFFFFL) else v_masked
  | B32 -> if Int64.logand v_masked 0x80000000L <> 0L then Int64.logor v_masked (Int64.lognot 0xFFFFFFFFL) else v_masked
  | B64 | B128 | B256 | B512 -> v

let get_vector_lane state idx lane =
  match Hashtbl.find_opt state.vectors (idx mod 32) with
  | Some lanes when lane >= 0 && lane < Array.length lanes -> lanes.(lane)
  | _ -> 0L

let set_vector_lane state idx lane value =
  let key = idx mod 32 in
  let lanes =
    match Hashtbl.find_opt state.vectors key with
    | Some lanes -> Array.copy lanes
    | None -> Array.make 8 0L
  in
  if lane >= 0 && lane < Array.length lanes then lanes.(lane) <- value;
  Hashtbl.replace state.vectors key lanes

let get_reg state reg =
  match reg with
  | Fpr (i, _) -> get_vector_lane state i 0
  | _ ->
      let w = Register.get_width reg in
      let r64 = Register.with_width reg B64 in
      let raw =
        if is_sp_reg reg then state.vsp
        else Option.value ~default:0L (Hashtbl.find_opt state.vregs r64)
      in
      truncate_val w raw

let set_reg state reg value =
  match reg with
  | Fpr (i, _) -> set_vector_lane state i 0 value
  | _ ->
      let w = Register.get_width reg in
      let r64 = Register.with_width reg B64 in
      let cur =
        if is_sp_reg reg then state.vsp
        else Option.value ~default:0L (Hashtbl.find_opt state.vregs r64)
      in
      let new_val =
        match w with
        | B64 -> value
        | B32 -> truncate_val B32 value
        | B16 ->
            let high = Int64.logand cur (Int64.lognot 0xFFFFL) in
            Int64.logor high (truncate_val B16 value)
        | B8 ->
            let high = Int64.logand cur (Int64.lognot 0xFFL) in
            Int64.logor high (truncate_val B8 value)
        | _ -> value
      in
      Hashtbl.replace state.vregs r64 new_val;
      if is_sp_reg reg then sync_sp state new_val


let read_byte state addr =
  Option.value ~default:0 (Hashtbl.find_opt state.memory addr)

let write_byte state addr b =
  Hashtbl.replace state.memory addr (b land 0xFF)

let read_mem ?(signed = false) state addr width =
  let num_bytes = Register.width_to_bytes width in
  let res = ref 0L in
  for i = 0 to num_bytes - 1 do
    let b = Int64.of_int (read_byte state (Int64.add addr (Int64.of_int i))) in
    res := Int64.logor !res (Int64.shift_left b (i * 8))
  done;
  if signed then
    match width with
    | B8 ->
        let v = Int64.logand !res 0xFFL in
        if Int64.logand v 0x80L <> 0L then Int64.logor v (Int64.lognot 0xFFL) else v
    | B16 ->
        let v = Int64.logand !res 0xFFFFL in
        if Int64.logand v 0x8000L <> 0L then Int64.logor v (Int64.lognot 0xFFFFL) else v
    | B32 ->
        let v = Int64.logand !res 0xFFFFFFFFL in
        if Int64.logand v 0x80000000L <> 0L then Int64.logor v (Int64.lognot 0xFFFFFFFFL) else v
    | B64 | B128 | B256 | B512 -> !res
  else
    !res

let write_mem state addr width value =
  let num_bytes = Register.width_to_bytes width in
  for i = 0 to num_bytes - 1 do
    let b = Int64.to_int (Int64.logand (Int64.shift_right_logical value (i * 8)) 0xFFL) in
    write_byte state (Int64.add addr (Int64.of_int i)) b
  done

let eval_mem_addr state (m : mem_ref) =
  let base_val =
    match m.base with
    | Some b -> get_reg state b
    | None -> 0L
  in
  let idx_val =
    match m.index with
    | Some (idx, scale) -> Int64.mul (get_reg state idx) (Int64.of_int scale)
    | None -> 0L
  in
  Int64.add (Int64.add base_val idx_val) m.disp

let eval_operand state = function
  | Reg r -> get_reg state r
  | Imm i -> i
  | Mem m ->
      let addr = eval_mem_addr state m in
      read_mem ~signed:m.is_signed state addr m.width

let write_operand state op value =
  match op with
  | Reg r -> set_reg state r value
  | Mem m ->
      let addr = eval_mem_addr state m in
      write_mem state addr m.width value
  | Imm _ -> ()

let vector_lane_mask = function
  | 8 -> 0xFFL
  | 16 -> 0xFFFFL
  | 32 -> 0xFFFFFFFFL
  | _ -> -1L

let float32_bits value =
  Int64.logand (Int64.of_int32 (Int32.bits_of_float value)) 0xFFFFFFFFL

let float64_bits value = Int64.bits_of_float value

let sign_extend_lane lane_bits v =
  let mask = vector_lane_mask lane_bits in
  let v_masked = Int64.logand v mask in
  match lane_bits with
  | 8 -> if Int64.logand v_masked 0x80L <> 0L then Int64.logor v_masked (Int64.lognot 0xFFL) else v_masked
  | 16 -> if Int64.logand v_masked 0x8000L <> 0L then Int64.logor v_masked (Int64.lognot 0xFFFFL) else v_masked
  | 32 -> if Int64.logand v_masked 0x80000000L <> 0L then Int64.logor v_masked (Int64.lognot 0xFFFFFFFFL) else v_masked
  | _ -> v

let vector_binary_value ~lane_bits ~elem ~op ~a ~b =
  let mask = vector_lane_mask lane_bits in
  match op, elem with
  | Vadd, VF32 ->
      let fa = Int32.float_of_bits (Int64.to_int32 a) in
      let fb = Int32.float_of_bits (Int64.to_int32 b) in
      float32_bits (fa +. fb)
  | Vsub, VF32 ->
      let fa = Int32.float_of_bits (Int64.to_int32 a) in
      let fb = Int32.float_of_bits (Int64.to_int32 b) in
      float32_bits (fa -. fb)
  | Vmul, VF32 ->
      let fa = Int32.float_of_bits (Int64.to_int32 a) in
      let fb = Int32.float_of_bits (Int64.to_int32 b) in
      float32_bits (fa *. fb)
  | Vmin, VF32 ->
      let fa = Int32.float_of_bits (Int64.to_int32 a) in
      let fb = Int32.float_of_bits (Int64.to_int32 b) in
      float32_bits (Float.min fa fb)
  | Vmax, VF32 ->
      let fa = Int32.float_of_bits (Int64.to_int32 a) in
      let fb = Int32.float_of_bits (Int64.to_int32 b) in
      float32_bits (Float.max fa fb)
  | Vadd, VF64 -> float64_bits (Int64.float_of_bits a +. Int64.float_of_bits b)
  | Vsub, VF64 -> float64_bits (Int64.float_of_bits a -. Int64.float_of_bits b)
  | Vmul, VF64 -> float64_bits (Int64.float_of_bits a *. Int64.float_of_bits b)
  | Vmin, VF64 -> float64_bits (Float.min (Int64.float_of_bits a) (Int64.float_of_bits b))
  | Vmax, VF64 -> float64_bits (Float.max (Int64.float_of_bits a) (Int64.float_of_bits b))
  | (Vadd | Vsub | Vmul), VInt -> (
      match op with
      | Vadd -> Int64.add a b
      | Vsub -> Int64.sub a b
      | Vmul -> Int64.mul a b
      | _ -> 0L)
  | (Vand | Vor | Vxor), (VInt | VF32 | VF64) -> (
      match op with
      | Vand -> Int64.logand a b
      | Vor -> Int64.logor a b
      | Vxor -> Int64.logxor a b
      | _ -> 0L)
  | Vandn, _ ->
      Int64.logand (Int64.lognot a) b
  | Vsll, _ ->
      let cnt = Int64.to_int (Int64.logand b 0xFFL) in
      if cnt >= lane_bits then 0L else Int64.shift_left a cnt
  | Vsrl, _ ->
      let cnt = Int64.to_int (Int64.logand b 0xFFL) in
      if cnt >= lane_bits then 0L else Int64.shift_right_logical (Int64.logand a mask) cnt
  | Vsra, _ ->
      let cnt = Int64.to_int (Int64.logand b 0xFFL) in
      let sa = sign_extend_lane lane_bits a in
      if cnt >= lane_bits then (if sa < 0L then mask else 0L)
      else Int64.shift_right sa cnt
  | Vcmpeq, _ ->
      if a = b then mask else 0L
  | Vcmpgt, _ ->
      let sa = sign_extend_lane lane_bits a in
      let sb = sign_extend_lane lane_bits b in
      if sa > sb then mask else 0L
  | Vmin, VInt ->
      let sa = sign_extend_lane lane_bits a in
      let sb = sign_extend_lane lane_bits b in
      if sa < sb then a else b
  | Vmax, VInt ->
      let sa = sign_extend_lane lane_bits a in
      let sb = sign_extend_lane lane_bits b in
      if sa > sb then a else b
  | Vminu, _ ->
      let ua = Int64.logand a mask in
      let ub = Int64.logand b mask in
      if Int64.unsigned_compare ua ub < 0 then a else b
  | Vmaxu, _ ->
      let ua = Int64.logand a mask in
      let ub = Int64.logand b mask in
      if Int64.unsigned_compare ua ub > 0 then a else b
  | Vabs, _ ->
      let sa = sign_extend_lane lane_bits a in
      let res = if sa < 0L then Int64.neg sa else sa in
      Int64.logand res mask
  | (Vunpckl | Vunpckh | Vpackss | Vpackus | Vshuf | Vblend), _ -> 0L

let apply_vector_lanes state ~dst_bits ~lane_bits ~elem ~src1 ~src2 ~dst op =
  let mask = vector_lane_mask lane_bits in
  let last = (dst_bits - lane_bits) / lane_bits in
  for lane = 0 to last do
    let pos = lane * lane_bits in
    let chunk = pos / 64 in
    let shift = pos mod 64 in
    let packed_mask = Int64.shift_left mask shift in
    let a_packed = get_vector_lane state src1 chunk in
    let b_packed = get_vector_lane state src2 chunk in
    let a = Int64.logand (Int64.shift_right_logical a_packed shift) mask in
    let b = Int64.logand (Int64.shift_right_logical b_packed shift) mask in
    let value =
      match op with
      | Vunpckl ->
          let num_lanes = 128 / lane_bits in
          let block_lane = lane mod num_lanes in
          let half_idx = block_lane / 2 in
          let src_reg = if block_lane mod 2 = 0 then src1 else src2 in
          let src_bit = ((pos / 128) * 128) + (half_idx * lane_bits) in
          let s_val = get_vector_lane state src_reg (src_bit / 64) in
          Int64.logand (Int64.shift_right_logical s_val (src_bit mod 64)) mask
      | Vunpckh ->
          let num_lanes = 128 / lane_bits in
          let block_lane = lane mod num_lanes in
          let half_idx = (num_lanes / 2) + (block_lane / 2) in
          let src_reg = if block_lane mod 2 = 0 then src1 else src2 in
          let src_bit = ((pos / 128) * 128) + (half_idx * lane_bits) in
          let s_val = get_vector_lane state src_reg (src_bit / 64) in
          Int64.logand (Int64.shift_right_logical s_val (src_bit mod 64)) mask
      | Vshuf when lane_bits = 8 ->
          let ctrl = Int64.to_int (Int64.logand b 0xFFL) in
          if ctrl land 0x80 <> 0 then 0L
          else
            let sel = ctrl land 0xF in
            let src_bit = ((pos / 128) * 128) + (sel * 8) in
            let s_val = get_vector_lane state src1 (src_bit / 64) in
            Int64.logand (Int64.shift_right_logical s_val (src_bit mod 64)) 0xFFL
      | _ ->
          vector_binary_value ~lane_bits ~elem ~op ~a ~b
    in
    let dst_packed = get_vector_lane state dst chunk in
    let cleared = Int64.logand dst_packed (Int64.lognot packed_mask) in
    let updated = Int64.logor cleared (Int64.shift_left (Int64.logand value mask) shift) in
    set_vector_lane state dst chunk updated
  done

let apply_vector_imm state ~dst_bits ~lane_bits ~elem ~src ~imm ~dst op =
  let mask = vector_lane_mask lane_bits in
  let last = (dst_bits - lane_bits) / lane_bits in
  let imm_val = Int64.logand imm 0xFFL in
  for lane = 0 to last do
    let pos = lane * lane_bits in
    let chunk = pos / 64 in
    let shift = pos mod 64 in
    let packed_mask = Int64.shift_left mask shift in
    let a_packed = get_vector_lane state src chunk in
    let a = Int64.logand (Int64.shift_right_logical a_packed shift) mask in
    let value =
      match op with
      | Vshuf when lane_bits = 32 ->
          let lane_in_128 = (pos / 32) mod 4 in
          let sel = Int64.to_int (Int64.logand (Int64.shift_right_logical imm_val (lane_in_128 * 2)) 3L) in
          let src_bit = ((pos / 128) * 128) + (sel * 32) in
          let s_val = get_vector_lane state src (src_bit / 64) in
          Int64.logand (Int64.shift_right_logical s_val (src_bit mod 64)) 0xFFFFFFFFL
      | Vblend ->
          let sel = Int64.logand (Int64.shift_right_logical imm_val (lane mod 8)) 1L in
          if sel = 0L then a
          else
            let cur_dst = get_vector_lane state dst chunk in
            Int64.logand (Int64.shift_right_logical cur_dst shift) mask
      | _ ->
          vector_binary_value ~lane_bits ~elem ~op ~a ~b:imm_val
    in
    let dst_packed = get_vector_lane state dst chunk in
    let cleared = Int64.logand dst_packed (Int64.lognot packed_mask) in
    let updated = Int64.logor cleared (Int64.shift_left (Int64.logand value mask) shift) in
    set_vector_lane state dst chunk updated
  done

let copy_vector state ~dst_bits ~dst ~src =
  let chunks = (dst_bits + 63) / 64 in
  for chunk = 0 to chunks - 1 do
    set_vector_lane state dst chunk (get_vector_lane state src chunk)
  done

let load_vector state ~dst_bits ~dst ~addr =
  let address = eval_mem_addr state addr in
  let bytes = dst_bits / 8 in
  for chunk = 0 to (bytes / 8) - 1 do
    set_vector_lane state dst chunk (read_mem state (Int64.add address (Int64.of_int (chunk * 8))) B64)
  done

let store_vector state ~src_bits ~src ~addr =
  let address = eval_mem_addr state addr in
  let bytes = src_bits / 8 in
  for chunk = 0 to (bytes / 8) - 1 do
    write_mem state (Int64.add address (Int64.of_int (chunk * 8))) B64 (get_vector_lane state src chunk)
  done

let operand_width = function
  | Reg r -> Some (Register.get_width r)
  | Mem m -> Some m.width
  | Imm _ -> None

let determine_width op1 op2 =
  match operand_width op1 with
  | Some w -> w
  | None -> (
      match operand_width op2 with
      | Some w -> w
      | None -> B64)

let mulh_u64 a b =
  let a_lo = Int64.logand a 0xFFFFFFFFL in
  let a_hi = Int64.shift_right_logical a 32 in
  let b_lo = Int64.logand b 0xFFFFFFFFL in
  let b_hi = Int64.shift_right_logical b 32 in
  let p0 = Int64.mul a_lo b_lo in
  let p1 = Int64.mul a_lo b_hi in
  let p2 = Int64.mul a_hi b_lo in
  let p3 = Int64.mul a_hi b_hi in
  let cy = Int64.shift_right_logical
    (Int64.add (Int64.shift_right_logical p0 32)
       (Int64.add (Int64.logand p1 0xFFFFFFFFL) (Int64.logand p2 0xFFFFFFFFL))) 32 in
  Int64.add p3 (Int64.add (Int64.shift_right_logical p1 32)
                  (Int64.add (Int64.shift_right_logical p2 32) cy))

let imulh_i64 a b =
  let ures = mulh_u64 a b in
  let adj_a = if a < 0L then b else 0L in
  let adj_b = if b < 0L then a else 0L in
  Int64.sub (Int64.sub ures adj_a) adj_b

let step state = function
  | Nop -> Ok None
  | Mov { dst; src } ->
      let v = eval_operand state src in
      write_operand state dst v;
      Ok None
  | Lea { dst; addr } ->
      let effective_addr = eval_mem_addr state addr in
      set_reg state dst effective_addr;
      Ok None
  | Push src ->
      let v = eval_operand state src in
      sync_sp state (Int64.sub state.vsp 8L);
      write_mem state state.vsp B64 v;
      Ok None
  | Pop dst ->
      let v = read_mem state state.vsp B64 in
      sync_sp state (Int64.add state.vsp 8L);
      write_operand state dst v;
      Ok None
  | Xchg (a, b) ->
      let va = eval_operand state a in
      let vb = eval_operand state b in
      write_operand state a vb;
      write_operand state b va;
      Ok None
  | Alu { op; dst; src1; src2; set_flags } ->
      let w = Register.get_width dst in
      let v1 = eval_operand state src1 in
      let v2 = eval_operand state src2 in
      let compute_alu () =
        match op with
        | Add ->
            let res = Int64.add v1 v2 in
            if set_flags then state.flags <- CC_OP_ADD { src1 = v1; src2 = v2; dst = res; width = w };
            res
        | Adc ->
            let c_in = compute_cf state.flags in
            let c_add = if c_in then 1L else 0L in
            let res = Int64.add (Int64.add v1 v2) c_add in
            if set_flags then state.flags <- CC_OP_ADC { src1 = v1; src2 = v2; carry_in = c_in; dst = res; width = w };
            res
        | Sub ->
            let res = Int64.sub v1 v2 in
            if set_flags then state.flags <- CC_OP_SUB { src1 = v1; src2 = v2; dst = res; width = w };
            res
        | Sbb ->
            let b_in = compute_cf state.flags in
            let b_sub = if b_in then 1L else 0L in
            let res = Int64.sub (Int64.sub v1 v2) b_sub in
            if set_flags then state.flags <- CC_OP_SBB { src1 = v1; src2 = v2; borrow_in = b_in; dst = res; width = w };
            res
        | And ->
            let res = Int64.logand v1 v2 in
            if set_flags then state.flags <- CC_OP_LOGIC { dst = res; width = w };
            res
        | Or ->
            let res = Int64.logor v1 v2 in
            if set_flags then state.flags <- CC_OP_LOGIC { dst = res; width = w };
            res
        | Xor ->
            let res = Int64.logxor v1 v2 in
            if set_flags then state.flags <- CC_OP_LOGIC { dst = res; width = w };
            res
        | Shl ->
            let shift_mask = match w with B64 -> 63L | _ -> 31L in
            let shift = Int64.to_int (Int64.logand v2 shift_mask) in
            let res = truncate_val w (Int64.shift_left v1 shift) in
            if set_flags then state.flags <- CC_OP_LOGIC { dst = res; width = w };
            res
        | Shr ->
            let shift_mask = match w with B64 -> 63L | _ -> 31L in
            let shift = Int64.to_int (Int64.logand v2 shift_mask) in
            let res = truncate_val w (Int64.shift_right_logical (truncate_val w v1) shift) in
            if set_flags then state.flags <- CC_OP_LOGIC { dst = res; width = w };
            res
        | Sar ->
            let shift_mask = match w with B64 -> 63L | _ -> 31L in
            let shift = Int64.to_int (Int64.logand v2 shift_mask) in
            let v1_signed = sign_extend w v1 in
            let res = truncate_val w (Int64.shift_right v1_signed shift) in
            if set_flags then state.flags <- CC_OP_LOGIC { dst = res; width = w };
            res
        | Rol ->
            let bits = Register.width_to_bits w in
            let shift = (Int64.to_int v2) mod bits in
            let res =
              if shift = 0 then truncate_val w v1
              else
                let v1_trunc = truncate_val w v1 in
                truncate_val w (Int64.logor (Int64.shift_left v1_trunc shift)
                                            (Int64.shift_right_logical v1_trunc (bits - shift)))
            in
            res
        | Ror ->
            let bits = Register.width_to_bits w in
            let shift = (Int64.to_int v2) mod bits in
            let res =
              if shift = 0 then truncate_val w v1
              else
                let v1_trunc = truncate_val w v1 in
                truncate_val w (Int64.logor (Int64.shift_right_logical v1_trunc shift)
                                            (Int64.shift_left v1_trunc (bits - shift)))
            in
            res
        | Mul | Imul ->
            let res = Int64.mul v1 v2 in
            res
        | Mulh ->
            mulh_u64 v1 v2
        | Imulh ->
            imulh_i64 v1 v2
        | Div ->
            if v2 = 0L then 0L
            else Int64.unsigned_div v1 v2
        | Idiv ->
            if v2 = 0L then 0L
            else if v2 = -1L then Int64.neg v1
            else Int64.div v1 v2
      in
      if (op = Div || op = Idiv) && v2 = 0L then
        Error "VM divide by zero"
      else if op = Idiv && v2 = -1L && v1 = Int64.min_int then
        Error "VM signed division overflow"
      else
        let raw_res = compute_alu () in
        set_reg state dst raw_res;
        Ok None
  | Unary { op; dst; src; set_flags } ->
      let w = Register.get_width dst in
      let v = eval_operand state src in
      let res =
        match op with
        | Not -> Int64.lognot v
        | Neg ->
            let r = Int64.neg v in
            if set_flags then state.flags <- CC_OP_SUB { src1 = 0L; src2 = v; dst = r; width = w };
            r
        | Inc ->
            let r = Int64.add v 1L in
            if set_flags then state.flags <- CC_OP_INC { old_dst = v; new_dst = r; prev_cf = compute_cf state.flags; width = w };
            r
        | Dec ->
            let r = Int64.sub v 1L in
            if set_flags then state.flags <- CC_OP_DEC { old_dst = v; new_dst = r; prev_cf = compute_cf state.flags; width = w };
            r
        | Bswap ->
            let bits = Register.width_to_bits w in
            if bits = 16 then
              let b0 = Int64.logand (Int64.shift_right_logical v 8) 0xFFL in
              let b1 = Int64.logand (Int64.shift_left v 8) 0xFF00L in
              Int64.logor b0 b1
            else if bits = 32 then
              let b0 = Int64.logand (Int64.shift_right_logical v 24) 0xFFL in
              let b1 = Int64.logand (Int64.shift_right_logical v 8) 0xFF00L in
              let b2 = Int64.logand (Int64.shift_left v 8) 0xFF0000L in
              let b3 = Int64.logand (Int64.shift_left v 24) 0xFF000000L in
              Int64.logor (Int64.logor b0 b1) (Int64.logor b2 b3)
            else if bits = 64 then
              let rec swap acc i =
                if i = 8 then acc
                else
                  let byte = Int64.logand (Int64.shift_right_logical v (i * 8)) 0xFFL in
                  let shifted = Int64.shift_left byte ((7 - i) * 8) in
                  swap (Int64.logor acc shifted) (i + 1)
              in
              swap 0L 0
            else v
        | Clz ->
            let bits = Register.width_to_bits w in
            let tv = truncate_val w v in
            let rec count i =
              if i = bits then Int64.of_int bits
              else if Int64.logand (Int64.shift_right_logical tv (bits - 1 - i)) 1L <> 0L then Int64.of_int i
              else count (i + 1)
            in
            count 0
        | Ctz ->
            let bits = Register.width_to_bits w in
            let tv = truncate_val w v in
            if tv = 0L then Int64.of_int bits
            else
              let rec count i =
                if i = bits then Int64.of_int bits
                else if Int64.logand (Int64.shift_right_logical tv i) 1L <> 0L then Int64.of_int i
                else count (i + 1)
              in
              count 0
        | Popcnt ->
            let bits = Register.width_to_bits w in
            let tv = truncate_val w v in
            let rec count i acc =
              if i = bits then Int64.of_int acc
              else
                let bit = if Int64.logand (Int64.shift_right_logical tv i) 1L <> 0L then 1 else 0 in
                count (i + 1) (acc + bit)
            in
            count 0 0
        | Rbit ->
            let bits = Register.width_to_bits w in
            let tv = truncate_val w v in
            let rec rev i acc =
              if i = bits then acc
              else
                let bit = Int64.logand (Int64.shift_right_logical tv i) 1L in
                let acc' = Int64.logor acc (Int64.shift_left bit (bits - 1 - i)) in
                rev (i + 1) acc'
            in
            rev 0 0L
      in
      set_reg state dst res;
      Ok None
  | Cmp { src1; src2 } ->
      let w = determine_width src1 src2 in
      let v1 = truncate_val w (eval_operand state src1) in
      let v2 = truncate_val w (eval_operand state src2) in
      let res = truncate_val w (Int64.sub v1 v2) in
      state.flags <- CC_OP_SUB { src1 = v1; src2 = v2; dst = res; width = w };
      Ok None
  | Ccmp { cond; src1; src2; nzcv } ->
      if evaluate_condition state.flags cond then begin
        let w = determine_width src1 src2 in
        let v1 = truncate_val w (eval_operand state src1) in
        let v2 = truncate_val w (eval_operand state src2) in
        let res = truncate_val w (Int64.sub v1 v2) in
        state.flags <- CC_OP_SUB { src1 = v1; src2 = v2; dst = res; width = w };
      end else begin
        let sf = if (nzcv land 8) <> 0 then 128L else 0L in
        let zf = if (nzcv land 4) <> 0 then 64L else 0L in
        let cf = if (nzcv land 2) <> 0 then 1L else 0L in
        let of_ = if (nzcv land 1) <> 0 then 2048L else 0L in
        state.flags <- CC_OP_RAW (Int64.logor 2L (Int64.logor cf (Int64.logor zf (Int64.logor sf of_))));
      end;
      Ok None
  | Ccmn { cond; src1; src2; nzcv } ->
      if evaluate_condition state.flags cond then begin
        let w = determine_width src1 src2 in
        let v1 = truncate_val w (eval_operand state src1) in
        let v2 = truncate_val w (eval_operand state src2) in
        let res = truncate_val w (Int64.add v1 v2) in
        state.flags <- CC_OP_ADD { src1 = v1; src2 = v2; dst = res; width = w };
      end else begin
        let sf = if (nzcv land 8) <> 0 then 128L else 0L in
        let zf = if (nzcv land 4) <> 0 then 64L else 0L in
        let cf = if (nzcv land 2) <> 0 then 1L else 0L in
        let of_ = if (nzcv land 1) <> 0 then 2048L else 0L in
        state.flags <- CC_OP_RAW (Int64.logor 2L (Int64.logor cf (Int64.logor zf (Int64.logor sf of_))));
      end;
      Ok None
  | Test { src1; src2 } ->
      let w = determine_width src1 src2 in
      let v1 = truncate_val w (eval_operand state src1) in
      let v2 = truncate_val w (eval_operand state src2) in
      let res = truncate_val w (Int64.logand v1 v2) in
      state.flags <- CC_OP_LOGIC { dst = res; width = w };
      Ok None
  | Jmp t -> Ok (Some t)
  | Jcc { cond; target_true; target_false } ->
      if evaluate_condition state.flags cond then Ok (Some target_true)
      else Ok (Some target_false)
  | Call (Label _lbl) ->
      (* External host/libc call mock: preserves or sets return register and continues synchronously *)
      Ok None
  | Call t ->
      sync_sp state (Int64.sub state.vsp 8L);
      write_mem state state.vsp B64 state.vip;
      Ok (Some t)
  | Ret ->
      let return_addr = read_mem state state.vsp B64 in
      sync_sp state (Int64.add state.vsp 8L);
      Ok (Some (TargetImm return_addr))
  | Setcc { cond; dst } ->
      let bit = if evaluate_condition state.flags cond then 1L else 0L in
      write_operand state dst bit;
      Ok None
  | Cmov { cond; dst; src } ->
      if evaluate_condition state.flags cond then begin
        let v = eval_operand state src in
        set_reg state dst v
      end;
      Ok None
  | Vm_enter ->
      (* Enter VM: state initialized *)
      Ok None
  | Vm_exit ->
      state.halted <- true;
      Ok None
  | Trap msg ->
      state.trapped <- Some msg;
      state.halted <- true;
      Error (Printf.sprintf "VM Trapped: %s" msg)
  | Bridge_to_flow _ | Bridge_to_math _ ->
      Ok None
  | Load_symbol { dst; sym; addend } ->
      let base_addr =
        try Int64.of_string sym
        with _ ->
          let h = Hashtbl.hash sym in
          Int64.add 0x100000000L (Int64.shift_left (Int64.of_int (h land 0xFFFFF)) 4)
      in
      set_reg state dst (Int64.add base_addr addend);
      Ok None
  | Vec_mov { dst; src; bits } ->
      copy_vector state ~dst_bits:bits ~dst ~src;
      Ok None
  | Vec_binop { op; elem; dst; src1; src2; bits; lane_bits } ->
      apply_vector_lanes state ~dst_bits:bits ~lane_bits ~elem ~src1 ~src2 ~dst op;
      Ok None
  | Vec_imm { op; elem; dst; src; imm; bits; lane_bits } ->
      apply_vector_imm state ~dst_bits:bits ~lane_bits ~elem ~src ~imm ~dst op;
      Ok None
  | Vec_load { dst; addr; bits } ->
      load_vector state ~dst_bits:bits ~dst ~addr;
      Ok None
  | Vec_store { src; addr; bits } ->
      store_vector state ~src_bits:bits ~src ~addr;
      Ok None
  | Vec_clear_upper reg ->
      set_vector_lane state reg 2 0L;
      set_vector_lane state reg 3 0L;
      Ok None
  | Vec_zero_upper ->
      for i = 0 to 15 do
        set_vector_lane state i 2 0L;
        set_vector_lane state i 3 0L;
      done;
      Ok None
  | Pmovmskb { dst; src; bits } ->
      let num_bytes = bits / 8 in
      let mask = ref 0L in
      for b = 0 to num_bytes - 1 do
        let chunk = b / 8 in
        let byte_pos = (b mod 8) * 8 in
        let byte_val = Int64.logand (Int64.shift_right_logical (get_vector_lane state src chunk) byte_pos) 0xFFL in
        if Int64.logand byte_val 0x80L <> 0L then
          mask := Int64.logor !mask (Int64.shift_left 1L b)
      done;
      set_reg state dst !mask;
      Ok None
  | Fp_binop { op; dst; src1; src2 } ->
      let a_bits = get_vector_lane state src1 0 in
      let b_bits = get_vector_lane state src2 0 in
      let a = Int64.float_of_bits a_bits in
      let b = Int64.float_of_bits b_bits in
      let res =
        match op with
        | Fadd -> a +. b
        | Fsub -> a -. b
        | Fmul -> a *. b
        | Fdiv -> if b = 0.0 then 0.0 else a /. b
        | Fsqrt -> if a < 0.0 then 0.0 else Float.sqrt a
      in
      set_vector_lane state dst 0 (Int64.bits_of_float res);
      Ok None
  | Fp_cmp { src1; src2 } ->
      let a_bits = get_vector_lane state src1 0 in
      let b_bits = get_vector_lane state src2 0 in
      let a = Int64.float_of_bits a_bits in
      let b = Int64.float_of_bits b_bits in
      let zf = (a = b) in
      let cf = (a >= b) in
      let sf = (a < b) in
      let cf_val = if cf then 1L else 0L in
      let zf_val = if zf then 64L else 0L in
      let sf_val = if sf then 128L else 0L in
      state.flags <- CC_OP_RAW (Int64.logor 2L (Int64.logor cf_val (Int64.logor zf_val sf_val)));
      Ok None
  | Fp_conv { op = Fcvtzs; dst; src } ->
      let a_bits = match src with Fpr (i, _) -> get_vector_lane state i 0 | _ -> get_reg state src in
      let a = Int64.float_of_bits a_bits in
      let v = Int64.of_float a in
      set_reg state dst v;
      Ok None
  | Fp_conv { op = Scvtf; dst; src } ->
      let v = match src with Fpr (i, _) -> get_vector_lane state i 0 | _ -> get_reg state src in
      let f = Int64.to_float v in
      let f_bits = Int64.bits_of_float f in
      (match dst with
       | Fpr (i, _) -> set_vector_lane state i 0 f_bits
       | _ -> set_reg state dst f_bits);
      Ok None
  | Atomic_mem { op; dst; addr; src; imm } ->
      let a = Int64.add (get_reg state addr) imm in
      (match op with
       | AtLoad ->
           let v = read_mem state a B64 in
           set_reg state dst v
       | AtStore ->
           let v = get_reg state src in
           write_mem state a B64 v;
           set_reg state dst 0L
       | AtCas ->
           let cur = read_mem state a B64 in
           let exp = get_reg state src in
           let des = get_reg state Register.rax in
           if cur = exp then write_mem state a B64 des
           else set_reg state src cur
       | AtAdd ->
           let old = read_mem state a B64 in
           let v = get_reg state src in
           write_mem state a B64 (Int64.add old v);
           set_reg state src old
       | AtSwp ->
           let old = read_mem state a B64 in
           let v = get_reg state src in
           write_mem state a B64 v;
           set_reg state src old);
      Ok None
  | Get_flags dst ->
      let raw = Flags.materialize_rflags state.flags in
      set_reg state dst raw;
      Ok None
  | Set_flags src ->
      let raw = eval_operand state src in
      state.flags <- Flags.of_rflags raw;
      Ok None

let run_block state (b : basic_block) =
  let rec loop = function
    | [] -> Ok None
    | instr :: rest -> (
        match step state instr with
        | Error _ as e -> e
        | Ok (Some target) -> Ok (Some target)
        | Ok None ->
            if state.halted then Ok None
            else loop rest)
  in
  loop b.instrs

let run_func ?(max_steps = 100000) state (f : func) =
  let current_id = ref f.cfg.entry_id in
  let steps = ref 0 in
  let rec loop () =
    if state.halted then Ok ()
    else if !steps >= max_steps then
      Error (Printf.sprintf "Exceeded max execution steps (%d)" max_steps)
    else
      match get_block f.cfg !current_id with
      | None -> Error (Printf.sprintf "Block ID %d not found in CFG" !current_id)
      | Some blk -> (
          incr steps;
          match run_block state blk with
          | Error _ as e -> e
          | Ok None -> Ok ()
          | Ok (Some (BlockId next_id)) ->
              current_id := next_id;
              loop ()
          | Ok (Some (Label lbl)) ->
              (* Look up block by label *)
              let found = ref None in
              Hashtbl.iter (fun id (b : basic_block) -> if b.label = lbl then found := Some id) f.cfg.blocks;
              (match !found with
              | Some id ->
                  current_id := id;
                  loop ()
              | None -> Error (Printf.sprintf "Label '%s' not found" lbl))
          | Ok (Some (TargetImm _)) ->
              Ok ())
  in
  loop ()
