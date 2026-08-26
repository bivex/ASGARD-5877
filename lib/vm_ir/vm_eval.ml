open Register
open Flags
open Ir

type state = {
  vregs : (Register.t, int64) Hashtbl.t;
  memory : (int64, int) Hashtbl.t;
  mutable flags : cc_op;
  mutable vsp : int64;
  mutable vip : int64;
  mutable halted : bool;
  mutable trapped : string option;
}

let make_state ?(stack_base = 0x7FFFFFFF0000L) () =
  {
    vregs = Hashtbl.create 32;
    memory = Hashtbl.create 1024;
    flags = empty_flags;
    vsp = stack_base;
    vip = 0x80000000L;
    halted = false;
    trapped = None;
  }

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

let read_byte state addr =
  Option.value ~default:0 (Hashtbl.find_opt state.memory addr)

let write_byte state addr b =
  Hashtbl.replace state.memory addr (b land 0xFF)

let read_mem state addr width =
  let num_bytes = Register.width_to_bytes width in
  let res = ref 0L in
  for i = 0 to num_bytes - 1 do
    let b = Int64.of_int (read_byte state (Int64.add addr (Int64.of_int i))) in
    res := Int64.logor !res (Int64.shift_left b (i * 8))
  done;
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
      read_mem state addr m.width

let write_operand state op value =
  match op with
  | Reg r -> set_reg state r value
  | Mem m ->
      let addr = eval_mem_addr state m in
      write_mem state addr m.width value
  | Imm _ -> ()

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
        | Div | Idiv ->
            if v2 = 0L then 0L
            else Int64.div v1 v2
      in
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
