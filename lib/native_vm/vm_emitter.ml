open Vm_ir
open Vm_transform
open Random_visa_constants.Magic_numbers

type vm_package = {
  bytecode : int64 list;
  bytecodes : (string * int64 list) list;
  cpp_runtime_source : string;
  runner_source : string;
  metrics : Metrics.metrics_report;
}

let shuffle_array rng arr =
  let n = Array.length arr in
  for i = n - 1 downto 1 do
    let j = Random.State.int rng (i + 1) in
    let tmp = arr.(i) in
    arr.(i) <- arr.(j);
    arr.(j) <- tmp
  done

let poly_multiplier_of_seed = Rolling_key.poly_multiplier_of_seed
let poly_init_of_seed = Rolling_key.poly_init_of_seed

(* The zero register shares its slot with the GS base in the native register
   file, so the guards that skip a write to it must compare the registers
   themselves and not their slot indices. *)
let is_zero_register (r : Register.t) =
  match r with
  | Register.Vreg (Register.VZERO, _) -> true
  | _ -> false
let emitter_dump_mutex = Mutex.create ()

let compile_and_package_multi
    ~rng
    ?runtime_profile
    ?config
    ?(enable_cff = false)
    ?(enable_mba = false)
    ?(enable_junk = true)
    ?(mba_depth = 2)
    ?(constants = [])
    (funcs : (string * Ir.func) list) =

  let (enable_cff, enable_mba, enable_junk, mba_depth, mba_engine,
       mba_max_depth, ir_eg_nodes, ir_eg_ms) =
    match config with
    | Some (c : Protection_config.t) ->
        (c.cff.enabled, c.mba.enabled, c.vm_runtime.enable_junk_instructions,
         c.mba.depth, c.mba.engine,
         c.mba.ir_max_depth, c.mba.ir_egraph_node_limit, c.mba.ir_egraph_time_budget_ms)
    | None ->
        (enable_cff, enable_mba, enable_junk, mba_depth, `Egraph,
         4, 80, 50)
  in

  (* ADC/SBC carry dialect (todo item 8): ARM64 reads C = NOT borrow after
     SUB-family flag writers, x86 reads CF = borrow.  The tag bit travels in
     the word's extra_bits area alongside set_flags. *)
  let arm64_carry = Protection_config.arm64_carry_enabled config in


  (* Generate randomized bijective register permutation π ∈ S_32 *)
  let reg_perm = Array.init 32 (fun i -> i) in
  shuffle_array rng reg_perm;
  let get_reg_idx r = reg_perm.(reg_to_index r) in

  (* Set up opcode bijection, polymorphic opcode aliases, and junk decoys with 100% table saturation *)
  let slots = Array.init 256 (fun i -> i) in
  shuffle_array rng slots;
  let kind_to_codes = Hashtbl.create 32 in
  let opcode_to_handler = Array.make 256 "H_DECOY" in
  List.iteri
    (fun i kind ->
      let code = slots.(i) in
      Hashtbl.replace kind_to_codes kind [code];
      opcode_to_handler.(code) <- op_kind_to_handler_name kind)
    all_op_kinds;

  let curr_slot = ref (List.length all_op_kinds) in
  let alias_specs = [
    (OP_ADD_RR, [ "H_ADD_RR_A1"; "H_ADD_RR_A2" ]);
    (OP_MOV_RR, [ "H_MOV_RR_A1"; "H_MOV_RR_A2" ]);
    (OP_MOV_RI, [ "H_MOV_RI_A1"; "H_MOV_RI_A2" ]);
    (OP_JMP,    [ "H_JMP_A1";    "H_JMP_A2" ]);
    (OP_CMP_RI, [ "H_CMP_RI_A1"; "H_CMP_RI_A2" ]);
    (OP_CMP_RR, [ "H_CMP_RR_A1" ]);
    (OP_SUB_RR, [ "H_SUB_RR_A1" ]);
    (OP_XOR_RR, [ "H_XOR_RR_A1" ]);
    (OP_AND_RR, [ "H_AND_RR_A1" ]);
    (OP_OR_RR,  [ "H_OR_RR_A1" ]);
    (OP_JCC,    [ "H_JCC_A1" ]);
  ] in
  List.iter (fun (kind, handlers) ->
    List.iter (fun h ->
      if !curr_slot < 256 then begin
        let code = slots.(!curr_slot) in
        incr curr_slot;
        opcode_to_handler.(code) <- h;
        let prev = match Hashtbl.find_opt kind_to_codes kind with Some l -> l | None -> [] in
        Hashtbl.replace kind_to_codes kind (code :: prev)
      end
    ) handlers
  ) alias_specs;

  (* Saturate all remaining opcode slots with polymorphic decoy handlers *)
  for i = !curr_slot to 255 do
    let code = slots.(i) in
    let decoy_idx = i mod 16 in
    opcode_to_handler.(code) <- Printf.sprintf "H_DECOY_%d" decoy_idx
  done;

  let get_opcode kind =
    match Hashtbl.find_opt kind_to_codes kind with
    | Some [code] -> code
    | Some codes ->
        let idx = Random.State.int rng (List.length codes) in
        List.nth codes idx
    | None -> failwith ("Unknown opcode kind: " ^ op_kind_to_handler_name kind)
  in

  let enable_super_ops =
    match config with
    | Some (c : Protection_config.t) -> c.vm_runtime.enable_super_operators
    | None -> true
  in

  let junk_density =
    match config with
    | Some (c : Protection_config.t) -> (
        let d = c.bloat.junk_density in
        let t1 = c.bloat.density_cap_threshold1_kb in
        let t2 = c.bloat.density_cap_threshold2_kb in
        match c.bloat.target_size_budget_kb with
        | Some budget_kb when t1 > 0 && budget_kb < t1 -> min d 0.1
        | Some budget_kb when t2 > 0 && budget_kb < t2 -> min d 0.5
        | _ -> d
      )
    | None -> 0.5
  in

  let gpu_mba_pool =
    if enable_mba then
      let mba_seed = Random.State.int64 rng 0x7FFFFFFFFFFFFFFFL in
      Some (Gpu_synth.Gpu_mba.create_pool ~seed:mba_seed ~rng ())
    else None
  in

  let gpu_sub_matrix =
    if enable_mba then
      Some (Gpu_synth.Gpu_matrix.generate ~rng ())
    else None
  in

  let key_seed = Random.State.int32 rng Int32.max_int in
  let word_layout = Rolling_key.layout_of_seed key_seed in
  let enable_rolling = Protection_config.rolling_key_enabled config in
  let enable_address_bound = Protection_config.address_bound_enabled config in

  let external_symbols = ref [] in
  let external_sym_tbl = Hashtbl.create 16 in
  let get_ext_sym_idx sym =
    match Hashtbl.find_opt external_sym_tbl sym with
    | Some idx -> idx
    | None ->
        let idx = List.length !external_symbols in
        external_symbols := !external_symbols @ [ sym ];
        Hashtbl.replace external_sym_tbl sym idx;
        idx
  in

  let compute_bytecode_hash seed bc =
    let mul_k = poly_multiplier_of_seed seed in
    let h = ref (poly_init_of_seed seed) in
    List.iteri
      (fun i w ->
        let mixed = Int64.logxor !h w in
        let mul = Int64.mul mixed mul_k in
        h := Int64.add mul (Int64.of_int i))
      bc;
    !h
  in

  let compile_one_func ?(macro_salt = 0) (func : Ir.func) =
    let func =
      if enable_mba then
        Dynamic_mba.transform ~density:0.4 ~rng func
      else func
    in
    let func =
      if enable_junk then
        Data_keyed_decoy.transform ~rng func
      else func
    in
    let func = Dag_scheduler.transform ~rng func in
    let target_func =
      if enable_cff then
        (* POP digest transform and the pop_digest option must be gated
           together: enabling one without the other leaves either an
           uninitialized digest register or dead digest computation. *)
        let pop_enabled, red_herring =
          match config with
          | Some c -> (c.cff.pop_digest, c.cff.red_herring)
          | None -> (true, true)
        in
        let cff_opts =
          match config with
          | Some c ->
              {
                Cff.inject_opaque_predicates = c.cff.inject_opaque_predicates;
                obfuscate_states = c.cff.obfuscate_states;
                input_tainted_transitions = c.cff.input_tainted_transitions;
                split_rate = c.cff.split_rate;
                hub_count = c.cff.hub_count;
                pop_digest =
                  (if pop_enabled then
                     Some (Cff.Pop_coupler.default_pop_config.digest_reg,
                           Cff.Pop_coupler.default_pop_config.initial_seed)
                   else None);
                red_herring;
              }
          | None ->
              { Cff.default_cff_options with
                pop_digest =
                  (if pop_enabled then
                     Some (Cff.Pop_coupler.default_pop_config.digest_reg,
                           Cff.Pop_coupler.default_pop_config.initial_seed)
                   else None);
                red_herring;
              }
        in
        let pop_func =
          if pop_enabled then Cff.Pop_coupler.apply_pop_transform ~rng func else func
        in
        match Cff.flatten_func ~options:cff_opts ~rng pop_func with
        | Ok f -> f
        | Error _ -> func
      else func
    in

    (* Linearize blocks and calculate block start offsets in bytecode with Super-Operator fusion and Junk insertion *)
    let is_block_terminated (b : Ir.basic_block) =
      match List.rev b.instrs with
      | (Ir.Jmp _ | Ir.Jcc _ | Ir.Ret | Ir.Vm_exit | Ir.Trap _) :: _ -> true
      | _ -> false
    in
    let entry_block = Hashtbl.find target_func.cfg.blocks target_func.cfg.entry_id in
    let other_blocks =
      Hashtbl.fold
        (fun id b acc -> if id <> target_func.cfg.entry_id then b :: acc else acc)
        target_func.cfg.blocks []
    in
    let sorted_other = List.sort (fun (a : Ir.basic_block) (b : Ir.basic_block) -> Int.compare a.id b.id) other_blocks in
    let rec canonicalize_fallthrough = function
      | [] -> []
      | [last] -> [last]
      | curr :: (next :: _ as rest) ->
          let curr' =
            if is_block_terminated curr then curr
            else { curr with instrs = curr.instrs @ [ Ir.Jmp (Ir.BlockId next.id) ] }
          in
          curr' :: canonicalize_fallthrough rest
    in
    let canonical_blocks = canonicalize_fallthrough (entry_block :: sorted_other) in
    let entry_block_canon = List.hd canonical_blocks in
    let other_canon = List.tl canonical_blocks in
    let other_arr = Array.of_list other_canon in
    shuffle_array rng other_arr;
    let sorted_blocks = entry_block_canon :: (Array.to_list other_arr) in

    (* -----------------------------------------------------------------------
       Parallel MBA via domainslib Task pool.
       Each basic block is independent — no shared state between blocks.
       A fork-per-block RNG ensures deterministic output regardless of
       scheduling order.
       ----------------------------------------------------------------------- *)
    let blocks_arr = Array.of_list sorted_blocks in
    let n_blocks   = Array.length blocks_arr in

    (* Pre-generate per-block RNGs deterministically from master state *)
    let block_rngs = Array.init n_blocks (fun _ ->
      Random.State.make [| Random.State.bits rng |]
    ) in

    (* Result array — index i written only by worker i, no contention *)
    let results = Array.make n_blocks (0, ([] : fused_op list)) in

    (* Use global pool — avoids spawn/teardown overhead per call *)
    let pool = Mba_par.global_pool () in
  Domainslib.Task.run pool (fun () ->
    Domainslib.Task.parallel_for pool ~start:0 ~finish:(n_blocks - 1)
      ~body:(fun i ->
        let b    = blocks_arr.(i) in
        let brng = block_rngs.(i) in
        let block_mba_depth =
          let jitter = Random.State.int brng 3 - 1 in (* -1, 0, +1 *)
          max 1 (min mba_max_depth (mba_depth + jitter))
        in
        let ir_eg_cfg =
          { Mba_engine.Egraph.
            node_limit = ir_eg_nodes;
            time_budget_s = float_of_int ir_eg_ms /. 1000.0;
            iter_limit = block_mba_depth }
        in
        let instrs =
          if enable_mba then
            List.concat_map
              (function
                | Ir.Alu { op; dst; src1; src2; set_flags } ->
                    let is_ineligible_reg = function
                      | Register.Gpr (Register.RSP, _) | Register.Vreg _ -> true
                      | _ -> false
                    in
                    let is_ineligible_op = function
                      | Ir.Reg r -> is_ineligible_reg r
                      | _ -> false
                    in
                    if set_flags || op = Ir.Adc || op = Ir.Sbb
                       || is_ineligible_reg dst || is_ineligible_op src1 || is_ineligible_op src2 then
                      [ Ir.Alu { op; dst; src1; src2; set_flags } ]
                    else (
                      try
                        match mba_engine with
                        | `Egraph ->
                            Mba_engine.Egraph.obfuscate_alu ~config:ir_eg_cfg ~rng:brng ~dst ~src1 ~src2 op
                        | `Poly   -> Mba_engine.Mba.obfuscate_alu ~rng:brng ~depth:block_mba_depth ~dst ~src1 ~src2 op
                        | `Ncfg   -> Mba_engine.Ncfg_synth.obfuscate_alu ~rng:brng ~depth:block_mba_depth ~dst ~src1 ~src2 op
                        | `Nullspace -> Mba_engine.Nullspace_synth.obfuscate_alu ~rng:brng ~dst ~src1 ~src2 op
                        | `Gpu_metal -> (
                            match gpu_mba_pool with
                            | Some gpool -> Gpu_synth.Gpu_mba.obfuscate_alu ~pool:gpool ~rng:brng ~dst ~src1 ~src2 op
                            | None -> Mba_engine.Egraph.obfuscate_alu ~rng:brng ~dst ~src1 ~src2 op)
                      with _ ->
                        [ Ir.Alu { op; dst; src1; src2; set_flags = false } ])
                | other -> [ other ])
              b.instrs
          else b.instrs
        in
        let instrs = canonicalize_3addr_alu instrs in
        let instrs = if enable_junk then inject_junk_instructions ~density:junk_density ~rng:brng instrs else instrs in
        (match Sys.getenv_opt "ASGARD_VM_EMITTER_DUMP" with
         | Some path ->
             let lines =
               Array.make (List.length instrs + 1) None in
             List.iteri (fun k (ins : Ir.instr) ->
               lines.(k) <- Some (Ir.instr_to_string ins)) instrs;
             lines.(List.length instrs) <- Some (Printf.sprintf "-- end block %d --" b.id);
             let buf = Buffer.create 256 in
             Array.iter (function
               | Some l -> Buffer.add_string buf (Printf.sprintf "B%d: %s\n" b.id l)
               | None -> ()) lines;
             Mutex.lock emitter_dump_mutex;
             let oc = open_out_gen [Open_append; Open_creat] 0o644 path in
             output_string oc (Buffer.contents buf);
             close_out oc;
             Mutex.unlock emitter_dump_mutex
         | None -> ());
        let fused  = if enable_super_ops then fuse_block_instructions instrs
                     else List.map (fun i -> Raw i) instrs in
        results.(i) <- (b.id, fused))
  );

  let block_fused_ops = Hashtbl.create n_blocks in
  Array.iter (fun (id, fused) -> Hashtbl.replace block_fused_ops id fused) results;

  let is_i32 imm = imm >= -2147483648L && imm <= 2147483647L in
  let words_of_fused = function
    | Raw (Ir.Mov { dst = Ir.Reg (Register.Fpr _); src = Ir.Imm imm }) ->
        if Int64.shift_right_logical imm 32 <> 0L then 3 else 2
    | Raw (Ir.Mov { dst = Ir.Reg _; src = Ir.Imm imm }) when Int64.shift_right_logical imm 32 <> 0L -> 2
    | Raw (Ir.Mov { dst = Ir.Mem _; src = Ir.Imm _ }) -> 2
    | Raw (Ir.Load_symbol { addend; _ }) when addend <> 0L -> 2
    | Raw (Ir.Set_flags (Ir.Imm _ | Ir.Mem _)) -> 2
    | Raw (Ir.Alu { src2 = Ir.Imm imm; _ }) when not (is_i32 imm) ->
        if Int64.shift_right_logical imm 32 <> 0L then 3 else 2
    | Raw (Ir.Cmp { src2 = Ir.Imm imm; _ }) when not (is_i32 imm) ->
        if Int64.shift_right_logical imm 32 <> 0L then 3 else 2
    | _ -> 1
  in
  let block_offsets = Hashtbl.create (List.length sorted_blocks) in
  let cur_offset = ref 0 in
  List.iter
    (fun (b : Ir.basic_block) ->
      let fused = Hashtbl.find block_fused_ops b.id in
      Hashtbl.replace block_offsets b.id !cur_offset;
      let count = List.fold_left (fun acc op -> acc + words_of_fused op) 0 fused in
      cur_offset := !cur_offset + count)
    sorted_blocks;

  let get_block_offset id =
    Option.value ~default:0 (Hashtbl.find_opt block_offsets id)
  in

  let label_to_block = Hashtbl.create 16 in
  List.iter
    (fun (b : Ir.basic_block) ->
      if b.label <> "" then Hashtbl.replace label_to_block b.label b.id)
    sorted_blocks;

  let resolve_target = function
    | Ir.BlockId bid -> Int64.of_int (get_block_offset bid)
    | Ir.TargetImm imm -> imm
    | Ir.TargetReg r -> Int64.of_int (get_reg_idx r)
    | Ir.Label sym -> (
        match Hashtbl.find_opt label_to_block sym with
        | Some bid -> Int64.of_int (get_block_offset bid)
        | None -> (
            try Int64.of_string sym
            with _ ->
              failwith (Printf.sprintf "vm_emitter: unresolved target label '%s'" sym)))
  in

  let cur_idx = ref 0 in
  let bytecode = ref [] in
  let cur_key = ref 0L in
  let assert_src1_eq_dst ~op ~dst ~src1 =
    match src1 with
    | Ir.Reg s1 when Register.to_string s1 = Register.to_string dst -> ()
    | Ir.Reg s1 ->
        failwith (Printf.sprintf "vm_emitter: uncanonicalized 3-address ALU (op=%s): dst=%s, src1=%s (must be canonicalized to src1=dst)"
          (Ir.alu_op_to_string op) (Register.to_string dst) (Register.to_string s1))
    | _ ->
        failwith (Printf.sprintf "vm_emitter: invalid ALU src1 (op=%s): dst=%s, src1=%s (must be Reg dst)"
          (Ir.alu_op_to_string op) (Register.to_string dst) (Ir.operand_to_string src1))
  in
  let encode_raw_word ?(extra_bits = 0L) op dst src imm =
    let op_salted = (op lxor macro_salt) land 0xFF in
    let w = ref 0L in
    w := Int64.logor !w (Int64.shift_left (Int64.of_int op_salted) word_layout.op_shift);
    w := Int64.logor !w (Int64.shift_left (Int64.of_int dst) word_layout.dst_shift);
    w := Int64.logor !w (Int64.shift_left (Int64.of_int src) word_layout.src_shift);
    let imm_masked =
      if extra_bits <> 0L then
        Int64.logand imm 0xFFFFFFFFL
      else
        Int64.logand imm 0x3FFFFFFFFFFFL
    in
    w := Int64.logor !w (Int64.shift_left imm_masked 18);
    if extra_bits <> 0L then
      w := Int64.logor !w (Int64.shift_left (Int64.logand extra_bits 0x3FFFL) 50);
    let k_pos = Rolling_key.key64_for_offset key_seed !cur_idx in
    let mask = if enable_address_bound then k_pos else Int64.logxor k_pos !cur_key in
    incr cur_idx;
    let masked_w = Int64.logxor !w mask in
    if enable_rolling && not enable_address_bound then begin
      (* Advance exactly like FETCH_NEXT does: op is the randomized opcode byte,
         imm is re-read from the packed word (32-bit sign-extended window), never
         from the source immediate — the 46→32 bit truncation must match. *)
      let (dop, ddst, _, dimm) = Rolling_key.decode_fields ~layout:word_layout !w in
      cur_key := Rolling_key.advance_key_step !cur_key dop ddst dimm
    end;
    bytecode := masked_w :: !bytecode
  in


  let vector_index i = i mod 32 in
  let vector_op_code = function
    | Ir.Vadd -> 0 | Ir.Vsub -> 1 | Ir.Vmul -> 2 | Ir.Vand -> 3 | Ir.Vor -> 4 | Ir.Vxor -> 5
    | Ir.Vsll -> 6 | Ir.Vsrl -> 7 | Ir.Vsra -> 8
    | Ir.Vcmpeq -> 9 | Ir.Vcmpgt -> 10
    | Ir.Vmin -> 11 | Ir.Vmax -> 12 | Ir.Vminu -> 13 | Ir.Vmaxu -> 14
    | Ir.Vabs -> 15 | Ir.Vandn -> 16
    | Ir.Vunpckl -> 17 | Ir.Vunpckh -> 18
    | Ir.Vpackss -> 19 | Ir.Vpackus -> 20
    | Ir.Vshuf -> 21 | Ir.Vblend -> 22
    | Ir.Vuzp1 -> 23 | Ir.Vuzp2 -> 24
    | Ir.Vtrn1 -> 25 | Ir.Vtrn2 -> 26
    | Ir.Vtbl -> 28 | Ir.Vtbx -> 29
    | Ir.Vdiv -> 30 | Ir.Vdivu -> 31 | Ir.Vrem -> 32 | Ir.Vremu -> 33
    | Ir.Vcmpne -> 34 | Ir.Vcmple -> 35 | Ir.Vcmpltu -> 36 | Ir.Vcmpleu -> 37
    | Ir.Vmaddwd -> 38 | Ir.Vsadbw -> 39
    | Ir.Vshuflw -> 40 | Ir.Vshufhw -> 41
    | Ir.Vsqadd -> 42 | Ir.Vsqsub -> 43 | Ir.Vsqrdmulh -> 44
  in
  let vector_elem_code = function
    | Ir.VInt -> 0 | Ir.VF32 -> 1 | Ir.VF64 -> 2
  in
  let vector_imm ~src2 ~bits ~lane_bits ~elem op =
    let w = Int64.of_int src2 in
    let w = Int64.logor w (Int64.shift_left (Int64.of_int bits) 5) in
    let w = Int64.logor w (Int64.shift_left (Int64.of_int lane_bits) 15) in
    let w = Int64.logor w (Int64.shift_left (Int64.of_int (vector_op_code op)) 23) in
    Int64.logor w (Int64.shift_left (Int64.of_int (vector_elem_code elem)) 29)
  in
  let vector_imm_val ~imm_val ~bits ~lane_bits ~elem:_ op =
    let w = Int64.logand imm_val 0xFFL in
    let w = Int64.logor w (Int64.shift_left (Int64.of_int bits) 8) in
    let w = Int64.logor w (Int64.shift_left (Int64.of_int lane_bits) 18) in
    Int64.logor w (Int64.shift_left (Int64.of_int ((vector_op_code op) land 0x3F)) 26)
  in

  let sha_op_code = function
    | Ir.Sha1rnds4 -> 0
    | Ir.Sha1nexte -> 1
    | Ir.Sha1msg1 -> 2
    | Ir.Sha1msg2 -> 3
    | Ir.Sha256rnds2 -> 4
    | Ir.Sha256msg1 -> 5
    | Ir.Sha256msg2 -> 6
  in
  let sha_imm ~src2 ~src3 ~imm ~bits =
    (* The immediate field carries the two source registers, the eight-bit
       immediate of SHA1RNDS4 and the width of the vector register. *)
    let w = Int64.of_int src2 in
    let w = Int64.logor w (Int64.shift_left (Int64.of_int src3) 5) in
    let w = Int64.logor w (Int64.shift_left (Int64.logand imm 0xFFL) 10) in
    Int64.logor w (Int64.shift_left (Int64.of_int bits) 18)
  in

  let aes_op_code = function
    | Ir.Aesenc -> 0
    | Ir.Aesenclast -> 1
    | Ir.Aesdec -> 2
    | Ir.Aesdeclast -> 3
    | Ir.Aesimc -> 4
    | Ir.Aeskeygenassist -> 5
  in
  let aes_imm ~src2 ~imm ~bits =
    let p = Int64.of_int (src2 land 31) in
    let p = Int64.logor p (Int64.shift_left (Int64.logand imm 0xFFL) 5) in
    Int64.logor p (Int64.shift_left (Int64.of_int bits) 13)
  in

  let vec_conv_op_code = function
    | Ir.Vcvtps2pd -> 0
    | Ir.Vcvtpd2ps -> 1
    | Ir.Vcvtdq2ps -> 2
    | Ir.Vcvtps2dq -> 3
    | Ir.Vcvttps2dq -> 4
    | Ir.Vcvtdq2pd -> 5
    | Ir.Vcvtpd2dq -> 6
    | Ir.Vcvttpd2dq -> 7
  in

  let encode_alu_imm ?(extra_bits = 0L) op_ri op_rr dst imm =
    if is_i32 imm then
      encode_raw_word ~extra_bits (get_opcode op_ri) (get_reg_idx dst) 0 imm
    else begin
      let temp_reg = if dst = Register.vx23 then Register.vx22 else Register.vx23 in
      let low = Int64.logand imm 0xFFFFFFFFL in
      let high = Int64.shift_right_logical imm 32 in
      encode_raw_word (get_opcode OP_MOV_RI) (get_reg_idx temp_reg) 0 low;
      if high <> 0L then
        encode_raw_word (get_opcode OP_MOV_HIGH) (get_reg_idx temp_reg) 0 high;
      encode_raw_word ~extra_bits (get_opcode op_rr) (get_reg_idx dst) (get_reg_idx temp_reg) 0L
    end
  in

  (* ADC/SBC word tags in the extra_bits area (bits 50..51): bit 0 =
     set_flags (handler writes NZCV), bit 1 = ARM64 carry dialect (handler
     reads ctx.cf_arm64, the ARM64-view carry, instead of ctx.cf).  Words
     without the tags keep the legacy x86 behaviour. *)
  let carry_tags set_flags =
    Int64.logor
      (if set_flags then 1L else 0L)
      (if arm64_carry then 2L else 0L)
  in

  (* Encode instructions (both Fused Super-Operators and Standard Raw Ops) *)
  List.iter
    (fun (b : Ir.basic_block) ->
      let ops = Hashtbl.find block_fused_ops b.id in
      (* Loop-safety: re-anchor the chain at every block entry, mirroring the
         runtime reanchor in H_JMP/H_JCC/H_CALL and the offset-0 entry probe.
         Blocks are encoded in layout order, so the offset below is exactly
         where this block's first word will land. *)
      if enable_rolling && not enable_address_bound then
        cur_key := Rolling_key.anchor_key key_seed (get_block_offset b.id);
      List.iter
        (function
          | Fused_Mov_Add { dst; src; imm } ->
              encode_raw_word (get_opcode OP_FUSED_MOV_ADD_RRI) (get_reg_idx dst) (get_reg_idx src) imm
          | Fused_Add_Imul { dst; src; imm } ->
              encode_raw_word (get_opcode OP_FUSED_ADD_IMUL_RRI) (get_reg_idx dst) (get_reg_idx src) imm
          | Fused_Add_Xor { dst; src; imm } ->
              encode_raw_word (get_opcode OP_FUSED_ADD_XOR_RRI) (get_reg_idx dst) (get_reg_idx src) imm
          | Fused_Sub_Xor { dst; src; imm } ->
              encode_raw_word (get_opcode OP_FUSED_SUB_XOR_RRI) (get_reg_idx dst) (get_reg_idx src) imm
          | Fused_Xor_Add { dst; src; imm } ->
              encode_raw_word (get_opcode OP_FUSED_XOR_ADD_RRI) (get_reg_idx dst) (get_reg_idx src) imm
          | Fused_And_Or { dst; src; imm } ->
              encode_raw_word (get_opcode OP_FUSED_AND_OR_RRI) (get_reg_idx dst) (get_reg_idx src) imm
          | Fused_Shl_Add { dst; src; imm } ->
              encode_raw_word (get_opcode OP_FUSED_SHL_ADD_RRI) (get_reg_idx dst) (get_reg_idx src) imm
          | Fused_Cmp_Cmov { cmp_dst; cmp_imm; cond; cmov_dst; cmov_src } ->
              let bits = Register.width_to_bits (Register.get_width cmp_dst) in
              let c = cond_to_code cond in
              let extra = Int64.logor (Int64.of_int c) (Int64.shift_left (Int64.of_int bits) 4) in
              encode_raw_word ~extra_bits:extra
                (get_opcode OP_FUSED_CMP_CMOV) (get_reg_idx cmov_dst) (get_reg_idx cmov_src) cmp_imm
          | Raw instr -> (
              match instr with
              | Ir.Nop -> encode_raw_word (get_opcode OP_NOP) 0 0 0L
              | Ir.Mov { dst = Ir.Reg (Register.Fpr (d, w)); src = Ir.Reg (Register.Fpr (s, _)) } ->
                  let bits = Int64.of_int (Register.width_to_bytes w * 8) in
                  encode_raw_word (get_opcode OP_VEC_MOV) (d mod 32) (s mod 32) bits
              | Ir.Mov { dst = Ir.Reg (Register.Fpr (d, _)); src = Ir.Reg s } ->
                  encode_raw_word (get_opcode OP_MOV_VR) (d mod 32) (get_reg_idx s) 0L
              | Ir.Mov { dst = Ir.Reg d; src = Ir.Reg (Register.Fpr (s, _)) } ->
                  encode_raw_word (get_opcode OP_MOV_RV) (get_reg_idx d) (s mod 32) 0L
              | Ir.Mov { dst = Ir.Reg (Register.Fpr (d, _)); src = Ir.Imm imm } ->
                  let temp_reg = Register.vtmp0 in
                  let low = Int64.logand imm 0xFFFFFFFFL in
                  let high = Int64.shift_right_logical imm 32 in
                  encode_raw_word (get_opcode OP_MOV_RI) (get_reg_idx temp_reg) 0 low;
                  if high <> 0L then
                    encode_raw_word (get_opcode OP_MOV_HIGH) (get_reg_idx temp_reg) 0 high;
                  encode_raw_word (get_opcode OP_MOV_VR) (d mod 32) (get_reg_idx temp_reg) 0L
              | Ir.Mov { dst = Ir.Reg (Register.Fpr (d, w)); src = Ir.Mem m } ->
                  let mem_bits = Register.width_to_bytes m.width * 8 in
                  let reg_bits = Register.width_to_bytes w * 8 in
                  let bits = Int64.of_int (min mem_bits reg_bits) in
                  let base_idx = match m.base with Some b -> get_reg_idx b | None -> 0 in
                  encode_raw_word ~extra_bits:bits (get_opcode OP_VEC_LOAD) (d mod 32) base_idx m.disp
              | Ir.Mov { dst = Ir.Mem m; src = Ir.Reg (Register.Fpr (s, w)) } ->
                  let mem_bits = Register.width_to_bytes m.width * 8 in
                  let reg_bits = Register.width_to_bytes w * 8 in
                  let bits = Int64.of_int (min mem_bits reg_bits) in
                  let base_idx = match m.base with Some b -> get_reg_idx b | None -> 0 in
                  encode_raw_word ~extra_bits:bits (get_opcode OP_VEC_STORE) base_idx (s mod 32) m.disp
              | Ir.Mov { dst = Ir.Reg d; src = Ir.Reg s } ->
                  encode_raw_word (get_opcode OP_MOV_RR) (get_reg_idx d) (get_reg_idx s) 0L
              | Ir.Mov { dst = Ir.Reg d; src = Ir.Imm imm } ->
                  let low = Int64.logand imm 0xFFFFFFFFL in
                  let high = Int64.shift_right_logical imm 32 in
                  encode_raw_word (get_opcode OP_MOV_RI) (get_reg_idx d) 0 low;
                  if high <> 0L then
                    encode_raw_word (get_opcode OP_MOV_HIGH) (get_reg_idx d) 0 high
              | Ir.Mov { dst = Ir.Reg d; src = Ir.Mem m } ->
                  if m.index <> None then
                    failwith "vm_emitter: uncanonicalized SIB indexed memory load (must be canonicalized before emission)";
                  let op =
                    if m.is_signed then
                      match m.width with
                      | Register.B32 -> OP_LOAD_S32
                      | Register.B16 -> OP_LOAD_S16
                      | Register.B8  -> OP_LOAD_S8
                      | _ -> OP_LOAD_64
                    else
                      match m.width with
                      | Register.B64 -> OP_LOAD_64
                      | Register.B32 -> OP_LOAD_32
                      | Register.B16 -> OP_LOAD_16
                      | _ -> OP_LOAD_8
                  in
                  let base_idx = match m.base with Some b -> get_reg_idx b | None -> 0 in
                  encode_raw_word (get_opcode op) (get_reg_idx d) base_idx m.disp
              | Ir.Mov { dst = Ir.Mem m; src = Ir.Reg s } ->
                  if m.index <> None then
                    failwith "vm_emitter: uncanonicalized SIB indexed memory store (must be canonicalized before emission)";
                  let op =
                    match m.width with
                    | Register.B64 -> OP_STORE_64
                    | Register.B32 -> OP_STORE_32
                    | Register.B16 -> OP_STORE_16
                    | _ -> OP_STORE_8
                  in
                  let base_idx = match m.base with Some b -> get_reg_idx b | None -> 0 in
                  encode_raw_word (get_opcode op) base_idx (get_reg_idx s) m.disp
              | Ir.Mov { dst = Ir.Mem m; src = Ir.Imm imm } ->
                  if m.index <> None then
                    failwith "vm_emitter: uncanonicalized SIB indexed memory store (must be canonicalized before emission)";
                  let temp_reg =
                    match m.base with
                    | Some b when Register.to_string b = Register.to_string Register.vtmp0 -> Register.vtmp1
                    | _ -> Register.vtmp0
                  in
                  encode_raw_word (get_opcode OP_MOV_RI) (get_reg_idx temp_reg) 0 imm;
                  let op =
                    match m.width with
                    | Register.B64 -> OP_STORE_64
                    | Register.B32 -> OP_STORE_32
                    | Register.B16 -> OP_STORE_16
                    | _ -> OP_STORE_8
                  in
                  let base_idx = match m.base with Some b -> get_reg_idx b | None -> 0 in
                  encode_raw_word (get_opcode op) base_idx (get_reg_idx temp_reg) m.disp
              | Ir.Alu { op = Ir.Add; dst = d; src1; src2 = Ir.Reg s; _ } ->
                  assert_src1_eq_dst ~op:Ir.Add ~dst:d ~src1;
                  encode_raw_word (get_opcode OP_ADD_RR) (get_reg_idx d) (get_reg_idx s) 0L
              | Ir.Alu { op = Ir.Add; dst = d; src1; src2 = Ir.Imm imm; _ } ->
                  assert_src1_eq_dst ~op:Ir.Add ~dst:d ~src1;
                  encode_alu_imm OP_ADD_RI OP_ADD_RR d imm
              | Ir.Alu { op = Ir.Adc; dst = d; src1; src2 = Ir.Reg s; set_flags } ->
                  assert_src1_eq_dst ~op:Ir.Adc ~dst:d ~src1;
                  encode_raw_word ~extra_bits:(carry_tags set_flags)
                    (get_opcode OP_ADC_RR) (get_reg_idx d) (get_reg_idx s) 0L
              | Ir.Alu { op = Ir.Adc; dst = d; src1; src2 = Ir.Imm imm; set_flags } ->
                  assert_src1_eq_dst ~op:Ir.Adc ~dst:d ~src1;
                  encode_alu_imm ~extra_bits:(carry_tags set_flags) OP_ADC_RI OP_ADC_RR d imm
              | Ir.Alu { op = Ir.Sub; dst = d; src1; src2 = Ir.Reg s; _ } ->
                  assert_src1_eq_dst ~op:Ir.Sub ~dst:d ~src1;
                  encode_raw_word (get_opcode OP_SUB_RR) (get_reg_idx d) (get_reg_idx s) 0L
              | Ir.Alu { op = Ir.Sub; dst = d; src1; src2 = Ir.Imm imm; _ } ->
                  assert_src1_eq_dst ~op:Ir.Sub ~dst:d ~src1;
                  encode_alu_imm OP_SUB_RI OP_SUB_RR d imm
              | Ir.Alu { op = Ir.Sbb; dst = d; src1; src2 = Ir.Reg s; set_flags } ->
                  assert_src1_eq_dst ~op:Ir.Sbb ~dst:d ~src1;
                  encode_raw_word ~extra_bits:(carry_tags set_flags)
                    (get_opcode OP_SBB_RR) (get_reg_idx d) (get_reg_idx s) 0L
              | Ir.Alu { op = Ir.Sbb; dst = d; src1; src2 = Ir.Imm imm; set_flags } ->
                  assert_src1_eq_dst ~op:Ir.Sbb ~dst:d ~src1;
                  encode_alu_imm ~extra_bits:(carry_tags set_flags) OP_SBB_RI OP_SBB_RR d imm
              | Ir.Alu { op = (Ir.Mul | Ir.Imul); dst = d; src1; src2 = Ir.Reg s; _ } ->
                  assert_src1_eq_dst ~op:Ir.Imul ~dst:d ~src1;
                  encode_raw_word (get_opcode OP_IMUL_RR) (get_reg_idx d) (get_reg_idx s) 0L
              | Ir.Alu { op = (Ir.Mul | Ir.Imul); dst = d; src1; src2 = Ir.Imm imm; _ } ->
                  assert_src1_eq_dst ~op:Ir.Imul ~dst:d ~src1;
                  encode_alu_imm OP_IMUL_RI OP_IMUL_RR d imm
              | Ir.Alu { op = Ir.Mulh; dst = d; src1; src2 = Ir.Reg s; _ } ->
                  assert_src1_eq_dst ~op:Ir.Mulh ~dst:d ~src1;
                  encode_raw_word (get_opcode OP_MULH_RR) (get_reg_idx d) (get_reg_idx s) 0L
              | Ir.Alu { op = Ir.Imulh; dst = d; src1; src2 = Ir.Reg s; _ } ->
                  assert_src1_eq_dst ~op:Ir.Imulh ~dst:d ~src1;
                  encode_raw_word (get_opcode OP_IMULH_RR) (get_reg_idx d) (get_reg_idx s) 0L
              | Ir.Alu { op = Ir.Div; dst = d; src1; src2 = Ir.Reg s; _ } ->
                  assert_src1_eq_dst ~op:Ir.Div ~dst:d ~src1;
                  encode_raw_word (get_opcode OP_DIV_RR) (get_reg_idx d) (get_reg_idx s) 0L
              | Ir.Alu { op = Ir.Idiv; dst = d; src1; src2 = Ir.Reg s; _ } ->
                  assert_src1_eq_dst ~op:Ir.Idiv ~dst:d ~src1;
                  encode_raw_word (get_opcode OP_IDIV_RR) (get_reg_idx d) (get_reg_idx s) 0L
              | Ir.Alu { op = Ir.Xor; dst = d; src1; src2 = Ir.Reg s; _ } ->
                  assert_src1_eq_dst ~op:Ir.Xor ~dst:d ~src1;
                  encode_raw_word (get_opcode OP_XOR_RR) (get_reg_idx d) (get_reg_idx s) 0L
              | Ir.Alu { op = Ir.Xor; dst = d; src1; src2 = Ir.Imm imm; _ } ->
                  assert_src1_eq_dst ~op:Ir.Xor ~dst:d ~src1;
                  encode_alu_imm OP_XOR_RI OP_XOR_RR d imm
              | Ir.Alu { op = Ir.And; dst = d; src1; src2 = Ir.Reg s; _ } ->
                  assert_src1_eq_dst ~op:Ir.And ~dst:d ~src1;
                  encode_raw_word (get_opcode OP_AND_RR) (get_reg_idx d) (get_reg_idx s) 0L
              | Ir.Alu { op = Ir.And; dst = d; src1; src2 = Ir.Imm imm; _ } ->
                  assert_src1_eq_dst ~op:Ir.And ~dst:d ~src1;
                  encode_alu_imm OP_AND_RI OP_AND_RR d imm
              | Ir.Alu { op = Ir.Or; dst = d; src1; src2 = Ir.Reg s; _ } ->
                  assert_src1_eq_dst ~op:Ir.Or ~dst:d ~src1;
                  encode_raw_word (get_opcode OP_OR_RR) (get_reg_idx d) (get_reg_idx s) 0L
              | Ir.Alu { op = Ir.Or; dst = d; src1; src2 = Ir.Imm imm; _ } ->
                  assert_src1_eq_dst ~op:Ir.Or ~dst:d ~src1;
                  encode_alu_imm OP_OR_RI OP_OR_RR d imm
              | Ir.Alu { op = Ir.Rol; dst = d; src1; src2 = Ir.Imm imm; _ } ->
                  assert_src1_eq_dst ~op:Ir.Rol ~dst:d ~src1;
                  encode_raw_word (get_opcode OP_ROL_RI) (get_reg_idx d) 0 imm
              | Ir.Alu { op = Ir.Rol; dst = d; src1; src2 = Ir.Reg s; _ } ->
                  assert_src1_eq_dst ~op:Ir.Rol ~dst:d ~src1;
                  encode_raw_word (get_opcode OP_ROL_RR) (get_reg_idx d) (get_reg_idx s) 0L
              | Ir.Alu { op = Ir.Ror; dst = d; src1; src2 = Ir.Imm imm; _ } ->
                  assert_src1_eq_dst ~op:Ir.Ror ~dst:d ~src1;
                  encode_raw_word (get_opcode OP_ROR_RI) (get_reg_idx d) 0 imm
              | Ir.Alu { op = Ir.Ror; dst = d; src1; src2 = Ir.Reg s; _ } ->
                  assert_src1_eq_dst ~op:Ir.Ror ~dst:d ~src1;
                  encode_raw_word (get_opcode OP_ROR_RR) (get_reg_idx d) (get_reg_idx s) 0L
              | Ir.Alu { op = Ir.Shl; dst = d; src1; src2 = Ir.Imm imm; _ } ->
                  assert_src1_eq_dst ~op:Ir.Shl ~dst:d ~src1;
                  encode_raw_word (get_opcode OP_SHL_RI) (get_reg_idx d) 0 imm
              | Ir.Alu { op = Ir.Shl; dst = d; src1; src2 = Ir.Reg s; _ } ->
                  assert_src1_eq_dst ~op:Ir.Shl ~dst:d ~src1;
                  encode_raw_word (get_opcode OP_SHL_RR) (get_reg_idx d) (get_reg_idx s) 0L
              | Ir.Alu { op = Ir.Shr; dst = d; src1; src2 = Ir.Imm imm; _ } ->
                  assert_src1_eq_dst ~op:Ir.Shr ~dst:d ~src1;
                  encode_raw_word (get_opcode OP_SHR_RI) (get_reg_idx d) 0 imm
              | Ir.Alu { op = Ir.Shr; dst = d; src1; src2 = Ir.Reg s; _ } ->
                  assert_src1_eq_dst ~op:Ir.Shr ~dst:d ~src1;
                  encode_raw_word (get_opcode OP_SHR_RR) (get_reg_idx d) (get_reg_idx s) 0L
              | Ir.Alu { op = Ir.Sar; dst = d; src1; src2 = Ir.Imm imm; _ } ->
                  assert_src1_eq_dst ~op:Ir.Sar ~dst:d ~src1;
                  encode_raw_word (get_opcode OP_SAR_RI) (get_reg_idx d) 0 imm
              | Ir.Alu { op = Ir.Sar; dst = d; src1; src2 = Ir.Reg s; _ } ->
                  assert_src1_eq_dst ~op:Ir.Sar ~dst:d ~src1;
                  encode_raw_word (get_opcode OP_SAR_RR) (get_reg_idx d) (get_reg_idx s) 0L
               | Ir.Unary { op = Ir.Inc; dst; _ } ->
                   encode_raw_word (get_opcode OP_ADD_RI) (get_reg_idx dst) 0 1L
               | Ir.Unary { op = Ir.Dec; dst; _ } ->
                   encode_raw_word (get_opcode OP_SUB_RI) (get_reg_idx dst) 0 1L
               | Ir.Unary { op = Ir.Neg; dst; _ } ->
                   encode_raw_word (get_opcode OP_NEG_RR) (get_reg_idx dst) 0 0L
               | Ir.Unary { op = Ir.Not; dst; _ } ->
                   encode_raw_word (get_opcode OP_NOT_RR) (get_reg_idx dst) 0 0L
               | Ir.Unary { op = Ir.Bswap; dst; src; _ } ->
                   let bits = Register.width_to_bits (Register.get_width dst) in
                   let s_idx = match src with Ir.Reg s -> get_reg_idx s | _ -> get_reg_idx dst in
                   encode_raw_word (get_opcode OP_BSWAP_RR) (get_reg_idx dst) s_idx (Int64.of_int bits)
               | Ir.Unary { op = Ir.Clz; dst; src; _ } ->
                   let bits = Register.width_to_bits (Register.get_width dst) in
                   let s_idx = match src with Ir.Reg s -> get_reg_idx s | _ -> get_reg_idx dst in
                   encode_raw_word (get_opcode OP_CLZ_RR) (get_reg_idx dst) s_idx (Int64.of_int bits)
               | Ir.Unary { op = Ir.Ctz; dst; src; _ } ->
                   let bits = Register.width_to_bits (Register.get_width dst) in
                   let s_idx = match src with Ir.Reg s -> get_reg_idx s | _ -> get_reg_idx dst in
                   encode_raw_word (get_opcode OP_CTZ_RR) (get_reg_idx dst) s_idx (Int64.of_int bits)
               | Ir.Unary { op = Ir.Popcnt; dst; src; _ } ->
                   let bits = Register.width_to_bits (Register.get_width dst) in
                   let s_idx = match src with Ir.Reg s -> get_reg_idx s | _ -> get_reg_idx dst in
                   encode_raw_word (get_opcode OP_POPCNT_RR) (get_reg_idx dst) s_idx (Int64.of_int bits)
               | Ir.Unary { op = Ir.Rbit; dst; src; _ } ->
                   let bits = Register.width_to_bits (Register.get_width dst) in
                   let s_idx = match src with Ir.Reg s -> get_reg_idx s | _ -> get_reg_idx dst in
                   encode_raw_word (get_opcode OP_RBIT_RR) (get_reg_idx dst) s_idx (Int64.of_int bits)
              | Ir.Cmp { src1 = Ir.Reg d; src2 = Ir.Reg s } ->
                  let bits = Register.width_to_bits (Register.get_width d) in
                  encode_raw_word ~extra_bits:(Int64.of_int bits) (get_opcode OP_CMP_RR) (get_reg_idx d) (get_reg_idx s) 0L
              | Ir.Cmp { src1 = Ir.Reg d; src2 = Ir.Imm imm } ->
                  let bits = Register.width_to_bits (Register.get_width d) in
                  if is_i32 imm then
                    encode_raw_word ~extra_bits:(Int64.of_int bits) (get_opcode OP_CMP_RI) (get_reg_idx d) 0 imm
                  else begin
                    let temp_reg = if d = Register.vx23 then Register.vx22 else Register.vx23 in
                    let low = Int64.logand imm 0xFFFFFFFFL in
                    let high = Int64.shift_right_logical imm 32 in
                    encode_raw_word (get_opcode OP_MOV_RI) (get_reg_idx temp_reg) 0 low;
                    if high <> 0L then
                      encode_raw_word (get_opcode OP_MOV_HIGH) (get_reg_idx temp_reg) 0 high;
                    encode_raw_word ~extra_bits:(Int64.of_int bits) (get_opcode OP_CMP_RR) (get_reg_idx d) (get_reg_idx temp_reg) 0L
                  end
              | Ir.Ccmp { cond; src1 = Ir.Reg d; src2 = Ir.Reg s; nzcv } ->
                  let bits = Register.width_to_bits (Register.get_width d) in
                  let c = cond_to_code cond in
                  let imm = Int64.logor (Int64.of_int c) (Int64.shift_left (Int64.of_int (nzcv land 0xF)) 4) in
                  encode_raw_word ~extra_bits:(Int64.of_int bits) (get_opcode OP_CCMP_RR) (get_reg_idx d) (get_reg_idx s) imm
              | Ir.Ccmp { cond; src1 = Ir.Reg d; src2 = Ir.Imm imm_val; nzcv } ->
                  let bits = Register.width_to_bits (Register.get_width d) in
                  let c = cond_to_code cond in
                  let imm = Int64.logor (Int64.of_int c) (Int64.shift_left (Int64.of_int (nzcv land 0xF)) 4) in
                  let imm = Int64.logor imm (Int64.shift_left (Int64.logand imm_val 0x1FL) 8) in
                  encode_raw_word ~extra_bits:(Int64.of_int bits) (get_opcode OP_CCMP_RI) (get_reg_idx d) 0 imm
              | Ir.Ccmn { cond; src1 = Ir.Reg d; src2 = Ir.Reg s; nzcv } ->
                  let bits = Register.width_to_bits (Register.get_width d) in
                  let c = cond_to_code cond in
                  let imm = Int64.logor (Int64.of_int c) (Int64.shift_left (Int64.of_int (nzcv land 0xF)) 4) in
                  encode_raw_word ~extra_bits:(Int64.of_int bits) (get_opcode OP_CCMN_RR) (get_reg_idx d) (get_reg_idx s) imm
              | Ir.Ccmn { cond; src1 = Ir.Reg d; src2 = Ir.Imm imm_val; nzcv } ->
                  let bits = Register.width_to_bits (Register.get_width d) in
                  let c = cond_to_code cond in
                  let imm = Int64.logor (Int64.of_int c) (Int64.shift_left (Int64.of_int (nzcv land 0xF)) 4) in
                  let imm = Int64.logor imm (Int64.shift_left (Int64.logand imm_val 0x1FL) 8) in
                  encode_raw_word ~extra_bits:(Int64.of_int bits) (get_opcode OP_CCMN_RI) (get_reg_idx d) 0 imm
              | Ir.Push (Ir.Reg d) ->
                  encode_raw_word (get_opcode OP_PUSH_R) (get_reg_idx d) 0 0L
              | Ir.Pop (Ir.Reg d) ->
                  encode_raw_word (get_opcode OP_POP_R) (get_reg_idx d) 0 0L
              | Ir.Jmp (Ir.TargetReg r) ->
                  encode_raw_word (get_opcode OP_IJMP_R) (get_reg_idx r) 0 0L
              | Ir.Jmp target ->
                  encode_raw_word (get_opcode OP_JMP) 0 0 (resolve_target target)
              | Ir.Jcc { cond; target_true; target_false } ->
                  let (cond, target_true, target_false) =
                    if cond = Flags.NP then
                      (Flags.P, target_false, target_true)
                    else
                      (cond, target_true, target_false)
                  in
                  let c = cond_to_code cond in
                  let t_off = resolve_target target_true in
                  let f_off = resolve_target target_false in
                  let base_vip = Int64.logand f_off 0x1FFFFFL in
                  let delta = Int64.logxor (Int64.logand t_off 0x1FFFFFL) base_vip in
                  let salt = Int64.logand (Int64.logxor (Int64.mul (Int64.of_int c) 0x5877L) salt_leetbeef) 0x1FFFFFL in
                  let enc_delta = Int64.logxor delta salt in
                  let imm = Int64.logor (Int64.of_int c) (Int64.shift_left base_vip 4) in
                  let imm = Int64.logor imm (Int64.shift_left enc_delta 25) in
                  encode_raw_word (get_opcode OP_JCC) 0 0 imm
              | Ir.Cmov { cond; dst = Register.Fpr (d, _); src = Ir.Reg (Register.Fpr (s, _)) } ->
                  encode_raw_word (get_opcode OP_FCSEL_VV) (d mod 32) (s mod 32) (Int64.of_int (cond_to_code cond))
              | Ir.Cmov { cond; dst; src = Ir.Reg s } ->
                  encode_raw_word (get_opcode OP_CMOV) (get_reg_idx dst) (get_reg_idx s) (Int64.of_int (cond_to_code cond))
              | Ir.Setcc { cond; dst = Ir.Reg d } ->
                  encode_raw_word (get_opcode OP_SETCC) (get_reg_idx d) 0 (Int64.of_int (cond_to_code cond))
              | Ir.Call (Ir.TargetReg r) ->
                  encode_raw_word (get_opcode OP_ICALL_R) (get_reg_idx r) 0 0L
              | Ir.Call (Ir.BlockId bid) ->
                  encode_raw_word (get_opcode OP_CALL) 0 0 (Int64.of_int (get_block_offset bid))
              | Ir.Call (Ir.TargetImm imm) ->
                  encode_raw_word (get_opcode OP_CALL) 0 0 imm
              | Ir.Call (Ir.Label sym) -> (
                  match Hashtbl.find_opt label_to_block sym with
                  | Some bid ->
                      encode_raw_word (get_opcode OP_CALL) 0 0 (Int64.of_int (get_block_offset bid))
                  | None ->
                      let sym_idx = get_ext_sym_idx sym in
                      encode_raw_word (get_opcode OP_CALL_EXTERN) 0 0 (Int64.of_int sym_idx))
              | Ir.Ret -> encode_raw_word (get_opcode OP_RET) 0 0 0L
              | Ir.Vm_exit -> encode_raw_word (get_opcode OP_EXIT) 0 0 0L
              | Ir.Vm_enter -> encode_raw_word (get_opcode OP_NOP) 0 0 0L
              | Ir.Trap _ -> encode_raw_word (get_opcode OP_EXIT) 0 0 0L
              | Ir.Bridge_to_flow imm -> encode_raw_word (get_opcode OP_BRIDGE_TO_FLOW) 0 0 imm
              | Ir.Bridge_to_math imm -> encode_raw_word (get_opcode OP_BRIDGE_TO_MATH) 0 0 imm
              | Ir.Load_symbol { dst; sym; addend } ->
                  let sym_idx = get_ext_sym_idx sym in
                  encode_raw_word (get_opcode OP_RESOLVE_SYM) (get_reg_idx dst) 0 (Int64.of_int sym_idx);
                  if addend <> 0L then
                    encode_raw_word (get_opcode OP_ADD_RI) (get_reg_idx dst) 0 addend
              | Ir.Fp_binop { op; dst; src1; src2 } ->
                  let op_kind = match op with Fadd -> OP_FADD_DD | Fsub -> OP_FSUB_DD | Fmul -> OP_FMUL_DD | Fdiv -> OP_FDIV_DD | Fsqrt -> OP_FSQRT_D in
                  encode_raw_word (get_opcode op_kind) (dst mod 32) (src1 mod 32) (Int64.of_int (src2 mod 32))
              | Ir.Fp_cmp { src1; src2; is_32 } ->
                  let mode = if is_32 then 1L else 0L in
                  encode_raw_word ~extra_bits:mode (get_opcode OP_FCMP_DD) 0 (src1 mod 32) (Int64.of_int (src2 mod 32))
              | Ir.Fp_ccmp { cond; src1; src2; nzcv; is_32 } ->
                  let mode = if is_32 then 1L else 0L in
                  let c = cond_to_code cond in
                  let imm = Int64.logor (Int64.of_int c)
                    (Int64.logor (Int64.shift_left (Int64.of_int (nzcv land 0xF)) 4)
                                 (Int64.shift_left (Int64.of_int (src2 mod 32)) 8))
                  in
                  encode_raw_word ~extra_bits:mode (get_opcode OP_FCCMP_DD) 0 (src1 mod 32) imm
              | Ir.Fp_conv { op = (Fcvtzs | Fcvtas | Fcvtms | Fcvtns | Fcvtps) as fop; dst; src } ->
                  let s_idx = match src with Register.Fpr (i, _) -> i mod 32 | _ -> get_reg_idx src in
                  let src_is_32 = if Register.get_width src = Register.B32 then 1L else 0L in
                  let rmode = match fop with
                    | Fcvtzs -> 0L
                    | Fcvtas -> 1L
                    | Fcvtms -> 2L
                    | Fcvtns -> 3L
                    | Fcvtps -> 4L
                    | _ -> 0L
                  in
                  let imm = Int64.logor src_is_32 (Int64.shift_left rmode 1) in
                  encode_raw_word (get_opcode OP_FCVTZS) (get_reg_idx dst) s_idx imm
              | Ir.Fp_conv { op = (Fcvtzu | Fcvtau | Fcvtmu | Fcvtnu | Fcvtpu) as fop; dst; src } ->
                  let s_idx = match src with Register.Fpr (i, _) -> i mod 32 | _ -> get_reg_idx src in
                  let src_is_32 = if Register.get_width src = Register.B32 then 1L else 0L in
                  let rmode = match fop with
                    | Fcvtzu -> 0L
                    | Fcvtau -> 1L
                    | Fcvtmu -> 2L
                    | Fcvtnu -> 3L
                    | Fcvtpu -> 4L
                    | _ -> 0L
                  in
                  let imm = Int64.logor src_is_32 (Int64.shift_left rmode 1) in
                  encode_raw_word (get_opcode OP_FCVTZU) (get_reg_idx dst) s_idx imm
              | Ir.Fp_conv { op = Scvtf; dst; src } ->
                  let d_idx = match dst with Register.Fpr (i, _) -> i mod 32 | _ -> get_reg_idx dst in
                  let src_is_32 = if Register.get_width src = Register.B32 then 1L else 0L in
                  let dst_is_32 = if Register.get_width dst = Register.B32 then 2L else 0L in
                  encode_raw_word (get_opcode OP_SCVTF) d_idx (get_reg_idx src) (Int64.logor src_is_32 dst_is_32)
              | Ir.Fp_conv { op = Ucvtf; dst; src } ->
                  let d_idx = match dst with Register.Fpr (i, _) -> i mod 32 | _ -> get_reg_idx dst in
                  let src_is_32 = if Register.get_width src = Register.B32 then 1L else 0L in
                  let dst_is_32 = if Register.get_width dst = Register.B32 then 2L else 0L in
                  encode_raw_word (get_opcode OP_UCVTF) d_idx (get_reg_idx src) (Int64.logor src_is_32 dst_is_32)
              | Ir.Fp_conv { op = Fcvt; dst; src } ->
                  let d_idx = match dst with Register.Fpr (i, _) -> i mod 32 | _ -> get_reg_idx dst in
                  let s_idx = match src with Register.Fpr (i, _) -> i mod 32 | _ -> get_reg_idx src in
                  let mode = if Register.get_width dst = Register.B32 then 1L else 0L in
                  encode_raw_word (get_opcode OP_FCVT) d_idx s_idx mode
              | Ir.Fjcvtzs { dst; src } ->
                  encode_raw_word (get_opcode OP_FJCVTZS) (get_reg_idx dst) (src mod 32) 0L
              | Ir.Vec_mov { dst; src; bits } ->
                  encode_raw_word (get_opcode OP_VEC_MOV) (vector_index dst) (vector_index src) (Int64.of_int bits)
              | Ir.Vec_splat { dst; src; bits; lane_bits } ->
                  let imm = Int64.logor (Int64.of_int bits) (Int64.shift_left (Int64.of_int lane_bits) 16) in
                  encode_raw_word (get_opcode OP_VEC_SPLAT) (vector_index dst) (get_reg_idx src) imm
              | Ir.Vec_binop { op; elem; dst; src1; src2; bits; lane_bits } ->
                  encode_raw_word (get_opcode OP_VEC_BINOP) (vector_index dst) (vector_index src1)
                    (vector_imm ~src2:(vector_index src2) ~bits ~lane_bits ~elem op)
              | Ir.Vec_sha { op; dst; src1; src2; src3; imm; bits } ->
                  encode_raw_word ~extra_bits:(Int64.of_int (sha_op_code op)) (get_opcode OP_VEC_SHA)
                    (vector_index dst) (vector_index src1)
                    (sha_imm ~src2:(vector_index src2) ~src3:(vector_index src3) ~imm ~bits)
              | Ir.Vec_pclmul { dst; src1; src2; imm; bits } ->
                  (* The immediate field carries the second source register,
                     the eight-bit immediate and the width of the vector. *)
                  let payload =
                    Int64.logor (Int64.of_int (vector_index src2))
                      (Int64.logor (Int64.shift_left (Int64.logand imm 0xFFL) 5)
                         (Int64.shift_left (Int64.of_int bits) 13))
                  in
                  encode_raw_word (get_opcode OP_VEC_PCLMUL) (vector_index dst) (vector_index src1) payload
              | Ir.Vec_aes { op; dst; src1; src2; imm; bits } ->
                  encode_raw_word ~extra_bits:(Int64.of_int (aes_op_code op)) (get_opcode OP_VEC_AES)
                    (vector_index dst) (vector_index src1)
                    (aes_imm ~src2:(vector_index src2) ~imm ~bits)
              | Ir.Vec_shuf2 { dst; src1; src2; imm; bits; lane_bits } ->
                  let payload =
                    Int64.logor (Int64.of_int (vector_index src2))
                      (Int64.logor (Int64.shift_left (Int64.logand imm 0xFFL) 5)
                        (Int64.logor (Int64.shift_left (Int64.of_int bits) 13)
                          (Int64.shift_left (Int64.of_int lane_bits) 23)))
                  in
                  encode_raw_word (get_opcode OP_VEC_SHUF2) (vector_index dst) (vector_index src1) payload
              | Ir.Ptest { src1; src2; bits } ->
                  encode_raw_word (get_opcode OP_PTEST) (vector_index src1) (vector_index src2) (Int64.of_int bits)
              | Ir.Vec_conv { op; dst; src; bits } ->
                  let payload =
                    Int64.logor (Int64.of_int (vec_conv_op_code op))
                      (Int64.shift_left (Int64.of_int bits) 4)
                  in
                  encode_raw_word (get_opcode OP_VEC_CONV) (vector_index dst) (vector_index src) payload
              | Ir.Pinsr { dst; src1; src2; imm; width } ->
                  let s2_idx = match src2 with Ir.Reg r -> get_reg_idx r | _ -> 0 in
                  let w_code = match width with Register.B8 -> 0 | Register.B16 -> 1 | Register.B32 -> 2 | _ -> 3 in
                  let payload =
                    Int64.logor (Int64.of_int (s2_idx land 31))
                      (Int64.logor (Int64.shift_left (Int64.of_int (imm land 15)) 5)
                        (Int64.shift_left (Int64.of_int w_code) 9))
                  in
                  encode_raw_word (get_opcode OP_PINSR) (vector_index dst) (vector_index src1) payload
              | Ir.Pextr { dst; src; imm; width } ->
                  let d_idx = match dst with Ir.Reg r -> get_reg_idx r | _ -> 0 in
                  let w_code = match width with Register.B8 -> 0 | Register.B16 -> 1 | Register.B32 -> 2 | _ -> 3 in
                  let payload =
                    Int64.logor (Int64.of_int (imm land 15))
                      (Int64.shift_left (Int64.of_int w_code) 4)
                  in
                  encode_raw_word (get_opcode OP_PEXTR) d_idx (vector_index src) payload
              | Ir.Read_ssp { dst } ->
                  encode_raw_word (get_opcode OP_READ_SSP) (get_reg_idx dst) 0
                    (if Register.get_width dst = Register.B32 then 32L else 64L)
              | Ir.Inc_ssp { width } ->
                  encode_raw_word (get_opcode OP_INC_SSP) 0 0
                    (if width = Register.B32 then 32L else 64L)
              | Ir.Vec_imm { op; elem; dst; src; imm; bits; lane_bits } ->
                  encode_raw_word (get_opcode OP_VEC_IMM) (vector_index dst) (vector_index src)
                    (vector_imm_val ~imm_val:imm ~bits ~lane_bits ~elem op)
              | Ir.Vec_load { dst; addr; bits } ->
                  let base_idx = match addr.base with Some b -> get_reg_idx b | None -> 0 in
                  encode_raw_word ~extra_bits:(Int64.of_int bits) (get_opcode OP_VEC_LOAD) (vector_index dst) base_idx addr.disp
              | Ir.Vec_store { src; addr; bits } ->
                  let base_idx = match addr.base with Some b -> get_reg_idx b | None -> 0 in
                  encode_raw_word ~extra_bits:(Int64.of_int bits) (get_opcode OP_VEC_STORE) base_idx (vector_index src) addr.disp
              | Ir.Vec_clear_upper reg ->
                  encode_raw_word (get_opcode OP_VEC_CLEAR_UPPER) (vector_index reg) 0 0L
              | Ir.Vec_zero_upper ->
                  encode_raw_word (get_opcode OP_VEC_ZERO_UPPER) 0 0 0L
              | Ir.Cpuid ->
                  encode_raw_word (get_opcode OP_CPUID) 0 0 0L
              | Ir.Vec_ext { dst; src1; src2; imm; bits } ->
                  let imm_payload =
                    Int64.logor (Int64.of_int (src2 land 31))
                      (Int64.logor (Int64.shift_left (Int64.of_int (imm land 15)) 5)
                         (Int64.shift_left (Int64.of_int bits) 9))
                  in
                  encode_raw_word (get_opcode OP_VEC_EXT) (vector_index dst) (vector_index src1) imm_payload
              | Ir.Pmovmskb { dst; src; bits; lane_bits } ->
                  let imm = Int64.logor (Int64.of_int bits) (Int64.shift_left (Int64.of_int lane_bits) 16) in
                  encode_raw_word (get_opcode OP_PMOVMSKB) (get_reg_idx dst) (vector_index src) imm
              | Ir.Atomic_mem { op; dst; addr; src; imm } -> (
                  match op with
                  | AtLoad ->
                      encode_raw_word (get_opcode OP_ATOMIC_LOAD) (get_reg_idx dst) (get_reg_idx addr) imm
                  | AtStore ->
                      encode_raw_word (get_opcode OP_ATOMIC_STORE) (get_reg_idx addr) (get_reg_idx src) imm
                  | AtCas ->
                      encode_raw_word (get_opcode OP_ATOMIC_CAS) (get_reg_idx addr) (get_reg_idx src) imm
                  | AtAdd ->
                      let w = if Register.get_width dst = Register.B64 then Register.get_width src else Register.get_width dst in
                      let wcode = match w with Register.B8 -> 3L | Register.B16 -> 2L | Register.B32 -> 1L | _ -> 0L in
                      if get_reg_idx dst = get_reg_idx src then
                        encode_raw_word ~extra_bits:wcode (get_opcode OP_ATOMIC_ADD) (get_reg_idx addr) (get_reg_idx src) imm
                      else begin
                        let tmp =
                          if get_reg_idx addr = get_reg_idx Register.vtmp0 || get_reg_idx src = get_reg_idx Register.vtmp0 then
                            Register.vtmp1
                          else Register.vtmp0
                        in
                        encode_raw_word (get_opcode OP_MOV_RR) (get_reg_idx tmp) (get_reg_idx src) 0L;
                        encode_raw_word ~extra_bits:wcode (get_opcode OP_ATOMIC_ADD) (get_reg_idx addr) (get_reg_idx tmp) imm;
                        if not (is_zero_register dst) then
                          encode_raw_word (get_opcode OP_MOV_RR) (get_reg_idx dst) (get_reg_idx tmp) 0L
                      end
                  | AtSwp ->
                      let w = if Register.get_width dst = Register.B64 then Register.get_width src else Register.get_width dst in
                      let wcode = match w with Register.B8 -> 3L | Register.B16 -> 2L | Register.B32 -> 1L | _ -> 0L in
                      if get_reg_idx dst = get_reg_idx src then
                        encode_raw_word ~extra_bits:wcode (get_opcode OP_ATOMIC_SWP) (get_reg_idx addr) (get_reg_idx src) imm
                      else begin
                        let tmp =
                          if get_reg_idx addr = get_reg_idx Register.vtmp0 || get_reg_idx src = get_reg_idx Register.vtmp0 then
                            Register.vtmp1
                          else Register.vtmp0
                        in
                        encode_raw_word (get_opcode OP_MOV_RR) (get_reg_idx tmp) (get_reg_idx src) 0L;
                        encode_raw_word ~extra_bits:wcode (get_opcode OP_ATOMIC_SWP) (get_reg_idx addr) (get_reg_idx tmp) imm;
                        if not (is_zero_register dst) then
                          encode_raw_word (get_opcode OP_MOV_RR) (get_reg_idx dst) (get_reg_idx tmp) 0L
                      end)
              | Ir.Fence _ ->
                  encode_raw_word (get_opcode OP_FENCE) 0 0 0L
              | Ir.Get_flags d ->
                  encode_raw_word (get_opcode OP_GET_FLAGS_R) (get_reg_idx d) 0 0L
              | Ir.Set_flags (Ir.Reg s) ->
                  encode_raw_word (get_opcode OP_SET_FLAGS_R) 0 (get_reg_idx s) 0L
              | Ir.Set_flags (Ir.Imm imm) ->
                  let tmp = Register.vtmp0 in
                  encode_raw_word (get_opcode OP_MOV_RI) (get_reg_idx tmp) 0 imm;
                  encode_raw_word (get_opcode OP_SET_FLAGS_R) 0 (get_reg_idx tmp) 0L
              | Ir.Set_flags (Ir.Mem m) ->
                  let tmp = Register.vtmp0 in
                  let base_idx = match m.base with Some b -> get_reg_idx b | None -> 0 in
                  encode_raw_word (get_opcode OP_LOAD_64) (get_reg_idx tmp) base_idx m.disp;
                  encode_raw_word (get_opcode OP_SET_FLAGS_R) 0 (get_reg_idx tmp) 0L
              | Ir.Fpu f -> (
                  match f with
                  | FpPush_st idx ->
                      encode_raw_word (get_opcode OP_FPU_PUSH_ST) 0 0 (Int64.of_int idx)
                  | FpPush_mem m ->
                      let base_idx = match m.base with Some b -> get_reg_idx b | None -> 0 in
                      let is_32 = if m.width = Register.B32 then 1L else 0L in
                      encode_raw_word ~extra_bits:is_32 (get_opcode OP_FPU_PUSH_MEM) 0 base_idx m.disp
                  | FpPush_int m ->
                      let base_idx = match m.base with Some b -> get_reg_idx b | None -> 0 in
                      let wcode = match m.width with Register.B16 -> 1L | Register.B32 -> 2L | _ -> 3L in
                      encode_raw_word ~extra_bits:wcode (get_opcode OP_FPU_PUSH_INT) 0 base_idx m.disp
                  | FpStore_st { idx; pop } ->
                      let pop_bit = if pop then 1L else 0L in
                      encode_raw_word ~extra_bits:pop_bit (get_opcode OP_FPU_STORE_ST) 0 0 (Int64.of_int idx)
                  | FpStore_mem { addr; pop } ->
                      let base_idx = match addr.base with Some b -> get_reg_idx b | None -> 0 in
                      let pop_bit = if pop then 4L else 0L in
                      let w_bit = if addr.width = Register.B32 then 1L else 0L in
                      encode_raw_word ~extra_bits:(Int64.logor pop_bit w_bit) (get_opcode OP_FPU_STORE_MEM) 0 base_idx addr.disp
                  | FpStore_int { addr; pop } ->
                      let base_idx = match addr.base with Some b -> get_reg_idx b | None -> 0 in
                      let pop_bit = if pop then 4L else 0L in
                      let wcode = match addr.width with Register.B16 -> 1L | Register.B32 -> 2L | _ -> 3L in
                      encode_raw_word ~extra_bits:(Int64.logor pop_bit wcode) (get_opcode OP_FPU_STORE_INT) 0 base_idx addr.disp
                  | FpBinop { op; dst; src; pop } ->
                      let op_code = match op with FpAdd -> 0L | FpSub -> 1L | FpSubR -> 2L | FpMul -> 3L | FpDiv -> 4L | FpDivR -> 5L in
                      let pop_bit = if pop then 1L else 0L in
                      let flags = Int64.logor (Int64.shift_left op_code 1) pop_bit in
                      encode_raw_word ~extra_bits:flags (get_opcode OP_FPU_BINOP) dst src 0L
                  | FpBinop_mem { op; src } ->
                      let base_idx = match src.base with Some b -> get_reg_idx b | None -> 0 in
                      let op_code = match op with FpAdd -> 0L | FpSub -> 1L | FpSubR -> 2L | FpMul -> 3L | FpDiv -> 4L | FpDivR -> 5L in
                      let is_32 = if src.width = Register.B32 then 1L else 0L in
                      let flags = Int64.logor (Int64.shift_left op_code 1) is_32 in
                      encode_raw_word ~extra_bits:flags (get_opcode OP_FPU_BINOP_MEM) 0 base_idx src.disp
                  | FpCompare { idx; pop_count } ->
                      encode_raw_word ~extra_bits:(Int64.of_int pop_count) (get_opcode OP_FPU_COMPARE) 0 0 (Int64.of_int idx)
                  | FpCompare_i { idx; pop } ->
                      let pop_bit = if pop then 1L else 0L in
                      encode_raw_word ~extra_bits:pop_bit (get_opcode OP_FPU_COMPARE_I) 0 0 (Int64.of_int idx)
                  | FpCompare_mem { src; pop } ->
                      let base_idx = match src.base with Some b -> get_reg_idx b | None -> 0 in
                      let pop_bit = if pop then 4L else 0L in
                      let is_32 = if src.width = Register.B32 then 1L else 0L in
                      encode_raw_word ~extra_bits:(Int64.logor pop_bit is_32) (get_opcode OP_FPU_COMPARE_MEM) 0 base_idx src.disp
                  | FpUnary op ->
                      let op_code = match op with FpChs -> 0L | FpAbs -> 1L | FpSqrt -> 2L in
                      encode_raw_word (get_opcode OP_FPU_UNARY) 0 0 op_code
                  | FpConst c ->
                      let c_code = match c with
                        | FpLd0 -> 0L | FpLd1 -> 1L | FpLdPi -> 2L | FpLdL2e -> 3L | FpLdL2t -> 4L | FpLdLg2 -> 5L | FpLdLn2 -> 6L
                      in
                      encode_raw_word (get_opcode OP_FPU_CONST) 0 0 c_code
                  | FpTrans t ->
                      let t_code = match t with
                        | FpSin -> 0L | FpCos -> 1L | FpSinCos -> 2L | FpTan -> 3L | FpATan -> 4L | FpYl2x -> 5L | FpYl2xp1 -> 6L | Fp2xm1 -> 7L
                      in
                      encode_raw_word (get_opcode OP_FPU_TRANS) 0 0 t_code
                  | FpStatus_to_ax ->
                      encode_raw_word (get_opcode OP_FPU_STATUS_TO_AX) 0 0 0L)
              | other ->
                  failwith (Printf.sprintf "vm_emitter: unsupported instruction: %s" (Ir.instr_to_string other))))
        ops)
    sorted_blocks;

    let final_bytecode = List.rev !bytecode in
    let block_spans =
      List.map
        (fun (b : Ir.basic_block) ->
          let off = get_block_offset b.id in
          let fused = Hashtbl.find block_fused_ops b.id in
          let len = List.fold_left (fun acc op -> acc + words_of_fused op) 0 fused in
          (off, len))
        sorted_blocks
    in
    (final_bytecode, block_spans, target_func)
  in

  let salt_of_name name =
    let clean = if String.starts_with ~prefix:"_" name then String.sub name 1 (String.length name - 1) else name in
    if clean = "" || clean = "main" || clean = "target_func" || List.length funcs <= 1 then 0
    else
      let h = Hashtbl.hash clean in
      (h land 0xFE) lor 1
  in
  let compiled = List.map (fun (name, f) ->
    let macro_salt = salt_of_name name in
    let (bc, spans, tf) = compile_one_func ~macro_salt f in
    let h = compute_bytecode_hash key_seed bc in
    (name, bc, h, spans, tf)
  ) funcs in

  let all_bytecodes = List.map (fun (name, bc, _, _, _) -> (name, bc)) compiled in
  let all_hashes = List.map (fun (_, _, h, _, _) -> h) compiled in
  let all_spans = List.concat (List.map (fun (_, _, _, spans, _) -> spans) compiled) in

  let primary_bc = match all_bytecodes with (_, bc) :: _ -> bc | [] -> [] in
  let primary_hash = match all_hashes with h :: _ -> h | [] -> 0L in
  let primary_func = match compiled with (_, _, _, _, tf) :: _ -> tf | [] -> failwith "compile_and_package_multi: empty funcs" in

  let cpp_src = Vm_runtime_emitter.emit_cpp_threaded_header
    ~rng
    ~key_seed
    ~reg_perm
    ~expected_hash:primary_hash
    ?expected_hashes:(if List.length all_hashes > 1 then Some all_hashes else None)
    ?runtime_profile
    ?config
    ~external_symbols:!external_symbols
    ~constants
    ~block_spans:all_spans
    ?gpu_matrix:gpu_sub_matrix
    opcode_to_handler
  in
  let runner_src = Vm_runtime_emitter.emit_runner_cpp ~key_seed:(Int64.of_int32 key_seed) ~reg_perm primary_bc in

  let decoy_count =
    Array.fold_left (fun acc h -> if String.starts_with ~prefix:"H_DECOY" h then acc + 1 else acc) 0 opcode_to_handler
  in
  let mba_nodes = if enable_mba then mba_depth * 15 else 0 in
  let metrics = Metrics.calculate_metrics
    ~bytecode:primary_bc
    ~func:primary_func
    ~decoy_count
    ~total_handlers:256
    ~mba_nodes
  in

  {
    bytecode = primary_bc;
    bytecodes = all_bytecodes;
    cpp_runtime_source = cpp_src;
    runner_source = runner_src;
    metrics;
  }

let compile_and_package
    ~rng
    ?runtime_profile
    ?config
    ?(enable_cff = false)
    ?(enable_mba = false)
    ?(enable_junk = true)
    ?(mba_depth = 2)
    ?(constants = [])
    (func : Ir.func) =
  compile_and_package_multi
    ~rng
    ?runtime_profile
    ?config
    ~enable_cff
    ~enable_mba
    ~enable_junk
    ~mba_depth
    ~constants
    [ (func.name, func) ]
