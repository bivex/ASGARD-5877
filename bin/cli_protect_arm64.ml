open Cmdliner
open Random_visa_ports
open Protect_ports
open Random_visa_application

(* 7b. PROTECT-ARM64 COMMAND (Automated ARM64 Native Lifter & VM Pipeline via Hexagonal Architecture) *)
let run_protect_arm64 input_file out_dir seed config_file preset enable_cff enable_mba mba_depth engine enable_jit compile_and_run =
  let resolved_engine =
    if enable_jit || engine = "jit" then "jit"
    else "threaded"
  in
  let base_cfg =
    match config_file with
    | Some path -> (
        match Native_vm.Protection_config.from_file path with
        | Ok c -> c
        | Error err ->
            prerr_endline (Printf.sprintf "[Config] Warning: %s, using default" err);
            Native_vm.Protection_config.default)
    | None -> (
        match preset with
        | Some p -> (
            match Native_vm.Protection_config.from_preset p with
            | Ok c -> c
            | Error err ->
                prerr_endline (Printf.sprintf "[Preset] Warning: %s, using default" err);
                Native_vm.Protection_config.default)
        | None -> Native_vm.Protection_config.default)
  in

  let resolved_cff = if enable_cff then true else base_cfg.cff.enabled in
  let resolved_mba = if enable_mba then true else base_cfg.mba.enabled in
  let resolved_mba_depth = if mba_depth <> 2 then mba_depth else base_cfg.mba.depth in
  let resolved_seed =
    match seed with
    | Some s -> Some s
    | None -> base_cfg.seed
  in
  let effective_cfg = {
    base_cfg with
    seed = resolved_seed;
    cff = { base_cfg.cff with enabled = resolved_cff };
    mba = { base_cfg.mba with enabled = resolved_mba; depth = resolved_mba_depth };
  } in

  let rng =
    match effective_cfg.seed with
    | Some s -> Random.State.make [| s |]
    | None ->
        let s = Random.self_init (); Random.bits () in
        Random.State.make [| s |]
  in

  let module Arm64_adapter = Protect_adapters.Arm64_lifter_adapter in
  let module C_macro_adapter = Protect_adapters.C_macro_obf_adapter in
  let module Trampoline_adapter = Protect_adapters.C_trampoline_adapter in
  let module Toolchain_adapter = Protect_adapters.Clang_toolchain_adapter in
  let module Vm_packager_adapters = Protect_adapters.Vm_packagers in

  let lifter = (module Arm64_adapter : Lifter) in
  let c_macro_obfuscator = (module C_macro_adapter : C_macro_obfuscator) in
  let trampoline_engine = (module Trampoline_adapter.C_trampoline_engine : Trampoline_engine) in
  let toolchain = (module Toolchain_adapter : Toolchain) in

  let vm_packager =
    if resolved_engine = "jit" then
      (module Vm_packager_adapters.Jit_vm_packager : Vm_packager)
    else
      (module Vm_packager_adapters.Threaded_vm_packager : Vm_packager)
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
      prerr_endline (Printf.sprintf "ARM64 VM Protection failed: %s" err);
      `Error (false, err)
  | Ok res ->
      print_endline (Native_vm.Metrics.report_to_string res.metrics);
      Printf.printf "Generated ARM64 VM Header: %s\n" res.header_path;
      Printf.printf "Generated ARM64 Protected Bytecode: %s (%d bytes)\n" res.bytecode_path res.bytecode_length_bytes;
      (match res.binary_path with
      | Some bin ->
          Printf.printf "\n[1/2] Compiling Native ARM64 Protected Binary...\n";
          Printf.printf "[2/2] Launching ARM64 Protected Binary (%s):\n" bin;
          Printf.printf "--------------------------------------------------------\n";
          (match res.execution_output with
          | Some (code, out) ->
              print_string out;
              Printf.printf "--------------------------------------------------------\n\n";
              Printf.printf "--- Target Execution Complete (Return Code: %d) ---\n" code
          | None -> ());
      | None -> ());
      `Ok ()

let protect_arm64_cmd =
  let doc = "Virtualize and protect ARM64 assembly or C source with ARM64 Lifter, CFF, MBA, and Direct Threaded or RD-JIT VM" in
  let input =
    let doc = "Input ARM64 assembly (.s / .asm) or C source (.c)" in
    Arg.(required & opt (some string) None & info [ "i"; "input" ] ~docv:"FILE" ~doc)
  in
  let out_dir =
    let doc = "Output directory for VM runtime and protected bytecode" in
    Arg.(value & opt string "./protected_arm64_out" & info [ "o"; "output-dir" ] ~docv:"DIR" ~doc)
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
    let doc = "Virtual machine execution engine: threaded or jit" in
    Arg.(value & opt string "threaded" & info [ "engine" ] ~docv:"ENGINE" ~doc)
  in
  let jit =
    let doc = "Enable Register-Driven JIT VM (RD-JIT with ephemeral native code synthesis)" in
    Arg.(value & flag & info [ "jit" ] ~doc)
  in
  let compile =
    let doc = "Compile native C++ runner and execute protected ARM64 binary" in
    Arg.(value & opt bool true & info [ "compile" ] ~docv:"BOOL" ~doc)
  in
  let term = Term.(ret (const run_protect_arm64 $ input $ out_dir $ seed $ config_file $ preset $ cff $ mba $ mba_depth $ engine $ jit $ compile)) in
  Cmd.v (Cmd.info "protect-arm64" ~doc) term
