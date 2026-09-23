open Vm_ir
open X86_parser

type options = {
  function_name : string;
}

let default_options = {
  function_name = "func_virtualized";
}

let ( let* ) = Result.bind

let to_ir_operand = function
  | X86_parser.OpReg r -> Ok (Ir.Reg r)
  | X86_parser.OpImm i -> Ok (Ir.Imm i)
  | X86_parser.OpMem m ->
      Ok (Ir.Mem { base = m.base; index = m.index; disp = m.disp; width = m.width; is_signed = false })
  | X86_parser.OpLabel l ->
      Error (Printf.sprintf "Label '%s' cannot be used directly as a value operand" l)

let to_target = function
  | X86_parser.OpLabel l -> Ir.Label l
  | X86_parser.OpImm i -> Ir.TargetImm i
  | X86_parser.OpReg r -> Ir.Label (Register.to_string r)
  | X86_parser.OpMem _ -> Ir.Label "indirect_mem"

let parse_jcc_mnemonic mnem =
  if not (String.starts_with ~prefix:"j" mnem) || mnem = "jmp" then None
  else
    let cond_str = String.sub mnem 1 (String.length mnem - 1) in
    match Flags.condition_of_string cond_str with
    | Ok cond -> Some cond
    | Error _ -> None

let parse_setcc_mnemonic mnem =
  if not (String.starts_with ~prefix:"set" mnem) then None
  else
    let cond_str = String.sub mnem 3 (String.length mnem - 3) in
    match Flags.condition_of_string cond_str with
    | Ok cond -> Some cond
    | Error _ -> None

let parse_cmovcc_mnemonic mnem =
  if not (String.starts_with ~prefix:"cmov" mnem) then None
  else
    let cond_str = String.sub mnem 4 (String.length mnem - 4) in
    match Flags.condition_of_string cond_str with
    | Ok cond -> Some cond
    | Error _ -> None

(* div/idiv lowering (TODO item 5).  x86 divides the implicit rdx:rax dividend
   by the explicit divisor, leaving the quotient in rax/eax and the remainder
   in rdx/edx.  The VM only models a plain 64-bit division, so both halves are
   reconstructed from rax alone: compiler-emitted code always canonicalizes rdx
   first (cqo/cdq or xor edx,edx), and with a canonical rdx the 128-bit
   dividend's value equals rax's extended 64-bit value, making a 64-bit
   division exact.  The remainder is rebuilt as dividend - quotient*divisor,
   which wraps correctly through the INT64_MIN / -1 corner in both machines.
   vx18 materializes the divisor (register, memory, even rax/rdx all take the
   same path) and vx19 saves the dividend; both are reserved for this pass.
   No flags are touched, mirroring x86 where div/idiv leave flags undefined.

   Encoding constraint: the threaded-VM bytecode carries two register fields
   per ALU word and the emitter drops [src1] whenever it differs from [dst]
   (vm_emitter encodes only [dst] and [src2]; the native handler computes
   dst OP src).  Every instruction produced here therefore keeps src1 = dst;
   the remainder subtraction accumulates in vx19 and is moved out afterwards
   instead of computing vx19 - rdx directly into rdx. *)
let lift_x86_div ~signed divisor =
  let width_of = function
    | X86_parser.OpReg r -> Register.get_width r
    | X86_parser.OpMem m -> m.width
    | _ -> Register.B64
  in
  let div_op = if signed then Ir.Idiv else Ir.Div in
  match width_of divisor with
  | Register.B64 ->
      let* ir_div = to_ir_operand divisor in
      Ok
        [ Ir.Mov { dst = Ir.Reg Register.vx18; src = ir_div };
          Ir.Mov { dst = Ir.Reg Register.vx19; src = Ir.Reg Register.rax };
          Ir.Alu { op = div_op; dst = Register.rax; src1 = Ir.Reg Register.rax; src2 = Ir.Reg Register.vx18; set_flags = false };
          Ir.Mov { dst = Ir.Reg Register.rdx; src = Ir.Reg Register.rax };
          Ir.Alu { op = Ir.Imul; dst = Register.rdx; src1 = Ir.Reg Register.rdx; src2 = Ir.Reg Register.vx18; set_flags = false };
          Ir.Alu { op = Ir.Sub; dst = Register.vx19; src1 = Ir.Reg Register.vx19; src2 = Ir.Reg Register.rdx; set_flags = false };
          Ir.Mov { dst = Ir.Reg Register.rdx; src = Ir.Reg Register.vx19 } ]
  | Register.B32 ->
      let* ir_div = to_ir_operand divisor in
      let eax = Register.with_width Register.rax Register.B32 in
      let edx = Register.with_width Register.rdx Register.B32 in
      (* Re-canonicalize both operands at B64: sext32 when signed, zext32 when
         unsigned.  Shl32/Sar32 is exact regardless of stale upper bits, and
         And 0xFFFFFFFF is idempotent on an already-truncated evaluator slot. *)
      let canonicalize r =
        if signed then
          [ Ir.Alu { op = Ir.Shl; dst = r; src1 = Ir.Reg r; src2 = Ir.Imm 32L; set_flags = false };
            Ir.Alu { op = Ir.Sar; dst = r; src1 = Ir.Reg r; src2 = Ir.Imm 32L; set_flags = false } ]
        else
          [ Ir.Alu { op = Ir.And; dst = r; src1 = Ir.Reg r; src2 = Ir.Imm 0xFFFFFFFFL; set_flags = false } ]
      in
      Ok
        ([ Ir.Mov { dst = Ir.Reg Register.vx18; src = ir_div } ]
        @ canonicalize Register.vx18
        @ [ Ir.Mov { dst = Ir.Reg Register.vx19; src = Ir.Reg Register.rax } ]
        @ canonicalize Register.rax
        @ [ (* rax = quotient (full 64-bit value) *)
            Ir.Alu { op = div_op; dst = Register.rax; src1 = Ir.Reg Register.rax; src2 = Ir.Reg Register.vx18; set_flags = false };
            (* save the full quotient before the eax write truncates the slot *)
            Ir.Mov { dst = Ir.Reg Register.rdx; src = Ir.Reg Register.rax };
            Ir.Mov { dst = Ir.Reg eax; src = Ir.Reg Register.rdx };
            (* rdx = remainder, then edx write re-truncates for the ISA view *)
            Ir.Alu { op = Ir.Imul; dst = Register.rdx; src1 = Ir.Reg Register.rdx; src2 = Ir.Reg Register.vx18; set_flags = false };
            Ir.Alu { op = Ir.Sub; dst = Register.vx19; src1 = Ir.Reg Register.vx19; src2 = Ir.Reg Register.rdx; set_flags = false };
            Ir.Mov { dst = Ir.Reg edx; src = Ir.Reg Register.vx19 } ])
  | _ ->
      Error (Printf.sprintf "%s is only modeled at 32/64-bit width" (if signed then "idiv" else "div"))

let lift_instr mnem ops =
  match mnem, ops with
  | ("nop" | ".ascii" | ".asciz" | ".string" | ".byte" | ".p2align" | ".align"), _ -> Ok [ Ir.Nop ]
  | "ret", [] -> Ok [ Ir.Ret ]
  | "vm_enter", [] -> Ok [ Ir.Vm_enter ]
  | "vm_exit", [] -> Ok [ Ir.Vm_exit ]

  | "push", [ op ] ->
      let* ir_op = to_ir_operand op in
      Ok [ Ir.Push ir_op ]
  | "pop", [ op ] ->
      let* ir_op = to_ir_operand op in
      Ok [ Ir.Pop ir_op ]
  | ("mov" | "movabs"), [ dst; src ] ->
      let* ir_dst = to_ir_operand dst in
      let* ir_src = to_ir_operand src in
      Ok [ Ir.Mov { dst = ir_dst; src = ir_src } ]
  | ("movzx" | "movzxb" | "movzxw" | "movzbq" | "movzwq"), [ dst; src ] -> (
      let* ir_dst = to_ir_operand dst in
      match (dst, src) with
      | (X86_parser.OpReg _, X86_parser.OpMem m) ->
          let ir_mem = Ir.Mem { base = m.base; index = m.index; disp = m.disp; width = m.width; is_signed = false } in
          Ok [ Ir.Mov { dst = ir_dst; src = ir_mem } ]
      | (X86_parser.OpReg d, X86_parser.OpReg s) ->
          let mask =
            match Register.get_width s with
            | Register.B8 -> 0xFFL
            | Register.B16 -> 0xFFFFL
            | _ -> 0xFFFFFFFFL
          in
          let d64 = Register.with_width d Register.B64 in
          Ok [
            Ir.Mov { dst = Ir.Reg d64; src = Ir.Reg s };
            Ir.Alu { op = Ir.And; dst = d64; src1 = Ir.Reg d64; src2 = Ir.Imm mask; set_flags = false };
            Ir.Mov { dst = Ir.Reg d; src = Ir.Reg d64 };
          ]
      | _ -> Error "Invalid operands for movzx")
  | ("movsx" | "movsxd" | "movsxb" | "movsxw" | "movsbq" | "movswq" | "movslq"), [ dst; src ] -> (
      let* ir_dst = to_ir_operand dst in
      match (dst, src) with
      | (X86_parser.OpReg _, X86_parser.OpMem m) ->
          let ir_mem = Ir.Mem { base = m.base; index = m.index; disp = m.disp; width = m.width; is_signed = true } in
          Ok [ Ir.Mov { dst = ir_dst; src = ir_mem } ]
      | (X86_parser.OpReg d, X86_parser.OpReg s) ->
          let shift =
            match Register.get_width s with
            | Register.B8 -> 56L
            | Register.B16 -> 48L
            | Register.B32 -> 32L
            | Register.B64 -> 0L
          in
          let d64 = Register.with_width d Register.B64 in
          if shift = 0L then
            Ok [ Ir.Mov { dst = ir_dst; src = Ir.Reg s } ]
          else
            Ok [
              Ir.Mov { dst = Ir.Reg d64; src = Ir.Reg s };
              Ir.Alu { op = Ir.Shl; dst = d64; src1 = Ir.Reg d64; src2 = Ir.Imm shift; set_flags = false };
              Ir.Alu { op = Ir.Sar; dst = d64; src1 = Ir.Reg d64; src2 = Ir.Imm shift; set_flags = false };
              Ir.Mov { dst = Ir.Reg d; src = Ir.Reg d64 };
            ]
      | _ -> Error "Invalid operands for movsx/movsxd")

  | "lea", [ dst; OpMem addr ] -> (
      match dst with
      | OpReg r ->
          Ok [ Ir.Lea { dst = r; addr = { base = addr.base; index = addr.index; disp = addr.disp; width = addr.width; is_signed = false } } ]
      | _ -> Error "LEA destination must be a register")
  | "xchg", [ a; b ] ->
      let* ir_a = to_ir_operand a in
      let* ir_b = to_ir_operand b in
      Ok [ Ir.Xchg (ir_a, ir_b) ]
  | "imul", [ dst; src; imm ] ->
      let* ir_src = to_ir_operand src in
      let* ir_imm = to_ir_operand imm in
      (match dst with
      | OpReg r ->
          Ok [
            Ir.Mov { dst = Ir.Reg r; src = ir_src };
            Ir.Alu { op = Ir.Imul; dst = r; src1 = Ir.Reg r; src2 = ir_imm; set_flags = true };
          ]
      | _ -> Error "3-operand IMUL destination must be a register")
  | ("add" | "adc" | "sub" | "sbb" | "and" | "or" | "xor" | "shl" | "shr" | "sar" | "rol" | "ror" | "imul"), [ dst; src ] ->
      let alu_op = match mnem with
        | "add" -> Ir.Add | "adc" -> Ir.Adc | "sub" -> Ir.Sub | "sbb" -> Ir.Sbb
        | "and" -> Ir.And | "or"  -> Ir.Or  | "xor" -> Ir.Xor
        | "shl" -> Ir.Shl | "shr" -> Ir.Shr | "sar" -> Ir.Sar
        | "rol" -> Ir.Rol | "ror" -> Ir.Ror
        | "imul" -> Ir.Imul
        | _ -> assert false
      in
      let* ir_src = to_ir_operand src in
      (match dst with
      | OpReg r ->
          Ok [ Ir.Alu { op = alu_op; dst = r; src1 = Ir.Reg r; src2 = ir_src; set_flags = true } ]
      | OpMem m ->
          let mem_ref = { Ir.base = m.base; index = m.index; disp = m.disp; width = m.width; is_signed = false } in
          Ok [
            Ir.Mov { dst = Ir.Reg Register.vtmp0; src = Ir.Mem mem_ref };
            Ir.Alu { op = alu_op; dst = Register.vtmp0; src1 = Ir.Reg Register.vtmp0; src2 = ir_src; set_flags = true };
            Ir.Mov { dst = Ir.Mem mem_ref; src = Ir.Reg Register.vtmp0 };
          ]
      | OpImm _ | OpLabel _ -> Error "Destination cannot be immediate or label")

  | ("inc" | "dec" | "not" | "neg"), [ dst ] ->
      let un_op = match mnem with
        | "inc" -> Ir.Inc | "dec" -> Ir.Dec | "not" -> Ir.Not | "neg" -> Ir.Neg
        | _ -> assert false
      in
      (match dst with
      | OpReg r ->
          Ok [ Ir.Unary { op = un_op; dst = r; src = Ir.Reg r; set_flags = true } ]
      | OpMem m ->
          let mem_ref = { Ir.base = m.base; index = m.index; disp = m.disp; width = m.width; is_signed = false } in
          Ok [
            Ir.Mov { dst = Ir.Reg Register.vtmp0; src = Ir.Mem mem_ref };
            Ir.Unary { op = un_op; dst = Register.vtmp0; src = Ir.Reg Register.vtmp0; set_flags = true };
            Ir.Mov { dst = Ir.Mem mem_ref; src = Ir.Reg Register.vtmp0 };
          ]
      | _ -> Error "Destination must be register or memory")
  | "cmp", [ s1; s2 ] ->
      let* ir_s1 = to_ir_operand s1 in
      let* ir_s2 = to_ir_operand s2 in
      Ok [ Ir.Cmp { src1 = ir_s1; src2 = ir_s2 } ]
  | "test", [ s1; s2 ] ->
      let* ir_s1 = to_ir_operand s1 in
      let* ir_s2 = to_ir_operand s2 in
      Ok [ Ir.Test { src1 = ir_s1; src2 = ir_s2 } ]
  | "jmp", [ target ] ->
      Ok [ Ir.Jmp (to_target target) ]
  | "call", [ target ] ->
      Ok [ Ir.Call (to_target target) ]
  | other, [ target ] when parse_jcc_mnemonic other <> None ->
      let cond = Option.get (parse_jcc_mnemonic other) in
      Ok [ Ir.Jcc { cond; target_true = to_target target; target_false = Ir.Label "__fallthrough__" } ]
  | other, [ dst ] when parse_setcc_mnemonic other <> None ->
      let cond = Option.get (parse_setcc_mnemonic other) in
      let* ir_dst = to_ir_operand dst in
      Ok [ Ir.Setcc { cond; dst = ir_dst } ]
  | other, [ dst; src ] when parse_cmovcc_mnemonic other <> None ->
      let cond = Option.get (parse_cmovcc_mnemonic other) in
      let* ir_src = to_ir_operand src in
      (match dst with
      | OpReg r -> Ok [ Ir.Cmov { cond; dst = r; src = ir_src } ]
      | _ -> Error "CMOV destination must be a register")
  | ("div" | "idiv"), [ divisor ] -> lift_x86_div ~signed:(mnem = "idiv") divisor
  | (* rdx canonicalization is folded into the div expansion; the dividend is
       reconstructed from rax alone, so the instruction itself is a no-op. *)
    ("cdq" | "cltd"), [] ->
      Ok [ Ir.Nop ]
  | ("cqo" | "cqto"), [] ->
      Ok [ Ir.Nop ]
  | (* cdqe/cltq sign-extend eax into rax: exact at B64 even with a stale
       upper half, because both shifts displace the stale bits. *)
    ("cdqe" | "cltq"), [] ->
      Ok
        [ Ir.Alu { op = Ir.Shl; dst = Register.rax; src1 = Ir.Reg Register.rax; src2 = Ir.Imm 32L; set_flags = false };
          Ir.Alu { op = Ir.Sar; dst = Register.rax; src1 = Ir.Reg Register.rax; src2 = Ir.Imm 32L; set_flags = false } ]
  | ("mul" | "imul"), [ _ ] ->
      Error "1-operand MUL/IMUL (128-bit product with high half in rdx) is not modeled; use the 2/3-operand forms"
  | other, _ ->
      Error (Printf.sprintf "Unsupported or invalid instruction '%s' with %d operands" other (List.length ops))

let is_terminator = function
  | Ir.Jmp _ | Ir.Jcc _ | Ir.Ret | Ir.Vm_exit | Ir.Trap _ -> true
  | _ -> false

let resolve_cfg_labels (cfg : Ir.cfg) =
  let label_to_id = Hashtbl.create 16 in
  Hashtbl.iter (fun id (b : Ir.basic_block) -> Hashtbl.replace label_to_id b.label id) cfg.blocks;

  let resolve_target = function
    | Ir.Label lbl -> (
        match Hashtbl.find_opt label_to_id lbl with
        | Some id -> Ir.BlockId id
        | None -> Ir.Label lbl)
    | other -> other
  in

  let resolved_blocks = Hashtbl.create (Hashtbl.length cfg.blocks) in
  Hashtbl.iter
    (fun id (b : Ir.basic_block) ->
      let resolved_instrs =
        List.map
          (fun instr ->
            match instr with
            | Ir.Jmp t -> Ir.Jmp (resolve_target t)
            | Ir.Jcc { cond; target_true; target_false } ->
                Ir.Jcc {
                  cond;
                  target_true = resolve_target target_true;
                  target_false = resolve_target target_false;
                }
            | Ir.Call t -> Ir.Call (resolve_target t)
            | other -> other)
          b.instrs
      in
      Hashtbl.replace resolved_blocks id { b with instrs = resolved_instrs })
    cfg.blocks;

  Ok { cfg with blocks = resolved_blocks }

let is_func_label lbl =
  let s = String.lowercase_ascii lbl in
  not (String.starts_with ~prefix:"ltmp" s
       || String.starts_with ~prefix:"lbb" s
       || String.starts_with ~prefix:"." s)


let lift_lines ?(options = default_options) raw_lines =
  let block_id = ref 0 in
  let func_name = ref options.function_name in
  let current_label = ref options.function_name in
  let current_instrs = ref [] in
  let raw_blocks = ref [] in

  let flush_block () =
    if !current_instrs <> [] || !raw_blocks = [] then begin
      let b = Ir.make_block ~id:!block_id ~label:!current_label ~instrs:(List.rev !current_instrs) in
      raw_blocks := b :: !raw_blocks;
      incr block_id;
      current_instrs := []
    end
  in

  let rec process = function
    | [] ->
        flush_block ();
        Ok (List.rev !raw_blocks)
    | X86_parser.LineEmpty :: rest | X86_parser.LineDirective _ :: rest
    | X86_parser.LineMarkerBegin _ :: rest | X86_parser.LineMarkerEnd :: rest ->
        process rest
    | X86_parser.LineLabel lbl :: rest ->
        if is_func_label lbl then func_name := lbl;
        if !current_instrs <> [] then flush_block ();
        current_label := lbl;
        process rest

    | X86_parser.LineInstr (mnem, ops) :: rest -> (
        match lift_instr mnem ops with
        | Error e -> Error e
        | Ok lifted ->
            List.iter (fun i -> current_instrs := i :: !current_instrs) lifted;
            let last_lifted = List.hd (List.rev lifted) in
            if is_terminator last_lifted then flush_block ();
            process rest)
  in

  let* blocks = process raw_lines in

  (* Zero-extend B32 sub-register writes (TODO item 6): widen each block before
     terminator patching so the pairs precede any appended jump/ret. *)
  let blocks = List.map Subreg_write.expand_block blocks in

  (* Patch fallthrough jumps between consecutive blocks *)
  let patched_blocks = ref [] in
  let n = List.length blocks in
  for i = 0 to n - 1 do
    let (b : Ir.basic_block) = List.nth blocks i in
    let next_id_opt = if i + 1 < n then Some (List.nth blocks (i + 1)).id else None in
    let new_instrs =
      match List.rev b.instrs with
      | [] -> (
          match next_id_opt with
          | Some next_id -> [ Ir.Jmp (Ir.BlockId next_id) ]
          | None -> [ Ir.Ret ])
      | last :: prev_rev -> (
          match last with
          | Ir.Jcc { cond; target_true; target_false = Ir.Label "__fallthrough__" } -> (
              match next_id_opt with
              | Some next_id ->
                  List.rev (Ir.Jcc { cond; target_true; target_false = Ir.BlockId next_id } :: prev_rev)
              | None ->
                  List.rev (Ir.Jcc { cond; target_true; target_false = Ir.Label "exit" } :: prev_rev))

          | _ ->
              if is_terminator last then b.instrs
              else
                match next_id_opt with
                | Some next_id -> b.instrs @ [ Ir.Jmp (Ir.BlockId next_id) ]
                | None -> b.instrs @ [ Ir.Ret ])
    in
    patched_blocks := { b with instrs = new_instrs } :: !patched_blocks
  done;

  let final_blocks = List.rev !patched_blocks in
  let detected_name =
    if is_func_label !func_name && !func_name <> default_options.function_name then !func_name
    else match final_blocks with
      | b :: _ when b.label <> "" && is_func_label b.label && b.label <> default_options.function_name -> b.label
      | _ -> options.function_name
  in
  let func = Ir.make_func ~name:detected_name ~entry_id:0 ~blocks:final_blocks in
  resolve_cfg_labels func.cfg
  |> Result.map (fun resolved_cfg -> { func with cfg = resolved_cfg })

let extract_marked_regions ?(require_markers = false) raw_lines =
  let has_markers =
    List.exists
      (function
        | X86_parser.LineMarkerBegin _ | X86_parser.LineMarkerEnd -> true
        | _ -> false)
      raw_lines
  in
  if not has_markers then
    if require_markers then []
    else [ (X86_parser.ModeUltra "main", raw_lines) ]
  else
    let regions = ref [] in
    let current_mode = ref None in
    let current_lines = ref [] in
    let last_label = ref "main" in

    List.iter
      (function
        | X86_parser.LineLabel lbl ->
            if !current_mode = None then (
              if is_func_label lbl then last_label := lbl
            ) else (
              current_lines := X86_parser.LineLabel lbl :: !current_lines
            )

        | X86_parser.LineMarkerBegin mode ->
            current_mode := Some (mode, !last_label);
            current_lines := []
        | X86_parser.LineMarkerEnd -> (
            match !current_mode with
            | Some (m, fn_lbl) ->
                regions := (m, X86_parser.LineLabel fn_lbl :: List.rev !current_lines) :: !regions;
                current_mode := None;
                current_lines := []
            | None -> ())
        | line ->
            if !current_mode <> None then
              current_lines := line :: !current_lines)

      raw_lines;

    if !regions = [] then
      [ (X86_parser.ModeUltra "main", raw_lines) ]
    else
      List.rev !regions

let lift_function ?options text =
  let* raw_lines = X86_parser.parse_lines text in
  lift_lines ?options raw_lines


