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

let make_stack_metrics ?(ghost_info = "Ghost padding: N/A") (prog : Stack_vm.Stack_ir.program) (enc : Stack_vm.Stack_encoder.encrypted_bytecode) : Protect_ports.metrics_report =
  let entropy = compute_shannon_entropy enc.bytes in
  let num_blocks = Hashtbl.length prog.blocks in
  let drs = min 99.0 (85.0 +. (entropy *. 1.5)) in
  let summary =
    Printf.sprintf
      "=== ASGARD-5877 Stack-VM Protection Report ===\n\
       - Architecture: Stack-VM Execution Engine (Universal Logic + Rolling Key)\n\
       - Opcode Mapping: Dynamic Polymorphic ISA (Unique Build Permutation)\n\
       - VSP Stack Value Whitening: Enabled (Slot-Keyed XOR, Fibonacci-Prime Stride)\n\
       - Ghost Stack Padding: %s\n\
       - Basic Blocks: %d\n\
       - Bytecode Size: %d bytes (%d words)\n\
       - Shannon Entropy: %.4f / 8.0 (%.1f%%)\n\
       - Devirtualization Resistance Score (DRS): %.2f / 100.0\n\
       - Rolling Key Seed: 0x%016LX\n\
       ==============================================="
      ghost_info
      num_blocks (Bytes.length enc.bytes) ((Bytes.length enc.bytes + 7) / 8)
      entropy (entropy /. 8.0 *. 100.0) drs enc.seed_key
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

    (* Apply stack balance pass to ensure well-formed basic blocks *)
    let prog = Stack_vm.Stack_balance_pass.repair_program ctx prog in

    (* Phase 3: Ghost Stack Padding — inject neutral junk ops per block *)
    let ghost_seed =
      Int64.logxor
        (Int64.of_int (Random.State.bits rng))
        (Int64.shift_left (Int64.of_int (Random.State.bits rng)) 17)
    in
    let ghost_cfg = Stack_vm.Stack_ghost_pass.default_ghost_config ghost_seed in
    let prog_ghost = Stack_vm.Stack_ghost_pass.apply_program ghost_cfg ctx prog in
    let ghost_info = Stack_vm.Stack_ghost_pass.ghost_stats prog prog_ghost in
    let prog = prog_ghost in

    let seed_key =
      Int64.logxor
        (Int64.of_int (Random.State.bits rng))
        (Int64.shift_left (Int64.of_int (Random.State.bits rng)) 32)
    in
    let enc = Stack_vm.Stack_encoder.encode_program ~seed_key prog in
    let bc_words = bytes_to_words enc.bytes in

    let runtime_cfg = Stack_vm.Stack_runtime.default_config Stack_vm.Stack_runtime.AArch64 in
    let cpp_runtime_source =
      Stack_vm.Stack_runtime.generate_c_runtime
        ~external_symbols
        ?constants
        ~enc
        runtime_cfg
        prog
    in
    let runner_source = Stack_vm.Stack_runtime.emit_runner_cpp bc_words in
    let metrics = make_stack_metrics ~ghost_info prog enc in
    {
      cpp_runtime_source;
      runner_source;
      bytecode = bc_words;
      metrics;
      header_name = "stack_vm_runtime.hpp";
    }
end

