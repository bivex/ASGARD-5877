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

let get_ext_sym_idx ext_syms sym =
  match Hashtbl.find_opt ext_syms sym with
  | Some idx -> idx
  | None ->
      let idx = Hashtbl.length ext_syms in
      Hashtbl.replace ext_syms sym idx;
      idx

let resolve_target label_to_block = function
  | BlockId id -> id
  | TargetImm imm -> Int64.to_int imm
  | Label s ->
      (match Hashtbl.find_opt label_to_block s with
       | Some id -> id
       | None ->
           (match int_of_string_opt s with
            | Some id -> id
            | None -> Hashtbl.hash s land 0xFFFF))

let lower_instr ?(label_to_block = Hashtbl.create 0) ?(ext_syms = Hashtbl.create 0) ctx = function
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
      src1_ops @ src2_ops @ [Cmp]
  | Test { src1; src2 } ->
      let src1_ops = lower_operand ctx src1 in
      let src2_ops = lower_operand ctx src2 in
      src1_ops @ src2_ops @ [Test]
  | Jmp target ->
      [JmpRel (resolve_target label_to_block target)]
  | Jcc { cond; target_true; target_false } ->
      let t_id = resolve_target label_to_block target_true in
      let f_id = resolve_target label_to_block target_false in
      [JccRel (t_id, cond); JmpRel f_id]
  | Setcc { cond; dst } ->
      [Setcc cond] @ store_to_operand ctx dst
  | Cmov { cond; dst; src } ->
      let src_ops = lower_operand ctx src in
      let d_slot = Context_allocator.slot_of_reg ctx dst in
      src_ops @ [Cmov (cond, d_slot)]
  | Xchg (op1, op2) ->
      let s1 = Context_allocator.alloc_scratch ctx in
      let s2 = Context_allocator.alloc_scratch ctx in
      (lower_operand ctx op1) @ [PopReg s1] @
      (lower_operand ctx op2) @ [PopReg s2] @
      [PushReg s1] @ (store_to_operand ctx op2) @
      [PushReg s2] @ (store_to_operand ctx op1)
  | Call target ->
      (match target with
       | BlockId id -> [JmpRel id]
       | Label sym ->
           (match Hashtbl.find_opt label_to_block sym with
            | Some id -> [JmpRel id]
            | None ->
                let sym_idx = get_ext_sym_idx ext_syms sym in
                [CallExtern sym_idx])
       | TargetImm imm ->
           let sym_idx = get_ext_sym_idx ext_syms (Printf.sprintf "0x%Lx" imm) in
           [CallExtern sym_idx])
  | Trap _ -> [Exit]
  | Bridge_to_flow _ | Bridge_to_math _ -> [Exit]
  | Load_symbol { dst; sym; addend } ->
      let sym_idx = get_ext_sym_idx ext_syms sym in
      let load_ops =
        [ResolveSym sym_idx] @
        (if addend = 0L then [] else [PushImm addend; Add]) @
        [PopReg (Context_allocator.slot_of_reg ctx dst)]
      in
      load_ops
  | Fp_binop _ | Fp_cmp _ | Fp_conv _ -> []
  | Vec_mov _ | Vec_binop _ | Vec_load _ | Vec_store _ -> []
  | Atomic_mem { dst; src; _ } ->
      [PushReg (Context_allocator.slot_of_reg ctx src);
       PopReg (Context_allocator.slot_of_reg ctx dst)]

let lower_basic_block ?(label_to_block = Hashtbl.create 0) ?(ext_syms = Hashtbl.create 0) ctx (b : Ir.basic_block) =
  let ops = List.concat_map (lower_instr ~label_to_block ~ext_syms ctx) b.instrs in
  make_block b.id b.label ops

let lower_cfg ?(ext_syms = Hashtbl.create 16) ctx (cfg : Ir.cfg) =
  let label_to_block = Hashtbl.create (Hashtbl.length cfg.blocks) in
  Hashtbl.iter (fun id b ->
    Hashtbl.replace label_to_block b.Ir.label id
  ) cfg.blocks;
  let block_list = Hashtbl.fold (fun _ b acc ->
    (lower_basic_block ~label_to_block ~ext_syms ctx b) :: acc
  ) cfg.blocks [] in
  make_program cfg.entry_id block_list (Context_allocator.total_slots ctx)

let lower_func ?(ctx = Context_allocator.create ()) ?(ext_syms = Hashtbl.create 16) (f : Ir.func) =
  let prog = lower_cfg ~ext_syms ctx f.cfg in
  (ctx, prog)

let get_symbols_list ext_syms =
  let arr = Array.make (Hashtbl.length ext_syms) "" in
  Hashtbl.iter (fun sym idx -> if idx < Array.length arr then arr.(idx) <- sym) ext_syms;
  Array.to_list arr

