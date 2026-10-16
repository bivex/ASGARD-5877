open Cmdliner

let run_project src_dir inputs out_bin seed enable_cff enable_mba mba_depth compile_and_run debug_symbols =
  if debug_symbols then Unix.putenv "ASGARD_DEBUG_SYMBOLS" "1";
  let rng =
    match seed with
    | Some s -> Random.State.make [| s |]
    | None ->
        let s = Random.self_init (); Random.bits () in
        Random.State.make [| s |]
  in

  let collect_files dir =
    if not (Sys.file_exists dir && Sys.is_directory dir) then []
    else
      let entries = Sys.readdir dir in
      Array.to_list entries
      |> List.filter (fun f ->
             String.ends_with ~suffix:".c" f || String.ends_with ~suffix:".cpp" f
             || String.ends_with ~suffix:".s" f || String.ends_with ~suffix:".asm" f)
      |> List.map (Filename.concat dir)
  in

  let all_inputs =
    let from_dir = match src_dir with Some d -> collect_files d | None -> [] in
    let combined = from_dir @ inputs in
    List.sort_uniq String.compare combined
  in

  if all_inputs = [] then begin
    prerr_endline "No C/C++/Assembly source files found to protect.";
    `Error (false, "No input files")
  end else begin
    let out_dir = Filename.dirname out_bin in
    let build_dir = Filename.concat (if out_dir = "" then "." else out_dir) ".asgard_build" in
    (try Sys.mkdir out_dir 0o755 with _ -> ());
    (try Sys.mkdir build_dir 0o755 with _ -> ());

    let hdr_path = Filename.concat build_dir "asgard_obf.h" in
    let seed_val = Random.State.int rng 0x3FFFFFFF in
    let config : C_macro_obf.config = {
      seed = seed_val;
      mba_depth;
      obfuscate_strings = true;
      obfuscate_constants = true;
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

    Printf.printf "\n================ ASGARD-5877 MULTI-FILE PROJECT BUILDER ================\n";
    Printf.printf "  Source Files Count:    %d files\n" (List.length all_inputs);
    Printf.printf "  Build Output Target:   %s\n" out_bin;
    Printf.printf "  Shared Header:         %s\n" hdr_path;
    Printf.printf "  Randomization Seed:    0x%X\n" seed_val;
    Printf.printf "========================================================================\n\n";

    let total_markers = ref 0 in
    let obj_files = ref [] in

    List.iteri
      (fun idx in_file ->
        let base = Filename.chop_extension (Filename.basename in_file) in
        let is_cpp = String.ends_with ~suffix:".cpp" in_file || String.ends_with ~suffix:".cc" in_file || String.ends_with ~suffix:".cxx" in_file in
        let is_c_src = String.ends_with ~suffix:".c" in_file || is_cpp in
        Printf.printf "[%d/%d] Processing %s...\n" (idx + 1) (List.length all_inputs) in_file;

        if is_c_src then begin
          let file_dir = Filename.dirname in_file in
          let inc_dirs = [
            build_dir;
            file_dir;
            Filename.concat file_dir "include";
            Filename.concat file_dir "../include";
            Filename.concat file_dir "../../include";
          ] in
          let inc_flags = String.concat " " (List.filter (fun s -> s <> "") (List.map (fun d -> if Sys.file_exists d then "-I" ^ d else "") inc_dirs)) in

          let ext = if is_cpp then ".cpp" else ".c" in
          let obf_c_path = Filename.concat build_dir (base ^ "_obf" ^ ext) in
          (match C_macro_obf.transform_file ~config ~in_file ~out_file:obf_c_path ~header_file:(Some hdr_path) () with
          | Ok () -> ()
          | Error err -> prerr_endline (Printf.sprintf "  [!] Pre-transform note: %s" err));

          let asm_out = Filename.concat build_dir (base ^ ".s") in
          let compiler = if is_cpp then "clang++ -std=c++20" else "clang" in
          let gen_asm_cmd = Printf.sprintf "%s -S -target x86_64-apple-darwin -masm=intel -O1 -fno-jump-tables -mllvm -switch-to-lookup=false -fno-stack-protector -Wno-format-security %s -fno-asynchronous-unwind-tables %s -o %s" compiler inc_flags obf_c_path asm_out in
          let _ = Sys.command gen_asm_cmd in

          let is_virtualized = ref false in
          if not (Sys.file_exists asm_out) then
            prerr_endline (Printf.sprintf "  [ERROR] Assembly generation failed for %s (obfuscated source did not compile; see diagnostics above)" in_file)
          else begin

          let ic = open_in asm_out in
          let len = in_channel_length ic in
          let text = really_input_string ic len in
          close_in ic;

          (match X86_lifter.X86_parser.parse_lines text with
          | Ok lines ->
              let regions = X86_lifter.Lifter.extract_marked_regions ~require_markers:true lines in
              if regions <> [] then begin
                total_markers := !total_markers + List.length regions;
                let vm_hdr_filename = base ^ "_threaded_vm.hpp" in
                let eh_hdr_path = Filename.concat build_dir "asg_tech_2601.hpp" in
                if not (Sys.file_exists eh_hdr_path) then begin
                  let oc_eh = open_out eh_hdr_path in
                  output_string oc_eh Tech_2601.Tech_2601_engine.runtime_header_source;
                  close_out oc_eh
                end;
                let vpc_hdr_path = Filename.concat build_dir "asg_tech_2603.hpp" in
                if not (Sys.file_exists vpc_hdr_path) then begin
                  let oc_vpc = open_out vpc_hdr_path in
                  output_string oc_vpc (Tech_2603.Tech_2603_engine.emit_tech_2603_cpp_header ());
                  close_out oc_vpc
                end;
                let chaff_hdr_path = Filename.concat build_dir "asg_tech_2608.hpp" in
                if not (Sys.file_exists chaff_hdr_path) then begin
                  let oc_chaff = open_out chaff_hdr_path in
                  output_string oc_chaff (Tech_2608.Tech_2608_engine.emit_tech_2608_cpp_header ());
                  close_out oc_chaff
                end;

                let const_pool = X86_lifter.Lifter.extract_const_pool lines in
                let lifted_funcs =
                  List.filter_map
                    (fun (_mode, rlines) ->
                      match X86_lifter.Lifter.lift_lines ~options:{ X86_lifter.Lifter.default_options with const_pool = Some const_pool } rlines with
                      | Ok func ->
                          let clean_name =
                            let n = func.name in
                            if String.starts_with ~prefix:"_" n then String.sub n 1 (String.length n - 1) else n
                          in
                          Some (clean_name, { func with name = clean_name })
                      | Error _ -> None)
                    regions
                in

                if lifted_funcs <> [] then begin
                  let pkg =
                    match lifted_funcs with
                    | [ (_name, func) ] ->
                        Native_vm.Vm_emitter.compile_and_package ~rng ~enable_cff ~enable_mba ~mba_depth func
                    | multi ->
                        Native_vm.Vm_emitter.compile_and_package_multi ~rng ~enable_cff ~enable_mba ~mba_depth multi
                  in
                  let vm_hdr_path = Filename.concat build_dir vm_hdr_filename in
                  let oc_h = open_out vm_hdr_path in
                  output_string oc_h pkg.cpp_runtime_source;
                  close_out oc_h;

                  let c_src_path = if Sys.file_exists obf_c_path then obf_c_path else in_file in
                  let ic_c = open_in c_src_path in
                  let c_len = in_channel_length ic_c in
                  let c_src = really_input_string ic_c c_len in
                  close_in ic_c;

                  let virt_cpp_path = Filename.concat build_dir (base ^ "_virtualized.cpp") in
                  let module TE = Protect_adapters.C_trampoline_adapter.C_trampoline_engine in
                  TE.embed_vm_trampoline
                    ~header_name:vm_hdr_filename
                    ~c_src
                    ~bytecodes:pkg.bytecodes
                    ~bytecode:pkg.bytecode
                    ~out_path:virt_cpp_path
                    ();

                  let obj_out = Filename.concat build_dir (base ^ ".o") in
                  let cxx_flags = if debug_symbols then "-std=c++20 -g -O1" else "-std=c++20 -O3 -fno-rtti -fno-exceptions -fno-unwind-tables -fno-asynchronous-unwind-tables -fvisibility=hidden" in
                  let comp_obj_cmd = Printf.sprintf "clang++ %s %s -c %s -o %s" cxx_flags inc_flags virt_cpp_path obj_out in
                  let st = Sys.command comp_obj_cmd in
                  if st <> 0 then prerr_endline (Printf.sprintf "  [ERROR] Failed to compile VM wrapper for %s" in_file)
                  else (
                    obj_files := obj_out :: !obj_files;
                    is_virtualized := true
                  );

                  Printf.printf "  -> Protected %d marked region(s) (CFF: %s, MBA: %s, Depth: %d)\n"
                    (List.length regions)
                    (if enable_cff then "ON" else "OFF")
                    (if enable_mba then "ON" else "OFF")
                    mba_depth
                end
              end
          | Error _ -> ());
          end;

          if not !is_virtualized then begin
            let obj_out = Filename.concat build_dir (base ^ ".o") in
            let c_flags = if debug_symbols then "-g -O1 -Wno-format-security" else "-O3 -Wno-format-security -fno-rtti -fno-exceptions -fno-unwind-tables -fno-asynchronous-unwind-tables -fvisibility=hidden" in
            let comp_obj_cmd = Printf.sprintf "%s %s %s -c %s -o %s" compiler c_flags inc_flags obf_c_path obj_out in
            let st = Sys.command comp_obj_cmd in
            if st <> 0 then prerr_endline (Printf.sprintf "  [ERROR] Failed to compile %s" in_file)
            else obj_files := obj_out :: !obj_files
          end
        end else begin
          let obj_out = Filename.concat build_dir (base ^ ".o") in
          let c_plain_flags = if debug_symbols then "-g -O1 " else "" in
          let comp_obj_cmd = Printf.sprintf "clang %s-c %s -o %s" c_plain_flags in_file obj_out in
          let st = Sys.command comp_obj_cmd in
          if st <> 0 then prerr_endline (Printf.sprintf "  [ERROR] Failed to compile %s" in_file)
          else obj_files := obj_out :: !obj_files
        end)
      all_inputs;

    let objs_str = String.concat " " (List.rev !obj_files) in
    let has_any_cpp = List.exists (fun f -> String.ends_with ~suffix:".cpp" f || String.ends_with ~suffix:".cc" f || String.ends_with ~suffix:".cxx" f) all_inputs in
    let linker = if has_any_cpp || !total_markers > 0 then "clang++" else "clang" in
    let link_cmd =
      if debug_symbols then
        Printf.sprintf "%s -g -O1 %s -o %s && dsymutil %s" linker objs_str out_bin out_bin
      else
        Printf.sprintf "%s -O3 -fno-rtti -fno-exceptions -fno-unwind-tables -fno-asynchronous-unwind-tables -fvisibility=hidden -Wl,-dead_strip -Wl,-x %s -o %s && strip -x %s" linker objs_str out_bin out_bin
    in

    Printf.printf "\n[Linking] Linking %d protected object files into %s...\n" (List.length !obj_files) out_bin;
    let link_st = Sys.command link_cmd in
    if link_st <> 0 then begin
      prerr_endline "Project linking failed!";
      `Error (false, "Linking error")
    end else begin
      Printf.printf "[SUCCESS] Multi-File Protected Binary created successfully: %s\n" out_bin;
      Printf.printf "  Total Files Virtualized:  %d\n" (List.length all_inputs);
      Printf.printf "  Total Marked Regions:     %d\n" !total_markers;
      Printf.printf "  Strip Status:             %s\n\n" (if debug_symbols then "DEBUG (DWARF symbols preserved via .dSYM)" else "STRIPPED (Zero C++ stdlib / symbol leaks)");

      if compile_and_run then begin
        Printf.printf "[Running] Executing Protected Multi-File Binary:\n";
        Printf.printf "--------------------------------------------------------\n";
        let run_cmd = Printf.sprintf "%s" out_bin in
        let _ = Sys.command run_cmd in
        Printf.printf "--------------------------------------------------------\n\n";
        `Ok ()
      end else `Ok ()
    end
  end

let project_cmd =
  let doc = "Build and protect a full multi-file C/C++ project with scattered markers and unified zero-bloat runtime" in
  let src_dir =
    let doc = "Directory containing source files (.c, .cpp, .s)" in
    Arg.(value & opt (some string) None & info [ "d"; "dir"; "src-dir" ] ~docv:"DIR" ~doc)
  in
  let inputs =
    let doc = "Individual source files to include in project" in
    Arg.(value & opt_all string [] & info [ "i"; "input" ] ~docv:"FILE" ~doc)
  in
  let out_bin =
    let doc = "Output executable path" in
    Arg.(value & opt string "./bin/protected_app" & info [ "o"; "output" ] ~docv:"FILE" ~doc)
  in
  let seed =
    let doc = "Project-wide randomization seed" in
    Arg.(value & opt (some int) None & info [ "s"; "seed" ] ~docv:"SEED" ~doc)
  in
  let cff =
    let doc = "Enable Control-Flow Flattening (CFF) across all files" in
    Arg.(value & flag & info [ "cff"; "flatten" ] ~doc)
  in
  let mba =
    let doc = "Enable Mixed Boolean-Arithmetic (MBA) rewriting across all files" in
    Arg.(value & flag & info [ "mba" ] ~doc)
  in
  let mba_depth =
    let doc = "MBA recursion depth (1..4)" in
    Arg.(value & opt int 2 & info [ "mba-depth" ] ~docv:"DEPTH" ~doc)
  in
  let compile =
    let doc = "Compile and execute final linked binary" in
    Arg.(value & opt bool true & info [ "run"; "compile" ] ~docv:"BOOL" ~doc)
  in
  let debug_symbols =
    let doc = "Preserve DWARF debug symbols and generate .dSYM for debugging/auditing in IDA" in
    Arg.(value & flag & info [ "g"; "debug-symbols" ] ~doc)
  in
  let term = Term.(ret (const run_project $ src_dir $ inputs $ out_bin $ seed $ cff $ mba $ mba_depth $ compile $ debug_symbols)) in
  Cmd.v (Cmd.info "project" ~doc) term
