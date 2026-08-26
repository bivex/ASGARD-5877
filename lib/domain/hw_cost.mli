(** Hardware-feasibility cost model for synthesized V-ISAs. *)

type verdict = Ok | Warn

type report = {
  regfile_read_ports : int;
  regfile_write_ports : int;
  max_group_bytes : int;
  vlen_bytes : int;
  widening_dst_bits : int;
  elen_bits : int;
  decoder_entries : int;
  distinct_funct6 : int;
  warnings : string list;
  verdict : verdict;
}

val evaluate : Vector_isa_spec.t -> report

val verdict_to_string : verdict -> string
