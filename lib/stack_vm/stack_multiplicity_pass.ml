(** Phase 2a: Stack-VM Handler Multiplicity & Metamorphic Synthesis Pass
    ───────────────────────────────────────────────────────────────────
    Expands stack operations into semantically identical metamorphic
    sequences:

      - Structural identities (flag-neutral):
          Swap ≡ Swap·Swap·Swap
          Dup  ≡ Dup·Swap·Swap
          Rot  ≡ Rot^4
          PushReg r ≡ PushReg r·Dup·PopReg r

      - Mixed Boolean-Arithmetic (MBA) & Semantic ALU Identities (flags dead):
          Add ≡ MBA De Morgan duality:
                x + y ≡ - (Nor(x, y) + Nand(x, y) + 2)
                Evaluated purely on stack via:
                  Dup2, Nand, Rot, Rot, Nor, Add, PushImm 2L, Add, PushImm 0L, Swap, Sub
          Sub ≡ Linear MBA Disjoint Projection:
                x - y ≡ (x ∧ ¬y) - (¬x ∧ y)
                Evaluated purely on stack via:
                  Dup2, Swap, Dup, Nor, Nor, Rot, Swap, Rot, Dup, Nor, Rot, Nor, Sub
          PushImm v ≡ 5-NOR XOR Circuit Decomposition:
                v = v1 ^ v2 where v1 is random
                Evaluated purely on stack via:
                  PushImm v1, PushImm v2, Dup2, Nor, Dup, Rot, Nor, Swap, Rot, Nor, Nor, Dup, Nor

    Soundness Invariants:
      1. SMT-Resilience: Replaces trivial single-pattern peephole targets with
         multivariate boolean-arithmetic polynomials requiring full SMT/Z3 solvers
         or e-graph saturation to reverse.
      2. Flag-Safety: MBA expansions modify flags and are strictly gated by
         [Stack_flag_liveness.analyze_list] so architectural flags are dead.
      3. Zero Net Stack Delta: Every expansion preserves the exact stack delta
         of the replaced operation (-1 for Add/Sub, +1 for PushImm, 0 for Swap/Rot).
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

(** MBA Add:
    x + y ≡ - (Nor(x, y) + Nand(x, y) + 2)
    Stack begins with [y, x] (y on top).
    Trace:
      Dup2          [y, x, y, x]
      Nand          [Nand(x, y), y, x]
      Rot; Rot      [y, x, Nand(x, y)]
      Nor           [Nor(x, y), Nand(x, y)]
      Add           [Nor + Nand]
      PushImm 2L    [2, Nor + Nand]
      Add           [Nor + Nand + 2]
      PushImm 0L    [0, Nor + Nand + 2]
      Swap; Sub     [ - (Nor + Nand + 2) ] = [ x + y ]
    Net result: [x + y] on stack, 11 operations, net stack delta = -1. *)
let expand_add_mba () =
  [
    Dup2;
    Nand;
    Rot;
    Rot;
    Nor;
    Add;
    PushImm 2L;
    Add;
    PushImm 0L;
    Swap;
    Sub;
  ]

(** MBA Sub:
    x - y ≡ (x ∧ ¬y) - (¬x ∧ y)
    Stack begins with [y, x] (y on top).
    Trace:
      Dup2          [y, x, y, x]
      Swap; Dup     [x, x, y, y, x]
      Nor           [~x, y, y, x]
      Nor           [(x & ~y), y, x]
      Rot; Swap; Rot [y, (x & ~y), x]
      Dup; Nor      [~y, (x & ~y), x]
      Rot; Nor      [(~x & y), (x & ~y)]
      Sub           [ (x & ~y) - (~x & y) ] = [ x - y ]
    Net result: [x - y] on stack, 13 operations, net stack delta = -1. *)
let expand_sub_mba () =
  [
    Dup2;
    Swap;
    Dup;
    Nor;
    Nor;
    Rot;
    Swap;
    Rot;
    Dup;
    Nor;
    Rot;
    Nor;
    Sub;
  ]

(** Metamorphic expansion of an op. [flag_dead] indicates whether condition
    flags are dead after this instruction, permitting ALU-based expansions. *)
let expand_op rng ~s1 ~s2 ~s3 flag_dead = function
  | Swap ->
      if next_int rng 2 = 0 then
        (* Desugar Swap via scratch slots: defeats Swap; Swap; Swap pattern matchers *)
        [ PopReg s1; PopReg s2; PushReg s1; PushReg s2 ]
      else
        [ Swap ]

  | Dup ->
      if next_int rng 2 = 0 then
        (* Desugar Dup via scratch slot: defeats Dup; Swap; Swap pattern matchers *)
        [ PopReg s1; PushReg s1; PushReg s1 ]
      else
        [ Dup ]

  | Rot ->
      if next_int rng 2 = 0 then
        (* Desugar Rot via scratch slots: defeats Rot*4 pattern matchers *)
        [ PopReg s1; PopReg s2; PopReg s3; PushReg s2; PushReg s1; PushReg s3 ]
      else
        [ Rot ]

  | PushReg r when flag_dead ->
      if next_int rng 2 = 0 then
        (* Algebraic register identity: (r - r) + r == r *)
        [ PushReg r; PushReg r; Sub; PushReg r; Add ]
      else
        [ PushReg r ]
  | PushReg r ->
      [ PushReg r ]

  | Add when flag_dead ->
      expand_add_mba ()

  | Sub when flag_dead ->
      expand_sub_mba ()

  | PushImm v when flag_dead ->
      let v1 = next_int64 rng in
      let v2 = Int64.sub v v1 in
      (* Register-anchored non-linear sum split: defeats 5-NOR XOR and constant folding *)
      [ PushReg s1; PushImm v1; Add; PushReg s1; Sub; PushImm v2; Add ]
  | other -> [ other ]
let is_expandable flag_dead = function
  | Swap | Dup | Rot | PushReg _ -> true
  | Add | Sub | PushImm _ -> flag_dead
  | _ -> false

let apply_block (cfg : multiplicity_config) ctx (b : block) : block =
  if not cfg.enabled || cfg.rate <= 0 then b
  else
    let rng =
      make_rng
        (Int64.logxor cfg.seed
           (Int64.of_int
              (b.id * Int64.to_int salt_multiplicity_block_mul
               + Int64.to_int salt_multiplicity_block_add)))
    in
    let s1 = Context_allocator.alloc_scratch ctx in
    let s2 = Context_allocator.alloc_scratch ctx in
    let s3 = Context_allocator.alloc_scratch ctx in
    let live = Stack_flag_liveness.analyze_list b.ops in
    let new_ops = ref [] in
    List.iteri (fun i op ->
      let flag_dead = not live.(i + 1) in
      if is_expandable flag_dead op && maybe rng cfg.rate then
        let expanded = expand_op rng ~s1 ~s2 ~s3 flag_dead op in
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
