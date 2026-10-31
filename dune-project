(lang dune 3.0)
(using menhir 2.1)
(name asgard)
(version 0.4.0)
(generate_opam_files true)
(package
 (name asgard)
 (synopsis "Hexagonal DDD Random Sail (V-ISA) Synthesizer and Emulator Generator in OCaml")
 (license BUSL-1.1)
 (depends
  (ocaml (>= 4.14.0))
  (dune (>= 3.0))
  cmdliner
  menhir
  alcotest
  qcheck
  qcheck-alcotest
  bos
  fpath
  yojson
  ppx_deriving_yojson
  ocamlgraph))
