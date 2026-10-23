(* Every case reports how long it took.  Alcotest captures the output of a
   case, so the line goes to the file named by [ASGARD_TEST_TIMES] (the test
   runner script tails it); without that variable the timing is only kept in
   the file-less default of no output. *)
let timings_path = Sys.getenv_opt "ASGARD_TEST_TIMES"

let record_timing line =
  match timings_path with
  | None -> ()
  | Some path ->
      let oc = open_out_gen [ Open_append; Open_creat; Open_wronly ] 0o644 path in
      output_string oc line;
      output_char oc '\n';
      close_out oc

let timed_case suite_name (case_name, speed, f) =
  let wrapped () =
    let t0 = Unix.gettimeofday () in
    match f () with
    | () ->
        record_timing
          (Printf.sprintf "[time] %-42s %-46s %7.3fs" suite_name case_name
             (Unix.gettimeofday () -. t0));
        ()
    | exception e ->
        record_timing
          (Printf.sprintf "[time] %-42s %-46s %7.3fs (failed)" suite_name case_name
             (Unix.gettimeofday () -. t0));
        raise e
  in
  (case_name, speed, wrapped)

let timed_suite (suite_name, cases) = (suite_name, List.map (timed_case suite_name) cases)

let () =
  Alcotest.run "Random_vISA_Tests" (List.map timed_suite [
    ("Domain Invariants", Test_domain_invariants.tests);
    ("ISA Grammar", Test_isa_grammar.tests);
    ("HW Cost", Test_hw_cost.tests);
    ("Families Generation", Test_families_generation.tests);
    ("Sail Parser Roundtrip", Test_sail_parser_roundtrip.tests);
    ("Golden Tests", Test_golden.tests);
    ("Property Tests (QCheck 1000+)", Test_properties.tests);
    ("C++ Emulator E2E", Test_cpp_emulator.tests);
    ("C11 Emulator E2E", Test_c11_emulator.tests);
    ("Assembler & Bytecode", Test_assembler.tests);
    ("Assembler Deep Cases", Test_assembler_deep.tests);
    ("Multi-VLEN Emulation", Test_multi_vlen.tests);
    ("CLI Integration E2E", Test_cli.tests);
    ("Vanguard-9292 Obfuscation", Test_vanguard_9292.tests);
    ("Vanguard Emulator E2E", Test_vanguard_emulator_e2e.tests);
    ("VM-IR & Lazy Flags", Test_vm_ir.tests);
    ("x86_64 Lifter & CFG", Test_x86_lifter.tests);
    ("Anti-Analysis (MBA & CFF)", Test_anti_analysis.tests);
    ("Native Threaded VM", Test_native_vm.tests);
    ("Native VM Sub-width Semantics", Test_native_semantics.tests);
    ("Devirtualization Metrics", Test_metrics.tests);
    ("C Macro Obfuscation", Test_c_macro_obf.tests);
    ("VM Runtime Profile", Test_runtime_profile.tests);
    ("Compiler Pipeline & Equivalence", Test_compiler_pipeline.tests);
    ("ARM64 Lifter & CFG", Test_arm64_lifter.tests);
    ("Multi-VM & Direct Zero-Bridge", Test_multi_vm.tests);
    ("GPU Metal Acceleration & Synthesis", Test_gpu_synth.tests);
    ("Register-Driven JIT VM & RNS", Test_rd_jit_vm.tests);
    ("arXiv Innovations (POP/DefUse/NCFG/LitStitch)", Test_arxiv_innovations.tests);
    ("E-graph Equality Expansion (Scrambler)", Test_egraph_expansion.tests);
    ("Anti-Pushan Rolling Key", Test_anti_pushan.tests);
    ("Dynamic Anti-Tamper & SMC (Layer 3)", Test_anti_tamper_smc.tests);
    ("Protection Config (JSON/Presets)", Test_protection_config.tests);
    ("RISC-V Lifter & CFG", Test_riscv_lifter.tests);
    ("Stack-VM Execution Engine", Test_stack_vm.tests);
    ("Bytecode Cryptography & Integrity", Test_bytecode_crypto.tests);
    ("Tech-2601 Exception Handling", Test_tech_2601.tests);
    ("Tech-2603 Anti-VPC Tracking", Test_tech_2603.tests);
    ("Tech-2608 Anti-Trace-Synthesis", Test_tech_2608.tests);
    ("Computational Stalling (Anti-Emulation)", Test_comp_stall.tests);
    ("Ring Codec (Data-Space Automorphisms)", Test_ring_codec.tests);
    ("Null-Space MBA Synthesis", Test_nullspace_mba.tests);
    ("Cross-Seed Metrics", Test_cross_seed_metrics.tests);
    ("Metamorphic ISA & Ring Codec", Test_metamorphic_isa.tests);
    ("Mach-O Compact Unwind (LC_ROUTINES)", Test_macho.tests);
    ("Build-Seed Watermarking", Test_watermark.tests);
    ("Structured Logger", Test_logger.tests);
  ])


