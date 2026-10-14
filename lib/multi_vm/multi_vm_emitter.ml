open Vm_ir

type multi_vm_package = {
  bridge : Bridge.affine_bridge;
  partition : Partitioner.partition_report;
  cpp_runtime_source : string;
  runner_source : string;
  bytecode : int64 list;
  metrics : Native_vm.Metrics.metrics_report;
}

let inject_bridge_transitions (bridge : Bridge.affine_bridge) (partition : Partitioner.partition_report) (f : Ir.func) : Ir.func * int =
  let digest = Bridge.initial_digest bridge in
  if partition.inter_vm_transitions = 0 then
    (* Homogeneous engine or single block: inject a zero-bridge roundtrip (Math -> Flow -> Math) *)
    let new_blocks = Hashtbl.create (Hashtbl.length f.cfg.blocks) in
    Hashtbl.iter (fun id (b : Ir.basic_block) ->
      let instrs =
        match List.rev b.instrs with
        | (Ir.Ret as ret) :: rest ->
            List.rev (ret :: Ir.Bridge_to_math digest :: Ir.Bridge_to_flow digest :: rest)
        | (Ir.Vm_exit as ex) :: rest ->
            List.rev (ex :: Ir.Bridge_to_math digest :: Ir.Bridge_to_flow digest :: rest)
        | other ->
            other @ [ Ir.Bridge_to_flow digest; Ir.Bridge_to_math digest ]
      in
      Hashtbl.replace new_blocks id { b with instrs }
    ) f.cfg.blocks;
    ({ f with cfg = { f.cfg with blocks = new_blocks } }, 2)
  else
    (* Multi-block with cross-engine transitions *)
    let block_engine = Hashtbl.create 16 in
    List.iter (fun (pb : Partitioner.partitioned_block) ->
      Hashtbl.replace block_engine pb.block.id pb.engine
    ) partition.blocks;

    let trans_count = ref 0 in
    let new_blocks = Hashtbl.create (Hashtbl.length f.cfg.blocks) in
    Hashtbl.iter (fun id (b : Ir.basic_block) ->
      let cur_eng = Hashtbl.find_opt block_engine id in
      let is_math = cur_eng = Some Partitioner.Engine_Math in
      let rev_acc = ref [] in
      List.iter (fun (instr : Ir.instr) ->
        match instr with
        | Ir.Jmp (BlockId target_id) ->
            let target_eng = Hashtbl.find_opt block_engine target_id in
            if target_eng <> cur_eng && cur_eng <> None && target_eng <> None then begin
              incr trans_count;
              if is_math then
                rev_acc := Ir.Bridge_to_flow digest :: !rev_acc
              else
                rev_acc := Ir.Bridge_to_math digest :: !rev_acc
            end;
            rev_acc := instr :: !rev_acc
        | Ir.Jcc { cond = _; target_true = BlockId tid; target_false = BlockId fid } ->
            let t_eng = Hashtbl.find_opt block_engine tid in
            let f_eng = Hashtbl.find_opt block_engine fid in
            if (t_eng <> cur_eng || f_eng <> cur_eng) && cur_eng <> None then begin
              incr trans_count;
              if is_math then
                rev_acc := Ir.Bridge_to_flow digest :: !rev_acc
              else
                rev_acc := Ir.Bridge_to_math digest :: !rev_acc
            end;
            rev_acc := instr :: !rev_acc
        | _ -> rev_acc := instr :: !rev_acc
      ) b.instrs;
      Hashtbl.replace new_blocks id { b with instrs = List.rev !rev_acc }
    ) f.cfg.blocks;
    ({ f with cfg = { f.cfg with blocks = new_blocks } }, !trans_count)

let emit_multi_vm_runner_main_def ~math_blocks ~flow_blocks ~inter_vm_transitions () : Cpp_codegen.Cpp_ast.top_decl =
  let open Cpp_codegen.Cpp_ast in
  let open Cpp_codegen.Cpp_dsl in
  func_decl Int32 "main" [(Int32, "argc"); (Ptr (Ptr (StructType "char")), "argv")] [
    raw "std::cout << \"[ASGARD-MULTI-VM] Initializing In-Place Heterogeneous Dual-VM Runtime...\\n\";";
    raw (Printf.sprintf "std::cout << \"  Engine 1: Math-VM (Register/RNS Oriented, \" << %d << \" blocks)\\n\";" math_blocks);
    raw (Printf.sprintf "std::cout << \"  Engine 2: Flow-VM (Stack/CFF Markov Oriented, \" << %d << \" blocks)\\n\";" flow_blocks);
    raw (Printf.sprintf "std::cout << \"  Zero-Bridge Transitions: \" << %d << \" affine morphing junctions\\n\";" inter_vm_transitions);
    raw "asgard_multi_vm::SharedVMContext shared_ctx = {};";
    expr_stmt (call "shared_ctx.math.init" [var "ASGARD_INITIAL_DIGEST"]);
    raw "vanguard_threaded_vm::VMContext base_ctx = {};";
    expr_stmt (call "base_ctx.init" []);
    let_u64 "init_rdi" (ternary (var "argc" >~ i32 1) (c_cast UInt64 (call "atoll" [Index (var "argv", i32 1)])) (u64 42L));
    expr_stmt (call "base_ctx.set_rdi" [var "init_rdi"]);
    raw "auto t0 = std::chrono::high_resolution_clock::now();";
    expr_stmt (call "vanguard_threaded_vm::execute_threaded" [var "base_ctx"; var "embedded_bytecode"; var "embedded_bytecode_len"]);
    raw "auto t1 = std::chrono::high_resolution_clock::now();";
    raw "double elapsed_us = std::chrono::duration<double, std::micro>(t1 - t0).count();";
    let_u64 "res" (call "base_ctx.get_rax" []);
    raw "std::cout << \"[ASGARD-MULTI-VM] Execution Successful!\\n\";";
    raw "std::cout << \"  Result (RAX): \" << res << \" (0x\" << std::hex << res << std::dec << \")\\n\";";
    raw "std::cout << \"  Execution Time: \" << elapsed_us << \" us\\n\";";
    ret (i32 0);
  ]

let compile_and_package ~rng ?(enable_cff = true) ?(enable_mba = true) ?(mba_depth = 2) ?config ?constants (f : Ir.func) : multi_vm_package =
  let bridge = Bridge.generate_bridge rng in
  let partition = Partitioner.partition_function f in
  let (bridged_func, actual_transitions) = inject_bridge_transitions bridge partition f in
  let updated_partition = { partition with inter_vm_transitions = actual_transitions } in

  let base_pkg =
    Native_vm.Vm_emitter.compile_and_package
      ~rng
      ~enable_cff
      ~enable_mba
      ~mba_depth
      ?config
      ?constants
      bridged_func
  in

  let bridge_cpp = Bridge.emit_cpp_bridge_code bridge in

  let hdr_models = [
    ("bridge_cpp", Jingoo.Jg_types.Tstr bridge_cpp);
    ("asgard_multi_vm_namespace", Jingoo.Jg_types.Tstr (Multi_vm_context_emitter.emit_asgard_multi_vm_source ()));
    ("base_runtime_source", Jingoo.Jg_types.Tstr base_pkg.cpp_runtime_source);
  ] in
  let multi_vm_hdr = Multi_vm_templates.render Multi_vm_templates.multi_vm_header_template hdr_models in

  let open Cpp_codegen.Cpp_ast in
  let open Cpp_codegen.Cpp_dsl in
  let open Cpp_codegen.Cpp_printer in
  let runner_decls = [
    include_local "multi_vm_runtime.hpp";
    include_sys "iostream";
    include_sys "vector";
    include_sys "chrono";
    global_var ~is_extern_c:true ~is_weak:true ~is_const:true
      (Array (UInt64, 0)) "embedded_bytecode"
      ~init:(init_list (List.map u64 base_pkg.bytecode));
    global_var ~is_extern_c:true ~is_weak:true ~is_const:true
      SizeT "embedded_bytecode_len"
      ~init:(sizeof_expr (var "embedded_bytecode") /~ sizeof_expr (idx (var "embedded_bytecode") (i32 0)));
    emit_multi_vm_runner_main_def
      ~math_blocks:updated_partition.math_blocks
      ~flow_blocks:updated_partition.flow_blocks
      ~inter_vm_transitions:updated_partition.inter_vm_transitions
      ();
  ] in
  let runner_cpp = render_top_decls runner_decls ^ "\n" in

  {
    bridge;
    partition = updated_partition;
    cpp_runtime_source = multi_vm_hdr;
    runner_source = runner_cpp;
    bytecode = base_pkg.bytecode;
    metrics = base_pkg.metrics;
  }
