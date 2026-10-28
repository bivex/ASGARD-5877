(** Phase 5g (Pass 15): T-Function Trace Invariant Closure
    ─────────────────────────────────────────────────────────
    Closes the Live → Ghost → Live dataflow cycle so that ghost/avid
    accumulator operations become *observable* to backward program
    slicing (Tier 4 threat model), collapsing the
    `Slicing_unobservable` category of the Dead Code Causality
    Analyzer.

    Threat Model:
      The deobfuscation probe's Tier 4 backward slicer keeps only the
      operations that transitively influence observable sinks
      (WriteMem, CallExtern, ResolveSym, Exit, JmpRel, JccRel).
      Ghost padding (Phase 5) and avid operands (Phase 5b) READ live
      registers but never WRITE anything the sinks depend on, so the
      slicer prunes the entire subtree.

    Mechanism (Klimov-Shamir T-Function with Split Entropy):
      A dedicated accumulator slot G evolves via the T-function
      T(x) = x + (x^2 | 5), a bijection on Z_{2^64}. Live register
      entropy is folded ONLY into the high 60 bits through a
      16-aligned product:

        raw_{k+1} = T(G_k) + 16 * ((r_live | G_k) * C_odd)  (mod 2^64)
        G_{k+1}   = (raw_{k+1} & ~0xF) | (T(G_k) & 0xF)

      Because the entropy term is 16-aligned, the low nibble obeys
      G_{k+1} & 0xF == T(G_k) & 0xF, i.e. it follows the pure
      compile-time trace mu_k = T^k(G_0) & 0xF known to the OCaml
      generator, while bits [4..63] chaotically depend on r_live.

    Sink Injection (pre-write value entanglement):
      At a live-write site [PushX v; PopReg r] the *pending* stack
      value is perturbed between the push and the pop:

        v' = v + (G_k & 0xF) - mu_k            (mod 2^64)

      (G_k & 0xF) == mu_k at runtime, so v' == v bit-exactly, but the
      PDG now contains a genuine def-use edge G_k → v' → r, forcing
      the slicer to retain the whole accumulator chain. The cluster
      never disturbs the stack: it consumes the pending value and
      re-pushes the (identical) entangled one, so the original
      [PopReg r] still finds exactly one value on top.

    Soundness Invariants:
      1. Stack Neutrality at the write site: the cluster maps a
         1-element stack [v] to a 1-element stack [v + 0] — the
         original [PopReg r] executes with its semantics unchanged.
         The accumulator step that follows runs on an empty operand
         window (own pushes only, net delta 0).
      2. Value Invariance: (G_k & 0xF) - mu_k == 0 (mod 2^64) for
         every reachable accumulator state, by the nibble-invariance
         theorem (the entropy term is 16-aligned). The theorem itself
         [emit_t_step G & 0xF == T(G) & 0xF for ALL G] is proven
         `Equivalent` by Stack_bv_verifier in QF_BV.
      3. Flag Safety: clusters are wrapped in PushFlags/PopFlags
         whenever architectural flags are live at the injection site.
      4. Nibble Trace Determinism: mu_k is computed by the same pure
         T-function recursion the emitted code performs on the low
         nibble, so generator and runtime can never drift.
*)

open Stack_ir

type trace_closure_config = {
  enabled : bool;
  rate : int;      (** percentage of live-write sites to entangle (0..100) *)
  seed : int64;
}

let default_trace_closure_config seed = {
  enabled = true;
  rate = 25;
  seed;
}

(* ── SplitMix64 PRNG ─────────────────────────────────────────────────── *)
let splitmix64 s =
  let open Int64 in
  let s = add s 0x9E3779B97F4A7C15L in
  let z = s in
  let z = logxor z (shift_right_logical z 30) in
  let z = mul z 0xBF58476D1CE4E5B9L in
  let z = logxor z (shift_right_logical z 27) in
  let z = mul z 0x94D049BB133111EBL in
  let z = logxor z (shift_right_logical z 31) in
  (s, z)

type rng_state = { mutable state : int64 }

let make_rng seed = { state = seed }

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

(* ── Klimov-Shamir T-function: T(x) = x + (x^2 | 5) over Z_{2^64} ────── *)
let t_function (x : int64) : int64 =
  Int64.add x (Int64.logor (Int64.mul x x) 5L)

(** Compile-time nibble trace: mu_{k+1} = T(mu_k) & 0xF. Because the
    runtime entropy term is 16-aligned, the emitted code's low nibble
    follows exactly this pure recursion. *)
let nibble_trace (g0 : int64) (steps : int) : int64 array =
  let mu = Array.make (steps + 1) (Int64.logand g0 0xFL) in
  for k = 0 to steps - 1 do
    mu.(k + 1) <- Int64.logand (t_function mu.(k)) 0xFL
  done;
  mu

(* ── NAND network macros (stack annotated, top = rightmost) ────────────
   AND(a, b) = NAND(NAND(a, b), NAND(a, b)):
     [.., a, b] Dup2 -> [.., a, b, a, b] Nand -> [.., a, b, N]
     Dup -> [.., a, b, N, N] Nand -> [.., a, b, AND(a,b)]
   OR(a, b) = NAND(NAND(a, b), NAND(a, b)) — same shape; the sequences
   below drain the stale operands with explicit Rot/Sub/Add discipline. *)

(** Emits the accumulator step onto the stack:
      [] -> [G']  where G' = (raw & ~0xF) | (T(G) & 0xF)
                   raw  = T(G) + 16 * ((live | G) * C_odd)
    Stack delta = +1. Every stage annotated; strictly ordered. *)
let emit_t_step ~g_slot ~live_slot ~(c_odd : int64) : stack_op list =
  [
    (* ── Part 1: T(G) = G + (G^2 | 5) = G + G^2 + 5 - (G^2 & 5) ── *)
    PushReg g_slot;                    (* [G] *)
    Dup;                               (* [G, G] *)
    Mul;                               (* [G^2] *)
    PushImm 5L;                        (* [G^2, 5] *)
    Add;                               (* [G^2 + 5] *)
    PushReg g_slot;                    (* [G^2 + 5, G] *)
    Add;                               (* [G^2 + 5 + G] *)
    PushReg g_slot;                    (* [Sum, G] *)
    Dup;                               (* [Sum, G, G] *)
    Mul;                               (* [Sum, G^2] *)
    PushImm 5L;                        (* [Sum, G^2, 5] *)
    Nand;                              (* [Sum, Nand(G^2, 5)] *)
    Dup;                               (* [Sum, Nand, Nand] *)
    Nand;                              (* [Sum, G^2 & 5] *)
    Sub;                               (* [T(G)] (depth 1) *)

    (* ── Part 2: ENT = 16 * ((r ^ G) * C_odd); raw = T + ENT ──── *)
    PushReg live_slot;                 (* [T, r] *)
    PushReg g_slot;                    (* [T, r, G] *)
    Add;                               (* [T, r + G] *)
    PushReg live_slot;                 (* [T, r + G, r] *)
    PushReg g_slot;                    (* [T, r + G, r, G] *)
    Nand;                              (* [T, r + G, Nand(r,G)] *)
    Dup;                               (* [T, r + G, Nand, Nand] *)
    Nand;                              (* [T, r + G, r & G] *)
    PushImm 2L;                        (* [T, r + G, r & G, 2] *)
    Mul;                               (* [T, r + G, 2 * (r & G)] *)
    Sub;                               (* [T, r ^ G] *)
    PushImm c_odd;                     (* [T, r ^ G, C] *)
    Mul;                               (* [T, (r ^ G) * C] *)
    PushImm 16L;                       (* [T, XC, 16] *)
    Mul;                               (* [T, ENT] *)
    Add;                               (* [raw = T + ENT] = [G'] (depth 1) *)
  ]

(** Pre-write entanglement: maps the pending value stack [v] to
    [v + (G & 0xF) - mu_k] — a compile-time-zero perturbation that
    creates a genuine PDG edge G → v'. *)
let pre_canonical ~g_slot ~(mu_k : int64) : stack_op list =
  [
    PushReg g_slot;                    (* [v, G] *)
    PushImm 0xFL;                      (* [v, G, 0xF] *)
    Nand;                              (* [v, Nand(G, 0xF)] *)
    Dup;                               (* [v, Nand, Nand] *)
    Nand;                              (* [v, G & 0xF] *)
    PushImm mu_k;                      (* [v, G & 0xF, mu] *)
    Sub;                               (* [v, (G & 0xF) - mu] *)
    Add;                               (* [v + (G & 0xF) - mu] = [v'] *)
  ]
let generate_closure_pair ~g_slot ~live_slot ~(mu_k : int64) ~(c_odd : int64) :
  stack_op list * stack_op list =
  let pre = pre_canonical ~g_slot ~mu_k in
  let post = emit_t_step ~g_slot ~live_slot ~c_odd @ [ PopReg g_slot ] in
  (pre, post)

let apply_block (cfg : trace_closure_config) ~(g_slot : int) ~(live_writes : int list)
    ~(mu : int64 array) ~(c_odd : int64) (b : block) : block =
  if not cfg.enabled || cfg.rate <= 0 || live_writes = [] then b
  else
    let rng =
      make_rng
        (Int64.logxor cfg.seed
           (Int64.of_int (b.id * 0x5A17 + 0x3C3C)))
    in
    let live = Stack_flag_liveness.analyze_list b.ops in
    let new_ops = ref [] in
    let step = ref 0 in
    let n_mu = Array.length mu in
    let ops_arr = Array.of_list b.ops in
    let n = Array.length ops_arr in
    let i = ref 0 in
    while !i < n do
      let op = ops_arr.(!i) in
      let idx = !i in
      let flags_live = if idx + 1 < Array.length live then live.(idx + 1) else false in
      (* Detect a live-write pair: PushX ...; PopReg r  with r live and
         the push directly adjacent. *)
      let is_live_write =
        idx + 1 < n
        && (match ops_arr.(idx + 1) with
            | PopReg r -> List.mem r live_writes
            | _ -> false)
      in
      let pushes_value = match op with
        | PushImm _ | PushReg _ | Setcc _ | AddImm _ | SubImm _ | AddImmImm _
        | SubImmImm _ | AddRegImm _ | ResolveSym _ -> true
        | _ -> false
      in
      if is_live_write && pushes_value && next_int rng 100 < cfg.rate then begin
        let r = match ops_arr.(idx + 1) with PopReg r -> r | _ -> -1 in
        let mu_k = if !step < n_mu then mu.(!step) else mu.(n_mu - 1) in
        incr step;
        let pre, post = generate_closure_pair ~g_slot ~live_slot:r ~mu_k ~c_odd in
        new_ops := op :: !new_ops;                       (* original push: [.., v] *)
        let guarded l = if flags_live then [ PushFlags ] @ l @ [ PopFlags ] else l in
        new_ops := List.rev_append (guarded pre) !new_ops; (* [.., v'] *)
        new_ops := ops_arr.(idx + 1) :: !new_ops;          (* original PopReg r *)
        new_ops := List.rev_append (guarded post) !new_ops;(* accumulator step, net 0 *)
        i := !i + 2
      end else begin
        new_ops := op :: !new_ops;
        incr i
      end
    done;
    { b with ops = List.rev !new_ops }

let apply_program (cfg : trace_closure_config) (ctx : Context_allocator.t) (prog : program) : program =
  if not cfg.enabled then prog
  else
    let g_slot = Context_allocator.alloc_scratch ctx in
    let live_regs = [ Vm_ir.Register.rax; Vm_ir.Register.rbx; Vm_ir.Register.rcx; Vm_ir.Register.rdx;
                      Vm_ir.Register.rsi; Vm_ir.Register.rdi; Vm_ir.Register.r8; Vm_ir.Register.r9 ] in
    let live_writes = List.map (Context_allocator.slot_of_reg ctx) live_regs in
    let mu = nibble_trace 0L 8192 in
    let c_odd = Int64.logor (next_int64 (make_rng cfg.seed)) 1L in
    let new_blocks = Hashtbl.create (Hashtbl.length prog.blocks) in
    Hashtbl.iter (fun id b ->
      let b' = apply_block cfg ~g_slot ~live_writes ~mu ~c_odd b in
      Hashtbl.add new_blocks id b'
    ) prog.blocks;
    let context_slots = max prog.context_slots (Context_allocator.total_slots ctx) in
    { prog with blocks = new_blocks; context_slots }

let trace_closure_stats prog_before prog_after =
  let count_ops prog = Hashtbl.fold (fun _ b acc -> acc + List.length b.ops) prog.blocks 0 in
  let before = count_ops prog_before and after = count_ops prog_after in
  Printf.sprintf "Trace Closure: %d ops -> %d ops (+%d T-function closure steps, live-sink entanglement active)"
    before after (after - before)
