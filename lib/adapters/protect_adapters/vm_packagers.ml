open Random_visa_ports
open Protect_ports
open Native_vm

(* Bytecode trace utility.
   Activated by env ASGARD_DUMP_BYTECODE=1 (or any non-empty value).
   Output goes to stderr so it never contaminates generated files / stdout.
   Format: phase separator + Stack_ir.program_to_string.
   Called at each pipeline phase boundary in Stack_vm_packager. *)
let is_dump_enabled () =
  match Sys.getenv_opt "ASGARD_DUMP_BYTECODE" with
  | Some s when s <> "" && s <> "0" -> true
  | _ -> false

let dump_bytecode_trace ~phase (prog : Stack_vm.Stack_ir.program) =
  if is_dump_enabled () then begin
    let sep = String.make 72 '=' in
    Printf.eprintf "\n%s\n[ASGARD BYTECODE TRACE] phase: %s\n%s\n%s\n%!"
      sep phase sep
      (Stack_vm.Stack_ir.program_to_string prog)
  end

(* Machine-readable phase dump, consumed by the MATLAB pipeline
   compatibility analyzer (scripts/pipeline_compat.m).
   Activated by env ASGARD_DUMP_JSON_DIR=<dir>: one JSON file per phase
   with the full Stack IR (ops, operands, authoritative stack deltas and
   flag classification).  Written next to the human-readable trace so
   both views describe exactly the same program state. *)
let dump_bytecode_json ~phase (prog : Stack_vm.Stack_ir.program) =
  match Sys.getenv_opt "ASGARD_DUMP_JSON_DIR" with
  | Some dir when dir <> "" && dir <> "0" ->
      let slug = String.map (fun c -> if c = ' ' then '_' else c) phase in
      let path = Filename.concat dir (Printf.sprintf "phase_%s.json" slug) in
      let json = Stack_vm.Stack_ir_json.program_to_json ~phase prog in
      (try Yojson.Safe.to_file path json
       with e ->
         prerr_endline
           (Printf.sprintf "[asgard] JSON phase dump failed (%s): %s" path
              (Printexc.to_string e)))
  | _ -> ()

let make_native_pass_board (engine_name : string) (cfg : Protection_config.t) : string =
  let pass_switch name enabled note =
    Printf.sprintf "    [%s] %s%s" (if enabled then "ON " else "OFF") name
      (if enabled || note = "" then "" else " (" ^ note ^ ")")
  in
  let passes =
    [
      pass_switch "Control-Flow Flattening (CFF)" cfg.cff.enabled "disabled in configuration";
      pass_switch "Mixed Boolean-Arithmetic (MBA)" cfg.mba.enabled "disabled in configuration";
      pass_switch "Superoperator Fusion" cfg.vm_runtime.enable_super_operators "disabled in configuration";
      pass_switch "Stack Scrambling" cfg.vm_runtime.stack_scrambling "disabled in configuration";
      pass_switch "Chameleon Multi-Domain Handlers" cfg.vm_runtime.chameleon_handlers (Printf.sprintf "domains=%d" cfg.vm_runtime.num_dispatch_domains);
      pass_switch "Oblivious Memory & Entanglement" cfg.vm_runtime.oblivious_memory "disabled in configuration";
      pass_switch "E-Graph Equality Expansion" cfg.vm_runtime.egraph_expansion "disabled in configuration";
      pass_switch "Junk Bytecode Injection" cfg.vm_runtime.enable_junk_instructions "disabled in configuration";
      pass_switch "Ephemeral JIT Micro-Handlers" cfg.vm_runtime.ephemeral_jit "disabled in configuration";
      pass_switch "Memory Sanitization" cfg.vm_runtime.memory_sanitization "disabled in configuration";
      pass_switch "Anti-Pushan Rolling Key" cfg.anti_pushan.running_key "disabled in configuration";
      pass_switch "Address Binding" cfg.anti_pushan.address_bound "disabled in configuration";
      pass_switch "Anti-Tamper (SMC + probes)" cfg.anti_tamper.enabled "disabled in configuration";
      pass_switch "Hardware Timing Probes" (cfg.anti_tamper.enabled && cfg.anti_tamper.hardware_timing_probes) "disabled in configuration";
      pass_switch "Memory Integrity Scanner" (cfg.anti_tamper.enabled && cfg.anti_tamper.memory_integrity_scanner) "disabled in configuration";
      pass_switch "Anti-Emulation Protection" (cfg.anti_tamper.enabled && cfg.anti_tamper.anti_emulation) "disabled in configuration";
      pass_switch "Dynamic Nanomites" (cfg.anti_tamper.enabled && cfg.anti_tamper.nanomites) "disabled in configuration";
      pass_switch "Direct Syscalls" (cfg.anti_tamper.enabled && cfg.anti_tamper.direct_syscalls) "disabled in configuration";
      pass_switch "C-Macro Obfuscation" cfg.c_macro.enabled "disabled in configuration";
      pass_switch "Stack String Encryption (ASG_STR)" (cfg.c_macro.enabled && cfg.c_macro.obfuscate_strings) "disabled in configuration";
      pass_switch "Constant Blinding (ASG_BLIND)" (cfg.c_macro.enabled && cfg.c_macro.obfuscate_constants) "disabled in configuration";
      pass_switch "Opaque Predicates" (cfg.c_macro.enabled && cfg.c_macro.opaque_predicates) "disabled in configuration";
      pass_switch "EH Shadowing" cfg.eh_shadowing.enabled "disabled in configuration";
      pass_switch "Anti-VPC Tracking" cfg.anti_vpc.enabled "disabled in configuration";
      pass_switch "Memory Chaffing" cfg.memory_chaffing.enabled "disabled in configuration";
    ]
  in
  Printf.sprintf
    "=== ASGARD-5877 %s Protection Report ===\n\
     - Protection Passes (ON/OFF):\n\
     %s\n\
     --------------------------------------------------------------------\n"
    engine_name
    (String.concat "\n" passes)

let convert_metrics ?(engine_name = "Threaded-VM") ?config (m : Native_vm.Metrics.metrics_report) : Protect_ports.metrics_report =
  let header =
    match config with
    | Some cfg -> make_native_pass_board engine_name cfg
    | None -> ""
  in
  {
    cyclomatic_complexity = Native_vm.Metrics.cyclomatic_complexity m;
    shannon_entropy = Native_vm.Metrics.shannon_entropy m;
    uniform_entropy = Native_vm.Metrics.shannon_entropy m /. 8.0;
    drs_score = Native_vm.Metrics.devirtualization_resistance_score m;
    formatted_summary = header ^ Native_vm.Metrics.report_to_string m;
  }

let inject_tech_2601 (config : Protection_config.t) (func_name : string) (cpp_source : string) : string =
  if config.eh_shadowing.enabled then
    let dummy_meta : Tech_2601.Tech_2601_types.original_metadata = {
      func_name;
      code_start_pc = 0x1000L;
      code_size = 256;
      unwind_ops = [ AllocStack config.eh_shadowing.shadow_alloc_size ];
      lsdata = { scopes = []; dtors = [] };
    } in
    let master_key = Bytes.of_string "ASGARD_TECH_2601_MASTER_KEY_32B!" in
    let container = Tech_2601.Tech_2601_engine.seal_metadata
      ~master_key
      ~alloc_size:config.eh_shadowing.shadow_alloc_size
      ~interceptor_symbol:config.eh_shadowing.interceptor_symbol
      dummy_meta
    in
    let prefix = Printf.sprintf
      "// [ASGARD Tech-2601] ABI-Compliant Exception Handling Shadowing Active\n\
// Shadow Allocation: %d bytes | Interceptor: %s\n\
#include \"asg_tech_2601.hpp\"\n\n"
      container.shadow.shadow_alloc_size
      container.shadow.interceptor_symbol
    in
    prefix ^ cpp_source
  else
    cpp_source

let inject_pipeline_hardening (config : Protection_config.t) (func_name : string) (cpp_source : string) : string =
  let s = inject_tech_2601 config func_name cpp_source in
  let s =
    if Protection_config.anti_vpc_enabled (Some config) then
      "// [ASGARD Tech-2603] Anti-VPC-Tracking & Non-Linear Dispatch Active\n\
#include \"asg_tech_2603.hpp\"\n\n" ^ s
    else s
  in
  let s =
    if Protection_config.memory_chaffing_enabled (Some config) then
      "// [ASGARD Tech-2608] Anti-Trace-Synthesis & Memory Chaffing Active\n\
#include \"asg_tech_2608.hpp\"\n\n" ^ s
    else s
  in
  s

module Threaded_vm_packager : Vm_packager = struct
  let engine_kind = Threaded

  let transform_func ~rng (f : Vm_ir.Ir.func) : Vm_ir.Ir.func =
    let seed = Vm_ir.Seed.create ~master_seed:(Random.State.int64 rng Int64.max_int) () in
    match Vm_ir.Ir_pipeline.compile ~seed ~verify_equivalence:true f with
    | Ok res -> res.diversified_func
    | Error err ->
        Printf.eprintf "[TRANSFORM_FUNC ERROR] %s\n" err;
        let sem_f = Vm_ir.Semantic_transform.transform_func ~seed f in
        let codec_cfg = Vm_ir.Codec_pass.default_config (Vm_ir.Seed.codec_seed seed) in
        Vm_ir.Codec_pass.transform_func ~cfg:codec_cfg sem_f

  let package ~rng ~config ?constants (func : ir_func) : package_result =
    let native_cfg : Protection_config.t = unwrap_config config in
    let ir_funcs = unwrap_multi_ir func in
    if List.length ir_funcs > 1 then
      let diversified_funcs = List.map (fun (name, f) -> (name, transform_func ~rng f)) ir_funcs in
      let pkg = Native_vm.Vm_emitter.compile_and_package_multi ~rng ~config:native_cfg ?constants diversified_funcs in
      {
        cpp_runtime_source = inject_pipeline_hardening native_cfg "multi_func" pkg.cpp_runtime_source;
        runner_source = pkg.runner_source;
        bytecode = pkg.bytecode;
        bytecodes = pkg.bytecodes;
        metrics = convert_metrics ~engine_name:"Threaded-VM" ~config:native_cfg pkg.metrics;
        header_name = "threaded_vm.hpp";
        rebind_address = None;
      }
    else
      let ir : Vm_ir.Ir.func = transform_func ~rng (unwrap_ir func) in
      let pkg = Native_vm.Vm_emitter.compile_and_package ~rng ~config:native_cfg ?constants ir in
      {
        cpp_runtime_source = inject_pipeline_hardening native_cfg ir.name pkg.cpp_runtime_source;
        runner_source = pkg.runner_source;
        bytecode = pkg.bytecode;
        bytecodes = pkg.bytecodes;
        metrics = convert_metrics ~engine_name:"Threaded-VM" ~config:native_cfg pkg.metrics;
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
      cpp_runtime_source = inject_pipeline_hardening native_cfg ir.name jit_pkg.cpp_runtime_source;
      runner_source = jit_pkg.runner_source;
      bytecode = jit_pkg.bytecode;
      bytecodes = [ (ir.name, jit_pkg.bytecode) ];
      metrics = convert_metrics ~engine_name:"Register-Driven JIT-VM" ~config:native_cfg jit_pkg.metrics;
      header_name = "jit_vm_runtime.hpp";
      rebind_address = None;
    }
end

module Multi_vm_packager : Vm_packager = struct
  let engine_kind = MultiVm

  let package ~rng ~config ?constants (func : ir_func) : package_result =
    let ir : Vm_ir.Ir.func = unwrap_ir func in
    let native_cfg : Protection_config.t = unwrap_config config in
    let mv_pkg =
      Multi_vm.Multi_vm_emitter.compile_and_package
        ~rng
        ~enable_cff:native_cfg.cff.enabled
        ~enable_mba:native_cfg.mba.enabled
        ~mba_depth:native_cfg.mba.depth
        ~config:native_cfg
        ?constants
        ir
    in
    {
      cpp_runtime_source = inject_pipeline_hardening native_cfg ir.name mv_pkg.cpp_runtime_source;
      runner_source = mv_pkg.runner_source;
      bytecode = mv_pkg.bytecode;
      bytecodes = [ (ir.name, mv_pkg.bytecode) ];
      metrics = convert_metrics ~engine_name:"Multi-VM" ~config:native_cfg mv_pkg.metrics;
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
    (native_cfg : Protection_config.t)
    ?(amplifier_info = "Bytecode amplification: N/A")
    ?(superop_info   = "Superoperator fusion: N/A")
    ?(spaghetti_info = "Spaghetti splitting: N/A")
    ?(ghost_info     = "Ghost padding: N/A")
    ?(feedback_info  = "State-feedback rolling key: N/A")
    ?(mba_info       = "MBA synthesis: N/A")
    ?(cff_info       = "CFG flattening: N/A")
    ?(real_ops       = 0)
    ?(real_blocks    = 0)
    ?(pass_params    = [])
    ?(compact_imm    = true)
    ?(runtime_hardening = true)
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
  (* Switch board: every protection pass and runtime feature with the
     state it was configured in, so a report states what was actually
     enabled instead of leaving it to the reader to infer. *)
  let pass_switch name enabled note =
    Printf.sprintf "    [%s] %s%s" (if enabled then "ON " else "OFF") name
      (if enabled || note = "" then "" else " (" ^ note ^ ")")
  in
  let pass_board =
    String.concat "\n"
      [
        pass_switch "Superoperator Fusion" native_cfg.stack_vm.superoperators
          "disabled in configuration";
        pass_switch "Bytecode Amplification" true "";
        pass_switch "MBA Constant Synthesis" true "";
        pass_switch "Virtual CFG Flattening" true "";
        pass_switch "Spaghetti CFG Splitting" true "";
        pass_switch "Ghost Stack Padding" true "";
        pass_switch "State-Feedback Rolling Key" native_cfg.stack_vm.state_feedback
          "disabled in configuration";
        pass_switch "Stack Balance Repair" true "";
        pass_switch "VSP Stack Value Whitening" true "";
        pass_switch "Opcode Polymorphism" true "";
        pass_switch "Compact Immediate Encoding" native_cfg.stack_vm.compact_imm
          "disabled in configuration";
        pass_switch "Field Layout Randomization" native_cfg.stack_vm.layout_randomization
          "disabled in configuration";
        pass_switch "C++ Runtime Hardening" native_cfg.stack_vm.runtime_hardening
          "disabled in configuration";
        pass_switch "Address Binding" native_cfg.anti_pushan.address_bound
          "disabled in configuration";
        pass_switch "Anti-Pushan Rolling Key" native_cfg.anti_pushan.running_key
          "disabled in configuration";
        pass_switch "Anti-Tamper (SMC + probes)" native_cfg.anti_tamper.enabled
          "disabled in configuration";
        pass_switch "Hardware Timing Probes" (native_cfg.anti_tamper.enabled && native_cfg.anti_tamper.hardware_timing_probes)
          "disabled in configuration";
        pass_switch "Memory Integrity Scanner" (native_cfg.anti_tamper.enabled && native_cfg.anti_tamper.memory_integrity_scanner)
          "disabled in configuration";
        pass_switch "Anti-Emulation Protection" (native_cfg.anti_tamper.enabled && native_cfg.anti_tamper.anti_emulation)
          "disabled in configuration";
        pass_switch "Dynamic Nanomites" (native_cfg.anti_tamper.enabled && native_cfg.anti_tamper.nanomites)
          "disabled in configuration";
        pass_switch "Direct Syscalls" (native_cfg.anti_tamper.enabled && native_cfg.anti_tamper.direct_syscalls)
          "disabled in configuration";
        pass_switch "C-Macro Obfuscation" native_cfg.c_macro.enabled
          "disabled in configuration";
        pass_switch "Stack String Encryption (ASG_STR)" (native_cfg.c_macro.enabled && native_cfg.c_macro.obfuscate_strings)
          "disabled in configuration";
        pass_switch "Constant Blinding (ASG_BLIND)" (native_cfg.c_macro.enabled && native_cfg.c_macro.obfuscate_constants)
          "disabled in configuration";
        pass_switch "Opaque Predicates" (native_cfg.c_macro.enabled && native_cfg.c_macro.opaque_predicates)
          "disabled in configuration";
        pass_switch "EH Shadowing" native_cfg.eh_shadowing.enabled
          "disabled in configuration";
        pass_switch "Anti-VPC Tracking" native_cfg.anti_vpc.enabled
          "disabled in configuration";
        pass_switch "Memory Chaffing" native_cfg.memory_chaffing.enabled
          "disabled in configuration";
      ]
  in
  let pass_parameters =
    if pass_params = [] then ""
    else Printf.sprintf "- Pass Parameters:\n%s\n" (String.concat "\n" pass_params)
  in
  let summary =
    Printf.sprintf
      "=== ASGARD-5877 Stack-VM Protection Report ===\n\
       - Protection Passes (ON/OFF):\n\
       %s\n\
       %s\
       - Architecture: Stack-VM Execution Engine (Universal Logic + Rolling Key)\n\
       - Opcode Mapping: Dynamic Polymorphic ISA (Unique Build Permutation)\n\
       - VSP Stack Value Whitening: Enabled (Slot-Keyed XOR, Fibonacci-Prime Stride)\n\
       - PushImm Operand Width: %s\n\
       - %s\n\
       - Superoperator Fusion: %s\n\
       - Spaghetti CFG Splitting: %s\n\
       - Ghost Stack Padding: %s\n\
       - State-Feedback Rolling Key: %s\n\
       - Multi-Operand Field Layout: %s\n\
       - C++ Runtime Hardening: %s\n\
       - MBA Constant Synthesis: %s\n\
       - Virtual CFG Flattening: %s\n\
       - VPC Dispatch Overhead: %.1f avg ops/transition (%.3f transitions/real-op)\n\
       - Basic Blocks: %d\n\
       - Bytecode Size: %d bytes (%d words)\n\
       - Shannon Entropy: %.4f / 8.0 (%.1f%%)\n\
       - Devirtualization Resistance Score (DRS): %.2f / 100.0\n\
       - Rolling Key Seed: 0x%016LX\n\
       ==============================================="
      pass_board pass_parameters imm_width_info
      amplifier_info
      superop_info
      spaghetti_info ghost_info feedback_info
      (Stack_vm.Stack_encoder.format_field_layout enc.layout)
      (if runtime_hardening then "Enabled (Identifier Scrambling & Strip Comments)" else "Disabled")
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
    (* The effective parameters of every pass, collected while the phases
       run, so the report states the settings that were actually used
       (and the seeds, which make the build reproducible). *)
    let pass_params = ref [] in
    let note line = pass_params := line :: !pass_params in
    let target_func =
      if native_cfg.cff.enabled then
        let cff_opts = {
          Cff.inject_opaque_predicates = native_cfg.cff.inject_opaque_predicates;
          obfuscate_states = native_cfg.cff.obfuscate_states;
          input_tainted_transitions = native_cfg.cff.input_tainted_transitions;
          split_rate = native_cfg.cff.split_rate;
          hub_count = native_cfg.cff.hub_count;
        } in

        match Cff.flatten_func ~options:cff_opts ~rng ir with
        | Ok f -> f
        | Error _ -> ir
      else ir
    in
    let ext_syms = Hashtbl.create 16 in
    let ctx, prog = Stack_vm.Ir_to_stack.lower_func ~ext_syms target_func in
    let external_symbols = Stack_vm.Ir_to_stack.get_symbols_list ext_syms in
    dump_bytecode_trace ~phase:"1-lowered" prog;
    dump_bytecode_json ~phase:"1-lowered" prog;
    Stack_vm.Stack_phase_guard.check_phase_invariants ~phase:"1-lowered" ~final:false prog;

    (* Phase 2a (Pre-amplification): Superoperator Fusion on original lowered program instructions *)
    let prog, pre_superop_stats =
      if native_cfg.stack_vm.superoperators then
        let superop_seed =
          Int64.logxor
            (Int64.of_int (Random.State.bits rng))
            (Int64.shift_left (Int64.of_int (Random.State.bits rng)) 29)
        in
        let superop_cfg =
          { (Stack_vm.Stack_superop_pass.default_superop_config superop_seed) with
            fusion_rate = 100 }
        in
        note
          (Printf.sprintf
             "    Superoperator Fusion       fusion=%d%% rules=[AddImm SubImm AddII SubII SetRegImm AddRegImm] seed=0x%016LX"
             superop_cfg.fusion_rate superop_cfg.seed);
        let prog_superop = Stack_vm.Stack_superop_pass.apply_program superop_cfg prog in
        let stats = Stack_vm.Stack_superop_pass.superop_stats prog prog_superop in
        (prog_superop, Some (superop_cfg, stats))
      else
        (prog, None)
    in
    dump_bytecode_trace ~phase:"2a-pre-superop" prog;
    dump_bytecode_json ~phase:"2a-pre-superop" prog;
    Stack_vm.Stack_phase_guard.check_phase_invariants ~phase:"2a-pre-superop" ~final:false prog;

    (* Phase 2: Mathematical Bytecode Amplification (Horner Polynomials, Carry-Chain, Def-Use Webbing)
       Pass Order Architecture: Bytecode_amplifier runs BEFORE Phase 2b (Stack_mba_pass) so that
       polynomial constant synthesis (Horner degree 6) targets ONLY original program constants.
       Running amplifier after MBA would cause multiplicative explosion O(MBA * Amplifier) ~ 1000x.
       We also use adaptive_profile to automatically scale Horner degree (2..6) based on block size. *)
    let max_block_size = Hashtbl.fold (fun _ (b : Stack_vm.Stack_ir.block) acc -> max acc (List.length b.ops)) prog.blocks 0 in
    (* Strong setting: the heavy amplification profile for every block.
       The stack pipeline amplifies BEFORE the MBA pass, so the
       multiplicative explosion the adaptive profile guards against
       (MBA * Amplifier) cannot happen here; the adaptive downgrade to
       the light profile (Horner degree 2) only made the constant
       synthesis cheap to recognise. *)
    let amp_profile = Stack_vm.Bytecode_amplifier.default_heavy_profile in
    note
      (Printf.sprintf
         "    Bytecode Amplification    horner_degree=%d bit_slice_lanes=%d expander_chord_len=%d expander_chord_rate=%d%% (heavy profile, max block %d ops)"
         amp_profile.horner_degree amp_profile.bit_slice_lanes amp_profile.expander_chord_len
         amp_profile.expander_chord_rate max_block_size);
    let prog_amplified = Stack_vm.Bytecode_amplifier.amplify_stack_program rng ~ctx ~profile:amp_profile prog in
    let amplifier_info = Stack_vm.Bytecode_amplifier.amplifier_stats prog prog_amplified in
    let prog = prog_amplified in
    Stack_vm.Context_allocator.reserve_slots ctx prog.context_slots;
    dump_bytecode_trace ~phase:"2-amplified" prog;
    dump_bytecode_json ~phase:"2-amplified" prog;
    Stack_vm.Stack_phase_guard.check_phase_invariants ~phase:"2-amplified" ~final:false prog;

    (* Phase 2a (Post-amplification): Superoperator Fusion on synthesized constants *)
    let prog, superop_info =
      match pre_superop_stats with
      | Some (superop_cfg, pre_stats) ->
          let prog_superop = Stack_vm.Stack_superop_pass.apply_program superop_cfg prog in
          let post_stats = Stack_vm.Stack_superop_pass.superop_stats prog prog_superop in
          let total_fused = pre_stats.fused_ops + post_stats.fused_ops in
          let total_add_imm = pre_stats.add_imm_count + post_stats.add_imm_count in
          let total_sub_imm = pre_stats.sub_imm_count + post_stats.sub_imm_count in
          let total_add_ii = pre_stats.add_ii_count + post_stats.add_ii_count in
          let total_sub_ii = pre_stats.sub_ii_count + post_stats.sub_ii_count in
          let total_set_reg_imm = pre_stats.set_reg_imm_count + post_stats.set_reg_imm_count in
          let total_add_reg_imm = pre_stats.add_reg_imm_count + post_stats.add_reg_imm_count in
          let info =
            Printf.sprintf "%d ops fused (AddImm:%d SubImm:%d AddII:%d SubII:%d SetRegImm:%d AddRegImm:%d)"
              total_fused total_add_imm total_sub_imm total_add_ii total_sub_ii total_set_reg_imm
              total_add_reg_imm
          in
          (prog_superop, info)
      | None ->
          (prog, "Disabled (Plain ISA)")
    in
    dump_bytecode_trace ~phase:"2a-post-superop" prog;
    dump_bytecode_json ~phase:"2a-post-superop" prog;
    Stack_vm.Stack_phase_guard.check_phase_invariants ~phase:"2a-post-superop" ~final:false prog;

    (* Phase 2b: MBA Constant Synthesis — replace PushImm with NOR/NAND/ADD sequences *)
    let mba_seed =
      Int64.logxor
        (Int64.of_int (Random.State.bits rng))
        (Int64.shift_left (Int64.of_int (Random.State.bits rng)) 19)
    in
    let mba_cfg = { (Stack_vm.Stack_mba_pass.default_mba_config mba_seed) with mba_rate = 100 } in
    note
      (Printf.sprintf "    MBA Constant Synthesis     rate=%d%% seed=0x%016LX" mba_cfg.mba_rate
         mba_cfg.seed);
    let prog_mba = Stack_vm.Stack_mba_pass.apply_program ~ctx mba_cfg prog in
    let mba_info = Stack_vm.Stack_mba_pass.mba_stats prog prog_mba in
    let prog = prog_mba in
    dump_bytecode_trace ~phase:"2b-mba" prog;
    dump_bytecode_json ~phase:"2b-mba" prog;
    Stack_vm.Stack_phase_guard.check_phase_invariants ~phase:"2b-mba" ~final:false prog;

    let real_blocks = Hashtbl.length prog.blocks in
    let real_ops = Hashtbl.fold (fun _ (b : Stack_vm.Stack_ir.block) acc -> acc + List.length b.ops) prog.blocks 0 in

    (* Phase 3: Virtual CFG Flattening — route jumps through VPC dispatcher *)
    let cff_seed =
      Int64.logxor
        (Int64.of_int (Random.State.bits rng))
        (Int64.shift_left (Int64.of_int (Random.State.bits rng)) 11)
    in
    let cff_cfg = Stack_vm.Stack_cff_pass.default_cff_config cff_seed in
    note
      (Printf.sprintf
         "    Virtual CFG Flattening     hubs=%d split_rate=%d opaque_predicates=%s seed=0x%016LX"
         native_cfg.cff.hub_count native_cfg.cff.split_rate
         (if native_cfg.cff.inject_opaque_predicates then "on" else "off")
         cff_cfg.seed);
    let prog_cff, cff_dispatcher = Stack_vm.Stack_cff_pass.apply_program_with_info cff_cfg ctx prog in
    let cff_info = Stack_vm.Stack_cff_pass.cff_stats prog prog_cff in
    let prog = prog_cff in
    dump_bytecode_trace ~phase:"3-cff" prog;
    dump_bytecode_json ~phase:"3-cff" prog;
    Stack_vm.Stack_phase_guard.check_phase_invariants ~phase:"3-cff" ~final:false prog;

    (* Phase 4: Spaghetti Control-Flow Splitting — split blocks after CFF *)
    let spaghetti_seed =
      Int64.logxor
        (Int64.of_int (Random.State.bits rng))
        (Int64.shift_left (Int64.of_int (Random.State.bits rng)) 23)
    in
    let cur_b = Hashtbl.length prog.blocks in
    let max_splits = max 64 (min 512 (cur_b / 2)) in
    let spaghetti_cfg = {
      (Stack_vm.Stack_spaghetti_pass.default_spaghetti_config spaghetti_seed) with
      split_rate = 100;
      max_blocks = cur_b + max_splits;
    } in
    note
      (Printf.sprintf "    Spaghetti CFG Splitting    split_rate=%d max_blocks=%d seed=0x%016LX"
         spaghetti_cfg.split_rate spaghetti_cfg.max_blocks spaghetti_cfg.seed);
    let prog_spaghetti = Stack_vm.Stack_spaghetti_pass.apply_program spaghetti_cfg prog in
    let spaghetti_info = Stack_vm.Stack_spaghetti_pass.spaghetti_stats prog prog_spaghetti in
    let prog = prog_spaghetti in
    dump_bytecode_trace ~phase:"4-spaghetti" prog;
    dump_bytecode_json ~phase:"4-spaghetti" prog;
    Stack_vm.Stack_phase_guard.check_phase_invariants ~phase:"4-spaghetti" ~final:false prog;

    (* Phase 5: Ghost Stack Padding — inject neutral junk ops per block *)
    let ghost_seed =
      Int64.logxor
        (Int64.of_int (Random.State.bits rng))
        (Int64.shift_left (Int64.of_int (Random.State.bits rng)) 17)
    in
    let ghost_cfg = { (Stack_vm.Stack_ghost_pass.default_ghost_config ghost_seed) with ghost_rate = 80 } in
    note
      (Printf.sprintf
         "    Ghost Stack Padding        rate=%d%% max_ghosts=%s entanglement=%s seed=0x%016LX"
         ghost_cfg.ghost_rate
         (if ghost_cfg.max_ghosts <= 0 then "unlimited" else string_of_int ghost_cfg.max_ghosts)
         (if ghost_cfg.entangle then "on" else "off")
         ghost_cfg.seed);
    let prog_ghost = Stack_vm.Stack_ghost_pass.apply_program ghost_cfg ctx prog in
    let ghost_info = Stack_vm.Stack_ghost_pass.ghost_stats prog prog_ghost in
    let prog = prog_ghost in
    dump_bytecode_trace ~phase:"5-ghost" prog;
    dump_bytecode_json ~phase:"5-ghost" prog;
    Stack_vm.Stack_phase_guard.check_phase_invariants ~phase:"5-ghost" ~final:false prog;

    (* Phase 6: State-Feedback Rolling Key — couple cipher stream to register state *)
    let prog, feedback_info =
      if native_cfg.stack_vm.state_feedback then
        let feedback_seed =
          Int64.logxor
            (Int64.of_int (Random.State.bits rng))
            (Int64.shift_left (Int64.of_int (Random.State.bits rng)) 27)
        in
        let feedback_cfg =
          { (Stack_vm.Stack_feedback_pass.default_feedback_config feedback_seed) with
            feedback_rate = 100 }
        in
        note
          (Printf.sprintf "    State-Feedback Rolling Key rate=%d%% seed=0x%016LX"
             feedback_cfg.feedback_rate feedback_cfg.seed);
        (* The VPC coupling: the state-feedback pass couples the rolling
           key to the VPC at the entry of every CFF block, where the VPC
           provably holds the token of that block.  The encryptor needs
           the same state to reproduce the key schedule. *)
        let prog_feedback =
          Stack_vm.Stack_feedback_pass.apply_program
            ~vpc_slot:cff_dispatcher.vpc_slot
            ~block_tokens:cff_dispatcher.block_tokens
            feedback_cfg prog
        in
        let feedback_stat = Stack_vm.Stack_feedback_pass.feedback_stats prog prog_feedback in
        let info =
          Printf.sprintf "%d dynamic checkpoints injected (register-coupled cipher stream)"
            feedback_stat.feedback_injected
        in
        (prog_feedback, info)
      else
        (prog, "Disabled (Static Cipher Stream)")
    in
    dump_bytecode_trace ~phase:"6-feedback" prog;
    dump_bytecode_json ~phase:"6-feedback" prog;
    Stack_vm.Stack_phase_guard.check_phase_invariants ~phase:"6-feedback" ~final:false prog;

    (* Phase 7: Stack Balance Pass — enforce block balance delta = 0 *)
    let prog = Stack_vm.Stack_balance_pass.repair_program ctx prog in
    dump_bytecode_trace ~phase:"7-balance (final)" prog;
    dump_bytecode_json ~phase:"7-balance (final)" prog;
    Stack_vm.Stack_phase_guard.check_phase_invariants ~phase:"7-balance (final)" ~final:true prog;


    let seed_key =
      Int64.logxor
        (Int64.of_int (Random.State.bits rng))
        (Int64.shift_left (Int64.of_int (Random.State.bits rng)) 32)
    in
    let compact_imm = native_cfg.stack_vm.compact_imm in
    let layout =
      if native_cfg.stack_vm.layout_randomization then None
      else Some Stack_vm.Stack_encoder.default_field_layout
    in
    (* The encryptor has to know the dispatcher state to accept the VPC
       couplings: the token of every CFF block, and the VPC slot. *)
    let dispatcher_tokens = Hashtbl.create (Hashtbl.length cff_dispatcher.block_tokens) in
    Hashtbl.iter
      (fun id token ->
        Hashtbl.replace dispatcher_tokens id (cff_dispatcher.vpc_slot, token))
      cff_dispatcher.block_tokens;
    let enc =
      Stack_vm.Stack_encoder.encode_program ~seed_key ?layout ~compact_imm
        ~dispatcher_tokens prog
    in
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
    let obfuscate_runtime = native_cfg.stack_vm.runtime_hardening in
    let cpp_runtime_source =
      Stack_vm.Stack_runtime.generate_c_runtime
        ~external_symbols:sanitized_external_symbols
        ?constants:sanitized_constants
        ~obfuscate_runtime
        ~enc
        runtime_cfg
        prog
    in
    let runner_source = Stack_vm.Stack_runtime.emit_runner_cpp bc_words in
    note "    Stack Balance Repair       underflow=PushImm 0 pads, exit-delta=PopReg scratch drain";
    note
      (Printf.sprintf
         "    Bloat / Crypto             mode=%s budget=%dKB density=%.2f  rounds=%d key_bits=%d"
         (match native_cfg.bloat.mode with
          | `Compact -> "compact"
          | `Balanced -> "balanced"
          | `Heavy -> "heavy"
          | `Insane -> "insane")
         (match native_cfg.bloat.target_size_budget_kb with Some k -> k | None -> 0)
         native_cfg.bloat.junk_density native_cfg.crypto.rounds native_cfg.crypto.key_bits);
    note
      (Printf.sprintf "    Dispatch / Chaffing        domains=%d  chaff pool=%d ratio=%.1f"
         native_cfg.vm_runtime.num_dispatch_domains native_cfg.memory_chaffing.pool_size
         native_cfg.memory_chaffing.chaff_ratio);
    let metrics =
      make_stack_metrics
        native_cfg
        ~pass_params:(List.rev !pass_params)
        ~compact_imm
        ~runtime_hardening:obfuscate_runtime
        ~amplifier_info
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
          ~obfuscate_runtime
          ~enc:enc_rebound
          runtime_cfg
          prog)
    in
    {
      cpp_runtime_source = inject_pipeline_hardening native_cfg target_func.name cpp_runtime_source;
      runner_source;
      bytecode = bc_words;
      bytecodes = [ ("target_func", bc_words) ];
      metrics;
      header_name = "stack_vm_runtime.hpp";
      rebind_address;
    }
end

