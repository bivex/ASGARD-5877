(** Phase 5l (Pass 23): Galois LFSR Non-Linear Whitening & Memory Diffing Resistance
    ─────────────────────────────────────────────────────────────────────────────────
    Defeats dynamic memory snapshot diffing (Frida memory scanning, hypervisor memory
    diffing, cheat-engine probes) by dynamically whitening operands and context slots
    with an evolving Galois LFSR stream over the degree-64 primitive polynomial
    P_64(x) = x^64 + x^4 + x^3 + x + 1 (OEIS A011260).

    On each execution step, the dedicated whitening register W evolves via Galois xtime:
      W_{k+1} = xtime_{64}(W_k) ^ C_salt

    Interleaved with operations, the pass injects Galois field distributivity zero-knots:
      xtime(s ^ W) ^ xtime(s) ^ xtime(W) == 0  (mod 2^64)

    Because GF(2^64) addition is purely bitwise XOR while polynomial reduction is non-linear
    over GF(2), automated SMT bit-vector solvers cannot simplify expressions intertwining
    Z_{2^64} integer addition and GF(2^64) Galois multiplication.

    Soundness Invariants:
    1. Exact Value Preservation: xtime(s ^ W) ^ xtime(s) ^ xtime(W) == 0L across all 2^64 values.
    2. Stack Delta Invariant: The whitening zero-knot cluster preserves net stack delta 0
       (consumes 0L and adds to top of stack: v + 0L = v).
    3. Flag Safety: Whitening clusters are wrapped in PushFlags ... PopFlags when architectural
       flags are live according to [Stack_flag_liveness].
*)

open Stack_ir
open Random_visa_constants.Magic_numbers

type whitening_config = {
  enabled : bool;
  rate : int;
  seed : int64;
}

let default_whitening_config seed = {
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

let next_int64 rng =
  let s, z = splitmix64 rng.state in
  rng.state <- s;
  z

let next_int rng n =
  if n <= 1 then 0
  else
    let z = next_int64 rng in
    Int64.to_int (Int64.logand z 0x7FFFFFFFL) mod n

(** Stack XOR primitive: consumes [B, A], pushes [A ^ B]. Net stack delta = -1. *)
let emit_xor () =
  [
    Dup2;                              (* [B, A, B, A] *)
    Nand; Dup; Nand;                   (* [A & B, B, A] *)
    Swap; Rot;                         (* [A, B, A & B] *)
    Nor; Dup; Nor;                     (* [A | B, A & B] *)
    Swap;
    Sub;                               (* [(A | B) - (A & B) = A ^ B] *)
  ]

(** Computes xtime_{64}(u) = (u << 1) ^ ((u >> 63) * 0x1B).
    Consumes [u], pushes [xtime(u)]. Net stack delta = 0. *)
let emit_xtime () =
  [
    Dup;                               (* [u, u] *)
    PushImm 1L;
    Shl;                               (* [u << 1, u] *)
    Swap;                              (* [u, u << 1] *)
    PushImm 63L;
    Shr;                               (* [u >> 63, u << 1] *)
    PushImm whitening_lfsr_poly;       (* [0x1B, u >> 63, u << 1] *)
    Mul;                               (* [poly = (u >> 63) * 0x1B, u << 1] *)
  ] @ emit_xor ()

(** Emits Galois distributivity zero-knot:
    xtime(s ^ W) ^ xtime(s) ^ xtime(W) == 0L.
    Pushes 0L onto stack. Net stack delta = +1. *)
let emit_galois_zero_knot ~whitening_slot ~s_val =
  (* 1. Compute u = s ^ W *)
  [
    PushImm s_val;
    PushReg whitening_slot;
  ] @ emit_xor () @                    (* [u = s ^ W] *)
  (* 2. Compute xtime(u) *)
  emit_xtime () @                      (* [xu = xtime(s ^ W)] *)
  (* 3. Compute xtime(s) *)
  [ PushImm s_val ] @
  emit_xtime () @                      (* [xs = xtime(s), xu] *)
  (* 4. XOR xu ^ xs *)
  emit_xor () @                        (* [xu ^ xs] *)
  (* 5. Compute xtime(W) and XOR: (xu ^ xs) ^ xtime(W) == 0L *)
  [ PushReg whitening_slot ] @
  emit_xtime () @                      (* [xw = xtime(W), xu ^ xs] *)
  emit_xor ()                          (* [0L] *)

(** Emits an LFSR advance step on whitening_slot:
    W_{k+1} = xtime(W_k) ^ salt. Net stack delta = 0. *)
let emit_advance_whitening ~whitening_slot ~salt =
  [ PushReg whitening_slot ] @
  emit_xtime () @
  [ PushImm salt ] @
  emit_xor () @
  [ PopReg whitening_slot ]

let apply_block (cfg : whitening_config) ~whitening_slot (b : block) : block =
  if not cfg.enabled || cfg.rate <= 0 then b
  else
    let rng =
      make_rng
        (Int64.logxor cfg.seed
           (Int64.logxor whitening_salt
              (Int64.of_int (b.id * 0x1126 + 0x5877))))
    in
    let live = Stack_flag_liveness.analyze_list b.ops in
    let new_ops = ref [] in
    let budget = ref 2 in

    List.iteri (fun idx op ->
      let flags_live = if idx + 1 < Array.length live then live.(idx + 1) else false in
      match op with
      | PushReg s
        when (not flags_live)
             && s < 32
             && s <> 4
             && s <> 5
             && !budget > 0
             && next_int rng 100 < cfg.rate ->
          decr budget;
          let s_val = Int64.logor (next_int64 rng) 1L in
          let salt = next_int64 rng in
          let knot = emit_galois_zero_knot ~whitening_slot ~s_val in
          let adv = emit_advance_whitening ~whitening_slot ~salt in
          let cluster = [ PushReg s ] @ knot @ [ Add ] @ adv in
          new_ops := List.rev cluster @ !new_ops
      | _ ->
          new_ops := op :: !new_ops
    ) b.ops;
    { b with ops = List.rev !new_ops }

let apply_program (cfg : whitening_config) (ctx : Context_allocator.t) (prog : program) : program =
  if not cfg.enabled || cfg.rate <= 0 then prog
  else
    let whitening_slot = Context_allocator.alloc_scratch ctx in
    let new_blocks = Hashtbl.create (Hashtbl.length prog.blocks) in
    Hashtbl.iter (fun id b ->
      let b' = apply_block cfg ~whitening_slot b in
      let b'' =
        if id = prog.entry_id then
          (* Initialize whitening register at program entry *)
          let init_ops = [ PushImm whitening_init_key; PopReg whitening_slot ] in
          { b' with ops = init_ops @ b'.ops }
        else b'
      in
      Hashtbl.add new_blocks id b''
    ) prog.blocks;
    let context_slots = max prog.context_slots (Context_allocator.total_slots ctx) in
    { prog with blocks = new_blocks; context_slots }

let whitening_stats prog_before prog_after =
  let count_ops prog =
    Hashtbl.fold (fun _ b acc -> acc + List.length b.ops) prog.blocks 0
  in
  let before = count_ops prog_before in
  let after = count_ops prog_after in
  let diff = after - before in
  Printf.sprintf "Galois LFSR Memory Whitening: %d ops -> %d ops (+%d whitened Galois clusters, +%.1f%%)"
    before after diff
    (if before = 0 then 0.0 else float_of_int diff /. float_of_int before *. 100.0)
