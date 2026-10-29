(** Phase 4: MBA Constant Synthesis Pass  (+ E-graph expansion)
    ─────────────────────────────────────────────────────────────
    Replaces PushImm instructions with semantically equivalent sequences
    of NOR, NAND, ADD, SUB, MUL operations, eliminating literal constants
    from the bytecode stream.

    Synthesis strategies (all have stack delta = +1, same as PushImm):

      L1 — ADD split:
        PushImm a          (random mask)
        PushImm (c − a)    (complement under addition mod 2^64)
        Add                → a + (c−a) = c

      L2 — NOR double complement:
        PushImm (~c) ; PushImm 0 ; Nor  → NOR(~c, 0) = c

      L3 — NAND self:
        PushImm (~c) ; PushImm (~c) ; Nand  → NAND(~c,~c) = c

      L4 — ADD + NOR (depth 3):
        PushImm a ; PushImm (~(c−a)) ; PushImm 0 ; Nor ; Add  → c

      L5 — E-graph MBA expansion (new):
        Builds Mba.Const c, runs Egraph.expand (tight budget), and lowers
        the resulting Mba.expr to stack ops using a post-order compiler.
        The extractor maximises (alternation, AST size), producing an
        expression mixing AND/OR/XOR/NOT/NEG with ADD/SUB/MUL.
        Chosen 30% of the time.

    Flag safety: all strategies write flags (Add/Sub/Nor/Nand), so synthesis
    is suppressed wherever produced flags are still live.

    Stack-ISA Boolean lowering (no direct And/Or/Xor ops, only Nor/Nand):
      AND(a,b) = NOR(NOR(a,a), NOR(b,b))     [De Morgan via double NOR-NOT]
      OR(a,b)  = NAND(NAND(a,a), NAND(b,b))  [De Morgan via double NAND-NOT]
      XOR(a,b) = OR(a,b) − AND(a,b)           [set-theoretic identity; uses Sub]
      NOT(x)   = NOR(x, x)
      NEG(x)   = PushImm 0 ; x ; Sub         [0 − x]
*)

open Stack_ir
open Random_visa_constants.Magic_numbers

(* ── SplitMix64 PRNG ─────────────────────────────────────────────────── *)
let splitmix64 s =
  let s = Int64.add s golden_ratio_64 in
  let z = s in
  let z = Int64.logxor z (Int64.shift_right_logical z 30) in
  let z = Int64.mul z splitmix64_gamma in
  let z = Int64.logxor z (Int64.shift_right_logical z 27) in
  let z = Int64.mul z splitmix64_mix in
  let z = Int64.logxor z (Int64.shift_right_logical z 31) in
  (s, z)
type mba_rng = { mutable state : int64 }

let make_rng seed = { state = seed }

let next_int64 rng =
  let s, z = splitmix64 rng.state in
  rng.state <- s;
  z

let next_int rng n =
  let v = Int64.to_int (Int64.logand (next_int64 rng) 0x7FFF_FFFFL) in
  v mod n

let maybe rng prob = next_int rng 100 < prob

(* ── Mba.expr → stack ops lowerer ───────────────────────────────────── *)
(** Post-order recursive compiler from a closed [Mba.expr] (no Var nodes)
    to stack operations.  Stack delta = +1.

    Boolean operators are lowered via NOR/NAND identities:
      AND(a,b) = NOR( NOR(a,a),  NOR(b,b) )
      OR(a,b)  = NAND( NAND(a,a), NAND(b,b) )
      XOR(a,b) = OR(a,b) − AND(a,b)          ← uses Sub, correct for Z_2^64
      NOT(x)   = NOR(x, x)
      NEG(x)   = 0 − x

    Sub semantics: pops b_top then a_next, pushes a_next − b_top.
    For XOR: emit or_ops (→ or_val on stack), then and_ops on top
    (→ and_val = top, or_val = next), Sub → or_val − and_val = XOR. ✓ *)
let emit_mba_anchored_zero r k =
  [
    PushReg r; PushImm k; Add;
    PushReg r; PushImm k; Nand; Dup; Nand; Sub;
    PushReg r; PushImm k; Nor; Dup; Nor; Sub;
  ]

let rec lower_mba_to_stack ?anchor (e : Mba_engine.Mba.expr) : stack_op list =
  match e with
  | Mba_engine.Mba.Const c ->
      (match anchor with
       | Some r ->
           let a = salt_egraph_scrambler in
           let b = Int64.sub c a in
           [ PushImm a; PushImm b; Add ] @ emit_mba_anchored_zero r salt_xwcafe_leetbeef @ [ Add ]
       | None -> [ PushImm c ])
  | Mba_engine.Mba.Var _      -> [ PushImm 0L ]
  | Mba_engine.Mba.Add (a, b) -> lower_mba_to_stack ?anchor a @ lower_mba_to_stack ?anchor b @ [ Add ]
  | Mba_engine.Mba.Sub (a, b) -> lower_mba_to_stack ?anchor a @ lower_mba_to_stack ?anchor b @ [ Sub ]
  | Mba_engine.Mba.Mul (a, b) -> lower_mba_to_stack ?anchor a @ lower_mba_to_stack ?anchor b @ [ Mul ]
  | Mba_engine.Mba.And (a, b) -> lower_and ?anchor a b
  | Mba_engine.Mba.Or  (a, b) -> lower_or  ?anchor a b
  | Mba_engine.Mba.Xor (a, b) -> lower_xor ?anchor a b
  | Mba_engine.Mba.Not a ->
      lower_mba_to_stack ?anchor a @ lower_mba_to_stack ?anchor a @ [ Nor ]
  | Mba_engine.Mba.Neg a ->
      (match anchor with
       | Some r -> emit_mba_anchored_zero r salt_xwcafe_leetbeef @ lower_mba_to_stack ?anchor a @ [ Sub ]
       | None -> [ PushImm 0L ] @ lower_mba_to_stack ?anchor a @ [ Sub ])

and lower_and ?anchor a b =
  let la = lower_mba_to_stack ?anchor a and lb = lower_mba_to_stack ?anchor b in
  la @ la @ [ Nor ] @
  lb @ lb @ [ Nor ] @
  [ Nor ]

and lower_or ?anchor a b =
  let la = lower_mba_to_stack ?anchor a and lb = lower_mba_to_stack ?anchor b in
  la @ la @ [ Nand ] @
  lb @ lb @ [ Nand ] @
  [ Nand ]

and lower_xor ?anchor a b =
  lower_or ?anchor a b @
  lower_and ?anchor a b @
  [ Sub ]

(* ── E-graph budget for per-constant expansion ───────────────────────── *)
(** Tight budget: constants are ground terms; we just want enough saturation
    to produce 1–3 alternation switches without blowing the time budget. *)
let egraph_const_config : Mba_engine.Egraph.config = {
  node_limit    = 120;
  time_budget_s = 0.08;
  iter_limit    = 5;
}

let egraph_config_of ~node_limit ~time_budget_ms ~iter_limit = {
  Mba_engine.Egraph.
  node_limit;
  time_budget_s = float_of_int time_budget_ms /. 1000.0;
  iter_limit;
}

(* ── Synthesize constant via E-graph expansion ───────────────────────── *)
(** [synthesize_egraph rng c] expands [Mba.Const c] through the e-graph,
    extracts the maximally complex equivalent expression, and lowers it to
    stack ops.  Falls back to L2 on any error. *)
let synthesize_egraph ?anchor ?(budget = egraph_const_config) rng c =
  (* Derive a Random.State seed from the SplitMix state, advance rng *)
  let seed_word = Int64.to_int (Int64.logxor rng.state salt_egraph_scrambler) in
  let _ = next_int64 rng in  (* advance so next call gets a different seed *)
  let eg_rng = Random.State.make [| seed_word |] in
  let expr = Mba_engine.Egraph.expand
    ~rng:eg_rng ~config:budget
    (Mba_engine.Mba.Const c) in
  match expr with
  | Mba_engine.Mba.Const _ ->
      let not_c = Int64.lognot c in
      (match anchor with
       | Some r -> PushImm not_c :: emit_mba_anchored_zero r salt_egraph_scrambler @ [ Nor ]
       | None -> [ PushImm not_c; PushImm 0L; Nor ])
  | _ -> lower_mba_to_stack ?anchor expr

(* ── MBA strategy type ───────────────────────────────────────────────── *)
type mba_strategy = L1_AddSplit | L2_NorNot | L3_NandSelf | L4_AddNor | L5_Egraph | L6_NullspaceZero

(* ── Synthesize constant c using a chosen strategy ───────────────────── *)
(** Returns a stack_op list with stack delta = +1 (equivalent to PushImm c). *)
let synthesize_const ?anchor ?(egraph_rate = 30) ?(egraph_budget = egraph_const_config) rng c =
  let mask = next_int64 rng in
  (* Default rate 30 keeps the historical RNG stream (next_int rng 20) so
     builds and regression tests are bit-identical. *)
  let strategy =
    if egraph_rate = 30 then
      (match next_int rng 20 with
       | 0 | 1 | 2 | 3 -> L1_AddSplit   (* 20% *)
       | 4 | 5 | 6 | 7 -> L2_NorNot     (* 20% *)
       | 8 | 9 | 10    -> L3_NandSelf   (* 15% *)
       | 11 | 12 | 13  -> L4_AddNor     (* 15% *)
       | _             -> L5_Egraph)    (* 30% — e-graph MBA expansion *)
    else begin
      let r = next_int rng 100 in
      if r < 20 then L6_NullspaceZero
      else if r < egraph_rate + 20 then L5_Egraph
      else
        let rest = ((r - egraph_rate - 20) * 4) / (max 1 (80 - egraph_rate)) in
        match rest with
        | 0 -> L1_AddSplit | 1 -> L2_NorNot | 2 -> L3_NandSelf | _ -> L4_AddNor
    end
  in
  match strategy with
  | L1_AddSplit ->
    let addend = Int64.sub c mask in
    (match anchor with
     | Some r ->
         let a = mask in
         let not_a = Int64.lognot a in
         let b = addend in
         (* (r | a) - (r & ~a) == a in Z_{2^64}; a + b == c.
            Peak stack depth increase = 3, fits strictly inside JIT 4-slot window. *)
         [
           PushReg r; PushImm a; Nor; Dup; Nor;
           PushReg r; PushImm not_a; Nand; Dup; Nand;
           Sub;
           PushImm b;
           Add;
         ]
     | None ->
         [ PushImm mask; PushImm addend; Add ])

  | L2_NorNot ->
    let not_c = Int64.lognot c in
    (match anchor with
     | Some r ->
         (* Zero synthesized via non-linear De Morgan zero knot: no literal 0L or r - r *)
         PushImm not_c :: emit_mba_anchored_zero r mask @ [ Nor ]
     | None ->
         [ PushImm not_c; PushImm 0L; Nor ])

  | L3_NandSelf ->
    let not_c = Int64.lognot c in
    (* Push single constant and duplicate: no adjacent identical literals *)
    [ PushImm not_c; Dup; Nand ]

  | L4_AddNor ->
    let a = mask in
    let diff = Int64.sub c a in
    let not_diff = Int64.lognot diff in
    (match anchor with
     | Some r ->
         [ PushImm a; PushImm not_diff ] @ emit_mba_anchored_zero r mask @ [ Nor; Add ]
     | None ->
         [ PushImm a; PushImm not_diff; PushImm 0L; Nor; Add ])
  | L6_NullspaceZero ->
    (* Anti-Transformer Nullspace strategy:
       Emits a three-part sequence whose net value = c:
         part A: PushImm r1 ; PushImm r2 ; Add          → r1 + r2 (random)
         part B: PushImm r3 ; PushImm r4 ; Add          → r3 + r4 = r1+r2 (random, same sum)
         cancel: Sub                                     → 0
         base:   PushImm c1 ; PushImm c2 ; Add          → c (split via L1)
         merge:  Add                                     → c + 0 = c
       Every token is a fresh 64-bit random constant, making the
       Transformer's token space effectively unbounded. Stack delta = +1. *)
    let r1 = next_int64 rng in
    let r2 = next_int64 rng in
    let r3 = next_int64 rng in
    (* r4 = (r1 + r2) - r3  mod 2^64 so that r3+r4 = r1+r2 *)
    let r4 = Int64.sub (Int64.add r1 r2) r3 in
    let c1 = next_int64 rng in
    let c2 = Int64.sub c c1 in
    (match anchor with
     | Some r ->
         emit_mba_anchored_zero r r1 @
         [ PushImm c1; PushImm c2; Add; Add ]
     | None ->
         [ PushImm r1; PushImm r2; Add;
           PushImm r3; PushImm r4; Add;
           Sub;
           PushImm c1; PushImm c2; Add;
           Add ])

  | L5_Egraph ->
    (try synthesize_egraph ?anchor ~budget:egraph_budget rng c
     with _ ->
       let not_c = Int64.lognot c in
       (match anchor with
        | Some r -> PushImm not_c :: emit_mba_anchored_zero r mask @ [ Nor ]
        | None -> [ PushImm not_c; PushImm 0L; Nor ]))
let find_anchor ops =
  List.find_map (function
    | PushReg r | PopReg r | SetRegImm (r, _) | AddRegImm (r, _) -> Some r
    | _ -> None
  ) ops

(* ── Per-block rewriter ──────────────────────────────────────────────── *)
(** Rewrites PushImm instructions with probability [mba_rate].
    Flag-liveness aware: synthesis is skipped when flags are live after
    the PushImm (every strategy ends with an instruction that sets flags). *)
let rewrite_block ?(egraph_rate = 30) ?(egraph_budget = egraph_const_config)
    ~rng ~scratch_slot:_ mba_rate block =
  let live = Stack_flag_liveness.analyze_arr (Array.of_list block.ops) in
  let anchor = find_anchor block.ops in
  let new_ops =
    List.concat_map (fun (i, op) ->
      match op with
      | PushImm c when (not live.(i + 1)) && maybe rng mba_rate ->
          synthesize_const ?anchor ~egraph_rate ~egraph_budget rng c
      | AddImmImm (a, b) when (not live.(i + 1)) && maybe rng mba_rate ->
          let c = Int64.add a b in
          synthesize_const ?anchor ~egraph_rate ~egraph_budget rng c
      | SubImmImm (a, b) when (not live.(i + 1)) && maybe rng mba_rate ->
          let c = Int64.sub a b in
          synthesize_const ?anchor ~egraph_rate ~egraph_budget rng c
      | _ -> [ op ]
    ) (List.mapi (fun i op -> (i, op)) block.ops)
  in
  { block with ops = new_ops }
(* ── Public API ───────────────────────────────────────────────────────── *)

type mba_config = {
  seed     : int64;
  mba_rate : int;   (** Probability 0–100 of synthesizing each PushImm *)
  egraph_rate : int;  (** Probability 0-100 of choosing the L5 e-graph
                          strategy (default 30 preserves the historical
                          distribution and RNG stream). *)
  egraph_node_limit  : int;
  egraph_time_budget_ms : int;
  egraph_iter_limit  : int;
}

let default_mba_config seed = {
  seed;
  mba_rate = 75;    (* 75% of PushImm instructions get synthesized *)
  egraph_rate = 30;
  egraph_node_limit = 120;
  egraph_time_budget_ms = 80;
  egraph_iter_limit = 5;
}

let egraph_budget_of (cfg : mba_config) =
  egraph_config_of
    ~node_limit:cfg.egraph_node_limit
    ~time_budget_ms:cfg.egraph_time_budget_ms
    ~iter_limit:cfg.egraph_iter_limit

let apply_block ?ctx cfg block =
  let rng = make_rng (Int64.logxor cfg.seed (Int64.of_int (block.id * Int64.to_int block_id_multiplier))) in
  (* Without a context allocator there is no safe scratch slot: slot 0
     is a program register, so the noise is omitted rather than
     corrupting the program. *)
  let scratch_slot =
    match ctx with
    | Some c -> Some (Context_allocator.alloc_scratch c)
    | None -> None
  in
  rewrite_block ~rng ~scratch_slot cfg.mba_rate block


let apply_program ?ctx cfg prog =
  (* Collect blocks in deterministic id order so the output is stable. *)
  let sorted =
    Hashtbl.fold (fun id b acc -> (id, b) :: acc) prog.blocks []
    |> List.sort (fun (a, _) (b, _) -> compare a b)
    |> Array.of_list
  in
  let n = Array.length sorted in
  (* Pre-allocate one scratch slot per block on the (single-threaded) main
     domain so Context_allocator.alloc_scratch is never called in parallel. *)
  let scratch_slots =
    match ctx with
    | None -> Array.make n None
    | Some c ->
        Array.init n (fun _ -> Some (Context_allocator.alloc_scratch c))
  in
  let pool = Random_visa_ports.Domain_pool.global_pool () in
  let out = Array.make n (0, { (snd sorted.(0)) with ops = [] }) in
  Random_visa_ports.Domain_pool.parallel_for pool ~n
    (fun i ->
      let (id, b) = sorted.(i) in
      let scratch_slot = scratch_slots.(i) in
      out.(i) <- (id, rewrite_block
        ~egraph_rate:cfg.egraph_rate
        ~egraph_budget:(egraph_budget_of cfg)
        ~rng:(make_rng (Int64.logxor cfg.seed (Int64.of_int (b.id * Int64.to_int block_id_multiplier))))
        ~scratch_slot cfg.mba_rate b));
  let new_blocks = Hashtbl.create n in
  Array.iter (fun (id, b) -> Hashtbl.replace new_blocks id b) out;
  let context_slots =
    match ctx with
    | Some c -> max prog.context_slots (Context_allocator.total_slots c)
    | None   -> prog.context_slots
  in
  { prog with blocks = new_blocks; context_slots }

let mba_stats prog_before prog_after =
  let count_push_imm prog =
    Hashtbl.fold (fun _ b acc ->
      acc + List.fold_left (fun a op ->
        match op with PushImm _ -> a + 1 | _ -> a
      ) 0 b.ops
    ) prog.blocks 0
  in
  let count_ops prog =
    Hashtbl.fold (fun _ b acc -> acc + List.length b.ops) prog.blocks 0
  in
  let push_before = count_push_imm prog_before in
  let push_after  = count_push_imm prog_after  in
  let ops_before  = count_ops prog_before in
  let ops_after   = count_ops prog_after  in
  let pct_str =
    if push_before = 0 then "0% eliminated"
    else if push_after >= push_before then
      let exp = float_of_int (push_after - push_before) /. float_of_int push_before *. 100.0 in
      Printf.sprintf "+%.0f%% expanded" exp
    else
      let elim = float_of_int (push_before - push_after) /. float_of_int push_before *. 100.0 in
      Printf.sprintf "%.0f%% eliminated" elim
  in
  Printf.sprintf
    "MBA+Egraph: %d PushImm → %d (%s); ops %d → %d"
    push_before push_after pct_str ops_before ops_after
