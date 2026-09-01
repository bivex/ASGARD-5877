(lang dune 3.0)
(using menhir 2.1)
(name random_visa)
(version 0.1.0)
(generate_opam_files true)
(package
 (name random_visa)
 (synopsis "Hexagonal DDD Random Sail (V-ISA) Synthesizer and Emulator Generator in OCaml")
 (depends
  (ocaml (>= 4.14.0))
  (dune (>= 3.0))
  cmdliner
  jingoo
  menhir
  alcotest
  qcheck
  qcheck-alcotest
  yojson))

(package
 (name vanguard-9292)
 (synopsis "Polymorphic Dynamic Bytecode Obfuscation Layer for Random vISA")
 (depends
  (ocaml (>= 4.14.0))
  (dune (>= 3.0))
  random_visa))
