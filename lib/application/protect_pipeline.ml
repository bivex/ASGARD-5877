open Random_visa_ports
open Protect_ports

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
    ?(compile_and_run = false)
    () : (protect_result, error) result =
  let module L = (val lifter : Lifter) in
  let module P = (val vm_packager : Vm_packager) in

  if not (Sys.file_exists input_file) then
    Error (Printf.sprintf "Input file not found: %s" input_file)
  else
    let () = try Sys.mkdir out_dir 0o755 with _ -> () in
    let is_c_src =
      String.ends_with ~suffix:".c" input_file || String.ends_with ~suffix:".cpp" input_file
    in

    (* 1. Optional C/C++ macro pre-transformation and clang frontend *)
    let asm_source_file_res =
      if is_c_src then
        match toolchain with
        | Some (module T : Toolchain) ->
            let c_source_for_asm, include_dir =
              let hdr_path = Filename.concat out_dir "asgard_obf.h" in
              if is_c_macro_enabled config then
                match c_macro_obfuscator with
                | Some (module C : C_macro_obfuscator) ->
                    let obf_c_path = Filename.concat out_dir "app_obf.c" in
                    (match C.transform_source ~config ~in_file:input_file ~out_c_file:obf_c_path ~out_header_file:hdr_path ~rng with
                    | Ok () -> ()
                    | Error err -> prerr_endline (Printf.sprintf "C pre-transform warning: %s" err));
                    (obf_c_path, out_dir)
                | None -> (input_file, out_dir)
              else begin
                (match c_macro_obfuscator with
                | Some (module C : C_macro_obfuscator) when not (Sys.file_exists hdr_path) ->
                    let dummy_c = Filename.concat out_dir "dummy.c" in
                    (match C.transform_source ~config ~in_file:input_file ~out_c_file:dummy_c ~out_header_file:hdr_path ~rng with
                    | Ok () -> (try Sys.remove dummy_c with _ -> ())
                    | Error _ -> ())
                | _ -> ());
                (input_file, out_dir)
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
      else Ok input_file
    in

    match asm_source_file_res with
    | Error err -> Error err
    | Ok asm_source_file ->
        let ic = open_in asm_source_file in
        let len = in_channel_length ic in
        let text = really_input_string ic len in
        close_in ic;

        (* 2. Lifter: parse assembly and lift to VM-IR *)
        match L.lift_source text with
        | Error err -> Error (Printf.sprintf "Lifter failed (%s): %s" L.arch_name err)
        | Ok (lifted_func, constants) ->
            (* 3. VM Packaging: CFF, MBA, rolling key, handler synthesis *)
            let pkg = P.package ~rng ~config ~constants lifted_func in

            (* 4. Write C++ runtime header *)
            let hdr_path = Filename.concat out_dir pkg.header_name in
            let oc_h = open_out hdr_path in
            output_string oc_h pkg.cpp_runtime_source;
            close_out oc_h;

            if P.engine_kind <> Threaded then begin
              let comp_hdr = Filename.concat out_dir "threaded_vm.hpp" in
              let oc_ch = open_out comp_hdr in
              output_string oc_ch pkg.cpp_runtime_source;
              close_out oc_ch;
            end;

            (* 5. Write runner.cpp *)
            let runner_path = Filename.concat out_dir "runner.cpp" in
            let oc_r = open_out runner_path in
            output_string oc_r pkg.runner_source;
            close_out oc_r;

            (* 6. Write protected.vanguard bytecode *)
            let bc_path = Filename.concat out_dir "protected.vanguard" in
            let oc_b = open_out_bin bc_path in
            List.iter
              (fun w ->
                for i = 0 to 7 do
                  let b = Int64.to_int (Int64.logand (Int64.shift_right_logical w (i * 8)) 0xFFL) in
                  output_byte oc_b b
                done)
              pkg.bytecode;
            close_out oc_b;

            (* 7. In-place C trampoline embedding if C/C++ source *)
            if is_c_src then begin
              match trampoline_engine with
              | Some (module TE : Trampoline_engine) ->
                  let obf_c_path = Filename.concat out_dir "app_obf.c" in
                  let c_src_path = if Sys.file_exists obf_c_path then obf_c_path else input_file in
                  let ic_c = open_in c_src_path in
                  let c_len = in_channel_length ic_c in
                  let c_src = really_input_string ic_c c_len in
                  close_in ic_c;
                  let virt_cpp_path = Filename.concat out_dir "app_virtualized.cpp" in
                  TE.embed_vm_trampoline ~c_src ~bytecode:pkg.bytecode ~out_path:virt_cpp_path
              | None -> ()
            end;

            (* 8. Optional native binary build and test execution *)
            let bin_artifact, exec_result =
              if compile_and_run then
                match toolchain with
                | Some (module T : Toolchain) ->
                    let bin_path = Filename.concat out_dir (if is_c_src then "protected_app" else "protected_runner") in
                    let virt_cpp = Filename.concat out_dir "app_virtualized.cpp" in
                    let comp_src =
                      if is_c_src && Sys.file_exists virt_cpp then virt_cpp
                      else if is_c_src then Filename.concat out_dir "app_obf.c"
                      else runner_path
                    in
                    let is_c_target = is_c_src && not (String.ends_with ~suffix:".cpp" comp_src) in
                    (match T.compile_native_binary ~is_c:is_c_target ~source_file:comp_src ~out_binary:bin_path ~include_dir:out_dir with
                    | Ok () ->
                        let exec_res =
                          match T.execute_binary ~binary_path:bin_path with
                          | Ok (code, out) -> Some (code, out)
                          | Error _ -> None
                        in
                        (Some bin_path, exec_res)
                    | Error err ->
                        prerr_endline (Printf.sprintf "Native build warning: %s" err);
                        (None, None))
                | None -> (None, None)
              else (None, None)
            in

            Ok {
              header_path = hdr_path;
              runner_path;
              bytecode_path = bc_path;
              bytecode_length_bytes = List.length pkg.bytecode * 8;
              metrics = pkg.metrics;
              binary_path = bin_artifact;
              execution_output = exec_result;
            }
