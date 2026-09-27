open Protection_types

let from_yojson (json : Yojson.Basic.t) : (t, string) result =
  Protection_types.of_yojson (json :> Yojson.Safe.t)

let to_yojson (cfg : t) : Yojson.Basic.t =
  Yojson.Safe.to_basic (Protection_types.to_yojson cfg)

let from_json_string str =
  try
    let json = Yojson.Safe.from_string str in
    Protection_types.of_yojson json
  with exn ->
    Error (Printf.sprintf "JSON parse error: %s" (Printexc.to_string exn))

let from_file path =
  if not (Sys.file_exists path) then
    Error (Printf.sprintf "Configuration file not found: %s" path)
  else
    try
      let json = Yojson.Safe.from_file path in
      Protection_types.of_yojson json
    with exn ->
      Error (Printf.sprintf "Failed to read configuration file %s: %s" path (Printexc.to_string exn))

let to_json_string ?(pretty = true) cfg =
  let json = Protection_types.to_yojson cfg in
  if pretty then Yojson.Safe.pretty_to_string json
  else Yojson.Safe.to_string json

let save_to_file path cfg =
  let str = to_json_string ~pretty:true cfg in
  let oc = open_out path in
  output_string oc str;
  output_char oc '\n';
  close_out oc
