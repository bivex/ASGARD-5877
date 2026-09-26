open Vm_ir
open Register
open Ir
open Stack_ir

let lower_mem_addr ctx (m : mem_ref) =
  let base_ops = match m.base with
    | None -> [PushImm 0L]
    | Some reg -> [PushReg (Context_allocator.slot_of_reg ctx reg)]
  in
  let index_ops = match m.index with
    | None -> base_ops
    | Some (reg, scale) ->
        base_ops @
        [PushReg (Context_allocator.slot_of_reg ctx reg)] @
        (if scale = 1 then [] else [PushImm (Int64.of_int scale); Mul]) @
        [Add]
  in
  if m.disp = 0L then index_ops
  else index_ops @ [PushImm m.disp; Add]

let lower_operand ctx = function
  | Imm v -> [PushImm v]
  | Reg r -> [PushReg (Context_allocator.slot_of_reg ctx r)]
  | Mem m ->
      let addr_ops = lower_mem_addr ctx m in
      addr_ops @ [ReadMem (width_to_bytes m.width)]

let store_to_operand ctx opnd =
  match opnd with
  | Reg r -> [PopReg (Context_allocator.slot_of_reg ctx r)]
  | Mem m ->
      let scratch_val = Context_allocator.alloc_scratch ctx in
      let addr_ops = lower_mem_addr ctx m in
      [PopReg scratch_val] @
      addr_ops @
      [PushReg scratch_val; WriteMem (width_to_bytes m.width)]
  | Imm _ ->
      let dummy = Context_allocator.alloc_scratch ctx in
      [PopReg dummy]

let resolve_target = function
  | BlockId id -> id
  | TargetImm imm -> Int64.to_int imm
  | Label s ->
      (match int_of_string_opt s with
       | Some id -> id
       | None -> Hashtbl.hash s land 0xFFFF)

let lower_instr ctx = function
  | Nop -> []
  | Vm_enter -> []
  | Vm_exit | Ret -> [Exit]
  | Mov { dst; src } ->
      let src_ops = lower_operand ctx src in
      let dst_ops = store_to_operand ctx dst in
      src_ops @ dst_ops
  | Lea { dst; addr } ->
      let addr_ops = lower_mem_addr ctx addr in
      addr_ops @ [PopReg (Context_allocator.slot_of_reg ctx dst)]
  | Push src ->
      let src_ops = lower_operand ctx src in
      let sp_slot = Context_allocator.slot_of_reg ctx Register.rsp in
      (* RSP = RSP - 8; [RSP] = src *)
      let scratch_val = Context_allocator.alloc_scratch ctx in
      src_ops @
      [PopReg scratch_val;
       PushReg sp_slot; PushImm 8L; Sub; Dup; PopReg sp_slot;
       PushReg scratch_val; WriteMem 8]
  | Pop dst ->
      let sp_slot = Context_allocator.slot_of_reg ctx Register.rsp in
      (* val = [RSP]; RSP = RSP + 8; dst = val *)
      let scratch_val = Context_allocator.alloc_scratch ctx in
      [PushReg sp_slot; ReadMem 8; PopReg scratch_val;
       PushReg sp_slot; PushImm 8L; Add; PopReg sp_slot;
       PushReg scratch_val] @
      store_to_operand ctx dst
  | Alu { op; dst; src1; src2; _ } ->
      let src1_ops = lower_operand ctx src1 in
      let src2_ops = lower_operand ctx src2 in
      let alu_ops = match op with
        | Add | Adc -> [Add]
        | Sub | Sbb -> [Sub]
        | Mul | Imul -> [Mul]
        | Shl -> [Shl]
        | Shr | Sar -> [Shr]
        | And -> Stack_logic_pass.expand_and_nor
        | Or -> Stack_logic_pass.expand_or_nor
        | Xor ->
            let s1 = Context_allocator.alloc_scratch ctx in
            let s2 = Context_allocator.alloc_scratch ctx in
            Stack_logic_pass.expand_xor_nor s1 s2
        | Rol | Ror -> [Shl] (* Fallback or simplified *)
        | Div | Idiv -> [Sub] (* Stack division abstraction *)
      in
      src1_ops @ src2_ops @ alu_ops @ [PopReg (Context_allocator.slot_of_reg ctx dst)]
  | Unary { op; dst; src; _ } ->
      let src_ops = lower_operand ctx src in
      let un_ops = match op with
        | Not -> Stack_logic_pass.expand_not_nor
        | Neg -> [PushImm 0L; Swap; Sub]
        | Inc -> [PushImm 1L; Add]
        | Dec -> [PushImm 1L; Sub]
      in
      src_ops @ un_ops @ [PopReg (Context_allocator.slot_of_reg ctx dst)]
  | Cmp { src1; src2 } ->
      let src1_ops = lower_operand ctx src1 in
      let src2_ops = lower_operand ctx src2 in
      let dummy = Context_allocator.alloc_scratch ctx in
      src1_ops @ src2_ops @ [Sub; PopReg dummy]
  | Test { src1; src2 } ->
      let src1_ops = lower_operand ctx src1 in
      let src2_ops = lower_operand ctx src2 in
      let dummy = Context_allocator.alloc_scratch ctx in
      src1_ops @ src2_ops @ Stack_logic_pass.expand_and_nor @ [PopReg dummy]
  | Jmp target ->
      [JmpRel (resolve_target target)]
  | Jcc { cond; target_true; target_false } ->
      let t_id = resolve_target target_true in
      let f_id = resolve_target target_false in
      [JccRel (t_id, cond); JmpRel f_id]
  | Setcc { cond; dst } ->
      (* Dummy setcc / conditional lowering *)
      let s_slot = Context_allocator.alloc_scratch ctx in
      let cont_id = 99999 in
      [PushImm 0L; PopReg s_slot;
       JccRel (cont_id, cond);
       JmpRel (cont_id + 1)] @
      store_to_operand ctx dst
  | Cmov { cond; dst; src } ->
      let src_ops = lower_operand ctx src in
      let skip_id = 88888 in
      [JccRel (skip_id, cond); JmpRel (skip_id + 1)] @
      src_ops @
      [PopReg (Context_allocator.slot_of_reg ctx dst)]
  | Xchg (op1, op2) ->
      let s1 = Context_allocator.alloc_scratch ctx in
      let s2 = Context_allocator.alloc_scratch ctx in
      (lower_operand ctx op1) @ [PopReg s1] @
      (lower_operand ctx op2) @ [PopReg s2] @
      [PushReg s1] @ (store_to_operand ctx op2) @
      [PushReg s2] @ (store_to_operand ctx op1)
  | Call target ->
      [JmpRel (resolve_target target)]
  | Trap _ -> [Exit]
  | Bridge_to_flow _ | Bridge_to_math _ -> [Exit]
  | Load_symbol { dst; addend; _ } ->
      [PushImm addend; PopReg (Context_allocator.slot_of_reg ctx dst)]
  | Fp_binop _ | Fp_cmp _ | Fp_conv _ -> []
  | Vec_mov _ | Vec_binop _ | Vec_load _ | Vec_store _ -> []
  | Atomic_mem { dst; src; _ } ->
      [PushReg (Context_allocator.slot_of_reg ctx src);
       PopReg (Context_allocator.slot_of_reg ctx dst)]

let lower_basic_block ctx (b : Ir.basic_block) =
  let ops = List.concat_map (lower_instr ctx) b.instrs in
  make_block b.id b.label ops

let lower_cfg ctx (cfg : Ir.cfg) =
  let block_list = Hashtbl.fold (fun _ b acc -> (lower_basic_block ctx b) :: acc) cfg.blocks [] in
  make_program cfg.entry_id block_list (Context_allocator.total_slots ctx)

let lower_func ?(ctx = Context_allocator.create ()) (f : Ir.func) =
  let prog = lower_cfg ctx f.cfg in
  (ctx, prog)
