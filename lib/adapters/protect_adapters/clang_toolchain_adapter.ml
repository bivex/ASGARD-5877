open Random_visa_ports
open Protect_ports
open Bos

let get_inc_args include_dir source_file =
  let src_dir = Filename.dirname source_file in
  let dirs = String.split_on_char ':' include_dir in
  let base = List.fold_left (fun acc d -> if d <> "" then Cmd.(acc % "-I" % d) else acc) Cmd.empty dirs in
  if src_dir <> "" && src_dir <> "." && not (List.mem src_dir dirs) then
    Cmd.(base % "-I" % src_dir)
  else
    base

let get_compiler_for_arch arch is_c =
  match arch with
  | Riscv64 ->
      (match Sys.getenv_opt "RISCV_CLANG" with
      | Some c -> c
      | None ->
          if Sys.file_exists "/opt/homebrew/opt/llvm@21/bin/clang" then
            if is_c then "/opt/homebrew/opt/llvm@21/bin/clang" else "/opt/homebrew/opt/llvm@21/bin/clang++"
          else if Sys.file_exists "/opt/homebrew/opt/llvm/bin/clang" then
            if is_c then "/opt/homebrew/opt/llvm/bin/clang" else "/opt/homebrew/opt/llvm/bin/clang++"
          else if is_c then "clang" else "clang++")
  | _ ->
      if is_c then "clang" else "clang++"

let compile_to_asm ~arch ~(c_source : string) ~(out_asm : string) ~(include_dir : string) : (unit, error) result =
  let is_cpp =
    String.ends_with ~suffix:".cpp" c_source || String.ends_with ~suffix:".cc" c_source || String.ends_with ~suffix:".cxx" c_source
  in
  let target_args =
    match arch with
    | X86_64 -> Cmd.(v "-target" % "x86_64-apple-darwin" % "-masm=intel")
    | Arm64 -> Cmd.(v "-target" % "arm64-apple-darwin" % "-fno-stack-check" % "-mno-stack-arg-probe" % "-ffixed-x14" % "-ffixed-x15" % "-ffixed-x24" % "-ffixed-x25" % "-ffixed-x26" % "-ffixed-x27" % "-ffixed-x28")
    | Riscv64 -> Cmd.(v "-target" % "riscv64-linux-gnu" % "-march=rv64gc" % "-mabi=lp64d")
  in
  let inc_args = get_inc_args include_dir c_source in
  let compiler = get_compiler_for_arch arch (not is_cpp) in
  let extra_flags =
    if is_cpp then
      Cmd.(v "-std=c++20" % "-fno-jump-tables" % "-mllvm" % "-switch-to-lookup=false"
           % "-funroll-loops" % "-mllvm" % "-unroll-threshold=500")
    else
      Cmd.(v "-fno-jump-tables" % "-mllvm" % "-switch-to-lookup=false"
           % "-funroll-loops" % "-mllvm" % "-unroll-threshold=500")
  in
  Logger.debugf ~section:"TOOLCHAIN" "Compiling C/C++ source '%s' to assembly '%s' (%s)"
    c_source out_asm compiler;
  let cmd =
    Cmd.(v compiler % "-S" %% extra_flags %% target_args % "-O1" % "-fno-inline" % "-fno-stack-protector" % "-Wno-format-security"
         %% inc_args % "-fno-asynchronous-unwind-tables" % c_source % "-o" % out_asm)
  in
  match OS.Cmd.run_status cmd with
  | Ok (`Exited 0) -> Ok ()
  | Ok (`Exited c) -> Error (Printf.sprintf "%s -S failed with exit code %d" compiler c)
  | Ok (`Signaled s) -> Error (Printf.sprintf "%s -S terminated by signal %d" compiler s)
  | Error (`Msg msg) -> Error (Printf.sprintf "%s -S execution error: %s" compiler msg)

let compile_native_binary ?arch ?(opt_level = "-O3") ?(extra_flags = []) ~is_c ~(source_file : string) ~(out_binary : string) ~(include_dir : string) () : (unit, error) result =
  let target_args =
    match arch with
    | Some X86_64 -> Cmd.(v "-target" % "x86_64-apple-darwin")
    | Some Arm64 -> Cmd.(v "-target" % "arm64-apple-darwin")
    | Some Riscv64 -> Cmd.(v "-target" % "riscv64-linux-gnu")
    | None -> Cmd.empty
  in
  let is_debug =
    match Sys.getenv_opt "ASGARD_DEBUG_SYMBOLS" with
    | Some "1" | Some "true" | Some "yes" -> true
    | _ -> false
  in
  let inc_args = get_inc_args include_dir source_file in
  let compiler = if is_c then "clang" else "clang++" in
  let base_args =
    if is_c then Cmd.empty
    else Cmd.(v "-std=c++20" % "-fvisibility-inlines-hidden")
  in
  Logger.debugf ~section:"TOOLCHAIN" "Compiling native binary '%s' -> '%s' (compiler=%s, debug=%b)"
    source_file out_binary compiler is_debug;
  if is_debug then begin
    let obj_file = Filename.chop_extension source_file ^ ".o" in
    let compile_obj_cmd =
      Cmd.(v compiler %% target_args %% base_args % "-g" % "-O1" % "-Wno-format-security" %% inc_args % "-c" % source_file % "-o" % obj_file)
    in
    match OS.Cmd.run_status compile_obj_cmd with
    | Ok (`Exited 0) ->
        let link_cmd = Cmd.(v compiler %% target_args %% base_args % "-g" % obj_file % "-o" % out_binary) in
        (match OS.Cmd.run_status link_cmd with
        | Ok (`Exited 0) ->
            let dsym_cmd = Cmd.(v "dsymutil" % out_binary) in
            let _ = OS.Cmd.run_status dsym_cmd in
            Ok ()
        | Ok (`Exited c) -> Error (Printf.sprintf "Native debug link failed with exit code %d" c)
        | Ok (`Signaled s) -> Error (Printf.sprintf "Native debug link terminated by signal %d" s)
        | Error (`Msg msg) -> Error (Printf.sprintf "Native debug link error: %s" msg))
    | Ok (`Exited c) -> Error (Printf.sprintf "Native debug compilation failed with exit code %d" c)
    | Ok (`Signaled s) -> Error (Printf.sprintf "Native debug compilation terminated by signal %d" s)
    | Error (`Msg msg) -> Error (Printf.sprintf "Native debug compilation error: %s" msg)
  end else begin
    let opt_args =
      let base_opt =
        Cmd.(v opt_level % "-Wno-format-security"
             % "-fno-rtti" % "-fno-exceptions"
             % "-fno-unwind-tables" % "-fno-asynchronous-unwind-tables"
             % "-fvisibility=hidden" % "-Wl,-dead_strip" % "-Wl,-export_dynamic")
      in
      List.fold_left (fun acc flag -> Cmd.(acc % flag)) base_opt extra_flags
    in
    let compile_cmd =
      Cmd.(v compiler %% target_args %% base_args %% opt_args %% inc_args % source_file % "-o" % out_binary)
    in
    match OS.Cmd.run_status compile_cmd with
    | Ok (`Exited 0) ->
        let strip_cmd = Cmd.(v "strip" % "-x" % out_binary) in
        (match OS.Cmd.run_status strip_cmd with
        | Ok (`Exited 0) -> Ok ()
        | Ok (`Exited c) -> Error (Printf.sprintf "strip -x failed with exit code %d" c)
        | Ok (`Signaled s) -> Error (Printf.sprintf "strip -x terminated by signal %d" s)
        | Error (`Msg msg) -> Error (Printf.sprintf "strip execution error: %s" msg))
    | Ok (`Exited c) -> Error (Printf.sprintf "Native compilation failed with exit code %d" c)
    | Ok (`Signaled s) -> Error (Printf.sprintf "Native compilation terminated by signal %d" s)
    | Error (`Msg msg) -> Error (Printf.sprintf "Native compilation error: %s" msg)
  end

let execute_binary ~(binary_path : string) : (int * string, error) result =
  if not (Sys.file_exists binary_path) then
    Error (Printf.sprintf "Binary not found: %s" binary_path)
  else
    let cmd = Cmd.v binary_path in
    Logger.debugf ~section:"TOOLCHAIN" "Executing binary: '%s'" binary_path;
    match OS.Cmd.run_io ~err:OS.Cmd.err_run_out cmd OS.Cmd.in_null |> OS.Cmd.out_string with
    | Ok (output, (_, `Exited code)) ->
        Logger.debugf ~section:"TOOLCHAIN" "Binary '%s' exited with code %d (output: %d bytes)" binary_path code (String.length output);
        Ok (code, output)
    | Ok (output, (_, `Signaled s)) -> Ok (128 + s, output)
    | Error (`Msg msg) -> Error (Printf.sprintf "Binary execution error: %s" msg)

let compile_swift_to_asm ~(swift_source : string) ~(out_asm : string) : (unit, error) result =
  let content =
    try
      let ic = open_in swift_source in
      let len = in_channel_length ic in
      let s = really_input_string ic len in
      close_in ic;
      s
    with _ -> ""
  in
  let has_main_attr =
    let rec contains i =
      if i + 5 > String.length content then false
      else if String.sub content i 5 = "@main" then true
      else contains (i + 1)
    in
    contains 0
  in
  let base_cmd = Cmd.(v "swiftc" % "-O") in
  let cmd =
    if has_main_attr then
      Cmd.(base_cmd % "-parse-as-library" % "-emit-assembly" % swift_source % "-o" % out_asm)
    else
      Cmd.(base_cmd % "-emit-assembly" % swift_source % "-o" % out_asm)
  in
  match OS.Cmd.run_status cmd with
  | Ok (`Exited 0) -> Ok ()
  | Ok (`Exited c) -> Error (Printf.sprintf "swiftc -emit-assembly failed with exit code %d" c)
  | Ok (`Signaled s) -> Error (Printf.sprintf "swiftc -emit-assembly terminated by signal %d" s)
  | Error (`Msg msg) -> Error (Printf.sprintf "swiftc execution error: %s" msg)

let compile_swift_binary ~(asm_source : string) ~(dispatch_source : string) ~(out_binary : string) ~(include_dir : string) : (unit, error) result =
  let dir = Filename.dirname out_binary in
  let dispatch_obj = Filename.concat dir "asgard_auto_dispatch.o" in
  let asm_obj = Filename.concat dir "app_protected.o" in
  let inc_args = get_inc_args include_dir dispatch_source in
  let compile_dispatch =
    Cmd.(v "clang++" % "-std=c++17" % "-O2" %% inc_args % "-c" % dispatch_source % "-o" % dispatch_obj)
  in
  match OS.Cmd.run_status compile_dispatch with
  | Ok (`Exited 0) ->
      let compile_asm =
        Cmd.(v "clang" % "-c" % asm_source % "-o" % asm_obj)
      in
      (match OS.Cmd.run_status compile_asm with
      | Ok (`Exited 0) ->
          let link_cmd =
            Cmd.(v "swiftc" % "-O" % asm_obj % dispatch_obj % "-lc++" % "-o" % out_binary)
          in
          (match OS.Cmd.run_status link_cmd with
          | Ok (`Exited 0) -> Ok ()
          | Ok (`Exited c) -> Error (Printf.sprintf "swiftc linking failed with exit code %d" c)
          | Ok (`Signaled s) -> Error (Printf.sprintf "swiftc linking signaled %d" s)
          | Error (`Msg msg) -> Error (Printf.sprintf "swiftc link error: %s" msg))
      | Ok (`Exited c) -> Error (Printf.sprintf "clang asm compilation failed with exit code %d" c)
      | Ok (`Signaled s) -> Error (Printf.sprintf "clang asm compilation signaled %d" s)
      | Error (`Msg msg) -> Error (Printf.sprintf "clang asm compilation error: %s" msg))
  | Ok (`Exited c) -> Error (Printf.sprintf "clang++ dispatch compilation failed with exit code %d" c)
  | Ok (`Signaled s) -> Error (Printf.sprintf "clang++ dispatch compilation signaled %d" s)
  | Error (`Msg msg) -> Error (Printf.sprintf "clang++ dispatch compilation error: %s" msg)
