open Prims
type condition =
  | Cond_O 
  | Cond_NO 
  | Cond_B 
  | Cond_AE 
  | Cond_E 
  | Cond_NE 
  | Cond_BE 
  | Cond_A 
  | Cond_S 
  | Cond_NS 
  | Cond_P 
  | Cond_NP 
  | Cond_L 
  | Cond_GE 
  | Cond_LE 
  | Cond_G 
let uu___is_Cond_O (projectee : condition) : Prims.bool=
  match projectee with | Cond_O -> true | uu___ -> false
let uu___is_Cond_NO (projectee : condition) : Prims.bool=
  match projectee with | Cond_NO -> true | uu___ -> false
let uu___is_Cond_B (projectee : condition) : Prims.bool=
  match projectee with | Cond_B -> true | uu___ -> false
let uu___is_Cond_AE (projectee : condition) : Prims.bool=
  match projectee with | Cond_AE -> true | uu___ -> false
let uu___is_Cond_E (projectee : condition) : Prims.bool=
  match projectee with | Cond_E -> true | uu___ -> false
let uu___is_Cond_NE (projectee : condition) : Prims.bool=
  match projectee with | Cond_NE -> true | uu___ -> false
let uu___is_Cond_BE (projectee : condition) : Prims.bool=
  match projectee with | Cond_BE -> true | uu___ -> false
let uu___is_Cond_A (projectee : condition) : Prims.bool=
  match projectee with | Cond_A -> true | uu___ -> false
let uu___is_Cond_S (projectee : condition) : Prims.bool=
  match projectee with | Cond_S -> true | uu___ -> false
let uu___is_Cond_NS (projectee : condition) : Prims.bool=
  match projectee with | Cond_NS -> true | uu___ -> false
let uu___is_Cond_P (projectee : condition) : Prims.bool=
  match projectee with | Cond_P -> true | uu___ -> false
let uu___is_Cond_NP (projectee : condition) : Prims.bool=
  match projectee with | Cond_NP -> true | uu___ -> false
let uu___is_Cond_L (projectee : condition) : Prims.bool=
  match projectee with | Cond_L -> true | uu___ -> false
let uu___is_Cond_GE (projectee : condition) : Prims.bool=
  match projectee with | Cond_GE -> true | uu___ -> false
let uu___is_Cond_LE (projectee : condition) : Prims.bool=
  match projectee with | Cond_LE -> true | uu___ -> false
let uu___is_Cond_G (projectee : condition) : Prims.bool=
  match projectee with | Cond_G -> true | uu___ -> false
type stack_op =
  | PushImm of Prims.int 
  | PushReg of Prims.int 
  | PopReg of Prims.int 
  | ReadMem of Prims.int 
  | WriteMem of Prims.int 
  | Add 
  | Sub 
  | Mul 
  | Nor 
  | Nand 
  | Shl 
  | Shr 
  | Sar 
  | Div 
  | Idiv 
  | Dup 
  | Dup2
  | Rot
  | Swap 
  | PushFlags 
  | PopFlags 
  | JmpRel of Prims.int 
  | JccRel of Prims.int * condition 
  | KeyAdjust of Prims.int 
  | Exit 
  | CallExtern of Prims.int 
  | ResolveSym of Prims.int 
  | Setcc of condition 
  | Cmov of condition * Prims.int 
  | Cmp 
  | Test 
  | AddImm of Prims.int 
  | SubImm of Prims.int 
  | AddImmImm of Prims.int * Prims.int 
  | SubImmImm of Prims.int * Prims.int 
  | SetRegImm of Prims.int * Prims.int 
  | AddRegImm of Prims.int * Prims.int 
  | KeyFeedback of Prims.int * Prims.int 
let uu___is_PushImm (projectee : stack_op) : Prims.bool=
  match projectee with | PushImm _0 -> true | uu___ -> false
let __proj__PushImm__item___0 (projectee : stack_op) : Prims.int=
  match projectee with | PushImm _0 -> _0
let uu___is_PushReg (projectee : stack_op) : Prims.bool=
  match projectee with | PushReg _0 -> true | uu___ -> false
let __proj__PushReg__item___0 (projectee : stack_op) : Prims.int=
  match projectee with | PushReg _0 -> _0
let uu___is_PopReg (projectee : stack_op) : Prims.bool=
  match projectee with | PopReg _0 -> true | uu___ -> false
let __proj__PopReg__item___0 (projectee : stack_op) : Prims.int=
  match projectee with | PopReg _0 -> _0
let uu___is_ReadMem (projectee : stack_op) : Prims.bool=
  match projectee with | ReadMem _0 -> true | uu___ -> false
let __proj__ReadMem__item___0 (projectee : stack_op) : Prims.int=
  match projectee with | ReadMem _0 -> _0
let uu___is_WriteMem (projectee : stack_op) : Prims.bool=
  match projectee with | WriteMem _0 -> true | uu___ -> false
let __proj__WriteMem__item___0 (projectee : stack_op) : Prims.int=
  match projectee with | WriteMem _0 -> _0
let uu___is_Add (projectee : stack_op) : Prims.bool=
  match projectee with | Add -> true | uu___ -> false
let uu___is_Sub (projectee : stack_op) : Prims.bool=
  match projectee with | Sub -> true | uu___ -> false
let uu___is_Mul (projectee : stack_op) : Prims.bool=
  match projectee with | Mul -> true | uu___ -> false
let uu___is_Nor (projectee : stack_op) : Prims.bool=
  match projectee with | Nor -> true | uu___ -> false
let uu___is_Nand (projectee : stack_op) : Prims.bool=
  match projectee with | Nand -> true | uu___ -> false
let uu___is_Shl (projectee : stack_op) : Prims.bool=
  match projectee with | Shl -> true | uu___ -> false
let uu___is_Shr (projectee : stack_op) : Prims.bool=
  match projectee with | Shr -> true | uu___ -> false
let uu___is_Sar (projectee : stack_op) : Prims.bool=
  match projectee with | Sar -> true | uu___ -> false
let uu___is_Div (projectee : stack_op) : Prims.bool=
  match projectee with | Div -> true | uu___ -> false
let uu___is_Idiv (projectee : stack_op) : Prims.bool=
  match projectee with | Idiv -> true | uu___ -> false
let uu___is_Dup (projectee : stack_op) : Prims.bool=
  match projectee with | Dup -> true | uu___ -> false
let uu___is_Swap (projectee : stack_op) : Prims.bool=
  match projectee with | Swap -> true | uu___ -> false
let uu___is_PushFlags (projectee : stack_op) : Prims.bool=
  match projectee with | PushFlags -> true | uu___ -> false
let uu___is_PopFlags (projectee : stack_op) : Prims.bool=
  match projectee with | PopFlags -> true | uu___ -> false
let uu___is_JmpRel (projectee : stack_op) : Prims.bool=
  match projectee with | JmpRel _0 -> true | uu___ -> false
let __proj__JmpRel__item___0 (projectee : stack_op) : Prims.int=
  match projectee with | JmpRel _0 -> _0
let uu___is_JccRel (projectee : stack_op) : Prims.bool=
  match projectee with | JccRel (_0, _1) -> true | uu___ -> false
let __proj__JccRel__item___0 (projectee : stack_op) : Prims.int=
  match projectee with | JccRel (_0, _1) -> _0
let __proj__JccRel__item___1 (projectee : stack_op) : condition=
  match projectee with | JccRel (_0, _1) -> _1
let uu___is_KeyAdjust (projectee : stack_op) : Prims.bool=
  match projectee with | KeyAdjust _0 -> true | uu___ -> false
let __proj__KeyAdjust__item___0 (projectee : stack_op) : Prims.int=
  match projectee with | KeyAdjust _0 -> _0
let uu___is_Exit (projectee : stack_op) : Prims.bool=
  match projectee with | Exit -> true | uu___ -> false
let uu___is_CallExtern (projectee : stack_op) : Prims.bool=
  match projectee with | CallExtern _0 -> true | uu___ -> false
let __proj__CallExtern__item___0 (projectee : stack_op) : Prims.int=
  match projectee with | CallExtern _0 -> _0
let uu___is_ResolveSym (projectee : stack_op) : Prims.bool=
  match projectee with | ResolveSym _0 -> true | uu___ -> false
let __proj__ResolveSym__item___0 (projectee : stack_op) : Prims.int=
  match projectee with | ResolveSym _0 -> _0
let uu___is_Setcc (projectee : stack_op) : Prims.bool=
  match projectee with | Setcc _0 -> true | uu___ -> false
let __proj__Setcc__item___0 (projectee : stack_op) : condition=
  match projectee with | Setcc _0 -> _0
let uu___is_Cmov (projectee : stack_op) : Prims.bool=
  match projectee with | Cmov (_0, _1) -> true | uu___ -> false
let __proj__Cmov__item___0 (projectee : stack_op) : condition=
  match projectee with | Cmov (_0, _1) -> _0
let __proj__Cmov__item___1 (projectee : stack_op) : Prims.int=
  match projectee with | Cmov (_0, _1) -> _1
let uu___is_Cmp (projectee : stack_op) : Prims.bool=
  match projectee with | Cmp -> true | uu___ -> false
let uu___is_Test (projectee : stack_op) : Prims.bool=
  match projectee with | Test -> true | uu___ -> false
let uu___is_AddImm (projectee : stack_op) : Prims.bool=
  match projectee with | AddImm _0 -> true | uu___ -> false
let __proj__AddImm__item___0 (projectee : stack_op) : Prims.int=
  match projectee with | AddImm _0 -> _0
let uu___is_SubImm (projectee : stack_op) : Prims.bool=
  match projectee with | SubImm _0 -> true | uu___ -> false
let __proj__SubImm__item___0 (projectee : stack_op) : Prims.int=
  match projectee with | SubImm _0 -> _0
let uu___is_AddImmImm (projectee : stack_op) : Prims.bool=
  match projectee with | AddImmImm (_0, _1) -> true | uu___ -> false
let __proj__AddImmImm__item___0 (projectee : stack_op) : Prims.int=
  match projectee with | AddImmImm (_0, _1) -> _0
let __proj__AddImmImm__item___1 (projectee : stack_op) : Prims.int=
  match projectee with | AddImmImm (_0, _1) -> _1
let uu___is_SubImmImm (projectee : stack_op) : Prims.bool=
  match projectee with | SubImmImm (_0, _1) -> true | uu___ -> false
let __proj__SubImmImm__item___0 (projectee : stack_op) : Prims.int=
  match projectee with | SubImmImm (_0, _1) -> _0
let __proj__SubImmImm__item___1 (projectee : stack_op) : Prims.int=
  match projectee with | SubImmImm (_0, _1) -> _1
let uu___is_SetRegImm (projectee : stack_op) : Prims.bool=
  match projectee with | SetRegImm (_0, _1) -> true | uu___ -> false
let __proj__SetRegImm__item___0 (projectee : stack_op) : Prims.int=
  match projectee with | SetRegImm (_0, _1) -> _0
let __proj__SetRegImm__item___1 (projectee : stack_op) : Prims.int=
  match projectee with | SetRegImm (_0, _1) -> _1
let uu___is_AddRegImm (projectee : stack_op) : Prims.bool=
  match projectee with | AddRegImm (_0, _1) -> true | uu___ -> false
let __proj__AddRegImm__item___0 (projectee : stack_op) : Prims.int=
  match projectee with | AddRegImm (_0, _1) -> _0
let __proj__AddRegImm__item___1 (projectee : stack_op) : Prims.int=
  match projectee with | AddRegImm (_0, _1) -> _1
let uu___is_KeyFeedback (projectee : stack_op) : Prims.bool=
  match projectee with | KeyFeedback (_0, _1) -> true | uu___ -> false
let __proj__KeyFeedback__item___0 (projectee : stack_op) : Prims.int=
  match projectee with | KeyFeedback (_0, _1) -> _0
let __proj__KeyFeedback__item___1 (projectee : stack_op) : Prims.int=
  match projectee with | KeyFeedback (_0, _1) -> _1
let push_weight (op : stack_op) : Prims.nat=
  match op with
  | PushImm uu___ -> Prims.int_one
  | PushReg uu___ -> Prims.int_one
  | PopReg uu___ -> Prims.int_zero
  | ReadMem uu___ -> Prims.int_one
  | WriteMem uu___ -> Prims.int_zero
  | Add -> Prims.int_one
  | Sub -> Prims.int_one
  | Mul -> Prims.int_one
  | Nor -> Prims.int_one
  | Nand -> Prims.int_one
  | Shl -> Prims.int_one
  | Shr -> Prims.int_one
  | Sar -> Prims.int_one
  | Div -> Prims.int_one
  | Idiv -> Prims.int_one
  | Dup -> Prims.of_int 2
  | Dup2 -> Prims.of_int 4
  | Rot -> Prims.of_int 3
  | Swap -> Prims.of_int 2
  | PushFlags -> Prims.int_one
  | PopFlags -> Prims.int_zero
  | JmpRel uu___ -> Prims.int_zero
  | JccRel (uu___, uu___1) -> Prims.int_zero
  | KeyAdjust uu___ -> Prims.int_zero
  | Exit -> Prims.int_zero
  | CallExtern uu___ -> Prims.int_zero
  | ResolveSym uu___ -> Prims.int_one
  | Setcc uu___ -> Prims.int_one
  | Cmov (uu___, uu___1) -> Prims.int_zero
  | Cmp -> Prims.int_zero
  | Test -> Prims.int_zero
  | AddImm uu___ -> Prims.int_one
  | SubImm uu___ -> Prims.int_one
  | AddImmImm (uu___, uu___1) -> Prims.int_one
  | SubImmImm (uu___, uu___1) -> Prims.int_one
  | AddRegImm (uu___, uu___1) -> Prims.int_one
  | SetRegImm (uu___, uu___1) -> Prims.int_zero
  | KeyFeedback (uu___, uu___1) -> Prims.int_zero
let pop_weight (op : stack_op) : Prims.nat=
  match op with
  | PushImm uu___ -> Prims.int_zero
  | PushReg uu___ -> Prims.int_zero
  | PopReg uu___ -> Prims.int_one
  | ReadMem uu___ -> Prims.int_one
  | WriteMem uu___ -> Prims.of_int 2
  | Add -> Prims.of_int 2
  | Sub -> Prims.of_int 2
  | Mul -> Prims.of_int 2
  | Nor -> Prims.of_int 2
  | Nand -> Prims.of_int 2
  | Shl -> Prims.of_int 2
  | Shr -> Prims.of_int 2
  | Sar -> Prims.of_int 2
  | Div -> Prims.of_int 2
  | Idiv -> Prims.of_int 2
  | Dup -> Prims.int_one
  | Dup2 -> Prims.of_int 2
  | Rot -> Prims.of_int 3
  | Swap -> Prims.of_int 2
  | PushFlags -> Prims.int_zero
  | PopFlags -> Prims.int_one
  | JmpRel uu___ -> Prims.int_zero
  | JccRel (uu___, uu___1) -> Prims.int_zero
  | KeyAdjust uu___ -> Prims.int_zero
  | Exit -> Prims.int_zero
  | CallExtern uu___ -> Prims.int_zero
  | ResolveSym uu___ -> Prims.int_zero
  | Setcc uu___ -> Prims.int_zero
  | Cmov (uu___, uu___1) -> Prims.int_one
  | Cmp -> Prims.of_int 2
  | Test -> Prims.of_int 2
  | AddImm uu___ -> Prims.int_one
  | SubImm uu___ -> Prims.int_one
  | AddImmImm (uu___, uu___1) -> Prims.int_zero
  | SubImmImm (uu___, uu___1) -> Prims.int_zero
  | AddRegImm (uu___, uu___1) -> Prims.int_zero
  | SetRegImm (uu___, uu___1) -> Prims.int_zero
  | KeyFeedback (uu___, uu___1) -> Prims.int_zero
let stack_delta (op : stack_op) : Prims.int=
  (push_weight op) - (pop_weight op)
let is_terminator (op : stack_op) : Prims.bool=
  match op with
  | JmpRel uu___ -> true
  | JccRel (uu___, uu___1) -> true
  | Exit -> true
  | uu___ -> false
let rec sum_delta (ops : stack_op Prims.list) : Prims.int=
  match ops with
  | [] -> Prims.int_zero
  | op::rest -> (stack_delta op) + (sum_delta rest)
let rec repeat_op (n : Prims.nat) (op : stack_op) : stack_op Prims.list=
  if n = Prims.int_zero then [] else op :: (repeat_op (n - Prims.int_one) op)
let rec split_at_first_term (ops : stack_op Prims.list) :
  (stack_op Prims.list * stack_op Prims.list)=
  match ops with
  | [] -> ([], [])
  | op::rest ->
      if is_terminator op
      then ([], (op :: rest))
      else
        (let uu___ = split_at_first_term rest in
         match uu___ with | (pre, suf) -> ((op :: pre), suf))
let repair_ops (ops : stack_op Prims.list) (dummy_reg : Prims.int) :
  stack_op Prims.list=
  let d = sum_delta ops in
  if d = Prims.int_zero
  then ops
  else
    if d > Prims.int_zero
    then
      (let dummies = repeat_op d (PopReg dummy_reg) in
       let uu___ = split_at_first_term ops in
       match uu___ with
       | (pre, suf) ->
           FStar_List_Tot_Base.op_At pre
             (FStar_List_Tot_Base.op_At dummies suf))
    else
      (let pads = repeat_op (- d) (PushImm Prims.int_zero) in
       FStar_List_Tot_Base.op_At pads ops)
let rec sum_path_delta (path : stack_op Prims.list Prims.list) : Prims.int=
  match path with
  | [] -> Prims.int_zero
  | blk::rest -> (sum_delta blk) + (sum_path_delta rest)
let step_depth (cur : Prims.nat) (op : stack_op) :
  Prims.nat FStar_Pervasives_Native.option=
  if cur < (pop_weight op)
  then FStar_Pervasives_Native.None
  else
    FStar_Pervasives_Native.Some ((cur - (pop_weight op)) + (push_weight op))
let rec eval_depth (cur : Prims.nat) (ops : stack_op Prims.list) :
  Prims.nat FStar_Pervasives_Native.option=
  match ops with
  | [] -> FStar_Pervasives_Native.Some cur
  | op::rest ->
      (match step_depth cur op with
       | FStar_Pervasives_Native.None -> FStar_Pervasives_Native.None
       | FStar_Pervasives_Native.Some next_d -> eval_depth next_d rest)
let rec min_req (ops : stack_op Prims.list) : Prims.nat=
  match ops with
  | [] -> Prims.int_zero
  | op::rest ->
      let r = min_req rest in
      let pw = pop_weight op in
      let uw = push_weight op in if uw >= r then pw else pw + (r - uw)
