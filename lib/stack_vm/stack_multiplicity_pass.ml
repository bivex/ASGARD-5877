(** Phase 2a: Stack-VM Handler Multiplicity & Metamorphic Synthesis Pass
    ───────────────────────────────────────────────────────────────────
    Expands eligible stack operations into longer, semantically identical
    instruction sequences (Swap, Dup, Rot, PushReg).

    By breaking the 1:1 mapping between high-level instruction semantics
    and fixed handler patterns, this pass prevents dynamic trace-profiling
    of stable instruction spans.

    [cfg.rate] is the honest expansion probability: the fraction of
    eligible operations that is replaced by a non-trivial variant.  An
    ineligible operation is never touched and consumes no RNG draws.

    Soundness Invariants:
      1. Register Value Faithfulness: PushReg expansions only write back
         the value they just read (ctx[r] := ctx[r]), so statically
         tracked context values (e.g. KeyFeedback scheduling) never
         diverge.  No other expansion writes a context slot at all.
      2. Exact Net Stack Delta: Every metamorphic expansion preserves the
         exact net stack delta and final stack order of the target
         operation.  Depth preconditions never exceed what the original
         operation itself already requires (no Rot-based expansions of
         shallow-stack ops).
      3. Strict Flag Neutrality: Expansions use only flag-neutral
         primitives (PushReg, PopReg, Swap, Dup, Rot), regardless of
         flag liveness.
*)

open Stack_ir
open Random_visa_constants.Magic_numbers

type multiplicity_config = {
  enabled : bool;
  rate    : int;   (** Expansion probability (0..100) per eligible operation *)
  seed    : int64;
}

let default_multiplicity_config seed = {
  enabled = true;
  rate    = 30;
  seed;
}

let splitmix64 s =
  let open Int64 in
  let s = add s golden_ratio_64 in
  let z = s in
  let z = mul (logxor z (shift_right_logical z 30)) splitmix64_gamma in
  let z = mul (logxor z (shift_right_logical z 27)) splitmix64_mix in
  let z = logxor z (shift_right_logical z 31) in
  (s, z)

type rng_state = { mutable state : int64 }

let make_rng seed = { state = seed }

let next_int64 rng =
  let s, z = splitmix64 rng.state in
  rng.state <- s;
  z

let next_int rng n =
  if n <= 1 then 0
  else
    let v = Int64.to_int (Int64.logand (next_int64 rng) 0x7FFFFFFFL) in
    v mod n

let maybe rng prob = next_int rng 100 < prob

(** Metamorphic variants for eligible Stack_ir operations.  Each variant
    list is semantically identical to the original operation:

      - Swap:   swap is an involution, so swap·swap·swap = swap.
      - Dup:    the two trailing swaps cancel above the fresh copy.
      - Rot:    rot cycles the top three with order 3, so rot^4 = rot.
      - PushReg r: the trailing PopReg writes ctx[r] back unchanged
        (either immediately, or through the duplicated copy).
    All primitives are flag-neutral; none grows the stack beyond the
    depth the original operation itself requires. *)
let expand_op rng = function
  | Swap ->
      [ Swap; Swap; Swap ]

  | Dup ->
      [ Dup; Swap; Swap ]

  | Rot ->
      [ Rot; Rot; Rot; Rot ]

  | PushReg r ->
      if next_int rng 2 = 0 then
        [ PushReg r; Dup; PopReg r ]
      else
        [ PushReg r; PushReg r; PopReg r ]

  | other -> [ other ]

(** Operations with at least one non-trivial metamorphic variant. *)
let is_expandable = function
  | Swap | Dup | Rot | PushReg _ -> true
  | _ -> false

let apply_block (cfg : multiplicity_config) _ctx (b : block) : block =
  if not cfg.enabled || cfg.rate <= 0 then b
  else
    let rng =
      make_rng
        (Int64.logxor cfg.seed
           (Int64.of_int
              (b.id * Int64.to_int salt_multiplicity_block_mul
               + Int64.to_int salt_multiplicity_block_add)))
    in
    let new_ops = ref [] in
    List.iter (fun op ->
      if is_expandable op && maybe rng cfg.rate then
        let expanded = expand_op rng op in
        new_ops := List.rev expanded @ !new_ops
      else
        new_ops := op :: !new_ops
    ) b.ops;
    { b with ops = List.rev !new_ops }

let apply_program (cfg : multiplicity_config) (ctx : Context_allocator.t) (prog : program) : program =
  if not cfg.enabled || cfg.rate <= 0 then prog
  else
    let new_blocks = Hashtbl.create (Hashtbl.length prog.blocks) in
    Hashtbl.iter (fun id b ->
      Hashtbl.add new_blocks id (apply_block cfg ctx b)
    ) prog.blocks;
    let context_slots = max prog.context_slots (Context_allocator.total_slots ctx) in
    { prog with blocks = new_blocks; context_slots }

let multiplicity_stats prog_before prog_after =
  let count_ops prog =
    Hashtbl.fold (fun _ b acc -> acc + List.length b.ops) prog.blocks 0
  in
  let before = count_ops prog_before in
  let after  = count_ops prog_after in
  let diff = after - before in
  Printf.sprintf "Handler multiplicity: %d ops → %d ops (synthesized +%d polymorphic variants, +%.1f%%)"
    before after diff
    (if before = 0 then 0.0 else float_of_int diff /. float_of_int before *. 100.0)
