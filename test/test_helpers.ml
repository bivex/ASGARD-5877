(** Test_helpers — Shared test utilities for ASGARD-5877 verification suite. *)

let with_temp_dir f =
  let tmp_dir = Filename.temp_file "asgard_test_" "" in
  (try Sys.remove tmp_dir with Sys_error _ -> ());
  Sys.mkdir tmp_dir 0o755;
  let res =
    try f tmp_dir
    with exn ->
      (try ignore (Sys.command (Printf.sprintf "rm -rf %s" tmp_dir)) with Sys_error _ -> ());
      raise exn
  in
  (try ignore (Sys.command (Printf.sprintf "rm -rf %s" tmp_dir)) with Sys_error _ -> ());
  res

let read_file_string path =
  let ic = open_in path in
  let len = in_channel_length ic in
  let content = really_input_string ic len in
  close_in ic;
  content

let write_file_string path content =
  let oc = open_out path in
  output_string oc content;
  close_out oc

let write_bytecode_bin path (words : int64 list) =
  let oc = open_out_bin path in
  List.iter
    (fun w ->
      for i = 0 to 7 do
        let b = Int64.to_int (Int64.logand (Int64.shift_right_logical w (i * 8)) 0xFFL) in
        output_byte oc b
      done)
    words;
  close_out oc

let run_command_capture cmd =
  let ic = Unix.open_process_in cmd in
  let out_buf = Buffer.create 256 in
  (try
     while true do
       Buffer.add_string out_buf (input_line ic);
       Buffer.add_char out_buf '\n'
     done
   with End_of_file -> ());
  let status = Unix.close_process_in ic in
  (status, Buffer.contents out_buf)

