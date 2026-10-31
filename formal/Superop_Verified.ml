open Prims
type u64 = Obj.t FStar_UInt.uint_t
let add64 (a : u64) (b : u64) : u64= FStar_UInt.add_mod (Prims.of_int 64) a b
let sub64 (a : u64) (b : u64) : u64= FStar_UInt.sub_mod (Prims.of_int 64) a b
type reg_id = Prims.nat
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
let compute_flags_add (a : u64) (b : u64) : flag_state=
  let res = FStar_UInt.add_mod (Prims.of_int 64) a b in
  let cf = res < a in
  let zf = res = Prims.int_zero in
  let sf = FStar_UInt.nth (Prims.of_int 64) res (Prims.of_int 63) in
  let a_sign = FStar_UInt.nth (Prims.of_int 64) a (Prims.of_int 63) in
  let b_sign = FStar_UInt.nth (Prims.of_int 64) b (Prims.of_int 63) in
  let res_sign = FStar_UInt.nth (Prims.of_int 64) res (Prims.of_int 63) in
  let of_flag = (a_sign = b_sign) && (res_sign <> a_sign) in
  { cf; zf; sf; of_flag }
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
type vm_state =
  {
  vstack: u64 Prims.list ;
  vregs: reg_id -> u64 ;
  vflags: flag_state ;
  fault: Prims.bool }
let __proj__Mkvm_state__item__vstack (projectee : vm_state) : u64 Prims.list=
  match projectee with | { vstack; vregs; vflags; fault;_} -> vstack
let __proj__Mkvm_state__item__vregs (projectee : vm_state) : reg_id -> u64=
  match projectee with | { vstack; vregs; vflags; fault;_} -> vregs
let __proj__Mkvm_state__item__vflags (projectee : vm_state) : flag_state=
  match projectee with | { vstack; vregs; vflags; fault;_} -> vflags
let __proj__Mkvm_state__item__fault (projectee : vm_state) : Prims.bool=
  match projectee with | { vstack; vregs; vflags; fault;_} -> fault
type stack_op =
  | PushImm of u64 
  | PushReg of reg_id 
  | PopReg of reg_id 
  | Add 
  | Sub 
  | AddImmImm of u64 * u64 
  | SubImmImm of u64 * u64 
  | AddRegImm of reg_id * u64 
  | SetRegImm of reg_id * u64 
  | AddImm of u64 
  | SubImm of u64 
let uu___is_PushImm (projectee : stack_op) : Prims.bool=
  match projectee with | PushImm v -> true | uu___ -> false
let __proj__PushImm__item__v (projectee : stack_op) : u64=
  match projectee with | PushImm v -> v
let uu___is_PushReg (projectee : stack_op) : Prims.bool=
  match projectee with | PushReg r -> true | uu___ -> false
let __proj__PushReg__item__r (projectee : stack_op) : reg_id=
  match projectee with | PushReg r -> r
let uu___is_PopReg (projectee : stack_op) : Prims.bool=
  match projectee with | PopReg r -> true | uu___ -> false
let __proj__PopReg__item__r (projectee : stack_op) : reg_id=
  match projectee with | PopReg r -> r
let uu___is_Add (projectee : stack_op) : Prims.bool=
  match projectee with | Add -> true | uu___ -> false
let uu___is_Sub (projectee : stack_op) : Prims.bool=
  match projectee with | Sub -> true | uu___ -> false
let uu___is_AddImmImm (projectee : stack_op) : Prims.bool=
  match projectee with | AddImmImm (a, b) -> true | uu___ -> false
let __proj__AddImmImm__item__a (projectee : stack_op) : u64=
  match projectee with | AddImmImm (a, b) -> a
let __proj__AddImmImm__item__b (projectee : stack_op) : u64=
  match projectee with | AddImmImm (a, b) -> b
let uu___is_SubImmImm (projectee : stack_op) : Prims.bool=
  match projectee with | SubImmImm (a, b) -> true | uu___ -> false
let __proj__SubImmImm__item__a (projectee : stack_op) : u64=
  match projectee with | SubImmImm (a, b) -> a
let __proj__SubImmImm__item__b (projectee : stack_op) : u64=
  match projectee with | SubImmImm (a, b) -> b
let uu___is_AddRegImm (projectee : stack_op) : Prims.bool=
  match projectee with | AddRegImm (r, c) -> true | uu___ -> false
let __proj__AddRegImm__item__r (projectee : stack_op) : reg_id=
  match projectee with | AddRegImm (r, c) -> r
let __proj__AddRegImm__item__c (projectee : stack_op) : u64=
  match projectee with | AddRegImm (r, c) -> c
let uu___is_SetRegImm (projectee : stack_op) : Prims.bool=
  match projectee with | SetRegImm (r, c) -> true | uu___ -> false
let __proj__SetRegImm__item__r (projectee : stack_op) : reg_id=
  match projectee with | SetRegImm (r, c) -> r
let __proj__SetRegImm__item__c (projectee : stack_op) : u64=
  match projectee with | SetRegImm (r, c) -> c
let uu___is_AddImm (projectee : stack_op) : Prims.bool=
  match projectee with | AddImm c -> true | uu___ -> false
let __proj__AddImm__item__c (projectee : stack_op) : u64=
  match projectee with | AddImm c -> c
let uu___is_SubImm (projectee : stack_op) : Prims.bool=
  match projectee with | SubImm c -> true | uu___ -> false
let __proj__SubImm__item__c (projectee : stack_op) : u64=
  match projectee with | SubImm c -> c
let op_delta (op : stack_op) : Prims.int=
  match op with
  | PushImm uu___ -> Prims.int_one
  | PushReg uu___ -> Prims.int_one
  | PopReg uu___ -> Prims.of_int (-1)
  | Add -> Prims.of_int (-1)
  | Sub -> Prims.of_int (-1)
  | AddImmImm (uu___, uu___1) -> Prims.int_one
  | SubImmImm (uu___, uu___1) -> Prims.int_one
  | AddRegImm (uu___, uu___1) -> Prims.int_one
  | SetRegImm (uu___, uu___1) -> Prims.int_zero
  | AddImm uu___ -> Prims.int_zero
  | SubImm uu___ -> Prims.int_zero
let rec seq_delta (ops : stack_op Prims.list) : Prims.int=
  match ops with
  | [] -> Prims.int_zero
  | op::rest -> (op_delta op) + (seq_delta rest)
let step_eval (st : vm_state) (op : stack_op) : vm_state=
  if st.fault
  then st
  else
    (match op with
     | PushImm v ->
         {
           vstack = (v :: (st.vstack));
           vregs = (st.vregs);
           vflags = (st.vflags);
           fault = (st.fault)
         }
     | PushReg r ->
         {
           vstack = ((st.vregs r) :: (st.vstack));
           vregs = (st.vregs);
           vflags = (st.vflags);
           fault = (st.fault)
         }
     | PopReg r ->
         (match st.vstack with
          | v::rest ->
              let new_regs r' = if r' = r then v else st.vregs r' in
              {
                vstack = rest;
                vregs = new_regs;
                vflags = (st.vflags);
                fault = (st.fault)
              }
          | [] ->
              {
                vstack = (st.vstack);
                vregs = (st.vregs);
                vflags = (st.vflags);
                fault = true
              })
     | Add ->
         (match st.vstack with
          | op2::op1::rest ->
              let res = add64 op1 op2 in
              let fl = compute_flags_add op1 op2 in
              {
                vstack = (res :: rest);
                vregs = (st.vregs);
                vflags = fl;
                fault = (st.fault)
              }
          | uu___ ->
              {
                vstack = (st.vstack);
                vregs = (st.vregs);
                vflags = (st.vflags);
                fault = true
              })
     | Sub ->
         (match st.vstack with
          | op2::op1::rest ->
              let res = sub64 op1 op2 in
              let fl = compute_flags_sub op1 op2 in
              {
                vstack = (res :: rest);
                vregs = (st.vregs);
                vflags = fl;
                fault = (st.fault)
              }
          | uu___ ->
              {
                vstack = (st.vstack);
                vregs = (st.vregs);
                vflags = (st.vflags);
                fault = true
              })
     | AddImmImm (a, b) ->
         let res = add64 a b in
         let fl = compute_flags_add a b in
         {
           vstack = (res :: (st.vstack));
           vregs = (st.vregs);
           vflags = fl;
           fault = (st.fault)
         }
     | SubImmImm (a, b) ->
         let res = sub64 a b in
         let fl = compute_flags_sub a b in
         {
           vstack = (res :: (st.vstack));
           vregs = (st.vregs);
           vflags = fl;
           fault = (st.fault)
         }
     | AddRegImm (r, c) ->
         let op1 = st.vregs r in
         let res = add64 op1 c in
         let fl = compute_flags_add op1 c in
         {
           vstack = (res :: (st.vstack));
           vregs = (st.vregs);
           vflags = fl;
           fault = (st.fault)
         }
     | SetRegImm (r, c) ->
         let new_regs r' = if r' = r then c else st.vregs r' in
         {
           vstack = (st.vstack);
           vregs = new_regs;
           vflags = (st.vflags);
           fault = (st.fault)
         }
     | AddImm c ->
         (match st.vstack with
          | op1::rest ->
              let res = add64 op1 c in
              let fl = compute_flags_add op1 c in
              {
                vstack = (res :: rest);
                vregs = (st.vregs);
                vflags = fl;
                fault = (st.fault)
              }
          | [] ->
              {
                vstack = (st.vstack);
                vregs = (st.vregs);
                vflags = (st.vflags);
                fault = true
              })
     | SubImm c ->
         (match st.vstack with
          | op1::rest ->
              let res = sub64 op1 c in
              let fl = compute_flags_sub op1 c in
              {
                vstack = (res :: rest);
                vregs = (st.vregs);
                vflags = fl;
                fault = (st.fault)
              }
          | [] ->
              {
                vstack = (st.vstack);
                vregs = (st.vregs);
                vflags = (st.vflags);
                fault = true
              }))
let rec eval_trace (st : vm_state) (ops : stack_op Prims.list) : vm_state=
  match ops with | [] -> st | op::rest -> eval_trace (step_eval st op) rest
