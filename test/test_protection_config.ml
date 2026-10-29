open Native_vm
open X86_lifter

(** Tests for [Protection_config] — JSON & Preset Configuration for ASGARD-5877. *)

let test_presets () =
  Alcotest.(check bool) "default config has cff enabled" true Protection_config.default.cff.enabled;
  Alcotest.(check bool) "max_security has depth 4" true (Protection_config.max_security.mba.depth = 4);
  (match Protection_config.from_preset "lightweight" with
   | Error _ -> Alcotest.(check bool) "lightweight rejected" true true
   | Ok _ -> Alcotest.fail "lightweight should be rejected");
  Alcotest.(check bool) "stealth has ncfg engine" true (Protection_config.stealth.mba.engine = `Ncfg);

  match Protection_config.from_preset "military" with
  | Ok cfg -> Alcotest.(check int) "military alias maps to max_security" 4 cfg.mba.depth
  | Error err -> Alcotest.fail err

let test_json_roundtrip () =
  let original = Protection_config.max_security in
  let json_str = Protection_config.to_json_string ~pretty:true original in
  match Protection_config.from_json_string json_str with
  | Error err -> Alcotest.fail err
  | Ok parsed ->
      Alcotest.(check bool) "cff.enabled matches" original.cff.enabled parsed.cff.enabled;
      Alcotest.(check int) "mba.depth matches" original.mba.depth parsed.mba.depth;
      Alcotest.(check bool) "anti_tamper.smc matches" original.anti_tamper.smc parsed.anti_tamper.smc;
      Alcotest.(check bool) "anti_tamper.smc_strict matches" original.anti_tamper.smc_strict parsed.anti_tamper.smc_strict;
      Alcotest.(check bool) "anti_tamper.nanomites matches" original.anti_tamper.nanomites parsed.anti_tamper.nanomites;
      Alcotest.(check bool) "anti_tamper.direct_syscalls matches" original.anti_tamper.direct_syscalls parsed.anti_tamper.direct_syscalls;
      Alcotest.(check bool) "anti_pushan.running_key matches" original.anti_pushan.running_key parsed.anti_pushan.running_key;
      Alcotest.(check bool) "anti_pushan.address_bound matches" original.anti_pushan.address_bound parsed.anti_pushan.address_bound;
      Alcotest.(check int) "vm_runtime.num_dispatch_domains matches" original.vm_runtime.num_dispatch_domains parsed.vm_runtime.num_dispatch_domains;
      Alcotest.(check bool) "vm_runtime.vector_isa matches" original.vm_runtime.vector_isa parsed.vm_runtime.vector_isa;
      Alcotest.(check bool) "vm_runtime.egraph_expansion matches" original.vm_runtime.egraph_expansion parsed.vm_runtime.egraph_expansion;
      Alcotest.(check bool) "vm_runtime.chameleon_handlers matches" original.vm_runtime.chameleon_handlers parsed.vm_runtime.chameleon_handlers;
      Alcotest.(check bool) "stack_vm.enabled matches" original.stack_vm.enabled parsed.stack_vm.enabled;
      Alcotest.(check bool) "stack_vm.superoperators matches" original.stack_vm.superoperators parsed.stack_vm.superoperators;
      Alcotest.(check bool) "stack_vm.state_feedback matches" original.stack_vm.state_feedback parsed.stack_vm.state_feedback;
      Alcotest.(check bool) "stack_vm.layout_randomization matches" original.stack_vm.layout_randomization parsed.stack_vm.layout_randomization;
      Alcotest.(check bool) "stack_vm.runtime_hardening matches" original.stack_vm.runtime_hardening parsed.stack_vm.runtime_hardening;
      Alcotest.(check bool) "stack_vm.compact_imm matches" original.stack_vm.compact_imm parsed.stack_vm.compact_imm;
      Alcotest.(check bool) "eh_shadowing.enabled matches" original.eh_shadowing.enabled parsed.eh_shadowing.enabled;
      Alcotest.(check int) "eh_shadowing.shadow_alloc_size matches" original.eh_shadowing.shadow_alloc_size parsed.eh_shadowing.shadow_alloc_size;
      Alcotest.(check bool) "anti_vpc.enabled matches" original.anti_vpc.enabled parsed.anti_vpc.enabled;
      Alcotest.(check bool) "anti_vpc.scramble_vpc matches" original.anti_vpc.scramble_vpc parsed.anti_vpc.scramble_vpc;
      Alcotest.(check bool) "anti_vpc.split_vpc matches" original.anti_vpc.split_vpc parsed.anti_vpc.split_vpc;
      Alcotest.(check bool) "anti_vpc.entropy_whitening matches" original.anti_vpc.entropy_whitening parsed.anti_vpc.entropy_whitening;
      Alcotest.(check bool) "memory_chaffing.enabled matches" original.memory_chaffing.enabled parsed.memory_chaffing.enabled;
      Alcotest.(check int) "memory_chaffing.pool_size matches" original.memory_chaffing.pool_size parsed.memory_chaffing.pool_size

let test_partial_json_parsing () =
  let partial_json = {|
  {
    "seed": 99999,
    "cff": {
      "enabled": false
    },
    "mba": {
      "depth": 3,
      "engine": "egraph"
    }
  }
  |} in
  match Protection_config.from_json_string partial_json with
  | Error err -> Alcotest.fail err
  | Ok cfg ->
      Alcotest.(check (option int)) "seed is 99999" (Some 99999) cfg.seed;
      Alcotest.(check bool) "cff.enabled is false" false cfg.cff.enabled;
      Alcotest.(check int) "mba.depth is 3" 3 cfg.mba.depth;
      Alcotest.(check bool) "mba.enabled defaults to true" true cfg.mba.enabled;
      Alcotest.(check bool) "anti_pushan defaults to true" true cfg.anti_pushan.enabled;
      Alcotest.(check bool) "anti_tamper defaults to true" true cfg.anti_tamper.enabled;
      Alcotest.(check bool) "stack_vm defaults to enabled" true cfg.stack_vm.enabled;
      Alcotest.(check bool) "stack_vm superoperators defaults to true" true cfg.stack_vm.superoperators

let test_stack_vm_presets () =
  let def = Protection_config.default in
  Alcotest.(check bool) "default stack_vm enabled" true def.stack_vm.enabled;
  Alcotest.(check bool) "default runtime_hardening enabled" true def.stack_vm.runtime_hardening;
  let max_s = Protection_config.max_security in
  Alcotest.(check bool) "max_security stack_vm runtime_hardening enabled" true max_s.stack_vm.runtime_hardening;
  let custom =
    Protection_config.create_builder ~base:def ()
    |> Protection_config.with_stack_vm ~superoperators:false ~runtime_hardening:false true
    |> Protection_config.build
  in
  Alcotest.(check bool) "custom stack_vm superoperators disabled" false custom.stack_vm.superoperators;
  Alcotest.(check bool) "custom stack_vm runtime_hardening disabled" false custom.stack_vm.runtime_hardening;
  let custom_vpc =
    Protection_config.create_builder ~base:def ()
    |> Protection_config.with_anti_vpc ~scramble_vpc:false false
    |> Protection_config.with_memory_chaffing ~pool_size:2048 ~chaff_ratio:1.5 true
    |> Protection_config.build
  in
  Alcotest.(check bool) "custom anti_vpc disabled" false custom_vpc.anti_vpc.enabled;
  Alcotest.(check int) "custom memory_chaffing pool_size" 2048 custom_vpc.memory_chaffing.pool_size

let test_protection_with_config () =
  let rng = Random.State.make [| 42 |] in
  let asm = {|
func_cfg_test:
    mov rax, 10
    add rax, 20
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let config = Protection_config.default in
      let pkg = Vm_emitter.compile_and_package ~rng ~config func in
      Alcotest.(check bool) "default bytecode emitted" true (List.length pkg.bytecode > 0);

      let config_max = Protection_config.max_security in
      let pkg_max = Vm_emitter.compile_and_package ~rng ~config:config_max func in
      Alcotest.(check bool) "max_security bytecode emitted" true (List.length pkg_max.bytecode > 0);
      Alcotest.(check bool) "max_security DRS >= default DRS" true
        (Native_vm.Metrics.devirtualization_resistance_score pkg_max.metrics >= Native_vm.Metrics.devirtualization_resistance_score pkg.metrics)

let test_junk_density_scaling () =
  let rng = Random.State.make [| 1337 |] in
  let instrs = [
    Vm_ir.Ir.Mov { dst = Vm_ir.Ir.Reg Vm_ir.Register.rax; src = Vm_ir.Ir.Imm 10L };
    Vm_ir.Ir.Alu { op = Vm_ir.Ir.Add; dst = Vm_ir.Register.rax; src1 = Vm_ir.Ir.Reg Vm_ir.Register.rax; src2 = Vm_ir.Ir.Imm 20L; set_flags = false };
    Vm_ir.Ir.Alu { op = Vm_ir.Ir.Sub; dst = Vm_ir.Register.rax; src1 = Vm_ir.Ir.Reg Vm_ir.Register.rax; src2 = Vm_ir.Ir.Imm 5L; set_flags = false };
    Vm_ir.Ir.Ret;
  ] in
  let zero_junk = Vm_transform.inject_junk_instructions ~density:0.0 ~rng instrs in
  Alcotest.(check int) "zero density produces no junk" (List.length instrs) (List.length zero_junk);
  let med_junk = Vm_transform.inject_junk_instructions ~density:0.5 ~rng instrs in
  let heavy_junk = Vm_transform.inject_junk_instructions ~density:2.0 ~rng instrs in
  Alcotest.(check bool) "heavy density produces more instructions than zero" true (List.length heavy_junk > List.length zero_junk);
  Alcotest.(check bool) "heavy density produces >= medium density" true (List.length heavy_junk >= List.length med_junk)

let test_presets_opaque_predicates () =
  Alcotest.(check bool) "max_security has opaque predicates" true Protection_config.max_security.cff.inject_opaque_predicates;
  Alcotest.(check bool) "high has opaque predicates" true Protection_config.high.cff.inject_opaque_predicates;
  Alcotest.(check bool) "stealth has opaque predicates" true Protection_config.stealth.cff.inject_opaque_predicates;
  Alcotest.(check bool) "default has opaque predicates disabled" false Protection_config.default.cff.inject_opaque_predicates;
  Alcotest.(check bool) "minimal has opaque predicates disabled" false Protection_config.minimal.cff.inject_opaque_predicates

let test_dispatch_domain_diversification () =
  let rng = Random.State.make [| 2026 |] in
  let asm = {|
func_dom_test:
    mov rax, 42
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let config = Protection_config.max_security in
      let pkg = Vm_emitter.compile_and_package ~rng ~config func in
      Alcotest.(check bool) "cpp_source contains dispatch domains" true
        (Test_helpers.string_contains pkg.cpp_runtime_source "all_dispatch_domains");
      Alcotest.(check bool) "cpp_source contains decoy handlers" true
        (Test_helpers.string_contains pkg.cpp_runtime_source "H_DECOY_");
      Alcotest.(check bool) "cpp_source contains compute_handlers_hash" true
        (Test_helpers.string_contains pkg.cpp_runtime_source "compute_handlers_hash")

let test_eh_shadowing_config () =
  Alcotest.(check bool) "default has eh_shadowing enabled" true Protection_config.default.eh_shadowing.enabled;
  Alcotest.(check bool) "max_security has eh_shadowing enabled" true Protection_config.max_security.eh_shadowing.enabled;
  Alcotest.(check int) "max_security shadow_alloc_size is 64" 64 Protection_config.max_security.eh_shadowing.shadow_alloc_size;
  Alcotest.(check bool) "minimal has eh_shadowing disabled" false Protection_config.minimal.eh_shadowing.enabled;

  let builder = Protection_config.create_builder () in
  let custom = Protection_config.with_eh_shadowing ~shadow_alloc_size:48 false builder |> Protection_config.build in
  Alcotest.(check bool) "builder disabled eh_shadowing" false custom.eh_shadowing.enabled;
  Alcotest.(check int) "builder shadow_alloc_size 48" 48 custom.eh_shadowing.shadow_alloc_size

let test_pass_config_sections () =
  (* Round-trip: new sections survive to_yojson/of_yojson *)
  let original = {
    Protection_config.default with
    amplifier = {
      enabled = true; profile = "balanced"; horner_degree = 4;
      bit_slice_lanes = 1; expander_chord_len = 6; expander_chord_rate = 55;
    };
    superop = {
      enabled = true; fusion_rate = 65;
      enable_add_imm = true; enable_sub_imm = false;
      enable_add_ii = false; enable_sub_ii = true;
      enable_set_reg_imm = true; enable_add_reg_imm = false;
    };
    ghost = { enabled = false; ghost_rate = 25; max_ghosts = 7; entangle = false };
    spaghetti = {
      enabled = true; split_rate = 90; max_extra_blocks = 500;
      max_splits_factor = 3; min_chunk = 1;
    };
    mba = { Protection_config.default.mba with stack_synthesis_rate = 45 };
    vm_runtime = {
      Protection_config.default.vm_runtime with
      context_epochs = 6;
      oblivious_decoys = 5;
    };
    stack_vm = {
      Protection_config.default.stack_vm with
      feedback_rate = 33; cff_couple_key = false;
      opcode_polymorphism = false;
      permute_registers = true;
      host_stack_size_kb = 2048;
    };
    watermark = { payload_bits = 48; redundancy = 9 };
    toolchain = { opt_level = "-O2"; extra_flags = ["-flto"] };
    cff = { Protection_config.default.cff with
      pop_digest = true; red_herring = false;
    };
    trampoline = { chunk_size = 128 };
    bloat = {
      Protection_config.default.bloat with
      density_cap_threshold1_kb = 300;
      density_cap_threshold2_kb = 600;
    };
  } in
  let json_str = Protection_config.to_json_string ~pretty:true original in
  (match Protection_config.from_json_string json_str with
   | Error err -> Alcotest.fail ("round-trip parse: " ^ err)
   | Ok parsed ->
       Alcotest.(check string) "amplifier.profile" original.amplifier.profile parsed.amplifier.profile;
       Alcotest.(check int) "amplifier.horner_degree" original.amplifier.horner_degree parsed.amplifier.horner_degree;
       Alcotest.(check int) "amplifier.expander_chord_rate" original.amplifier.expander_chord_rate parsed.amplifier.expander_chord_rate;
       Alcotest.(check int) "superop.fusion_rate" original.superop.fusion_rate parsed.superop.fusion_rate;
       Alcotest.(check bool) "superop.enable_sub_ii" original.superop.enable_sub_ii parsed.superop.enable_sub_ii;
       Alcotest.(check int) "ghost.ghost_rate" original.ghost.ghost_rate parsed.ghost.ghost_rate;
       Alcotest.(check int) "ghost.max_ghosts" original.ghost.max_ghosts parsed.ghost.max_ghosts;
       Alcotest.(check int) "spaghetti.max_extra_blocks" original.spaghetti.max_extra_blocks parsed.spaghetti.max_extra_blocks;
       Alcotest.(check int) "spaghetti.min_chunk" original.spaghetti.min_chunk parsed.spaghetti.min_chunk;
       Alcotest.(check int) "mba.stack_synthesis_rate" original.mba.stack_synthesis_rate parsed.mba.stack_synthesis_rate;
       Alcotest.(check int) "stack_vm.feedback_rate" original.stack_vm.feedback_rate parsed.stack_vm.feedback_rate;
       Alcotest.(check bool) "stack_vm.cff_couple_key" original.stack_vm.cff_couple_key parsed.stack_vm.cff_couple_key;
       Alcotest.(check bool) "cff.pop_digest" original.cff.pop_digest parsed.cff.pop_digest;
       Alcotest.(check bool) "cff.red_herring" original.cff.red_herring parsed.cff.red_herring;
       Alcotest.(check int) "trampoline.chunk_size" 128 parsed.trampoline.chunk_size;
       Alcotest.(check int) "watermark.redundancy" 9 parsed.watermark.redundancy;
       Alcotest.(check string) "toolchain.opt_level" "-O2" parsed.toolchain.opt_level;
       Alcotest.(check int) "vm_runtime.context_epochs" 6 parsed.vm_runtime.context_epochs;
       Alcotest.(check int) "vm_runtime.oblivious_decoys" 5 parsed.vm_runtime.oblivious_decoys;
       Alcotest.(check bool) "stack_vm.opcode_polymorphism" false parsed.stack_vm.opcode_polymorphism;
       Alcotest.(check bool) "stack_vm.permute_registers" true parsed.stack_vm.permute_registers;
       Alcotest.(check int) "stack_vm.host_stack_size_kb" 2048 parsed.stack_vm.host_stack_size_kb;
       Alcotest.(check int) "bloat.density_cap_threshold1_kb" 300 parsed.bloat.density_cap_threshold1_kb;
       Alcotest.(check int) "bloat.density_cap_threshold2_kb" 600 parsed.bloat.density_cap_threshold2_kb);
  (match Protection_json.from_json_string {|{"arch":"aarch64"}|} with
   | Error err -> Alcotest.fail ("defaults parse: " ^ err)
   | Ok cfg ->
       Alcotest.(check bool) "amplifier defaults enabled" true cfg.amplifier.enabled;
       Alcotest.(check string) "amplifier defaults heavy" "heavy" cfg.amplifier.profile;
       Alcotest.(check int) "amplifier horner override 0" 0 cfg.amplifier.horner_degree;
       Alcotest.(check int) "superop defaults fusion 100" 100 cfg.superop.fusion_rate;
       Alcotest.(check bool) "superop defaults enabled" true cfg.superop.enabled;
       Alcotest.(check int) "ghost defaults rate 80" 80 cfg.ghost.ghost_rate;
       Alcotest.(check bool) "ghost defaults enabled" true cfg.ghost.enabled;
       Alcotest.(check int) "spaghetti defaults factor 1" 1 cfg.spaghetti.max_splits_factor;
       Alcotest.(check int) "mba defaults stack rate 100" 100 cfg.mba.stack_synthesis_rate;
       Alcotest.(check int) "stack_vm defaults feedback 100" 100 cfg.stack_vm.feedback_rate;
       Alcotest.(check bool) "stack_vm defaults couple key" true cfg.stack_vm.cff_couple_key;
       Alcotest.(check bool) "cff defaults pop_digest off" false cfg.cff.pop_digest;
       Alcotest.(check bool) "cff defaults red_herring on" true cfg.cff.red_herring;
       Alcotest.(check int) "trampoline defaults chunk_size 64" 64 cfg.trampoline.chunk_size;
       Alcotest.(check int) "bloat defaults threshold1 200" 200 cfg.bloat.density_cap_threshold1_kb;
       Alcotest.(check int) "bloat defaults threshold2 500" 500 cfg.bloat.density_cap_threshold2_kb;
       Alcotest.(check int) "mba defaults ir_max_depth 4" 4 cfg.mba.ir_max_depth;
       Alcotest.(check int) "mba defaults ir_egraph_nodes 80" 80 cfg.mba.ir_egraph_node_limit;
       Alcotest.(check int) "watermark defaults redundancy 7" 7 cfg.watermark.redundancy;
       Alcotest.(check string) "toolchain defaults opt_level -O3" "-O3" cfg.toolchain.opt_level;
       Alcotest.(check int) "vm_runtime defaults epochs 4" 4 cfg.vm_runtime.context_epochs;
       Alcotest.(check int) "vm_runtime defaults decoys 3" 3 cfg.vm_runtime.oblivious_decoys;
       Alcotest.(check bool) "stack_vm defaults polymorphism on" true cfg.stack_vm.opcode_polymorphism;
       Alcotest.(check bool) "stack_vm defaults permute off" false cfg.stack_vm.permute_registers;
       Alcotest.(check int) "stack_vm defaults host stack 1024" 1024 cfg.stack_vm.host_stack_size_kb)

let test_pass_config_presets () =
  let open Protection_config in
  (* minimal: amplifier and ghost disabled *)
  Alcotest.(check bool) "minimal amplifier disabled" false minimal.amplifier.enabled;
  Alcotest.(check bool) "minimal ghost disabled" false minimal.ghost.enabled;
  (* high: heavier ghost *)
  Alcotest.(check int) "high ghost_rate 90" 90 high.ghost.ghost_rate;
  (* max_security: max ghost + doubled spaghetti ceiling *)
  Alcotest.(check int) "max_security ghost_rate 100" 100 max_security.ghost.ghost_rate;
  Alcotest.(check int) "max_security spaghetti factor 2" 2 max_security.spaghetti.max_splits_factor;
  (* default is balanced-minimal: light amplifier, halved pass rates;
     stealth/edr_stealth keep base defaults *)
  Alcotest.(check int) "default ghost_rate 30" 30 default.ghost.ghost_rate;
  Alcotest.(check string) "default amplifier light" "light" default.amplifier.profile;
  Alcotest.(check string) "stealth amplifier heavy" "heavy" stealth.amplifier.profile;
  ; let edr = match Protection_config.from_preset "edr_stealth" with Ok c -> c | Error e -> Alcotest.fail e in
    Alcotest.(check int) "edr_stealth ghost_rate 80" 80 edr.ghost.ghost_rate


let tests = [
  Alcotest.test_case "presets" `Quick test_presets;
  Alcotest.test_case "json_roundtrip" `Quick test_json_roundtrip;
  Alcotest.test_case "partial_json_parsing" `Quick test_partial_json_parsing;
  Alcotest.test_case "stack_vm_presets" `Quick test_stack_vm_presets;
  Alcotest.test_case "protection_with_config" `Quick test_protection_with_config;
  Alcotest.test_case "junk_density_scaling" `Quick test_junk_density_scaling;
  Alcotest.test_case "presets_opaque_predicates" `Quick test_presets_opaque_predicates;
  Alcotest.test_case "dispatch_domain_diversification" `Quick test_dispatch_domain_diversification;
  Alcotest.test_case "eh_shadowing_config" `Quick test_eh_shadowing_config;
  Alcotest.test_case "pass_config_sections" `Quick test_pass_config_sections;
  Alcotest.test_case "pass_config_presets" `Quick test_pass_config_presets;
]
