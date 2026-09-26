open Vm_ir
open Register
open Flags
open Stack_ir
open Stack_encoder

type state = {
  mutable vip : int64;
  mutable vsp : int64;
  mutable vkey : int64;
  mutable vdisp : int64;
  mutable vstack : int64 list;
  vctx : (int, int64) Hashtbl.t;
  vmem : (int64, int) Hashtbl.t;
  mutable flags : Flags.cc_op;
  mutable current_block_id : int;
  mutable halted : bool;
}

let create_state ?(stack_base = 0x7FFFFFFF0000L) ?(seed_key = 0x5877A564D00FL) ?(initial_ctx = []) () =
  let ctx = Hashtbl.create 64 in
  List.iter (fun (slot, v) -> Hashtbl.replace ctx slot v) initial_ctx;
  {
    vip = 0x80000000L;
    vsp = stack_base;
    vkey = seed_key;
    vdisp = 0x10000000L;
    vstack = [];
    vctx = ctx;
    vmem = Hashtbl.create 1024;
    flags = Flags.empty_flags;
    current_block_id = 0;
    halted = false;
  }

let get_reg state slot =
  match Hashtbl.find_opt state.vctx slot with
  | Some v -> v
  | None -> 0L

let set_reg state slot v =
  Hashtbl.replace state.vctx slot v

let read_mem_byte state addr =
  match Hashtbl.find_opt state.vmem addr with
  | Some b -> b land 0xFF
  | None -> 0

let write_mem_byte state addr b =
  Hashtbl.replace state.vmem addr (b land 0xFF)

let read_mem_word state addr width =
  let res = ref 0L in
  for i = 0 to width - 1 do
    let b = read_mem_byte state (Int64.add addr (Int64.of_int i)) in
    let b_i64 = Int64.shift_left (Int64.of_int b) (i * 8) in
    res := Int64.logor !res b_i64
  done;
  !res

let write_mem_word state addr value width =
  for i = 0 to width - 1 do
    let b = Int64.to_int (Int64.logand (Int64.shift_right_logical value (i * 8)) 0xFFL) in
    write_mem_byte state (Int64.add addr (Int64.of_int i)) b
  done

let step_op state = function
  | PushImm v ->
      state.vstack <- v :: state.vstack;
      state.vsp <- Int64.sub state.vsp 8L
  | PushReg idx ->
      let v = get_reg state idx in
      state.vstack <- v :: state.vstack;
      state.vsp <- Int64.sub state.vsp 8L
  | PopReg idx ->
      (match state.vstack with
       | v :: rest ->
           state.vstack <- rest;
           state.vsp <- Int64.add state.vsp 8L;
           set_reg state idx v
       | [] -> ())
  | ReadMem w ->
      (match state.vstack with
       | addr :: rest ->
           let v = read_mem_word state addr w in
           state.vstack <- v :: rest
       | [] -> ())
  | WriteMem w ->
      (match state.vstack with
       | v :: addr :: rest ->
           write_mem_word state addr v w;
           state.vstack <- rest;
           state.vsp <- Int64.add state.vsp 16L
       | _ -> ())
  | Add ->
      (match state.vstack with
       | op2 :: op1 :: rest ->
           let res = Int64.add op1 op2 in
           state.flags <- CC_OP_ADD { src1 = op1; src2 = op2; dst = res; width = B64 };
           state.vstack <- res :: rest;
           state.vsp <- Int64.add state.vsp 8L
       | _ -> ())
  | Sub ->
      (match state.vstack with
       | op2 :: op1 :: rest ->
           let res = Int64.sub op1 op2 in
           state.flags <- CC_OP_SUB { src1 = op1; src2 = op2; dst = res; width = B64 };
           state.vstack <- res :: rest;
           state.vsp <- Int64.add state.vsp 8L
       | _ -> ())
  | Mul ->
      (match state.vstack with
       | op2 :: op1 :: rest ->
           let res = Int64.mul op1 op2 in
           state.vstack <- res :: rest;
           state.vsp <- Int64.add state.vsp 8L
       | _ -> ())
  | Nor ->
      (match state.vstack with
       | op2 :: op1 :: rest ->
           let res = Int64.lognot (Int64.logor op1 op2) in
           state.flags <- CC_OP_LOGIC { dst = res; width = B64 };
           state.vstack <- res :: rest;
           state.vsp <- Int64.add state.vsp 8L
       | _ -> ())
  | Nand ->
      (match state.vstack with
       | op2 :: op1 :: rest ->
           let res = Int64.lognot (Int64.logand op1 op2) in
           state.flags <- CC_OP_LOGIC { dst = res; width = B64 };
           state.vstack <- res :: rest;
           state.vsp <- Int64.add state.vsp 8L
       | _ -> ())
  | Shl ->
      (match state.vstack with
       | count :: val_op :: rest ->
           let shift = Int64.to_int (Int64.logand count 0x3FL) in
           let res = Int64.shift_left val_op shift in
           state.flags <- CC_OP_LOGIC { dst = res; width = B64 };
           state.vstack <- res :: rest;
           state.vsp <- Int64.add state.vsp 8L
       | _ -> ())
  | Shr ->
      (match state.vstack with
       | count :: val_op :: rest ->
           let shift = Int64.to_int (Int64.logand count 0x3FL) in
           let res = Int64.shift_right_logical val_op shift in
           state.flags <- CC_OP_LOGIC { dst = res; width = B64 };
           state.vstack <- res :: rest;
           state.vsp <- Int64.add state.vsp 8L
       | _ -> ())
  | Dup ->
      (match state.vstack with
       | top :: _ ->
           state.vstack <- top :: state.vstack;
           state.vsp <- Int64.sub state.vsp 8L
       | [] -> ())
  | Swap ->
      (match state.vstack with
       | a :: b :: rest ->
           state.vstack <- b :: a :: rest
       | _ -> ())
  | PushFlags ->
      (* Push simulated raw EFLAGS integer *)
      let fl = match state.flags with
        | CC_OP_RAW raw -> raw
        | _ -> 0x02L
      in
      state.vstack <- fl :: state.vstack;
      state.vsp <- Int64.sub state.vsp 8L
  | PopFlags ->
      (match state.vstack with
       | fl :: rest ->
           state.flags <- CC_OP_RAW fl;
           state.vstack <- rest;
           state.vsp <- Int64.add state.vsp 8L
       | [] -> ())
  | JmpRel target ->
      state.current_block_id <- target
  | JccRel (target, cond) ->
      if Flags.evaluate_condition state.flags cond then
        state.current_block_id <- target
  | KeyAdjust delta ->
      state.vkey <- Int64.logxor state.vkey delta
  | Exit ->
      state.halted <- true
  | CallExtern _ -> ()
  | ResolveSym _ ->
      state.vstack <- 0x1000L :: state.vstack;
      state.vsp <- Int64.sub state.vsp 8L
  | Setcc c ->
      let v = if Flags.evaluate_condition state.flags c then 1L else 0L in
      state.vstack <- v :: state.vstack;
      state.vsp <- Int64.sub state.vsp 8L
  | Cmov (c, idx) ->
      (match state.vstack with
       | v :: rest ->
           state.vstack <- rest;
           state.vsp <- Int64.add state.vsp 8L;
           if Flags.evaluate_condition state.flags c then
             set_reg state idx v
       | [] -> ())
  | Cmp ->
      (match state.vstack with
       | op2 :: op1 :: rest ->
           let res = Int64.sub op1 op2 in
           state.flags <- CC_OP_SUB { src1 = op1; src2 = op2; dst = res; width = B64 };
           state.vstack <- rest;
           state.vsp <- Int64.add state.vsp 16L
       | _ -> ())
  | Test ->
      (match state.vstack with
       | op2 :: op1 :: rest ->
           let res = Int64.logand op1 op2 in
           state.flags <- CC_OP_LOGIC { dst = res; width = B64 };
           state.vstack <- rest;
           state.vsp <- Int64.add state.vsp 16L
       | _ -> ())

let run_program ?(max_steps = 100000) ?initial_ctx prog =
  let state = create_state ?initial_ctx () in
  state.current_block_id <- prog.entry_id;
  let steps = ref 0 in
  while not state.halted && !steps < max_steps do
    match Hashtbl.find_opt prog.blocks state.current_block_id with
    | None -> state.halted <- true
    | Some block ->
        let initial_block = state.current_block_id in
        let rec exec_ops = function
          | [] -> ()
          | op :: rest ->
              step_op state op;
              if not state.halted && state.current_block_id = initial_block then
                exec_ops rest
        in
        exec_ops block.ops;
        incr steps
  done;
  state

let run_bytecode ?(max_steps = 100000) ?initial_ctx enc =
  let state = create_state ~seed_key:enc.seed_key ?initial_ctx () in
  let pos = ref 0 in
  let key = ref enc.seed_key in
  let steps = ref 0 in
  while not state.halted && !steps < max_steps && !pos < Bytes.length enc.bytes do
    let cur_bid = state.current_block_id in
    match decode_op ~op_map:enc.op_map enc.bytes pos key with
    | None -> state.halted <- true
    | Some op ->
        step_op state op;
        if state.current_block_id <> cur_bid then begin
          match Hashtbl.find_opt enc.block_offsets state.current_block_id,
                Hashtbl.find_opt enc.block_keys state.current_block_id with
          | Some new_pos, Some new_key ->
              pos := new_pos;
              key := new_key
          | _ -> state.halted <- true
        end;
        incr steps
  done;
  state
