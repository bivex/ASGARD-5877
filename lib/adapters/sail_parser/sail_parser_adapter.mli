open Random_visa_domain
open Random_visa_ports

include Ports.Sail_parser

val parse_source : ?spec_name:string -> string -> (Vector_isa_spec.t, Errors.t) result
