open Vm_ir
open Vm_transform

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

  let (enable_cff, enable_mba, enable_junk, mba_depth, mba_engine) =
    match config with
    | Some (c : Protection_config.t) ->
        (c.cff.enabled, c.mba.enabled, c.vm_runtime.enable_junk_instructions, c.mba.depth, c.mba.engine)
    | None ->
        (enable_cff, enable_mba, enable_junk, mba_depth, `Egraph)
  in

  (* Generate randomized bijective register permutation π ∈ S_32 *)
  let reg_perm = Array.init 32 (fun i -> i) in
  shuffle_array rng reg_perm;
  let get_reg_idx r = reg_perm.(reg_to_index r) in

  (* Set up opcode bijection and junk decoys with 100% table saturation *)
  let slots = Array.init 256 (fun i -> i) in
  shuffle_array rng slots;
  let kind_to_code = Hashtbl.create 32 in
  let opcode_to_handler = Array.make 256 "H_DECOY" in
  List.iteri
    (fun i kind ->
      let code = slots.(i) in
      Hashtbl.replace kind_to_code kind code;
      opcode_to_handler.(code) <- op_kind_to_handler_name kind)
    all_op_kinds;

  (* Saturate all remaining opcode slots with polymorphic decoy handlers *)
  for i = List.length all_op_kinds to 255 do
    let code = slots.(i) in
    let decoy_idx = i mod 16 in
    opcode_to_handler.(code) <- Printf.sprintf "H_DECOY_%d" decoy_idx
  done;

  let get_opcode kind =
    Hashtbl.find kind_to_code kind
  in

  let enable_super_ops =
    match config with
    | Some (c : Protection_config.t) -> c.vm_runtime.enable_super_operators
    | None -> true
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
    let h = ref (Int64.logxor 0x811C9DC5C9DC5119L (Int64.logand (Int64.of_int32 seed) 0xFFFFFFFFL)) in
    List.iteri
      (fun i w ->
        let mixed = Int64.logxor !h w in
        let mul = Int64.mul mixed 0x100000001B3L in
        h := Int64.add mul (Int64.of_int i))
      bc;
    !h
  in

  let compile_one_func (func : Ir.func) =
    let target_func =
      if enable_cff then
        let cff_opts =
          match config with
          | Some c ->
              {
                Cff.inject_opaque_predicates = c.cff.inject_opaque_predicates;
                obfuscate_states = c.cff.obfuscate_states;
              }
          | None -> Cff.default_cff_options
        in
        match Cff.flatten_func ~options:cff_opts ~rng func with
        | Ok f -> f
        | Error _ -> func
      else func
    in

    (* Linearize blocks and calculate block start offsets in bytecode with Super-Operator fusion and Junk insertion *)
    let entry_block = Hashtbl.find target_func.cfg.blocks target_func.cfg.entry_id in
    let other_blocks =
      Hashtbl.fold
        (fun id b acc -> if id <> target_func.cfg.entry_id then b :: acc else acc)
        target_func.cfg.blocks []
    in
    let sorted_other = List.sort (fun (a : Ir.basic_block) (b : Ir.basic_block) -> Int.compare a.id b.id) other_blocks in
    let sorted_blocks = entry_block :: sorted_other in

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
        let instrs =
          if enable_mba then
            List.concat_map
              (function
                | Ir.Alu { op; dst; src1; src2; _ } -> (
                    try
                      match mba_engine with
                      | `Egraph ->
                          let eg_cfg = { Mba_engine.Egraph.default_op_config with iter_limit = max 1 (min 4 mba_depth) } in
                          Mba_engine.Egraph.obfuscate_alu ~config:eg_cfg ~rng:brng ~dst ~src1 ~src2 op
                      | `Poly   -> Mba_engine.Mba.obfuscate_alu ~rng:brng ~depth:mba_depth ~dst ~src1 ~src2 op
                      | `Ncfg   -> Mba_engine.Egraph.obfuscate_alu ~rng:brng ~dst ~src1 ~src2 op
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
        let instrs = if enable_junk then inject_junk_instructions ~rng:brng instrs else instrs in
        let fused  = if enable_super_ops then fuse_block_instructions instrs
                     else List.map (fun i -> Raw i) instrs in
        results.(i) <- (b.id, fused))
  );

  let block_fused_ops = Hashtbl.create n_blocks in
  Array.iter (fun (id, fused) -> Hashtbl.replace block_fused_ops id fused) results;

  let words_of_fused = function
    | Raw (Ir.Mov { src = Ir.Imm imm; _ }) when Int64.shift_right_logical imm 32 <> 0L -> 2
    | Raw (Ir.Load_symbol { addend; _ }) when addend <> 0L -> 2
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
    let w = ref 0L in
    w := Int64.logor !w (Int64.of_int op);
    w := Int64.logor !w (Int64.shift_left (Int64.of_int dst) 8);
    w := Int64.logor !w (Int64.shift_left (Int64.of_int src) 13);
    let imm_masked = Int64.logand imm 0x3FFFFFFFFFFL in
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
      let (dop, ddst, _, dimm) = Rolling_key.decode_fields !w in
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
  in
  let vector_elem_code = function
    | Ir.VInt -> 0 | Ir.VF32 -> 1 | Ir.VF64 -> 2
  in
  let vector_imm ~src2 ~bits ~lane_bits ~elem op =
    let w = Int64.of_int src2 in
    let w = Int64.logor w (Int64.shift_left (Int64.of_int bits) 5) in
    let w = Int64.logor w (Int64.shift_left (Int64.of_int lane_bits) 15) in
    let w = Int64.logor w (Int64.shift_left (Int64.of_int (vector_op_code op)) 23) in
    Int64.logor w (Int64.shift_left (Int64.of_int (vector_elem_code elem)) 28)
  in
  let vector_imm_val ~imm_val ~bits ~lane_bits ~elem op =
    let w = Int64.logand imm_val 0xFFL in
    let w = Int64.logor w (Int64.shift_left (Int64.of_int bits) 8) in
    let w = Int64.logor w (Int64.shift_left (Int64.of_int lane_bits) 18) in
    let w = Int64.logor w (Int64.shift_left (Int64.of_int (vector_op_code op)) 26) in
    Int64.logor w (Int64.shift_left (Int64.of_int (vector_elem_code elem)) 31)
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
          | Fused_Cmp_Cmov { cmp_dst; cmp_imm; cond; cmov_dst; cmov_src } ->
              let bits = Register.width_to_bits (Register.get_width cmp_dst) in
              let c = cond_to_code cond in
              let extra = Int64.logor (Int64.of_int c) (Int64.shift_left (Int64.of_int bits) 4) in
              encode_raw_word ~extra_bits:extra
                (get_opcode OP_FUSED_CMP_CMOV) (get_reg_idx cmov_dst) (get_reg_idx cmov_src) cmp_imm
          | Raw instr -> (
              match instr with
              | Ir.Nop -> encode_raw_word (get_opcode OP_NOP) 0 0 0L
              | Ir.Mov { dst = Ir.Reg (Register.Fpr (d, _)); src = Ir.Reg (Register.Fpr (s, _)) } ->
                  encode_raw_word (get_opcode OP_VEC_MOV) (d mod 32) (s mod 32) 64L
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
              | Ir.Mov { dst = Ir.Reg (Register.Fpr (d, _)); src = Ir.Mem m } ->
                  let base_idx = match m.base with Some b -> get_reg_idx b | None -> 0 in
                  encode_raw_word ~extra_bits:64L (get_opcode OP_VEC_LOAD) (d mod 32) base_idx m.disp
              | Ir.Mov { dst = Ir.Mem m; src = Ir.Reg (Register.Fpr (s, _)) } ->
                  let base_idx = match m.base with Some b -> get_reg_idx b | None -> 0 in
                  encode_raw_word ~extra_bits:64L (get_opcode OP_VEC_STORE) base_idx (s mod 32) m.disp
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
                  let temp_reg = Register.vtmp0 in
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
                  encode_raw_word (get_opcode OP_ADD_RI) (get_reg_idx d) 0 imm
              | Ir.Alu { op = Ir.Adc; dst = d; src1; src2 = Ir.Reg s; _ } ->
                  assert_src1_eq_dst ~op:Ir.Adc ~dst:d ~src1;
                  encode_raw_word (get_opcode OP_ADC_RR) (get_reg_idx d) (get_reg_idx s) 0L
              | Ir.Alu { op = Ir.Adc; dst = d; src1; src2 = Ir.Imm imm; _ } ->
                  assert_src1_eq_dst ~op:Ir.Adc ~dst:d ~src1;
                  encode_raw_word (get_opcode OP_ADC_RI) (get_reg_idx d) 0 imm
              | Ir.Alu { op = Ir.Sub; dst = d; src1; src2 = Ir.Reg s; _ } ->
                  assert_src1_eq_dst ~op:Ir.Sub ~dst:d ~src1;
                  encode_raw_word (get_opcode OP_SUB_RR) (get_reg_idx d) (get_reg_idx s) 0L
              | Ir.Alu { op = Ir.Sub; dst = d; src1; src2 = Ir.Imm imm; _ } ->
                  assert_src1_eq_dst ~op:Ir.Sub ~dst:d ~src1;
                  encode_raw_word (get_opcode OP_SUB_RI) (get_reg_idx d) 0 imm
              | Ir.Alu { op = Ir.Sbb; dst = d; src1; src2 = Ir.Reg s; _ } ->
                  assert_src1_eq_dst ~op:Ir.Sbb ~dst:d ~src1;
                  encode_raw_word (get_opcode OP_SBB_RR) (get_reg_idx d) (get_reg_idx s) 0L
              | Ir.Alu { op = Ir.Sbb; dst = d; src1; src2 = Ir.Imm imm; _ } ->
                  assert_src1_eq_dst ~op:Ir.Sbb ~dst:d ~src1;
                  encode_raw_word (get_opcode OP_SBB_RI) (get_reg_idx d) 0 imm
              | Ir.Alu { op = (Ir.Mul | Ir.Imul); dst = d; src1; src2 = Ir.Reg s; _ } ->
                  assert_src1_eq_dst ~op:Ir.Imul ~dst:d ~src1;
                  encode_raw_word (get_opcode OP_IMUL_RR) (get_reg_idx d) (get_reg_idx s) 0L
              | Ir.Alu { op = (Ir.Mul | Ir.Imul); dst = d; src1; src2 = Ir.Imm imm; _ } ->
                  assert_src1_eq_dst ~op:Ir.Imul ~dst:d ~src1;
                  encode_raw_word (get_opcode OP_IMUL_RI) (get_reg_idx d) 0 imm
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
                  encode_raw_word (get_opcode OP_XOR_RI) (get_reg_idx d) 0 imm
              | Ir.Alu { op = Ir.And; dst = d; src1; src2 = Ir.Reg s; _ } ->
                  assert_src1_eq_dst ~op:Ir.And ~dst:d ~src1;
                  encode_raw_word (get_opcode OP_AND_RR) (get_reg_idx d) (get_reg_idx s) 0L
              | Ir.Alu { op = Ir.And; dst = d; src1; src2 = Ir.Imm imm; _ } ->
                  assert_src1_eq_dst ~op:Ir.And ~dst:d ~src1;
                  encode_raw_word (get_opcode OP_AND_RI) (get_reg_idx d) 0 imm
              | Ir.Alu { op = Ir.Or; dst = d; src1; src2 = Ir.Reg s; _ } ->
                  assert_src1_eq_dst ~op:Ir.Or ~dst:d ~src1;
                  encode_raw_word (get_opcode OP_OR_RR) (get_reg_idx d) (get_reg_idx s) 0L
              | Ir.Alu { op = Ir.Or; dst = d; src1; src2 = Ir.Imm imm; _ } ->
                  assert_src1_eq_dst ~op:Ir.Or ~dst:d ~src1;
                  encode_raw_word (get_opcode OP_OR_RI) (get_reg_idx d) 0 imm
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
                  encode_raw_word ~extra_bits:(Int64.of_int bits) (get_opcode OP_CMP_RI) (get_reg_idx d) 0 imm
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
                  let c = cond_to_code cond in
                  let t_off = resolve_target target_true in
                  let f_off = resolve_target target_false in
                  let imm = Int64.logor (Int64.of_int c) (Int64.shift_left (Int64.logand t_off 0x1FFFFFL) 4) in
                  let imm = Int64.logor imm (Int64.shift_left (Int64.logand f_off 0x1FFFFFL) 25) in
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
              | Ir.Fp_cmp { src1; src2 } ->
                  encode_raw_word (get_opcode OP_FCMP_DD) 0 (src1 mod 32) (Int64.of_int (src2 mod 32))
              | Ir.Fp_conv { op = Fcvtzs; dst; src } ->
                  let s_idx = match src with Register.Fpr (i, _) -> i mod 32 | _ -> get_reg_idx src in
                  encode_raw_word (get_opcode OP_FCVTZS) (get_reg_idx dst) s_idx 0L
              | Ir.Fp_conv { op = Fcvtzu; dst; src } ->
                  let s_idx = match src with Register.Fpr (i, _) -> i mod 32 | _ -> get_reg_idx src in
                  encode_raw_word (get_opcode OP_FCVTZU) (get_reg_idx dst) s_idx 0L
              | Ir.Fp_conv { op = Scvtf; dst; src } ->
                  let d_idx = match dst with Register.Fpr (i, _) -> i mod 32 | _ -> get_reg_idx dst in
                  encode_raw_word (get_opcode OP_SCVTF) d_idx (get_reg_idx src) 0L
              | Ir.Fp_conv { op = Ucvtf; dst; src } ->
                  let d_idx = match dst with Register.Fpr (i, _) -> i mod 32 | _ -> get_reg_idx dst in
                  encode_raw_word (get_opcode OP_UCVTF) d_idx (get_reg_idx src) 0L
              | Ir.Fp_conv { op = Fcvt; dst; src } ->
                  let d_idx = match dst with Register.Fpr (i, _) -> i mod 32 | _ -> get_reg_idx dst in
                  let s_idx = match src with Register.Fpr (i, _) -> i mod 32 | _ -> get_reg_idx src in
                  encode_raw_word (get_opcode OP_FCVT) d_idx s_idx 0L
              | Ir.Vec_mov { dst; src; bits } ->
                  encode_raw_word (get_opcode OP_VEC_MOV) (vector_index dst) (vector_index src) (Int64.of_int bits)
              | Ir.Vec_splat { dst; src; bits; lane_bits } ->
                  let imm = Int64.logor (Int64.of_int bits) (Int64.shift_left (Int64.of_int lane_bits) 16) in
                  encode_raw_word (get_opcode OP_VEC_SPLAT) (vector_index dst) (get_reg_idx src) imm
              | Ir.Vec_binop { op; elem; dst; src1; src2; bits; lane_bits } ->
                  encode_raw_word (get_opcode OP_VEC_BINOP) (vector_index dst) (vector_index src1)
                    (vector_imm ~src2:(vector_index src2) ~bits ~lane_bits ~elem op)
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
              | Ir.Vec_ext { dst; src1; src2; imm; bits } ->
                  let imm_payload =
                    Int64.logor (Int64.of_int (src2 land 31))
                      (Int64.logor (Int64.shift_left (Int64.of_int (imm land 15)) 5)
                         (Int64.shift_left (Int64.of_int bits) 9))
                  in
                  encode_raw_word (get_opcode OP_VEC_EXT) (vector_index dst) (vector_index src1) imm_payload
              | Ir.Pmovmskb { dst; src; bits } ->
                  encode_raw_word (get_opcode OP_PMOVMSKB) (get_reg_idx dst) (vector_index src) (Int64.of_int bits)
              | Ir.Atomic_mem { op; dst; addr; src; imm } -> (
                  match op with
                  | AtLoad ->
                      encode_raw_word (get_opcode OP_ATOMIC_LOAD) (get_reg_idx dst) (get_reg_idx addr) imm
                  | AtStore ->
                      encode_raw_word (get_opcode OP_ATOMIC_STORE) (get_reg_idx addr) (get_reg_idx src) imm
                  | AtCas ->
                      encode_raw_word (get_opcode OP_ATOMIC_CAS) (get_reg_idx addr) (get_reg_idx src) imm
                  | AtAdd ->
                      encode_raw_word (get_opcode OP_ATOMIC_ADD) (get_reg_idx addr) (get_reg_idx src) imm
                  | AtSwp ->
                      encode_raw_word (get_opcode OP_ATOMIC_SWP) (get_reg_idx addr) (get_reg_idx src) imm)
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

  let compiled = List.map (fun (name, f) ->
    let (bc, spans, tf) = compile_one_func f in
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

  let decoy_count = 256 - List.length all_op_kinds in
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
