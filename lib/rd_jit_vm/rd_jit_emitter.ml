open Vm_ir
include Rd_jit_types
open Cpp_codegen.Cpp_ast
open Cpp_codegen.Cpp_dsl
open Cpp_codegen.Cpp_printer
module Magic_numbers = Random_visa_constants.Magic_numbers


let emit_rd_jit_runtime_decls ~external_symbols =
  let sym_entries =
    match external_symbols with
    | [] -> [ str_lit "" ]
    | xs -> List.map str_lit xs
  in
  let sym_decl =
    global_var ~is_static:true ~is_const:true
      (Array (Ptr (StructType "char"), 0))
      "g_rd_jit_external_symbols"
      ~init:(init_list sym_entries)
  in
  Rd_jit_buffer.header_decls ()
  @ [ sym_decl ]
  @ Rd_jit_synth.synth_decls ~external_symbols ()
  @ Nano_jit_slot.build_nano_arena_ast ()
  @ Rd_jit_synth.vm_bridge_decls ()

let emit_rd_jit_runtime_header ~external_symbols =
  render_top_decls (emit_rd_jit_runtime_decls ~external_symbols)

let emit_rd_jit_main_def () : top_decl =
  func_decl Int32 "main" [(Int32, "argc"); (Ptr (Ptr (StructType "char")), "argv")] [
    raw "std::cout << \"[ASGARD-RD-JIT] Initializing Register-Driven JIT Virtual Machine...\\n\";";
    raw "std::cout << \"  * Architecture: Register-Driven RISC (No Stack Emulation)\\n\";";
    raw "std::cout << \"  * Arithmetic: RNS-4 Modular Residue Splitting (M > 2^64)\\n\";";
    raw "std::cout << \"  * Memory Protection: Dual-Mapped W^X Ephemeral Buffer\\n\";";
    raw "std::cout << \"  * Sealed Chunks: \" << g_num_nano_chunks << \" Kolakoski-fissioned nano-slot chunk(s)\\n\";";
    raw "asgard_rd_jit::DualMappedJITBuffer jit_buf(4096);";
    raw "asgard_rd_jit::RD_JIT_Context ctx;";
    expr_stmt (call "ctx.init" []);
    let_u64 "arg1" (ternary (var "argc" >~ i32 1) (c_cast UInt64 (call "atoll" [Index (var "argv", i32 1)])) (u64 42L));
    let_u64 "arg2" (ternary (var "argc" >~ i32 2) (c_cast UInt64 (call "atoll" [Index (var "argv", i32 2)])) (u64 58L));
    expr_stmt (call "ctx.set_reg" [i32 0; var "arg1"]);
    expr_stmt (call "ctx.set_reg" [i32 1; var "arg2"]);
    raw "auto t0 = std::chrono::high_resolution_clock::now();";
    raw "asgard::nano_jit::execute_sealed_function(jit_buf, ctx, g_nano_tickets, g_nano_blobs, g_num_nano_chunks, g_nano_master);";
    raw "auto t1 = std::chrono::high_resolution_clock::now();";
    raw "double elapsed_us = std::chrono::duration<double, std::micro>(t1 - t0).count();";
    let_u64 "res" (call "ctx.get_reg" [i32 0]);
    raw "std::cout << \"[ASGARD-RD-JIT] Ephemeral Execution Successful!\\n\";";
    raw "std::cout << \"  * Result (REG 0): \" << res << \" (0x\" << std::hex << res << std::dec << \")\\n\";";
    raw "std::cout << \"  * RNS Residues: (\" << ctx.vregs[0].r1 << \", \" << ctx.vregs[0].r2 << \", \" << ctx.vregs[0].r3 << \", \" << ctx.vregs[0].r4 << \")\\n\";";
    raw "std::cout << \"  * JIT Cycle Time: \" << elapsed_us << \" us\\n\";";
    ret (i32 0);
  ]

(* Per-chunk sealing ticket emitted into the runner next to its ciphertext. *)
type sealed_chunk_ticket = {
  nonce      : int64;
  word_count : int;
  instr_count : int;
  perm_idx   : int;
}

let compile_and_package_core ~rng ?config ?(enable_cff = false) ?(enable_mba = false) ?(mba_depth = 2) ?external_symbols ?chunks (func : Ir.func) : rd_jit_package =
  let (enable_cff, enable_mba, mba_depth) =
    match config with
    | Some (c : Native_vm.Protection_config.t) ->
        (c.cff.enabled || enable_cff, c.mba.enabled || enable_mba, if mba_depth <> 2 then mba_depth else c.mba.depth)
    | None -> (enable_cff, enable_mba, mba_depth)
  in

  let target_func =
    if enable_cff then
      (* POP digest transform and the pop_digest option must be gated
         together (see vm_emitter.ml for the rationale). *)
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

  let base_pkg =
    Native_vm.Vm_emitter.compile_and_package
      ~rng
      ?config
      ~enable_cff
      ~enable_mba
      ~mba_depth
      target_func
  in

  let entry_block = Hashtbl.find target_func.cfg.blocks target_func.cfg.entry_id in
  let other_blocks =
    Hashtbl.fold
      (fun id b acc -> if id <> target_func.cfg.entry_id then b :: acc else acc)
      target_func.cfg.blocks []
  in
  let sorted_other = List.sort (fun (a : Ir.basic_block) (b : Ir.basic_block) -> Int.compare a.id b.id) other_blocks in
  let sorted_blocks = entry_block :: sorted_other in

  let external_symbols = ref (match external_symbols with Some xs -> xs | None -> []) in
  let external_sym_tbl = Hashtbl.create 16 in
  List.iteri (fun idx sym -> Hashtbl.replace external_sym_tbl sym idx) !external_symbols;
  let get_ext_sym_idx sym =
    match Hashtbl.find_opt external_sym_tbl sym with
    | Some idx -> idx
    | None ->
        let idx = List.length !external_symbols in
        Stdlib.(external_symbols := !external_symbols @ [ sym ]);
        Hashtbl.replace external_sym_tbl sym idx;
        idx
  in

  let assert_src1_eq_dst ~op ~dst ~src1 =
    match src1 with
    | Ir.Reg s1 when Register.to_string s1 = Register.to_string dst -> ()
    | Ir.Reg s1 ->
        failwith (Printf.sprintf "rd_jit_emitter: uncanonicalized 3-address ALU (op=%s): dst=%s, src1=%s (must be canonicalized to src1=dst)"
          (Ir.alu_op_to_string op) (Register.to_string dst) (Register.to_string s1))
    | _ ->
        failwith (Printf.sprintf "rd_jit_emitter: invalid ALU src1 (op=%s): dst=%s, src1=%s (must be Reg dst)"
          (Ir.alu_op_to_string op) (Register.to_string dst) (Ir.operand_to_string src1))
  in

  (* ---- Sealed nano-chunk pipeline ---------------------------------
     OEIS A000002 (Kolakoski fission), A010060 (Thue-Morse dummy opcodes),
     A000166 (derangement operand remap), A000695 (Moser-de Bruijn
     immediate blinding), transport sealing towards the A269160 arena. *)

  (* Serialization table mirroring the JITOpKind enum order of
     Rd_jit_synth.jit_op_kind_decl; the correspondence is locked by the
     RD-JIT test suite (enum order vs. this table). *)
  let jit_op_order =
    [ "NOP"; "MOV_RR"; "MOV_RI"; "ADD_RR"; "ADD_RI"; "SUB_RR"; "SUB_RI";
      "MUL_RR"; "MUL_RI"; "CALL_EXTERN"; "XOR_RR"; "XOR_RI"; "AND_RR";
      "AND_RI"; "OR_RR"; "OR_RI"; "SHL_RI"; "SHR_RI"; "SAR_RI"; "NOT_R";
      "NEG_R"; "LOAD_64"; "STORE_64"; "RET"; "EXIT";
      "SHL_RR"; "SHR_RR"; "SAR_RR"; "ROR_RR"; "DIV_RR"; "SDIV_RR"; "REM_RR";
      "CMP_RR"; "CSEL_RR"; "MULH_RR"; "SMULH_RR";
      "LOAD_8"; "LOAD_16"; "LOAD_32"; "STORE_8"; "STORE_16"; "STORE_32";
      "RESOLVE_SYM" ]
  in
  let jit_op_code_tbl = Hashtbl.create 32 in
  List.iteri
    (fun i suffix -> Hashtbl.replace jit_op_code_tbl suffix i)
    jit_op_order;
  let jit_op_code (op : string) : int =
    let prefix = "asgard_rd_jit::JIT_OP_" in
    let suffix =
      String.sub op (String.length prefix) (String.length op - String.length prefix)
    in
    match Hashtbl.find_opt jit_op_code_tbl suffix with
    | Some c -> c
    | None -> failwith ("rd_jit_emitter: unknown JIT opcode " ^ op)
  in

  let jit_op_nop = "asgard_rd_jit::JIT_OP_NOP" in
  let jit_op_extern = "asgard_rd_jit::JIT_OP_CALL_EXTERN" in

  let cond_to_arm64_code = function
    | Flags.E -> 0
    | Flags.NE -> 1
    | Flags.B -> 2
    | Flags.AE -> 3
    | Flags.S -> 4
    | Flags.NS -> 5
    | Flags.O -> 6
    | Flags.NO -> 7
    | Flags.A -> 8
    | Flags.BE -> 9
    | Flags.GE -> 10
    | Flags.L -> 11
    | Flags.G -> 12
    | Flags.LE -> 13
    | Flags.ALWAYS -> 14
    | _ -> 0
  in

  let map_instr (instr : Ir.instr) : string * int * int * int64 =
    match instr with
    | Ir.Nop -> (jit_op_nop, 0, 0, 0L)
    | Ir.Mov { dst = Ir.Reg d; src = Ir.Reg s } ->
        ("asgard_rd_jit::JIT_OP_MOV_RR", Native_vm.Vm_transform.reg_to_index d mod 16,
         Native_vm.Vm_transform.reg_to_index s mod 16, 0L)
    | Ir.Mov { dst = Ir.Reg d; src = Ir.Imm imm } ->
        ("asgard_rd_jit::JIT_OP_MOV_RI", Native_vm.Vm_transform.reg_to_index d mod 16, 0, imm)
    | Ir.Alu { op = (Ir.Add | Ir.Adc); dst; src1; src2 = Ir.Reg s; _ } ->
        assert_src1_eq_dst ~op:Ir.Add ~dst ~src1;
        ("asgard_rd_jit::JIT_OP_ADD_RR", Native_vm.Vm_transform.reg_to_index dst mod 16,
         Native_vm.Vm_transform.reg_to_index s mod 16, 0L)
    | Ir.Alu { op = (Ir.Add | Ir.Adc); dst; src1; src2 = Ir.Imm imm; _ } ->
        assert_src1_eq_dst ~op:Ir.Add ~dst ~src1;
        ("asgard_rd_jit::JIT_OP_ADD_RI", Native_vm.Vm_transform.reg_to_index dst mod 16, 0, imm)
    | Ir.Alu { op = (Ir.Sub | Ir.Sbb); dst; src1; src2 = Ir.Reg s; _ } ->
        assert_src1_eq_dst ~op:Ir.Sub ~dst ~src1;
        ("asgard_rd_jit::JIT_OP_SUB_RR", Native_vm.Vm_transform.reg_to_index dst mod 16,
         Native_vm.Vm_transform.reg_to_index s mod 16, 0L)
    | Ir.Alu { op = (Ir.Sub | Ir.Sbb); dst; src1; src2 = Ir.Imm imm; _ } ->
        assert_src1_eq_dst ~op:Ir.Sub ~dst ~src1;
        ("asgard_rd_jit::JIT_OP_SUB_RI", Native_vm.Vm_transform.reg_to_index dst mod 16, 0, imm)
    | Ir.Alu { op = (Ir.Mul | Ir.Imul); dst; src1; src2 = Ir.Reg s; _ } ->
        assert_src1_eq_dst ~op:Ir.Imul ~dst ~src1;
        ("asgard_rd_jit::JIT_OP_MUL_RR", Native_vm.Vm_transform.reg_to_index dst mod 16,
         Native_vm.Vm_transform.reg_to_index s mod 16, 0L)
    | Ir.Alu { op = (Ir.Mul | Ir.Imul); dst; src1; src2 = Ir.Imm imm; _ } ->
        assert_src1_eq_dst ~op:Ir.Imul ~dst ~src1;
        ("asgard_rd_jit::JIT_OP_MUL_RI", Native_vm.Vm_transform.reg_to_index dst mod 16, 0, imm)
    | Ir.Alu { op = Ir.Xor; dst; src1; src2 = Ir.Reg s; _ } ->
        assert_src1_eq_dst ~op:Ir.Xor ~dst ~src1;
        ("asgard_rd_jit::JIT_OP_XOR_RR", Native_vm.Vm_transform.reg_to_index dst mod 16,
         Native_vm.Vm_transform.reg_to_index s mod 16, 0L)
    | Ir.Alu { op = Ir.Xor; dst; src1; src2 = Ir.Imm imm; _ } ->
        assert_src1_eq_dst ~op:Ir.Xor ~dst ~src1;
        ("asgard_rd_jit::JIT_OP_XOR_RI", Native_vm.Vm_transform.reg_to_index dst mod 16, 0, imm)
    | Ir.Alu { op = Ir.And; dst; src1; src2 = Ir.Reg s; _ } ->
        assert_src1_eq_dst ~op:Ir.And ~dst ~src1;
        ("asgard_rd_jit::JIT_OP_AND_RR", Native_vm.Vm_transform.reg_to_index dst mod 16,
         Native_vm.Vm_transform.reg_to_index s mod 16, 0L)
    | Ir.Alu { op = Ir.And; dst; src1; src2 = Ir.Imm imm; _ } ->
        assert_src1_eq_dst ~op:Ir.And ~dst ~src1;
        ("asgard_rd_jit::JIT_OP_AND_RI", Native_vm.Vm_transform.reg_to_index dst mod 16, 0, imm)
    | Ir.Alu { op = Ir.Or; dst; src1; src2 = Ir.Reg s; _ } ->
        assert_src1_eq_dst ~op:Ir.Or ~dst ~src1;
        ("asgard_rd_jit::JIT_OP_OR_RR", Native_vm.Vm_transform.reg_to_index dst mod 16,
         Native_vm.Vm_transform.reg_to_index s mod 16, 0L)
    | Ir.Alu { op = Ir.Or; dst; src1; src2 = Ir.Imm imm; _ } ->
        assert_src1_eq_dst ~op:Ir.Or ~dst ~src1;
        ("asgard_rd_jit::JIT_OP_OR_RI", Native_vm.Vm_transform.reg_to_index dst mod 16, 0, imm)
    | Ir.Alu { op = Ir.Shl; dst; src1; src2 = Ir.Imm imm; _ } ->
        assert_src1_eq_dst ~op:Ir.Shl ~dst ~src1;
        ("asgard_rd_jit::JIT_OP_SHL_RI", Native_vm.Vm_transform.reg_to_index dst mod 16, 0, imm)
    | Ir.Alu { op = Ir.Shr; dst; src1; src2 = Ir.Imm imm; _ } ->
        assert_src1_eq_dst ~op:Ir.Shr ~dst ~src1;
        ("asgard_rd_jit::JIT_OP_SHR_RI", Native_vm.Vm_transform.reg_to_index dst mod 16, 0, imm)
    | Ir.Alu { op = Ir.Sar; dst; src1; src2 = Ir.Imm imm; _ } ->
        assert_src1_eq_dst ~op:Ir.Sar ~dst ~src1;
        ("asgard_rd_jit::JIT_OP_SAR_RI", Native_vm.Vm_transform.reg_to_index dst mod 16, 0, imm)
    | Ir.Alu { op = Ir.Shl; dst; src1; src2 = Ir.Reg s; _ } ->
        assert_src1_eq_dst ~op:Ir.Shl ~dst ~src1;
        ("asgard_rd_jit::JIT_OP_SHL_RR", Native_vm.Vm_transform.reg_to_index dst mod 16,
         Native_vm.Vm_transform.reg_to_index s mod 16, 0L)
    | Ir.Alu { op = Ir.Shr; dst; src1; src2 = Ir.Reg s; _ } ->
        assert_src1_eq_dst ~op:Ir.Shr ~dst ~src1;
        ("asgard_rd_jit::JIT_OP_SHR_RR", Native_vm.Vm_transform.reg_to_index dst mod 16,
         Native_vm.Vm_transform.reg_to_index s mod 16, 0L)
    | Ir.Alu { op = Ir.Sar; dst; src1; src2 = Ir.Reg s; _ } ->
        assert_src1_eq_dst ~op:Ir.Sar ~dst ~src1;
        ("asgard_rd_jit::JIT_OP_SAR_RR", Native_vm.Vm_transform.reg_to_index dst mod 16,
         Native_vm.Vm_transform.reg_to_index s mod 16, 0L)
    | Ir.Alu { op = Ir.Ror; dst; src1; src2 = Ir.Reg s; _ } ->
        assert_src1_eq_dst ~op:Ir.Ror ~dst ~src1;
        ("asgard_rd_jit::JIT_OP_ROR_RR", Native_vm.Vm_transform.reg_to_index dst mod 16,
         Native_vm.Vm_transform.reg_to_index s mod 16, 0L)
    | Ir.Alu { op = Ir.Mulh; dst; src1; src2 = Ir.Reg s; _ } ->
        assert_src1_eq_dst ~op:Ir.Mulh ~dst ~src1;
        ("asgard_rd_jit::JIT_OP_MULH_RR", Native_vm.Vm_transform.reg_to_index dst mod 16,
         Native_vm.Vm_transform.reg_to_index s mod 16, 0L)
    | Ir.Alu { op = Ir.Imulh; dst; src1; src2 = Ir.Reg s; _ } ->
        assert_src1_eq_dst ~op:Ir.Imulh ~dst ~src1;
        ("asgard_rd_jit::JIT_OP_SMULH_RR", Native_vm.Vm_transform.reg_to_index dst mod 16,
         Native_vm.Vm_transform.reg_to_index s mod 16, 0L)
    | Ir.Alu { op = Ir.Div; dst; src1; src2 = Ir.Reg s; _ } ->
        assert_src1_eq_dst ~op:Ir.Div ~dst ~src1;
        ("asgard_rd_jit::JIT_OP_DIV_RR", Native_vm.Vm_transform.reg_to_index dst mod 16,
         Native_vm.Vm_transform.reg_to_index s mod 16, 0L)
    | Ir.Alu { op = Ir.Idiv; dst; src1; src2 = Ir.Reg s; _ } ->
        assert_src1_eq_dst ~op:Ir.Idiv ~dst ~src1;
        ("asgard_rd_jit::JIT_OP_SDIV_RR", Native_vm.Vm_transform.reg_to_index dst mod 16,
         Native_vm.Vm_transform.reg_to_index s mod 16, 0L)
    | Ir.Cmp { src1 = Ir.Reg s1; src2 = Ir.Reg s2 } ->
        ("asgard_rd_jit::JIT_OP_CMP_RR", Native_vm.Vm_transform.reg_to_index s1 mod 16,
         Native_vm.Vm_transform.reg_to_index s2 mod 16, 0L)
    | Ir.Cmov { cond; dst; src = Ir.Reg s } ->
        let c = cond_to_arm64_code cond in
        let d = Native_vm.Vm_transform.reg_to_index dst mod 16 in
        let s_idx = Native_vm.Vm_transform.reg_to_index s mod 16 in
        ("asgard_rd_jit::JIT_OP_CSEL_RR", d, s_idx, Int64.of_int (c lor (d lsl 8)))
    | Ir.Unary { op = Ir.Not; dst; src = _; _ } ->
        ("asgard_rd_jit::JIT_OP_NOT_R", Native_vm.Vm_transform.reg_to_index dst mod 16, 0, 0L)
    | Ir.Unary { op = Ir.Neg; dst; src = _; _ } ->
        ("asgard_rd_jit::JIT_OP_NEG_R", Native_vm.Vm_transform.reg_to_index dst mod 16, 0, 0L)
    | Ir.Mov { dst = Ir.Reg d; src = Ir.Mem { base = Some b; disp; width; _ } } ->
        let op = match width with
          | Register.B8 -> "asgard_rd_jit::JIT_OP_LOAD_8"
          | Register.B16 -> "asgard_rd_jit::JIT_OP_LOAD_16"
          | Register.B32 -> "asgard_rd_jit::JIT_OP_LOAD_32"
          | _ -> "asgard_rd_jit::JIT_OP_LOAD_64"
        in
        (op, Native_vm.Vm_transform.reg_to_index d mod 16,
         Native_vm.Vm_transform.reg_to_index b mod 16, disp)
    | Ir.Mov { dst = Ir.Mem { base = Some b; disp; width; _ }; src = Ir.Reg s } ->
        let op = match width with
          | Register.B8 -> "asgard_rd_jit::JIT_OP_STORE_8"
          | Register.B16 -> "asgard_rd_jit::JIT_OP_STORE_16"
          | Register.B32 -> "asgard_rd_jit::JIT_OP_STORE_32"
          | _ -> "asgard_rd_jit::JIT_OP_STORE_64"
        in
        (op, Native_vm.Vm_transform.reg_to_index b mod 16,
         Native_vm.Vm_transform.reg_to_index s mod 16, disp)
    | Ir.Call (Ir.Label sym) ->
        let sym_idx = get_ext_sym_idx sym in
        (jit_op_extern, 0, 0, Int64.of_int sym_idx)
    | Ir.Ret -> ("asgard_rd_jit::JIT_OP_RET", 0, 0, 0L)
    | Ir.Vm_exit -> ("asgard_rd_jit::JIT_OP_EXIT", 0, 0, 0L)
    | _ -> (jit_op_nop, 0, 0, 0L)
  in

  let all_instrs =
    List.concat_map
      (fun (b : Ir.basic_block) ->
        let instrs = Native_vm.Vm_transform.canonicalize_3addr_alu b.instrs in
        List.map map_instr instrs)
      sorted_blocks
  in

  let kolakoski_chunks =
    match chunks with
    | Some cs ->
        List.map
          (fun chunk ->
            let has_extern = List.exists (fun (op, _, _, _) -> op = jit_op_extern) chunk in
            (chunk, has_extern))
          cs
    | None ->
        (* OEIS A010060: a dummy opcode is generated at stream position n iff
           t_n = popcount(n) mod 2 = 1; the synthesized machine code then carries
           aperiodic no-op padding no loop summarizer can align. *)
        let pos = ref 0 in
        let out = ref [] in
        List.iter
          (fun item ->
            if Nano_jit_slot.thue_morse !pos then begin
              Stdlib.(out := (jit_op_nop, 0, 0, 0L) :: !out);
              incr pos
            end;
            Stdlib.(out := item :: !out);
            incr pos)
          all_instrs;
        let thue_morse_stream = List.rev !out in
        (* OEIS A000002: chunk target sizes are the run lengths of the Kolakoski
           word scaled by nano_kolakoski_scale (2 or 4 instructions). *)
        let kolakoski_word = Nano_jit_slot.kolakoski 256 in
        let run_idx = ref 0 in
        let cur = ref [] in
        let acc = ref [] in
        let flush () =
          if !cur <> [] then begin
            let chunk = List.rev !cur in
            let has_extern = List.exists (fun (op, _, _, _) -> op = jit_op_extern) chunk in
            Stdlib.(acc := (chunk, has_extern) :: !acc);
            Stdlib.(cur := []);
            incr run_idx
          end
        in
        List.iter
          (fun item ->
            let target =
              kolakoski_word.(!run_idx mod Array.length kolakoski_word)
              * Nano_jit_slot.nano_kolakoski_scale
            in
            if List.length !cur >= target
               || List.length !cur >= Nano_jit_slot.nano_max_chunk_instrs
            then flush ();
            Stdlib.(cur := item :: !cur))
          thue_morse_stream;
        flush ();
        match List.rev !acc with
        | [] -> [ ([ (jit_op_nop, 0, 0, 0L) ], false) ]
        | chunks -> chunks
  in

  let master_key = Random.State.int64 rng 0x7FFFFFFFFFFFFFFFL in
  let draw64 () = Random.State.int64 rng 0x7FFFFFFFFFFFFFFFL in

  let put_u64_le (b : bytes) (off : int) (v : int64) =
    for i = 0 to 7 do
      Bytes.set b (off + i)
        (Char.chr
           (Int64.to_int
              (Int64.logand (Int64.shift_right_logical v (8 * i)) 0xFFL)))
    done
  in
  let get_u64_le (b : bytes) (off : int) : int64 =
    let v = ref 0L in
    for i = 7 downto 0 do
      Stdlib.(v :=
        Int64.logor (Int64.shift_left !v 8)
          (Int64.of_int (Char.code (Bytes.get b (off + i)))));
    done;
    !v
  in

  (* OEIS A000166: chunk k permutes its virtual-register operands with the
     fix-free permutation pi_k (identity at external-call ABI boundaries),
     and every immediate crosses the seal as a Moser-de Bruijn (A000695)
     carry-free X + 2Y pair. *)
  let sealed_chunks =
    List.mapi
      (fun k (chunk, has_extern) ->
        let perm_idx =
          if has_extern then Nano_jit_slot.perm_identity_index
          else k mod (Array.length Nano_jit_slot.derangement_tables)
        in
        let packed = Nano_jit_slot.perm_tables.(perm_idx) in
        let remap_idx i = Nano_jit_slot.perm_apply packed i in
        let words =
          List.map
            (fun (op, dst, src, imm) ->
              let opc = jit_op_code op in
              let imm' =
                if op = "asgard_rd_jit::JIT_OP_CSEL_RR" then
                  let cond = Int64.logand imm 0xFFL in
                  let src2 = Int64.to_int (Int64.shift_right_logical imm 8) land 0xFF in
                  let src2' = remap_idx src2 in
                  Int64.logor cond (Int64.shift_left (Int64.of_int src2') 8)
                else imm
              in
              let w0 =
                Int64.logor
                  (Int64.logor
                     (Int64.of_int opc)
                     (Int64.shift_left (Int64.of_int (remap_idx dst)) 8))
                  (Int64.shift_left (Int64.of_int (remap_idx src)) 16)
              in
              let w1 = Nano_jit_slot.moser_pack imm' in
            (w0, w1))
          chunk
        in
        let plain = Bytes.create (16 * List.length words) in
        List.iteri
          (fun i (w0, w1) ->
            put_u64_le plain (16 * i) w0;
            put_u64_le plain ((16 * i) + 8) w1)
          words;
        let nonce = Int64.logxor (draw64 ()) (Int64.of_int ((k + 1) * 64775)) in
        let seal =
          Nano_jit_slot.seal_nano_block ~block_id:k ~raw_code:plain
            ~master_key ~nonce
        in
        let cipher = seal.encrypted_bytes in
        let cipher_words =
          List.init (2 * List.length words) (fun j -> get_u64_le cipher (8 * j))
        in
        let ticket =
          { nonce;
            word_count = 2 * List.length words;
            instr_count = List.length chunk;
            perm_idx }
        in
        (cipher_words, ticket))
      kolakoski_chunks
  in

  let master_decl =
    global_var ~is_static:true ~is_const:true UInt64 "g_nano_master"
      ~init:(u64 master_key)
  in
  let blob_decls =
    List.mapi
      (fun k (cipher_words, _) ->
        global_var ~is_static:true ~is_const:true (Array (UInt64, 0))
          (Printf.sprintf "jit_blob_%d" k)
          ~init:(init_list (List.map u64 cipher_words)))
      sealed_chunks
  in
  let blobs_ptr_decl =
    global_var ~is_static:true ~is_const:true (Array (Ptr UInt64, 0))
      "g_nano_blobs"
      ~init:(init_list
               (List.mapi
                  (fun k _ -> var (Printf.sprintf "jit_blob_%d" k))
                  sealed_chunks))
  in
  let tickets_decl =
    global_var ~is_static:true ~is_const:true
      (Array (StructType "asgard::nano_jit::NanoTicket", 0))
      "g_nano_tickets"
      ~init:(init_list
               (List.map
                  (fun (_, t) ->
                    init_list
                      [ u64 t.nonce;
                        u32 (Int32.of_int t.word_count);
                        u32 (Int32.of_int t.instr_count);
                        u32 (Int32.of_int t.perm_idx) ])
                  sealed_chunks))
  in
  let num_chunks_decl =
    global_var ~is_static:true ~is_const:true SizeT "g_num_nano_chunks"
      ~init:(sizeof_expr (var "g_nano_tickets")
             /~ sizeof_expr (Index (var "g_nano_tickets", i32 0)))
  in
  let sealed_descriptors_code =
    render_top_decls (master_decl :: (blob_decls @ [ blobs_ptr_decl; tickets_decl; num_chunks_decl ]))
  in

  let rd_jit_hdr = emit_rd_jit_runtime_header ~external_symbols:!external_symbols in

  let runner_cpp =
    "#if __has_include(\"jit_vm_runtime.hpp\")\n\
#include \"jit_vm_runtime.hpp\"\n\
#elif __has_include(\"rd_jit_runtime.hpp\")\n\
#include \"rd_jit_runtime.hpp\"\n\
#else\n\
#include \"threaded_vm.hpp\"\n\
#endif\n\
#include <iostream>\n\
#include <chrono>\n\n\
// Sealed Nano-Chunk Descriptors (OEIS A000002 fission, A000695 blinding)\n"
    ^ sealed_descriptors_code
    ^ "\n\n"
    ^ render_top_decl (emit_rd_jit_main_def ())
    ^ "\n" in

  let serialize_jit_bytecode () : int64 list =
    let magic = Magic_numbers.jit_bytecode_magic in
    let num_chunks = Int64.of_int (List.length sealed_chunks) in
    let header = [ magic; master_key; num_chunks ] in
    let chunks_bc =
      List.concat_map
        (fun (cipher_words, t) ->
          [
            t.nonce;
            Int64.of_int t.word_count;
            Int64.of_int t.instr_count;
            Int64.of_int t.perm_idx;
          ]
          @ cipher_words)
        sealed_chunks
    in
    header @ chunks_bc
  in
  let jit_bytecode = serialize_jit_bytecode () in

  {
    cpp_runtime_source = rd_jit_hdr;
    runner_source = runner_cpp;
    rns_moduli = (Rns.m1, Rns.m2, Rns.m3, Rns.m4);
    bytecode = jit_bytecode;
    metrics = base_pkg.metrics;
  }

let compile_and_package ~rng ?config ?enable_cff ?enable_mba ?mba_depth ?external_symbols func =
  compile_and_package_core ~rng ?config ?enable_cff ?enable_mba ?mba_depth ?external_symbols func

let compile_and_package_chunked ~rng ?config ?enable_cff ?enable_mba ?mba_depth ?external_symbols ~chunks func =
  compile_and_package_core ~rng ?config ?enable_cff ?enable_mba ?mba_depth ?external_symbols ~chunks func
