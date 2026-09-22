open Cmdliner
open Random_visa_ports
open Protect_ports
open Random_visa_application

(* 7. PROTECT COMMAND (Automated x86_64 & C/C++ VM-Protector Pipeline via Hexagonal Architecture) *)
let run_protect input_file out_dir seed config_file preset enable_cff enable_mba mba_depth enable_multi_vm engine enable_jit compile_and_run =
  let resolved_engine =
    if enable_jit || engine = "jit" then "jit"
    else if enable_multi_vm || engine = "multi_vm" || engine = "multi-vm" then "multi_vm"
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

  let module X86_adapter = Protect_adapters.X86_lifter_adapter in
  let module C_macro_adapter = Protect_adapters.C_macro_obf_adapter in
  let module Trampoline_adapter = Protect_adapters.C_trampoline_adapter in
  let module Toolchain_adapter = Protect_adapters.Clang_toolchain_adapter in
  let module Vm_packager_adapters = Protect_adapters.Vm_packagers in

  let lifter = (module X86_adapter : Lifter) in
  let c_macro_obfuscator = (module C_macro_adapter : C_macro_obfuscator) in
  let trampoline_engine = (module Trampoline_adapter.C_trampoline_engine : Trampoline_engine) in
  let toolchain = (module Toolchain_adapter : Toolchain) in

  let vm_packager =
    if resolved_engine = "jit" then
      (module Vm_packager_adapters.Jit_vm_packager : Vm_packager)
    else if resolved_engine = "multi_vm" then
      (module Vm_packager_adapters.Multi_vm_packager : Vm_packager)
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
      prerr_endline (Printf.sprintf "VM Protection failed: %s" err);
      `Error (false, err)
  | Ok res ->
      print_endline res.metrics.formatted_summary;
      Printf.printf "Generated VM Runtime Header: %s\n" res.header_path;
      Printf.printf "Generated Protected Bytecode: %s (%d bytes)\n" res.bytecode_path res.bytecode_length_bytes;
      (match res.binary_path with
      | Some bin ->
          Printf.printf "\n[1/2] Compiling Native Protected Binary (Zero-Bloat / Stripped)...\n";
          Printf.printf "[2/2] Launching Protected Binary (%s):\n" bin;
          Printf.printf "--------------------------------------------------------\n";
          (match res.execution_output with
          | Some (code, out) ->
              print_string out;
              Printf.printf "--------------------------------------------------------\n\n";
              Printf.printf "--- Target Execution Complete (Return Code: %d) ---\n" code
          | None -> ());
      | None -> ());
      `Ok ()

let protect_cmd =
  let doc = "Virtualize and protect x86_64 assembly function with CFF, MBA, rolling key, and Direct Threaded VM" in
  let input =
    let doc = "Input x86_64 assembly file (.s / .asm)" in
    Arg.(required & opt (some string) None & info [ "i"; "input" ] ~docv:"FILE" ~doc)
  in
  let out_dir =
    let doc = "Output directory for VM runtime and protected bytecode" in
    Arg.(value & opt string "./protected_out" & info [ "o"; "output-dir" ] ~docv:"DIR" ~doc)
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
  let multi_vm =
    let doc = "Enable Heterogeneous Dual-VM Runtime (Math-VM & Flow-VM with Affine GL16 Zero-Bridge)" in
    Arg.(value & flag & info [ "multi-vm" ] ~doc)
  in
  let engine =
    let doc = "Virtual machine execution engine: threaded, multi_vm, or jit" in
    Arg.(value & opt string "threaded" & info [ "engine" ] ~docv:"ENGINE" ~doc)
  in
  let jit =
    let doc = "Enable Register-Driven JIT VM (RD-JIT with ephemeral native code synthesis)" in
    Arg.(value & flag & info [ "jit" ] ~doc)
  in
  let compile =
    let doc = "Compile native C++ runner and execute protected binary" in
    Arg.(value & opt bool true & info [ "compile" ] ~docv:"BOOL" ~doc)
  in
  let term = Term.(ret (const run_protect $ input $ out_dir $ seed $ config_file $ preset $ cff $ mba $ mba_depth $ multi_vm $ engine $ jit $ compile)) in
  Cmd.v (Cmd.info "protect" ~doc) term

let run_c_obf input out_file out_header seed strings consts mba_depth compile =
  match
    Protect_adapters.C_macro_obf_adapter.run_c_obfuscation
      ~input
      ~out_file
      ~out_header
      ~seed
      ~strings
      ~consts
      ~mba_depth
      ~compile
  with
  | Ok () -> `Ok ()
  | Error msg ->
      prerr_endline ("C Macro Obfuscation failed: " ^ msg);
      `Error (false, msg)

let c_obf_cmd =
  let doc = "Obfuscate C source code via polymorphic macros, stack string encryption, and MBA" in
  let input =
    let doc = "Input C source file (.c)" in
    Arg.(required & opt (some string) None & info [ "i"; "input" ] ~docv:"FILE" ~doc)
  in
  let out_file =
    let doc = "Output obfuscated C source file" in
    Arg.(value & opt string "./obfuscated.c" & info [ "o"; "output" ] ~docv:"FILE" ~doc)
  in
  let out_header =
    let doc = "Output companion header file path (defaults to asgard_obf.h next to output)" in
    Arg.(value & opt (some string) None & info [ "header" ] ~docv:"FILE" ~doc)
  in
  let seed =
    let doc = "Randomization seed" in
    Arg.(value & opt (some int) None & info [ "s"; "seed" ] ~docv:"SEED" ~doc)
  in
  let strings =
    let doc = "Enable compile-time stack string encryption" in
    Arg.(value & opt bool true & info [ "strings" ] ~docv:"BOOL" ~doc)
  in
  let consts =
    let doc = "Enable constant blinding" in
    Arg.(value & opt bool true & info [ "constants" ] ~docv:"BOOL" ~doc)
  in
  let mba_depth =
    let doc = "Mixed Boolean-Arithmetic expansion depth (1..4)" in
    Arg.(value & opt int 2 & info [ "mba-depth" ] ~docv:"DEPTH" ~doc)
  in
  let compile =
    let doc = "Compile obfuscated C with clang -O2 and execute" in
    Arg.(value & opt bool true & info [ "compile" ] ~docv:"BOOL" ~doc)
  in
  let term = Term.(ret (const run_c_obf $ input $ out_file $ out_header $ seed $ strings $ consts $ mba_depth $ compile)) in
  Cmd.v (Cmd.info "c-obf" ~doc) term

let run_init_config out_file preset =
  match Protect_adapters.Config_adapter.init_config ~out_file ~preset with
  | Ok () -> `Ok ()
  | Error err ->
      prerr_endline (Printf.sprintf "Preset error: %s" err);
      `Error (false, err)

let init_config_cmd =
  let doc = "Generate an annotated JSON protection configuration file for target binary" in
  let out_file =
    let doc = "Output configuration file path" in
    Arg.(value & opt string "asgard.json" & info [ "o"; "output" ] ~docv:"FILE" ~doc)
  in
  let preset =
    let doc = "Protection preset template (default, max_security, lightweight, stealth)" in
    Arg.(value & opt (some string) None & info [ "p"; "preset" ] ~docv:"PRESET" ~doc)
  in
  let term = Term.(ret (const run_init_config $ out_file $ preset)) in
  Cmd.v (Cmd.info "init-config" ~doc) term
