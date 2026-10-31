(** Hardware-feasibility cost model for synthesized V-ISAs.

    Structural validation (ports, group widths, ELEN/VLEN fits) plus an
    additive weighted cost model:

      Cost_ALU = alpha * Area + beta * Latency + gamma * Energy

    - Area: register-file silicon approximated as 32 registers x VLEN bytes
      per physical port (each read/write port costs a full crossbar over the
      register file), plus the decoder ROM (one entry per instruction) and
      the widest register group.
    - Latency: one vector ALU op serialized over LMUL register groups
      (LMUL >= 2 iterates the datapath over consecutive register groups);
      widening ops add a 1.5x pipeline penalty for the double-width result.
    - Energy: switching activity proportional to the bits toggled per
      operation (SEW x LMUL group), doubled for widening results.

    Weights default to a balanced profile and are overridable per target
    (FPGA vs. custom ASIC).                                   *)

type verdict = Ok | Warn

type cost_weights = {
  alpha_area : float;    (* weight of the area term *)
  beta_latency : float;  (* weight of the latency term *)
  gamma_energy : float;  (* weight of the energy term *)
}

let default_cost_weights = { alpha_area = 1.0; beta_latency = 1.0; gamma_energy = 0.5 }

type cost_breakdown = {
  area_estimate : float;    (* relative silicon area units *)
  latency_estimate : float; (* relative cycle count per vector op *)
  energy_estimate : float;  (* relative switching energy per vector op *)
  cost_alu : float;         (* weighted total cost *)
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

let verdict_to_string = function
  | Ok -> "ok"
  | Warn -> "warn"

let is_two_source_format = function
  | Types.Instruction_format.OP_VV
  | Types.Instruction_format.OP_RED
  | Types.Instruction_format.OP_WIDENING -> true
  | _ -> false

(* Number of architectural vector registers: the RVV register file always
   has 32 VLEN-wide registers, independent of LMUL. *)
let vector_register_count = 32

let evaluate_with_weights ~(weights : cost_weights) (spec : Vector_isa_spec.t) =
  let config = spec.config in
  let instructions = spec.instructions in

  let worst_sources =
    List.fold_left
      (fun acc (inst : Vector_instruction.t) ->
        let sources = if is_two_source_format inst.format then 2 else 1 in
        max acc sources)
      1 instructions
  in
  let read_ports = worst_sources + 1 in
  let write_ports = 1 in

  let sew_val = Types.Sew.to_bits config.default_sew in
  let lmul_mult = Types.Lmul.multiplier_val config.default_lmul in
  let group_bits = float_of_int sew_val *. lmul_mult in
  let max_group_bytes = max 1 (int_of_float (Float.round (group_bits /. 8.0))) in

  let has_widening = List.exists (fun (inst : Vector_instruction.t) -> inst.is_widening) instructions in
  let widening_dst_bits = if has_widening then sew_val * 2 else 0 in

  let vlen = config.vlen in
  let elen = config.elen in
  let vlen_bytes = vlen / 8 in

  let warnings = ref [] in
  (* Explicit LMUL grouping constraint: LMUL <= VLEN/SEW.  The register
     group SEW*LMUL must fit into a single VLEN-wide vector register;
     larger groupings overflow the register file's per-register width. *)
  let max_lmul = float vlen /. float sew_val in
  if lmul_mult > max_lmul then
    warnings := !warnings @ [
      Printf.sprintf
        "LMUL(%g) exceeds max register grouping VLEN/SEW = %d/%d = %g (SEW x LMUL = %gb > VLEN(%db))"
        lmul_mult vlen sew_val max_lmul group_bits vlen
    ];
  if has_widening && widening_dst_bits > elen then
    warnings := !warnings @ [
      Printf.sprintf "widening destination %db exceeds ELEN(%db)"
        widening_dst_bits elen
    ];

  let funct6_set =
    List.fold_left
      (fun acc (inst : Vector_instruction.t) ->
        if List.mem inst.funct6 acc then acc else inst.funct6 :: acc)
      [] instructions
  in
  let distinct_funct6 = List.length funct6_set in
  let decoder_entries = List.length instructions in

  (* Additive cost model: alpha*Area + beta*Latency + gamma*Energy *)
  let ports = read_ports + write_ports in
  let area_regfile =
    float (ports * vlen_bytes * vector_register_count)
  in
  let area_decoder = float decoder_entries in
  let area_group = float max_group_bytes in
  let area_estimate = area_regfile +. area_decoder +. area_group in
  let widening_penalty = if has_widening then 1.5 else 1.0 in
  let latency_estimate = Float.max 1.0 lmul_mult *. widening_penalty in
  let energy_estimate =
    (group_bits /. 8.0) *. (if has_widening then 2.0 else 1.0)
  in
  let cost_alu =
    weights.alpha_area *. area_estimate
    +. weights.beta_latency *. latency_estimate
    +. weights.gamma_energy *. energy_estimate
  in
  let cost = {
    area_estimate;
    latency_estimate;
    energy_estimate;
    cost_alu;
    weights;
  } in

  let verdict = if !warnings <> [] then Warn else Ok in

  {
    regfile_read_ports = read_ports;
    regfile_write_ports = write_ports;
    max_group_bytes;
    vlen_bytes;
    widening_dst_bits;
    elen_bits = elen;
    decoder_entries;
    distinct_funct6;
    cost;
    warnings = !warnings;
    verdict;
  }

let evaluate = evaluate_with_weights ~weights:default_cost_weights
