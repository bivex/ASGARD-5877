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

let compile_to_asm ~arch ~(c_source : string) ~(out_asm : string) ~(include_dir : string) : (unit, error) result =
  let target_args =
    match arch with
    | X86_64 -> Cmd.(v "-target" % "x86_64-apple-darwin" % "-masm=intel")
    | Arm64 -> Cmd.(v "-target" % "arm64-apple-darwin" % "-fno-inline" % "-fno-stack-check" % "-mno-stack-arg-probe")
    | Riscv64 -> Cmd.(v "-target" % "riscv64-unknown-elf" % "-march=rv64gcv" % "-mabi=lp64d" % "-fno-inline")
  in
  let inc_args = get_inc_args include_dir c_source in
  let cmd =
    Cmd.(v "clang" % "-S" %% target_args % "-O1" % "-fno-stack-protector" % "-Wno-format-security"
         %% inc_args % "-fno-asynchronous-unwind-tables" % c_source % "-o" % out_asm)
  in
  match OS.Cmd.run_status cmd with
  | Ok (`Exited 0) -> Ok ()
  | Ok (`Exited c) -> Error (Printf.sprintf "clang -S failed with exit code %d" c)
  | Ok (`Signaled s) -> Error (Printf.sprintf "clang -S terminated by signal %d" s)
  | Error (`Msg msg) -> Error (Printf.sprintf "clang -S execution error: %s" msg)

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
  let opt_args =
    if is_debug then
      Cmd.(v "-g" % "-O1" % "-Wno-format-security")
    else
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
      if not is_debug then begin
        let strip_cmd = Cmd.(v "strip" % "-x" % out_binary) in
        match OS.Cmd.run_status strip_cmd with
        | Ok (`Exited 0) -> Ok ()
        | Ok (`Exited c) -> Error (Printf.sprintf "strip -x failed with exit code %d" c)
        | Ok (`Signaled s) -> Error (Printf.sprintf "strip -x terminated by signal %d" s)
        | Error (`Msg msg) -> Error (Printf.sprintf "strip execution error: %s" msg)
      end else
        Ok ()
  | Ok (`Exited c) -> Error (Printf.sprintf "Native compilation failed with exit code %d" c)
  | Ok (`Signaled s) -> Error (Printf.sprintf "Native compilation terminated by signal %d" s)
  | Error (`Msg msg) -> Error (Printf.sprintf "Native compilation error: %s" msg)

let execute_binary ~(binary_path : string) : (int * string, error) result =
  if not (Sys.file_exists binary_path) then
    Error (Printf.sprintf "Binary not found: %s" binary_path)
  else
    let cmd = Cmd.v binary_path in
    match OS.Cmd.run_io ~err:OS.Cmd.err_run_out cmd OS.Cmd.in_null |> OS.Cmd.out_string with
    | Ok (output, (_, `Exited code)) -> Ok (code, output)
    | Ok (output, (_, `Signaled s)) -> Ok (128 + s, output)
    | Error (`Msg msg) -> Error (Printf.sprintf "Binary execution error: %s" msg)
