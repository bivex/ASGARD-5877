open Cmdliner

(* 7. PROTECT COMMAND (Full Automated x86_64 & C/C++ VM-Protector Pipeline) *)
let run_protect input_file out_dir seed config_file preset enable_cff enable_mba mba_depth enable_multi_vm compile_and_run =
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

  if not (Sys.file_exists input_file) then begin
    prerr_endline (Printf.sprintf "Input file not found: %s" input_file);
    `Error (false, "File not found")
  end else begin
    (try Sys.mkdir out_dir 0o755 with _ -> ());
    let is_c_src = String.ends_with ~suffix:".c" input_file || String.ends_with ~suffix:".cpp" input_file in

    let asm_source_file =
      if is_c_src && effective_cfg.c_macro.enabled then begin
        let hdr_path = Filename.concat out_dir "asgard_obf.h" in
        let obf_c_path = Filename.concat out_dir "app_obf.c" in
        let seed_val = Random.State.int rng 0x3FFFFFFF in
        let config : C_macro_obf.config = {
          seed = seed_val;
          mba_depth = effective_cfg.mba.depth;
          macro_prefix = effective_cfg.c_macro.macro_prefix;
          obfuscate_strings = effective_cfg.c_macro.obfuscate_strings;
          obfuscate_constants = effective_cfg.c_macro.obfuscate_constants;
          obfuscate_arithmetic = effective_cfg.c_macro.obfuscate_arithmetic;
          inject_opaque_predicates = effective_cfg.c_macro.opaque_predicates;
          api_hashing = effective_cfg.c_macro.api_hashing;
          anti_debug = effective_cfg.c_macro.anti_debug;
          signal_dispatch = effective_cfg.c_macro.signal_dispatch;
          timing_guard = effective_cfg.c_macro.timing_guard;
          timing_threshold_ticks = effective_cfg.c_macro.timing_threshold_ticks;
        } in
        (match C_macro_obf.transform_file ~config ~in_file:input_file ~out_file:obf_c_path ~header_file:(Some hdr_path) () with
        | Ok () -> ()
        | Error err -> prerr_endline (Printf.sprintf "C pre-transform warning: %s" err));

        let asm_out = Filename.concat out_dir "app.s" in
        let gen_asm_cmd = Printf.sprintf "clang -S -target x86_64-apple-darwin -masm=intel -O1 -fno-stack-protector -Wno-format-security -I%s -fno-asynchronous-unwind-tables %s -o %s" out_dir obf_c_path asm_out in
        let _ = Sys.command gen_asm_cmd in
        asm_out
      end else input_file
    in

    let ic = open_in asm_source_file in
    let len = in_channel_length ic in
    let text = really_input_string ic len in
    close_in ic;

    let raw_lines =
      match X86_lifter.X86_parser.parse_lines text with
      | Ok lines -> lines
      | Error err ->
          prerr_endline (Printf.sprintf "Parser warning: %s, falling back to full function" err);
          []
    in

    let regions =
      if raw_lines <> [] then X86_lifter.Lifter.extract_marked_regions raw_lines
      else []
    in

    if List.length regions > 1 || (List.length regions = 1 && (match fst (List.hd regions) with X86_lifter.X86_parser.ModeUltra "main" -> false | _ -> true)) then
      Printf.printf "[VM-Protector] Auto-detected %d marker protected region(s) in source.\n" (List.length regions);

    match X86_lifter.Lifter.lift_function text with
    | Error err ->
        prerr_endline (Printf.sprintf "Lifter failed: %s" err);
        `Error (false, err)
    | Ok lifted_func ->
        let (runtime_src, runner_src, bc, metrics, hdr_name) =
          if enable_multi_vm then
            let mv_pkg =
              Multi_vm.Multi_vm_emitter.compile_and_package
                ~rng
                ~enable_cff:resolved_cff
                ~enable_mba:resolved_mba
                ~mba_depth:resolved_mba_depth
                ~config:effective_cfg
                lifted_func
            in
            (mv_pkg.cpp_runtime_source, mv_pkg.runner_source, mv_pkg.bytecode, mv_pkg.metrics, "multi_vm_runtime.hpp")
          else
            let pkg =
              Native_vm.Vm_emitter.compile_and_package
                ~rng
                ~config:effective_cfg
                lifted_func
            in
            (pkg.cpp_runtime_source, pkg.runner_source, pkg.bytecode, pkg.metrics, "threaded_vm.hpp")
        in

        let hdr_path = Filename.concat out_dir hdr_name in
        let oc_h = open_out hdr_path in
        output_string oc_h runtime_src;
        close_out oc_h;

        if enable_multi_vm then begin
          let comp_hdr = Filename.concat out_dir "threaded_vm.hpp" in
          let oc_ch = open_out comp_hdr in
          output_string oc_ch runtime_src;
          close_out oc_ch;
        end;

        let runner_path = Filename.concat out_dir "runner.cpp" in
        let oc_r = open_out runner_path in
        output_string oc_r runner_src;
        close_out oc_r;

        let bc_path = Filename.concat out_dir "protected.vanguard" in
        let oc_b = open_out_bin bc_path in
        List.iter
          (fun w ->
            for i = 0 to 7 do
              let b = Int64.to_int (Int64.logand (Int64.shift_right_logical w (i * 8)) 0xFFL) in
              output_byte oc_b b
            done)
          bc;
        close_out oc_b;

        print_endline (Native_vm.Metrics.report_to_string metrics);
        Printf.printf "Generated VM Runtime Header: %s\n" hdr_path;
        Printf.printf "Generated Protected Bytecode: %s (%d bytes)\n" bc_path (List.length bc * 8);

        if compile_and_run then begin
          let bin_path = Filename.concat out_dir (if is_c_src then "protected_app" else "protected_runner") in
          let comp_src = if is_c_src then Filename.concat out_dir "app_obf.c" else runner_path in
          let compiler = if is_c_src then "clang -O3 -Wno-format-security" else "clang++ -std=c++20 -O3 -Wno-format-security -fvisibility-inlines-hidden" in
          let comp_cmd = Printf.sprintf "%s -fno-rtti -fno-exceptions -fno-unwind-tables -fno-asynchronous-unwind-tables -fvisibility=hidden -Wl,-dead_strip -Wl,-x -I%s %s -o %s && strip -x %s" compiler out_dir comp_src bin_path bin_path in

          Printf.printf "\n[1/2] Compiling Native Protected Binary (Zero-Bloat / Stripped) with %s...\n" (if is_c_src then "clang -O3" else "clang++ -O3");
          flush stdout;
          let comp_status = Sys.command comp_cmd in
          if comp_status <> 0 then begin
            prerr_endline "Native compilation failed";
            `Error (false, "Compilation error")
          end else begin
            Printf.printf "[2/2] Launching Protected Binary:\n";
            Printf.printf "--------------------------------------------------------\n";
            flush stdout;
            let run_cmd = Printf.sprintf "%s" bin_path in
            let _ = Sys.command run_cmd in
            Printf.printf "--------------------------------------------------------\n\n";
            flush stdout;
            `Ok ()
          end
        end else `Ok ()
  end

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
  let compile =
    let doc = "Compile native C++ runner and execute protected binary" in
    Arg.(value & opt bool true & info [ "compile" ] ~docv:"BOOL" ~doc)
  in
  let term = Term.(ret (const run_protect $ input $ out_dir $ seed $ config_file $ preset $ cff $ mba $ mba_depth $ multi_vm $ compile)) in
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
    signal_dispatch = true;
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
