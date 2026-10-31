(** Hardware-feasibility cost model for synthesized V-ISAs. *)

type verdict = Ok | Warn

type cost_weights = {
  alpha_area : float;    (** weight of the area term *)
  beta_latency : float;  (** weight of the latency term *)
  gamma_energy : float;  (** weight of the energy term *)
}

val default_cost_weights : cost_weights

type cost_breakdown = {
  area_estimate : float;    (** relative silicon area units *)
  latency_estimate : float; (** relative cycle count per vector op *)
  energy_estimate : float;  (** relative switching energy per vector op *)
  cost_alu : float;         (** weighted total: alpha*Area + beta*Latency + gamma*Energy *)
  weights : cost_weights;
}

type report = {
  regfile_read_ports : int;
  regfile_write_ports : int;
  max_group_bytes : int;
  vlen_bytes : int;
  widening_dst_bits : int;
  elen_bits : int;
  decoder_entries : int;
  distinct_funct6 : int;
  cost : cost_breakdown;
  warnings : string list;
  verdict : verdict;
}

val evaluate : Vector_isa_spec.t -> report
val evaluate_with_weights : weights:cost_weights -> Vector_isa_spec.t -> report

val verdict_to_string : verdict -> string
