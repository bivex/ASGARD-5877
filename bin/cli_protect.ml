open Cmdliner
open Random_visa_ports
open Protect_ports
open Random_visa_application
open Protect_adapters

(* 7. PROTECT COMMAND (Automated x86_64 & C/C++ VM-Protector Pipeline via Hexagonal Architecture) *)
let run_protect input_file out_dir seed config_file preset enable_cff enable_mba mba_depth enable_multi_vm engine enable_jit compile_and_run =
  let resolved_engine =
    if enable_jit || engine = "jit" then "jit"
    else if enable_multi_vm || engine = "multi_vm" || engine = "multi-vm" then "multi_vm"
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

  let lifter = (module X86_lifter_adapter : Lifter) in
  let c_macro_obfuscator = (module C_macro_obf_adapter : C_macro_obfuscator) in
  let trampoline_engine = (module C_trampoline_adapter.C_trampoline_engine : Trampoline_engine) in
  let toolchain = (module Clang_toolchain_adapter : Toolchain) in

  let vm_packager =
    if resolved_engine = "jit" then
      (module Vm_packagers.Jit_vm_packager : Vm_packager)
    else if resolved_engine = "multi_vm" then
      (module Vm_packagers.Multi_vm_packager : Vm_packager)
    else
      (module Vm_packagers.Threaded_vm_packager : Vm_packager)
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
      print_endline (Native_vm.Metrics.report_to_string res.metrics);
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
  let seed_val = match seed with Some s -> s | None -> Random.self_init (); Random.int 0x3FFFFFFF in

  let config : C_macro_obf.config = {
    seed = seed_val;
    mba_depth;
    obfuscate_strings = strings;
    obfuscate_constants = consts;
    obfuscate_arithmetic = true;
    inject_opaque_predicates = true;
    api_hashing = true;
    anti_debug = true;
    signal_dispatch = false;
    nanomites = false;
    timing_guard = true;
    timing_threshold_ticks = 50000000L;
    macro_prefix = "ASG_";
  } in
  let header_path = match out_header with
    | Some p -> p
    | None ->
        let dir = Filename.dirname out_file in
        Filename.concat (if dir = "" then "." else dir) "asgard_obf.h"
  in
  match C_macro_obf.transform_file ~config ~in_file:input ~out_file ~header_file:(Some header_path) () with
  | Error msg ->
      prerr_endline ("C Macro Obfuscation failed: " ^ msg);
      `Error (false, msg)
  | Ok () ->
      Printf.printf "=== C MACRO OBFUSCATION COMPLETE ===\n";
      Printf.printf "  Input C Source:       %s\n" input;
      Printf.printf "  Obfuscated Output:    %s\n" out_file;
      Printf.printf "  Generated Header:     %s\n" header_path;
      Printf.printf "  Random Seed:          0x%X\n" seed_val;
      Printf.printf "  String Encryption:    %s\n" (if strings then "ENABLED" else "DISABLED");
      Printf.printf "  Constant Blinding:    %s\n" (if consts then "ENABLED" else "DISABLED");
      Printf.printf "  MBA Depth:            %d\n" mba_depth;
      Printf.printf "====================================\n\n";
      if compile then begin
        let bin_path = (try Filename.chop_extension out_file with _ -> out_file) ^ "_bin" in
        let comp_cmd = Printf.sprintf "clang -O2 -I%s %s -o %s" (Filename.dirname header_path) out_file bin_path in
        Printf.printf "[1/2] Compiling obfuscated C source with clang -O2...\n";
        let status = Sys.command comp_cmd in
        if status <> 0 then begin
          prerr_endline "Clang compilation failed!";
          `Error (false, "Compilation error")
        end else begin
          Printf.printf "[2/2] Running Obfuscated Binary (%s):\n" bin_path;
          Printf.printf "--------------------------------------------------------\n";
          let _ = Sys.command bin_path in
          Printf.printf "--------------------------------------------------------\n\n";
          `Ok ()
        end
      end else `Ok ()

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
  let cfg =
    match preset with
    | Some p -> (
        match Native_vm.Protection_config.from_preset p with
        | Ok c -> c
        | Error err ->
            prerr_endline (Printf.sprintf "Preset error: %s, using default" err);
            Native_vm.Protection_config.default)
    | None -> Native_vm.Protection_config.default
  in
  Native_vm.Protection_config.save_to_file out_file cfg;
  Printf.printf "[ASGARD-5877] Protection configuration saved: %s\n" out_file;
  `Ok ()

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
