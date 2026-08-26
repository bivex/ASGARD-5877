let () =
  Alcotest.run "Random_vISA_Tests" [
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
  ]
