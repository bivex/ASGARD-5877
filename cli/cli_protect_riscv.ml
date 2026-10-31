open Cmdliner
open Random_visa_ports
open Protect_ports
open Random_visa_application

(* 7c. PROTECT-RISCV COMMAND (Automated RISC-V RV64GC Native Lifter & VM Pipeline via Hexagonal Architecture) *)
let run_protect_riscv input_file out_dir seed config_file preset enable_cff enable_mba mba_depth engine enable_jit compile debug_symbols comp_stall comp_stall_iterations comp_stall_variant comp_stall_seed =
  let resolved_engine =
    if enable_jit || engine = "jit" then "jit"
    else if engine = "stack" then "stack"
    else if engine = "multi" || engine = "multi_vm" then "multi"
    else "threaded"
  in
  let comp_stall_seed_val =
    match comp_stall_seed with
    | Some s -> (try Some (Int64.of_string s) with _ -> None)
    | None -> None
  in
  let effective_cfg =
    let resolved =
      Protect_adapters.Config_adapter.resolve_with_watermark
        ~watermark:None
        ~config_file
        ~preset
        ~enable_cff
        ~enable_mba
        ~mba_depth
        ?enable_comp_stall:comp_stall
        ?comp_stall_iterations
        ?comp_stall_variant
        ?comp_stall_seed:comp_stall_seed_val
        ~seed
        ()
    in
    let raw = Protect_adapters.Config_adapter.unwrap resolved in
    Protect_adapters.Config_adapter.wrap { raw with arch = `RISCV }
  in
  let rng =
    match Protect_ports.seed effective_cfg with
    | Some s -> Random.State.make [| s |]
    | None ->
        let s = Random.self_init (); Random.bits () in
        Random.State.make [| s |]
  in

  let module Riscv_adapter = Protect_adapters.Riscv_lifter_adapter in
  let module C_macro_adapter = Protect_adapters.C_macro_obf_adapter in
  let module Trampoline_adapter = Protect_adapters.C_trampoline_adapter in
  let module Toolchain_adapter = Protect_adapters.Clang_toolchain_adapter in
  let module Vm_packager_adapters = Protect_adapters.Vm_packagers in

  let lifter = (module Riscv_adapter : Lifter) in
  let c_macro_obfuscator = (module C_macro_adapter : C_macro_obfuscator) in
  let trampoline_engine = (module Trampoline_adapter.C_trampoline_engine : Trampoline_engine) in
  let toolchain = (module Toolchain_adapter : Toolchain) in

  let vm_packager =
    match resolved_engine with
    | "jit" -> (module Vm_packager_adapters.Jit_vm_packager : Vm_packager)
    | "stack" -> (module Vm_packager_adapters.Stack_vm_packager : Vm_packager)
    | "multi" -> (module Vm_packager_adapters.Multi_vm_packager : Vm_packager)
    | _ -> (module Vm_packager_adapters.Threaded_vm_packager : Vm_packager)
  in

  match
    Protect_pipeline.run
      ~lifter
      ~c_macro_obfuscator
      ~vm_packager
      ~trampoline_engine
      ~toolchain
      ~rng
      ~config:effective_cfg
      ~input_file
      ~out_dir
      ~compile
      ~debug_symbols
      ()
  with
  | Error err ->
      Logger.errorf ~section:"CLI" "RISC-V VM Protection failed: %s" err;
      `Error (false, err)
  | Ok res ->
      print_endline res.metrics.formatted_summary;
      `Ok ()

let protect_riscv_cmd =
  let doc = "Virtualize and protect RISC-V assembly or C source with RISC-V Lifter, CFF, MBA, and Direct Threaded VM" in
  let input =
    let doc = "Input RISC-V assembly (.s / .asm) or C source (.c)" in
    Arg.(required & opt (some string) None & info [ "i"; "input" ] ~docv:"FILE" ~doc)
  in
  let out_dir =
    let doc = "Output directory for VM runtime and protected bytecode" in
    Arg.(value & opt string "./protected_riscv_out" & info [ "o"; "output-dir" ] ~docv:"DIR" ~doc)
  in
  let seed =
    let doc = "Randomization seed" in
    Arg.(value & opt (some int) None & info [ "s"; "seed" ] ~docv:"SEED" ~doc)
  in
  let config_file =
    let doc = "Path to JSON protection configuration file" in
    Arg.(value & opt (some string) None & info [ "c"; "config" ] ~docv:"FILE" ~doc)
  in
  let preset =
    let doc = "Protection preset (default, max_security, stealth, edr_stealth)" in
    Arg.(value & opt (some string) None & info [ "p"; "preset" ] ~docv:"PRESET" ~doc)
  in
  let cff =
    let doc = "Enable Control-Flow Flattening (CFF) with state dispatcher" in
    Arg.(value & flag & info [ "cff"; "flatten" ] ~doc)
  in
  let mba =
    let doc = "Enable Mixed Boolean-Arithmetic (MBA) rewriting" in
    Arg.(value & flag & info [ "mba" ] ~doc)
  in
  let mba_depth =
    let doc = "Mixed Boolean-Arithmetic recursion depth (1..4)" in
    Arg.(value & opt int 2 & info [ "mba-depth" ] ~docv:"DEPTH" ~doc)
  in
  let engine =
    let doc = "Virtual machine execution engine: threaded, jit, multi, or stack" in
    Arg.(value & opt string "threaded" & info [ "engine" ] ~docv:"ENGINE" ~doc)
  in
  let jit =
    let doc = "Enable Register-Driven JIT VM (RD-JIT with ephemeral native code synthesis)" in
    Arg.(value & flag & info [ "jit" ] ~doc)
  in
  let compile =
    let doc = "Compile native protected binary with Clang" in
    Arg.(value & opt bool false & info [ "compile" ] ~docv:"BOOL" ~doc)
  in
  let debug_symbols =
    let doc = "Preserve DWARF debug symbols and generate .dSYM for debugging/auditing in IDA" in
    Arg.(value & flag & info [ "g"; "debug-symbols" ] ~doc)
  in
  let comp_stall =
    let doc = "Enable Computational Stalling anti-emulation loop inside bytecode" in
    Arg.(value & opt (some bool) None & info [ "comp-stall" ] ~docv:"BOOL" ~doc)
  in
  let comp_stall_iterations =
    let doc = "Number of computational stalling iterations inside bytecode (e.g. 50000)" in
    Arg.(value & opt (some int) None & info [ "comp-stall-iterations"; "stall-iters" ] ~docv:"ITERS" ~doc)
  in
  let comp_stall_variant =
    let doc = "Computational stalling dynamical system variant (ergodic, chebyshev, two_adic, time_lock)" in
    Arg.(value & opt (some string) None & info [ "comp-stall-variant"; "stall-variant" ] ~docv:"VARIANT" ~doc)
  in
  let comp_stall_seed =
    let doc = "Custom 64-bit seed for computational stalling key derivation (hex or decimal)" in
    Arg.(value & opt (some string) None & info [ "comp-stall-seed" ] ~docv:"SEED" ~doc)
  in
  let term = Term.(ret (const run_protect_riscv $ input $ out_dir $ seed $ config_file $ preset $ cff $ mba $ mba_depth $ engine $ jit $ compile $ debug_symbols $ comp_stall $ comp_stall_iterations $ comp_stall_variant $ comp_stall_seed)) in
  Cmd.v (Cmd.info "protect-riscv" ~doc) term
