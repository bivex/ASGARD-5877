open Ir

(* Sub-register write semantics reconciliation (TODO.md item 6).

   Both x86-64 and ARM64 zero the upper 32 bits of the backing register
   when an instruction writes the 32-bit view (`mov eax, ..` / `add w0, ..`).
   The native VM is width-blind: handlers always operate on the full 64-bit
   vreg slot, so a B32 write leaves stale upper bits behind and later
   full-width reads diverge from the reference evaluator (which models the
   truncation exactly in [Vm_eval.set_reg]).

   This pass restores one shared instruction stream for both machines:
   after every GPR write at width B32 it appends a flag-free
   `shl 32 / shr 32` pair at B64 width, executed by the existing
   OP_SHL_RI / OP_SHR_RI handlers.  In the evaluator the pair is a no-op
   ([set_reg] already truncated on the B32 write); in the native VM it
   performs the zeroing the ISA would have done.  Only CMP handlers write
   flags, so the pairs cannot clobber condition codes.

   Deliberately excluded: B8/B16 writes (still merge semantics, unmodeled
   in the width-blind VM), [Fp_conv] and [Atomic_mem] (the evaluator no-ops
   them, so a pair would alter evaluator state on an unmodeled path), and
   [Cmov] on the false path is accepted: compilers treat the upper half
   after a sub-register write as undefined and never rely on it surviving.
   Vregs and FPRs never appear at B32 from the lifters, and are filtered
   out for safety. *)

(* GPRs written by an instruction, at the width the ISA assigns to the
   write.  Instructions not listed (stores, branches, flag writers) do not
   write registers. *)
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
  (* x86 setcc writes 8 bits (merge) and is filtered out by [is_b32_gpr];
     arm64 cset writes a W register (B32) and IS zero-extended, matching
     the hardware. *)
  | Setcc { dst = Reg d; _ } -> [ d ]
  | Setcc _ -> []
  | Load_symbol { dst; _ } -> [ dst ]
  | _ -> []

let is_b32_gpr r =
  match r with Register.Gpr (_, Register.B32) -> true | _ -> false

let zext_pair r =
  let r64 = Register.with_width r Register.B64 in
  [ Alu { op = Shl; dst = r64; src1 = Reg r64; src2 = Imm 32L; set_flags = false };
    Alu { op = Shr; dst = r64; src1 = Reg r64; src2 = Imm 32L; set_flags = false } ]

let expand_instr i =
  match List.filter is_b32_gpr (written_gprs i) with
  | [] -> [ i ]
  | dsts -> i :: List.concat_map zext_pair dsts

let expand_block (b : basic_block) : basic_block =
  { b with instrs = List.concat_map expand_instr b.instrs }

let expand_cfg (c : cfg) : cfg =
  let blocks = Hashtbl.create (Hashtbl.length c.blocks) in
  Hashtbl.iter (fun id b -> Hashtbl.replace blocks id (expand_block b)) c.blocks;
  { c with blocks }

let expand_func (f : func) : func = { f with cfg = expand_cfg f.cfg }
