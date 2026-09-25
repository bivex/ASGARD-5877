open Random_visa_ports
open Protect_ports

let compile_to_asm ~arch ~(c_source : string) ~(out_asm : string) ~(include_dir : string) : (unit, error) result =
  let target_flag, extra_flags =
    match arch with
    | X86_64 -> ("-target x86_64-apple-darwin -masm=intel", "")
    | Arm64 -> ("-target arm64-apple-darwin -fno-inline -fno-stack-check -mno-stack-arg-probe", "")
    | Riscv64 -> ("-target riscv64-unknown-elf -march=rv64gcv -mabi=lp64d -fno-inline", "")
  in
  let cmd =
    Printf.sprintf
      "clang -S %s -O1 -fno-stack-protector -Wno-format-security -I%s -fno-asynchronous-unwind-tables %s %s -o %s"
      target_flag include_dir extra_flags c_source out_asm
  in
  let code = Sys.command cmd in
  if code = 0 then Ok ()
  else Error (Printf.sprintf "clang -S failed with exit code %d" code)

let compile_native_binary ~is_c ~(source_file : string) ~(out_binary : string) ~(include_dir : string) : (unit, error) result =
  let compiler =
    if is_c then "clang -O3 -Wno-format-security"
    else "clang++ -std=c++20 -O3 -Wno-format-security -fvisibility-inlines-hidden"
  in
  let cmd =
    Printf.sprintf
      "%s -fno-rtti -fno-exceptions -fno-unwind-tables -fno-asynchronous-unwind-tables -fvisibility=hidden -Wl,-dead_strip -Wl,-x -I%s %s -o %s && strip -x %s"
      compiler include_dir source_file out_binary out_binary
  in
  let code = Sys.command cmd in
  if code = 0 then Ok ()
  else Error (Printf.sprintf "Native compilation failed with exit code %d" code)

let execute_binary ~(binary_path : string) : (int * string, error) result =
  if not (Sys.file_exists binary_path) then
    Error (Printf.sprintf "Binary not found: %s" binary_path)
  else
    let in_ch = Unix.open_process_in (binary_path ^ " < /dev/null") in
    let buf = Buffer.create 256 in
    (try
       while true do
         Buffer.add_channel buf in_ch 1
       done
     with End_of_file -> ());
    let status = Unix.close_process_in in_ch in
    let exit_code =
      match status with
      | Unix.WEXITED code -> code
      | Unix.WSIGNALED s -> 128 + s
      | Unix.WSTOPPED s -> s
    in
    Ok (exit_code, Buffer.contents buf)
