open Random_visa_domain

let get_compiler_cmd () =
  match Sys.getenv_opt "CXX" with
  | Some cmd -> cmd
  | None -> "clang++"

let run_command_in_dir ~cwd cmd args =
  let old_pwd = Sys.getcwd () in
  try
    Sys.chdir cwd;
    let out_r, out_w = Unix.pipe () in
    let err_r, err_w = Unix.pipe () in
    let argv = Array.of_list (cmd :: args) in
    let pid = Unix.create_process cmd argv Unix.stdin out_w err_w in
    Unix.close out_w;
    Unix.close err_w;

    let read_all fd =
      let ic = Unix.in_channel_of_descr fd in
      let buf = Buffer.create 1024 in
      (try
         while true do
           let line = input_line ic in
           Buffer.add_string buf line;
           Buffer.add_char buf '\n'
         done
       with End_of_file -> ());
      close_in ic;
      Buffer.contents buf
    in
    let stdout_str = read_all out_r in
    let stderr_str = read_all err_r in
    let _, status = Unix.waitpid [] pid in
    Sys.chdir old_pwd;
    match status with
    | Unix.WEXITED 0 -> Ok stdout_str
    | Unix.WEXITED code ->
        Error (Printf.sprintf "Process '%s' exited with code %d:\n%s\n%s" cmd code stdout_str stderr_str)
    | Unix.WSIGNALED s ->
        Error (Printf.sprintf "Process '%s' killed by signal %d" cmd s)
    | Unix.WSTOPPED s ->
        Error (Printf.sprintf "Process '%s' stopped by signal %d" cmd s)
  with exn ->
    (try Sys.chdir old_pwd with _ -> ());
    Error (Printexc.to_string exn)

let compile ~project_dir =
  let abs_dir =
    if Filename.is_relative project_dir then Filename.concat (Sys.getcwd ()) project_dir
    else project_dir
  in
  let cxx = get_compiler_cmd () in
  let main_cpp = Filename.concat abs_dir "main.cpp" in
  let inst_cpp = Filename.concat abs_dir "instructions.cpp" in
  let out_bin = Filename.concat abs_dir "visa_test_runner" in
  let args = [
    "-std=c++20";
    "-O2";
    "-Wall";
    "-Wextra";
    "-I"; abs_dir;
    main_cpp;
    inst_cpp;
    "-o"; out_bin;
  ] in
  match run_command_in_dir ~cwd:abs_dir cxx args with
  | Ok _ -> Ok ()
  | Error msg -> Error (Errors.Compilation_error msg)

let run_tests ~project_dir =
  let abs_dir =
    if Filename.is_relative project_dir then Filename.concat (Sys.getcwd ()) project_dir
    else project_dir
  in
  let bin = Filename.concat abs_dir "visa_test_runner" in
  if not (Sys.file_exists bin) then
    Error (Errors.Compilation_error (Printf.sprintf "Binary not found: %s" bin))
  else
    match run_command_in_dir ~cwd:abs_dir bin [] with
    | Ok out -> Ok out
    | Error msg -> Error (Errors.Compilation_error msg)
