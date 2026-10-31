open Prims
type u64 = Obj.t FStar_UInt.uint_t
let and64 (a : u64) (b : u64) : u64= FStar_UInt.logand (Prims.of_int 64) a b
let add64 (a : u64) (b : u64) : u64= FStar_UInt.add_mod (Prims.of_int 64) a b
let opaque_parity_predicate (x : u64) : u64=
  and64 (and64 x (add64 x Prims.int_one)) Prims.int_one
type block_id = Prims.nat
type state_key = u64
type cff_entry = {
  state: state_key ;
  target: block_id }
let __proj__Mkcff_entry__item__state (projectee : cff_entry) : state_key=
  match projectee with | { state; target;_} -> state
let __proj__Mkcff_entry__item__target (projectee : cff_entry) : block_id=
  match projectee with | { state; target;_} -> target
let rec dispatch (ladder : cff_entry Prims.list) (cur : state_key) :
  block_id FStar_Pervasives_Native.option=
  match ladder with
  | [] -> FStar_Pervasives_Native.None
  | entry::rest ->
      if entry.state = cur
      then FStar_Pervasives_Native.Some (entry.target)
      else dispatch rest cur
let state_neq (s : state_key) (e : cff_entry) : Prims.bool= e.state <> s
let rec distinct_states (ladder : cff_entry Prims.list) : Prims.bool=
  match ladder with
  | [] -> true
  | entry::rest ->
      (FStar_List_Tot_Base.for_all (state_neq entry.state) rest) &&
        (distinct_states rest)
type cfg_transition = {
  src: block_id ;
  dst: block_id }
let __proj__Mkcfg_transition__item__src (projectee : cfg_transition) :
  block_id= match projectee with | { src; dst;_} -> src
let __proj__Mkcfg_transition__item__dst (projectee : cfg_transition) :
  block_id= match projectee with | { src; dst;_} -> dst
let direct_step (edges : cfg_transition Prims.list) (cur : block_id) :
  block_id FStar_Pervasives_Native.option=
  match FStar_List_Tot_Base.find (fun e -> e.src = cur) edges with
  | FStar_Pervasives_Native.Some e -> FStar_Pervasives_Native.Some (e.dst)
  | FStar_Pervasives_Native.None -> FStar_Pervasives_Native.None
let cff_step (edges : cfg_transition Prims.list)
  (ladder : cff_entry Prims.list)
  (block_to_state : block_id -> state_key FStar_Pervasives_Native.option)
  (cur : block_id) : block_id FStar_Pervasives_Native.option=
  match direct_step edges cur with
  | FStar_Pervasives_Native.None -> FStar_Pervasives_Native.None
  | FStar_Pervasives_Native.Some next_b ->
      (match block_to_state next_b with
       | FStar_Pervasives_Native.None -> FStar_Pervasives_Native.None
       | FStar_Pervasives_Native.Some next_state ->
           dispatch ladder next_state)
