(** Phase 5i (Pass 18): I/O Sink Entanglement & Slicing Barrier Pass
    ───────────────────────────────────────────────────────────────
    Defeats Tier 4 backward program slicing (Triton / LLVM DSE / IDA Hex-Rays)
    by mathematically binding intermediate state registers and accumulator
    chains directly into observable sinks:
      1. Memory Sinks (WriteMem): entangles memory address and value operands
         with intermediate scratch registers via zero-knots.
      2. External Sinks (CallExtern): entangles live FFI argument registers
         (ctx[0]..ctx[5]) with scratch registers before invocation.
      3. Termination Sinks (Exit): entangles exit return register ctx[0]
         with scratch registers.
      4. Branch Sinks (Cmp/Test): entangles comparison operands prior to Cmp/Test.

    Soundness Invariants:
    1. Zero Net Stack Delta: All injected barrier operations maintain exact stack depth.
    2. Exact Value Preservation: All transformations add/subtract zero-knots (V + 0 == V).
    3. Flag Preservation: Wraps barrier clusters in PushFlags ... PopFlags when downstream
       condition codes are live.
*)

open Stack_ir
open Random_visa_constants.Magic_numbers

type sink_barrier_config = {
  enabled : bool;
  rate : int;
  seed : int64;
}

let default_sink_barrier_config seed = {
  enabled = true;
  rate = 40;
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

(** Pass 18 Knot 1: Algebraic Sink Barrier Zero-Knot.
    Evaluates:
      (s + C) - (s & C) - (s | C) == 0 (mod 2^64).
    Since for all 64-bit integers: (s + C) == (s & C) + (s | C).
    Net stack delta = +1 (pushes 0L onto stack). *)
let emit_algebraic_barrier_knot ~scratch_slot =
  let c = salt_xwcafe_leetbeef in
  [
    (* 1. s + C *)
    PushReg scratch_slot;
    PushImm c;
    Add;                                   (* [s + C] *)

    (* 2. s & C *)
    PushReg scratch_slot;
    PushImm c;
    Nand; Dup; Nand;                       (* [s & C, s + C] *)
    Sub;                                   (* [(s + C) - (s & C) = s | C] *)

    (* 3. s | C *)
    PushReg scratch_slot;
    PushImm c;
    Nor; Dup; Nor;                         (* [s | C, s | C] *)
    Sub;                                   (* [(s | C) - (s | C) = 0L] *)
  ]

(** Pass 18 Knot 2: Mersenne Prime Field M31 Invertibility Barrier Knot.
    Evaluates in F_{M31}:
      s0 - fold31(fold31(s0 * a) * a^-1) == 0.
    Net stack delta = +1 (pushes 0L onto stack). *)
let emit_mersenne_barrier_knot ~scratch_slot =
  [
    PushReg scratch_slot;
    PushImm finite_field_m31_mask;
    Nand; Dup; Nand;                       (* [s0] *)
    Dup;
    PushImm finite_field_m31_mul;
    Mul;                                   (* [p1, s0] *)
    Dup;
    PushImm finite_field_m31;
    Nand; Dup; Nand;
    Swap;
    PushImm 31L;
    Shr;
    Add;
    Dup;
    PushImm finite_field_m31;
    Nand; Dup; Nand;
    Swap;
    PushImm 31L;
    Shr;
    Add;                                   (* [y, s0] *)
    PushImm finite_field_m31_inv;
    Mul;                                   (* [p2, s0] *)
    Dup;
    PushImm finite_field_m31;
    Nand; Dup; Nand;
    Swap;
    PushImm 31L;
    Shr;
    Add;
    Dup;
    PushImm finite_field_m31;
    Nand; Dup; Nand;
    Swap;
    PushImm 31L;
    Shr;
    Add;                                   (* [z, s0] *)
    Sub;                                   (* [0L] *)
  ]

let apply_block (cfg : sink_barrier_config) ?scratch_ring _ctx (b : block) : block =
  if not cfg.enabled || cfg.rate <= 0 then b
  else
    let scratch_ring =
      match scratch_ring with
      | Some r -> r
      | None -> [| 1 |]
    in
    let n_ring = Array.length scratch_ring in
    if n_ring = 0 then b
    else
      let rng =
        make_rng
          (Int64.logxor cfg.seed
             (Int64.of_int (b.id * 0x5877 + 0x1337)))
      in
      let live = Stack_flag_liveness.analyze_list b.ops in
      let new_ops = ref [] in
      let ring_idx = ref (b.id mod n_ring) in
      let depth = ref 0 in

      let pick_knot () =
        let s = scratch_ring.(!ring_idx) in
        ring_idx := (!ring_idx + 1) mod n_ring;
        if next_int rng 2 = 0 then emit_algebraic_barrier_knot ~scratch_slot:s
        else emit_mersenne_barrier_knot ~scratch_slot:s
      in

      List.iteri (fun idx op ->
        let flags_live = if idx < Array.length live then live.(idx) else false in
        match op with
        | WriteMem _ when !depth >= 2 && not flags_live && next_int rng 100 < cfg.rate ->
            (* Stack: [..., value, address]. When flags are dead, entangle operands cleanly. *)
            let k_addr = pick_knot () in
            let k_val = pick_knot () in
            let barrier =
              k_addr @ [ Add ] @
              [ Swap ] @ k_val @ [ Add; Swap ]
            in
            new_ops := List.rev barrier @ !new_ops;
            new_ops := op :: !new_ops;
            depth := !depth + stack_delta op

        | CallExtern _ when next_int rng 100 < cfg.rate ->
            (* Entangle FFI argument registers ctx[0]..ctx[2] with scratch state *)
            let barrier = ref [] in
            for reg = 0 to 2 do
              let k = pick_knot () in
              barrier := !barrier @ [ PushReg reg ] @ k @ [ Add; PopReg reg ]
            done;
            let cluster =
              if flags_live then [ PushFlags ] @ !barrier @ [ PopFlags ]
              else !barrier
            in
            new_ops := List.rev cluster @ !new_ops;
            new_ops := op :: !new_ops;
            depth := !depth + stack_delta op

        | Exit when next_int rng 100 < cfg.rate ->
            (* Entangle exit code register ctx[0] with scratch state *)
            let k = pick_knot () in
            let barrier =
              if flags_live then [ PushFlags; PushReg 0 ] @ k @ [ Add; PopReg 0; PopFlags ]
              else [ PushReg 0 ] @ k @ [ Add; PopReg 0 ]
            in
            new_ops := List.rev barrier @ !new_ops;
            new_ops := op :: !new_ops;
            depth := !depth + stack_delta op

        | Cmp when !depth >= 2 && next_int rng 100 < cfg.rate ->
            (* Stack: [..., op2, op1]. Entangle both operands before Cmp *)
            let k1 = pick_knot () in
            let barrier =
              if flags_live then
                [ PushFlags ] @
                k1 @ [ Add ] @
                [ PopFlags ]
              else
                k1 @ [ Add ]
            in
            new_ops := List.rev barrier @ !new_ops;
            new_ops := op :: !new_ops;
            depth := !depth + stack_delta op

        | _ ->
            new_ops := op :: !new_ops;
            depth := !depth + stack_delta op
      ) b.ops;
      { b with ops = List.rev !new_ops }

let apply_program ?scratch_ring (cfg : sink_barrier_config) (ctx : Context_allocator.t) (prog : program) : program =
  if not cfg.enabled || cfg.rate <= 0 then prog
  else
    let scratch_ring =
      match scratch_ring with
      | Some r -> r
      | None -> Array.init 4 (fun _ -> Context_allocator.alloc_scratch ctx)
    in
    let new_blocks = Hashtbl.create (Hashtbl.length prog.blocks) in
    Hashtbl.iter (fun id b ->
      let b' = apply_block cfg ~scratch_ring ctx b in
      Hashtbl.add new_blocks id b'
    ) prog.blocks;
    let context_slots = max prog.context_slots (Context_allocator.total_slots ctx) in
    { prog with blocks = new_blocks; context_slots }

let sink_barrier_stats prog_before prog_after =
  let count_ops prog =
    Hashtbl.fold (fun _ b acc -> acc + List.length b.ops) prog.blocks 0
  in
  let before = count_ops prog_before in
  let after = count_ops prog_after in
  let diff = after - before in
  Printf.sprintf "I/O Sink Barrier: %d ops -> %d ops (+%d sink barrier knots, +%.1f%%)"
    before after diff
    (if before = 0 then 0.0 else float_of_int diff /. float_of_int before *. 100.0)
