(** Phase 5: Virtual CFG Flattening
    ──────────────────────────────────
    Eliminates direct block-ID references from branch instructions by routing
    all inter-block control flow through a virtual dispatcher chain.

    Attack vector defeated:
      Devirtualization tools that reconstruct the CFG from direct block ID
      references (NoVmp CFG recovery, Mergen CFG-unflattener, IDA VTIL CFG
      builder) see only the dispatcher as a hub — the real block graph is hidden
      behind the VPC token → block mapping.

    Design:
      1. Assign each block a random 64-bit token T[bid].
      2. Allocate a Virtual Program Counter (VPC) context slot.
      3. Build a dispatcher chain: one small block per real block that does
           PushReg vpc ; PushImm T[B_i] ; Cmp ; JccRel(B_i, E) ; JmpRel(disp_{i+1})
      4. Transform block terminators:

           JmpRel target
             → PushImm T[target] ; PopReg vpc ; JmpRel dispatcher_0

           JccRel(true_bid, cond) + JmpRel(false_bid)
             → PushImm T[false_bid] ; PopReg vpc          (default: false path)
               PushImm T[true_bid]  ; Cmov(cond, vpc)     (override if cond true)
               JmpRel dispatcher_0

           Exit — unchanged

      All added sequences have stack delta = 0, preserving block balance.
      The entry block entry_id is unchanged; it executes directly and only
      routes through the dispatcher after its first terminator fires.

    Token derivation:
      T[bid] = splitmix64(seed XOR bid)  — second output of splitmix64
*)

open Stack_ir
open Vm_ir
open Flags

(* ── SplitMix64 ───────────────────────────────────────────────────────── *)
let splitmix64 s =
  let s = Int64.add s 0x9E3779B97F4A7C15L in
  let z = s in
  let z = Int64.logxor z (Int64.shift_right_logical z 30) in
  let z = Int64.mul z 0xBF58476D1CE4E5B9L in
  let z = Int64.logxor z (Int64.shift_right_logical z 27) in
  let z = Int64.mul z 0x94D049BB133111EBL in
  let z = Int64.logxor z (Int64.shift_right_logical z 31) in
  (s, z)

let block_token seed id =
  let _, z = splitmix64 (Int64.logxor seed (Int64.of_int (id lxor 0xDEAD_C0DE))) in
  if z = 0L then 0xC0FFEE_0000_0001L else z

(* ── Terminator classification ────────────────────────────────────────── *)
type term_kind =
  | Exit_term
  | Jmp_term  of int                          (* JmpRel target *)
  | Jcc_term  of int * condition * int        (* JccRel(true, cond) ; JmpRel(false) *)
  | Jcc_only  of int * condition              (* lone JccRel — leave untouched *)
  | No_term                                   (* no recognizable terminator *)

(** Split block ops into (body, terminator_pattern). *)
let split_terminators ops =
  match List.rev ops with
  | Exit :: rest ->
    (List.rev rest, Exit_term)
  | (JmpRel false_b) :: (JccRel (true_b, cond)) :: rest ->
    (* Conditional branch: JccRel(true, cond); JmpRel(false) — must precede bare JmpRel *)
    (List.rev rest, Jcc_term (true_b, cond, false_b))
  | (JmpRel b) :: rest ->
    (List.rev rest, Jmp_term b)
  | (JccRel (b, cond)) :: rest ->
    (List.rev rest, Jcc_only (b, cond))
  | _ ->
    (ops, No_term)

(* ── Block transformation ─────────────────────────────────────────────── *)
let transform_block vpc_slot dispatcher_0_id tokens block =
  let (body, term) = split_terminators block.ops in
  (* Helper: write token to VPC — delta 0 *)
  let set_vpc token = [ PushImm token; PopReg vpc_slot ] in
  let go_disp = [ JmpRel dispatcher_0_id ] in
  let new_ops = match term with
    | Exit_term | No_term | Jcc_only _ ->
      (* Leave unchanged: Exit is correct; No_term/Jcc_only are edge cases *)
      block.ops

    | Jmp_term target ->
      (* Unknown target (e.g. block removed by an earlier pass): leave the
        whole block untouched rather than raising Not_found mid-pipeline. *)
      (match Hashtbl.find_opt tokens target with
       | Some token -> body @ set_vpc token @ go_disp
       | None -> block.ops)

    | Jcc_term (true_bid, cond, false_bid) ->
      (match Hashtbl.find_opt tokens true_bid, Hashtbl.find_opt tokens false_bid with
       | Some t_true, Some t_false ->
       (* Sequence (stack delta = 0 total for the new suffix):
           PushImm t_false   (+1)
           PopReg vpc_slot   (-1)  → vpc = T[false] by default
           PushImm t_true    (+1)
           Cmov(cond, vpc)   (-1)  → if cond: vpc = T[true]
           JmpRel dispatcher (0)
         Flags from the Cmp/Test that preceded this JccRel are preserved
         because none of the above ops modify the flag register. *)
      body
      @ set_vpc t_false
      @ [ PushImm t_true; Cmov (cond, vpc_slot) ]
      @ go_disp
       | _ -> block.ops)
  in
  { block with ops = new_ops }

(* ── Dispatcher chain construction ────────────────────────────────────── *)
(** Build a chain of (n_real + 1) dispatcher blocks.
    Block at [base_id + i] checks vpc against T[real_ids[i]],
    jumps to real block if equal, else falls to [base_id + i + 1].
    Block at [base_id + n] is the emergency Exit. *)
let build_dispatcher_chain vpc_slot tokens real_ids base_id =
  let sorted_ids = List.sort compare real_ids in
  let n = List.length sorted_ids in
  let exit_block = make_block (base_id + n) "cff_exit" [ Exit ] in
  let comparison_blocks =
    List.mapi (fun i bid ->
      let disp_id      = base_id + i in
      let next_disp_id = base_id + i + 1 in
      let token = Hashtbl.find tokens bid in
      make_block disp_id
        (Printf.sprintf "cff_disp_%d" i)
        [ PushReg vpc_slot      (* +1: load VPC token *)
        ; PushImm token         (* +1: load expected token *)
        ; Cmp                   (* -2: sets flags, stack empty *)
        ; JccRel (bid, E)      (*  0: jump to real block if EQ *)
        ; JmpRel next_disp_id   (*  0: else continue chain *)
        ]
    ) sorted_ids
  in
  comparison_blocks @ [ exit_block ]

(* ── Public API ───────────────────────────────────────────────────────── *)

type cff_config = {
  seed : int64;
}

let default_cff_config seed = { seed }

(** [apply_program cfg ctx prog] applies virtual CFG flattening.
    Mutates [ctx] to allocate a VPC slot. Returns the new program
    with added dispatcher chain blocks. *)
let apply_program cfg ctx prog =
  let n_real = Hashtbl.length prog.blocks in

  (* 1. Assign tokens to every real block *)
  let tokens : (int, int64) Hashtbl.t = Hashtbl.create n_real in
  Hashtbl.iter (fun id _ ->
    Hashtbl.replace tokens id (block_token cfg.seed id)
  ) prog.blocks;

  (* 2. Allocate VPC context slot (beyond existing context) *)
  let vpc_slot = Context_allocator.alloc_scratch ctx in

  (* 3. Find a safe base ID for dispatcher blocks *)
  let max_real_id =
    Hashtbl.fold (fun id _ acc -> max id acc) prog.blocks 0
  in
  let dispatcher_base = max_real_id + 1 in
  let dispatcher_0_id = dispatcher_base in

  (* 4. Transform every real block's terminators *)
  let new_real_blocks = Hashtbl.create n_real in
  Hashtbl.iter (fun id b ->
    let b' = transform_block vpc_slot dispatcher_0_id tokens b in
    Hashtbl.replace new_real_blocks id b'
  ) prog.blocks;

  (* 5. Build the dispatcher chain *)
  let real_ids = Hashtbl.fold (fun id _ acc -> id :: acc) prog.blocks [] in
  let disp_blocks = build_dispatcher_chain vpc_slot tokens real_ids dispatcher_base in

  (* 6. Assemble the new program *)
  let all_blocks = Hashtbl.create (n_real + List.length disp_blocks) in
  Hashtbl.iter (fun id b -> Hashtbl.replace all_blocks id b) new_real_blocks;
  List.iter (fun b -> Hashtbl.replace all_blocks b.id b) disp_blocks;

  (* 7. Update context_slots to cover the newly allocated VPC slot *)
  let new_ctx_slots = max prog.context_slots (vpc_slot + 1) in

  { prog with
    blocks        = all_blocks;
    context_slots = new_ctx_slots;
  }

(** [cff_stats before after] returns a human-readable summary. *)
let cff_stats prog_before prog_after =
  let n_before = Hashtbl.length prog_before.blocks in
  let n_after  = Hashtbl.length prog_after.blocks  in
  let n_disp   = n_after - n_before in
  Printf.sprintf
    "CFG flattening: %d real blocks → %d total (%d dispatcher nodes, VPC-routed)"
    n_before n_after n_disp

(** [direct_jump_count prog] counts direct JmpRel/JccRel in all blocks
    (used to verify flattening removed direct jumps). *)
let direct_jmp_count prog =
  Hashtbl.fold (fun _ b acc ->
    List.fold_left (fun a op ->
      match op with
      | JmpRel _ | JccRel _ -> a + 1
      | _ -> a
    ) acc b.ops
  ) prog.blocks 0
