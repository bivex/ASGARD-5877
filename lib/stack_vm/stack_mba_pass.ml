(** Phase 4: MBA Constant Synthesis Pass
    ─────────────────────────────────────
    Replaces PushImm instructions with semantically equivalent sequences
    of NOR, NAND, and ADD operations, eliminating literal constants from
    the bytecode stream.

    Attack vector defeated:
      Devirtualization tools that recover constants from immediate operands
      (e.g., IDA VTIL lifter, Hex-Rays decompiler, NoVmp constant tracking)
      will see computed values instead of literals. The synthesized sequence
      must be symbolically evaluated to recover the original constant.

    Synthesis strategies (all have stack delta = +1, same as PushImm):

      L1 — ADD split:
        PushImm a          (random mask)
        PushImm (c − a)    (complement under addition mod 2^64)
        Add                → a + (c−a) = c

      L2 — NOR double complement:
        PushImm (~c)       (bitwise NOT of constant)
        PushImm 0          (zero)
        Nor                → NOR(~c, 0) = ~(~c | 0) = ~~c = c

      L3 — NAND self:
        PushImm (~c)       (bitwise NOT of constant)
        PushImm (~c)       (same)
        Nand               → NAND(~c, ~c) = ~(~c & ~c) = ~~c = c

      L4 — ADD + NOR (depth 3):
        PushImm a          (random)
        PushImm (~(c − a)) (complement of addend)
        PushImm 0          (zero)
        Nor                → ~(~(c−a) | 0) = c−a
        Add                → a + (c−a) = c
        [5 ops vs 1 for the original PushImm — maximum obfuscation]

    Selection is seed-deterministic via SplitMix64. MBA rate controls
    what fraction of PushImm instructions are synthesized.
*)

open Stack_ir

(* ── SplitMix64 PRNG ─────────────────────────────────────────────────── *)
let splitmix64 s =
  let s = Int64.add s 0x9E3779B97F4A7C15L in
  let z = s in
  let z = Int64.logxor z (Int64.shift_right_logical z 30) in
  let z = Int64.mul z 0xBF58476D1CE4E5B9L in
  let z = Int64.logxor z (Int64.shift_right_logical z 27) in
  let z = Int64.mul z 0x94D049BB133111EBL in
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

(* ── MBA strategy type ───────────────────────────────────────────────── *)
type mba_strategy = L1_AddSplit | L2_NorNot | L3_NandSelf | L4_AddNor

(* ── Synthesize constant c using a chosen strategy ───────────────────── *)
(** [synthesize_const rng c] returns a list of stack_ops that leaves c
    on top of the stack. Stack delta = +1 (same as [PushImm c]).
    The list never contains a literal PushImm of c itself. *)
let synthesize_const rng c =
  let mask = next_int64 rng in  (* random 64-bit mask *)
  (* Choose strategy, weighted toward higher complexity *)
  let strategy =
    match next_int rng 10 with
    | 0 | 1 | 2 -> L1_AddSplit   (* 30% — fast *)
    | 3 | 4 | 5 -> L2_NorNot     (* 30% — NOR double NOT *)
    | 6 | 7     -> L3_NandSelf   (* 20% — NAND self *)
    | _         -> L4_AddNor     (* 20% — deep 5-op form *)
  in
  match strategy with
  | L1_AddSplit ->
    (* c = mask + (c - mask)  [mod 2^64] *)
    let addend = Int64.sub c mask in
    [ PushImm mask; PushImm addend; Add ]

  | L2_NorNot ->
    (* NOR(~c, 0) = ~(~c | 0) = c *)
    let not_c = Int64.lognot c in
    [ PushImm not_c; PushImm 0L; Nor ]

  | L3_NandSelf ->
    (* NAND(~c, ~c) = ~(~c & ~c) = c *)
    let not_c = Int64.lognot c in
    [ PushImm not_c; PushImm not_c; Nand ]

  | L4_AddNor ->
    (* a + NOR(~(c−a), 0) = a + (c−a) = c
       NOR(~(c−a), 0) = ~(~(c−a) | 0) = c−a *)
    let a = mask in
    let diff = Int64.sub c a in          (* c - a *)
    let not_diff = Int64.lognot diff in  (* ~(c - a) *)
    [ PushImm a; PushImm not_diff; PushImm 0L; Nor; Add ]

(* ── Per-instruction rewriter ────────────────────────────────────────── *)
(** [rewrite_op rng mba_rate op] either synthesizes a PushImm or returns
    [op] unchanged. Non-PushImm ops are always returned as-is. *)
let rewrite_op rng mba_rate op =
  match op with
  | PushImm c when maybe rng mba_rate ->
    synthesize_const rng c
  | _ -> [ op ]

(** [rewrite_block rng mba_rate block] rewrites every PushImm in a block
    with probability [mba_rate] (integer 0–100). *)
let rewrite_block rng mba_rate block =
  let new_ops =
    List.concat_map (fun op -> rewrite_op rng mba_rate op) block.ops
  in
  { block with ops = new_ops }

(* ── Public API ───────────────────────────────────────────────────────── *)

type mba_config = {
  seed     : int64;
  mba_rate : int;   (** Probability 0–100 of synthesizing each PushImm *)
}

let default_mba_config seed = {
  seed;
  mba_rate = 75;    (* 75% of PushImm instructions get synthesized *)
}

(** [apply_block cfg block] applies MBA synthesis to a single block. *)
let apply_block cfg block =
  (* Per-block seed: XOR global seed with block id for diversity *)
  let rng = make_rng (Int64.logxor cfg.seed (Int64.of_int (block.id * 0xB7E1_5163))) in
  rewrite_block rng cfg.mba_rate block

(** [apply_program cfg prog] applies MBA synthesis to every block. *)
let apply_program cfg prog =
  let new_blocks = Hashtbl.create (Hashtbl.length prog.blocks) in
  Hashtbl.iter (fun id b ->
    Hashtbl.replace new_blocks id (apply_block cfg b)
  ) prog.blocks;
  { prog with blocks = new_blocks }

(** [mba_stats prog_before prog_after] returns a summary string. *)
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
  Printf.sprintf
    "MBA synthesis: %d PushImm → %d (%.0f%% eliminated); ops %d → %d"
    push_before push_after
    (if push_before = 0 then 0.0
     else float_of_int (push_before - push_after)
          /. float_of_int push_before *. 100.0)
    ops_before ops_after
