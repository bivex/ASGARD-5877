(** ASGARD-5877: Stack-VM Bytecode VDF & Multi-Page SoftMMU Stalling Pass.
    Academic Foundations:
    - arXiv:2211.08162 (Single Squaring Verifiable Delay Functions in Groups of Known Order)
    - arXiv:2105.14273 (EXAMINER: CPU Emulator vs Real Hardware Deviations & SoftMMU Eviction)
    - ACM CCS'11 (The Power of Procrastination: Non-Monotonic Data-Coupled Stalling)

    Synthesizes a verifiable delay loop with:
    1. VDF Squaring mod p = 0xFFFFFFFB (sequential, non-parallelizable)
    2. Non-monotonic chaotic Collatz/attractor loop scheduling (breaks DSE / loop detection)
    3. Sparse 16-page SoftMMU thrashing (forces QEMU/Unicorn/Sogen soft-TLB re-walks)
    4. Dual-rail conditional deraille: the exit block re-derives both rails
       (slot_x == x_n, slot_s == s_n) and jumps into an endless trap block on
       any mismatch — a patched counter skips the loop but never reaches the
       original entry, so the sandbox burns its whole budget. *)

open Stack_ir
open Vm_ir
open Flags
open Constants.Magic_numbers

type vdf_stall_config = {
  n_iterations : int;
  seed : int64;
  sparse_pages : int;
}

let default_config = {
  n_iterations = 28_475;   (* calibrated: 1.000 hr in Sogen @ 0.1258 s/iter *)
  seed = comp_stall_chebyshev_salt;
  sparse_pages = 16;
}

let compute_vdf_key ~(seed : int64) ~(n_iterations : int) : int64 * int64 =
  let p = comp_stall_vdf_prime in
  let raw_x0 = Int64.logand (Int64.logxor seed comp_stall_chebyshev_salt) 0x7FFFFFFFL in
  let x0 = if raw_x0 < 2L then Int64.add raw_x0 2L else raw_x0 in
  let s0 =
    Int64.logxor
      (Int64.logor (Int64.shift_right_logical seed 17) (Int64.shift_left seed 47))
      0x5877A55A1337BEEFL
  in
  let rec loop i x s =
    if i >= n_iterations then (x, s)
    else
      let x2 = Int64.mul x x in
      let x_next = Int64.unsigned_rem x2 p in
      let s_next =
        if Int64.logand s 1L = 0L then
          Int64.logxor (Int64.shift_right_logical s 1) x_next
        else
          Int64.add (Int64.mul 3L s) 0x5877L
      in
      loop (i + 1) x_next s_next
  in
  loop 0 x0 s0

let apply_vdf_stall ?ctx ?(config = default_config) (prog : program) : program =
  if config.n_iterations <= 0 then prog
  else
    let n_iters = config.n_iterations in
    let seed = config.seed in
    let p = comp_stall_vdf_prime in
    let x_n, s_n = compute_vdf_key ~seed ~n_iterations:n_iters in
    let raw_x0 = Int64.logand (Int64.logxor seed comp_stall_chebyshev_salt) 0x7FFFFFFFL in
    let x0 = if raw_x0 < 2L then Int64.add raw_x0 2L else raw_x0 in
    let s0 =
      Int64.logxor
        (Int64.logor (Int64.shift_right_logical seed 17) (Int64.shift_left seed 47))
        0x5877A55A1337BEEFL
    in

    (* Allocate fresh block IDs *)
    let max_id = Hashtbl.fold (fun id _ acc -> max acc id) prog.blocks 0 in
    let vdf_init_id      = max_id + 1 in
    let vdf_check_id     = max_id + 2 in
    let vdf_split_id     = max_id + 3 in
    let vdf_body_even_id = max_id + 4 in
    let vdf_body_odd_id  = max_id + 5 in
    let vdf_exit_id     = max_id + 6 in
    let vdf_trap_id     = max_id + 7 in

    (* Allocate scratch context slots *)
    let slot_counter, slot_x, slot_s, slot_tmp_a, slot_tmp_b, slot_sp, new_context_slots =
      match ctx with
      | Some c ->
          let sc = Context_allocator.alloc_scratch c in
          let sx = Context_allocator.alloc_scratch c in
          let ss = Context_allocator.alloc_scratch c in
          let ta = Context_allocator.alloc_scratch c in
          let tb = Context_allocator.alloc_scratch c in
          let sp = 4 in
          (sc, sx, ss, ta, tb, sp, max prog.context_slots (Context_allocator.total_slots c))
      | None ->
          let base = max 6 prog.context_slots in
          (base, base + 1, base + 2, base + 3, base + 4, 4, base + 5)
    in
    let orig_entry = prog.entry_id in

    (* 1. Init block *)
    let init_ops = [
      PushImm (Int64.of_int n_iters);
      PopReg slot_counter;
      PushImm x0;
      PopReg slot_x;
      PushImm s0;
      PopReg slot_s;
      JmpRel vdf_check_id;
    ] in
    let init_block = {
      id = vdf_init_id;
      label = Printf.sprintf "vdf_init_%d" vdf_init_id;
      ops = init_ops;
    } in

    (* 2. Check block: counter == 0 *)
    let check_ops = [
      PushReg slot_counter;
      PushImm 0L;
      Cmp;
      JccRel (vdf_exit_id, E);
      JmpRel vdf_split_id;
    ] in
    let check_block = {
      id = vdf_check_id;
      label = Printf.sprintf "vdf_check_%d" vdf_check_id;
      ops = check_ops;
    } in

    (* 3. Split block: checks bit 0 of slot_s *)
    let split_ops = [
      PushReg slot_s;
      PushImm 1L;
      Nand;
      Dup;
      Nand;
      PushImm 0L;
      Cmp;
      JccRel (vdf_body_odd_id, NE);
      JmpRel vdf_body_even_id;
    ] in
    let split_block = {
      id = vdf_split_id;
      label = Printf.sprintf "vdf_split_%d" vdf_split_id;
      ops = split_ops;
    } in

    (* 4. Memory touch operations: 16-page SoftMMU thrashing *)
    let mem_touch_ops = [
      PushReg slot_sp;
      PushReg slot_s;
      PushImm 0x7000L;
      Nand;
      Dup;
      Nand;
      PushReg slot_x;
      PushImm 0x1F8L;
      Nand;
      Dup;
      Nand;
      Add;
      PushImm 16L;
      Add;
      Sub;                      (* [addr] *)
      Dup;                      (* [addr, addr] *)
      PushReg slot_x;           (* [x_next, addr, addr] *)
      WriteMem 8;               (* [addr] *)
      ReadMem 8;                (* [read_val = x_next] *)
      PushReg slot_x;           (* [x_next, read_val] *)
      Sub;                      (* [x_next - read_val = 0] *)
      PushReg slot_x;           (* [x_next, 0] *)
      Add;                      (* [x_next] *)
      PopReg slot_x;            (* [] *)
      PushFlags;
      PopFlags;
    ] in

    (* 5a. Body Even *)
    let body_even_ops = [
      (* VDF squaring: x_next = x^2 - ((x^2 / P) * P) *)
      PushReg slot_x;
      Dup;
      Mul;
      PopReg slot_tmp_a;
      PushReg slot_tmp_a;
      PushImm p;
      Div;
      PushImm p;
      Mul;
      PopReg slot_tmp_b;
      PushReg slot_tmp_a;
      PushReg slot_tmp_b;
      Sub;
      PopReg slot_x;

      (* Chaotic orbit: s_next = (s >> 1) ^ x_next *)
      PushReg slot_s;
      PushImm 1L;
      Shr;
      PopReg slot_tmp_a;
      PushReg slot_x;
      PopReg slot_tmp_b;
      PushReg slot_tmp_a;
      PushReg slot_tmp_b;
      Nor;
      Dup;
      Nor;
      PushReg slot_tmp_a;
      PushReg slot_tmp_b;
      Nand;
      Dup;
      Nand;
      Sub;
      PopReg slot_s;
    ]
    @ mem_touch_ops
    @ [
      PushReg slot_counter;
      PushImm 1L;
      Sub;
      PopReg slot_counter;
      JmpRel vdf_check_id;
    ] in
    let body_even_block = {
      id = vdf_body_even_id;
      label = Printf.sprintf "vdf_body_even_%d" vdf_body_even_id;
      ops = body_even_ops;
    } in

    (* 5b. Body Odd *)
    let body_odd_ops = [
      (* VDF squaring: x_next = x^2 - ((x^2 / P) * P) *)
      PushReg slot_x;
      Dup;
      Mul;
      PopReg slot_tmp_a;
      PushReg slot_tmp_a;
      PushImm p;
      Div;
      PushImm p;
      Mul;
      PopReg slot_tmp_b;
      PushReg slot_tmp_a;
      PushReg slot_tmp_b;
      Sub;
      PopReg slot_x;

      (* Chaotic orbit: s_next = 3 * s + 0x5877L *)
      PushReg slot_s;
      PushImm 3L;
      Mul;
      PushImm 0x5877L;
      Add;
      PopReg slot_s;
    ]
    @ mem_touch_ops
    @ [
      PushReg slot_counter;
      PushImm 1L;
      Sub;
      PopReg slot_counter;
      JmpRel vdf_check_id;
    ] in
    let body_odd_block = {
      id = vdf_body_odd_id;
      label = Printf.sprintf "vdf_body_odd_%d" vdf_body_odd_id;
      ops = body_odd_ops;
    } in

    (* 6. Exit blocks: dual-rail conditional deraille, ONE conditional per
       block (the encoder supports at most one JccRel per block — a second
       JccRel in the same block mis-resolves its target at bytecode level).
       Rail A: (slot_x - x_n) == 0 else trap;  then fall into rail B block.
       Rail B: (slot_s - s_n) == 0 else trap;  then jump to the original entry. *)
    let exit_ops = [
      (* delta_x = slot_x - x_n *)
      PushReg slot_x;
      PushImm x_n;
      Sub;
      (* delta_s = slot_s - s_n *)
      PushReg slot_s;
      PushImm s_n;
      Sub;
      (* combined = delta_x | delta_s  (OR: no cancellation, nonzero iff any
         rail mismatches).  Nor pops both rails and pushes ~(dx|ds); Dup+Nor
         push dx|ds — net effect: the two rails collapse to their OR. *)
      Nor;
      Dup;
      Nor;
      PushImm 0L;
      Cmp;
      JccRel (vdf_trap_id, NE);
      JmpRel orig_entry;
    ] in
    let exit_block = {
      id = vdf_exit_id;
      label = Printf.sprintf "vdf_exit_%d" vdf_exit_id;
      ops = exit_ops;
    } in

    (* 7. Trap block: jumps back into the check block, closing the cycle
       check → exit → trap → check → … — an endless op-burning loop with no
       self-referencing block (self-target JmpRel is not encodable). *)
    let trap_block = {
      id = vdf_trap_id;
      label = Printf.sprintf "vdf_trap_%d" vdf_trap_id;
      ops = [ JmpRel vdf_check_id ];
    } in



    let new_blocks = Hashtbl.copy prog.blocks in
    Hashtbl.replace new_blocks vdf_init_id init_block;
    Hashtbl.replace new_blocks vdf_check_id check_block;
    Hashtbl.replace new_blocks vdf_split_id split_block;
    Hashtbl.replace new_blocks vdf_body_even_id body_even_block;
    Hashtbl.replace new_blocks vdf_body_odd_id body_odd_block;
    Hashtbl.replace new_blocks vdf_exit_id exit_block;
    Hashtbl.replace new_blocks vdf_trap_id trap_block;

    {
      entry_id = vdf_init_id;
      blocks = new_blocks;
      context_slots = new_context_slots;
    }
