open Vm_ir
open Riscv_types
open Flags

type options = {
  function_name : string;
}

let default_options = {
  function_name = "riscv_lifted_func";
}

let raw_to_ir_operand = function
  | OpReg r -> Ir.Reg r
  | OpImm i -> Ir.Imm i
  | OpMem m -> Ir.Mem { base = m.base; index = None; disp = m.disp; width = m.width; is_signed = m.is_signed }
  | OpLabel _ -> Ir.Imm 0L

let emit_3addr_alu ~op ~dst ~src1 ~src2 ~set_flags =
  if Register.to_string dst = Register.to_string src1 then
    [ Ir.Alu { op; dst; src1 = Reg src1; src2 = raw_to_ir_operand src2; set_flags } ]
  else
    [
      Ir.Mov { dst = Reg dst; src = Reg src1 };
      Ir.Alu { op; dst; src1 = Reg dst; src2 = raw_to_ir_operand src2; set_flags };
    ]

let is_terminator = function
  | Ir.Jmp _ | Ir.Jcc _ | Ir.Ret | Ir.Trap _ -> true
  | _ -> false

let lift_instr (mnemonic : string) (ops : raw_op list) : (Ir.instr list, string) result =
  match (mnemonic, ops) with
  (* NOP & directives *)
  | ("nop", _) | (".align" | ".p2align" | ".globl" | ".text" | ".data" | ".rodata"), _ ->
      Ok [ Ir.Nop ]

  (* Moves, Immediates, Load Address *)
  | ("mv", [ OpReg dst; OpReg src ]) ->
      Ok [ Ir.Mov { dst = Reg dst; src = Reg src } ]
  | ("li", [ OpReg dst; OpImm imm ]) ->
      Ok [ Ir.Mov { dst = Reg dst; src = Imm imm } ]
  | ("lui", [ OpReg dst; OpImm imm ]) ->
      let shifted = Int64.shift_left (Int64.logand imm 0xFFFFFL) 12 in
      Ok [ Ir.Mov { dst = Reg dst; src = Imm shifted } ]
  | ("auipc", [ OpReg dst; OpImm imm ]) ->
      let shifted = Int64.shift_left (Int64.logand imm 0xFFFFFL) 12 in
      Ok [ Ir.Load_symbol { dst; sym = "."; addend = shifted } ]
  | ("auipc", [ OpReg dst; OpLabel sym ]) ->
      Ok [ Ir.Load_symbol { dst; sym; addend = 0L } ]
  | ("neg", [ OpReg dst; OpReg src ]) ->
      Ok [
        Ir.Mov { dst = Reg dst; src = Reg src };
        Ir.Unary { op = Neg; dst; src = Reg dst; set_flags = false };
      ]
  | ("not", [ OpReg dst; OpReg src ]) ->
      Ok [
        Ir.Mov { dst = Reg dst; src = Reg src };
        Ir.Unary { op = Not; dst; src = Reg dst; set_flags = false };
      ]

  (* 64-bit / 32-bit ALU: Add / Sub *)
  | (("add" | "addi" | "addw" | "addiw"), [ OpReg dst; OpReg src1; ((OpReg _ | OpImm _) as src2) ]) ->
      Ok (emit_3addr_alu ~op:Add ~dst ~src1 ~src2 ~set_flags:false)
  | (("sub" | "subw"), [ OpReg dst; OpReg src1; ((OpReg _ | OpImm _) as src2) ]) ->
      Ok (emit_3addr_alu ~op:Sub ~dst ~src1 ~src2 ~set_flags:false)

  (* M-extension: Mul / Div / Rem *)
  | (("mul" | "mulw"), [ OpReg dst; OpReg src1; ((OpReg _ | OpImm _) as src2) ]) ->
      Ok (emit_3addr_alu ~op:Mul ~dst ~src1 ~src2 ~set_flags:false)
  | (("div" | "divw"), [ OpReg dst; OpReg src1; ((OpReg _ | OpImm _) as src2) ]) ->
      Ok (emit_3addr_alu ~op:Idiv ~dst ~src1 ~src2 ~set_flags:false)
  | (("divu" | "divuw"), [ OpReg dst; OpReg src1; ((OpReg _ | OpImm _) as src2) ]) ->
      Ok (emit_3addr_alu ~op:Div ~dst ~src1 ~src2 ~set_flags:false)
  | (("rem" | "remw"), [ OpReg dst; OpReg src1; ((OpReg _ | OpImm _) as src2) ]) ->
      (* rem = dividend - quotient * divisor *)
      Ok [
        Ir.Mov { dst = Reg Register.vtmp0; src = Reg src1 };
        Ir.Alu { op = Idiv; dst = Register.vtmp0; src1 = Reg Register.vtmp0; src2 = raw_to_ir_operand src2; set_flags = false };
        Ir.Alu { op = Mul; dst = Register.vtmp0; src1 = Reg Register.vtmp0; src2 = raw_to_ir_operand src2; set_flags = false };
        Ir.Mov { dst = Reg dst; src = Reg src1 };
        Ir.Alu { op = Sub; dst; src1 = Reg dst; src2 = Reg Register.vtmp0; set_flags = false };
      ]
  | (("remu" | "remuw"), [ OpReg dst; OpReg src1; ((OpReg _ | OpImm _) as src2) ]) ->
      Ok [
        Ir.Mov { dst = Reg Register.vtmp0; src = Reg src1 };
        Ir.Alu { op = Div; dst = Register.vtmp0; src1 = Reg Register.vtmp0; src2 = raw_to_ir_operand src2; set_flags = false };
        Ir.Alu { op = Mul; dst = Register.vtmp0; src1 = Reg Register.vtmp0; src2 = raw_to_ir_operand src2; set_flags = false };
        Ir.Mov { dst = Reg dst; src = Reg src1 };
        Ir.Alu { op = Sub; dst; src1 = Reg dst; src2 = Reg Register.vtmp0; set_flags = false };
      ]

  (* Logic *)
  | (("and" | "andi"), [ OpReg dst; OpReg src1; ((OpReg _ | OpImm _) as src2) ]) ->
      Ok (emit_3addr_alu ~op:And ~dst ~src1 ~src2 ~set_flags:false)
  | (("or" | "ori"), [ OpReg dst; OpReg src1; ((OpReg _ | OpImm _) as src2) ]) ->
      Ok (emit_3addr_alu ~op:Or ~dst ~src1 ~src2 ~set_flags:false)
  | (("xor" | "xori"), [ OpReg dst; OpReg src1; ((OpReg _ | OpImm _) as src2) ]) ->
      Ok (emit_3addr_alu ~op:Xor ~dst ~src1 ~src2 ~set_flags:false)

  (* Shifts *)
  | (("sll" | "slli" | "sllw" | "slliw"), [ OpReg dst; OpReg src1; ((OpReg _ | OpImm _) as src2) ]) ->
      Ok (emit_3addr_alu ~op:Shl ~dst ~src1 ~src2 ~set_flags:false)
  | (("srl" | "srli" | "srlw" | "srliw"), [ OpReg dst; OpReg src1; ((OpReg _ | OpImm _) as src2) ]) ->
      Ok (emit_3addr_alu ~op:Shr ~dst ~src1 ~src2 ~set_flags:false)
  | (("sra" | "srai" | "sraw" | "sraiw"), [ OpReg dst; OpReg src1; ((OpReg _ | OpImm _) as src2) ]) ->
      Ok (emit_3addr_alu ~op:Sar ~dst ~src1 ~src2 ~set_flags:false)

  (* Set Less Than *)
  | (("slt" | "slti"), [ OpReg dst; OpReg src1; ((OpReg _ | OpImm _) as src2) ]) ->
      Ok [
        Ir.Cmp { src1 = Reg src1; src2 = raw_to_ir_operand src2 };
        Ir.Setcc { cond = L; dst = Reg dst };
      ]
  | (("sltu" | "sltui"), [ OpReg dst; OpReg src1; ((OpReg _ | OpImm _) as src2) ]) ->
      Ok [
        Ir.Cmp { src1 = Reg src1; src2 = raw_to_ir_operand src2 };
        Ir.Setcc { cond = B; dst = Reg dst };
      ]

  (* Memory: Loads *)
  | (("ld" | "lw" | "lwu" | "lh" | "lhu" | "lb" | "lbu"), [ OpReg dst; OpMem m ]) ->
      Ok [ Ir.Mov { dst = Reg dst; src = raw_to_ir_operand (OpMem m) } ]
  | (("fld" | "flw"), [ OpReg dst; OpMem m ]) ->
      Ok [ Ir.Mov { dst = Reg dst; src = raw_to_ir_operand (OpMem m) } ]

  (* Memory: Stores *)
  | (("sd" | "sw" | "sh" | "sb"), [ OpReg src; OpMem m ]) ->
      Ok [ Ir.Mov { dst = raw_to_ir_operand (OpMem m); src = Reg src } ]
  | (("fsd" | "fsw"), [ OpReg src; OpMem m ]) ->
      Ok [ Ir.Mov { dst = raw_to_ir_operand (OpMem m); src = Reg src } ]

  (* Branches *)
  | ("beq", [ OpReg src1; ((OpReg _ | OpImm _) as src2); OpLabel target ]) ->
      Ok [
        Ir.Cmp { src1 = Reg src1; src2 = raw_to_ir_operand src2 };
        Ir.Jcc { cond = E; target_true = Label target; target_false = TargetImm 0L };
      ]
  | ("bne", [ OpReg src1; ((OpReg _ | OpImm _) as src2); OpLabel target ]) ->
      Ok [
        Ir.Cmp { src1 = Reg src1; src2 = raw_to_ir_operand src2 };
        Ir.Jcc { cond = NE; target_true = Label target; target_false = TargetImm 0L };
      ]
  | ("blt", [ OpReg src1; ((OpReg _ | OpImm _) as src2); OpLabel target ]) ->
      Ok [
        Ir.Cmp { src1 = Reg src1; src2 = raw_to_ir_operand src2 };
        Ir.Jcc { cond = L; target_true = Label target; target_false = TargetImm 0L };
      ]
  | ("bge", [ OpReg src1; ((OpReg _ | OpImm _) as src2); OpLabel target ]) ->
      Ok [
        Ir.Cmp { src1 = Reg src1; src2 = raw_to_ir_operand src2 };
        Ir.Jcc { cond = GE; target_true = Label target; target_false = TargetImm 0L };
      ]
  | ("bltu", [ OpReg src1; ((OpReg _ | OpImm _) as src2); OpLabel target ]) ->
      Ok [
        Ir.Cmp { src1 = Reg src1; src2 = raw_to_ir_operand src2 };
        Ir.Jcc { cond = B; target_true = Label target; target_false = TargetImm 0L };
      ]
  | ("bgeu", [ OpReg src1; ((OpReg _ | OpImm _) as src2); OpLabel target ]) ->
      Ok [
        Ir.Cmp { src1 = Reg src1; src2 = raw_to_ir_operand src2 };
        Ir.Jcc { cond = AE; target_true = Label target; target_false = TargetImm 0L };
      ]

  (* Pseudo branches *)
  | ("beqz", [ OpReg src; OpLabel target ]) ->
      Ok [
        Ir.Cmp { src1 = Reg src; src2 = Imm 0L };
        Ir.Jcc { cond = E; target_true = Label target; target_false = TargetImm 0L };
      ]
  | ("bnez", [ OpReg src; OpLabel target ]) ->
      Ok [
        Ir.Cmp { src1 = Reg src; src2 = Imm 0L };
        Ir.Jcc { cond = NE; target_true = Label target; target_false = TargetImm 0L };
      ]
  | ("blez", [ OpReg src; OpLabel target ]) ->
      Ok [
        Ir.Cmp { src1 = Reg src; src2 = Imm 0L };
        Ir.Jcc { cond = LE; target_true = Label target; target_false = TargetImm 0L };
      ]
  | ("bgez", [ OpReg src; OpLabel target ]) ->
      Ok [
        Ir.Cmp { src1 = Reg src; src2 = Imm 0L };
        Ir.Jcc { cond = GE; target_true = Label target; target_false = TargetImm 0L };
      ]
  | ("bltz", [ OpReg src; OpLabel target ]) ->
      Ok [
        Ir.Cmp { src1 = Reg src; src2 = Imm 0L };
        Ir.Jcc { cond = L; target_true = Label target; target_false = TargetImm 0L };
      ]
  | ("bgtz", [ OpReg src; OpLabel target ]) ->
      Ok [
        Ir.Cmp { src1 = Reg src; src2 = Imm 0L };
        Ir.Jcc { cond = G; target_true = Label target; target_false = TargetImm 0L };
      ]

  (* Jumps & Calls & Returns *)
  | ("j", [ OpLabel target ]) ->
      Ok [ Ir.Jmp (Label target) ]
  | ("jal", [ OpLabel target ]) ->
      Ok [ Ir.Call (Label target) ]
  | ("jal", [ OpReg (Register.Vreg (Register.VZERO, _)); OpLabel target ]) ->
      Ok [ Ir.Jmp (Label target) ]
  | ("jal", [ OpReg _; OpLabel target ]) ->
      Ok [ Ir.Call (Label target) ]
  | ("ret", []) ->
      Ok [ Ir.Ret ]
  | ("jr", [ OpReg (Register.Vreg (Register.VTMP3, _)) ]) ->
      Ok [ Ir.Ret ]
  | ("jr", [ OpReg _ ]) ->
      Ok [ Ir.Jmp (TargetImm 0L) ]
  | ("jalr", [ OpReg (Register.Vreg (Register.VZERO, _)); OpMem m ]) when m.disp = 0L ->
      (match m.base with
      | Some (Register.Vreg (Register.VTMP3, _)) -> Ok [ Ir.Ret ]
      | _ -> Ok [ Ir.Jmp (TargetImm 0L) ])
  | ("jalr", [ OpReg _; OpMem _ ]) | ("jalr", [ OpReg _ ]) ->
      Ok [ Ir.Call (TargetImm 0L) ]
  | ("call", [ OpLabel target ]) ->
      Ok [ Ir.Call (Label target) ]
  | ("tail", [ OpLabel target ]) ->
      Ok [ Ir.Jmp (Label target) ]

  (* A-extension: Atomics *)
  | (("lr.w" | "lr.d"), [ OpReg dst; OpMem m ]) ->
      let base = match m.base with Some b -> b | None -> Register.rsp in
      Ok [ Ir.Atomic_mem { op = AtLoad; dst; addr = base; src = dst; imm = m.disp } ]
  | (("sc.w" | "sc.d"), [ OpReg dst; OpReg src; OpMem m ]) ->
      let base = match m.base with Some b -> b | None -> Register.rsp in
      Ok [ Ir.Atomic_mem { op = AtStore; dst; addr = base; src; imm = m.disp } ]
  | (("amoswap.w" | "amoswap.d"), [ OpReg dst; OpReg src; OpMem m ]) ->
      let base = match m.base with Some b -> b | None -> Register.rsp in
      Ok [ Ir.Atomic_mem { op = AtSwp; dst; addr = base; src; imm = m.disp } ]
  | (("amoadd.w" | "amoadd.d"), [ OpReg dst; OpReg src; OpMem m ]) ->
      let base = match m.base with Some b -> b | None -> Register.rsp in
      Ok [ Ir.Atomic_mem { op = AtAdd; dst; addr = base; src; imm = m.disp } ]
  | (("fence" | "fence.i"), _) ->
      Ok [ Ir.Nop ]

  (* F & D Extensions: Floating Point *)
  | (("fadd.s" | "fadd.d"), [ OpReg (Register.Fpr (d, _)); OpReg (Register.Fpr (s1, _)); OpReg (Register.Fpr (s2, _)) ]) ->
      Ok [ Ir.Fp_binop { op = Fadd; dst = d; src1 = s1; src2 = s2 } ]
  | (("fsub.s" | "fsub.d"), [ OpReg (Register.Fpr (d, _)); OpReg (Register.Fpr (s1, _)); OpReg (Register.Fpr (s2, _)) ]) ->
      Ok [ Ir.Fp_binop { op = Fsub; dst = d; src1 = s1; src2 = s2 } ]
  | (("fmul.s" | "fmul.d"), [ OpReg (Register.Fpr (d, _)); OpReg (Register.Fpr (s1, _)); OpReg (Register.Fpr (s2, _)) ]) ->
      Ok [ Ir.Fp_binop { op = Fmul; dst = d; src1 = s1; src2 = s2 } ]
  | (("fdiv.s" | "fdiv.d"), [ OpReg (Register.Fpr (d, _)); OpReg (Register.Fpr (s1, _)); OpReg (Register.Fpr (s2, _)) ]) ->
      Ok [ Ir.Fp_binop { op = Fdiv; dst = d; src1 = s1; src2 = s2 } ]
  | (("feq.s" | "feq.d" | "flt.s" | "flt.d" | "fle.s" | "fle.d"), [ OpReg dst; OpReg (Register.Fpr (s1, _)); OpReg (Register.Fpr (s2, _)) ]) ->
      let cond = match mnemonic with
        | "feq.s" | "feq.d" -> E
        | "flt.s" | "flt.d" -> B
        | _ -> BE
      in
      Ok [
        Ir.Fp_cmp { src1 = s1; src2 = s2 };
        Ir.Setcc { cond; dst = Reg dst };
      ]
  | (("fcvt.w.d" | "fcvt.w.s" | "fcvt.l.d" | "fcvt.l.s"), [ OpReg dst; OpReg (Register.Fpr (s, _)) ]) ->
      Ok [ Ir.Fp_conv { op = Fcvtzs; dst; src = Register.Fpr (s, Register.B64) } ]
  | (("fcvt.d.w" | "fcvt.s.w" | "fcvt.d.l" | "fcvt.s.l"), [ OpReg (Register.Fpr (d, _)); OpReg src ]) ->
      Ok [ Ir.Fp_conv { op = Scvtf; dst = Register.Fpr (d, Register.B64); src } ]
  | (("fmv.d" | "fmv.s"), [ OpReg (Register.Fpr (d, _)); OpReg (Register.Fpr (s, _)) ]) ->
      Ok [ Ir.Fp_binop { op = Fadd; dst = d; src1 = s; src2 = 31 } ]

  (* V-extension: RVV Vector Operations *)
  | ("vadd.vv", [ OpReg (Register.Fpr (d, _)); OpReg (Register.Fpr (s1, _)); OpReg (Register.Fpr (s2, _)) ]) ->
      Ok [ Ir.Vec_binop { op = Vadd; elem = VInt; dst = d; src1 = s1; src2 = s2; bits = 128; lane_bits = 64 } ]
  | ("vsub.vv", [ OpReg (Register.Fpr (d, _)); OpReg (Register.Fpr (s1, _)); OpReg (Register.Fpr (s2, _)) ]) ->
      Ok [ Ir.Vec_binop { op = Vsub; elem = VInt; dst = d; src1 = s1; src2 = s2; bits = 128; lane_bits = 64 } ]
  | ("vmul.vv", [ OpReg (Register.Fpr (d, _)); OpReg (Register.Fpr (s1, _)); OpReg (Register.Fpr (s2, _)) ]) ->
      Ok [ Ir.Vec_binop { op = Vmul; elem = VInt; dst = d; src1 = s1; src2 = s2; bits = 128; lane_bits = 64 } ]
  | ("vand.vv", [ OpReg (Register.Fpr (d, _)); OpReg (Register.Fpr (s1, _)); OpReg (Register.Fpr (s2, _)) ]) ->
      Ok [ Ir.Vec_binop { op = Vand; elem = VInt; dst = d; src1 = s1; src2 = s2; bits = 128; lane_bits = 64 } ]
  | ("vor.vv", [ OpReg (Register.Fpr (d, _)); OpReg (Register.Fpr (s1, _)); OpReg (Register.Fpr (s2, _)) ]) ->
      Ok [ Ir.Vec_binop { op = Vor; elem = VInt; dst = d; src1 = s1; src2 = s2; bits = 128; lane_bits = 64 } ]
  | ("vxor.vv", [ OpReg (Register.Fpr (d, _)); OpReg (Register.Fpr (s1, _)); OpReg (Register.Fpr (s2, _)) ]) ->
      Ok [ Ir.Vec_binop { op = Vxor; elem = VInt; dst = d; src1 = s1; src2 = s2; bits = 128; lane_bits = 64 } ]
  | (("vle8.v" | "vle16.v" | "vle32.v" | "vle64.v"), [ OpReg (Register.Fpr (d, _)); OpMem m ]) ->
      Ok [ Ir.Vec_load { dst = d; addr = { base = m.base; index = None; disp = m.disp; width = m.width; is_signed = false }; bits = 128 } ]
  | (("vse8.v" | "vse16.v" | "vse32.v" | "vse64.v"), [ OpReg (Register.Fpr (s, _)); OpMem m ]) ->
      Ok [ Ir.Vec_store { src = s; addr = { base = m.base; index = None; disp = m.disp; width = m.width; is_signed = false }; bits = 128 } ]
  | ("vmv.v.v", [ OpReg (Register.Fpr (d, _)); OpReg (Register.Fpr (s, _)) ]) ->
      Ok [ Ir.Vec_mov { dst = d; src = s; bits = 128 } ]
  | (("vsetvli" | "vsetivli" | "vsetvl"), OpReg dst :: _) ->
      Ok [ Ir.Mov { dst = Reg dst; src = Imm 16L } ]

  | _ ->
      if String.starts_with ~prefix:"." mnemonic then
        Ok [ Ir.Nop ]
      else
        Error (Printf.sprintf "Unsupported or invalid RISC-V instruction: %s" mnemonic)

let lift_lines ?(options = default_options) (lines : raw_line list) : (Ir.func, string) result =
  let blocks = ref [] in
  let label_aliases = Hashtbl.create 32 in
  let cur_labels = ref [ "entry" ] in
  let cur_instrs = ref [] in
  let cur_id = ref 0 in

  let flush_block () =
    if !cur_instrs <> [] || !blocks = [] then begin
      let primary_label = match !cur_labels with hd :: _ -> hd | [] -> Printf.sprintf "l_bb_%d" !cur_id in
      List.iter (fun l -> Hashtbl.replace label_aliases l !cur_id) !cur_labels;
      let b = {
        Ir.id = !cur_id;
        label = primary_label;
        instrs = List.rev !cur_instrs;
      } in
      blocks := b :: !blocks;
      incr cur_id;
      cur_instrs := [];
      cur_labels := [ Printf.sprintf "l_bb_%d" !cur_id ]
    end
  in

  let rec process = function
    | [] ->
        flush_block ();
        Ok (List.rev !blocks)
    | LineEmpty :: rest | LineDirective _ :: rest | LineMarkerBegin _ :: rest | LineMarkerEnd :: rest ->
        process rest
    | LineLabel lbl :: rest ->
        if !cur_instrs <> [] then (
          flush_block ();
          cur_labels := [ lbl ]
        ) else (
          cur_labels := lbl :: !cur_labels
        );
        process rest
    | LineInstr (m, ops) :: rest ->
        match lift_instr m ops with
        | Error err -> Error err
        | Ok ir_list ->
            cur_instrs := List.rev ir_list @ !cur_instrs;
            let last_lifted = List.hd (List.rev ir_list) in
            if is_terminator last_lifted then flush_block ();
            process rest
  in

  match process lines with
  | Error err -> Error err
  | Ok bb_list ->
      let label_map = label_aliases in
      List.iter (fun (b : Ir.basic_block) -> Hashtbl.replace label_map b.label b.id) bb_list;

      let bb_list = List.map Subreg_write.expand_block bb_list in

      let patched_blocks = List.mapi (fun idx (b : Ir.basic_block) ->
        let fallthrough_id = if idx + 1 < List.length bb_list then (List.nth bb_list (idx + 1)).id else 0 in
        let patch_target = function
          | Ir.Label l ->
              (match Hashtbl.find_opt label_map l with
              | Some bid -> Ir.BlockId bid
              | None -> Ir.Label l)
          | Ir.TargetImm _ -> Ir.BlockId fallthrough_id
          | t -> t
        in
        let patched_instrs = List.map (function
          | Ir.Jmp t -> Ir.Jmp (patch_target t)
          | Ir.Jcc { cond; target_true; target_false } ->
              Ir.Jcc { cond; target_true = patch_target target_true; target_false = patch_target target_false }
          | Ir.Call t -> Ir.Call (patch_target t)
          | other -> other
        ) b.instrs in

        let final_instrs =
          match List.rev patched_instrs with
          | [] -> [ Ir.Jmp (Ir.BlockId fallthrough_id) ]
          | last :: _ when not (is_terminator last) ->
              patched_instrs @ [ Ir.Jmp (Ir.BlockId fallthrough_id) ]
          | _ -> patched_instrs
        in
        { b with instrs = final_instrs }
      ) bb_list in

      let cfg_blocks = Hashtbl.create (List.length patched_blocks) in
      List.iter (fun (b : Ir.basic_block) -> Hashtbl.replace cfg_blocks b.id b) patched_blocks;
      let entry_id = match patched_blocks with hd :: _ -> hd.id | [] -> 0 in
      Ok {
        Ir.name = options.function_name;
        cfg = { entry_id; blocks = cfg_blocks };
      }

let lift_function ?(options = default_options) (asm_text : string) : (Ir.func, string) result =
  match Riscv_parser.parse_lines asm_text with
  | Error err -> Error err
  | Ok lines -> lift_lines ~options lines

let extract_marked_regions ?(require_markers = false) (raw_lines : Riscv_parser.raw_line list) =
  let has_markers =
    List.exists
      (function
        | Riscv_parser.LineMarkerBegin _ | Riscv_parser.LineMarkerEnd -> true
        | _ -> false)
      raw_lines
  in
  if not has_markers then
    if require_markers then []
    else [ (Riscv_parser.ModeUltra "main", raw_lines) ]
  else
    let regions = ref [] in
    let current_mode = ref None in
    let fn_lines = ref [] in
    let last_label = ref "main" in
    let seen_begin = ref false in
    let seen_end = ref false in

    List.iter
      (function
        | Riscv_parser.LineLabel lbl when not (String.starts_with ~prefix:"L" lbl) && not (String.starts_with ~prefix:"." lbl) ->
            (match !current_mode with
            | Some m when !seen_begin ->
                regions := (m, Riscv_parser.LineLabel !last_label :: List.rev !fn_lines) :: !regions;
                current_mode := None;
                seen_begin := false;
                seen_end := false;
                fn_lines := []
            | _ ->
                fn_lines := []);
            last_label := lbl

        | Riscv_parser.LineMarkerBegin mode ->
            current_mode := Some mode;
            seen_begin := true

        | Riscv_parser.LineMarkerEnd ->
            seen_end := true

        | other ->
            if !seen_begin && not !seen_end then
              fn_lines := other :: !fn_lines
      )
      raw_lines;

    (match !current_mode with
    | Some m when !seen_begin ->
        regions := (m, Riscv_parser.LineLabel !last_label :: List.rev !fn_lines) :: !regions
    | _ -> ());

    List.rev !regions

module Riscv_parser = Riscv_parser
