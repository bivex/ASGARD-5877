open Ir

(* Sub-register writes are normalized before lowering so the native VM follows
   the evaluator for B8/B16 merge and B32 zero-extension. *)

let written_gprs : instr -> Register.t list = function
  | Mov { dst = Reg d; _ } -> [ d ]
  | Lea { dst; _ } -> [ dst ]
  | Xchg (Reg a, Reg b) -> [ a; b ]
  | Xchg (Reg a, _) | Xchg (_, Reg a) -> [ a ]
  | Xchg _ -> []
  | Alu { dst; _ } -> [ dst ]
  | Unary { dst; _ } -> [ dst ]
  | Pop (Reg d) -> [ d ]
  | Cmov { dst; _ } -> [ dst ]
  | Setcc { dst = Reg d; _ } -> [ d ]
  | Setcc _ -> []
  | Load_symbol { dst; _ } -> [ dst ]
  | _ -> []

let same_reg a b = Register.to_string a = Register.to_string b

let is_arm_gpr_alias v =
  match v with
  | Register.VTMP0 | Register.VTMP1 | Register.VTMP2 | Register.VTMP3
  | Register.VX18 | Register.VX19 | Register.VX20 | Register.VX21
  | Register.VX22 | Register.VX23 | Register.VX24 | Register.VX25
  | Register.VX26 -> true
  | _ -> false

let is_gpr_like r =
  match r with
  | Register.Gpr _ -> true
  | Register.Vreg (v, _) -> is_arm_gpr_alias v
  | _ -> false

let is_b32_gpr r =
  is_gpr_like r && Register.get_width r = Register.B32

let is_merge_gpr r =
  match r with
  | Register.Gpr (_, (Register.B8 | Register.B16)) -> true
  | _ -> false

let mem_regs (m : mem_ref) =
  let base_regs = match m.base with Some r -> [ r ] | None -> [] in
  let index_regs = match m.index with Some (r, _) -> [ r ] | None -> [] in
  base_regs @ index_regs

let operand_regs = function
  | Reg r -> [ r ]
  | Imm _ -> []
  | Mem m -> mem_regs m

let instr_regs i =
  let operand_dst = function Reg r -> [ r ] | _ -> [] in
  match i with
  | Mov { dst; src } -> operand_dst dst @ operand_regs src
  | Lea { dst; addr } -> [ dst ] @ mem_regs addr
  | Push op | Pop op -> operand_regs op
  | Xchg (a, b) -> operand_regs a @ operand_regs b
  | Alu { dst; src1; src2; _ } -> [ dst ] @ operand_regs src1 @ operand_regs src2
  | Unary { dst; src; _ } -> [ dst ] @ operand_regs src
  | Cmp { src1; src2 } | Test { src1; src2 } -> operand_regs src1 @ operand_regs src2
  | Setcc { dst; _ } -> operand_dst dst
  | Cmov { dst; src; _ } -> dst :: operand_regs src
  | Load_symbol { dst; _ } -> [ dst ]
  | _ -> []

let pick_scratch used =
  let candidates = [ Register.vtmp0; Register.vtmp1; Register.vtmp2; Register.vx26 ] in
  match List.find_opt (fun candidate -> not (List.exists (same_reg candidate) used)) candidates with
  | Some candidate -> candidate
  | None -> Register.vx26

let mask_of_width = function
  | Register.B8 -> 0xFFL
  | Register.B16 -> 0xFFFFL
  | _ -> 0xFFFFFFFFL

let zext_pair r =
  let r64 = Register.with_width r Register.B64 in
  [ Alu { op = Shl; dst = r64; src1 = Reg r64; src2 = Imm 32L; set_flags = false };
    Alu { op = Shr; dst = r64; src1 = Reg r64; src2 = Imm 32L; set_flags = false } ]

let merge_sequence scratch dst =
  let dst64 = Register.with_width dst Register.B64 in
  let scratch64 = Register.with_width scratch Register.B64 in
  let mask = mask_of_width (Register.get_width dst) in
  [ Alu { op = And; dst = dst64; src1 = Reg dst64; src2 = Imm mask; set_flags = false };
    Alu { op = And; dst = scratch64; src1 = Reg scratch64; src2 = Imm (Int64.lognot mask); set_flags = false };
    Alu { op = Or; dst = dst64; src1 = Reg dst64; src2 = Reg scratch64; set_flags = false } ]

let expand_instr i =
  let writes = written_gprs i in
  let b32_writes = List.filter is_b32_gpr writes in
  let merge_writes = List.filter is_merge_gpr writes in
  let used = instr_regs i in
  let merge_pairs, _ =
    List.fold_left
      (fun (pairs, used) dst ->
        let scratch = pick_scratch used in
        ((dst, scratch) :: pairs, scratch :: used))
      ([], used) merge_writes
  in
  let pre = List.map (fun (dst, scratch) -> Mov { dst = Reg (Register.with_width scratch Register.B64); src = Reg (Register.with_width dst Register.B64) }) merge_pairs in
  let post = List.concat_map (fun (dst, scratch) -> merge_sequence scratch dst) merge_pairs in
  let zexts = List.concat_map zext_pair b32_writes in
  if pre = [] && post = [] && zexts = [] then [ i ] else pre @ (i :: (post @ zexts))

let expand_block (b : basic_block) : basic_block =
  { b with instrs = List.concat_map expand_instr b.instrs }

let expand_cfg (c : cfg) : cfg =
  let blocks = Hashtbl.create (Hashtbl.length c.blocks) in
  Hashtbl.iter (fun id b -> Hashtbl.replace blocks id (expand_block b)) c.blocks;
  { c with blocks }

let expand_func (f : func) : func = { f with cfg = expand_cfg f.cfg }
