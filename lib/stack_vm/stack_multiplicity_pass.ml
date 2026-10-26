(** Phase 2a: Stack-VM Handler Multiplicity & Metamorphic Synthesis Pass
    ───────────────────────────────────────────────────────────────────
    Expands stack operations into semantically identical metamorphic
    sequences:

      - Structural identities (flag-neutral):
          Swap ≡ Swap·Swap·Swap
          Dup  ≡ Dup·Swap·Swap
          Rot  ≡ Rot^4
          PushReg r ≡ PushReg r·Dup·PopReg r

      - Semantic ALU identities (active when condition flags are dead):
          Add ≡ PushImm 0L · Swap · Sub · Sub    [a + b ≡ a - (-b)]
          Sub ≡ Dup · Nor · Add · PushImm 1L · Add [a - b ≡ a + ~b + 1]
          PushImm v ≡ PushImm v1 · PushImm v2 · 5-NOR XOR circuit [v1 ^ v2 = v]

    By requiring non-trivial boolean algebra and sign reasoning (SMT/Z3 level)
    to deobfuscate, these expansions defeat local 1-pass pattern matchers.
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

(** PushImm v decomposed via 5-NOR XOR circuit:
    v = v1 ^ v2 where v1 is random, v2 = v ^ v1.
    Stack trace starting from []:
      PushImm v1; PushImm v2;           [v2, v1]
      Dup2; Nor;                        [d, v2, v1]   where d = ~(v1 | v2)
      Dup; Rot; Nor;                    [b, d, v1]    where b = ~(d | v2)
      Swap; Rot; Nor;                   [a, b]        where a = ~(d | v1)
      Nor; Dup; Nor;                    [v]           where v = ~(a | b)
    Net result: exactly [v] pushed, exactly 11 operations. *)
let expand_push_imm_xor rng v =
  let v1 = next_int64 rng in
  let v2 = Int64.logxor v v1 in
  [
    PushImm v1;
    PushImm v2;
    Dup2;
    Nor;
    Dup;
    Rot;
    Nor;
    Swap;
    Rot;
    Nor;
    Nor;
    Dup;
    Nor;
  ]

(** Metamorphic expansion of an op. [flag_dead] indicates whether condition
    flags are dead after this instruction, permitting ALU-based expansions. *)
let expand_op rng flag_dead = function
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

  | Add when flag_dead ->
      (* a + b ≡ a - (-b) via PushImm 0L; Swap; Sub; Sub *)
      [ PushImm 0L; Swap; Sub; Sub ]

  | Sub when flag_dead ->
      (* a - b ≡ a + ~b + 1 via Dup; Nor; Add; PushImm 1L; Add *)
      [ Dup; Nor; Add; PushImm 1L; Add ]

  | PushImm v when flag_dead ->
      expand_push_imm_xor rng v

  | other -> [ other ]

let is_expandable flag_dead = function
  | Swap | Dup | Rot | PushReg _ -> true
  | Add | Sub | PushImm _ -> flag_dead
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
    let live = Stack_flag_liveness.analyze_list b.ops in
    let new_ops = ref [] in
    List.iteri (fun i op ->
      let flag_dead = not live.(i + 1) in
      if is_expandable flag_dead op && maybe rng cfg.rate then
        let expanded = expand_op rng flag_dead op in
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
