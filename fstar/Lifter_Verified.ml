open Prims
type u64 = Obj.t FStar_UInt.uint_t
type reg_id =
  | RAX 
  | RBX 
  | RCX 
  | RDX 
  | RSI 
  | RDI 
  | RBP 
  | RSP 
  | VTMP0 
  | VTMP1 
let uu___is_RAX (projectee : reg_id) : Prims.bool=
  match projectee with | RAX -> true | uu___ -> false
let uu___is_RBX (projectee : reg_id) : Prims.bool=
  match projectee with | RBX -> true | uu___ -> false
let uu___is_RCX (projectee : reg_id) : Prims.bool=
  match projectee with | RCX -> true | uu___ -> false
let uu___is_RDX (projectee : reg_id) : Prims.bool=
  match projectee with | RDX -> true | uu___ -> false
let uu___is_RSI (projectee : reg_id) : Prims.bool=
  match projectee with | RSI -> true | uu___ -> false
let uu___is_RDI (projectee : reg_id) : Prims.bool=
  match projectee with | RDI -> true | uu___ -> false
let uu___is_RBP (projectee : reg_id) : Prims.bool=
  match projectee with | RBP -> true | uu___ -> false
let uu___is_RSP (projectee : reg_id) : Prims.bool=
  match projectee with | RSP -> true | uu___ -> false
let uu___is_VTMP0 (projectee : reg_id) : Prims.bool=
  match projectee with | VTMP0 -> true | uu___ -> false
let uu___is_VTMP1 (projectee : reg_id) : Prims.bool=
  match projectee with | VTMP1 -> true | uu___ -> false
let is_arch_reg (r : reg_id) : Prims.bool=
  match r with | VTMP0 -> false | VTMP1 -> false | uu___ -> true
type flag_state =
  {
  cf: Prims.bool ;
  zf: Prims.bool ;
  sf: Prims.bool ;
  of_flag: Prims.bool }
let __proj__Mkflag_state__item__cf (projectee : flag_state) : Prims.bool=
  match projectee with | { cf; zf; sf; of_flag;_} -> cf
let __proj__Mkflag_state__item__zf (projectee : flag_state) : Prims.bool=
  match projectee with | { cf; zf; sf; of_flag;_} -> zf
let __proj__Mkflag_state__item__sf (projectee : flag_state) : Prims.bool=
  match projectee with | { cf; zf; sf; of_flag;_} -> sf
let __proj__Mkflag_state__item__of_flag (projectee : flag_state) :
  Prims.bool= match projectee with | { cf; zf; sf; of_flag;_} -> of_flag
type machine_state = {
  regs: reg_id -> u64 ;
  flags: flag_state }
let __proj__Mkmachine_state__item__regs (projectee : machine_state) :
  reg_id -> u64= match projectee with | { regs; flags;_} -> regs
let __proj__Mkmachine_state__item__flags (projectee : machine_state) :
  flag_state= match projectee with | { regs; flags;_} -> flags
let get_reg (st : machine_state) (r : reg_id) : u64= st.regs r
let set_reg (st : machine_state) (r : reg_id) (v : u64) : machine_state=
  { regs = (fun r' -> if r' = r then v else st.regs r'); flags = (st.flags) }
let set_flags (st : machine_state) (fl : flag_state) : machine_state=
  { regs = (st.regs); flags = fl }
type alu_op =
  | OpAdd 
  | OpSub 
  | OpXor 
  | OpAnd 
  | OpOr 
  | OpShl 
  | OpShr 
  | OpRol 
  | OpRor 
let uu___is_OpAdd (projectee : alu_op) : Prims.bool=
  match projectee with | OpAdd -> true | uu___ -> false
let uu___is_OpSub (projectee : alu_op) : Prims.bool=
  match projectee with | OpSub -> true | uu___ -> false
let uu___is_OpXor (projectee : alu_op) : Prims.bool=
  match projectee with | OpXor -> true | uu___ -> false
let uu___is_OpAnd (projectee : alu_op) : Prims.bool=
  match projectee with | OpAnd -> true | uu___ -> false
let uu___is_OpOr (projectee : alu_op) : Prims.bool=
  match projectee with | OpOr -> true | uu___ -> false
let uu___is_OpShl (projectee : alu_op) : Prims.bool=
  match projectee with | OpShl -> true | uu___ -> false
let uu___is_OpShr (projectee : alu_op) : Prims.bool=
  match projectee with | OpShr -> true | uu___ -> false
let uu___is_OpRol (projectee : alu_op) : Prims.bool=
  match projectee with | OpRol -> true | uu___ -> false
let uu___is_OpRor (projectee : alu_op) : Prims.bool=
  match projectee with | OpRor -> true | uu___ -> false
let eval_alu (op : alu_op) (a : u64) (b : u64) : u64=
  match op with
  | OpAdd -> FStar_UInt.add_mod (Prims.of_int 64) a b
  | OpSub -> FStar_UInt.sub_mod (Prims.of_int 64) a b
  | OpXor -> FStar_UInt.logxor (Prims.of_int 64) a b
  | OpAnd -> FStar_UInt.logand (Prims.of_int 64) a b
  | OpOr -> FStar_UInt.logor (Prims.of_int 64) a b
  | OpShl ->
      let shift = FStar_UInt.logand (Prims.of_int 64) b (Prims.of_int 63) in
      FStar_UInt.shift_left (Prims.of_int 64) a shift
  | OpShr ->
      let shift = FStar_UInt.logand (Prims.of_int 64) b (Prims.of_int 63) in
      FStar_UInt.shift_right (Prims.of_int 64) a shift
  | OpRol ->
      let shift = FStar_UInt.logand (Prims.of_int 64) b (Prims.of_int 63) in
      FStar_UInt.rotate_left (Prims.of_int 64) a shift
  | OpRor ->
      let shift = FStar_UInt.logand (Prims.of_int 64) b (Prims.of_int 63) in
      FStar_UInt.rotate_right (Prims.of_int 64) a shift
type unary_op =
  | OpInc 
  | OpDec 
  | OpNot 
  | OpNeg 
let uu___is_OpInc (projectee : unary_op) : Prims.bool=
  match projectee with | OpInc -> true | uu___ -> false
let uu___is_OpDec (projectee : unary_op) : Prims.bool=
  match projectee with | OpDec -> true | uu___ -> false
let uu___is_OpNot (projectee : unary_op) : Prims.bool=
  match projectee with | OpNot -> true | uu___ -> false
let uu___is_OpNeg (projectee : unary_op) : Prims.bool=
  match projectee with | OpNeg -> true | uu___ -> false
let eval_unary (op : unary_op) (a : u64) : u64=
  match op with
  | OpInc -> FStar_UInt.add_mod (Prims.of_int 64) a Prims.int_one
  | OpDec -> FStar_UInt.sub_mod (Prims.of_int 64) a Prims.int_one
  | OpNot -> FStar_UInt.lognot (Prims.of_int 64) a
  | OpNeg -> FStar_UInt.sub_mod (Prims.of_int 64) Prims.int_zero a
let compute_flags_sub (a : u64) (b : u64) : flag_state=
  let res = FStar_UInt.sub_mod (Prims.of_int 64) a b in
  let cf = a < b in
  let zf = res = Prims.int_zero in
  let sf = FStar_UInt.nth (Prims.of_int 64) res (Prims.of_int 63) in
  let a_sign = FStar_UInt.nth (Prims.of_int 64) a (Prims.of_int 63) in
  let b_sign = FStar_UInt.nth (Prims.of_int 64) b (Prims.of_int 63) in
  let res_sign = FStar_UInt.nth (Prims.of_int 64) res (Prims.of_int 63) in
  let of_flag = (a_sign <> b_sign) && (res_sign <> a_sign) in
  { cf; zf; sf; of_flag }
let compute_flags_and (a : u64) (b : u64) : flag_state=
  let res = FStar_UInt.logand (Prims.of_int 64) a b in
  {
    cf = false;
    zf = (res = Prims.int_zero);
    sf = (FStar_UInt.nth (Prims.of_int 64) res (Prims.of_int 63));
    of_flag = false
  }
type cond_code =
  | CondE 
  | CondNE 
  | CondB 
  | CondAE 
  | CondL 
  | CondGE 
let uu___is_CondE (projectee : cond_code) : Prims.bool=
  match projectee with | CondE -> true | uu___ -> false
let uu___is_CondNE (projectee : cond_code) : Prims.bool=
  match projectee with | CondNE -> true | uu___ -> false
let uu___is_CondB (projectee : cond_code) : Prims.bool=
  match projectee with | CondB -> true | uu___ -> false
let uu___is_CondAE (projectee : cond_code) : Prims.bool=
  match projectee with | CondAE -> true | uu___ -> false
let uu___is_CondL (projectee : cond_code) : Prims.bool=
  match projectee with | CondL -> true | uu___ -> false
let uu___is_CondGE (projectee : cond_code) : Prims.bool=
  match projectee with | CondGE -> true | uu___ -> false
let eval_cond (cond : cond_code) (fl : flag_state) : Prims.bool=
  match cond with
  | CondE -> fl.zf
  | CondNE -> Prims.not fl.zf
  | CondB -> fl.cf
  | CondAE -> Prims.not fl.cf
  | CondL -> fl.sf <> fl.of_flag
  | CondGE -> fl.sf = fl.of_flag
type operand =
  | Reg of reg_id 
  | Imm of u64 
let uu___is_Reg (projectee : operand) : Prims.bool=
  match projectee with | Reg r -> true | uu___ -> false
let __proj__Reg__item__r (projectee : operand) : reg_id=
  match projectee with | Reg r -> r
let uu___is_Imm (projectee : operand) : Prims.bool=
  match projectee with | Imm i -> true | uu___ -> false
let __proj__Imm__item__i (projectee : operand) : u64=
  match projectee with | Imm i -> i
let is_arch_operand (op : operand) : Prims.bool=
  match op with | Reg r -> is_arch_reg r | Imm uu___ -> true
let eval_op (st : machine_state) (op : operand) : u64=
  match op with | Reg r -> get_reg st r | Imm i -> i
type arch_instr =
  | Arch_Mov of reg_id * operand 
  | Arch_Alu of alu_op * reg_id * operand 
  | Arch_Unary of unary_op * reg_id 
  | Arch_Cmp of operand * operand 
  | Arch_Test of operand * operand 
  | Arch_Cmov of cond_code * reg_id * operand 
  | Arch_Xchg of reg_id * reg_id 
  | Arch_Xadd of reg_id * reg_id 
  | Arch_Andn of reg_id * reg_id * operand 
let uu___is_Arch_Mov (projectee : arch_instr) : Prims.bool=
  match projectee with | Arch_Mov (dst, src) -> true | uu___ -> false
let __proj__Arch_Mov__item__dst (projectee : arch_instr) : reg_id=
  match projectee with | Arch_Mov (dst, src) -> dst
let __proj__Arch_Mov__item__src (projectee : arch_instr) : operand=
  match projectee with | Arch_Mov (dst, src) -> src
let uu___is_Arch_Alu (projectee : arch_instr) : Prims.bool=
  match projectee with | Arch_Alu (op, dst, src) -> true | uu___ -> false
let __proj__Arch_Alu__item__op (projectee : arch_instr) : alu_op=
  match projectee with | Arch_Alu (op, dst, src) -> op
let __proj__Arch_Alu__item__dst (projectee : arch_instr) : reg_id=
  match projectee with | Arch_Alu (op, dst, src) -> dst
let __proj__Arch_Alu__item__src (projectee : arch_instr) : operand=
  match projectee with | Arch_Alu (op, dst, src) -> src
let uu___is_Arch_Unary (projectee : arch_instr) : Prims.bool=
  match projectee with | Arch_Unary (op, dst) -> true | uu___ -> false
let __proj__Arch_Unary__item__op (projectee : arch_instr) : unary_op=
  match projectee with | Arch_Unary (op, dst) -> op
let __proj__Arch_Unary__item__dst (projectee : arch_instr) : reg_id=
  match projectee with | Arch_Unary (op, dst) -> dst
let uu___is_Arch_Cmp (projectee : arch_instr) : Prims.bool=
  match projectee with | Arch_Cmp (s1, s2) -> true | uu___ -> false
let __proj__Arch_Cmp__item__s1 (projectee : arch_instr) : operand=
  match projectee with | Arch_Cmp (s1, s2) -> s1
let __proj__Arch_Cmp__item__s2 (projectee : arch_instr) : operand=
  match projectee with | Arch_Cmp (s1, s2) -> s2
let uu___is_Arch_Test (projectee : arch_instr) : Prims.bool=
  match projectee with | Arch_Test (s1, s2) -> true | uu___ -> false
let __proj__Arch_Test__item__s1 (projectee : arch_instr) : operand=
  match projectee with | Arch_Test (s1, s2) -> s1
let __proj__Arch_Test__item__s2 (projectee : arch_instr) : operand=
  match projectee with | Arch_Test (s1, s2) -> s2
let uu___is_Arch_Cmov (projectee : arch_instr) : Prims.bool=
  match projectee with | Arch_Cmov (cond, dst, src) -> true | uu___ -> false
let __proj__Arch_Cmov__item__cond (projectee : arch_instr) : cond_code=
  match projectee with | Arch_Cmov (cond, dst, src) -> cond
let __proj__Arch_Cmov__item__dst (projectee : arch_instr) : reg_id=
  match projectee with | Arch_Cmov (cond, dst, src) -> dst
let __proj__Arch_Cmov__item__src (projectee : arch_instr) : operand=
  match projectee with | Arch_Cmov (cond, dst, src) -> src
let uu___is_Arch_Xchg (projectee : arch_instr) : Prims.bool=
  match projectee with | Arch_Xchg (r1, r2) -> true | uu___ -> false
let __proj__Arch_Xchg__item__r1 (projectee : arch_instr) : reg_id=
  match projectee with | Arch_Xchg (r1, r2) -> r1
let __proj__Arch_Xchg__item__r2 (projectee : arch_instr) : reg_id=
  match projectee with | Arch_Xchg (r1, r2) -> r2
let uu___is_Arch_Xadd (projectee : arch_instr) : Prims.bool=
  match projectee with | Arch_Xadd (dst, src) -> true | uu___ -> false
let __proj__Arch_Xadd__item__dst (projectee : arch_instr) : reg_id=
  match projectee with | Arch_Xadd (dst, src) -> dst
let __proj__Arch_Xadd__item__src (projectee : arch_instr) : reg_id=
  match projectee with | Arch_Xadd (dst, src) -> src
let uu___is_Arch_Andn (projectee : arch_instr) : Prims.bool=
  match projectee with | Arch_Andn (dst, s1, s2) -> true | uu___ -> false
let __proj__Arch_Andn__item__dst (projectee : arch_instr) : reg_id=
  match projectee with | Arch_Andn (dst, s1, s2) -> dst
let __proj__Arch_Andn__item__s1 (projectee : arch_instr) : reg_id=
  match projectee with | Arch_Andn (dst, s1, s2) -> s1
let __proj__Arch_Andn__item__s2 (projectee : arch_instr) : operand=
  match projectee with | Arch_Andn (dst, s1, s2) -> s2
let step_arch (st : machine_state) (instr : arch_instr) : machine_state=
  match instr with
  | Arch_Mov (dst, src) -> set_reg st dst (eval_op st src)
  | Arch_Alu (op, dst, src) ->
      let v_dst = get_reg st dst in
      let v_src = eval_op st src in
      let res = eval_alu op v_dst v_src in
      let fl =
        match op with
        | OpSub -> compute_flags_sub v_dst v_src
        | OpAnd -> compute_flags_and v_dst v_src
        | uu___ -> st.flags in
      set_flags (set_reg st dst res) fl
  | Arch_Unary (op, dst) ->
      let v = get_reg st dst in
      let res = eval_unary op v in set_reg st dst res
  | Arch_Cmp (s1, s2) ->
      let fl = compute_flags_sub (eval_op st s1) (eval_op st s2) in
      set_flags st fl
  | Arch_Test (s1, s2) ->
      let fl = compute_flags_and (eval_op st s1) (eval_op st s2) in
      set_flags st fl
  | Arch_Cmov (cond, dst, src) ->
      if eval_cond cond st.flags then set_reg st dst (eval_op st src) else st
  | Arch_Xchg (r1, r2) ->
      let v1 = get_reg st r1 in
      let v2 = get_reg st r2 in set_reg (set_reg st r1 v2) r2 v1
  | Arch_Xadd (dst, src) ->
      let v_dst = get_reg st dst in
      let v_src = get_reg st src in
      let res = FStar_UInt.add_mod (Prims.of_int 64) v_dst v_src in
      if dst = src
      then set_reg st dst res
      else (let st1 = set_reg st src v_dst in set_reg st1 dst res)
  | Arch_Andn (dst, s1, s2) ->
      let v1 = get_reg st s1 in
      let v2 = eval_op st s2 in
      let res =
        FStar_UInt.logand (Prims.of_int 64)
          (FStar_UInt.lognot (Prims.of_int 64) v1) v2 in
      let fl = compute_flags_and (FStar_UInt.lognot (Prims.of_int 64) v1) v2 in
      set_flags (set_reg st dst res) fl
type vm_instr =
  | Vm_Mov of reg_id * operand 
  | Vm_Alu of alu_op * reg_id * operand * operand * Prims.bool 
  | Vm_Unary of unary_op * reg_id * operand 
  | Vm_Cmp of operand * operand 
  | Vm_Test of operand * operand 
  | Vm_Cmov of cond_code * reg_id * operand 
let uu___is_Vm_Mov (projectee : vm_instr) : Prims.bool=
  match projectee with | Vm_Mov (dst, src) -> true | uu___ -> false
let __proj__Vm_Mov__item__dst (projectee : vm_instr) : reg_id=
  match projectee with | Vm_Mov (dst, src) -> dst
let __proj__Vm_Mov__item__src (projectee : vm_instr) : operand=
  match projectee with | Vm_Mov (dst, src) -> src
let uu___is_Vm_Alu (projectee : vm_instr) : Prims.bool=
  match projectee with
  | Vm_Alu (op, dst, src1, src2, set_fl) -> true
  | uu___ -> false
let __proj__Vm_Alu__item__op (projectee : vm_instr) : alu_op=
  match projectee with | Vm_Alu (op, dst, src1, src2, set_fl) -> op
let __proj__Vm_Alu__item__dst (projectee : vm_instr) : reg_id=
  match projectee with | Vm_Alu (op, dst, src1, src2, set_fl) -> dst
let __proj__Vm_Alu__item__src1 (projectee : vm_instr) : operand=
  match projectee with | Vm_Alu (op, dst, src1, src2, set_fl) -> src1
let __proj__Vm_Alu__item__src2 (projectee : vm_instr) : operand=
  match projectee with | Vm_Alu (op, dst, src1, src2, set_fl) -> src2
let __proj__Vm_Alu__item__set_fl (projectee : vm_instr) : Prims.bool=
  match projectee with | Vm_Alu (op, dst, src1, src2, set_fl) -> set_fl
let uu___is_Vm_Unary (projectee : vm_instr) : Prims.bool=
  match projectee with | Vm_Unary (op, dst, src) -> true | uu___ -> false
let __proj__Vm_Unary__item__op (projectee : vm_instr) : unary_op=
  match projectee with | Vm_Unary (op, dst, src) -> op
let __proj__Vm_Unary__item__dst (projectee : vm_instr) : reg_id=
  match projectee with | Vm_Unary (op, dst, src) -> dst
let __proj__Vm_Unary__item__src (projectee : vm_instr) : operand=
  match projectee with | Vm_Unary (op, dst, src) -> src
let uu___is_Vm_Cmp (projectee : vm_instr) : Prims.bool=
  match projectee with | Vm_Cmp (s1, s2) -> true | uu___ -> false
let __proj__Vm_Cmp__item__s1 (projectee : vm_instr) : operand=
  match projectee with | Vm_Cmp (s1, s2) -> s1
let __proj__Vm_Cmp__item__s2 (projectee : vm_instr) : operand=
  match projectee with | Vm_Cmp (s1, s2) -> s2
let uu___is_Vm_Test (projectee : vm_instr) : Prims.bool=
  match projectee with | Vm_Test (s1, s2) -> true | uu___ -> false
let __proj__Vm_Test__item__s1 (projectee : vm_instr) : operand=
  match projectee with | Vm_Test (s1, s2) -> s1
let __proj__Vm_Test__item__s2 (projectee : vm_instr) : operand=
  match projectee with | Vm_Test (s1, s2) -> s2
let uu___is_Vm_Cmov (projectee : vm_instr) : Prims.bool=
  match projectee with | Vm_Cmov (cond, dst, src) -> true | uu___ -> false
let __proj__Vm_Cmov__item__cond (projectee : vm_instr) : cond_code=
  match projectee with | Vm_Cmov (cond, dst, src) -> cond
let __proj__Vm_Cmov__item__dst (projectee : vm_instr) : reg_id=
  match projectee with | Vm_Cmov (cond, dst, src) -> dst
let __proj__Vm_Cmov__item__src (projectee : vm_instr) : operand=
  match projectee with | Vm_Cmov (cond, dst, src) -> src
let step_vm (st : machine_state) (instr : vm_instr) : machine_state=
  match instr with
  | Vm_Mov (dst, src) -> set_reg st dst (eval_op st src)
  | Vm_Alu (op, dst, s1, s2, set_fl) ->
      let v1 = eval_op st s1 in
      let v2 = eval_op st s2 in
      let res = eval_alu op v1 v2 in
      let fl =
        if set_fl
        then
          match op with
          | OpSub -> compute_flags_sub v1 v2
          | OpAnd -> compute_flags_and v1 v2
          | uu___ -> st.flags
        else st.flags in
      set_flags (set_reg st dst res) fl
  | Vm_Unary (op, dst, s) ->
      let res = eval_unary op (eval_op st s) in set_reg st dst res
  | Vm_Cmp (s1, s2) ->
      let fl = compute_flags_sub (eval_op st s1) (eval_op st s2) in
      set_flags st fl
  | Vm_Test (s1, s2) ->
      let fl = compute_flags_and (eval_op st s1) (eval_op st s2) in
      set_flags st fl
  | Vm_Cmov (cond, dst, src) ->
      if eval_cond cond st.flags then set_reg st dst (eval_op st src) else st
let rec step_vm_seq (st : machine_state) (instrs : vm_instr Prims.list) :
  machine_state=
  match instrs with
  | [] -> st
  | head::rest -> step_vm_seq (step_vm st head) rest
let lift_instr (instr : arch_instr) : vm_instr Prims.list=
  match instr with
  | Arch_Mov (dst, src) -> [Vm_Mov (dst, src)]
  | Arch_Alu (op, dst, src) ->
      let need_flags = (op = OpSub) || (op = OpAnd) in
      [Vm_Alu (op, dst, (Reg dst), src, need_flags)]
  | Arch_Unary (op, dst) -> [Vm_Unary (op, dst, (Reg dst))]
  | Arch_Cmp (s1, s2) -> [Vm_Cmp (s1, s2)]
  | Arch_Test (s1, s2) -> [Vm_Test (s1, s2)]
  | Arch_Cmov (cond, dst, src) -> [Vm_Cmov (cond, dst, src)]
  | Arch_Xchg (r1, r2) ->
      [Vm_Mov (VTMP0, (Reg r1));
      Vm_Mov (r1, (Reg r2));
      Vm_Mov (r2, (Reg VTMP0))]
  | Arch_Xadd (dst, src) ->
      if dst = src
      then [Vm_Alu (OpAdd, dst, (Reg dst), (Reg dst), false)]
      else
        [Vm_Mov (VTMP0, (Reg dst));
        Vm_Alu (OpAdd, dst, (Reg dst), (Reg src), false);
        Vm_Mov (src, (Reg VTMP0))]
  | Arch_Andn (dst, s1, s2) ->
      [Vm_Mov (VTMP1, (Reg s1));
      Vm_Unary (OpNot, VTMP1, (Reg VTMP1));
      Vm_Alu (OpAnd, dst, (Reg VTMP1), s2, true)]
