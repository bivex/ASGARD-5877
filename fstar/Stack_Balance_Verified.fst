(**
  Stack_Balance_Verified.fst — Формальная верификация стекового баланса и защиты от Underflow в ASGARD-5877.
  F* 2026.08.23 + Z3 5.0.0.

  Доказывает:
  1. Аддитивный гомоморфизм дельты стека: delta(L1 @ L2) = delta(L1) + delta(L2).
  2. Корректность восстановления баланса (Repair Soundness):
     Для ЛЮБОГО блока ops после repair_ops суммарная дельта строго равна 0.
  3. Инвариант путей CFG (Path Invariance):
     Любой путь через сбалансированные блоки сохраняет высоту стека неизменной (delta = 0).
  4. Сохранение дельты при динамическом выполнении без underflow:
     eval_depth d ops = Some (d + sum_delta ops).
  5. Корректность минимальной безопасной глубины (Min Required Depth / Underflow Freedom):
     Если начальная глубина >= min_req ops, стек гарантированно не опустошается ниже 0.
*)
module Stack_Balance_Verified

open FStar.List.Tot

(* ------------------------------------------------------------------ *)
(* 1. Определение системы команд Stack-VM                             *)
(* ------------------------------------------------------------------ *)

type condition =
  | Cond_O | Cond_NO | Cond_B | Cond_AE | Cond_E | Cond_NE | Cond_BE | Cond_A
  | Cond_S | Cond_NS | Cond_P | Cond_NP | Cond_L | Cond_GE | Cond_LE | Cond_G

type stack_op =
  | PushImm : int -> stack_op
  | PushReg : int -> stack_op
  | PopReg : int -> stack_op
  | ReadMem : int -> stack_op
  | WriteMem : int -> stack_op
  | Add | Sub | Mul | Nor | Nand | Shl | Shr | Sar | Div | Idiv
  | Dup | Dup2 | Rot | Swap
  | PushFlags | PopFlags
  | JmpRel : int -> stack_op
  | JccRel : int -> condition -> stack_op
  | KeyAdjust : int -> stack_op
  | Exit
  | CallExtern : int -> stack_op
  | ResolveSym : int -> stack_op
  | Setcc : condition -> stack_op
  | Cmov : condition -> int -> stack_op
  | Cmp | Test
  | AddImm : int -> stack_op
  | SubImm : int -> stack_op
  | AddImmImm : int -> int -> stack_op
  | SubImmImm : int -> int -> stack_op
  | SetRegImm : int -> int -> stack_op
  | AddRegImm : int -> int -> stack_op
  | KeyFeedback : int -> int -> stack_op

let push_weight (op:stack_op) : nat =
  match op with
  | PushImm _ -> 1
  | PushReg _ -> 1
  | PopReg _ -> 0
  | ReadMem _ -> 1
  | WriteMem _ -> 0
  | Add | Sub | Mul | Nor | Nand | Shl | Shr | Sar | Div | Idiv -> 1
  | Dup -> 2
  | Dup2 -> 4
  | Rot -> 3
  | Swap -> 2
  | PushFlags -> 1
  | PopFlags -> 0
  | JmpRel _ | JccRel _ _ | KeyAdjust _ | Exit -> 0
  | CallExtern _ -> 0
  | ResolveSym _ -> 1
  | Setcc _ -> 1
  | Cmov _ _ -> 0
  | Cmp | Test -> 0
  | AddImm _ | SubImm _ -> 1
  | AddImmImm _ _ | SubImmImm _ _ | AddRegImm _ _ -> 1
  | SetRegImm _ _ | KeyFeedback _ _ -> 0

let pop_weight (op:stack_op) : nat =
  match op with
  | PushImm _ -> 0
  | PushReg _ -> 0
  | PopReg _ -> 1
  | ReadMem _ -> 1
  | WriteMem _ -> 2
  | Add | Sub | Mul | Nor | Nand | Shl | Shr | Sar | Div | Idiv -> 2
  | Dup -> 1
  | Dup2 -> 2
  | Rot -> 3
  | Swap -> 2
  | PushFlags -> 0
  | PopFlags -> 1
  | JmpRel _ | JccRel _ _ | KeyAdjust _ | Exit -> 0
  | CallExtern _ -> 0
  | ResolveSym _ -> 0
  | Setcc _ -> 0
  | Cmov _ _ -> 1
  | Cmp | Test -> 2
  | AddImm _ | SubImm _ -> 1
  | AddImmImm _ _ | SubImmImm _ _ | AddRegImm _ _ -> 0
  | SetRegImm _ _ | KeyFeedback _ _ -> 0

let stack_delta (op:stack_op) : int =
  push_weight op - pop_weight op

(** Лемма: Дельта Dup2 строго равна +2 *)
val lemma_dup2_delta : unit -> Lemma (stack_delta Dup2 == 2)
let lemma_dup2_delta () = ()

(** Лемма: Дельта Rot строго равна 0 *)
val lemma_rot_delta : unit -> Lemma (stack_delta Rot == 0)
let lemma_rot_delta () = ()

let is_terminator (op:stack_op) : bool =
  match op with
  | JmpRel _ | JccRel _ _ | Exit -> true
  | _ -> false

(* ------------------------------------------------------------------ *)
(* 2. Суммарная дельта последовательности операций                     *)
(* ------------------------------------------------------------------ *)

let rec sum_delta (ops:list stack_op) : int =
  match ops with
  | [] -> 0
  | op :: rest -> stack_delta op + sum_delta rest

(** Лемма: Дельта конкатенации равна сумме дельт *)
val lemma_sum_delta_append : l1:list stack_op -> l2:list stack_op ->
  Lemma (sum_delta (l1 @ l2) == sum_delta l1 + sum_delta l2)
let rec lemma_sum_delta_append l1 l2 =
  match l1 with
  | [] -> ()
  | op :: rest -> lemma_sum_delta_append rest l2

let rec repeat_op (n:nat) (op:stack_op) : list stack_op =
  if n = 0 then []
  else op :: repeat_op (n - 1) op

(** Лемма: Дельта повторения операции равна n * delta(op) *)
val lemma_sum_delta_repeat : n:nat -> op:stack_op ->
  Lemma (sum_delta (repeat_op n op) == n * stack_delta op)
let rec lemma_sum_delta_repeat n op =
  if n = 0 then ()
  else lemma_sum_delta_repeat (n - 1) op

(* ------------------------------------------------------------------ *)
(* 3. Алгоритм разделения у первого терминатора и Repair               *)
(* ------------------------------------------------------------------ *)

let rec split_at_first_term (ops:list stack_op) : (list stack_op & list stack_op) =
  match ops with
  | [] -> ([], [])
  | op :: rest ->
    if is_terminator op then ([], op :: rest)
    else
      let (pre, suf) = split_at_first_term rest in
      (op :: pre, suf)

(** Лемма: Разделение сохраняет список в точности *)
val lemma_split_append : ops:list stack_op ->
  Lemma (let (pre, suf) = split_at_first_term ops in pre @ suf == ops)
let rec lemma_split_append ops =
  match ops with
  | [] -> ()
  | op :: rest ->
    if is_terminator op then ()
    else lemma_split_append rest

(** Восстановление блока *)
let repair_ops (ops:list stack_op) (dummy_reg:int) : list stack_op =
  let d = sum_delta ops in
  if d = 0 then ops
  else if d > 0 then
    let dummies = repeat_op d (PopReg dummy_reg) in
    let (pre, suf) = split_at_first_term ops in
    pre @ dummies @ suf
  else
    let pads = repeat_op (- d) (PushImm 0) in
    pads @ ops

(* ------------------------------------------------------------------ *)
(* 4. Главная теорема 1: Восстановленный блок строго сбалансирован     *)
(* ------------------------------------------------------------------ *)

val theorem_repair_balanced : ops:list stack_op -> dummy_reg:int ->
  Lemma (sum_delta (repair_ops ops dummy_reg) == 0)
let theorem_repair_balanced ops dummy_reg =
  let d = sum_delta ops in
  if d = 0 then ()
  else if d > 0 then begin
    let (pre, suf) = split_at_first_term ops in
    lemma_split_append ops;
    lemma_sum_delta_append pre suf;
    assert (sum_delta pre + sum_delta suf == d);
    let dummies = repeat_op d (PopReg dummy_reg) in
    lemma_sum_delta_repeat d (PopReg dummy_reg);
    assert (stack_delta (PopReg dummy_reg) == -1);
    assert (sum_delta dummies == -d);
    lemma_sum_delta_append pre (dummies @ suf);
    lemma_sum_delta_append dummies suf;
    assert (sum_delta (repair_ops ops dummy_reg) == 0)
  end
  else begin
    let pads = repeat_op (- d) (PushImm 0) in
    lemma_sum_delta_repeat (- d) (PushImm 0);
    assert (stack_delta (PushImm 0) == 1);
    assert (sum_delta pads == -d);
    lemma_sum_delta_append pads ops;
    assert (sum_delta (repair_ops ops dummy_reg) == 0)
  end

(* ------------------------------------------------------------------ *)
(* 5. Главная теорема 2: Инвариант путей CFG (Path Stack Invariance)   *)
(* ------------------------------------------------------------------ *)

let rec sum_path_delta (path:list (list stack_op)) : int =
  match path with
  | [] -> 0
  | blk :: rest -> sum_delta blk + sum_path_delta rest

val theorem_path_balance : path:list (list stack_op) ->
  Lemma (requires (forall (blk:list stack_op). mem blk path ==> sum_delta blk == 0))
        (ensures (sum_path_delta path == 0))
let rec theorem_path_balance path =
  match path with
  | [] -> ()
  | blk :: rest -> theorem_path_balance rest

(* ------------------------------------------------------------------ *)
(* 6. Модель динамического выполнения стека и Underflow-безопасность   *)
(* ------------------------------------------------------------------ *)

let step_depth (cur:nat) (op:stack_op) : option nat =
  if cur < pop_weight op then None
  else Some (cur - pop_weight op + push_weight op)

let rec eval_depth (cur:nat) (ops:list stack_op) : Tot (option nat) (decreases ops) =
  match ops with
  | [] -> Some cur
  | op :: rest ->
    match step_depth cur op with
    | None -> None
    | Some next_d -> eval_depth next_d rest

(** Теорема 3: Успешное выполнение точно сохраняет связь с sum_delta *)
val theorem_eval_depth_delta : cur:nat -> ops:list stack_op -> final_d:nat ->
  Lemma (requires (eval_depth cur ops == Some final_d))
        (ensures (final_d == cur + sum_delta ops))
        (decreases ops)
let rec theorem_eval_depth_delta cur ops final_d =
  match ops with
  | [] -> ()
  | op :: rest ->
    let Some next_d = step_depth cur op in
    theorem_eval_depth_delta next_d rest final_d

(* ------------------------------------------------------------------ *)
(* 7. Минимальная безопасная глубина (Underflow Freedom)               *)
(* ------------------------------------------------------------------ *)

let rec min_req (ops:list stack_op) : nat =
  match ops with
  | [] -> 0
  | op :: rest ->
    let r = min_req rest in
    let pw = pop_weight op in
    let uw = push_weight op in
    if uw >= r then pw
    else pw + (r - uw)

(** Теорема 4: При начальной глубине >= min_req ops стек никогда не опустошается *)
val theorem_min_req_safe : cur:nat -> ops:list stack_op ->
  Lemma (requires (cur >= min_req ops))
        (ensures (Some? (eval_depth cur ops)))
        (decreases ops)
let rec theorem_min_req_safe cur ops =
  match ops with
  | [] -> ()
  | op :: rest ->
    let pw = pop_weight op in
    let uw = push_weight op in
    let r = min_req rest in
    assert (cur >= pw);
    let next_d = cur - pw + uw in
    assert (next_d >= r);
    theorem_min_req_safe next_d rest

(** Теорема 5: Паддинг в виде (min_req ops) PushImm гарантирует отсутствие underflow *)
val theorem_padded_never_underflows : ops:list stack_op ->
  Lemma (Some? (eval_depth 0 (repeat_op (min_req ops) (PushImm 0) @ ops)))
let theorem_padded_never_underflows ops =
  let k = min_req ops in
  let pads = repeat_op k (PushImm 0) in
  (* Доказываем, что k PushImm от 0 дают в точности глубину k *)
  let rec lemma_pads_reach (n:nat) (cur:nat) :
    Lemma (ensures (eval_depth cur (repeat_op n (PushImm 0)) == Some (cur + n)))
          (decreases n) =
    if n = 0 then ()
    else lemma_pads_reach (n - 1) (cur + 1)
  in
  lemma_pads_reach k 0;
  (* Доказываем композицию eval_depth *)
  let rec lemma_eval_depth_append (c:nat) (l1:list stack_op) (l2:list stack_op) :
    Lemma (requires (Some? (eval_depth c l1)))
          (ensures (eval_depth c (l1 @ l2) == eval_depth (Some?.v (eval_depth c l1)) l2))
          (decreases l1) =
    match l1 with
    | [] -> ()
    | op :: rest ->
      let Some next_c = step_depth c op in
      lemma_eval_depth_append next_c rest l2
  in
  lemma_eval_depth_append 0 pads ops;
  theorem_min_req_safe k ops
