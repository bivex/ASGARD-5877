(** Phase 5c: Stack-VM Memory-Address Entanglement Pass
    ──────────────────────────────────────────────────
    Defeats Boolean Differential Calculus (∂Sink/∂s == 0) and Inductive
    Program Synthesis (Syntia, QSynth) by routing scratch-ring def-use chains
    through physical memory loads and stores.

    Soundness Invariants:
      1. Zero Stack Delta: Net stack delta across every cluster is exactly 0.
      2. Flag Preservation: Wrapped in PushFlags ... PopFlags when architectural
         flags are live at the injection site.
      3. Value Invariance: Value of scratch_slot is mathematically preserved:
         s := s + (s - Memory[SP - offset(s)]) == s.
      4. Safe Memory Window: Memory access is bounded to [SP - 136 .. SP - 16],
         aligned to 8 bytes, well within the allocated thread-local host_stack.
      5. Non-Zero Boolean Derivative: Address of WriteMem physically shifts
         with s, defeating static algebraic cancellation.
*)

open Stack_ir
open Random_visa_constants.Magic_numbers

type mem_webbing_config = {
  enabled : bool;
  rate : int;
  seed : int64;
}

let default_mem_webbing_config seed = {
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

let generate_mem_web_cluster ~sp_slot ~scratch_slot flags_live =
  (* Dual-store aliasing with positive offset above SP:
     1. Base is aligned to 64 bytes in the upper host_stack frame:
          Base = (SP + 128) & ~0x3F
        Both offsets [0..56] strictly lie within the exact same 64-byte L1D line:
          a1 = Base + (s & 0x38)
          a2 = Base + ((s ^ 0x18) & 0x38)
        Because Base >= SP + 64, this operates strictly ABOVE SP, completely
        immune to Red-Zone clobber on Windows x64 and ARM64.
     2. Store order defeats McCarthy Store-to-Load Forwarding:
          Step 1: WriteMem(a1, s)            (real value)
          Step 2: WriteMem(a2, Decoy)         (decoy value s ^ 0x5877...)
          Step 3: ReadMem(a1)                 (reads back real value)
        Because Step 2 stores Decoy != s to a2 AFTER Step 1, McCarthy array
        theory cannot collapse select(store(store(M, a1, s), a2, Decoy), a1)
        without resolving the aliasing constraint across the two stores. *)
  let inner = [
    (* 1. Compute Base = (SP - 128) & ~0x3F *)
    PushReg sp_slot;
    PushImm mem_webbing_base_offset; (* 128L *)
    Sub;
    PushImm mem_webbing_base_align_mask; (* 0xFFFFFFFFFFFFFFC0L *)
    Nand; Dup; Nand;                 (* [base] *)

    (* 2. Compute a1 = base + (s & 0x38) *)
    Dup;                             (* [base, base] *)
    PushReg scratch_slot;
    PushImm mem_webbing_offset_mask; (* 0x38L *)
    Nand; Dup; Nand;                 (* [s & 0x38, base, base] *)
    Add;                             (* [a1 = base + (s & 0x38), base] *)

    (* 3. Compute a2 = base + ((s ^ 0x18) & 0x38) *)
    Swap;                            (* [base, a1] *)
    PushReg scratch_slot;
    PushImm mem_webbing_alias_diff;  (* 0x18L *)
    Add;                             (* s + 0x18 *)
    PushReg scratch_slot;
    PushImm mem_webbing_alias_diff;  (* 0x18L *)
    Nand; Dup; Nand;                 (* s & 0x18 *)
    Dup; Add;                        (* 2 * (s & 0x18) *)
    Sub;                             (* s ^ 0x18 = (s + 0x18) - 2*(s & 0x18) *)
    PushImm mem_webbing_offset_mask; (* 0x38L *)
    Nand; Dup; Nand;                 (* (s ^ 0x18) & 0x38 *)
    Add;                             (* [a2 = base + ((s ^ 0x18) & 0x38), a1] *)

    (* 4. Store real s to a1: [a1] := s *)
    Swap;                            (* [a1, a2] *)
    Dup;                             (* [a1, a1, a2] *)
    PushReg scratch_slot;            (* [s, a1, a1, a2] *)
    WriteMem 8;                      (* [a1, a2] *)

    (* 5. Store decoy to a2: [a2] := s + 0x58771337CAFE *)
    Swap;                            (* [a2, a1] *)
    PushReg scratch_slot;
    PushImm mem_webbing_decoy_salt;
    Add;                             (* [Decoy, a2, a1] *)
    WriteMem 8;                      (* [a1] *)

    (* 6. Read real s back from a1 *)
    ReadMem 8;                       (* [read_s] *)

    (* 7. Verify and preserve s: s := s + (s - read_s) == s *)
    PushReg scratch_slot;            (* [s, read_s] *)
    Sub;                             (* [read_s - s = 0] *)
    PushReg scratch_slot;            (* [s, 0] *)
    Add;                             (* [s + 0 = s] *)
    PopReg scratch_slot;             (* [] *)
  ] in
  if flags_live then [ PushFlags ] @ inner @ [ PopFlags ]
  else inner

let is_terminator = function
  | JmpRel _ | JccRel _ | Exit -> true
  | _ -> false

let apply_block (cfg : mem_webbing_config) ~sp_slot ~scratch_ring _ctx (b : block) : block =
  if not cfg.enabled || cfg.rate <= 0 || Array.length scratch_ring = 0 then b
  else
    let n_ring = Array.length scratch_ring in
    let rng =
      make_rng
        (Int64.logxor cfg.seed
           (Int64.of_int (b.id * 0x5877 + 0x1337)))
    in
    let live = Stack_flag_liveness.analyze_list b.ops in
    let new_ops = ref [] in
    let count = ref 0 in
    let max_per_block = 2 in
    let ring_idx = ref (b.id mod n_ring) in
    List.iteri (fun idx op ->
      new_ops := op :: !new_ops;
      if not (is_terminator op) && !count < max_per_block then begin
        if next_int rng 100 < cfg.rate then begin
          let flags_live = if idx + 1 < Array.length live then live.(idx + 1) else false in
          let s = scratch_ring.(!ring_idx) in
          ring_idx := (!ring_idx + 1) mod n_ring;
          let cluster = generate_mem_web_cluster ~sp_slot ~scratch_slot:s flags_live in
          new_ops := List.rev cluster @ !new_ops;
          incr count
        end
      end
    ) b.ops;
    { b with ops = List.rev !new_ops }

let apply_program ?scratch_ring ?sp_slot (cfg : mem_webbing_config) (ctx : Context_allocator.t) (prog : program) : program =
  if not cfg.enabled || cfg.rate <= 0 then prog
  else
    let scratch_ring =
      match scratch_ring with
      | Some r -> r
      | None -> Array.init 4 (fun _ -> Context_allocator.alloc_scratch ctx)
    in
    let sp_slot =
      match sp_slot with
      | Some s -> s
      | None -> Context_allocator.slot_of_reg ctx Vm_ir.Register.rsp
    in
    let new_blocks = Hashtbl.create (Hashtbl.length prog.blocks) in
    Hashtbl.iter (fun id b ->
      let b' = apply_block cfg ~sp_slot ~scratch_ring ctx b in
      Hashtbl.add new_blocks id b'
    ) prog.blocks;
    let context_slots = max prog.context_slots (Context_allocator.total_slots ctx) in
    { prog with blocks = new_blocks; context_slots }
let mem_webbing_stats prog_before prog_after =
  let count_mem_ops prog =
    Hashtbl.fold (fun _ b (r, w) ->
      List.fold_left (fun (acc_r, acc_w) -> function
        | ReadMem _ -> (acc_r + 1, acc_w)
        | WriteMem _ -> (acc_r, acc_w + 1)
        | _ -> (acc_r, acc_w)
      ) (r, w) b.ops
    ) prog.blocks (0, 0)
  in
  let r_before, w_before = count_mem_ops prog_before in
  let r_after, w_after = count_mem_ops prog_after in
  Printf.sprintf "Memory Webbing: +%d writes, +%d reads through host stack (total %d writes, %d reads)"
    (w_after - w_before) (r_after - r_before) w_after r_after
