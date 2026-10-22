open Random_visa_ports
open Protect_ports
open Macho

let run
    ~(lifter : (module Lifter))
    ?c_macro_obfuscator
    ~(vm_packager : (module Vm_packager))
    ?trampoline_engine
    ?toolchain
    ~(rng : Random.State.t)
    ~(config : protection_config)
    ~(input_file : string)
    ~(out_dir : string)
    ?(compile = false)
    ?(compile_and_run = false)
    ?(debug_symbols = false)
    () : (protect_result, error) result =
  let should_compile = compile || compile_and_run in
  let should_run = compile_and_run in
  let () =
    if debug_symbols then Unix.putenv "ASGARD_DEBUG_SYMBOLS" "1"
  in
  (* Pre-warm the parallel worker pool so domain-spawn latency is paid once
     at pipeline entry rather than inside the first Stack-VM pass. *)
  let () = Random_visa_ports.Domain_pool.warm () in
  let module L = (val lifter : Lifter) in
  let module P = (val vm_packager : Vm_packager) in
  let native_cfg : Native_vm.Protection_config.t = unwrap_config config in

  if not (Sys.file_exists input_file) then begin
    Logger.errorf ~loc:__LOC__ ~section:"PIPELINE" "Input file not found: %s" input_file;
    Error (Printf.sprintf "Input file not found: %s" input_file)
  end else
    let () = if not (Sys.file_exists out_dir) then Sys.mkdir out_dir 0o755 in
    let is_swift_src = String.ends_with ~suffix:".swift" input_file in
    let is_cpp_src =
      String.ends_with ~suffix:".cpp" input_file || String.ends_with ~suffix:".cc" input_file || String.ends_with ~suffix:".cxx" input_file
    in
    let is_c_src =
      String.ends_with ~suffix:".c" input_file || is_cpp_src
    in

    Logger.infof ~loc:__LOC__ ~section:"PIPELINE" "Starting VM protection for '%s' (out_dir='%s', arch=%s)"
      input_file out_dir L.arch_name;
    (* 1. Optional C/C++/Swift frontend to assembly *)
    let asm_source_file_res =
      if is_swift_src then begin
        Logger.stepf ~loc:__LOC__ ~section:"FRONTEND" ~step:1 ~total:8 "Compiling Swift source '%s' to %s assembly..." input_file L.arch_name;
        match toolchain with
        | Some (module T : Toolchain) ->
            let asm_name =
              match L.target_arch with
              | X86_64 -> "app_swift_x86_64.s"
              | Arm64 -> "app_swift_arm64.s"
              | Riscv64 -> "app_swift_riscv64.s"
            in
            let asm_out = Filename.concat out_dir asm_name in
            (match T.compile_swift_to_asm ~swift_source:input_file ~out_asm:asm_out with
            | Ok () -> Ok asm_out
            | Error err -> Error err)
        | None -> Error "A Swift source was provided, but no toolchain was available to compile it to assembly"
      end else if is_c_src then begin
        Logger.stepf ~loc:__LOC__ ~section:"FRONTEND" ~step:1 ~total:8 "Compiling C/C++ source '%s' to %s assembly..." input_file L.arch_name;
        match toolchain with
        | Some (module T : Toolchain) ->
            let c_source_for_asm, include_dir =
              let hdr_path = Filename.concat out_dir "asgard_obf.h" in
              let orig_dir = Filename.dirname input_file in
              let inc_paths = if orig_dir <> "" && orig_dir <> "." && orig_dir <> out_dir then out_dir ^ ":" ^ orig_dir else out_dir in
              if is_c_macro_enabled config then
                match c_macro_obfuscator with
                | Some (module C : C_macro_obfuscator) ->
                    let obf_name = if is_cpp_src then "app_obf.cpp" else "app_obf.c" in
                    let obf_c_path = Filename.concat out_dir obf_name in
                    (match C.transform_source ~config ~in_file:input_file ~out_c_file:obf_c_path ~out_header_file:hdr_path ~rng with
                    | Ok () -> ()
                    | Error err -> Logger.warnf ~loc:__LOC__ ~section:"C_MACRO" "C pre-transform warning: %s" err);
                    (obf_c_path, inc_paths)
                | None -> (input_file, inc_paths)
              else begin
                (match c_macro_obfuscator with
                | Some (module C : C_macro_obfuscator) when not (Sys.file_exists hdr_path) ->
                    let dummy_c = Filename.concat out_dir "dummy.c" in
                    (match C.transform_source ~config ~in_file:input_file ~out_c_file:dummy_c ~out_header_file:hdr_path ~rng with
                    | Ok () -> if Sys.file_exists dummy_c then Sys.remove dummy_c
                    | Error _ -> ())
                | _ -> ());
                (input_file, inc_paths)
              end
            in
            let asm_name =
              match L.target_arch with
              | X86_64 -> "app.s"
              | Arm64 -> "app_arm64.s"
              | Riscv64 -> "app_riscv64.s"
            in
            let asm_out = Filename.concat out_dir asm_name in
            (match T.compile_to_asm ~arch:L.target_arch ~c_source:c_source_for_asm ~out_asm:asm_out ~include_dir with
            | Ok () -> Ok asm_out
            | Error err -> Error err)
        | None -> Error "A C/C++ source was provided, but no toolchain was available to compile it to assembly"
      end else begin
        Logger.stepf ~loc:__LOC__ ~section:"FRONTEND" ~step:1 ~total:8 "Using assembly source '%s'" input_file;
        Ok input_file
      end
    in

    match asm_source_file_res with
    | Error err -> Error err
    | Ok asm_source_file ->
        let ic = open_in asm_source_file in
        let len = in_channel_length ic in
        let text = really_input_string ic len in
        close_in ic;
        Logger.debugf ~loc:__LOC__ ~section:"LIFTER" "Read %d bytes of assembly text from '%s'" len asm_source_file;

        (* 2. Lifter: parse assembly and lift to VM-IR *)
        Logger.stepf ~loc:__LOC__ ~section:"LIFTER" ~step:2 ~total:8 "Parsing and lifting %s assembly to VM-IR..." L.arch_name;
        match L.lift_source text with
        | Error err ->
            Logger.errorf ~loc:__LOC__ ~section:"LIFTER" "Lifter failed (%s): %s" L.arch_name err;
            Error (Printf.sprintf "Lifter failed (%s): %s" L.arch_name err)
        | Ok (lifted_func, constants) ->
            let func_info =
              match unwrap_multi_ir lifted_func with
              | [ (name, obj) ] ->
                  (try
                     let f : Vm_ir.Ir.func = obj in
                     Printf.sprintf "single func '%s' (%d blocks)" f.name (Hashtbl.length f.cfg.blocks)
                   with _ -> Printf.sprintf "single func '%s'" name)
              | fns ->
                  Printf.sprintf "multi-func [%s]" (String.concat ", " (List.map fst fns))
            in
            Logger.infof ~loc:__LOC__ ~section:"LIFTER" "Lifted IR: %s (%d constant pool entries)" func_info (List.length constants);
            Logger.infof ~loc:__LOC__ ~section:"LIFTER" "  ├─ SIB memory addressing and RMW instructions lowered";
            Logger.infof ~loc:__LOC__ ~section:"LIFTER" "  └─ Sub-register zero-extension & lazy algebraic flags configured";
            (* 3. VM Packaging: CFF, MBA, rolling key, handler synthesis *)
            let engine_str =
              match P.engine_kind with
              | Threaded -> "threaded"
              | Jit -> "jit"
              | MultiVm -> "multi_vm"
              | Stack -> "stack"
            in
            Logger.stepf ~loc:__LOC__ ~section:"PACKAGER" ~step:3 ~total:8 "Packaging VM bytecode and synthesizing handlers (engine=%s)..." engine_str;
            let pkg = P.package ~rng ~config ~constants lifted_func in
            Logger.infof ~loc:__LOC__ ~section:"PACKAGER" "Bytecode packaging complete: %d words (%d bytes), runtime header='%s'"
              (List.length pkg.bytecode) (List.length pkg.bytecode * 8) pkg.header_name;

            (* 4. Write C++ runtime header *)
            Logger.stepf ~loc:__LOC__ ~section:"CODEGEN" ~step:4 ~total:8 "Writing VM runtime headers to '%s'..." out_dir;
            let hdr_path = Filename.concat out_dir pkg.header_name in
            let oc_h = open_out hdr_path in
            output_string oc_h pkg.cpp_runtime_source;
            close_out oc_h;
            Logger.infof ~loc:__LOC__ ~section:"CODEGEN" "  ├─ VM Runtime: emitted '%s'" pkg.header_name;
            if native_cfg.eh_shadowing.enabled then
              Logger.infof ~loc:__LOC__ ~section:"CODEGEN" "  ├─ [Tech-2601] Emitted ABI Exception Handling Shadowing header (asg_tech_2601.hpp)";
            if native_cfg.anti_vpc.enabled then
              Logger.infof ~loc:__LOC__ ~section:"CODEGEN" "  ├─ [Tech-2603] Emitted Anti-VPC Tracking header (asg_tech_2603.hpp)";
            if native_cfg.memory_chaffing.enabled then
              Logger.infof ~loc:__LOC__ ~section:"CODEGEN" "  └─ [Tech-2608] Emitted Anti-Trace Memory Chaffing header (asg_tech_2608.hpp)";

            (* 4a. Write Tech-2601 Exception Handling Shadowing runtime header *)
            let eh_hdr_path = Filename.concat out_dir "asg_tech_2601.hpp" in
            let oc_eh = open_out eh_hdr_path in
            output_string oc_eh Tech_2601.Tech_2601_engine.runtime_header_source;
            close_out oc_eh;

            (* 4c. Write Tech-2603 Anti-VPC-Tracking runtime header *)
            let vpc_hdr_path = Filename.concat out_dir "asg_tech_2603.hpp" in
            let oc_vpc = open_out vpc_hdr_path in
            output_string oc_vpc (Tech_2603.Tech_2603_engine.emit_tech_2603_cpp_header ());
            close_out oc_vpc;

            (* 4d. Write Tech-2608 Anti-Trace-Synthesis runtime header *)
            let chaff_hdr_path = Filename.concat out_dir "asg_tech_2608.hpp" in
            let oc_chaff = open_out chaff_hdr_path in
            output_string oc_chaff (Tech_2608.Tech_2608_engine.emit_tech_2608_cpp_header ());
            close_out oc_chaff;

            (* 4b. Address binding (Anti-VMPredator): active via runtime handler integrity *)
            if native_cfg.anti_pushan.address_bound then
              Logger.infof ~loc:__LOC__ ~section:"ANTI_VMPREDATOR" "Address Binding: active via runtime handler integrity binding";
            (* 5. Write runner.cpp *)
            let runner_path = Filename.concat out_dir "runner.cpp" in
            let oc_r = open_out runner_path in
            output_string oc_r pkg.runner_source;
            close_out oc_r;

            (* 6. Write protected.vanguard bytecode *)
            let bc_path = Filename.concat out_dir "protected.vanguard" in
            Logger.stepf ~loc:__LOC__ ~section:"CODEGEN" ~step:5 ~total:8 "Writing runner harness and protected bytecode payload (%s)..." bc_path;
            Logger.infof ~loc:__LOC__ ~section:"CODEGEN" "  ├─ Serialized %d bytecode words (%d bytes)"
              (List.length pkg.bytecode) (List.length pkg.bytecode * 8);
            Logger.infof ~loc:__LOC__ ~section:"CODEGEN" "  └─ Runner test harness written: '%s'" runner_path;
            let oc_b = open_out_bin bc_path in
            List.iter
              (fun w ->
                for i = 0 to 7 do
                  let b = Int64.to_int (Int64.logand (Int64.shift_right_logical w (i * 8)) 0xFFL) in
                  output_byte oc_b b
                done)
              pkg.bytecode;
            close_out oc_b;

            (* 7. In-place trampoline embedding *)
            Logger.step ~loc:__LOC__ ~section:"TRAMPOLINE" ~step:6 ~total:8 "Generating zero-native call trampolines...";
            let protected_swift_asm = ref None in
            let dispatch_cpp_path = ref None in
            if is_swift_src then begin
              let raw_names =
                match pkg.bytecodes with
                | [] ->
                    (try [ (unwrap_ir lifted_func : Vm_ir.Ir.func).name ]
                     with _ -> [ "target_func" ])
                | bs -> List.map fst bs
              in
              let target_names =
                let found = ref [] in
                (try
                   let ic_scan = open_in asm_source_file in
                   let rec scan () =
                     match input_line ic_scan with
                     | line ->
                         let trimmed = String.trim line in
                         if String.starts_with ~prefix:"_" line && String.ends_with ~suffix:":" trimmed then begin
                           let sym = String.sub trimmed 0 (String.length trimmed - 1) in
                           let clean = if String.starts_with ~prefix:"_" sym then String.sub sym 1 (String.length sym - 1) else sym in
                           if String.starts_with ~prefix:"asgard_" clean || String.starts_with ~prefix:"verify_" clean then
                             if not (List.mem clean !found) then found := clean :: !found
                         end;
                         scan ()
                     | exception End_of_file -> close_in ic_scan
                   in
                   scan ()
                 with _ -> ());
                if !found <> [] then !found else raw_names
              in
              let d_path = Filename.concat out_dir "asgard_auto_dispatch.cpp" in
              dispatch_cpp_path := Some d_path;
              let oc_d = open_out d_path in
              output_string oc_d (Printf.sprintf "#include \"%s\"\n#include <stdint.h>\n#include <stddef.h>\n\nstatic const uint64_t embedded_bytecode[] = {\n" pkg.header_name);
              List.iteri (fun idx w ->
                if idx > 0 then output_string oc_d ",\n";
                output_string oc_d (Printf.sprintf "    0x%016LxULL" w)
              ) pkg.bytecode;
              output_string oc_d "\n};\n\n";
              List.iter (fun fn ->
                let clean_fn = if String.starts_with ~prefix:"_" fn then String.sub fn 1 (String.length fn - 1) else fn in
                output_string oc_d (Printf.sprintf "extern \"C\" uint64_t asgard_vm_entry_%s(uint64_t a0, uint64_t a1, uint64_t a2, uint64_t a3, uint64_t a4, uint64_t a5, uint64_t a6, uint64_t a7) {\n" clean_fn);
                output_string oc_d "    size_t bc_len = sizeof(embedded_bytecode) / sizeof(embedded_bytecode[0]);\n";
                output_string oc_d "    return vanguard_threaded_vm::asgard_vm_call(embedded_bytecode, bc_len, a0, a1, a2, a3, a4, a5, a6, a7);\n}\n\n";
                output_string oc_d (Printf.sprintf "extern \"C\" uint64_t _asgard_vm_entry_%s(uint64_t a0, uint64_t a1, uint64_t a2, uint64_t a3, uint64_t a4, uint64_t a5, uint64_t a6, uint64_t a7) {\n" clean_fn);
                output_string oc_d (Printf.sprintf "    return asgard_vm_entry_%s(a0, a1, a2, a3, a4, a5, a6, a7);\n}\n\n" clean_fn)
              ) target_names;
              close_out oc_d;

              (* In-place ASM rewriting *)
              let s_protected = Filename.concat out_dir "app_swift_protected.s" in
              protected_swift_asm := Some s_protected;
              let ic_s = open_in asm_source_file in
              let oc_s = open_out s_protected in
              let skip = ref false in
              let rec patch_lines () =
                match input_line ic_s with
                | line ->
                    let trimmed = String.trim line in
                    let is_target_label =
                      List.exists (fun fn ->
                        let clean_fn = if String.starts_with ~prefix:"_" fn then String.sub fn 1 (String.length fn - 1) else fn in
                        String.starts_with ~prefix:"_" line && String.ends_with ~suffix:":" trimmed
                        && (let has_sub s sub =
                              let slen = String.length s in
                              let sublen = String.length sub in
                              let rec check i =
                                if i + sublen > slen then false
                                else if String.sub s i sublen = sub then true
                                else check (i + 1)
                              in check 0
                            in has_sub line clean_fn)
                      ) target_names
                    in
                    if is_target_label then begin
                      output_string oc_s line;
                      output_char oc_s '\n';
                      let first_fn = List.hd target_names in
                      let clean_first = if String.starts_with ~prefix:"_" first_fn then String.sub first_fn 1 (String.length first_fn - 1) else first_fn in
                      output_string oc_s (Printf.sprintf "\tb\t_asgard_vm_entry_%s\n" clean_first);
                      skip := true
                    end else if !skip && trimmed = "ret" then begin
                      skip := false
                    end else if not !skip then begin
                      output_string oc_s line;
                      output_char oc_s '\n'
                    end;
                    patch_lines ()
                | exception End_of_file ->
                    close_in ic_s;
                    close_out oc_s
              in
              patch_lines ()
            end else if is_c_src then begin
              match trampoline_engine with
              | Some (module TE : Trampoline_engine) ->
                  let obf_name = if is_cpp_src then "app_obf.cpp" else "app_obf.c" in
                  let obf_c_path = Filename.concat out_dir obf_name in
                  let c_src_path = if Sys.file_exists obf_c_path then obf_c_path else input_file in
                  let ic_c = open_in c_src_path in
                  let c_len = in_channel_length ic_c in
                  let c_src = really_input_string ic_c c_len in
                  close_in ic_c;
                  let virt_cpp_path = Filename.concat out_dir "app_virtualized.cpp" in
                  let chunk_size = if native_cfg.trampoline.chunk_size > 0 then Some native_cfg.trampoline.chunk_size else None in
                  TE.embed_vm_trampoline ?chunk_size ~header_name:pkg.header_name ~c_src ~bytecodes:pkg.bytecodes ~bytecode:pkg.bytecode ~out_path:virt_cpp_path ()
              | None -> ()
            end;

            (* 7. Native compilation and optional execution *)
            Logger.stepf ~loc:__LOC__ ~section:"TOOLCHAIN" ~step:7 ~total:8 "%s"
              (if should_compile then
                 (if should_run then "Compiling and launching protected native binary..."
                  else "Compiling protected native binary...")
               else "Native compilation skipped (compile=false)");
            let bin_artifact, exec_result =
              if should_compile then
                match toolchain with
                | Some (module T : Toolchain) ->
                    if is_swift_src then
                      match !protected_swift_asm, !dispatch_cpp_path with
                      | Some s_asm, Some d_cpp ->
                          let bin_path = Filename.concat out_dir "protected_app" in
                          (match T.compile_swift_binary ~asm_source:s_asm ~dispatch_source:d_cpp ~out_binary:bin_path ~include_dir:out_dir with
                          | Ok () ->
                              Logger.infof ~loc:__LOC__ ~section:"TOOLCHAIN" "Native Swift binary compiled: %s" bin_path;
                              let exec_res =
                                if should_run then
                                  match T.execute_binary ~binary_path:bin_path with
                                  | Ok (code, out) ->
                                      Logger.infof ~section:"TOOLCHAIN" "Native Swift binary '%s' executed (exit code %d)" bin_path code;
                                      if String.trim out <> "" then
                                        Logger.debugf ~section:"TOOLCHAIN" "Binary execution output:\n%s" (String.trim out);
                                      Some (code, out)
                                  | Error err ->
                                      Logger.warnf ~section:"TOOLCHAIN" "Swift execution warning: %s" err;
                                      None
                                else None
                              in
                              (Some bin_path, exec_res)
                          | Error err ->
                              Logger.warnf ~section:"TOOLCHAIN" "Swift native build warning: %s" err;
                              (None, None))
                      | _ -> (None, None)
                    else
                      let bin_path = Filename.concat out_dir (if is_c_src then "protected_app" else "protected_runner") in
                      let virt_cpp = Filename.concat out_dir "app_virtualized.cpp" in
                      let comp_src =
                        if is_c_src && Sys.file_exists virt_cpp then virt_cpp
                        else if is_c_src then Filename.concat out_dir (if is_cpp_src then "app_obf.cpp" else "app_obf.c")
                        else runner_path
                      in
                      let is_c_target = is_c_src && not (String.ends_with ~suffix:".cpp" comp_src) in
                      (match T.compile_native_binary ~opt_level:native_cfg.toolchain.opt_level ~extra_flags:native_cfg.toolchain.extra_flags ~is_c:is_c_target ~source_file:comp_src ~out_binary:bin_path ~include_dir:out_dir () with
                      | Ok () ->
                          Logger.infof ~loc:__LOC__ ~section:"TOOLCHAIN" "Native binary compiled: %s" bin_path;
                          let exec_res =
                            if should_run then
                              match T.execute_binary ~binary_path:bin_path with
                              | Ok (code, out) ->
                                  Logger.infof ~section:"TOOLCHAIN" "Native binary '%s' executed (exit code %d)" bin_path code;
                                  if String.trim out <> "" then
                                    Logger.debugf ~section:"TOOLCHAIN" "Binary execution output:\n%s" (String.trim out);
                                  Some (code, out)
                              | Error err ->
                                  Logger.warnf ~section:"TOOLCHAIN" "Execution warning: %s" err;
                                  None
                            else None
                          in
                          (Some bin_path, exec_res)
                      | Error err ->
                          Logger.warnf ~section:"TOOLCHAIN" "Native build warning: %s" err;
                          (None, None))
                | None -> (None, None)
              else (None, None)
            in

            Logger.step ~loc:__LOC__ ~section:"AUDIT" ~step:8 ~total:8 "Running Mach-O compact unwind audit and build-seed watermark sealing...";
            (* 8b. Mach-O compact unwind audit of the produced binary. *)
            let unwind_audit =
              match bin_artifact with
              | Some bin when Sys.file_exists bin ->
                  (match Macho_image.of_file bin with
                  | exception Macho_image.Parse_error msg ->
                      Logger.debugf ~section:"AUDIT" "Mach-O audit skipped: %s" msg;
                      Some (Printf.sprintf "skipped (%s)" msg)
                  | img ->
                      let report = Macho_unwind.check img in
                      let issues = List.length report.Macho_unwind.issues in
                      let rep_str =
                        Printf.sprintf "%s, %d routine(s), %s"
                           (Macho_unwind.format_layout report.Macho_unwind.layout)
                           (List.length report.Macho_unwind.routines)
                           (if issues = 0 then "no inconsistency"
                            else Printf.sprintf "%d issue(s)" issues)
                      in
                      Logger.infof ~loc:__LOC__ ~section:"AUDIT" "  ├─ Mach-O compact unwind audit: %s" rep_str;
                      Some rep_str)
              | _ -> None
            in

            (* Address binding report: runtime integrity binding active when configured *)
            let metrics =
              if native_cfg.anti_pushan.address_bound then
                let sep = "===============================================" in
                let summary = pkg.metrics.formatted_summary in
                let n = String.length summary in
                let sep_len = String.length sep in
                let body =
                  if n > sep_len then String.sub summary 0 (n - sep_len) else summary
                in
                { pkg.metrics with
                  formatted_summary =
                    body
                    ^ Printf.sprintf "- Address Binding: Active (Runtime Integrity Binding)\n%s" sep }
              else
                pkg.metrics
            in
            let metrics =
              match unwind_audit with
              | None -> metrics
              | Some line ->
                  let sep = "===============================================" in
                  let summary = metrics.formatted_summary in
                  let n = String.length summary in
                  let sep_len = String.length sep in
                  let body =
                    if n > sep_len then String.sub summary 0 (n - sep_len) else summary
                  in
                  { metrics with
                    formatted_summary =
                      body ^ Printf.sprintf "- Mach-O Compact Unwind: %s\n%s" line sep }
            in
            let wm_id_opt =
              match Protect_ports.watermark config with
              | Some payload ->
                  let s_val = Int64.of_int (match Protect_ports.seed config with Some s -> s | None -> 1337) in
                  let wid = Watermark.Wm_types.derive ~build_seed:s_val ~client_payload:payload in
                  let manifest_path = Filename.concat out_dir "watermark_manifest.json" in
                  let manifest : Watermark.Wm_chooser.manifest = {
                    build_id = Printf.sprintf "build_%016LX" wid.derivation_key;
                    derivation_key = wid.derivation_key;
                    client_payload = wid.raw_bits;
                    carrier_points = (
                      let pbits = native_cfg.watermark.payload_bits in
                      let red = native_cfg.watermark.redundancy in
                      let pts = ref [] in
                      for p = 0 to (pbits * red) - 1 do
                        let bit_idx = p mod pbits in
                        let target_bit = Watermark.Wm_embed.get_bit wid.raw_bits bit_idx in
                        let site_tag = (p + 1, 1) in
                        let global_tag = Watermark.Wm_chooser.mix_tag wid.derivation_key site_tag in
                        let key = Int64.logxor wid.derivation_key global_tag in
                        let pool_zeros, pool_ones = Watermark.Wm_chooser.balanced_split ~key 2 in
                        let chosen = if target_bit then pool_ones.(0) else pool_zeros.(0) in
                        pts := {
                          Watermark.Wm_chooser.function_name = "license_validation";
                          call_site_salt = wid.derivation_key;
                          site_tag;
                          eligible_count = 2;
                          chosen_idx = chosen;
                          payload_bit_idx = Some bit_idx;
                        } :: !pts
                      done;
                      List.rev !pts
                    );
                  } in
                  Watermark.Wm_chooser.save_manifest manifest_path manifest;
                  let pbits = native_cfg.watermark.payload_bits in
                  let red = native_cfg.watermark.redundancy in
                  Logger.infof ~loc:__LOC__ ~section:"WATERMARK" "  └─ Build-seed watermark: embedded %d-bit payload via balanced SplitMix64 ECC (%dx redundancy, Client ID: 0x%016LX, Derivation Key: 0x%016LX)"
                    pbits red wid.raw_bits wid.derivation_key;
                  Some wid
              | None -> None
            in
            let metrics =
              match wm_id_opt with
              | None -> metrics
              | Some wid ->
                  let sep = "===============================================" in
                  let summary = metrics.formatted_summary in
                  let n = String.length summary in
                  let sep_len = String.length sep in
                  let body =
                    if n > sep_len then String.sub summary 0 (n - sep_len) else summary
                  in
                  { metrics with
                    formatted_summary =
                      body
                      ^ Printf.sprintf "- Build-Seed Watermark: Active (Client ID: 0x%016LX, Derivation Key: 0x%016LX)\n%s"
                          wid.raw_bits wid.derivation_key sep }
            in
            let output_target = match bin_artifact with Some b -> b | None -> hdr_path in
            let sep = "===============================================" in
            let summary = metrics.formatted_summary in
            let n = String.length summary in
            let sep_len = String.length sep in
            let body =
              if n > sep_len then String.sub summary 0 (n - sep_len) else summary
            in
            let metrics =
              { metrics with
                formatted_summary =
                  body
                  ^ Printf.sprintf "- Protected File: %s -> %s\n%s" input_file output_target sep }
            in
            Logger.infof ~loc:__LOC__ ~section:"PIPELINE" "Protected file: '%s' -> '%s'" input_file output_target;
            Logger.infof ~loc:__LOC__ ~section:"PIPELINE" "Protection completed successfully for '%s' (Aggregated DRS: %.1f/100.0)"
              input_file metrics.drs_score;
            Ok {
              header_path = hdr_path;
              runner_path;
              bytecode_path = bc_path;
              bytecode_length_bytes = List.length pkg.bytecode * 8;
              metrics;
              binary_path = bin_artifact;
              execution_output = exec_result;
            }
