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
open Random_visa_constants.Magic_numbers

(* ── SplitMix64 ───────────────────────────────────────────────────────── *)
let splitmix64 s =
  let s = Int64.add s golden_ratio_64 in
  let z = s in
  let z = Int64.logxor z (Int64.shift_right_logical z 30) in
  let z = Int64.mul z splitmix64_gamma in
  let z = Int64.logxor z (Int64.shift_right_logical z 27) in
  let z = Int64.mul z splitmix64_mix in
  let z = Int64.logxor z (Int64.shift_right_logical z 31) in
  (s, z)

let block_token seed id =
  let _, z = splitmix64 (Int64.logxor seed (Int64.of_int (id lxor Int64.to_int salt_deadcode))) in
  if z = 0L then sentinel_c0ffee_1 else z
(* The dispatcher state the state-feedback pass needs: the VPC context
   slot and the token every real block is addressed by.  On entry to a
   real block the VPC provably holds that block's token: the predecessor
   writes it before jumping to the dispatcher, and the dispatcher only
   compares it.  The value is therefore statically known, which is what
   the encryptor needs to reproduce the rolling key schedule. *)
type dispatcher_info = {
  vpc_slot : int;
  block_tokens : (int, int64) Hashtbl.t;  (** real block id -> VPC token *)
}

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

let hash_shard_id ~(salt : int64) (token : int64) (n_shards : int) : int =
  let z = Int64.add token salt in
  let z = Int64.logxor z (Int64.shift_right_logical z 30) in
  let z = Int64.mul z splitmix64_gamma in
  let z = Int64.logxor z (Int64.shift_right_logical z 27) in
  let z = Int64.mul z splitmix64_mix in
  let z = Int64.logxor z (Int64.shift_right_logical z 31) in
  abs (Int64.to_int z) mod n_shards

(* ── Block transformation ─────────────────────────────────────────────── *)
let transform_block ?(rng = Random.State.make [| 0x5877 |]) vpc_slot entry_of decoy_entry_of tokens block =
  let (body, term) = split_terminators block.ops in
  let set_vpc token = [ PushImm token; PopReg vpc_slot ] in
  let go_disp target =
    let real_entry = entry_of target in
    let decoy_entry = decoy_entry_of target in
    (* Non-Linear Register-Anchored Opaque Zero Branch:
       (vpc * r2 + r3) - (vpc * r2 + r3) == 0 in Z/2^64Z.
       Anchoring to runtime register vpc_slot prevents constant folding,
       while 64-bit non-linear multiplication (Mul) creates full carry chains.
       Guaranteed 100% runtime evaluation to 0, taking JccRel(real_entry, E)
       with decoy JmpRel(decoy_entry) indistinguishability. *)
    let r2 = Int64.logor (Random.State.int64 rng Int64.max_int) 1L in
    let r3 = Random.State.int64 rng Int64.max_int in
    [
      PushReg vpc_slot; PushImm r2; Mul; PushImm r3; Add;
      PushReg vpc_slot; PushImm r2; Mul; PushImm r3; Add;
      Sub;
      PushImm 0L;
      Cmp;
      JccRel (real_entry, E);
      JmpRel decoy_entry;
    ] in
  let new_ops = match term with
    | Exit_term | No_term | Jcc_only _ ->
      block.ops

    | Jmp_term target ->
      (match Hashtbl.find_opt tokens target with
       | Some token -> body @ set_vpc token @ go_disp target
       | None -> block.ops)

    | Jcc_term (true_bid, cond, false_bid) ->
      (match Hashtbl.find_opt tokens true_bid, Hashtbl.find_opt tokens false_bid with
       | Some t_true, Some t_false ->
      body
      @ set_vpc t_false
      @ [ PushImm t_true; Cmov (cond, vpc_slot) ]
      @ go_disp false_bid
       | _ -> block.ops)
  in
  { block with ops = new_ops }

(* ── Dispatcher chain construction ────────────────────────────────────── *)
(** Builds a circular sharded Ramanujan expander dispatcher.
    Real blocks are partitioned across [n_shards] buckets by SplitMix64 token hash.
    Each shard checks its local bucket tokens; on mismatch at the shard tail,
    execution falls through circularly to [(s + 1) mod n_shards].
    This ensures 100% reachability across any branch without ever deadlocking or
    prematurely exiting, eliminating the single dispatcher entry bottleneck. *)
let build_dispatcher_chain ~seed vpc_slot tokens real_ids base_id =
  let n_real = List.length real_ids in
  let n_shards = min 16 (max 2 (n_real / 4)) in
  let buckets = Array.make n_shards [] in
  List.iter (fun bid ->
    let tok = Hashtbl.find tokens bid in
    let s = hash_shard_id ~salt:seed tok n_shards in
    buckets.(s) <- bid :: buckets.(s)
  ) real_ids;
  for s = 0 to n_shards - 1 do
    buckets.(s) <- List.sort compare buckets.(s)
  done;

  let entry_base = Array.make n_shards 0 in
  let next = ref base_id in
  for s = 0 to n_shards - 1 do
    entry_base.(s) <- !next;
    next := !next + List.length buckets.(s)
  done;
  let exit_id = !next in

  let entry_of_s s =
    let rec find i count =
      if count >= n_shards then exit_id
      else if buckets.(i) <> [] then entry_base.(i)
      else find ((i + 1) mod n_shards) (count + 1)
    in
    if buckets.(s) <> [] then entry_base.(s)
    else find ((s + 1) mod n_shards) 1
  in

  let entry_of target =
    match Hashtbl.find_opt tokens target with
    | Some tok ->
      let s = hash_shard_id ~salt:seed tok n_shards in
      entry_of_s s
    | None -> exit_id
  in

  (* Per-node metamorphic comparison shapes: a dynamic tracer hooking
     ctx[vpc_slot] must not see one uniform "load vpc, compare, JccRel"
     template across all dispatcher nodes.  Six shapes (3 operand layouts
     x 2 branch polarities), all provably equivalent for the equality
     test consumed by JccRel: ZF(vpc-token) == ZF(token-vpc) == 1 iff
     vpc = token; the NE polarity swaps the taken/fallthrough edges
     while preserving the runtime CFG exactly. *)
  let rng = Random.State.make [| Int64.to_int (Int64.logand seed 0x7FFFFFFFL) |] in
  let compute_hensel_coefficients tau rng =
    let a1 =
      let r = Int64.logxor (Int64.of_int (Random.State.bits rng))
                (Int64.shift_left (Int64.of_int (Random.State.bits rng)) 31) in
      Int64.logor r 1L
    in
    let c2 =
      Int64.logxor (Int64.of_int (Random.State.bits rng))
        (Int64.shift_left (Int64.of_int (Random.State.bits rng)) 31)
    in
    let c3 =
      Int64.logxor (Int64.of_int (Random.State.bits rng))
        (Int64.shift_left (Int64.of_int (Random.State.bits rng)) 31)
    in
    let open Int64 in
    let tau2 = mul tau tau in
    let tau3 = mul tau2 tau in
    let g0 = add (neg (mul a1 tau)) (sub (mul 2L (mul c2 tau2)) (mul 4L (mul c3 tau3))) in
    let g1 = add (sub a1 (mul 4L (mul c2 tau))) (mul 12L (mul c3 tau2)) in
    let g2 = sub (mul 2L c2) (mul 12L (mul c3 tau)) in
    let g3 = mul 4L c3 in
    (g0, g1, g2, g3)
  in
  let comparison_blocks = ref [] in
  for s = 0 to n_shards - 1 do
    let ids = buckets.(s) in
    let n_in_s = List.length ids in
    List.iteri (fun i bid ->
      let disp_id = entry_base.(s) + i in
      let fall_to =
        if i + 1 < n_in_s then entry_base.(s) + i + 1
        else
          (* Circular expander ring transition to next non-empty shard *)
          entry_of_s ((s + 1) mod n_shards)
      in
      let token = Hashtbl.find tokens bid in
      let cmp_ops = match Random.State.int rng 4 with
        | 0 ->
            (* Pass 13: Hensel Lifting Implicit Cubic Predicate *)
            let (g0, g1, g2, g3) = compute_hensel_coefficients token rng in
            [
              PushImm g3;
              PushReg vpc_slot;
              Mul;
              PushImm g2;
              Add;
              PushReg vpc_slot;
              Mul;
              PushImm g1;
              Add;
              PushReg vpc_slot;
              Mul;
              PushImm g0;
              Add;
              PushImm 0L;
              Cmp;
            ]
        | 1 -> [ PushReg vpc_slot; PushImm token; Cmp ]
        | 2 -> (* operand-symmetric: ZF(token-vpc) == ZF(vpc-token) *)
            [ PushImm token; PushReg vpc_slot; Cmp ]
        | _ -> (* difference-vs-anchored-zero: no literal 0L in stream *)
            [ PushReg vpc_slot; PushImm token; Sub;
              PushReg vpc_slot; PushReg vpc_slot; Sub;
              Cmp ]
      in
      let term = match Random.State.int rng 2 with
        | 0 -> [ JccRel (bid, E); JmpRel fall_to ]
        | _ -> (* inverted polarity: equal falls through to JmpRel bid *)
            [ JccRel (fall_to, NE); JmpRel bid ]
      in
      let blk =
        make_block disp_id
          (Printf.sprintf "cff_disp_%d" disp_id)
          (cmp_ops @ term)
      in
      comparison_blocks := blk :: !comparison_blocks
    ) ids
  done;

  let decoy_entry_of target =
    match Hashtbl.find_opt tokens target with
    | Some tok ->
      let s = hash_shard_id ~salt:seed tok n_shards in
      entry_of_s ((s + max 1 (n_shards / 2)) mod n_shards)
    | None -> exit_id
  in
  let exit_block = make_block exit_id "cff_exit" [ Exit ] in
  (List.rev !comparison_blocks @ [ exit_block ], entry_of, decoy_entry_of)

(* ── Public API ───────────────────────────────────────────────────────── *)

type cff_config = {
  seed : int64;
  (* Couple the rolling key to the VPC write on every CFF edge, so the
     key depends on the path the program took.  See [set_vpc]. *)
  couple_key : bool;
}

let default_cff_config seed = { seed; couple_key = true }

(** [apply_program_with_info cfg ctx prog] applies virtual CFG flattening.
    Mutates [ctx] to allocate a VPC slot. Returns the new program with
    added dispatcher chain blocks, together with the dispatcher state
    (the VPC slot and the token of every real block). *)
let apply_program_with_info cfg ctx prog =
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

  (* 4. Build the circular sharded dispatcher chain with per-function salt derivation
     so shard mapping cannot be precomputed statically across functions in the binary *)
  let real_ids = Hashtbl.fold (fun id _ acc -> id :: acc) prog.blocks [] in
  let func_salt =
    Int64.logxor cfg.seed
      (Int64.logxor salt_stack_vm_state
         (Int64.mul (Int64.of_int prog.entry_id) block_id_multiplier))
  in
  let disp_blocks, entry_of, decoy_entry_of =
    build_dispatcher_chain ~seed:func_salt vpc_slot tokens real_ids dispatcher_base
  in

  (* 5. Transform every real block's terminators with sharded entry routing *)
  let new_real_blocks = Hashtbl.create n_real in
  let rng = Random.State.make [| Int64.to_int func_salt |] in
  Hashtbl.iter (fun id b ->
    let b' = transform_block ~rng vpc_slot entry_of decoy_entry_of tokens b in
    (* 5b. Couple the rolling key to the VPC at the entry of every block
       the dispatcher can reach.  There the VPC provably holds that
       block's token, so the coupled value is statically known and the
       encryptor can reproduce the key schedule.  The coupling therefore
       makes the key depend on the path the program took: a block
       harvested in isolation carries no key of its own.

       The coupling is the FIRST operation of the block, so a later
       splitting pass cannot separate it from the state it relies on. *)
    let b' =
      if cfg.couple_key && id <> prog.entry_id then
        match Hashtbl.find_opt tokens id with
        | Some token -> { b' with ops = KeyFeedback (vpc_slot, token) :: b'.ops }
        | None -> b'
      else b'
    in
    Hashtbl.replace new_real_blocks id b'
  ) prog.blocks;

  (* 6. Assemble the new program *)
  let all_blocks = Hashtbl.create (n_real + List.length disp_blocks) in
  Hashtbl.iter (fun id b -> Hashtbl.replace all_blocks id b) new_real_blocks;
  List.iter (fun b -> Hashtbl.replace all_blocks b.id b) disp_blocks;

  (* 7. Update context_slots to cover the newly allocated VPC slot *)
  let new_ctx_slots = max prog.context_slots (vpc_slot + 1) in

  ( { prog with
      blocks        = all_blocks;
      context_slots = new_ctx_slots;
    },
    { vpc_slot; block_tokens = tokens } )

(** [apply_program cfg ctx prog] is [apply_program_with_info] without the
    dispatcher state. *)
let apply_program cfg ctx prog = fst (apply_program_with_info cfg ctx prog)

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
