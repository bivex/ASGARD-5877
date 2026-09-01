open Native_vm
open X86_lifter

(** Tests for [Protection_config] — JSON & Preset Configuration for ASGARD-5877. *)

let test_presets () =
  Alcotest.(check bool) "default config has cff enabled" true Protection_config.default.cff.enabled;
  Alcotest.(check bool) "max_security has depth 4" true (Protection_config.max_security.mba.depth = 4);
  Alcotest.(check bool) "lightweight has cff disabled" false Protection_config.lightweight.cff.enabled;
  Alcotest.(check bool) "stealth has ncfg engine" true (Protection_config.stealth.mba.engine = `Ncfg);

  match Protection_config.from_preset "military" with
  | Ok cfg -> Alcotest.(check int) "military alias maps to max_security" 4 cfg.mba.depth
  | Error err -> Alcotest.fail err

let test_json_roundtrip () =
  let original = Protection_config.max_security in
  let json_str = Protection_config.to_json_string ~pretty:true original in
  match Protection_config.from_json_string json_str with
  | Error err -> Alcotest.fail err
  | Ok parsed ->
      Alcotest.(check bool) "cff.enabled matches" original.cff.enabled parsed.cff.enabled;
      Alcotest.(check int) "mba.depth matches" original.mba.depth parsed.mba.depth;
      Alcotest.(check bool) "anti_tamper.smc matches" original.anti_tamper.smc parsed.anti_tamper.smc;
      Alcotest.(check bool) "anti_pushan.running_key matches" original.anti_pushan.running_key parsed.anti_pushan.running_key;
      Alcotest.(check int) "vm_runtime.num_dispatch_domains matches" original.vm_runtime.num_dispatch_domains parsed.vm_runtime.num_dispatch_domains

let test_partial_json_parsing () =
  let partial_json = {|
  {
    "seed": 99999,
    "cff": {
      "enabled": false
    },
    "mba": {
      "depth": 3,
      "engine": "egraph"
    }
  }
  |} in
  match Protection_config.from_json_string partial_json with
  | Error err -> Alcotest.fail err
  | Ok cfg ->
      Alcotest.(check (option int)) "seed is 99999" (Some 99999) cfg.seed;
      Alcotest.(check bool) "cff.enabled is false" false cfg.cff.enabled;
      Alcotest.(check int) "mba.depth is 3" 3 cfg.mba.depth;
      Alcotest.(check bool) "mba.enabled defaults to true" true cfg.mba.enabled;
      Alcotest.(check bool) "anti_pushan defaults to true" true cfg.anti_pushan.enabled;
      Alcotest.(check bool) "anti_tamper defaults to true" true cfg.anti_tamper.enabled

let test_protection_with_config () =
  let rng = Random.State.make [| 42 |] in
  let asm = {|
func_cfg_test:
    mov rax, 10
    add rax, 20
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let config = Protection_config.lightweight in
      let pkg = Vm_emitter.compile_and_package ~rng ~config func in
      Alcotest.(check bool) "lightweight bytecode emitted" true (List.length pkg.bytecode > 0);

      let config_max = Protection_config.max_security in
      let pkg_max = Vm_emitter.compile_and_package ~rng ~config:config_max func in
      Alcotest.(check bool) "max_security bytecode emitted" true (List.length pkg_max.bytecode > 0);
      Alcotest.(check bool) "max_security DRS > lightweight DRS" true
        (pkg_max.metrics.devirtualization_resistance_score >= pkg.metrics.devirtualization_resistance_score)

let tests = [
  Alcotest.test_case "presets" `Quick test_presets;
  Alcotest.test_case "json_roundtrip" `Quick test_json_roundtrip;
  Alcotest.test_case "partial_json_parsing" `Quick test_partial_json_parsing;
  Alcotest.test_case "protection_with_config" `Quick test_protection_with_config;
]
