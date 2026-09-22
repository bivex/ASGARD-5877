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

let tests = [
  Alcotest.test_case "shannon_entropy_high_and_low" `Quick test_shannon_entropy_high_and_low;
  Alcotest.test_case "shannon_entropy_empty" `Quick test_shannon_entropy_empty;
  Alcotest.test_case "shannon_entropy_uniform_distribution" `Quick test_shannon_entropy_uniform_byte_distribution;
  Alcotest.test_case "cfg_complexity_linear" `Quick test_cfg_complexity_linear;
  Alcotest.test_case "cfg_complexity_diamond" `Quick test_cfg_complexity_diamond;
  Alcotest.test_case "calculate_metrics_and_report_to_string" `Quick test_calculate_metrics_and_report_to_string;
]
