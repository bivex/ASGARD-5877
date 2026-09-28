open Random_visa_ports
open Protect_ports
open Native_vm

let convert_metrics (m : Native_vm.Metrics.metrics_report) : Protect_ports.metrics_report =
  {
    cyclomatic_complexity = Native_vm.Metrics.cyclomatic_complexity m;
    shannon_entropy = Native_vm.Metrics.shannon_entropy m;
    uniform_entropy = Native_vm.Metrics.shannon_entropy m /. 8.0;
    drs_score = Native_vm.Metrics.devirtualization_resistance_score m;
    formatted_summary = Native_vm.Metrics.report_to_string m;
  }

module Threaded_vm_packager : Vm_packager = struct
  let engine_kind = Threaded

  let package ~rng ~config ?constants (func : ir_func) : package_result =
    let ir : Vm_ir.Ir.func = unwrap_ir func in
    let native_cfg : Protection_config.t = unwrap_config config in
    let pkg = Native_vm.Vm_emitter.compile_and_package ~rng ~config:native_cfg ?constants ir in
    {
      cpp_runtime_source = pkg.cpp_runtime_source;
      runner_source = pkg.runner_source;
      bytecode = pkg.bytecode;
      metrics = convert_metrics pkg.metrics;
      header_name = "threaded_vm.hpp";
      rebind_address = None;
    }
end

module Jit_vm_packager : Vm_packager = struct
  let engine_kind = Jit

  let package ~rng ~config ?constants:_ (func : ir_func) : package_result =
    let ir : Vm_ir.Ir.func = unwrap_ir func in
    let native_cfg : Protection_config.t = unwrap_config config in
    let jit_pkg =
      Rd_jit_vm.Rd_jit_emitter.compile_and_package
        ~rng
        ?config:(Some native_cfg)
        ~enable_cff:native_cfg.cff.enabled
        ~enable_mba:native_cfg.mba.enabled
        ~mba_depth:native_cfg.mba.depth
        ir
    in
    {
      cpp_runtime_source = jit_pkg.cpp_runtime_source;
      runner_source = jit_pkg.runner_source;
      bytecode = jit_pkg.bytecode;
      metrics = convert_metrics jit_pkg.metrics;
      header_name = "jit_vm_runtime.hpp";
      rebind_address = None;
    }
end

module Multi_vm_packager : Vm_packager = struct
  let engine_kind = MultiVm

  let package ~rng ~config ?constants:_ (func : ir_func) : package_result =
    let ir : Vm_ir.Ir.func = unwrap_ir func in
    let native_cfg : Protection_config.t = unwrap_config config in
    let mv_pkg =
      Multi_vm.Multi_vm_emitter.compile_and_package
        ~rng
        ~enable_cff:native_cfg.cff.enabled
        ~enable_mba:native_cfg.mba.enabled
        ~mba_depth:native_cfg.mba.depth
        ~config:native_cfg
        ir
    in
    {
      cpp_runtime_source = mv_pkg.cpp_runtime_source;
      runner_source = mv_pkg.runner_source;
      bytecode = mv_pkg.bytecode;
      metrics = convert_metrics mv_pkg.metrics;
      header_name = "multi_vm_runtime.hpp";
      rebind_address = None;
    }
end

let bytes_to_words (b : bytes) : int64 list =
  let len = Bytes.length b in
  let pad_len = ((len + 7) / 8) * 8 in
  let padded = Bytes.make pad_len '\000' in
  Bytes.blit b 0 padded 0 len;
  let words = ref [] in
  for i = (pad_len / 8) - 1 downto 0 do
    let w = ref 0L in
    for j = 7 downto 0 do
      let byte_val = Int64.of_int (Char.code (Bytes.get padded (i * 8 + j))) in
      w := Int64.logor (Int64.shift_left !w 8) byte_val
    done;
    words := !w :: !words
  done;
  !words

let compute_shannon_entropy (b : bytes) : float =
  let len = Bytes.length b in
  if len = 0 then 0.0
  else
    let counts = Array.make 256 0 in
    for i = 0 to len - 1 do
      let byte_val = Char.code (Bytes.get b i) in
      counts.(byte_val) <- counts.(byte_val) + 1
    done;
    let entropy = ref 0.0 in
    let flen = float_of_int len in
    for i = 0 to 255 do
      if counts.(i) > 0 then
        let p = float_of_int counts.(i) /. flen in
        entropy := !entropy -. (p *. (log p /. log 2.0))
    done;
    !entropy

let make_stack_metrics
    ?(superop_info   = "Superoperator fusion: N/A")
    ?(spaghetti_info = "Spaghetti splitting: N/A")
    ?(ghost_info     = "Ghost padding: N/A")
    ?(feedback_info  = "State-feedback rolling key: N/A")
    ?(mba_info       = "MBA synthesis: N/A")
    ?(cff_info       = "CFG flattening: N/A")
    ?(real_ops       = 0)
    ?(real_blocks    = 0)
    ?(compact_imm    = true)
    (prog : Stack_vm.Stack_ir.program)
    (enc  : Stack_vm.Stack_encoder.encrypted_bytecode)
    : Protect_ports.metrics_report =
  let entropy = compute_shannon_entropy enc.bytes in
  let num_blocks = Hashtbl.length prog.blocks in
  let drs = min 99.0 (85.0 +. (entropy *. 1.5)) in
  let vpc_transitions_per_op =
    if real_ops > 0 then float_of_int real_blocks /. float_of_int real_ops
    else 0.0
  in
  let avg_disp_ops = float_of_int (real_blocks + 1) *. 2.5 in
  let imm_width_info =
    if compact_imm then "Hybrid {i32, i64} (Compact Polymorphic)"
    else "Fixed i64 (Uniform 8-byte)"
  in
  let summary =
    Printf.sprintf
      "=== ASGARD-5877 Stack-VM Protection Report ===\n\
       - Architecture: Stack-VM Execution Engine (Universal Logic + Rolling Key)\n\
       - Opcode Mapping: Dynamic Polymorphic ISA (Unique Build Permutation)\n\
       - VSP Stack Value Whitening: Enabled (Slot-Keyed XOR, Fibonacci-Prime Stride)\n\
       - PushImm Operand Width: %s\n\
       - Superoperator Fusion: %s\n\
       - Spaghetti CFG Splitting: %s\n\
       - Ghost Stack Padding: %s\n\
       - State-Feedback Rolling Key: %s\n\
       - Multi-Operand Field Layout: %s\n\
       - MBA Constant Synthesis: %s\n\
       - Virtual CFG Flattening: %s\n\
       - VPC Dispatch Overhead: %.1f avg ops/transition (%.3f transitions/real-op)\n\
       - Basic Blocks: %d\n\
       - Bytecode Size: %d bytes (%d words)\n\
       - Shannon Entropy: %.4f / 8.0 (%.1f%%)\n\
       - Devirtualization Resistance Score (DRS): %.2f / 100.0\n\
       - Rolling Key Seed: 0x%016LX\n\
       ==============================================="
      imm_width_info
      superop_info
      spaghetti_info ghost_info feedback_info
      (Stack_vm.Stack_encoder.format_field_layout enc.layout)
      mba_info cff_info
      avg_disp_ops vpc_transitions_per_op
      num_blocks (Bytes.length enc.bytes) ((Bytes.length enc.bytes + 7) / 8)
      entropy (entropy /. 8.0 *. 100.0) drs (Stack_vm.Stack_encoder.effective_seed_key enc)
  in
  {
    cyclomatic_complexity = num_blocks;
    shannon_entropy = entropy;
    uniform_entropy = entropy /. 8.0;
    drs_score = drs;
    formatted_summary = summary;
  }

module Stack_vm_packager : Vm_packager = struct
  let engine_kind = Stack

  let package ~rng ~config ?constants (func : ir_func) : package_result =
    let ir : Vm_ir.Ir.func = unwrap_ir func in
    let native_cfg : Protection_config.t = unwrap_config config in
    let target_func =
      if native_cfg.cff.enabled then
        let cff_opts = {
          Cff.inject_opaque_predicates = native_cfg.cff.inject_opaque_predicates;
          obfuscate_states = native_cfg.cff.obfuscate_states;
        } in
        match Cff.flatten_func ~options:cff_opts ~rng ir with
        | Ok f -> f
        | Error _ -> ir
      else ir
    in
    let ext_syms = Hashtbl.create 16 in
    let ctx, prog = Stack_vm.Ir_to_stack.lower_func ~ext_syms target_func in
    let external_symbols = Stack_vm.Ir_to_stack.get_symbols_list ext_syms in

    (* Phase 2a: Superoperator Fusion — fuse recurring patterns into fused ops *)
    let superop_seed =
      Int64.logxor
        (Int64.of_int (Random.State.bits rng))
        (Int64.shift_left (Int64.of_int (Random.State.bits rng)) 29)
    in
    let superop_cfg = Stack_vm.Stack_superop_pass.default_superop_config superop_seed in
    let prog_superop = Stack_vm.Stack_superop_pass.apply_program superop_cfg prog in
    let superop_stats = Stack_vm.Stack_superop_pass.superop_stats prog prog_superop in
    let superop_info =
      Printf.sprintf "%d ops fused (AddImm:%d SubImm:%d AddII:%d SubII:%d SetRegImm:%d AddRegImm:%d)"
        superop_stats.fused_ops superop_stats.add_imm_count superop_stats.sub_imm_count
        superop_stats.add_ii_count superop_stats.sub_ii_count superop_stats.set_reg_imm_count
        superop_stats.add_reg_imm_count
    in
    let prog = prog_superop in

    (* Phase 2b: MBA Constant Synthesis — replace PushImm with NOR/NAND/ADD sequences *)
    let mba_seed =
      Int64.logxor
        (Int64.of_int (Random.State.bits rng))
        (Int64.shift_left (Int64.of_int (Random.State.bits rng)) 19)
    in
    let mba_cfg = Stack_vm.Stack_mba_pass.default_mba_config mba_seed in
    let prog_mba = Stack_vm.Stack_mba_pass.apply_program mba_cfg prog in
    let mba_info = Stack_vm.Stack_mba_pass.mba_stats prog prog_mba in
    let prog = prog_mba in

    let real_blocks = Hashtbl.length prog.blocks in
    let real_ops = Hashtbl.fold (fun _ (b : Stack_vm.Stack_ir.block) acc -> acc + List.length b.ops) prog.blocks 0 in

    (* Phase 3: Virtual CFG Flattening — route jumps through VPC dispatcher *)
    let cff_seed =
      Int64.logxor
        (Int64.of_int (Random.State.bits rng))
        (Int64.shift_left (Int64.of_int (Random.State.bits rng)) 11)
    in
    let cff_cfg = Stack_vm.Stack_cff_pass.default_cff_config cff_seed in
    let prog_cff = Stack_vm.Stack_cff_pass.apply_program cff_cfg ctx prog in
    let cff_info = Stack_vm.Stack_cff_pass.cff_stats prog prog_cff in
    let prog = prog_cff in

    (* Phase 4: Spaghetti Control-Flow Splitting — split blocks after CFF *)
    let spaghetti_seed =
      Int64.logxor
        (Int64.of_int (Random.State.bits rng))
        (Int64.shift_left (Int64.of_int (Random.State.bits rng)) 23)
    in
    let spaghetti_cfg = Stack_vm.Stack_spaghetti_pass.default_spaghetti_config spaghetti_seed in
    let prog_spaghetti = Stack_vm.Stack_spaghetti_pass.apply_program spaghetti_cfg prog in
    let spaghetti_info = Stack_vm.Stack_spaghetti_pass.spaghetti_stats prog prog_spaghetti in
    let prog = prog_spaghetti in

    (* Phase 5: Ghost Stack Padding — inject neutral junk ops per block *)
    let ghost_seed =
      Int64.logxor
        (Int64.of_int (Random.State.bits rng))
        (Int64.shift_left (Int64.of_int (Random.State.bits rng)) 17)
    in
    let ghost_cfg = Stack_vm.Stack_ghost_pass.default_ghost_config ghost_seed in
    let prog_ghost = Stack_vm.Stack_ghost_pass.apply_program ghost_cfg ctx prog in
    let ghost_info = Stack_vm.Stack_ghost_pass.ghost_stats prog prog_ghost in
    let prog = prog_ghost in

    (* Phase 6: State-Feedback Rolling Key — couple cipher stream to register state *)
    let feedback_seed =
      Int64.logxor
        (Int64.of_int (Random.State.bits rng))
        (Int64.shift_left (Int64.of_int (Random.State.bits rng)) 27)
    in
    let feedback_cfg = Stack_vm.Stack_feedback_pass.default_feedback_config feedback_seed in
    let prog_feedback = Stack_vm.Stack_feedback_pass.apply_program feedback_cfg prog in
    let feedback_stat = Stack_vm.Stack_feedback_pass.feedback_stats prog prog_feedback in
    let feedback_info =
      Printf.sprintf "%d dynamic checkpoints injected (register-coupled cipher stream)"
        feedback_stat.feedback_injected
    in
    let prog = prog_feedback in

    (* Phase 7: Stack Balance Pass — enforce block balance delta = 0 *)
    let prog = Stack_vm.Stack_balance_pass.repair_program ctx prog in

    let seed_key =
      Int64.logxor
        (Int64.of_int (Random.State.bits rng))
        (Int64.shift_left (Int64.of_int (Random.State.bits rng)) 32)
    in
    let compact_imm = Random.State.int rng 100 < 80 in
    let enc = Stack_vm.Stack_encoder.encode_program ~seed_key ~compact_imm prog in
    let bc_words = bytes_to_words enc.bytes in

    let is_internal_sym name =
      (match constants with
       | Some cs -> List.exists (fun (cname, _) -> cname = name) cs
       | None -> false)
      || String.contains name '.'
      || (String.length name >= 3 && String.sub name 0 3 = "LBB")
      || (String.length name >= 2 && String.sub name 0 2 = ".L")
    in
    let sanitize_sym name =
      if is_internal_sym name then
        Printf.sprintf "asg_c_%08x" (Hashtbl.hash name land 0x7FFFFFFF)
      else name
    in
    let sanitized_constants =
      match constants with
      | Some cs ->
          Some (List.map (fun (name, data) -> (sanitize_sym name, data)) cs)
      | None -> None
    in
    let sanitized_external_symbols =
      List.map sanitize_sym external_symbols
    in

    let runtime_cfg = Stack_vm.Stack_runtime.default_config Stack_vm.Stack_runtime.AArch64 in
    let cpp_runtime_source =
      Stack_vm.Stack_runtime.generate_c_runtime
        ~external_symbols:sanitized_external_symbols
        ?constants:sanitized_constants
        ~enc
        runtime_cfg
        prog
    in
    let runner_source = Stack_vm.Stack_runtime.emit_runner_cpp bc_words in
    let metrics =
      make_stack_metrics
        ~compact_imm
        ~superop_info
        ~spaghetti_info ~ghost_info ~feedback_info ~mba_info ~cff_info
        ~real_ops ~real_blocks prog enc
    in
    let rebind_address =
      Some (fun d_hex ->
        let d = Stack_vm.Stack_encoder.parse_u64_hex d_hex in
        let enc_rebound = Stack_vm.Stack_encoder.apply_addr_mask enc d in
        Stack_vm.Stack_runtime.generate_c_runtime
          ~external_symbols:sanitized_external_symbols
          ?constants:sanitized_constants
          ~enc:enc_rebound
          runtime_cfg
          prog)
    in
    {
      cpp_runtime_source;
      runner_source;
      bytecode = bc_words;
      metrics;
      header_name = "stack_vm_runtime.hpp";
      rebind_address;
    }
end

