open Random_visa_ports

let run (module C : Ports.Compiler) ~project_dir =
  match C.compile ~project_dir with
  | Error err -> Error err
  | Ok () -> C.run_tests ~project_dir
