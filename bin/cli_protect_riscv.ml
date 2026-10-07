open Cmdliner
open Random_visa_ports
open Protect_ports
open Random_visa_application

(* 7c. PROTECT-RISCV COMMAND (Automated RISC-V RV64GC Native Lifter & VM Pipeline via Hexagonal Architecture) *)
let run_protect_riscv input_file out_dir seed config_file preset enable_cff enable_mba mba_depth engine enable_jit compile_and_run =
  let resolved_engine =
    if enable_jit || engine = "jit" then "jit"
    else if engine = "stack" then "stack"
    else if engine = "multi" || engine = "multi_vm" then "multi"
    else "threaded"
  in
  let effective_cfg =
    Protect_adapters.Config_adapter.resolve
      ~config_file
      ~preset
      ~enable_cff
      ~enable_mba
      ~mba_depth
      ~seed
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
      ~compile_and_run
      ()
  with
  | Error err ->
      prerr_endline (Printf.sprintf "RISC-V VM Protection failed: %s" err);
      `Error (false, err)
  | Ok res ->
      print_endline res.metrics.formatted_summary;
      Printf.printf "Generated RISC-V VM Header: %s\n" res.header_path;
      Printf.printf "Generated RISC-V Protected Bytecode: %s (%d bytes)\n" res.bytecode_path res.bytecode_length_bytes;
      (match res.binary_path with
      | Some bin ->
          Printf.printf "\n[1/2] Compiling Native RISC-V Protected Binary...\n";
          Printf.printf "[2/2] Launching RISC-V Protected Binary (%s):\n" bin;
          Printf.printf "--------------------------------------------------------\n";
          (match res.execution_output with
          | Some (code, out) ->
              print_string out;
              Printf.printf "--------------------------------------------------------\n\n";
              Printf.printf "--- Target Execution Complete (Return Code: %d) ---\n" code
          | None -> ());
      | None -> ());
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
    let doc = "Protection preset (default, max_security, lightweight, stealth)" in
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
    let doc = "Compile native C++ runner and execute protected RISC-V binary" in
    Arg.(value & opt bool false & info [ "compile" ] ~docv:"BOOL" ~doc)
  in
  let term = Term.(ret (const run_protect_riscv $ input $ out_dir $ seed $ config_file $ preset $ cff $ mba $ mba_depth $ engine $ jit $ compile)) in
  Cmd.v (Cmd.info "protect-riscv" ~doc) term
