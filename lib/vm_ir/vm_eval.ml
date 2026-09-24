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
  s

let get_mask = function
  | B8  -> 0xFFL
  | B16 -> 0xFFFFL
  | B32 -> 0xFFFFFFFFL
  | B64 -> -1L

let truncate_val w v =
  Int64.logand v (get_mask w)

let get_reg state reg =
  let w = Register.get_width reg in
  let r64 = Register.with_width reg B64 in
  let raw = Option.value ~default:0L (Hashtbl.find_opt state.vregs r64) in
  truncate_val w raw

let set_reg state reg value =
  let w = Register.get_width reg in
  let r64 = Register.with_width reg B64 in
  let cur = Option.value ~default:0L (Hashtbl.find_opt state.vregs r64) in
  let new_val =
    match w with
    | B64 -> value
    | B32 ->
        (* In x86_64, writing to a 32-bit subregister (eax) zero-extends to 64 bits (rax) *)
        truncate_val B32 value
    | B16 ->
        let high = Int64.logand cur (Int64.lognot 0xFFFFL) in
        Int64.logor high (truncate_val B16 value)
    | B8 ->
        let high = Int64.logand cur (Int64.lognot 0xFFL) in
        Int64.logor high (truncate_val B8 value)
  in
  Hashtbl.replace state.vregs r64 new_val

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
    | B64 -> !res
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

let vector_binary_value ~elem ~op ~a ~b =
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
  | Vadd, VF64 -> float64_bits (Int64.float_of_bits a +. Int64.float_of_bits b)
  | Vsub, VF64 -> float64_bits (Int64.float_of_bits a -. Int64.float_of_bits b)
  | Vmul, VF64 -> float64_bits (Int64.float_of_bits a *. Int64.float_of_bits b)
  | (Vadd | Vsub | Vmul), VInt -> (
      match op with
      | Vadd -> Int64.add a b
      | Vsub -> Int64.sub a b
      | Vmul -> Int64.mul a b
      | Vand | Vor | Vxor -> 0L)
  | (Vand | Vor | Vxor), (VInt | VF32 | VF64) -> (
      match op with
      | Vand -> Int64.logand a b
      | Vor -> Int64.logor a b
      | Vxor -> Int64.logxor a b
      | Vadd | Vsub | Vmul -> 0L)

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
    let value = vector_binary_value ~elem ~op ~a ~b in
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
      state.vsp <- Int64.sub state.vsp 8L;
      write_mem state state.vsp B64 v;
      Ok None
  | Pop dst ->
      let v = read_mem state state.vsp B64 in
      state.vsp <- Int64.add state.vsp 8L;
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
            let shift = Int64.to_int (Int64.logand v2 63L) in
            let res = Int64.shift_left v1 shift in
            if set_flags then state.flags <- CC_OP_LOGIC { dst = res; width = w };
            res
        | Shr ->
            let shift = Int64.to_int (Int64.logand v2 63L) in
            let res = Int64.shift_right_logical v1 shift in
            if set_flags then state.flags <- CC_OP_LOGIC { dst = res; width = w };
            res
        | Sar ->
            let shift = Int64.to_int (Int64.logand v2 63L) in
            let res = Int64.shift_right v1 shift in
            if set_flags then state.flags <- CC_OP_LOGIC { dst = res; width = w };
            res
        | Rol ->
            let shift = Int64.to_int (Int64.logand v2 63L) in
            let res = Int64.logor (Int64.shift_left v1 shift) (Int64.shift_right_logical v1 (64 - shift)) in
            res
        | Ror ->
            let shift = Int64.to_int (Int64.logand v2 63L) in
            let res = Int64.logor (Int64.shift_right_logical v1 shift) (Int64.shift_left v1 (64 - shift)) in
            res
        | Mul | Imul ->
            let res = Int64.mul v1 v2 in
            res
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
      in
      set_reg state dst res;
      Ok None
  | Cmp { src1; src2 } ->
      let v1 = eval_operand state src1 in
      let v2 = eval_operand state src2 in
      let res = Int64.sub v1 v2 in
      state.flags <- CC_OP_SUB { src1 = v1; src2 = v2; dst = res; width = B64 };
      Ok None
  | Test { src1; src2 } ->
      let v1 = eval_operand state src1 in
      let v2 = eval_operand state src2 in
      let res = Int64.logand v1 v2 in
      state.flags <- CC_OP_LOGIC { dst = res; width = B64 };
      Ok None
  | Jmp t -> Ok (Some t)
  | Jcc { cond; target_true; target_false } ->
      if evaluate_condition state.flags cond then Ok (Some target_true)
      else Ok (Some target_false)
  | Call (Label _lbl) ->
      (* External host/libc call mock: preserves or sets return register and continues synchronously *)
      Ok None
  | Call t ->
      state.vsp <- Int64.sub state.vsp 8L;
      write_mem state state.vsp B64 state.vip;
      Ok (Some t)
  | Ret ->
      let return_addr = read_mem state state.vsp B64 in
      state.vsp <- Int64.add state.vsp 8L;
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
  | Load_symbol { dst; addend; _ } ->
      set_reg state dst addend;
      Ok None
  | Vec_mov { dst; src; bits } ->
      copy_vector state ~dst_bits:bits ~dst ~src;
      Ok None
  | Vec_binop { op; elem; dst; src1; src2; bits; lane_bits } ->
      apply_vector_lanes state ~dst_bits:bits ~lane_bits ~elem ~src1 ~src2 ~dst op;
      Ok None
  | Vec_load { dst; addr; bits } ->
      load_vector state ~dst_bits:bits ~dst ~addr;
      Ok None
  | Vec_store { src; addr; bits } ->
      store_vector state ~src_bits:bits ~src ~addr;
      Ok None
  | Fp_binop _ | Fp_cmp _ | Fp_conv _ | Atomic_mem _ ->
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
