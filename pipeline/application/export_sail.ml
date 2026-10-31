open Random_visa_domain
open Random_visa_ports

let to_string spec = Vector_isa_spec.to_sail_specification spec

let run (module W : Ports.Sail_spec_writer) spec ~target_file_path =
  W.write_spec spec ~target_file_path
