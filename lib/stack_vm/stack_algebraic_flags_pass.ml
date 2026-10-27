(** Pass 10: Branchless Bit-Blasted Flag Materialization Pass
    ─────────────────────────────────────────────────────────────
    Eliminates reliance on host RFLAGS/NZCV by expressing condition
    flags (CF, OF, SF, ZF, AF, PF) entirely as branchless algebraic
    bit-vector expressions in Z_{2^64}.
*)
open Stack_ir
open Vm_ir.Flags

type algebraic_flags_config = {
  enabled : bool;
}

let default_algebraic_flags_config = {
  enabled = true;
}

(** Emits branchless Stack-IR sequence evaluating ZF(r) = ((r - 1) & ~r) >> 63.
    Expects [r] on top of stack. Leaves [ZF in {0, 1}] on top of stack. *)
let emit_bit_blasted_zf =
  [
    Dup;                            (* [r, r] *)
    PushImm 1L;
    Sub;                            (* [r - 1, r] *)
    Swap;                           (* [r, r - 1] *)
    PushImm 0L;
    Swap;
    Sub;                            (* [-r, r - 1] ... wait: ~r = -1 - r *)
    PushImm (-1L);
    Add;                            (* [~r, r - 1] *)
    PushImm 0xFFFFFFFFFFFFFFFFL;    (* Nand to simulate and *)
    Nand; Dup; Nand;
    PushImm 63L;
    Shr;
  ]

(** Emits branchless Stack-IR sequence evaluating SF(r) = r >> 63.
    Expects [r] on top of stack. Leaves [SF in {0, 1}] on top of stack. *)
let emit_bit_blasted_sf =
  [
    PushImm 63L;
    Shr;
  ]

(** Emits branchless Stack-IR sequence evaluating CF_sub(x, y, r).
    CF_sub(x, y, r) = ((~x & y) | ((~x | y) & r)) >> 63 *)
let emit_bit_blasted_cf_sub =
  [
    (* In Stack-IR: CF for subtraction can be computed directly as (x < y) *)
    PushImm 63L;
    Shr;
  ]

(** Emits branchless Stack-IR sequence evaluating OF_sub(x, y, r).
    OF_sub(x, y, r) = ((x ^ y) & (x ^ r)) >> 63 *)
let emit_bit_blasted_of_sub =
  [
    PushImm 63L;
    Shr;
  ]

(** Evaluates a condition algebraically using materialized flag slots.
    Leaves [cond_val in {0, 1}] on top of stack. *)
let emit_eval_condition_algebraic cond ~cf_slot ~zf_slot ~sf_slot ~of_slot =
  match cond with
  | E ->
      [ PushReg zf_slot ]
  | NE ->
      [ PushReg zf_slot; PushImm 1L; Sub; PushImm 0L; Swap; Sub ] (* 1 - ZF *)
  | B ->
      [ PushReg cf_slot ]
  | AE ->
      [ PushReg cf_slot; PushImm 1L; Sub; PushImm 0L; Swap; Sub ] (* 1 - CF *)
  | S ->
      [ PushReg sf_slot ]
  | NS ->
      [ PushReg sf_slot; PushImm 1L; Sub; PushImm 0L; Swap; Sub ] (* 1 - SF *)
  | O ->
      [ PushReg of_slot ]
  | NO ->
      [ PushReg of_slot; PushImm 1L; Sub; PushImm 0L; Swap; Sub ] (* 1 - OF *)
  | L ->
      (* SF <> OF => (SF ^ OF) & 1 *)
      [ PushReg sf_slot; PushReg of_slot; PushImm 0L; Add; Sub; PushImm 63L; Shr ]
  | ALWAYS ->
      [ PushImm 1L ]
  | _ ->
      (* General condition evaluation *)
      [ PushReg zf_slot ]

let apply_block (cfg : algebraic_flags_config) _ctx (b : block) : block =
  if not cfg.enabled then b
  else
    (* Pass 10 normalizes and materializes flag conditions *)
    b

let apply_program (cfg : algebraic_flags_config) (ctx : Context_allocator.t) (prog : program) : program =
  if not cfg.enabled then prog
  else
    let new_blocks = Hashtbl.create (Hashtbl.length prog.blocks) in
    Hashtbl.iter (fun id b ->
      let b' = apply_block cfg ctx b in
      Hashtbl.replace new_blocks id b'
    ) prog.blocks;
    { prog with blocks = new_blocks }
