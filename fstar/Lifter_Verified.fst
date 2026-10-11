(**
  Lifter_Verified.fst — Формальная верификация Instruction Lifter и семантической эквивалентности в ASGARD-5877.
  F* 2026.08.23 + Z3 5.0.0.

  Доказывает:
  1. Семантическую эквивалентность понижения x86 ALU операций (Add, Sub, Xor, And, Or, Shl, Shr, Rol, Ror).
  2. Семантическую эквивалентность унарных инструкций (Inc, Dec, Not, Neg).
  3. Семантическую эквивалентность операций флагов (Cmp, Test).
  4. Семантическую эквивалентность условной пересылки (Cmov).
  5. Корректность понижения составных x86 инструкций:
     - Xchg r1 r2 (обмен без потерь)
     - Xadd dst src (атомарное сложение и сохранение старого значения)
     - Andn dst s1 s2 (композиция Not и And)
  6. Главная теорема трансляции (Lifter Simulation Soundness):
     Для любой архитектурной инструкции последовательность инструкций VM-IR
     сохраняет точное архитектурное состояние регистров и флагов.
*)
module Lifter_Verified

open FStar.UInt
open FStar.UInt64
open FStar.List.Tot

type u64 = uint_t 64

type reg_id =
  | RAX | RBX | RCX | RDX | RSI | RDI | RBP | RSP
  | VTMP0 | VTMP1

let is_arch_reg (r:reg_id) : bool =
  match r with
  | VTMP0 | VTMP1 -> false
  | _ -> true

type flag_state = {
  cf : bool;
  zf : bool;
  sf : bool;
  of_flag : bool;
}

noeq type machine_state = {
  regs : reg_id -> u64;
  flags: flag_state;
}

let get_reg (st:machine_state) (r:reg_id) : u64 = st.regs r

let set_reg (st:machine_state) (r:reg_id) (v:u64) : machine_state =
  { st with regs = (fun r' -> if r' = r then v else st.regs r') }

let set_flags (st:machine_state) (fl:flag_state) : machine_state =
  { st with flags = fl }

(* ------------------------------------------------------------------ *)
(* 1. Арифметико-логические операции и флаги                          *)
(* ------------------------------------------------------------------ *)

type alu_op =
  | OpAdd | OpSub | OpXor | OpAnd | OpOr
  | OpShl | OpShr | OpRol | OpRor

let eval_alu (op:alu_op) (a:u64) (b:u64) : u64 =
  match op with
  | OpAdd -> add_mod #64 a b
  | OpSub -> sub_mod #64 a b
  | OpXor -> logxor #64 a b
  | OpAnd -> logand #64 a b
  | OpOr  -> logor #64 a b
  | OpShl ->
    let shift = logand #64 b 63 in
    shift_left #64 a shift
  | OpShr ->
    let shift = logand #64 b 63 in
    shift_right #64 a shift
  | OpRol ->
    let shift = logand #64 b 63 in
    rotate_left #64 a shift
  | OpRor ->
    let shift = logand #64 b 63 in
    rotate_right #64 a shift

type unary_op =
  | OpInc | OpDec | OpNot | OpNeg

let eval_unary (op:unary_op) (a:u64) : u64 =
  match op with
  | OpInc -> add_mod #64 a 1
  | OpDec -> sub_mod #64 a 1
  | OpNot -> lognot #64 a
  | OpNeg -> sub_mod #64 0 a

let compute_flags_sub (a:u64) (b:u64) : flag_state =
  let res = sub_mod #64 a b in
  let cf = a < b in
  let zf = res = 0 in
  let sf = nth res 63 in
  let a_sign = nth a 63 in
  let b_sign = nth b 63 in
  let res_sign = nth res 63 in
  let of_flag = (a_sign <> b_sign) && (res_sign <> a_sign) in
  { cf; zf; sf; of_flag }

let compute_flags_and (a:u64) (b:u64) : flag_state =
  let res = logand #64 a b in
  { cf = false; zf = (res = 0); sf = nth res 63; of_flag = false }

type cond_code =
  | CondE | CondNE | CondB | CondAE | CondL | CondGE

let eval_cond (cond:cond_code) (fl:flag_state) : bool =
  match cond with
  | CondE  -> fl.zf
  | CondNE -> not fl.zf
  | CondB  -> fl.cf
  | CondAE -> not fl.cf
  | CondL  -> fl.sf <> fl.of_flag
  | CondGE -> fl.sf = fl.of_flag

(* ------------------------------------------------------------------ *)
(* 2. Архитектурный AST и семантика (x86_64)                         *)
(* ------------------------------------------------------------------ *)

type operand =
  | Reg : r:reg_id -> operand
  | Imm : i:u64 -> operand

let is_arch_operand (op:operand) : bool =
  match op with
  | Reg r -> is_arch_reg r
  | Imm _ -> true

let eval_op (st:machine_state) (op:operand) : u64 =
  match op with
  | Reg r -> get_reg st r
  | Imm i -> i

type arch_instr =
  | Arch_Mov   : dst:reg_id -> src:operand -> arch_instr
  | Arch_Alu   : op:alu_op -> dst:reg_id -> src:operand -> arch_instr
  | Arch_Unary : op:unary_op -> dst:reg_id -> arch_instr
  | Arch_Cmp   : s1:operand -> s2:operand -> arch_instr
  | Arch_Test  : s1:operand -> s2:operand -> arch_instr
  | Arch_Cmov  : cond:cond_code -> dst:reg_id -> src:operand -> arch_instr
  | Arch_Xchg  : r1:reg_id -> r2:reg_id -> arch_instr
  | Arch_Xadd  : dst:reg_id -> src:reg_id -> arch_instr
  | Arch_Andn  : dst:reg_id -> s1:reg_id -> s2:operand -> arch_instr

let step_arch (st:machine_state) (instr:arch_instr) : machine_state =
  match instr with
  | Arch_Mov dst src ->
    set_reg st dst (eval_op st src)
  | Arch_Alu op dst src ->
    let v_dst = get_reg st dst in
    let v_src = eval_op st src in
    let res = eval_alu op v_dst v_src in
    let fl =
      match op with
      | OpSub -> compute_flags_sub v_dst v_src
      | OpAnd -> compute_flags_and v_dst v_src
      | _ -> st.flags
    in
    set_flags (set_reg st dst res) fl
  | Arch_Unary op dst ->
    let v = get_reg st dst in
    let res = eval_unary op v in
    set_reg st dst res
  | Arch_Cmp s1 s2 ->
    let fl = compute_flags_sub (eval_op st s1) (eval_op st s2) in
    set_flags st fl
  | Arch_Test s1 s2 ->
    let fl = compute_flags_and (eval_op st s1) (eval_op st s2) in
    set_flags st fl
  | Arch_Cmov cond dst src ->
    if eval_cond cond st.flags then
      set_reg st dst (eval_op st src)
    else st
  | Arch_Xchg r1 r2 ->
    let v1 = get_reg st r1 in
    let v2 = get_reg st r2 in
    set_reg (set_reg st r1 v2) r2 v1
  | Arch_Xadd dst src ->
    let v_dst = get_reg st dst in
    let v_src = get_reg st src in
    let res = add_mod #64 v_dst v_src in
    if dst = src then
      set_reg st dst res
    else
      let st1 = set_reg st src v_dst in
      set_reg st1 dst res
  | Arch_Andn dst s1 s2 ->
    let v1 = get_reg st s1 in
    let v2 = eval_op st s2 in
    let res = logand #64 (lognot #64 v1) v2 in
    let fl = compute_flags_and (lognot #64 v1) v2 in
    set_flags (set_reg st dst res) fl

(* ------------------------------------------------------------------ *)
(* 3. Промежуточный язык VM-IR и его семантика                        *)
(* ------------------------------------------------------------------ *)

type vm_instr =
  | Vm_Mov   : dst:reg_id -> src:operand -> vm_instr
  | Vm_Alu   : op:alu_op -> dst:reg_id -> src1:operand -> src2:operand -> set_fl:bool -> vm_instr
  | Vm_Unary : op:unary_op -> dst:reg_id -> src:operand -> vm_instr
  | Vm_Cmp   : s1:operand -> s2:operand -> vm_instr
  | Vm_Test  : s1:operand -> s2:operand -> vm_instr
  | Vm_Cmov  : cond:cond_code -> dst:reg_id -> src:operand -> vm_instr

let step_vm (st:machine_state) (instr:vm_instr) : machine_state =
  match instr with
  | Vm_Mov dst src ->
    set_reg st dst (eval_op st src)
  | Vm_Alu op dst s1 s2 set_fl ->
    let v1 = eval_op st s1 in
    let v2 = eval_op st s2 in
    let res = eval_alu op v1 v2 in
    let fl =
      if set_fl then
        match op with
        | OpSub -> compute_flags_sub v1 v2
        | OpAnd -> compute_flags_and v1 v2
        | _ -> st.flags
      else st.flags
    in
    set_flags (set_reg st dst res) fl
  | Vm_Unary op dst s ->
    let res = eval_unary op (eval_op st s) in
    set_reg st dst res
  | Vm_Cmp s1 s2 ->
    let fl = compute_flags_sub (eval_op st s1) (eval_op st s2) in
    set_flags st fl
  | Vm_Test s1 s2 ->
    let fl = compute_flags_and (eval_op st s1) (eval_op st s2) in
    set_flags st fl
  | Vm_Cmov cond dst src ->
    if eval_cond cond st.flags then
      set_reg st dst (eval_op st src)
    else st

let rec step_vm_seq (st:machine_state) (instrs:list vm_instr) : Tot machine_state (decreases instrs) =
  match instrs with
  | [] -> st
  | head :: rest ->
    step_vm_seq (step_vm st head) rest

(* ------------------------------------------------------------------ *)
(* 4. Реализация транслятора Instruction Lifter                      *)
(* ------------------------------------------------------------------ *)

let lift_instr (instr:arch_instr) : list vm_instr =
  match instr with
  | Arch_Mov dst src ->
    [ Vm_Mov dst src ]
  | Arch_Alu op dst src ->
    let need_flags = (op = OpSub || op = OpAnd) in
    [ Vm_Alu op dst (Reg dst) src need_flags ]
  | Arch_Unary op dst ->
    [ Vm_Unary op dst (Reg dst) ]
  | Arch_Cmp s1 s2 ->
    [ Vm_Cmp s1 s2 ]
  | Arch_Test s1 s2 ->
    [ Vm_Test s1 s2 ]
  | Arch_Cmov cond dst src ->
    [ Vm_Cmov cond dst src ]
  | Arch_Xchg r1 r2 ->
    [
      Vm_Mov VTMP0 (Reg r1);
      Vm_Mov r1 (Reg r2);
      Vm_Mov r2 (Reg VTMP0);
    ]
  | Arch_Xadd dst src ->
    if dst = src then
      [ Vm_Alu OpAdd dst (Reg dst) (Reg dst) false ]
    else
      [
        Vm_Mov VTMP0 (Reg dst);
        Vm_Alu OpAdd dst (Reg dst) (Reg src) false;
        Vm_Mov src (Reg VTMP0);
      ]
  | Arch_Andn dst s1 s2 ->
    [
      Vm_Mov VTMP1 (Reg s1);
      Vm_Unary OpNot VTMP1 (Reg VTMP1);
      Vm_Alu OpAnd dst (Reg VTMP1) s2 true;
    ]

(* ------------------------------------------------------------------ *)
(* 5. Теоремы семантической эквивалентности                           *)
(* ------------------------------------------------------------------ *)

let state_equiv_on_arch (s1:machine_state) (s2:machine_state) : prop =
  (forall (r:reg_id). is_arch_reg r ==> get_reg s1 r == get_reg s2 r) /\
  s1.flags == s2.flags

(** Теорема 1: Эквивалентность понижения Mov *)
val theorem_lift_mov_equiv : st:machine_state -> dst:reg_id -> src:operand ->
  Lemma (requires (is_arch_reg dst))
        (ensures (state_equiv_on_arch (step_vm_seq st (lift_instr (Arch_Mov dst src)))
                                      (step_arch st (Arch_Mov dst src))))
let theorem_lift_mov_equiv st dst src = ()

(** Теорема 2: Эквивалентность понижения ALU *)
val theorem_lift_alu_equiv : st:machine_state -> op:alu_op -> dst:reg_id -> src:operand ->
  Lemma (requires (is_arch_reg dst))
        (ensures (state_equiv_on_arch (step_vm_seq st (lift_instr (Arch_Alu op dst src)))
                                      (step_arch st (Arch_Alu op dst src))))
let theorem_lift_alu_equiv st op dst src = ()

(** Теорема 3: Эквивалентность понижения Unary *)
val theorem_lift_unary_equiv : st:machine_state -> op:unary_op -> dst:reg_id ->
  Lemma (requires (is_arch_reg dst))
        (ensures (state_equiv_on_arch (step_vm_seq st (lift_instr (Arch_Unary op dst)))
                                      (step_arch st (Arch_Unary op dst))))
let theorem_lift_unary_equiv st op dst = ()

(** Теорема 4: Эквивалентность понижения Cmp и Test *)
val theorem_lift_cmp_equiv : st:machine_state -> s1:operand -> s2:operand ->
  Lemma (state_equiv_on_arch (step_vm_seq st (lift_instr (Arch_Cmp s1 s2)))
                             (step_arch st (Arch_Cmp s1 s2)))
let theorem_lift_cmp_equiv st s1 s2 = ()

val theorem_lift_test_equiv : st:machine_state -> s1:operand -> s2:operand ->
  Lemma (state_equiv_on_arch (step_vm_seq st (lift_instr (Arch_Test s1 s2)))
                             (step_arch st (Arch_Test s1 s2)))
let theorem_lift_test_equiv st s1 s2 = ()

(** Теорема 5: Эквивалентность понижения Cmov *)
val theorem_lift_cmov_equiv : st:machine_state -> cond:cond_code -> dst:reg_id -> src:operand ->
  Lemma (requires (is_arch_reg dst))
        (ensures (state_equiv_on_arch (step_vm_seq st (lift_instr (Arch_Cmov cond dst src)))
                                      (step_arch st (Arch_Cmov cond dst src))))
let theorem_lift_cmov_equiv st cond dst src = ()

(** Теорема 6: Эквивалентность понижения составного Xchg *)
val theorem_lift_xchg_equiv : st:machine_state -> r1:reg_id -> r2:reg_id ->
  Lemma (requires (is_arch_reg r1 /\ is_arch_reg r2))
        (ensures (state_equiv_on_arch (step_vm_seq st (lift_instr (Arch_Xchg r1 r2)))
                                      (step_arch st (Arch_Xchg r1 r2))))
let theorem_lift_xchg_equiv st r1 r2 = ()

(** Теорема 7: Эквивалентность понижения составного Xadd *)
val theorem_lift_xadd_equiv : st:machine_state -> dst:reg_id -> src:reg_id ->
  Lemma (requires (is_arch_reg dst /\ is_arch_reg src))
        (ensures (state_equiv_on_arch (step_vm_seq st (lift_instr (Arch_Xadd dst src)))
                                      (step_arch st (Arch_Xadd dst src))))
let theorem_lift_xadd_equiv st dst src = ()

(** Теорема 8: Эквивалентность понижения составного Andn *)
val theorem_lift_andn_equiv : st:machine_state -> dst:reg_id -> s1:reg_id -> s2:operand ->
  Lemma (requires (is_arch_reg dst /\ is_arch_reg s1 /\ is_arch_operand s2))
        (ensures (state_equiv_on_arch (step_vm_seq st (lift_instr (Arch_Andn dst s1 s2)))
                                      (step_arch st (Arch_Andn dst s1 s2))))
let theorem_lift_andn_equiv st dst s1 s2 = ()

(** Главная теорема 9: Общая корректность Instruction Lifter (Simulation Soundness) *)
val theorem_lifter_soundness : st:machine_state -> instr:arch_instr ->
  Lemma (requires (
    match instr with
    | Arch_Mov dst src -> is_arch_reg dst /\ is_arch_operand src
    | Arch_Alu _ dst src -> is_arch_reg dst /\ is_arch_operand src
    | Arch_Unary _ dst -> is_arch_reg dst
    | Arch_Cmov _ dst src -> is_arch_reg dst /\ is_arch_operand src
    | Arch_Xchg r1 r2 -> is_arch_reg r1 /\ is_arch_reg r2
    | Arch_Xadd dst src -> is_arch_reg dst /\ is_arch_reg src
    | Arch_Andn dst s1 s2 -> is_arch_reg dst /\ is_arch_reg s1 /\ is_arch_operand s2
    | Arch_Cmp s1 s2 -> is_arch_operand s1 /\ is_arch_operand s2
    | Arch_Test s1 s2 -> is_arch_operand s1 /\ is_arch_operand s2
  ))
  (ensures (state_equiv_on_arch (step_vm_seq st (lift_instr instr))
                                (step_arch st instr)))
let theorem_lifter_soundness st instr =
  match instr with
  | Arch_Mov dst src -> theorem_lift_mov_equiv st dst src
  | Arch_Alu op dst src -> theorem_lift_alu_equiv st op dst src
  | Arch_Unary op dst -> theorem_lift_unary_equiv st op dst
  | Arch_Cmp s1 s2 -> theorem_lift_cmp_equiv st s1 s2
  | Arch_Test s1 s2 -> theorem_lift_test_equiv st s1 s2
  | Arch_Cmov cond dst src -> theorem_lift_cmov_equiv st cond dst src
  | Arch_Xchg r1 r2 -> theorem_lift_xchg_equiv st r1 r2
  | Arch_Xadd dst src -> theorem_lift_xadd_equiv st dst src
  | Arch_Andn dst s1 s2 -> theorem_lift_andn_equiv st dst s1 s2
