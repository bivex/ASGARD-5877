open Random_visa_domain

let to_string (spec : Vector_isa_spec.t) =
  Vector_isa_spec.to_sail_specification spec

let ensure_parent_dir path =
  let dir = Filename.dirname path in
  if dir <> "." && dir <> "/" && not (Sys.file_exists dir) then
    let rec mkdir_p d =
      if not (Sys.file_exists d) then begin
        mkdir_p (Filename.dirname d);
        try Sys.mkdir d 0o755 with Sys_error _ -> ()
      end
    in
    mkdir_p dir

let write_spec (spec : Vector_isa_spec.t) ~target_file_path =
  try
    ensure_parent_dir target_file_path;
    let content = to_string spec in
    let oc = open_out_bin target_file_path in
    output_string oc content;
    close_out oc;
    Ok target_file_path
  with exn ->
    Error (Errors.General_error (Printf.sprintf "Failed to write sail spec to %s: %s" target_file_path (Printexc.to_string exn)))
