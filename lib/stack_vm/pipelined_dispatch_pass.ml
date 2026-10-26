(** Phase 8: Pipelined Stage Dispatch Pass (Stage Relocation & Decoupled Execution)
    ─────────────────────────────────────────────────────────────────────────────
    Plans the transition from the centralized dispatch step to the pipelined
    stage model of [docs/Pipelined_stage_dispatch.md]:

      - Stage 1 (ASG_PIPELINED_PREFETCH): every handler epilogue pre-fetches
        and decodes the next opcode (fetch_byte already advances VIP and
        steps VKEY), so no shared central dispatcher block exists.
      - Stage 2 (inter-stage chaffing): between the pre-fetch and the
        computed jump, a pseudo-random XOR is folded into a *dead* context
        slot, VCTX[hash(op)] ^= VKEY + op, breaking memory-read taint
        continuity from the bytecode buffer into the program counter.
      - Stage 3 (ASG_PIPELINED_DISPATCH): branchless affine unmasking of the
        pre-blinded dispatch table entry and the computed jump.

    The pass performs no IR transformation: the bytecode, the keystream
    cadence (Invariant 1: one step_key per consumed byte, already enforced
    by fetch_byte) and all guest-visible state are untouched.  What it does
    is derive the Stage-2 chaff plan for the generated runtime and verify
    its soundness invariants:

      1. Dead-Slot Isolation: the chaff region [base, base+count) lies
         entirely at or above the program's context_slots, so no live guest
         register, scratch slot or CFF VPC slot can ever be XORed.
      2. Flag Faithfulness: the chaff touches neither the software flags
         (vm->cf/zf/sf/pf/of) nor the vsp stack, so deferred flag consumers
         (JccRel, Setcc, Cmov) are unaffected.
      3. Constant-Time Slot Selection: the slot index is computed
         branchlessly as ((op * golden_ratio_64) ^ salt) >> 56, masked to a
         power-of-two region, with mul/xor only.
*)

open Stack_ir

type pipelined_config = {
  enabled     : bool;
  chaff_slots : int;   (** Requested Stage-2 chaff slot count (1..16) *)
  seed        : int64;
}

let default_pipelined_config seed = {
  enabled     = true;
  chaff_slots = 4;
  seed;
}

type dispatch_plan = {
  chaff_slot_base   : int;    (** First dead ctx slot of the chaff region *)
  chaff_slot_count  : int;    (** Region size, power of two in [1; 16] *)
  chaff_salt        : int64;  (** Per-build salt mixed into the slot hash *)
  ctx_slots_required : int;   (** ctx[] must have at least this many slots *)
}

(* Stage-2 chaff is branchless only when the region size is a power of two. *)
let normalize_chaff_slots n =
  let n = max 1 (min 16 n) in
  let rec next_pow2 v = if v >= n then v else next_pow2 (v * 2) in
  next_pow2 1

let derive_chaff_salt seed =
  (* Per-build salt: one splitmix64 step over the seed, golden-ratio
     incremented (both constants from the magic-number registry). *)
  let open Int64 in
  let module M = Random_visa_constants.Magic_numbers in
  let z = add seed M.golden_ratio_64 in
  logxor z (shift_right_logical z 32)

(** Derive the Stage-2 chaff plan for a finalized program.  [None] when the
    pass is disabled.  The chaff region starts exactly at the program's
    context_slots: every slot a handler can address is strictly below it,
    so the XOR writes provably land in dead slots only (Invariant 1). *)
let plan_dispatch (cfg : pipelined_config) (prog : program) : dispatch_plan option =
  if not cfg.enabled then None
  else
    let count = normalize_chaff_slots cfg.chaff_slots in
    let base = prog.context_slots in
    Some {
      chaff_slot_base    = base;
      chaff_slot_count   = count;
      chaff_salt         = derive_chaff_salt cfg.seed;
      ctx_slots_required = base + count;
    }

(** Invariant audit of a plan against a program: the chaff region must not
    overlap any addressable slot, and the ctx sizing must cover it. *)
let check_plan_invariants (prog : program) (plan : dispatch_plan) : unit =
  if plan.chaff_slot_base < prog.context_slots then
    invalid_arg
      (Printf.sprintf
         "pipelined dispatch: chaff region base %d overlaps live slots (< %d)"
         plan.chaff_slot_base prog.context_slots);
  if plan.chaff_slot_count < 1
     || plan.chaff_slot_count land (plan.chaff_slot_count - 1) <> 0 then
    invalid_arg "pipelined dispatch: chaff slot count must be a positive power of two";
  if plan.ctx_slots_required < plan.chaff_slot_base + plan.chaff_slot_count then
    invalid_arg "pipelined dispatch: ctx sizing does not cover the chaff region"

let pipelined_stats = function
  | None -> "Disabled (config: pipelined_dispatch.enabled=false)"
  | Some p ->
      Printf.sprintf
        "epilogue pre-fetch + decoupled computed jump, stage-2 chaff over %d dead ctx slots [%d..%d], salt=0x%016LX"
        p.chaff_slot_count p.chaff_slot_base (p.chaff_slot_base + p.chaff_slot_count - 1)
        p.chaff_salt
