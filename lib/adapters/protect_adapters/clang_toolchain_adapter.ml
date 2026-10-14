open Random_visa_ports
open Protect_ports
open Bos

let get_inc_args include_dir source_file =
  let src_dir = Filename.dirname source_file in
  let base = Cmd.(v "-I" % include_dir) in
  if src_dir <> "" && src_dir <> "." && src_dir <> include_dir then
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
  let target_args =
    match arch with
    | X86_64 -> Cmd.(v "-target" % "x86_64-apple-darwin" % "-masm=intel")
    | Arm64 -> Cmd.(v "-target" % "arm64-apple-darwin" % "-fno-inline" % "-fno-stack-check" % "-mno-stack-arg-probe" % "-ffixed-x14" % "-ffixed-x15" % "-ffixed-x24" % "-ffixed-x25" % "-ffixed-x26" % "-ffixed-x27" % "-ffixed-x28")
    | Riscv64 -> Cmd.(v "-target" % "riscv64-linux-gnu" % "-march=rv64gc" % "-mabi=lp64d" % "-fno-inline")
  in
  let inc_args = get_inc_args include_dir c_source in
  let compiler = get_compiler_for_arch arch true in
  let cmd =
    Cmd.(v compiler % "-S" %% target_args % "-O1" % "-fno-stack-protector" % "-Wno-format-security"
         %% inc_args % "-fno-asynchronous-unwind-tables" % c_source % "-o" % out_asm)
  in
  match OS.Cmd.run_status cmd with
  | Ok (`Exited 0) -> Ok ()
  | Ok (`Exited c) -> Error (Printf.sprintf "%s -S failed with exit code %d" compiler c)
  | Ok (`Signaled s) -> Error (Printf.sprintf "%s -S terminated by signal %d" compiler s)
  | Error (`Msg msg) -> Error (Printf.sprintf "%s -S execution error: %s" compiler msg)

let compile_native_binary ~is_c ~(source_file : string) ~(out_binary : string) ~(include_dir : string) : (unit, error) result =
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
  if is_debug then begin
    let obj_file = Filename.chop_extension source_file ^ ".o" in
    let compile_obj_cmd =
      Cmd.(v compiler %% base_args % "-g" % "-O1" % "-Wno-format-security" %% inc_args % "-c" % source_file % "-o" % obj_file)
    in
    match OS.Cmd.run_status compile_obj_cmd with
    | Ok (`Exited 0) ->
        let link_cmd = Cmd.(v compiler %% base_args % "-g" % obj_file % "-o" % out_binary) in
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
      Cmd.(v "-O3" % "-Wno-format-security"
           % "-fno-rtti" % "-fno-exceptions"
           % "-fno-unwind-tables" % "-fno-asynchronous-unwind-tables"
           % "-fvisibility=hidden" % "-Wl,-dead_strip" % "-Wl,-x")
    in
    let compile_cmd =
      Cmd.(v compiler %% base_args %% opt_args %% inc_args % source_file % "-o" % out_binary)
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
    match OS.Cmd.run_io ~err:OS.Cmd.err_run_out cmd OS.Cmd.in_null |> OS.Cmd.out_string with
    | Ok (output, (_, `Exited code)) -> Ok (code, output)
    | Ok (output, (_, `Signaled s)) -> Ok (128 + s, output)
    | Error (`Msg msg) -> Error (Printf.sprintf "Binary execution error: %s" msg)
