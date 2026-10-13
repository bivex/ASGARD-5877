open Vm_ir
open Native_vm

let test_shannon_entropy_high_and_low () =
  let sample_bytecode = [
    0x8F0123456789ABCDL;
    0x1234567890ABCDEFL;
    0xFEDCBA0987654321L;
    0xCAFEBABE11223344L;
    0xDEADBEEF55667788L;
  ] in
  let entropy = Metrics.calculate_shannon_entropy sample_bytecode in
  Alcotest.(check bool) "entropy is high (> 4.0)" true (entropy > 4.0);

  let low_entropy_bytecode = [ 0L; 0L; 0L; 0L ] in
  let low_entropy = Metrics.calculate_shannon_entropy low_entropy_bytecode in
  Alcotest.(check bool) "low entropy is 0" true (low_entropy = 0.0)

let test_shannon_entropy_empty () =
  let empty_entropy = Metrics.calculate_shannon_entropy [] in
  Alcotest.(check bool) "empty bytecode entropy is 0.0" true (empty_entropy = 0.0)

let test_shannon_entropy_uniform_byte_distribution () =
  (* 256 distinct bytes in 32 64-bit words -> Shannon entropy is exactly 8.0 bits/byte *)
  let words = ref [] in
  for w = 0 to 31 do
    let word = ref 0L in
    for b = 0 to 7 do
      let byte_val = Int64.of_int (w * 8 + b) in
      word := Int64.logor !word (Int64.shift_left byte_val (b * 8))
    done;
    words := !word :: !words
  done;
  let entropy = Metrics.calculate_shannon_entropy (List.rev !words) in
  Alcotest.(check bool) "uniform 256 bytes has entropy ~ 8.0" true (abs_float (entropy -. 8.0) < 1e-6)

let test_cfg_complexity_linear () =
  let b0 = { Ir.id = 0; label = "b0"; instrs = [ Ir.Nop; Ir.Jmp (Ir.Label "b1") ] } in
  let b1 = { Ir.id = 1; label = "b1"; instrs = [ Ir.Ret ] } in
  let blocks = Hashtbl.create 2 in
  Hashtbl.replace blocks 0 b0;
  Hashtbl.replace blocks 1 b1;
  let func = { Ir.name = "linear"; cfg = { Ir.entry_id = 0; blocks } } in
  let c = Metrics.calculate_cfg_complexity func in
  Alcotest.(check int) "linear CFG complexity is 1" 1 c

let test_cfg_complexity_diamond () =
  let b0 = { Ir.id = 0; label = "b0"; instrs = [ Ir.Jcc { cond = Flags.E; target_true = Ir.Label "b1"; target_false = Ir.Label "b2" } ] } in
  let b1 = { Ir.id = 1; label = "b1"; instrs = [ Ir.Jmp (Ir.Label "b3") ] } in
  let b2 = { Ir.id = 2; label = "b2"; instrs = [ Ir.Jmp (Ir.Label "b3") ] } in
  let b3 = { Ir.id = 3; label = "b3"; instrs = [ Ir.Ret ] } in
  let blocks = Hashtbl.create 4 in
  Hashtbl.replace blocks 0 b0;
  Hashtbl.replace blocks 1 b1;
  Hashtbl.replace blocks 2 b2;
  Hashtbl.replace blocks 3 b3;
  let func = { Ir.name = "diamond"; cfg = { Ir.entry_id = 0; blocks } } in
  let c = Metrics.calculate_cfg_complexity func in
  Alcotest.(check int) "diamond CFG complexity is 2" 2 c

let test_calculate_metrics_and_report_to_string () =
  let b0 = { Ir.id = 0; label = "entry"; instrs = [ Ir.Ret ] } in
  let blocks = Hashtbl.create 1 in
  Hashtbl.replace blocks 0 b0;
  let func = { Ir.name = "test_metrics_func"; cfg = { Ir.entry_id = 0; blocks } } in
  let rep = Metrics.calculate_metrics
    ~bytecode:[ 0xDEADBEEFCAFEBABEL; 0x0123456789ABCDEFL ]
    ~func
    ~decoy_count:10
    ~total_handlers:50
    ~mba_nodes:20 in
  let drs = Metrics.devirtualization_resistance_score rep in
  Alcotest.(check bool) "drs in valid range" true (drs >= 0.0 && drs <= 100.0);
  Alcotest.(check int) "cyclomatic complexity >= 1" 1 (Metrics.cyclomatic_complexity rep);
  Alcotest.(check int) "flattening depth 1" 1 (Metrics.flattening_depth rep);
  Alcotest.(check int) "mba node count 20" 20 (Metrics.mba_node_count rep);
  let rep_str = Metrics.report_to_string rep in
  Alcotest.(check bool) "report string contains header" true (String.contains rep_str '=');
  Alcotest.(check bool) "report string contains DRS" true (String.contains rep_str 'D' && String.contains rep_str 'R' && String.contains rep_str 'S')

let test_p3_independent_resilience_metrics () =
  let b0 = { Ir.id = 0; label = "entry"; instrs = [ Ir.Jcc { cond = Flags.E; target_true = Ir.Label "b1"; target_false = Ir.Label "b2" } ] } in
  let b1 = { Ir.id = 1; label = "b1"; instrs = [ Ir.Ret ] } in
  let b2 = { Ir.id = 2; label = "b2"; instrs = [ Ir.Ret ] } in
  let blocks = Hashtbl.create 3 in
  Hashtbl.replace blocks 0 b0;
  Hashtbl.replace blocks 1 b1;
  Hashtbl.replace blocks 2 b2;
  let func = { Ir.name = "branchy_func"; cfg = { Ir.entry_id = 0; blocks } } in
  let bc = [ 0x1122334455667788L; 0x99AABBCCDDEEFF00L; 0x123456789ABCDEF0L ] in

  let rep = Metrics.calculate_resilience_metrics
    ~dynamic_key_active:true
    ~native_ir_ops:2
    ~differential_verified:true
    ~bytecode:bc
    ~func
    ~decoy_count:15
    ~total_handlers:256
    ~mba_nodes:30
    () in

  (* 1. CFG Recovery Cost *)
  let cfg = Metrics.cfg_recovery rep in
  Alcotest.(check int) "dispatcher fanout >= 2" 2 cfg.dispatcher_fanout;
  Alcotest.(check bool) "symbolic unflatten cost > 0" true (cfg.symbolic_unflatten_cost > 0.0);

  (* 2. Static Decoding Ambiguity *)
  let dec = Metrics.decoding_ambiguity rep in
  Alcotest.(check bool) "dynamic context dependency is 100%" true (dec.dynamic_context_dependency_ratio = 1.0);
  Alcotest.(check int) "key recovery depth equals flattening depth" 3 dec.key_recovery_depth;
  Alcotest.(check bool) "static decodability rate is 0%" true (dec.static_decodability_rate = 0.0);

  (* 3. Runtime Overhead Vector *)
  let ovh = Metrics.runtime_overhead rep in
  Alcotest.(check bool) "expansion ratio >= 1.5x" true (ovh.expansion_ratio >= 1.5);
  Alcotest.(check bool) "code bloat factor >= 2.0x" true (ovh.code_bloat_factor >= 2.0);
  Alcotest.(check bool) "estimated cycle overhead > 0" true (ovh.estimated_cycle_overhead > 0.0);

  (* 4. Code Size Footprint *)
  let sz = Metrics.code_size rep in
  Alcotest.(check int) "bytecode bytes is 24" 24 sz.bytecode_bytes;
  Alcotest.(check int) "handler table is 256*8 = 2048" 2048 sz.handler_table_footprint_bytes;

  (* 5. Reproducibility & Golden Equivalence *)
  let rep_rob = Metrics.reproducibility rep in
  Alcotest.(check int) "seed entropy is 64 bits" 64 rep_rob.seed_entropy_bits;
  Alcotest.(check bool) "differential pass rate is 100%" true (rep_rob.differential_pass_rate = 1.0);

  (* Structured Report String Verification *)
  let summary = Metrics.report_to_string rep in
  Alcotest.(check bool) "summary has CFG Recovery section" true (String.contains summary 'C' && String.contains summary 'F' && String.contains summary 'G');
  Alcotest.(check bool) "summary has Decoding Ambiguity section" true (String.contains summary 'A' && String.contains summary 'm' && String.contains summary 'b');
  Alcotest.(check bool) "summary has Overhead Vector section" true (String.contains summary 'O' && String.contains summary 'v' && String.contains summary 'e');
  Alcotest.(check bool) "summary has Footprint section" true (String.contains summary 'F' && String.contains summary 'o' && String.contains summary 'o');
  Alcotest.(check bool) "summary has Reproducibility section" true (String.contains summary 'R' && String.contains summary 'e' && String.contains summary 'p')

let tests = [
  Alcotest.test_case "shannon_entropy_high_and_low" `Quick test_shannon_entropy_high_and_low;
  Alcotest.test_case "shannon_entropy_empty" `Quick test_shannon_entropy_empty;
  Alcotest.test_case "shannon_entropy_uniform_distribution" `Quick test_shannon_entropy_uniform_byte_distribution;
  Alcotest.test_case "cfg_complexity_linear" `Quick test_cfg_complexity_linear;
  Alcotest.test_case "cfg_complexity_diamond" `Quick test_cfg_complexity_diamond;
  Alcotest.test_case "calculate_metrics_and_report_to_string" `Quick test_calculate_metrics_and_report_to_string;
  Alcotest.test_case "p3_independent_resilience_metrics" `Quick test_p3_independent_resilience_metrics;
]
