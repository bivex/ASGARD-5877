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
