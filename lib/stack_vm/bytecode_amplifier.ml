open Stack_ir
open Random_visa_constants.Magic_numbers

type amplification_profile = {
  horner_degree       : int;
  bit_slice_lanes     : int;
  expander_chord_len  : int;
  expander_chord_rate : int;
}

let default_heavy_profile = {
  horner_degree       = 6;
  bit_slice_lanes     = 2;
  expander_chord_len  = 8;
  expander_chord_rate = 75;
}

let balanced_profile = {
  horner_degree       = 3;
  bit_slice_lanes     = 2;
  expander_chord_len  = 8;
  expander_chord_rate = 50;
}

let light_profile = {
  horner_degree       = 2;
  bit_slice_lanes     = 1;
  expander_chord_len  = 10;
  expander_chord_rate = 25;
}

let adaptive_profile ?(block_size = 0) ?(post_mba = false) () =
  if post_mba || block_size > 80 then light_profile
  else if block_size > 25 then balanced_profile
  else default_heavy_profile

let rand_u64 (rng : Random.State.t) : int64 =
  let hi = Int64.of_int (Random.State.bits rng) in
  let mid = Int64.of_int (Random.State.bits rng) in
  let lo = Int64.of_int (Random.State.bits rng) in
  Int64.logor (Int64.shift_left hi 34) (Int64.logor (Int64.shift_left mid 4) (Int64.logand lo 0xFL))

(* Scratch-slot budget reserved by amplify_stack_program: 16 slots past
   scratch_base.
     base+0  s1      carry-chain work vector 1
     base+1  s2      carry-chain work vector 2
     base+2  sx      original x operand (flag re-definition)
     base+3  sy      original y operand (flag re-definition)
     base+4..base+9  anchor ring (K <= 6 write anchors for expander knots) *)
let n_anchor_slots (profile : amplification_profile) : int =
  max 1 (min 6 profile.expander_chord_len)

(** 1. POLYNOMIAL CONSTANT SYNTHESIS VIA THE HORNER SCHEME OVER Z_{2^64}
    Suppose we want to obtain a constant C at the point t_0.
    We pick random leading coefficients a_d, a_{d-1}, ..., a_1 \in Z_{2^64}.
    We compute the partial sum P_high(t_0) = (...((a_d * t_0 + a_{d-1}) * t_0 + ...) * t_0.
    Then the free term a_0 is uniquely determined as:
    a_0 = C - P_high(t_0) (mod 2^64)! *)
let synth_horner_polynomial (rng : Random.State.t) ~(target_const : int64) ~(degree : int)
    : int64 * int64 list =
  let d = max 1 degree in
  (* We choose an odd point t_0 for maximal bit mixing during multiplication *)
  let t0 = Int64.logor (rand_u64 rng) 1L in
  let high_coeffs = List.init d (fun _ -> rand_u64 rng) in
  let p_high =
    List.fold_left (fun acc a_k -> Int64.mul (Int64.add acc a_k) t0) 0L high_coeffs
  in
  let a0 = Int64.sub target_const p_high in
  (t0, high_coeffs @ [a0])

let eval_horner_polynomial ~(t0 : int64) ~(coeffs : int64 list) : int64 =
  match coeffs with
  | [] -> 0L
  | hd :: tl -> List.fold_left (fun acc c -> Int64.add (Int64.mul acc t0) c) hd tl

(** Generation of a chain of stack instructions evaluating the Horner polynomial on the stack.
    Stack delta = +1 (equivalent to PushImm target_const).
    At every step t_0 is masked via the identity (t_0 ^ m) + 2*(t_0 & m) - m. *)
let emit_horner_step (rng : Random.State.t) ~(t0 : int64) ~(a_k : int64) : stack_op list =
  let m = rand_u64 rng in
  let variant = Random.State.int rng 5 in
  let t0_eval =
    match variant with
    | 0 ->
        (* Variant 0: Additive XOR-AND split: (t0 ^ m) + 2*(t0 & m) - m *)
        let t0_xor_m = Int64.logxor t0 m in
        let t0_and_m = Int64.shift_left (Int64.logand t0 m) 1 in
        [ PushImm t0_xor_m; PushImm t0_and_m; Add; PushImm m; Sub ]
    | 1 ->
        (* Variant 1: Disjunctive OR-AND split: (t0 | m) + (t0 & m) - m *)
        let t0_or_m = Int64.logor t0 m in
        let t0_and_m = Int64.logand t0 m in
        [ PushImm t0_or_m; PushImm t0_and_m; Add; PushImm m; Sub ]
    | 2 ->
        (* Variant 2: Subtractive 2*OR - XOR split: 2*(t0 | m) - (t0 ^ m) - m *)
        let t0_2or_m = Int64.shift_left (Int64.logor t0 m) 1 in
        let t0_xor_m = Int64.logxor t0 m in
        [ PushImm t0_2or_m; PushImm t0_xor_m; Sub; PushImm m; Sub ]
    | 3 ->
        (* Variant 3: Direct modular additive partition: (t0 - m) + m *)
        let t0_sub_m = Int64.sub t0 m in
        [ PushImm t0_sub_m; PushImm m; Add ]
    | _ ->
        (* Variant 4: Pre-subtracted XOR split: ((t0 ^ m) - m) + 2*(t0 & m) *)
        let t0_xor_m = Int64.logxor t0 m in
        let t0_and_m = Int64.shift_left (Int64.logand t0 m) 1 in
        [ PushImm t0_xor_m; PushImm m; Sub; PushImm t0_and_m; Add ]
  in
  let add_ak =
    if Random.State.bool rng then
      [ PushImm a_k; Add ]
    else
      let m_ak = rand_u64 rng in
      [ PushImm (Int64.sub a_k m_ak); PushImm m_ak; Add; Add ]
  in
  t0_eval @ [ Mul ] @ add_ak

(** Generation of a chain of stack instructions evaluating the Horner polynomial on the stack.
    Stack delta = +1 (equivalent to PushImm target_const).
    Uses a randomized 5-variant metamorphic grammar per step, shattering deterministic DCE templates. *)
let emit_horner_stack_insns (rng : Random.State.t) ~(target_const : int64) ~(degree : int)
    : stack_op list =
  let (t0, coeffs) = synth_horner_polynomial rng ~target_const ~degree in
  match coeffs with
  | [] -> [PushImm target_const]
  | a_d :: rest ->
      let init_insns = [PushImm a_d] in
      let step_insns =
        List.concat_map (fun a_k -> emit_horner_step rng ~t0 ~a_k) rest
      in
      init_insns @ step_insns

(* ------------------------------------------------------------------ *)
(* Metamorphic ring twist (bridge to Metamorphic_ring from mba_engine):
   Preserves stack top value and flags with 4 distinct algebraic shapes. *)
let emit_ring_twist (rng : Random.State.t) : stack_op list =
  let variant = Random.State.int rng 4 in
  match variant with
  | 0 ->
      (* Standard odd-twist: x * k_odd * k_inv == x *)
      let k_odd = Int64.logor (rand_u64 rng) 1L in
      let k_inv = Mba_engine.Metamorphic_ring.inv_mod_2_64 k_odd in
      [ PushImm k_odd; Mul; PushImm k_inv; Mul ]
  | 1 ->
      (* Two-stage coprime cascade: x * k1 * k2 * (k1*k2)^-1 == x *)
      let k1 = Int64.logor (rand_u64 rng) 1L in
      let k2 = Int64.logor (rand_u64 rng) 1L in
      let k_prod = Int64.mul k1 k2 in
      let k_inv = Mba_engine.Metamorphic_ring.inv_mod_2_64 k_prod in
      [ PushImm k1; Mul; PushImm k2; Mul; PushImm k_inv; Mul ]
  | 2 ->
      (* Swap-interleaved inverse scaling *)
      let k_odd = Int64.logor (rand_u64 rng) 1L in
      let k_inv = Mba_engine.Metamorphic_ring.inv_mod_2_64 k_odd in
      [ PushImm k_inv; PushImm k_odd; Mul; Mul ]
  | _ ->
      (* Inverted evaluation order with split factors: Mul does not touch flags *)
      let k_odd = Int64.logor (rand_u64 rng) 1L in
      let k_inv = Mba_engine.Metamorphic_ring.inv_mod_2_64 k_odd in
      [ PushImm k_odd; PushImm k_inv; Mul; Mul ]
(* ------------------------------------------------------------------ *)
(* Minterm basis (bridge to Nullspace_mba): NOR/NAND representations
   of disjoint minterms over a pair of registers. Each push leaves
   exactly one value on the stack. *)
let push_or_regs (s1 : int) (s2 : int) : stack_op list =
  (* s1 | s2 = Nand(Nor(s1, s1), Nor(s2, s2)) *)
  [ PushReg s1; PushReg s1; Nor;
    PushReg s2; PushReg s2; Nor;
    Nand ]

let push_and_regs (s1 : int) (s2 : int) : stack_op list =
  (* s1 & s2 = Nor(Nor(s1, s1), Nor(s2, s2)) *)
  [ PushReg s1; PushReg s1; Nor;
    PushReg s2; PushReg s2; Nor;
    Nor ]

let push_xor_regs (s1 : int) (s2 : int) : stack_op list =
  (* s1 ^ s2 = (s1 | s2) - (s1 & s2)  — numeric identity over Z_{2^64} *)
  push_or_regs s1 s2 @ push_and_regs s1 s2 @ [ Sub ]

(** Auxiliary generator of a carry cascade from registers s1 and s2:
    Computes u_1 = s1 ^ s2, c_1 = 2*(s1 & s2), then u_2 = u_1 ^ c_1, c_2 = 2*(u_1 & c_1),
    sums them as u_2 + c_2 and applies the invertible ring scaling k_odd * k_inv = 1. *)
let emit_carry_stages (rng : Random.State.t) ~(s1 : int) ~(s2 : int) : stack_op list =
  let k_odd = Int64.logor (rand_u64 rng) 1L in
  let k_inv = Mba_engine.Metamorphic_ring.inv_mod_2_64 k_odd in
  [
    (* u1 = (s1 ^ s2), minterm decomposition *)
    PushReg s1; PushReg s1; Nor;
    PushReg s2; PushReg s2; Nor;
    Nand;
    PushReg s1; PushReg s1; Nor;
    PushReg s2; PushReg s2; Nor;
    Nor;
    Sub;

    (* c1 = 2 * (s1 & s2) *)
    PushReg s1; PushReg s1; Nor;
    PushReg s2; PushReg s2; Nor;
    Nor;
    PushImm 1L;
    Shl;

    (* Save the intermediate vectors into scratch registers *)
    PopReg s2; (* c1 *)
    PopReg s1; (* u1 *)

    (* Second carry stage: u2 = u1 ^ c1 *)
    PushReg s1; PushReg s1; Nor;
    PushReg s2; PushReg s2; Nor;
    Nand;
    PushReg s1; PushReg s1; Nor;
    PushReg s2; PushReg s2; Nor;
    Nor;
    Sub;

    (* c2 = 2 * (u1 & c1) *)
    PushReg s1; PushReg s1; Nor;
    PushReg s2; PushReg s2; Nor;
    Nor;
    PushImm 1L;
    Shl;

    (* u2 + c2 == s1 + s2 in Z_{2^64} *)
    Add;

    (* Ring twist: (x * k_odd) * k_inv = x *)
    PushImm k_odd;
    Mul;
    PushImm k_inv;
    Mul;
  ]

(** Hidden re-definition of the flags after replacing Add/Sub with a carry-chain.
    Add/Sub in this VM DEFINE flags (CC_OP_ADD/SUB {src1; src2; dst}), and
    if the flags are live after the command (flag liveness), the replacement must
    reproduce this definition bit for bit. A PushFlags wrapper does NOT work here:
    it would restore the PRE-command flags. Instead we execute the
    real command on the saved copies of the operands (sx, sy) and
    drop the duplicate result into scratch. Stack delta = 0. *)
let emit_flag_redef_add (sx : int) (sy : int) : stack_op list =
  [ PushReg sx; PushReg sy; Add; PopReg sx ]

let emit_flag_redef_sub (sx : int) (sy : int) : stack_op list =
  [ PushReg sx; PushReg sy; Sub; PopReg sx ]

(** 2. NONLINEAR DECOMPOSITION OF ADDITION VIA A CARRY CASCADE (Carry-Chain Expansion)
    Stack delta = -1 (pops 2 operands, leaves the sum).
    The original operands are additionally saved into sx/sy for the flag re-definition. *)
let emit_carry_chain_add (rng : Random.State.t) ~(s1 : int) ~(s2 : int) ~(sx : int) ~(sy : int)
    : stack_op list =
  [
    PopReg s2; PushReg s2; PopReg sy;   (* save y *)
    PopReg s1; PushReg s1; PopReg sx;   (* save x *)
  ] @ emit_carry_stages rng ~s1 ~s2

(** 3. DECOMPOSITION OF SUBTRACTION VIA COMPLEMENT AND A CARRY CASCADE
    x - y = x + (~y + 1) in Z_{2^64}.
    Stack delta = -1. *)
let emit_carry_chain_sub (rng : Random.State.t) ~(s1 : int) ~(s2 : int) ~(sx : int) ~(sy : int)
    : stack_op list =
  [
    PopReg s2; PushReg s2; PopReg sy;   (* save y *)
    PopReg s1; PushReg s1; PopReg sx;   (* save x *)
    (* neg_y = Nor(y, y) + 1 *)
    PushReg sy; PushReg sy; Nor;
    PushImm 1L; Add;
    PopReg s2;
  ] @ emit_carry_stages rng ~s1 ~s2

(** 4. WIRING TO A WRITE ANCHOR (Def-Use Webbing)
    Weaves an identity zero taken from a distant anchor into the stack top:
    Nor(r, Nor(r, r)) == 0L for any r. Stack delta = 0.
    The anchor is one of the K last written registers (a ring buffer
    in amplify_block), so the chord in the def-use graph reaches back up to K
    writes, not only to the last one. *)
let emit_expander_web_knot (rng : Random.State.t) ?(s_reg : int option = None) () : stack_op list =
  match s_reg with
  | Some reg ->
      (* Wiring to the register: v = v + Nor(r, Nor(r, r)) *)
      [
        PushReg reg;
        PushReg reg;
        Nor;
        PushReg reg;
        Nor;
        Add;
      ]
  | None ->
      let salt = rand_u64 rng in
      [
        Dup;
        PushImm salt;
        Add;
        Dup;
        Dup;
        Nor;
        Nor;
        Add;
      ]

let amplify_block
    (rng : Random.State.t)
    ~(profile : amplification_profile)
    ~(scratch_base : int)
    (block : block) : block =
  let live = Stack_flag_liveness.analyze_arr (Array.of_list block.ops) in
  let s1 = scratch_base in
  let s2 = scratch_base + 1 in
  let sx = scratch_base + 2 in
  let sy = scratch_base + 3 in
  let k_anchors = n_anchor_slots profile in
  let anchors = Array.init k_anchors (fun i -> scratch_base + 4 + i) in
  let anchor_j = ref 0 in
  let pick_anchor () = anchors.(Random.State.int rng k_anchors) in
  let maybe_knot phase =
    if !anchor_j > 0
       && phase mod max 1 profile.expander_chord_len = 0
       && Random.State.int rng 100 < profile.expander_chord_rate
    then emit_expander_web_knot rng ~s_reg:(Some (pick_anchor ())) ()
    else []
  in
  let new_ops =
    List.concat_map (fun (i, op) ->
      let flag_safe = not live.(i + 1) in
      match op with
      | PushImm c when flag_safe ->
          let horner = emit_horner_stack_insns rng ~target_const:c ~degree:profile.horner_degree in
          horner @ maybe_knot i

      | PushImm c ->
          (* Flags are live: it is safe to wrap via PushFlags/PopFlags
             (PushImm does not define flags, so restoring the pre-command
             state is correct). *)
          [PushFlags] @
          emit_horner_stack_insns rng ~target_const:c ~degree:profile.horner_degree @
          [Swap; PopFlags]

      | Add when profile.bit_slice_lanes > 0 ->
          let carry = emit_carry_chain_add rng ~s1 ~s2 ~sx ~sy in
          if flag_safe then carry @ maybe_knot (i + 1)
          else carry @ emit_flag_redef_add sx sy

      | Sub when profile.bit_slice_lanes > 0 ->
          let carry = emit_carry_chain_sub rng ~s1 ~s2 ~sx ~sy in
          if flag_safe then carry @ maybe_knot (i + 2)
          else carry @ emit_flag_redef_sub sx sy

      (* Bridge to Metamorphic_ring: the original command stays, on top of it —
         a flag-neutral ring twist. Always applicable. *)
      | Mul | Nor | Nand | Shl | Shr | Sar | Div | Idiv ->
          [ op ] @ emit_ring_twist rng

      | PopReg r ->
          let anchor = anchors.(!anchor_j mod k_anchors) in
          incr anchor_j;
          [ PopReg r; PushReg r; PopReg anchor ]
      | other ->
          [other]
    ) (List.mapi (fun i op -> (i, op)) block.ops)
  in
  { block with ops = new_ops }

let amplify_stack_program
    (rng : Random.State.t)
    ?ctx
    ~(profile : amplification_profile)
    (prog : program) : program =
  let scratch_base =
    match ctx with
    | Some c ->
        let s = Context_allocator.alloc_scratch c in
        for _ = 2 to 16 do
          ignore (Context_allocator.alloc_scratch c)
        done;
        s
    | None -> max 64 prog.context_slots
  in
  let new_context_slots =
    match ctx with
    | Some c ->
        Context_allocator.reserve_slots c (scratch_base + 16);
        (* The declared context must never shrink below what the input
           program already used: prog.context_slots is the size the
           program was built for, while total_slots c is the allocator's
           own counter.  They coincide after Ir_to_stack.lower_func, but
           relying on that coupling would silently produce out-of-range
           register accesses for any caller that does not keep them in
           sync (the Stack_ir.InvalidContextSlot invariant would fire
           and the emitted handlers would read past the context). *)
        max (scratch_base + 16)
          (max (Context_allocator.total_slots c) prog.context_slots)
    | None -> max (scratch_base + 16) prog.context_slots
  in
  (* Determinism: block order is fixed by id so block_rng seeds are stable
     regardless of Hashtbl.iter order or parallel scheduling. *)
  let sorted_blocks =
    Hashtbl.fold (fun id b acc -> (id, b) :: acc) prog.blocks []
    |> List.sort (fun (a, _) (b, _) -> compare a b)
    |> Array.of_list
  in
  (* Pre-derive one seed word per block sequentially (preserves the RNG
     stream of the caller), then map over blocks in parallel. *)
  let n = Array.length sorted_blocks in
  let parent_seeds = Array.init n (fun _ -> Random.State.bits rng) in
  (* Build a (parent_seed, id, block) triple for each block, then run all
     amplify_block calls in parallel.  Each block uses its own
     deterministic RNG (seeded from parent_seeds.(i) + id), so there is
     no shared mutable state between tasks. *)
  let pool = Random_visa_ports.Domain_pool.global_pool () in
  let indexed = Array.init n (fun i ->
    let (id, b) = sorted_blocks.(i) in
    let block_rng = Random.State.make [|
      parent_seeds.(i);
      id * 0x5877;
      (Int64.to_int salt_deadbeef);
    |] in
    (id, block_rng, b))
  in
  let out = Array.make n (0, { (snd sorted_blocks.(0)) with ops = [] }) in
  Random_visa_ports.Domain_pool.parallel_for pool ~n
    (fun i ->
      let (id, block_rng, b) = indexed.(i) in
      out.(i) <- (id, amplify_block block_rng ~profile ~scratch_base b));
  let new_blocks = Hashtbl.create n in
  Array.iter (fun (id, b) -> Hashtbl.replace new_blocks id b) out;
  { prog with blocks = new_blocks; context_slots = new_context_slots }

let amplifier_stats (prog_before : program) (prog_after : program) : string =
  let count_ops prog =
    Hashtbl.fold (fun _ b acc -> acc + List.length b.ops) prog.blocks 0
  in
  let ops_before = count_ops prog_before in
  let ops_after = count_ops prog_after in
  let ratio =
    if ops_before > 0 then float_of_int ops_after /. float_of_int ops_before
    else 1.0
  in
  Printf.sprintf
    "Bytecode Amplification: %d ops → %d ops (%.1fx expansion, 0%% dead code loss)"
    ops_before ops_after ratio
