(** ASGARD-5877: Stack-VM Bytecode Computational Stalling Pass.
    Injects a non-linear dynamical stall loop directly into the program
    bytecode (Stack-IR), ensuring computational stalling runs exclusively
    within the interpreted VM rather than in native host prologue code. *)

open Stack_ir
open Vm_ir
open Flags
open Random_visa_constants.Magic_numbers

type stall_config = {
  n_iterations : int;
  seed : int64;
  variant : string;
}

let default_config = {
  n_iterations = 50_000;
  seed = comp_stall_chebyshev_salt;
  variant = "ergodic";
}

let apply_stall ?ctx ?(config = default_config) (prog : program) : program =
  if config.n_iterations <= 0 then prog
  else
    let n_iters = config.n_iterations in
    let seed = config.seed in
    let key_mat = Comp_stall.Comp_stall_engine.compute_ergodic_key ~seed ~n_iterations:n_iters in
    let c_const = key_mat.c_const in
    let x0 = key_mat.x0 in
    let x_n = key_mat.x_n in

    (* Allocate fresh block IDs *)
    let max_id = Hashtbl.fold (fun id _ acc -> max acc id) prog.blocks 0 in
    let stall_init_id  = max_id + 1 in
    let stall_check_id = max_id + 2 in
    let stall_body_id  = max_id + 3 in
    let stall_exit_id  = max_id + 4 in

    (* Allocate 2 scratch context slots via Context_allocator if provided *)
    let slot_counter, slot_state, new_context_slots =
      match ctx with
      | Some c ->
          let sc = Context_allocator.alloc_scratch c in
          let ss = Context_allocator.alloc_scratch c in
          (sc, ss, max prog.context_slots (Context_allocator.total_slots c))
      | None ->
          (prog.context_slots, prog.context_slots + 1, prog.context_slots + 2)
    in
    let orig_entry = prog.entry_id in

    (* 1. Init block: sets counter and state, jumps to check block *)
    let init_ops = [
      PushImm (Int64.of_int n_iters);
      PopReg slot_counter;
      PushImm x0;
      PopReg slot_state;
      JmpRel stall_check_id;
    ] in
    let init_block = {
      id = stall_init_id;
      label = Printf.sprintf "stall_init_%d" stall_init_id;
      ops = init_ops;
    } in

    (* 2. Check block: if counter == 0 goto exit, else goto body *)
    let check_ops = [
      PushReg slot_counter;
      PushImm 0L;
      Cmp;
      JccRel (stall_exit_id, E);
      JmpRel stall_body_id;
    ] in
    let check_block = {
      id = stall_check_id;
      label = Printf.sprintf "stall_check_%d" stall_check_id;
      ops = check_ops;
    } in

    (* 3. Body block: x_next = x + 2x^2 + 4x^3 + c, cnt = cnt - 1, goto check *)
    let body_ops = [
      (* x_next = x + 2*x^2 + 4*x^3 + c *)
      PushReg slot_state;       (* [x] *)
      Dup;                      (* [x, x] *)
      Mul;                      (* [x^2] *)
      Dup;                      (* [x^2, x^2] *)
      PushReg slot_state;       (* [x, x^2, x^2] *)
      Mul;                      (* [x^3, x^2] *)
      PushImm 4L;               (* [4, x^3, x^2] *)
      Mul;                      (* [4*x^3, x^2] *)
      Swap;                     (* [x^2, 4*x^3] *)
      PushImm 2L;               (* [2, x^2, 4*x^3] *)
      Mul;                      (* [2*x^2, 4*x^3] *)
      Add;                      (* [2*x^2 + 4*x^3] *)
      PushReg slot_state;       (* [x, 2*x^2 + 4*x^3] *)
      Add;                      (* [x + 2*x^2 + 4*x^3] *)
      PushImm c_const;          (* [c, x + 2*x^2 + 4*x^3] *)
      Add;                      (* [x_next] *)
      PopReg slot_state;        (* [] *)

      (* cnt = cnt - 1 *)
      PushReg slot_counter;     (* [cnt] *)
      PushImm 1L;               (* [1, cnt] *)
      Sub;                      (* [cnt - 1] *)
      PopReg slot_counter;      (* [] *)

      JmpRel stall_check_id;
    ] in
    let body_block = {
      id = stall_body_id;
      label = Printf.sprintf "stall_body_%d" stall_body_id;
      ops = body_ops;
    } in

    (* 4. Exit block: verifies slot_state == x_n and adds (slot_state - x_n) to ctx[0] *)
    let exit_ops = [
      PushReg slot_state;
      PushImm x_n;
      Sub;                      (* [slot_state - x_n] -> 0 if valid *)
      PushReg 0;                (* [ctx[0], delta] *)
      Add;                      (* [ctx[0] + delta] *)
      PopReg 0;                 (* ctx[0] updated *)
      JmpRel orig_entry;
    ] in
    let exit_block = {
      id = stall_exit_id;
      label = Printf.sprintf "stall_exit_%d" stall_exit_id;
      ops = exit_ops;
    } in

    let new_blocks = Hashtbl.copy prog.blocks in
    Hashtbl.replace new_blocks stall_init_id init_block;
    Hashtbl.replace new_blocks stall_check_id check_block;
    Hashtbl.replace new_blocks stall_body_id body_block;
    Hashtbl.replace new_blocks stall_exit_id exit_block;

    {
      entry_id = stall_init_id;
      blocks = new_blocks;
      context_slots = new_context_slots;
    }
