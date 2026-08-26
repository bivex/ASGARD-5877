open Vm_ir

type metrics_report = {
  shannon_entropy : float;
  cyclomatic_complexity : int;
  flattening_depth : int;
  decoy_density : float;
  mba_node_count : int;
  devirtualization_resistance_score : float;
}

let calculate_shannon_entropy words =
  if words = [] then 0.0
  else
    let byte_counts = Array.make 256 0 in
    let total_bytes = ref 0 in
    List.iter
      (fun w ->
        for b_idx = 0 to 7 do
          let b = Int64.to_int (Int64.logand (Int64.shift_right_logical w (b_idx * 8)) 0xFFL) in
          byte_counts.(b) <- byte_counts.(b) + 1;
          incr total_bytes
        done)
      words;

    let tot = float_of_int !total_bytes in
    let entropy = ref 0.0 in
    for i = 0 to 255 do
      if byte_counts.(i) > 0 then begin
        let p = float_of_int byte_counts.(i) /. tot in
        entropy := !entropy -. (p *. (log p /. log 2.0))
      end
    done;
    !entropy

let calculate_cfg_complexity (func : Ir.func) =
  let blocks = Hashtbl.fold (fun _ b acc -> b :: acc) func.cfg.blocks [] in
  let num_vertices = List.length blocks in
  let num_edges =
    List.fold_left
      (fun acc (b : Ir.basic_block) ->
        acc + List.length (Ir.successors b))
      0
      blocks
  in
  max 1 (num_edges - num_vertices + 2)

let calculate_metrics ~bytecode ~func ~decoy_count ~total_handlers ~mba_nodes =
  let entropy = calculate_shannon_entropy bytecode in
  let complexity = calculate_cfg_complexity func in
  let flattening_depth = Hashtbl.length func.cfg.blocks in
  let decoy_density =
    if total_handlers <= 0 then 0.0
    else float_of_int decoy_count /. float_of_int total_handlers
  in

  (* Calculate composite Devirtualization Resistance Score (0.0 to 100.0) *)
  let s_entropy = min 25.0 ((entropy /. 8.0) *. 25.0) in
  let s_complexity = min 25.0 ((float_of_int complexity /. 10.0) *. 25.0) in
  let s_mba = min 25.0 ((float_of_int mba_nodes /. 40.0) *. 25.0) in
  let s_decoy = min 25.0 ((decoy_density /. 0.25) *. 25.0) in
  let drs = s_entropy +. s_complexity +. s_mba +. s_decoy in

  {
    shannon_entropy = entropy;
    cyclomatic_complexity = complexity;
    flattening_depth;
    decoy_density;
    mba_node_count = mba_nodes;
    devirtualization_resistance_score = drs;
  }

let report_to_string r =
  let b = Buffer.create 512 in
  Buffer.add_string b "================ DEVIRTUALIZATION RESISTANCE REPORT ================\n";
  Buffer.add_string b (Printf.sprintf "  Shannon Bytecode Entropy:        %.3f / 8.000 bits/byte\n" r.shannon_entropy);
  Buffer.add_string b (Printf.sprintf "  CFG Cyclomatic Complexity:       %d\n" r.cyclomatic_complexity);
  Buffer.add_string b (Printf.sprintf "  Control Flow Flattening Depth:   %d blocks\n" r.flattening_depth);
  Buffer.add_string b (Printf.sprintf "  Decoy / Junk Trap Density:       %.1f%%\n" (r.decoy_density *. 100.0));
  Buffer.add_string b (Printf.sprintf "  MBA Transformation Node Count:   %d nodes\n" r.mba_node_count);
  Buffer.add_string b "--------------------------------------------------------------------\n";
  Buffer.add_string b (Printf.sprintf "  TOTAL RESISTANCE SCORE (DRS):    %.1f / 100.0 [ %s ]\n"
                         r.devirtualization_resistance_score
                         (if r.devirtualization_resistance_score >= 80.0 then "MIL-GRADE HARDENED"
                          else if r.devirtualization_resistance_score >= 50.0 then "STRONG OBFUSCATION"
                          else "STANDARD PROTECTION"));
  Buffer.add_string b "====================================================================\n";
  Buffer.contents b
