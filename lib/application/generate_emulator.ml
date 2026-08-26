open Random_visa_ports

let run_cpp (module E : Ports.Cpp_code_emitter) spec ~output_dir =
  E.emit_emulator_project spec ~output_dir

let run_c11 (module E : Ports.C11_code_emitter) spec ~output_dir =
  E.emit_c_project spec ~output_dir
