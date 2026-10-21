open Vm_ir
include Rd_jit_types
open Cpp_codegen.Cpp_ast
open Cpp_codegen.Cpp_dsl
open Cpp_codegen.Cpp_printer

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
  @ Rd_jit_synth.header_decls ~external_symbols ()

let emit_rd_jit_runtime_header ~external_symbols =
  render_top_decls (emit_rd_jit_runtime_decls ~external_symbols)

let emit_rd_jit_main_def () : top_decl =
  func_decl Int32 "main" [(Int32, "argc"); (Ptr (Ptr (StructType "char")), "argv")] [
    raw "std::cout << \"[ASGARD-RD-JIT] Initializing Register-Driven JIT Virtual Machine...\\n\";";
    raw "std::cout << \"  * Architecture: Register-Driven RISC (No Stack Emulation)\\n\";";
    raw "std::cout << \"  * Arithmetic: RNS-4 Modular Residue Splitting (M > 2^64)\\n\";";
    raw "std::cout << \"  * Memory Protection: Dual-Mapped W^X Ephemeral Buffer\\n\";";
    raw "std::cout << \"  * Blocks: \" << num_jit_blocks << \" dynamic JIT synthesis block(s)\\n\";";
    raw "asgard_rd_jit::DualMappedJITBuffer jit_buf(4096);";
    raw "asgard_rd_jit::RD_JIT_Context ctx;";
    expr_stmt (call "ctx.init" []);
    let_u64 "arg1" (ternary (var "argc" >~ i32 1) (c_cast UInt64 (call "atoll" [Index (var "argv", i32 1)])) (u64 42L));
    let_u64 "arg2" (ternary (var "argc" >~ i32 2) (c_cast UInt64 (call "atoll" [Index (var "argv", i32 2)])) (u64 58L));
    expr_stmt (call "ctx.set_reg" [i32 0; var "arg1"]);
    expr_stmt (call "ctx.set_reg" [i32 1; var "arg2"]);
    raw "auto t0 = std::chrono::high_resolution_clock::now();";
    raw "asgard_rd_jit::execute_jit_function(jit_buf, ctx, jit_blocks, num_jit_blocks);";
    raw "auto t1 = std::chrono::high_resolution_clock::now();";
    raw "double elapsed_us = std::chrono::duration<double, std::micro>(t1 - t0).count();";
    let_u64 "res" (call "ctx.get_reg" [i32 0]);
    raw "std::cout << \"[ASGARD-RD-JIT] Ephemeral Execution Successful!\\n\";";
    raw "std::cout << \"  * Result (REG 0): \" << res << \" (0x\" << std::hex << res << std::dec << \")\\n\";";
    raw "std::cout << \"  * RNS Residues: (\" << ctx.vregs[0].r1 << \", \" << ctx.vregs[0].r2 << \", \" << ctx.vregs[0].r3 << \", \" << ctx.vregs[0].r4 << \")\\n\";";
    raw "std::cout << \"  * JIT Cycle Time: \" << elapsed_us << \" us\\n\";";
    ret (i32 0);
  ]

let compile_and_package ~rng ?config ?(enable_cff = false) ?(enable_mba = false) ?(mba_depth = 2) (func : Ir.func) : rd_jit_package =
  let (enable_cff, enable_mba, mba_depth) =
    match config with
    | Some (c : Native_vm.Protection_config.t) ->
        (c.cff.enabled || enable_cff, c.mba.enabled || enable_mba, if mba_depth <> 2 then mba_depth else c.mba.depth)
    | None -> (enable_cff, enable_mba, mba_depth)
  in

  let target_func =
    if enable_cff then
      let cff_opts =
        match config with
        | Some c ->
            {
              Cff.inject_opaque_predicates = c.cff.inject_opaque_predicates;
              obfuscate_states = c.cff.obfuscate_states;
              input_tainted_transitions = c.cff.input_tainted_transitions;
              split_rate = c.cff.split_rate;
              hub_count = c.cff.hub_count;
              pop_digest = Some (Cff.Pop_coupler.default_pop_config.digest_reg, Cff.Pop_coupler.default_pop_config.initial_seed);
              red_herring = true;
            }
        | None ->
            { Cff.default_cff_options with
              pop_digest = Some (Cff.Pop_coupler.default_pop_config.digest_reg, Cff.Pop_coupler.default_pop_config.initial_seed);
            }
      in
      let pop_func = Cff.Pop_coupler.apply_pop_transform ~rng func in
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

  let external_symbols = ref [] in
  let external_sym_tbl = Hashtbl.create 16 in
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

  let (block_instr_decls, block_entries) =
    List.mapi
      (fun idx (b : Ir.basic_block) ->
        let instrs = Native_vm.Vm_transform.canonicalize_3addr_alu b.instrs in
        let instr_exprs =
          List.map
            (fun instr ->
              let (op, dst, src, imm) =
                match instr with
                | Ir.Nop -> ("asgard_rd_jit::JIT_OP_NOP", 0, 0, 0L)
                | Ir.Mov { dst = Ir.Reg d; src = Ir.Reg s } ->
                    ("asgard_rd_jit::JIT_OP_MOV_RR", Native_vm.Vm_transform.reg_to_index d mod 16, Native_vm.Vm_transform.reg_to_index s mod 16, 0L)
                | Ir.Mov { dst = Ir.Reg d; src = Ir.Imm imm } ->
                    ("asgard_rd_jit::JIT_OP_MOV_RI", Native_vm.Vm_transform.reg_to_index d mod 16, 0, imm)
                | Ir.Alu { op = (Ir.Add | Ir.Adc); dst; src1; src2 = Ir.Reg s; _ } ->
                    assert_src1_eq_dst ~op:Ir.Add ~dst ~src1;
                    ("asgard_rd_jit::JIT_OP_ADD_RR", Native_vm.Vm_transform.reg_to_index dst mod 16, Native_vm.Vm_transform.reg_to_index s mod 16, 0L)
                | Ir.Alu { op = (Ir.Add | Ir.Adc); dst; src1; src2 = Ir.Imm imm; _ } ->
                    assert_src1_eq_dst ~op:Ir.Add ~dst ~src1;
                    ("asgard_rd_jit::JIT_OP_ADD_RI", Native_vm.Vm_transform.reg_to_index dst mod 16, 0, imm)
                | Ir.Alu { op = (Ir.Sub | Ir.Sbb); dst; src1; src2 = Ir.Reg s; _ } ->
                    assert_src1_eq_dst ~op:Ir.Sub ~dst ~src1;
                    ("asgard_rd_jit::JIT_OP_SUB_RR", Native_vm.Vm_transform.reg_to_index dst mod 16, Native_vm.Vm_transform.reg_to_index s mod 16, 0L)
                | Ir.Alu { op = (Ir.Sub | Ir.Sbb); dst; src1; src2 = Ir.Imm imm; _ } ->
                    assert_src1_eq_dst ~op:Ir.Sub ~dst ~src1;
                    ("asgard_rd_jit::JIT_OP_SUB_RI", Native_vm.Vm_transform.reg_to_index dst mod 16, 0, imm)
                | Ir.Alu { op = (Ir.Mul | Ir.Imul); dst; src1; src2 = Ir.Reg s; _ } ->
                    assert_src1_eq_dst ~op:Ir.Imul ~dst ~src1;
                    ("asgard_rd_jit::JIT_OP_MUL_RR", Native_vm.Vm_transform.reg_to_index dst mod 16, Native_vm.Vm_transform.reg_to_index s mod 16, 0L)
                | Ir.Alu { op = (Ir.Mul | Ir.Imul); dst; src1; src2 = Ir.Imm imm; _ } ->
                    assert_src1_eq_dst ~op:Ir.Imul ~dst ~src1;
                    ("asgard_rd_jit::JIT_OP_MUL_RI", Native_vm.Vm_transform.reg_to_index dst mod 16, 0, imm)
                | Ir.Alu { op = Ir.Xor; dst; src1; src2 = Ir.Reg s; _ } ->
                    assert_src1_eq_dst ~op:Ir.Xor ~dst ~src1;
                    ("asgard_rd_jit::JIT_OP_XOR_RR", Native_vm.Vm_transform.reg_to_index dst mod 16, Native_vm.Vm_transform.reg_to_index s mod 16, 0L)
                | Ir.Alu { op = Ir.Xor; dst; src1; src2 = Ir.Imm imm; _ } ->
                    assert_src1_eq_dst ~op:Ir.Xor ~dst ~src1;
                    ("asgard_rd_jit::JIT_OP_XOR_RI", Native_vm.Vm_transform.reg_to_index dst mod 16, 0, imm)
                | Ir.Alu { op = Ir.And; dst; src1; src2 = Ir.Reg s; _ } ->
                    assert_src1_eq_dst ~op:Ir.And ~dst ~src1;
                    ("asgard_rd_jit::JIT_OP_AND_RR", Native_vm.Vm_transform.reg_to_index dst mod 16, Native_vm.Vm_transform.reg_to_index s mod 16, 0L)
                | Ir.Alu { op = Ir.And; dst; src1; src2 = Ir.Imm imm; _ } ->
                    assert_src1_eq_dst ~op:Ir.And ~dst ~src1;
                    ("asgard_rd_jit::JIT_OP_AND_RI", Native_vm.Vm_transform.reg_to_index dst mod 16, 0, imm)
                | Ir.Alu { op = Ir.Or; dst; src1; src2 = Ir.Reg s; _ } ->
                    assert_src1_eq_dst ~op:Ir.Or ~dst ~src1;
                    ("asgard_rd_jit::JIT_OP_OR_RR", Native_vm.Vm_transform.reg_to_index dst mod 16, Native_vm.Vm_transform.reg_to_index s mod 16, 0L)
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
                | Ir.Unary { op = Ir.Not; dst; src = _; _ } ->
                    ("asgard_rd_jit::JIT_OP_NOT_R", Native_vm.Vm_transform.reg_to_index dst mod 16, 0, 0L)
                | Ir.Unary { op = Ir.Neg; dst; src = _; _ } ->
                    ("asgard_rd_jit::JIT_OP_NEG_R", Native_vm.Vm_transform.reg_to_index dst mod 16, 0, 0L)
                | Ir.Mov { dst = Ir.Reg d; src = Ir.Mem { base = Some b; disp; _ } } ->
                    ("asgard_rd_jit::JIT_OP_LOAD_64", Native_vm.Vm_transform.reg_to_index d mod 16, Native_vm.Vm_transform.reg_to_index b mod 16, disp)
                | Ir.Mov { dst = Ir.Mem { base = Some b; disp; _ }; src = Ir.Reg s } ->
                    ("asgard_rd_jit::JIT_OP_STORE_64", Native_vm.Vm_transform.reg_to_index b mod 16, Native_vm.Vm_transform.reg_to_index s mod 16, disp)
                | Ir.Call (Ir.Label sym) ->
                    let sym_idx = get_ext_sym_idx sym in
                    ("asgard_rd_jit::JIT_OP_CALL_EXTERN", 0, 0, Int64.of_int sym_idx)
                | Ir.Ret -> ("asgard_rd_jit::JIT_OP_RET", 0, 0, 0L)
                | Ir.Vm_exit -> ("asgard_rd_jit::JIT_OP_EXIT", 0, 0, 0L)
                | _ -> ("asgard_rd_jit::JIT_OP_NOP", 0, 0, 0L)
              in
              init_list [ var op; i32 dst; i32 src; u64 imm ])
            instrs
        in
        let count = List.length instr_exprs in
        let decl =
          global_var ~is_static:true ~is_const:true
            (Array (StructType "asgard_rd_jit::JITInstr", 0))
            (Printf.sprintf "jit_block_%d_instrs" idx)
            ~init:(init_list instr_exprs)
        in
        let entry = init_list [ i32 idx; i32 count; var (Printf.sprintf "jit_block_%d_instrs" idx) ] in
        (decl, entry))
      sorted_blocks
    |> List.split
  in

  let jit_blocks_decl =
    global_var ~is_static:true ~is_const:true
      (Array (StructType "asgard_rd_jit::JITBlock", 0))
      "jit_blocks"
      ~init:(init_list block_entries)
  in
  let num_jit_blocks_decl =
    global_var ~is_static:true ~is_const:true SizeT "num_jit_blocks"
      ~init:(sizeof_expr (var "jit_blocks") /~ sizeof_expr (Index (var "jit_blocks", i32 0)))
  in
  let all_jit_decls = block_instr_decls @ [ jit_blocks_decl; num_jit_blocks_decl ] in
  let jit_descriptors_code = render_top_decls all_jit_decls in

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
// JIT Block Descriptors\n"
    ^ jit_descriptors_code
    ^ "\n\n"
    ^ render_top_decl (emit_rd_jit_main_def ())
    ^ "\n" in

  {
    cpp_runtime_source = rd_jit_hdr;
    runner_source = runner_cpp;
    rns_moduli = (Rns.m1, Rns.m2, Rns.m3, Rns.m4);
    bytecode = base_pkg.bytecode;
    metrics = base_pkg.metrics;
  }
