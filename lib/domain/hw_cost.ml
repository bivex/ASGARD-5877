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

let verdict_to_string = function
  | Ok -> "ok"
  | Warn -> "warn"

let is_two_source_format = function
  | Types.Instruction_format.OP_VV
  | Types.Instruction_format.OP_RED
  | Types.Instruction_format.OP_WIDENING -> true
  | _ -> false

let evaluate (spec : Vector_isa_spec.t) =
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
  if group_bits > float_of_int vlen then
    warnings := !warnings @ [
      Printf.sprintf "SEW(%d) x LMUL(%g) = %gb exceeds VLEN(%db)"
        sew_val lmul_mult group_bits vlen
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
  let verdict = if !warnings <> [] then Warn else Ok in

  {
    regfile_read_ports = read_ports;
    regfile_write_ports = write_ports;
    max_group_bytes;
    vlen_bytes;
    widening_dst_bits;
    elen_bits = elen;
    decoder_entries = List.length instructions;
    distinct_funct6;
    warnings = !warnings;
    verdict;
  }
