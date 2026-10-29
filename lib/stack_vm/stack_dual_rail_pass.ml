(** Phase 5j (Pass 21): Dual-Rail Complement Arithmetic & Invariant Checkpoints
    ───────────────────────────────────────────────────────────────────────────
    Provides fault injection resistance (EMFI, clock glitching) and dynamic
    tamper detection by maintaining dedicated dual-rail complement register pairs:
      r_bar = NOT(r) = -1 - r (mod 2^64).

    Mechanisms:
      1. Dedicated Dual-Rail Ring: Allocates dedicated scratch register pairs
         (rail_true, rail_comp) isolated from guest architectural state.
      2. Fundamental Invariants:
         - Sum Invariant: rail_true + rail_comp + 1 == 0 (mod 2^64)
         - Orthogonality: rail_true & rail_comp == 0
         - Span Invariant: rail_true | rail_comp == -1
      3. Dual-Rail Arithmetic Evolution:
         Evolves pairs through homomorphic dual-rail addition and subtraction:
           z = x + y
           z_bar = x_bar + y_bar + 1
      4. Dynamic Fault Checkpoints:
         Evaluates invariant zero-knots directly into live stack operands.
         Any fault injection (bit-flip, glitch) breaks the invariant, silently
         destroying computation without obvious detection branches.

    Soundness Invariants:
    1. Zero Net Stack Delta: All checkpoint clusters maintain exact stack depth.
    2. Exact Value Preservation: Legitimate execution adds 0 to operands (V + 0 == V).
    3. Flag Preservation: Wraps updates in PushFlags ... PopFlags when downstream
       condition codes are live.
*)

open Stack_ir
open Random_visa_constants.Magic_numbers

type dual_rail_config = {
  enabled : bool;
  rate : int;
  seed : int64;
}

let default_dual_rail_config seed = {
  enabled = true;
  rate = 35;
  seed;
}

type rng_state = { mutable state : int64 }

let make_rng seed = { state = seed }

let splitmix64 s =
  let open Int64 in
  let s = add s golden_ratio_64 in
  let z = s in
  let z = mul (logxor z (shift_right_logical z 30)) splitmix64_gamma in
  let z = mul (logxor z (shift_right_logical z 27)) splitmix64_mix in
  (s, logxor z (shift_right_logical z 31))

let next_int rng n =
  if n <= 1 then 0
  else
    let s, z = splitmix64 rng.state in
    rng.state <- s;
    Int64.to_int (Int64.logand z 0x7FFFFFFFL) mod n

let next_int64 rng =
  let s, z = splitmix64 rng.state in
  rng.state <- s;
  z

let is_terminator = function
  | JmpRel _ | JccRel _ | Exit -> true
  | _ -> false

(** Emits complement update for register [reg] into [dual_slot]:
    PushReg reg; Dup; Nand; PopReg dual_slot;
    Net stack delta = 0. *)
let emit_dual_update ~reg ~dual_slot =
  [
    PushReg reg;
    Dup;
    Nand;
    PopReg dual_slot;
  ]

(** Emits a dynamic dual-rail evolution step:
      rail_true  <- rail_true + step
      rail_comp  <- NOT(rail_true)   (via the homomorphic complement update)
    Both invariants (sum & orthogonality) are re-established for the NEW
    rail value, so the checkpoint knots that follow verify dynamic state
    instead of compile-time constants an SMT solver can fold away.
    Net stack delta = 0 (clobbers flags; caller must guard). *)
let emit_dual_evolve ~reg ~dual_slot ~step =
  [
    PushReg reg;
    PushImm step;
    Add;
    PopReg reg;
  ] @ emit_dual_update ~reg ~dual_slot

(** Emits sum invariant zero-knot:
    PushReg reg; PushReg dual_slot; Add; PushImm 1L; Add;
    Evaluates to 0L on stack top. Net stack delta = +1. *)
let emit_sum_invariant_knot ~reg ~dual_slot =
  [
    PushReg reg;
    PushReg dual_slot;
    Add;
    PushImm 1L;
    Add;
  ]

(** Emits orthogonality invariant zero-knot:
    PushReg reg; PushReg dual_slot; Nand; Dup; Nand;
    Evaluates to 0L on stack top. Net stack delta = +1. *)
let emit_ortho_invariant_knot ~reg ~dual_slot =
  [
    PushReg reg;
    PushReg dual_slot;
    Nand;
    Dup;
    Nand;
  ]

let apply_block (cfg : dual_rail_config) ?pairs (ctx : Context_allocator.t) (b : block) : block =
  if not cfg.enabled then b
  else
    let pairs =
      match pairs with
      | Some p -> p
      | None -> Array.init 4 (fun _ ->
          (Context_allocator.alloc_scratch ctx, Context_allocator.alloc_scratch ctx)
        )
    in
    let n_pairs = Array.length pairs in
    if n_pairs = 0 then b
    else
    let rng =
      make_rng
        (Int64.logxor cfg.seed
           (Int64.of_int (b.id * 0x4224 + 0x2442)))
    in
    let live = Stack_flag_liveness.analyze_list b.ops in
    let new_ops = ref [] in
    let count = ref 0 in
    let max_per_block = 2 in
    let depth = ref 0 in
    let pair_idx = ref (b.id mod n_pairs) in

    List.iteri (fun idx op ->
      new_ops := op :: !new_ops;
      depth := !depth + stack_delta op;

      (* Periodic dynamic invariant verification checkpoints *)
      if not (is_terminator op) && !depth >= 1 && !count < max_per_block then begin
        if next_int rng 100 < cfg.rate then begin
          let flags_live = if idx + 1 < Array.length live then live.(idx + 1) else false in
          let (r, dual_slot) = pairs.(!pair_idx) in
          pair_idx := (!pair_idx + 1) mod n_pairs;
          let step = Int64.logor (next_int64 rng) 1L in
          let evolve = emit_dual_evolve ~reg:r ~dual_slot ~step in
          let knot =
            if next_int rng 2 = 0 then emit_sum_invariant_knot ~reg:r ~dual_slot
            else emit_ortho_invariant_knot ~reg:r ~dual_slot
          in
          let cluster =
            if flags_live then [ PushFlags; Swap ] @ evolve @ knot @ [ Add; Swap; PopFlags ]
            else evolve @ knot @ [ Add ]
          in
          new_ops := List.rev cluster @ !new_ops;
          incr count
        end
      end
    ) b.ops;
    { b with ops = List.rev !new_ops }

let apply_program (cfg : dual_rail_config) (ctx : Context_allocator.t) (prog : program) : program =
  if not cfg.enabled then prog
  else
    (* Allocate 4 dedicated dual-rail complement pairs in scratch space *)
    let pairs = Array.init 4 (fun _ ->
      (Context_allocator.alloc_scratch ctx, Context_allocator.alloc_scratch ctx)
    ) in

    let new_blocks = Hashtbl.create (Hashtbl.length prog.blocks) in
    Hashtbl.iter (fun id b ->
      let b' = apply_block cfg ~pairs ctx b in
      let b'' =
        if id = prog.entry_id then
          (* Initialize dual-rail scratch pairs at program entry with well-mixed entropy *)
          let init_ops = ref [] in
          Array.iteri (fun i (r, dr) ->
            let seed_val =
              Int64.logxor dual_rail_salt (Int64.of_int (i * 0x5877 + 0x1337))
            in
            init_ops := !init_ops @ [
              SetRegImm (r, seed_val);
              SetRegImm (dr, Int64.lognot seed_val);
            ]
          ) pairs;
          { b' with ops = !init_ops @ b'.ops }
        else b'
      in
      Hashtbl.add new_blocks id b''
    ) prog.blocks;
    let context_slots = max prog.context_slots (Context_allocator.total_slots ctx) in
    { prog with blocks = new_blocks; context_slots }

let dual_rail_stats prog_before prog_after =
  let count_ops prog =
    Hashtbl.fold (fun _ b acc -> acc + List.length b.ops) prog.blocks 0
  in
  let before = count_ops prog_before in
  let after = count_ops prog_after in
  let diff = after - before in
  Printf.sprintf "Dual-Rail Complement Arithmetic: %d ops -> %d ops (+%d fault-invariant checkpoints, +%.1f%%)"
    before after diff
    (if before = 0 then 0.0 else float_of_int diff /. float_of_int before *. 100.0)
