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
let width_mask = function
  | Register.B8 -> 0xFFL
  | Register.B16 -> 0xFFFFL
  | Register.B32 -> 0xFFFFFFFFL
  | Register.B64 -> -1L

let width_bits = Register.width_to_bits

let mov_reg dst src = Ir.Mov { dst = Ir.Reg dst; src = Ir.Reg src }

let canonicalize_reg ~signed r width =
  if signed then
    let shift = Int64.of_int (64 - width_bits width) in
    [ Ir.Alu { op = Ir.Shl; dst = r; src1 = Ir.Reg r; src2 = Ir.Imm shift; set_flags = false };
      Ir.Alu { op = Ir.Sar; dst = r; src1 = Ir.Reg r; src2 = Ir.Imm shift; set_flags = false } ]
  else
    [ Ir.Alu { op = Ir.And; dst = r; src1 = Ir.Reg r; src2 = Ir.Imm (width_mask width); set_flags = false } ]

let sign_extend_bits r bits =
  let shift = 64 - bits in
  if shift = 0 then []
  else
    [ Ir.Alu { op = Ir.Shl; dst = r; src1 = Ir.Reg r; src2 = Ir.Imm (Int64.of_int shift); set_flags = false };
      Ir.Alu { op = Ir.Sar; dst = r; src1 = Ir.Reg r; src2 = Ir.Imm (Int64.of_int shift); set_flags = false } ]

let mask_reg r width =
  [ Ir.Alu { op = Ir.And; dst = r; src1 = Ir.Reg r; src2 = Ir.Imm (width_mask width); set_flags = false } ]

let load_dividend_parts width =
  let low = Register.vx19 in
  let high = Register.vx20 in
  match width with
  | Register.B8 ->
      [ Ir.Mov { dst = Ir.Reg low; src = Ir.Reg Register.rax };
        Ir.Alu { op = Ir.And; dst = low; src1 = Ir.Reg low; src2 = Ir.Imm 0xFFL; set_flags = false };
        Ir.Mov { dst = Ir.Reg high; src = Ir.Reg Register.rax };
        Ir.Alu { op = Ir.And; dst = high; src1 = Ir.Reg high; src2 = Ir.Imm 0xFFFFL; set_flags = false };
        Ir.Alu { op = Ir.Shr; dst = high; src1 = Ir.Reg high; src2 = Ir.Imm 8L; set_flags = false } ]
  | _ ->
      [ Ir.Mov { dst = Ir.Reg low; src = Ir.Reg Register.rax };
        Ir.Mov { dst = Ir.Reg high; src = Ir.Reg Register.rdx } ]

let lift_x86_div_narrow ~signed width divisor =
  let* ir_div = to_ir_operand divisor in
  let div_op = if signed then Ir.Idiv else Ir.Div in
  let divisor_reg = Register.vx18 in
  let low_reg = Register.vx19 in
  let high_reg = Register.vx20 in
  let dividend_reg = Register.vx21 in
  let quotient_reg = Register.vx22 in
  let remainder_reg = Register.vx23 in
  let product_reg = Register.vx24 in
  let bits = width_bits width in
  let pre =
    [ Ir.Mov { dst = Ir.Reg divisor_reg; src = ir_div } ]
    @ canonicalize_reg ~signed divisor_reg width
    @ load_dividend_parts width
    @ mask_reg low_reg width
    @ mask_reg high_reg width
  in
  let build_dividend =
    [ mov_reg dividend_reg high_reg;
      Ir.Alu { op = Ir.Shl; dst = dividend_reg; src1 = Ir.Reg dividend_reg; src2 = Ir.Imm (Int64.of_int bits); set_flags = false };
      Ir.Alu { op = Ir.Or; dst = dividend_reg; src1 = Ir.Reg dividend_reg; src2 = Ir.Reg low_reg; set_flags = false } ]
    @ (if signed then sign_extend_bits dividend_reg (2 * bits) else [])
  in
  let divide =
    [ mov_reg quotient_reg dividend_reg;
      Ir.Alu { op = div_op; dst = quotient_reg; src1 = Ir.Reg quotient_reg; src2 = Ir.Reg divisor_reg; set_flags = false };
      mov_reg remainder_reg dividend_reg;
      mov_reg product_reg quotient_reg;
      Ir.Alu { op = Ir.Imul; dst = product_reg; src1 = Ir.Reg product_reg; src2 = Ir.Reg divisor_reg; set_flags = false };
      Ir.Alu { op = Ir.Sub; dst = remainder_reg; src1 = Ir.Reg remainder_reg; src2 = Ir.Reg product_reg; set_flags = false } ]
  in
  let write_outputs =
    match width with
    | Register.B8 ->
        let ax = Register.with_width Register.rax Register.B16 in
        let quotient_byte = Register.vx25 in
        let high_byte = Register.vx24 in
        [ Ir.Mov { dst = Ir.Reg quotient_byte; src = Ir.Reg quotient_reg };
          Ir.Alu { op = Ir.And; dst = quotient_byte; src1 = Ir.Reg quotient_byte; src2 = Ir.Imm 0xFFL; set_flags = false };
          Ir.Mov { dst = Ir.Reg ax; src = Ir.Reg quotient_byte };
          Ir.Mov { dst = Ir.Reg high_byte; src = Ir.Reg remainder_reg };
          Ir.Alu { op = Ir.And; dst = high_byte; src1 = Ir.Reg high_byte; src2 = Ir.Imm 0xFFL; set_flags = false };
          Ir.Alu { op = Ir.Shl; dst = high_byte; src1 = Ir.Reg high_byte; src2 = Ir.Imm 8L; set_flags = false };
          Ir.Alu { op = Ir.Or; dst = ax; src1 = Ir.Reg ax; src2 = Ir.Reg high_byte; set_flags = false } ]
    | Register.B16 ->
        let ax = Register.with_width Register.rax Register.B16 in
        let dx = Register.with_width Register.rdx Register.B16 in
        [ Ir.Mov { dst = Ir.Reg ax; src = Ir.Reg quotient_reg };
          Ir.Mov { dst = Ir.Reg dx; src = Ir.Reg remainder_reg } ]
    | Register.B32 ->
        let eax = Register.with_width Register.rax Register.B32 in
        let edx = Register.with_width Register.rdx Register.B32 in
        [ Ir.Mov { dst = Ir.Reg eax; src = Ir.Reg quotient_reg };
          Ir.Mov { dst = Ir.Reg edx; src = Ir.Reg remainder_reg } ]
    | Register.B64 -> []
  in
  Ok (pre @ build_dividend @ divide @ write_outputs)

let lift_x86_div64 ~signed divisor =
  let* ir_div = to_ir_operand divisor in
  let d_reg = Register.vx18 in
  let rem_reg = Register.vx19 in
  let quo_reg = Register.vx20 in
  let tmp_rem = Register.vx21 in
  let tmp_bit = Register.vx22 in
  let sign_q = Register.vx23 in
  let sign_r = Register.vx24 in
  let zero_check = Register.vx25 in
  let tmp_inv = Register.vtmp3 in
  let div_op = if signed then Ir.Idiv else Ir.Div in

  let init_instrs =
    [ Ir.Mov { dst = Ir.Reg d_reg; src = ir_div };
      Ir.Mov { dst = Ir.Reg rem_reg; src = Ir.Reg Register.rdx };
      Ir.Mov { dst = Ir.Reg quo_reg; src = Ir.Reg Register.rax };
      (* Trigger fault if division by zero *)
      Ir.Alu { op = div_op; dst = zero_check; src1 = Ir.Imm 0L; src2 = Ir.Reg d_reg; set_flags = false } ]
  in

  let sign_prep =
    if signed then
      [ (* sign_r = rem_reg >> 63 *)
        Ir.Mov { dst = Ir.Reg sign_r; src = Ir.Reg rem_reg };
        Ir.Alu { op = Ir.Shr; dst = sign_r; src1 = Ir.Reg sign_r; src2 = Ir.Imm 63L; set_flags = false };
        (* sign_q = (rem_reg ^ d_reg) >> 63 *)
        Ir.Mov { dst = Ir.Reg sign_q; src = Ir.Reg rem_reg };
        Ir.Alu { op = Ir.Xor; dst = sign_q; src1 = Ir.Reg sign_q; src2 = Ir.Reg d_reg; set_flags = false };
        Ir.Alu { op = Ir.Shr; dst = sign_q; src1 = Ir.Reg sign_q; src2 = Ir.Imm 63L; set_flags = false };

        (* If dividend is negative (sign_r != 0), negate 128-bit (rem_reg : quo_reg) *)
        (* tmp_bit = not quo_reg + 1 *)
        Ir.Unary { op = Ir.Not; dst = tmp_bit; src = Ir.Reg quo_reg; set_flags = false };
        Ir.Alu { op = Ir.Add; dst = tmp_bit; src1 = Ir.Reg tmp_bit; src2 = Ir.Imm 1L; set_flags = false };
        (* carry in tmp_rem: 1 if tmp_bit == 0, else 0 *)
        Ir.Mov { dst = Ir.Reg tmp_rem; src = Ir.Imm 0L };
        Ir.Mov { dst = Ir.Reg tmp_inv; src = Ir.Imm 1L };
        Ir.Cmp { src1 = Ir.Reg tmp_bit; src2 = Ir.Imm 0L };
        Ir.Cmov { cond = Flags.E; dst = tmp_rem; src = Ir.Reg tmp_inv };
        (* not rem_reg + carry *)
        Ir.Unary { op = Ir.Not; dst = tmp_inv; src = Ir.Reg rem_reg; set_flags = false };
        Ir.Alu { op = Ir.Add; dst = tmp_inv; src1 = Ir.Reg tmp_inv; src2 = Ir.Reg tmp_rem; set_flags = false };
        (* Conditionally apply negation if sign_r != 0 *)
        Ir.Cmp { src1 = Ir.Reg sign_r; src2 = Ir.Imm 0L };
        Ir.Cmov { cond = Flags.NE; dst = quo_reg; src = Ir.Reg tmp_bit };
        Ir.Cmp { src1 = Ir.Reg sign_r; src2 = Ir.Imm 0L };
        Ir.Cmov { cond = Flags.NE; dst = rem_reg; src = Ir.Reg tmp_inv };

        (* If divisor is negative (d_reg < 0), negate d_reg *)
        Ir.Unary { op = Ir.Neg; dst = tmp_bit; src = Ir.Reg d_reg; set_flags = false };
        Ir.Cmp { src1 = Ir.Reg d_reg; src2 = Ir.Imm 0L };
        Ir.Cmov { cond = Flags.L; dst = d_reg; src = Ir.Reg tmp_bit } ]
    else []
  in

  let div_steps = ref [] in
  for _ = 0 to 63 do
    let step =
      [ (* 1. tmp_bit = (quo_reg >> 63) & 1 *)
        Ir.Mov { dst = Ir.Reg tmp_bit; src = Ir.Reg quo_reg };
        Ir.Alu { op = Ir.Shr; dst = tmp_bit; src1 = Ir.Reg tmp_bit; src2 = Ir.Imm 63L; set_flags = false };

        (* 2. quo_reg = quo_reg << 1 *)
        Ir.Alu { op = Ir.Shl; dst = quo_reg; src1 = Ir.Reg quo_reg; src2 = Ir.Imm 1L; set_flags = false };

        (* 3. rem_reg = (rem_reg << 1) | tmp_bit *)
        Ir.Alu { op = Ir.Shl; dst = rem_reg; src1 = Ir.Reg rem_reg; src2 = Ir.Imm 1L; set_flags = false };
        Ir.Alu { op = Ir.Or; dst = rem_reg; src1 = Ir.Reg rem_reg; src2 = Ir.Reg tmp_bit; set_flags = false };

        (* 4. tmp_rem = rem_reg - d_reg *)
        Ir.Mov { dst = Ir.Reg tmp_rem; src = Ir.Reg rem_reg };
        Ir.Alu { op = Ir.Sub; dst = tmp_rem; src1 = Ir.Reg tmp_rem; src2 = Ir.Reg d_reg; set_flags = false };

        (* 5. Prepare quo_reg | 1 in tmp_bit *)
        Ir.Mov { dst = Ir.Reg tmp_bit; src = Ir.Reg quo_reg };
        Ir.Alu { op = Ir.Or; dst = tmp_bit; src1 = Ir.Reg tmp_bit; src2 = Ir.Imm 1L; set_flags = false };

        (* 6. Atomic cmp + cmov for quo_reg *)
        Ir.Cmp { src1 = Ir.Reg rem_reg; src2 = Ir.Reg d_reg };
        Ir.Cmov { cond = Flags.AE; dst = quo_reg; src = Ir.Reg tmp_bit };

        (* 7. Atomic cmp + cmov for rem_reg *)
        Ir.Cmp { src1 = Ir.Reg rem_reg; src2 = Ir.Reg d_reg };
        Ir.Cmov { cond = Flags.AE; dst = rem_reg; src = Ir.Reg tmp_rem } ]
    in
    div_steps := !div_steps @ step
  done;

  let sign_post =
    if signed then
      [ (* If sign_q != 0, quo_reg = -quo_reg *)
        Ir.Unary { op = Ir.Neg; dst = tmp_bit; src = Ir.Reg quo_reg; set_flags = false };
        Ir.Cmp { src1 = Ir.Reg sign_q; src2 = Ir.Imm 0L };
        Ir.Cmov { cond = Flags.NE; dst = quo_reg; src = Ir.Reg tmp_bit };

        (* If sign_r != 0, rem_reg = -rem_reg *)
        Ir.Unary { op = Ir.Neg; dst = tmp_bit; src = Ir.Reg rem_reg; set_flags = false };
        Ir.Cmp { src1 = Ir.Reg sign_r; src2 = Ir.Imm 0L };
        Ir.Cmov { cond = Flags.NE; dst = rem_reg; src = Ir.Reg tmp_bit } ]
    else []
  in

  let out_instrs =
    [ Ir.Mov { dst = Ir.Reg Register.rax; src = Ir.Reg quo_reg };
      Ir.Mov { dst = Ir.Reg Register.rdx; src = Ir.Reg rem_reg } ]
  in
  Ok (init_instrs @ sign_prep @ !div_steps @ sign_post @ out_instrs)

let lift_x86_div ~signed divisor =
  let width_of = function
    | X86_parser.OpReg r -> Register.get_width r
    | X86_parser.OpMem m -> m.width
    | _ -> Register.B64
  in
  match width_of divisor with
  | Register.B64 -> lift_x86_div64 ~signed divisor
  | (Register.B8 | Register.B16 | Register.B32) as width -> lift_x86_div_narrow ~signed width divisor

let lift_x86_mul_narrow ~signed width divisor =
  let* ir_div = to_ir_operand divisor in
  let operand = Register.vx18 in
  let accumulator = Register.vx19 in
  let product = Register.vx20 in
  let high = Register.vx21 in
  let pre =
    [ Ir.Mov { dst = Ir.Reg operand; src = ir_div } ]
    @ canonicalize_reg ~signed operand width
    @ [ Ir.Mov { dst = Ir.Reg accumulator; src = Ir.Reg Register.rax } ]
    @ canonicalize_reg ~signed accumulator width
  in
  let product_instrs =
    [ mov_reg product accumulator;
      Ir.Alu { op = Ir.Imul; dst = product; src1 = Ir.Reg product; src2 = Ir.Reg operand; set_flags = false } ]
  in
  let outputs =
    match width with
    | Register.B8 ->
        let ax = Register.with_width Register.rax Register.B16 in
        [ Ir.Mov { dst = Ir.Reg ax; src = Ir.Reg product } ]
    | Register.B16 ->
        let ax = Register.with_width Register.rax Register.B16 in
        let dx = Register.with_width Register.rdx Register.B16 in
        [ Ir.Mov { dst = Ir.Reg ax; src = Ir.Reg product };
          Ir.Mov { dst = Ir.Reg high; src = Ir.Reg product };
          Ir.Alu { op = Ir.Shr; dst = high; src1 = Ir.Reg high; src2 = Ir.Imm 16L; set_flags = false };
          Ir.Mov { dst = Ir.Reg dx; src = Ir.Reg high } ]
    | Register.B32 ->
        let eax = Register.with_width Register.rax Register.B32 in
        let edx = Register.with_width Register.rdx Register.B32 in
        [ Ir.Mov { dst = Ir.Reg eax; src = Ir.Reg product };
          Ir.Mov { dst = Ir.Reg high; src = Ir.Reg product };
          Ir.Alu { op = Ir.Shr; dst = high; src1 = Ir.Reg high; src2 = Ir.Imm 32L; set_flags = false };
          Ir.Mov { dst = Ir.Reg edx; src = Ir.Reg high } ]
    | Register.B64 -> []
  in
  Ok (pre @ product_instrs @ outputs)

let lift_x86_mul64 ~signed divisor =
  let* ir_div = to_ir_operand divisor in
  let a = Register.vx18 in
  let b = Register.vx19 in
  let product_low = Register.vx20 in
  let product_high = Register.vx21 in
  let product = Register.vx22 in
  let piece_low = Register.vx23 in
  let piece_high = Register.vx24 in
  let limb_a = Register.vx25 in
  let limb_b = Register.vx26 in
  let extract_limb base idx dst =
    [ Ir.Mov { dst = Ir.Reg dst; src = Ir.Reg base } ]
    @ (if idx = 0 then [] else [ Ir.Alu { op = Ir.Shr; dst; src1 = Ir.Reg dst; src2 = Ir.Imm (Int64.of_int (16 * idx)); set_flags = false } ])
    @ [ Ir.Alu { op = Ir.And; dst; src1 = Ir.Reg dst; src2 = Ir.Imm 0xFFFFL; set_flags = false } ]
  in
  let add_piece p0 p1 piece shift =
    let target, offset, other, propagate =
      if shift < 64 then p0, shift, p1, true else p1, shift - 64, p0, false
    in
    let shifted =
      if offset = 0 then []
      else [ Ir.Alu { op = Ir.Shl; dst = piece; src1 = Ir.Reg piece; src2 = Ir.Imm (Int64.of_int offset); set_flags = false } ]
    in
    let add =
      [ Ir.Mov { dst = Ir.Reg limb_a; src = Ir.Reg target };
        Ir.Mov { dst = Ir.Reg product; src = Ir.Reg piece };
        Ir.Alu { op = Ir.Add; dst = target; src1 = Ir.Reg target; src2 = Ir.Reg piece; set_flags = false } ]
    in
    let carry =
      if not propagate then []
      else
        [ Ir.Alu { op = Ir.And; dst = limb_b; src1 = Ir.Reg limb_a; src2 = Ir.Reg piece; set_flags = false };
          Ir.Alu { op = Ir.Or; dst = piece; src1 = Ir.Reg limb_a; src2 = Ir.Reg piece; set_flags = false };
          Ir.Unary { op = Ir.Not; dst = product; src = Ir.Reg target; set_flags = false };
          Ir.Alu { op = Ir.And; dst = piece; src1 = Ir.Reg piece; src2 = Ir.Reg product; set_flags = false };
          Ir.Alu { op = Ir.Or; dst = limb_b; src1 = Ir.Reg limb_b; src2 = Ir.Reg piece; set_flags = false };
          Ir.Alu { op = Ir.Shr; dst = limb_b; src1 = Ir.Reg limb_b; src2 = Ir.Imm 63L; set_flags = false };
          Ir.Alu { op = Ir.Add; dst = other; src1 = Ir.Reg other; src2 = Ir.Reg limb_b; set_flags = false } ]
    in
    shifted @ add @ carry
  in
  let pre = [ Ir.Mov { dst = Ir.Reg a; src = Ir.Reg Register.rax }; Ir.Mov { dst = Ir.Reg b; src = ir_div } ] in
  let product_instrs = ref [ Ir.Mov { dst = Ir.Reg product_low; src = Ir.Imm 0L }; Ir.Mov { dst = Ir.Reg product_high; src = Ir.Imm 0L } ] in
  for i = 0 to 3 do
    for j = 0 to 3 do
      let shift = 16 * (i + j) in
      let term =
        [ Ir.Mov { dst = Ir.Reg limb_a; src = Ir.Reg a } ]
        @ extract_limb limb_a i limb_a
        @ [ Ir.Mov { dst = Ir.Reg limb_b; src = Ir.Reg b } ]
        @ extract_limb limb_b j limb_b
        @ [ Ir.Alu { op = Ir.Imul; dst = product; src1 = Ir.Reg limb_a; src2 = Ir.Reg limb_b; set_flags = false };
          Ir.Alu { op = Ir.And; dst = piece_low; src1 = Ir.Reg product; src2 = Ir.Imm 0xFFFFL; set_flags = false };
          Ir.Alu { op = Ir.Shr; dst = piece_high; src1 = Ir.Reg product; src2 = Ir.Imm 16L; set_flags = false } ]
        @ add_piece product_low product_high piece_low shift
        @ add_piece product_low product_high piece_high (shift + 16)
      in
      product_instrs := !product_instrs @ term
    done
  done;
  let correction =
    if signed then
      [ Ir.Mov { dst = Ir.Reg piece_low; src = Ir.Reg a };
        Ir.Alu { op = Ir.Shr; dst = piece_low; src1 = Ir.Reg piece_low; src2 = Ir.Imm 63L; set_flags = false };
        Ir.Unary { op = Ir.Neg; dst = piece_low; src = Ir.Reg piece_low; set_flags = false };
        Ir.Alu { op = Ir.And; dst = piece_low; src1 = Ir.Reg piece_low; src2 = Ir.Reg b; set_flags = false };
        Ir.Alu { op = Ir.Sub; dst = product_high; src1 = Ir.Reg product_high; src2 = Ir.Reg piece_low; set_flags = false };
        Ir.Mov { dst = Ir.Reg piece_high; src = Ir.Reg b };
        Ir.Alu { op = Ir.Shr; dst = piece_high; src1 = Ir.Reg piece_high; src2 = Ir.Imm 63L; set_flags = false };
        Ir.Unary { op = Ir.Neg; dst = piece_high; src = Ir.Reg piece_high; set_flags = false };
        Ir.Alu { op = Ir.And; dst = piece_high; src1 = Ir.Reg piece_high; src2 = Ir.Reg a; set_flags = false };
        Ir.Alu { op = Ir.Sub; dst = product_high; src1 = Ir.Reg product_high; src2 = Ir.Reg piece_high; set_flags = false } ]
    else []
  in
  let outputs =
    [ Ir.Mov { dst = Ir.Reg Register.rax; src = Ir.Reg product_low };
      Ir.Mov { dst = Ir.Reg Register.rdx; src = Ir.Reg product_high } ]
  in
  Ok (pre @ !product_instrs @ correction @ outputs)

let lift_x86_mul_one ~signed divisor =
  let width_of = function
    | X86_parser.OpReg r -> Register.get_width r
    | X86_parser.OpMem m -> m.width
    | _ -> Register.B64
  in
  match width_of divisor with
  | Register.B64 -> lift_x86_mul64 ~signed divisor
  | (Register.B8 | Register.B16 | Register.B32) as width -> lift_x86_mul_narrow ~signed width divisor

let ir_mem_of_raw (m : X86_parser.raw_mem) : Ir.mem_ref =
  { base = m.base; index = m.index; disp = m.disp; width = m.width; is_signed = false }

let vector_reg_index = function
  | X86_parser.OpReg (Register.Fpr (i, _)) -> Some (i mod 32)
  | _ -> None

let vector_bits mnem = if String.length mnem > 0 && mnem.[0] = 'v' then 256 else 128

let vector_move_mnemonic = function
  | "movaps" | "movups" | "movdqa" | "movdqu"
  | "vmovaps" | "vmovups" | "vmovdqa" | "vmovdqu" -> true
  | _ -> false

let vector_op_of_mnemonic = function
  | "paddb" | "vpaddb" -> Some (Ir.Vadd, Ir.VInt, 8)
  | "paddw" | "vpaddw" -> Some (Ir.Vadd, Ir.VInt, 16)
  | "paddd" | "vpaddd" -> Some (Ir.Vadd, Ir.VInt, 32)
  | "paddq" | "vpaddq" -> Some (Ir.Vadd, Ir.VInt, 64)
  | "psubb" | "vpsubb" -> Some (Ir.Vsub, Ir.VInt, 8)
  | "psubw" | "vpsubw" -> Some (Ir.Vsub, Ir.VInt, 16)
  | "psubd" | "vpsubd" -> Some (Ir.Vsub, Ir.VInt, 32)
  | "psubq" | "vpsubq" -> Some (Ir.Vsub, Ir.VInt, 64)
  | "pand" | "vpand" -> Some (Ir.Vand, Ir.VInt, 64)
  | "por" | "vpor" -> Some (Ir.Vor, Ir.VInt, 64)
  | "pxor" | "vpxor" -> Some (Ir.Vxor, Ir.VInt, 64)
  | "addps" | "vaddps" -> Some (Ir.Vadd, Ir.VF32, 32)
  | "addpd" | "vaddpd" -> Some (Ir.Vadd, Ir.VF64, 64)
  | "subps" | "vsubps" -> Some (Ir.Vsub, Ir.VF32, 32)
  | "subpd" | "vsubpd" -> Some (Ir.Vsub, Ir.VF64, 64)
  | "mulps" | "vmulps" -> Some (Ir.Vmul, Ir.VF32, 32)
  | "mulpd" | "vmulpd" -> Some (Ir.Vmul, Ir.VF64, 64)
  | "andps" | "vandps" | "andpd" | "vandpd" -> Some (Ir.Vand, Ir.VInt, 64)
  | "orps" | "vorps" | "orpd" | "vorpd" -> Some (Ir.Vor, Ir.VInt, 64)
  | "xorps" | "vxorps" | "xorpd" | "vxorpd" -> Some (Ir.Vxor, Ir.VInt, 64)
  | _ -> None

let lift_vector_move mnem dst src =
  let bits = vector_bits mnem in
  match dst, src with
  | X86_parser.OpReg _, X86_parser.OpReg _ -> (
      match vector_reg_index dst, vector_reg_index src with
      | Some di, Some si -> Ok [ Ir.Vec_mov { dst = di; src = si; bits } ]
      | _ -> Error "vector move requires vector registers")
  | X86_parser.OpReg _, X86_parser.OpMem m -> (
      match vector_reg_index dst with
      | Some di -> Ok [ Ir.Vec_load { dst = di; addr = ir_mem_of_raw m; bits } ]
      | None -> Error "vector load destination must be a vector register")
  | X86_parser.OpMem m, X86_parser.OpReg _ -> (
      match vector_reg_index src with
      | Some si -> Ok [ Ir.Vec_store { src = si; addr = ir_mem_of_raw m; bits } ]
      | None -> Error "vector store source must be a vector register")
  | _ -> Error "invalid vector move operands"

let lift_vector_binop mnem ops =
  match vector_op_of_mnemonic mnem with
  | None -> Error "unsupported vector operation"
  | Some (op, elem, lane_bits) ->
      let bits = vector_bits mnem in
      let get_index = function
        | X86_parser.OpReg r -> vector_reg_index (X86_parser.OpReg r)
        | _ -> None
      in
      (match ops with
      | [dst; src] -> (
          match get_index dst, get_index src with
          | Some di, Some si -> Ok [ Ir.Vec_binop { op; elem; dst = di; src1 = di; src2 = si; bits; lane_bits } ]
          | _ -> Error "vector binary operation requires vector registers")
      | [dst; src1; src2] -> (
          match get_index dst, get_index src1, get_index src2 with
          | Some di, Some s1, Some s2 -> Ok [ Ir.Vec_binop { op; elem; dst = di; src1 = s1; src2 = s2; bits; lane_bits } ]
          | _ -> Error "vector binary operation requires vector registers")
      | _ -> Error "invalid vector binary operation operands")

let lift_instr mnem ops =
  match mnem, ops with
  | ("nop" | ".ascii" | ".asciz" | ".string" | ".byte" | ".p2align" | ".align"), _ -> Ok [ Ir.Nop ]
  | "ret", [] -> Ok [ Ir.Ret ]
  | "vm_enter", [] -> Ok [ Ir.Vm_enter ]
  | "vm_exit", [] -> Ok [ Ir.Vm_exit ]
  | ("vzeroupper" | "vzeroall"), [] -> Ok [ Ir.Nop ]
  | mnem, [ dst; src ] when vector_move_mnemonic mnem -> lift_vector_move mnem dst src
  | mnem, ops
    when (List.length ops = 2 || List.length ops = 3)
         && (match vector_op_of_mnemonic mnem with Some _ -> true | None -> false) ->
      lift_vector_binop mnem ops

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
  | ("cdq" | "cltd"), [] ->
      Ok
        [ Ir.Mov { dst = Ir.Reg Register.rdx; src = Ir.Reg Register.rax };
          Ir.Alu { op = Ir.Shr; dst = Register.rdx; src1 = Ir.Reg Register.rdx; src2 = Ir.Imm 31L; set_flags = false };
          Ir.Unary { op = Ir.Neg; dst = Register.rdx; src = Ir.Reg Register.rdx; set_flags = false } ]
  | ("cqo" | "cqto"), [] ->
      Ok
        [ Ir.Mov { dst = Ir.Reg Register.rdx; src = Ir.Reg Register.rax };
          Ir.Alu { op = Ir.Shr; dst = Register.rdx; src1 = Ir.Reg Register.rdx; src2 = Ir.Imm 63L; set_flags = false };
          Ir.Unary { op = Ir.Neg; dst = Register.rdx; src = Ir.Reg Register.rdx; set_flags = false } ]
  | "cwd", [] ->
      Ok
        [ Ir.Mov { dst = Ir.Reg Register.rdx; src = Ir.Reg Register.rax };
          Ir.Alu { op = Ir.And; dst = Register.rdx; src1 = Ir.Reg Register.rdx; src2 = Ir.Imm 0xFFFFL; set_flags = false };
          Ir.Alu { op = Ir.Shr; dst = Register.rdx; src1 = Ir.Reg Register.rdx; src2 = Ir.Imm 15L; set_flags = false };
          Ir.Unary { op = Ir.Neg; dst = Register.rdx; src = Ir.Reg Register.rdx; set_flags = false } ]
  | (* cdqe/cltq sign-extend eax into rax: exact at B64 even with a stale
       upper half, because both shifts displace the stale bits. *)
    ("cdqe" | "cltq"), [] ->
      Ok
        [ Ir.Alu { op = Ir.Shl; dst = Register.rax; src1 = Ir.Reg Register.rax; src2 = Ir.Imm 32L; set_flags = false };
          Ir.Alu { op = Ir.Sar; dst = Register.rax; src1 = Ir.Reg Register.rax; src2 = Ir.Imm 32L; set_flags = false } ]
  | ("mul" | "imul"), [ divisor ] ->
      lift_x86_mul_one ~signed:(mnem = "imul") divisor
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
  let label_is_new = ref true in
  let current_instrs = ref [] in
  let raw_blocks = ref [] in

  let flush_block () =
    if !current_instrs <> [] || !raw_blocks = [] then begin
      let b = Ir.make_block ~id:!block_id ~label:!current_label ~instrs:(List.rev !current_instrs) in
      raw_blocks := b :: !raw_blocks;
      incr block_id;
      current_instrs := [];
      label_is_new := false
    end else if !label_is_new && !current_label <> "" && !current_label <> options.function_name then begin
      let b = Ir.make_block ~id:!block_id ~label:!current_label ~instrs:[ Ir.Ret ] in
      raw_blocks := b :: !raw_blocks;
      incr block_id;
      current_instrs := [];
      label_is_new := false
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
        label_is_new := true;
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


