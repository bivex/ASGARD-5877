open Random_visa_ports

let run (module P : Ports.Sail_parser) ?spec_name content =
  P.parse ?spec_name content

let run_file (module P : Ports.Sail_parser) ?spec_name file_path =
  P.parse_file ?spec_name file_path
