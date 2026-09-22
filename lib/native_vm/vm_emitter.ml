open Vm_ir
open Vm_transform

type vm_package = {
  bytecode : int64 list;
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

let compile_and_package
    ~rng
    ?runtime_profile
    ?config
    ?(enable_cff = false)
    ?(enable_mba = false)
    ?(enable_junk = true)
    ?(mba_depth = 2)
    (func : Ir.func) =

  let (enable_cff, enable_mba, enable_junk, mba_depth, mba_engine) =
    match config with
    | Some (c : Protection_config.t) ->
        (c.cff.enabled, c.mba.enabled, c.vm_runtime.enable_junk_instructions, c.mba.depth, c.mba.engine)
    | None ->
        (enable_cff, enable_mba, enable_junk, mba_depth, `Egraph)
  in

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

  (* Linearize blocks and calculate block start offsets in bytecode with Super-Operator fusion and Junk insertion *)
  let entry_block = Hashtbl.find target_func.cfg.blocks target_func.cfg.entry_id in
  let other_blocks =
    Hashtbl.fold
      (fun id b acc -> if id <> target_func.cfg.entry_id then b :: acc else acc)
      target_func.cfg.blocks []
  in
  let sorted_other = List.sort (fun (a : Ir.basic_block) (b : Ir.basic_block) -> Int.compare a.id b.id) other_blocks in
  let sorted_blocks = entry_block :: sorted_other in

  let block_fused_ops = Hashtbl.create (List.length sorted_blocks) in
  List.iter
    (fun (b : Ir.basic_block) ->
      let instrs =
        if enable_mba then
          List.concat_map
            (function
              | Ir.Alu { op; dst; src1; src2; _ } -> (
                  try
                    match mba_engine with
                    | `Egraph -> Mba_engine.Egraph.obfuscate_alu ~rng ~dst ~src1 ~src2 op
                    | `Poly -> Mba_engine.Mba.obfuscate_alu ~rng ~depth:mba_depth ~dst ~src1 ~src2 op
                    | `Ncfg -> Mba_engine.Egraph.obfuscate_alu ~rng ~dst ~src1 ~src2 op
                  with _ ->
                    [ Ir.Alu { op; dst; src1; src2; set_flags = false } ])
              | other -> [ other ])
            b.instrs
        else b.instrs
      in
      let instrs = if enable_junk then inject_junk_instructions ~rng instrs else instrs in
      let enable_super_ops =
        match config with
        | Some (c : Protection_config.t) -> c.vm_runtime.enable_super_operators
        | None -> true
      in
      let fused = if enable_super_ops then fuse_block_instructions instrs else List.map (fun i -> Raw i) instrs in
      Hashtbl.replace block_fused_ops b.id fused)
    sorted_blocks;

  let words_of_fused = function
    | Raw (Ir.Mov { src = Ir.Imm imm; _ }) when Int64.shift_right_logical imm 32 <> 0L -> 2
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

  let key_seed = Random.State.int32 rng Int32.max_int in

  let cur_idx = ref 0 in
  let bytecode = ref [] in
  (* Anti-Pushan block-chained rolling key: OCaml mirror of the C++ keystream.
     [cur_key] tracks ctx.running_key word by word; it stays 0L when the feature
     is disabled, making the mask byte-identical to the legacy positional PRF. *)
  let enable_rolling = Protection_config.rolling_key_enabled config in
  let cur_key = ref 0L in
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
    let mask = Int64.logxor k_pos !cur_key in
    incr cur_idx;
    let masked_w = Int64.logxor !w mask in
    if enable_rolling then begin
      (* Advance exactly like FETCH_NEXT does: op is the randomized opcode byte,
         imm is re-read from the packed word (32-bit sign-extended window), never
         from the source immediate — the 46→32 bit truncation must match. *)
      let (dop, ddst, _, dimm) = Rolling_key.decode_fields !w in
      cur_key := Rolling_key.advance_key_step !cur_key dop ddst dimm
    end;
    bytecode := masked_w :: !bytecode
  in

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

  (* Encode instructions (both Fused Super-Operators and Standard Raw Ops) *)
  List.iter
    (fun (b : Ir.basic_block) ->
      let ops = Hashtbl.find block_fused_ops b.id in
      (* Loop-safety: re-anchor the chain at every block entry, mirroring the
         runtime reanchor in H_JMP/H_JCC/H_CALL and the offset-0 entry probe.
         Blocks are encoded in layout order, so the offset below is exactly
         where this block's first word will land. *)
      if enable_rolling then
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
          | Fused_Cmp_Cmov { cmp_dst = _; cmp_imm; cond; cmov_dst; cmov_src } ->
              encode_raw_word ~extra_bits:(Int64.of_int (cond_to_code cond))
                (get_opcode OP_FUSED_CMP_CMOV) (get_reg_idx cmov_dst) (get_reg_idx cmov_src) cmp_imm
          | Raw instr -> (
              match instr with
              | Ir.Nop -> encode_raw_word (get_opcode OP_NOP) 0 0 0L
              | Ir.Mov { dst = Ir.Reg d; src = Ir.Reg s } ->
                  encode_raw_word (get_opcode OP_MOV_RR) (get_reg_idx d) (get_reg_idx s) 0L
              | Ir.Mov { dst = Ir.Reg d; src = Ir.Imm imm } ->
                  let low = Int64.logand imm 0xFFFFFFFFL in
                  let high = Int64.shift_right_logical imm 32 in
                  encode_raw_word (get_opcode OP_MOV_RI) (get_reg_idx d) 0 low;
                  if high <> 0L then
                    encode_raw_word (get_opcode OP_MOV_HIGH) (get_reg_idx d) 0 high
              | Ir.Mov { dst = Ir.Reg d; src = Ir.Mem m } ->
                  let op =
                    match m.width with
                    | Register.B64 -> OP_LOAD_64
                    | Register.B32 -> OP_LOAD_32
                    | _ -> OP_LOAD_8
                  in
                  let base_idx = match m.base with Some b -> get_reg_idx b | None -> 0 in
                  encode_raw_word (get_opcode op) (get_reg_idx d) base_idx m.disp
              | Ir.Mov { dst = Ir.Mem m; src = Ir.Reg s } ->
                  let op =
                    match m.width with
                    | Register.B64 -> OP_STORE_64
                    | Register.B32 -> OP_STORE_32
                    | _ -> OP_STORE_8
                  in
                  let base_idx = match m.base with Some b -> get_reg_idx b | None -> 0 in
                  encode_raw_word (get_opcode op) base_idx (get_reg_idx s) m.disp
              | Ir.Alu { op = Ir.Add; dst = d; src1 = Ir.Reg _; src2 = Ir.Reg s; _ } ->
                  encode_raw_word (get_opcode OP_ADD_RR) (get_reg_idx d) (get_reg_idx s) 0L
              | Ir.Alu { op = Ir.Add; dst = d; src1 = Ir.Reg _; src2 = Ir.Imm imm; _ } ->
                  encode_raw_word (get_opcode OP_ADD_RI) (get_reg_idx d) 0 imm
              | Ir.Alu { op = Ir.Sub; dst = d; src1 = Ir.Reg _; src2 = Ir.Reg s; _ } ->
                  encode_raw_word (get_opcode OP_SUB_RR) (get_reg_idx d) (get_reg_idx s) 0L
              | Ir.Alu { op = Ir.Sub; dst = d; src1 = Ir.Reg _; src2 = Ir.Imm imm; _ } ->
                  encode_raw_word (get_opcode OP_SUB_RI) (get_reg_idx d) 0 imm
              | Ir.Alu { op = Ir.Imul; dst = d; src1 = Ir.Reg _; src2 = Ir.Reg s; _ } ->
                  encode_raw_word (get_opcode OP_IMUL_RR) (get_reg_idx d) (get_reg_idx s) 0L
              | Ir.Alu { op = Ir.Imul; dst = d; src1 = Ir.Reg _; src2 = Ir.Imm imm; _ } ->
                  encode_raw_word (get_opcode OP_IMUL_RI) (get_reg_idx d) 0 imm
              | Ir.Alu { op = Ir.Xor; dst = d; src1 = Ir.Reg _; src2 = Ir.Reg s; _ } ->
                  encode_raw_word (get_opcode OP_XOR_RR) (get_reg_idx d) (get_reg_idx s) 0L
              | Ir.Alu { op = Ir.Xor; dst = d; src1 = Ir.Reg _; src2 = Ir.Imm imm; _ } ->
                  encode_raw_word (get_opcode OP_XOR_RI) (get_reg_idx d) 0 imm
              | Ir.Alu { op = Ir.And; dst = d; src1 = Ir.Reg _; src2 = Ir.Reg s; _ } ->
                  encode_raw_word (get_opcode OP_AND_RR) (get_reg_idx d) (get_reg_idx s) 0L
              | Ir.Alu { op = Ir.And; dst = d; src1 = Ir.Reg _; src2 = Ir.Imm imm; _ } ->
                  encode_raw_word (get_opcode OP_AND_RI) (get_reg_idx d) 0 imm
              | Ir.Alu { op = Ir.Or; dst = d; src1 = Ir.Reg _; src2 = Ir.Reg s; _ } ->
                  encode_raw_word (get_opcode OP_OR_RR) (get_reg_idx d) (get_reg_idx s) 0L
              | Ir.Alu { op = Ir.Or; dst = d; src1 = Ir.Reg _; src2 = Ir.Imm imm; _ } ->
                  encode_raw_word (get_opcode OP_OR_RI) (get_reg_idx d) 0 imm
              | Ir.Alu { op = Ir.Rol; dst = d; src1 = Ir.Reg _; src2 = Ir.Imm imm; _ } ->
                  encode_raw_word (get_opcode OP_ROL_RI) (get_reg_idx d) 0 imm
              | Ir.Alu { op = Ir.Ror; dst = d; src1 = Ir.Reg _; src2 = Ir.Imm imm; _ } ->
                  encode_raw_word (get_opcode OP_ROR_RI) (get_reg_idx d) 0 imm
              | Ir.Alu { op = Ir.Shl; dst = d; src1 = Ir.Reg _; src2 = Ir.Imm imm; _ } ->
                  encode_raw_word (get_opcode OP_SHL_RI) (get_reg_idx d) 0 imm
              | Ir.Alu { op = Ir.Shr; dst = d; src1 = Ir.Reg _; src2 = Ir.Imm imm; _ } ->
                  encode_raw_word (get_opcode OP_SHR_RI) (get_reg_idx d) 0 imm
              | Ir.Unary { op = Ir.Inc; dst; _ } ->
                  encode_raw_word (get_opcode OP_ADD_RI) (get_reg_idx dst) 0 1L
              | Ir.Unary { op = Ir.Dec; dst; _ } ->
                  encode_raw_word (get_opcode OP_SUB_RI) (get_reg_idx dst) 0 1L
              | Ir.Unary { op = Ir.Not; dst; _ } ->
                  encode_raw_word (get_opcode OP_XOR_RI) (get_reg_idx dst) 0 0xFFFFFFFF_FFFFFFFFL
              | Ir.Cmp { src1 = Ir.Reg d; src2 = Ir.Reg s } ->
                  encode_raw_word (get_opcode OP_CMP_RR) (get_reg_idx d) (get_reg_idx s) 0L
              | Ir.Cmp { src1 = Ir.Reg d; src2 = Ir.Imm imm } ->
                  encode_raw_word (get_opcode OP_CMP_RI) (get_reg_idx d) 0 imm
              | Ir.Push (Ir.Reg d) ->
                  encode_raw_word (get_opcode OP_PUSH_R) (get_reg_idx d) 0 0L
              | Ir.Pop (Ir.Reg d) ->
                  encode_raw_word (get_opcode OP_POP_R) (get_reg_idx d) 0 0L
              | Ir.Jmp (Ir.BlockId bid) ->
                  encode_raw_word (get_opcode OP_JMP) 0 0 (Int64.of_int (get_block_offset bid))
              | Ir.Jcc { cond; target_true = Ir.BlockId tid; target_false = Ir.BlockId fid } ->
                  let c = cond_to_code cond in
                  let t_off = get_block_offset tid in
                  let f_off = get_block_offset fid in
                  let imm = Int64.logor (Int64.of_int c) (Int64.shift_left (Int64.of_int t_off) 4) in
                  let imm = Int64.logor imm (Int64.shift_left (Int64.of_int f_off) 25) in
                  encode_raw_word (get_opcode OP_JCC) 0 0 imm
              | Ir.Cmov { cond; dst; src = Ir.Reg s } ->
                  encode_raw_word (get_opcode OP_CMOV) (get_reg_idx dst) (get_reg_idx s) (Int64.of_int (cond_to_code cond))
              | Ir.Setcc { cond; dst = Ir.Reg d } ->
                  encode_raw_word (get_opcode OP_SETCC) (get_reg_idx d) 0 (Int64.of_int (cond_to_code cond))
              | Ir.Call (Ir.BlockId bid) ->
                  encode_raw_word (get_opcode OP_CALL) 0 0 (Int64.of_int (get_block_offset bid))
              | Ir.Call (Ir.TargetImm imm) ->
                  encode_raw_word (get_opcode OP_CALL) 0 0 imm
              | Ir.Call (Ir.Label sym) ->
                  let sym_idx = get_ext_sym_idx sym in
                  encode_raw_word (get_opcode OP_CALL_EXTERN) 0 0 (Int64.of_int sym_idx)
              | Ir.Ret -> encode_raw_word (get_opcode OP_RET) 0 0 0L
              | Ir.Vm_exit -> encode_raw_word (get_opcode OP_EXIT) 0 0 0L
              | Ir.Bridge_to_flow imm -> encode_raw_word (get_opcode OP_BRIDGE_TO_FLOW) 0 0 imm
              | Ir.Bridge_to_math imm -> encode_raw_word (get_opcode OP_BRIDGE_TO_MATH) 0 0 imm
              | _ -> encode_raw_word (get_opcode OP_NOP) 0 0 0L))
        ops)
    sorted_blocks;

  let final_bytecode = List.rev !bytecode in
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
  let expected_hash = compute_bytecode_hash key_seed final_bytecode in
  let cpp_src = Vm_runtime_emitter.emit_cpp_threaded_header ~rng ~key_seed ~reg_perm ~expected_hash ?runtime_profile ?config ~external_symbols:!external_symbols opcode_to_handler in
  let runner_src = Vm_runtime_emitter.emit_runner_cpp ~key_seed:(Int64.of_int32 key_seed) ~reg_perm final_bytecode in

  let decoy_count = 256 - List.length all_op_kinds in
  let mba_nodes = if enable_mba then mba_depth * 15 else 0 in
  let metrics = Metrics.calculate_metrics
    ~bytecode:final_bytecode
    ~func:target_func
    ~decoy_count
    ~total_handlers:256
    ~mba_nodes
  in

  {
    bytecode = final_bytecode;
    cpp_runtime_source = cpp_src;
    runner_source = runner_src;
    metrics;
  }
