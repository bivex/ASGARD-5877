open Random_visa_domain
open Random_visa_ports

type pipeline_result = {
  spec_name : string;
  instruction_count : int;
  sail_file_path : string;
  emitted_files : string list;
  compilation_success : bool;
  compiler_output : string;
  execution_output : string;
  hw_cost_report : Hw_cost.report;
  vlen : int;
  elen : int;
  seed : int option;
  profile : string;
}

val run :
  sail_writer:(module Ports.Sail_spec_writer) ->
  cpp_emitter:(module Ports.Cpp_code_emitter) ->
  ?compiler:(module Ports.Compiler) ->
  rng:Random.State.t ->
  name:string ->
  num_instructions:int ->
  output_dir:string ->
  ?vlen:int ->
  ?seed:int ->
  ?compile_and_test:bool ->
  ?profile_name:string ->
  unit ->
  (pipeline_result, Errors.t) result
