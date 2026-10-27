(** Pass A: Relational State Encoding Pass
    ────────────────────────────────────────
    Encodes relations between pairs of virtual context registers (rx, ry)
    using reversible Feistel round transformations:
      u = x
      v = y ^ ROL(x, k)
    with exact inverse:
      x = u
      y = v ^ ROL(u, k)
*)

open Stack_ir

type relational_config = {
  enabled : bool;
  shift_k : int;
  seed    : int64;
}

let default_relational_config seed = {
  enabled = true;
  shift_k = 29;
  seed;
}

(** Emits Stack-IR sequence computing ROL(x, k) onto the stack *)
let emit_rol ~rx ~k =
  let k_64 = Int64.of_int (k land 63) in
  let inv_k = Int64.of_int (64 - (k land 63)) in
  [
    PushReg rx;
    PushImm k_64;
    Shl;
    PushReg rx;
    PushImm inv_k;
    Shr;
    Add; (* ROL(x, k) via non-overlapping shift sum *)
  ]

(** Emits Stack-IR sequence computing y := y ^ ROL(x, k) *)
let emit_feistel_step ~rx ~ry ~k =
  let rol_ops = emit_rol ~rx ~k in
  [
    (* 1. y + ROL(x, k) *)
    PushReg ry;
  ] @ rol_ops @ [
    Add;

    (* 2. y & ROL(x, k) *)
    PushReg ry;
  ] @ rol_ops @ [
    Nand;
    Dup;
    Nand;

    (* 3. (y + ROL(x, k)) - 2*(y & ROL(x, k)) == y ^ ROL(x, k) *)
    PushImm 2L;
    Mul;
    Sub;

    (* 4. Store back to ry *)
    PopReg ry;
  ]

let emit_relational_encode ~rx ~ry ~k =
  emit_feistel_step ~rx ~ry ~k

let emit_relational_decode ~rx ~ry ~k =
  emit_feistel_step ~rx ~ry ~k

let apply_block (cfg : relational_config) _ctx (b : block) : block =
  if not cfg.enabled then b
  else
    b

let apply_program (cfg : relational_config) (ctx : Context_allocator.t) (prog : program) : program =
  if not cfg.enabled then prog
  else
    let new_blocks = Hashtbl.create (Hashtbl.length prog.blocks) in
    Hashtbl.iter (fun id b ->
      let b' = apply_block cfg ctx b in
      Hashtbl.replace new_blocks id b'
    ) prog.blocks;
    { prog with blocks = new_blocks }
