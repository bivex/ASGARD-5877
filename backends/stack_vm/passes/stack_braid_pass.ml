(** Phase 4b (Pass 16): Braided CFG Merging & Decoy Elimination
    ────────────────────────────────────────────────────────────
    Fuses pairs of real, isomorphic basic blocks (B_A, B_B) into a
    single unified braided block B_braid without creating unreachable
    decoy blocks. *)

open Stack_ir

type braid_config = {
  enabled : bool;
  rate : int;
  seed : int64;
}

let default_braid_config seed = {
  enabled = true;
  rate = 30;
  seed;
}

(* ── SplitMix64 PRNG ─────────────────────────────────────────────────── *)
let splitmix64 s =
  let open Int64 in
  let s = add s 0x9E3779B97F4A7C15L in
  let z = s in
  let z = logxor z (shift_right_logical z 30) in
  let z = mul z 0xBF58476D1CE4E5B9L in
  let z = logxor z (shift_right_logical z 27) in
  let z = mul z 0x94D049BB133111EBL in
  let z = logxor z (shift_right_logical z 31) in
  (s, z)

type rng_state = { mutable state : int64 }

let make_rng seed = { state = seed }

let next_int rng n =
  if n <= 1 then 0
  else
    let s, z = splitmix64 rng.state in
    rng.state <- s;
    Int64.to_int (Int64.logand z 0x7FFFFFFFL) mod n

let next_int64 rng =
  let s, z = splitmix64 rng.state in
  rng.state <- s;
  z

(** Newton-Raphson 64-bit modular inverse of odd integer [a] modulo 2^64. *)
let mod_inv_64 a =
  let open Int64 in
  let a = logor a 1L in (* Ensure odd *)
  let x = logxor (mul 3L a) 2L in
  let x = mul x (sub 2L (mul a x)) in
  let x = mul x (sub 2L (mul a x)) in
  let x = mul x (sub 2L (mul a x)) in
  mul x (sub 2L (mul a x))

let is_terminator = function
  | JmpRel _ | JccRel _ | Exit -> true
  | _ -> false

let emit_route_discriminant ~route_slot ~tau_A ~inv =
  [
    PushReg route_slot;                (* [r_route] *)
    PushImm tau_A;                     (* [r_route, tau_A] *)
    Sub;                               (* [r_route - tau_A] *)
    PushImm inv;                       (* [diff, inv] *)
    Mul;                               (* [diff * inv] *)
    PushImm 1L;                        (* [X, 1] *)
    Nand;                              (* [Nand(X, 1)] *)
    Dup;                               (* [N, N] *)
    Nand;                              (* [X & 1] = [d] *)
  ]

let emit_discriminant_setup ~route_slot ~d_slot ~d_bar_slot ~tau_A ~inv =
  emit_route_discriminant ~route_slot ~tau_A ~inv
  @ [
      Dup;                             (* [d, d] *)
      PopReg d_slot;                   (* [d] *)
      PushImm 1L;                      (* [d, 1] *)
      Swap;                            (* [1, d] *)
      Sub;                             (* [1 - d] *)
      PopReg d_bar_slot;               (* [] *)
    ]

let emit_multiplexed_pop ~d_slot ~d_bar_slot ~target_slot ~is_path_b =
  let (sel_new, sel_old) =
    if is_path_b then (d_slot, d_bar_slot)
    else (d_bar_slot, d_slot)
  in
  [
    (* stack: [..., v_new] *)
    PushReg sel_new;                   (* [..., v_new, sel_new] *)
    Mul;                               (* [..., sel_new * v_new] *)
    PushReg target_slot;               (* [..., X, r_old] *)
    PushReg sel_old;                   (* [..., X, r_old, sel_old] *)
    Mul;                               (* [..., X, sel_old * r_old] *)
    Add;                               (* [..., (sel_new * v_new) + (sel_old * r_old)] *)
    PopReg target_slot;                (* [...] *)
  ]

let are_isomorphic (b_a : block) (b_b : block) =
  let non_terms_a = List.filter (fun op -> not (is_terminator op)) b_a.ops in
  let non_terms_b = List.filter (fun op -> not (is_terminator op)) b_b.ops in
  List.length non_terms_a = List.length non_terms_b
  && List.for_all2 (fun op_a op_b ->
       match op_a, op_b with
       | PushImm _, PushImm _ -> true
       | PushReg _, PushReg _ -> true
       | PopReg _, PopReg _ -> true
       | SetRegImm _, SetRegImm _ -> true
       | Add, Add | Sub, Sub | Mul, Mul | Nor, Nor | Nand, Nand -> true
       | Shl, Shl | Shr, Shr | Sar, Sar -> true
       | Swap, Swap | Dup, Dup | Rot, Rot -> true
       | _ -> false
     ) non_terms_a non_terms_b

let braid_isomorphic_ops ~d_slot ~d_bar_slot (ops_a : stack_op list) (ops_b : stack_op list) : stack_op list =
  List.concat (List.map2 (fun op_a op_b ->
    match op_a, op_b with
    | PushImm ca, PushImm cb when ca = cb ->
        [ PushImm ca ]
    | PushImm ca, PushImm cb ->
        [
          PushImm ca;
          PushReg d_bar_slot;
          Mul;
          PushImm cb;
          PushReg d_slot;
          Mul;
          Add;
        ]
    | PushReg sa, PushReg sb when sa = sb ->
        [ PushReg sa ]
    | PushReg sa, PushReg sb ->
        [
          PushReg sa;
          PushReg d_bar_slot;
          Mul;
          PushReg sb;
          PushReg d_slot;
          Mul;
          Add;
        ]
    | PopReg da, PopReg db when da = db ->
        [ PopReg da ]
    | PopReg da, PopReg db ->
        [
          Dup;
          PushReg d_bar_slot;
          Mul;
          PushReg da;
          PushReg d_slot;
          Mul;
          Add;
          PopReg da;
          PushReg d_slot;
          Mul;
          PushReg db;
          PushReg d_bar_slot;
          Mul;
          Add;
          PopReg db;
        ]
    | SetRegImm (sa, ca), SetRegImm (sb, cb) when sa = sb ->
        [
          PushImm ca;
          PushReg d_bar_slot;
          Mul;
          PushImm cb;
          PushReg d_slot;
          Mul;
          Add;
          PopReg sa;
        ]
    | SetRegImm (sa, ca), SetRegImm (sb, cb) ->
        [
          PushImm ca;
          PushReg d_bar_slot;
          Mul;
          PushImm cb;
          PushReg d_slot;
          Mul;
          Add;
          Dup;
          PushReg d_bar_slot;
          Mul;
          PushReg sa;
          PushReg d_slot;
          Mul;
          Add;
          PopReg sa;
          PushReg d_slot;
          Mul;
          PushReg sb;
          PushReg d_bar_slot;
          Mul;
          Add;
          PopReg sb;
        ]
    | Add, Add -> [ Add ]
    | Sub, Sub -> [ Sub ]
    | Mul, Mul -> [ Mul ]
    | Nor, Nor -> [ Nor ]
    | Nand, Nand -> [ Nand ]
    | Shl, Shl -> [ Shl ]
    | Shr, Shr -> [ Shr ]
    | Sar, Sar -> [ Sar ]
    | Swap, Swap -> [ Swap ]
    | Dup, Dup -> [ Dup ]
    | Rot, Rot -> [ Rot ]
    | op, _ -> [ op ]
  ) ops_a ops_b)

let extract_block_succ (b : block) =
  let rec find = function
    | [] -> None
    | JmpRel target :: _ -> Some target
    | Exit :: _ -> None
    | _ :: rest -> find rest
  in
  find (List.rev b.ops)

let braid_blocks ~route_slot ~d_slot ~d_bar_slot ~flag_slot ~tau_A ~inv ~(b_a : block) ~(b_b : block) : block =
  let flag_save = [ PushFlags; PopReg flag_slot ] in
  let flag_restore = [ PushReg flag_slot; PopFlags ] in
  let setup = emit_discriminant_setup ~route_slot ~d_slot ~d_bar_slot ~tau_A ~inv in
  let non_terms_a = List.filter (fun op -> not (is_terminator op)) b_a.ops in
  let non_terms_b = List.filter (fun op -> not (is_terminator op)) b_b.ops in
  let fused_body = braid_isomorphic_ops ~d_slot ~d_bar_slot non_terms_a non_terms_b in

  let succ_a = extract_block_succ b_a in
  let succ_b = extract_block_succ b_b in

  let epilogue =
    match succ_a, succ_b with
    | Some sa, Some sb when sa = sb ->
        [ JmpRel sa ]
    | Some sa, Some sb ->
        [
          PushReg d_slot;
          PushImm 0L;
          Cmp;
          JccRel (sa, Vm_ir.Flags.E);
          JmpRel sb;
        ]
    | Some sa, None ->
        [
          PushReg d_slot;
          PushImm 0L;
          Cmp;
          JccRel (sa, Vm_ir.Flags.E);
          Exit;
        ]
    | None, Some sb ->
        [
          PushReg d_slot;
          PushImm 0L;
          Cmp;
          JccRel (sb, Vm_ir.Flags.NE);
          Exit;
        ]
    | None, None ->
        [ Exit ]
  in
  {
    id = b_a.id;
    label = Printf.sprintf "braid_%d_%d" b_a.id b_b.id;
    ops = flag_save @ setup @ flag_restore @ fused_body @ epilogue;
  }
let is_eligible ~jcc_targets (b : block) =
  let has_writemem = List.exists (function WriteMem _ -> true | _ -> false) b.ops in
  let not_targeted_by_jcc = not (Hashtbl.mem jcc_targets b.id) in
  let ends_uncond_or_exit =
    match List.rev b.ops with
    | JmpRel _ :: _ | Exit :: _ -> true
    | _ -> false
  in
  (not has_writemem) && not_targeted_by_jcc && ends_uncond_or_exit

let retarget_predecessors ~blocks ~id_a ~id_b ~id_braid ~tau_a ~tau_b ~route_slot =
  Hashtbl.iter (fun id b ->
    if id <> id_braid && id <> id_b then begin
      let rec rewrite acc = function
        | [] -> List.rev acc
        | JccRel (tb, c) :: JmpRel target :: rest when target = id_a ->
            rewrite (JmpRel id_braid :: JccRel (tb, c) :: PopReg route_slot :: PushImm tau_a :: acc) rest
        | JccRel (tb, c) :: JmpRel target :: rest when target = id_b ->
            rewrite (JmpRel id_braid :: JccRel (tb, c) :: PopReg route_slot :: PushImm tau_b :: acc) rest
        | JmpRel target :: rest when target = id_a ->
            rewrite (JmpRel id_braid :: PopReg route_slot :: PushImm tau_a :: acc) rest
        | JmpRel target :: rest when target = id_b ->
            rewrite (JmpRel id_braid :: PopReg route_slot :: PushImm tau_b :: acc) rest
        | op :: rest ->
            rewrite (op :: acc) rest
      in
      let ops' = rewrite [] b.ops in
      if ops' <> b.ops then
        Hashtbl.replace blocks id { b with ops = ops' }
    end
  ) blocks

let apply_program (cfg : braid_config) (ctx : Context_allocator.t) (prog : program) : program =
  if not cfg.enabled || cfg.rate <= 0 then prog
  else
    let rng = make_rng cfg.seed in
    let blocks = Hashtbl.copy prog.blocks in
    let jcc_targets = Hashtbl.create 64 in
    Hashtbl.iter (fun _ b ->
      List.iter (function
        | JccRel (target, _) -> Hashtbl.replace jcc_targets target ()
        | _ -> ()
      ) b.ops
    ) blocks;
    (* Group candidate blocks by (shape, successor) so fused pairs converge cleanly *)
    let shape_map = Hashtbl.create 16 in
    Hashtbl.iter (fun id b ->
      if id <> prog.entry_id && is_eligible ~jcc_targets b then begin
        let non_terms = List.filter (fun op -> not (is_terminator op)) b.ops in
        let shape = List.map (function
          | PushImm _ -> 1
          | PushReg _ -> 2
          | PopReg _ -> 3
          | SetRegImm _ -> 4
          | Add -> 5 | Sub -> 6 | Mul -> 7 | Nor -> 8 | Nand -> 9
          | Shl -> 10 | Shr -> 11 | Sar -> 12
          | Swap -> 13 | Dup -> 14 | Rot -> 15
          | _ -> 0
        ) non_terms in
        if not (List.mem 0 shape) then begin
          let key = (shape, extract_block_succ b) in
          let l = match Hashtbl.find_opt shape_map key with Some l -> l | None -> [] in
          Hashtbl.replace shape_map key (b :: l)
        end
      end
    ) blocks;

    let pairs_fused = ref 0 in

    Hashtbl.iter (fun _ group ->
      let rec pair_up = function
        | b_a :: b_b :: rest ->
            if next_int rng 100 < cfg.rate then begin
              let route_slot = Context_allocator.alloc_scratch ctx in
              let d_slot = Context_allocator.alloc_scratch ctx in
              let d_bar_slot = Context_allocator.alloc_scratch ctx in
              let flag_slot = Context_allocator.alloc_scratch ctx in

              let tau_a = next_int64 rng in
              let delta = Int64.logor (next_int64 rng) 1L in (* odd *)
              let tau_b = Int64.add tau_a delta in
              let inv = mod_inv_64 delta in

              let b_braid = braid_blocks ~route_slot ~d_slot ~d_bar_slot ~flag_slot ~tau_A:tau_a ~inv ~b_a ~b_b in
              Hashtbl.replace blocks b_a.id b_braid;
              Hashtbl.remove blocks b_b.id;

              retarget_predecessors ~blocks ~id_a:b_a.id ~id_b:b_b.id ~id_braid:b_a.id ~tau_a ~tau_b ~route_slot;
              incr pairs_fused
            end;
            pair_up rest
        | _ -> ()
      in
      pair_up group
    ) shape_map;

    let context_slots = max prog.context_slots (Context_allocator.total_slots ctx) in
    { prog with blocks; context_slots }

let braid_stats prog_before prog_after =
  let b_before = Hashtbl.length prog_before.blocks in
  let b_after = Hashtbl.length prog_after.blocks in
  Printf.sprintf "Braided CFG Merging: %d -> %d blocks (Isomorphic Block Braiding with 100%% live routes)"
    b_before b_after
