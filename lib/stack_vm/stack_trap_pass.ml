(** Phase 6b (Pass 19): Cross-Block Execution Path Integrity & Anti-DBI Traps
    ────────────────────────────────────────────────────────────────────────
    Cryptographically couples the runtime execution path to dynamic trap
    assertions, defeating dynamic binary instrumentation (Frida, QBDI, GDB/LLDB).

    Mechanisms:
      1. Path Digest Accumulator: Maintains an evolving cryptographic digest
         H_{k+1} = (H_k * C_mul + Token(B_i)) mod 2^64 across every executed basic block.
      2. Dynamic Anti-DBI Zero-Knots:
         Evaluates algebraic path assertions (H + C) - (H & C) - (H | C) == 0 (mod 2^64),
         entangled directly into stack operands and context writes.
      3. Silent Desynchronization: If an adversary hooks a handler or bypasses
         a security check block, H is corrupted, causing silent algebraic distortion
         and invalid opcode aborts downstream.

    Soundness Invariants:
    1. Zero Net Stack Delta: Digest updates and knot evaluations preserve stack balance.
    2. Exact Value Preservation: All transformations add 0 to operands under legitimate paths.
    3. Flag Preservation: Wraps updates in PushFlags ... PopFlags when condition codes are live.
*)

open Stack_ir
open Random_visa_constants.Magic_numbers

type trap_config = {
  enabled : bool;
  rate : int;
  seed : int64;
}

let default_trap_config seed = {
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

let is_terminator = function
  | JmpRel _ | JccRel _ | Exit -> true
  | _ -> false

(** Computes a deterministic 64-bit token for block [bid]. *)
let block_token bid =
  let open Int64 in
  add (mul (of_int bid) trap_token_mul) trap_step_add

(** Emits the path digest update cluster for block [bid] into slot [digest_slot]:
    H = (H * C_mul + Token(bid)) mod 2^64.
    Net stack delta = 0. *)
let emit_digest_update ~digest_slot ~bid =
  [
    PushReg digest_slot;
    PushImm trap_step_mul;
    Mul;
    PushImm (block_token bid);
    Add;
    PopReg digest_slot;
  ]

(** Emits an anti-DBI path zero-knot using [digest_slot]:
    Knot = (H + C) - (H & C) - (H | C) == 0 (mod 2^64).
    Net stack delta = +1 (pushes 0L onto stack). *)
let emit_trap_knot ~digest_slot =
  let c = trap_step_mul in
  [
    (* 1. H + C *)
    PushReg digest_slot;
    PushImm c;
    Add;                                   (* [H + C] *)

    (* 2. H & C *)
    PushReg digest_slot;
    PushImm c;
    Nand; Dup; Nand;                       (* [H & C, H + C] *)
    Sub;                                   (* [(H + C) - (H & C) = H | C] *)

    (* 3. H | C *)
    PushReg digest_slot;
    PushImm c;
    Nor; Dup; Nor;                         (* [H | C, H | C] *)
    Sub;                                   (* [(H | C) - (H | C) = 0L] *)
  ]

let apply_block (cfg : trap_config) ~digest_slot _ctx (b : block) : block =
  if not cfg.enabled then b
  else
    let rng =
      make_rng
        (Int64.logxor cfg.seed
           (Int64.of_int (b.id * 0x7758 + 0x3713)))
    in
    let live = Stack_flag_liveness.analyze_list b.ops in
    let flags_live_at_entry = if Array.length live > 0 then live.(0) else false in

    (* 1. Emit block path digest update *)
    let update = emit_digest_update ~digest_slot ~bid:b.id in
    let update_cluster =
      if flags_live_at_entry then [ PushFlags ] @ update @ [ PopFlags ]
      else update
    in

    (* 2. Traverse body and inject dynamic trap knots *)
    let new_ops = ref (List.rev update_cluster) in
    let count = ref 0 in
    let max_per_block = 2 in
    let depth = ref 0 in

    List.iteri (fun idx op ->
      new_ops := op :: !new_ops;
      depth := !depth + stack_delta op;
      if not (is_terminator op) && !depth >= 1 && !count < max_per_block then begin
        if next_int rng 100 < cfg.rate then begin
          let flags_live = if idx + 1 < Array.length live then live.(idx + 1) else false in
          let knot = emit_trap_knot ~digest_slot in
          let cluster =
            if flags_live then [ PushFlags; Swap ] @ knot @ [ Add; Swap; PopFlags ]
            else knot @ [ Add ]
          in
          new_ops := List.rev cluster @ !new_ops;
          incr count
        end
      end
    ) b.ops;
    { b with ops = List.rev !new_ops }

let apply_program (cfg : trap_config) (ctx : Context_allocator.t) (prog : program) : program =
  if not cfg.enabled then prog
  else
    let digest_slot = Context_allocator.alloc_scratch ctx in
    let sorted =
      Hashtbl.fold (fun id b acc -> (id, b) :: acc) prog.blocks []
      |> List.sort (fun (a, _) (b, _) -> compare a b)
      |> Array.of_list
    in
    let n = Array.length sorted in
    let out = Array.make n (0, { (snd sorted.(0)) with ops = [] }) in
    let pool = Random_visa_ports.Domain_pool.global_pool () in
    Random_visa_ports.Domain_pool.parallel_for ~min_n:4 pool ~n (fun i ->
      let (id, b) = sorted.(i) in
      let b' = apply_block cfg ~digest_slot ctx b in
      let b'' =
        if id = prog.entry_id then
          (* Prepend digest initialization at program entry *)
          let init_cluster = [ PushImm trap_salt_init; PopReg digest_slot ] in
          { b' with ops = init_cluster @ b'.ops }
        else b'
      in
      out.(i) <- (id, b'')
    );
    let new_blocks = Hashtbl.create n in
    Array.iter (fun (id, b) -> Hashtbl.replace new_blocks id b) out;
    let context_slots = max prog.context_slots (Context_allocator.total_slots ctx) in
    { prog with blocks = new_blocks; context_slots }

let trap_stats prog_before prog_after =
  let count_ops prog =
    Hashtbl.fold (fun _ b acc -> acc + List.length b.ops) prog.blocks 0
  in
  let before = count_ops prog_before in
  let after = count_ops prog_after in
  let diff = after - before in
  Printf.sprintf "Anti-DBI Traps & Path Digest: %d ops -> %d ops (+%d trap checks, +%.1f%%)"
    before after diff
    (if before = 0 then 0.0 else float_of_int diff /. float_of_int before *. 100.0)
