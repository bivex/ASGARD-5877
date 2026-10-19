(* Cross-engine verification of the Z_{2^64} parameter generator.
   The generator lives in scripts/mba_mod64_params.m (GNU Octave / MATLAB)
   and emits test/data/mba_mod64_golden.json.  The host engine SATURATES
   integer arithmetic, so the generator emulates Z_{2^64} with an explicit
   carry chain; the runtime uses native OCaml int64, which WRAPS.

   This test closes the loop between the two implementations: every value
   produced by the MATLAB/Octave generator is re-evaluated with the very
   same runtime functions the obfuscation layer uses.  If the two engines
   ever disagree about the semantics of Z_{2^64}, this test fails instead
   of silently shipping mismatched constants. *)

[@@@warning "-21"]

module Amp = Stack_vm.Bytecode_amplifier
module Ring = Mba_engine.Metamorphic_ring

let fail fmt = Printf.ksprintf (fun s -> Alcotest.fail s) fmt

(* The fixture is declared as a dune dependency, so it is copied into the
   build directory (dune runtest).  The extra candidates keep the binary
   usable straight from the repository root (dune exec). *)
let fixture_candidates =
  [
    "mba_mod64_golden.json";
    "data/mba_mod64_golden.json";
    "test/data/mba_mod64_golden.json";
    "../test/data/mba_mod64_golden.json";
  ]

let fixture_path =
  match List.find_opt Sys.file_exists fixture_candidates with
  | Some p -> p
  | None ->
      fail "golden fixture not found, looked in: %s"
        (String.concat ", " fixture_candidates)


let member (name : string) (json : Yojson.Safe.t) : Yojson.Safe.t =
  match json with
  | `Assoc fields -> (
      match List.assoc_opt name fields with
      | Some v -> v
      | None -> fail "fixture: missing field %S" name)
  | _ -> fail "fixture: expected an object for field %S" name

let int64_of_member (name : string) (json : Yojson.Safe.t) : int64 =
  match member name json with
  | `String s -> (
      match Int64.of_string_opt s with
      | Some v -> v
      | None -> fail "fixture: %S is not a parsable int64: %S" name s)
  | _ -> fail "fixture: %S must be a decimal string" name

let int64_of_string_value (json : Yojson.Safe.t) : int64 =
  match json with
  | `String s -> (
      match Int64.of_string_opt s with
      | Some v -> v
      | None -> fail "fixture: %S is not a parsable int64" s)
  | _ -> fail "fixture: expected a decimal string"

let int64_list_of_member (name : string) (json : Yojson.Safe.t) : int64 list =
  match member name json with
  | `List items -> List.map int64_of_string_value items
  | _ -> fail "fixture: %S must be a list" name

let int_of_member (name : string) (json : Yojson.Safe.t) : int =
  match member name json with
  | `Int i -> i
  | _ -> fail "fixture: %S must be an int" name

(* The generator emits the same value twice: as a signed decimal string
   (Int64.of_string compatible) and as an unsigned hex mirror.  Both must
   decode to the same 64-bit pattern. *)
let check_decimal_hex_agreement json =
  let pairs =
    [
      ("target", "target_hex");
      ("t0", "t0_hex");
    ]
  in
  let hex_of name json =
    match member name json with
    | `String s -> (
        match Int64.of_string_opt ("0x" ^ s) with
        | Some v -> v
        | None -> fail "fixture: %S is not a parsable hex int64: %S" name s)
    | _ -> fail "fixture: %S must be a hex string" name
  in
  let check_vector vector =
    List.iter
      (fun (dec_name, hex_name) ->
        let dec = int64_of_member dec_name vector in
        let hex = hex_of hex_name vector in
        Alcotest.(check int64) (dec_name ^ " decimal and hex must agree") dec hex)
      pairs;
    match member "coeffs" vector, member "coeffs_hex" vector with
    | `List decs, `List hexes ->
        Alcotest.(check int) "coefficient count" (List.length hexes) (List.length decs);
        List.iter2
          (fun dec hex ->
            let dec_v =
              match dec with
              | `String s -> Int64.of_string s
              | _ -> fail "fixture: coefficient must be a decimal string"
            in
            let hex_v =
              match hex with
              | `String s -> Int64.of_string ("0x" ^ s)
              | _ -> fail "fixture: coefficient hex must be a string"
            in
            Alcotest.(check int64) "coefficient decimal and hex must agree" dec_v hex_v)
          decs hexes
    | _ -> fail "fixture: coeffs / coeffs_hex must be lists"
  in
  match member "horner_vectors" json with
  | `List vectors -> List.iter check_vector vectors
  | _ -> fail "fixture: horner_vectors must be a list";
  match member "ring_keys" json with
  | `List keys ->
      List.iter
        (fun key ->
          let k_odd = int64_of_member "k_odd" key in
          let k_inv = int64_of_member "k_inv" key in
          Alcotest.(check int64) "k_odd decimal and hex must agree" k_odd
            (hex_of "k_odd_hex" key);
          Alcotest.(check int64) "k_inv decimal and hex must agree" k_inv
            (hex_of "k_inv_hex" key))
        keys
  | _ -> fail "fixture: ring_keys must be a list"

(* Every Horner vector must reproduce its target constant when evaluated
   with the RUNTIME function over native int64 arithmetic. *)
let test_horner_vectors json =
  match member "horner_vectors" json with
  | `List vectors ->
      Alcotest.(check bool) "fixture must contain horner vectors" true (List.length vectors > 0);
      List.iteri
        (fun idx vector ->
          let target = int64_of_member "target" vector in
          let t0 = int64_of_member "t0" vector in
          let coeffs = int64_list_of_member "coeffs" vector in
          Alcotest.(check bool) (Printf.sprintf "vector %d: t_0 must be odd" idx) true (Int64.logand t0 1L = 1L);
          let evaluated = Amp.eval_horner_polynomial ~t0 ~coeffs in
          Alcotest.(check int64)
            (Printf.sprintf "vector %d: Horner evaluation must equal the target" idx)
            target evaluated;
          (* a_0 = C - P_high(t_0) with P_high built as (acc + a_k) * t_0 *)
          let d = List.length coeffs - 1 in
          let p_high =
            List.fold_left
              (fun acc a_k -> Int64.mul (Int64.add acc a_k) t0)
              0L (List.filteri (fun i _ -> i < d) coeffs)
          in
          let a0 = List.nth coeffs d in
          Alcotest.(check int64)
            (Printf.sprintf "vector %d: a_0 must equal C - P_high(t_0)" idx)
            (Int64.sub target p_high) a0)
        vectors
  | _ -> fail "fixture: horner_vectors must be a list"

(* Ring keys: the generator's Newton iteration must coincide with the
   runtime's own inv_mod_2_64, and the product must be exactly 1 in
   native (wrapping) int64 arithmetic. *)
let test_ring_keys json =
  match member "ring_keys" json with
  | `List keys ->
      Alcotest.(check bool) "fixture must contain ring keys" true (List.length keys > 0);
      List.iteri
        (fun idx key ->
          let k_odd = int64_of_member "k_odd" key in
          let k_inv = int64_of_member "k_inv" key in
          Alcotest.(check bool) (Printf.sprintf "key %d: k_odd must be odd" idx) true (Int64.logand k_odd 1L = 1L);
          Alcotest.(check int64)
            (Printf.sprintf "key %d: k_odd * k_inv must be 1 mod 2^64" idx)
            1L (Int64.mul k_odd k_inv);
          Alcotest.(check int64)
            (Printf.sprintf "key %d: runtime inverse must match the generator" idx)
            (Ring.inv_mod_2_64 k_odd) k_inv;
          (* ring twist: (x * k) * k_inv == x for arbitrary x *)
          let x = Int64.logor (Int64.of_int 0x5DEECE66D) 1L in
          Alcotest.(check int64)
            (Printf.sprintf "key %d: ring twist must be the identity" idx)
            x (Int64.mul (Int64.mul x k_odd) k_inv))
        keys
  | _ -> fail "fixture: ring_keys must be a list"

(* The reference profiles mirrored by the generator must match the
   runtime constants exactly - otherwise MATLAB and OCaml would disagree
   about the obfuscation limits. *)
let test_reference_profiles json =
  let refs = member "reference_profiles" json in
  let check name (runtime_profile : Amp.amplification_profile) =
    let p = member name refs in
    Alcotest.(check int) (name ^ ".horner_degree") runtime_profile.horner_degree
      (int_of_member "horner_degree" p);
    Alcotest.(check int) (name ^ ".bit_slice_lanes") runtime_profile.bit_slice_lanes
      (int_of_member "bit_slice_lanes" p);
    Alcotest.(check int) (name ^ ".expander_chord_len") runtime_profile.expander_chord_len
      (int_of_member "expander_chord_len" p);
    Alcotest.(check int) (name ^ ".expander_chord_rate") runtime_profile.expander_chord_rate
      (int_of_member "expander_chord_rate" p)
  in
  check "heavy" Amp.default_heavy_profile;
  check "balanced" Amp.balanced_profile;
  check "light" Amp.light_profile

(* Randomised profiles must stay inside the declared limits and inside
   the bounds the runtime tolerates (anchor ring K = clamp 1..6). *)
let test_profile_bounds json =
  let bounds = member "bounds" json in
  let bound name =
    match member name bounds with
    | `List [ `Int lo; `Int hi ] -> (lo, hi)
    | _ -> fail "fixture: bound %S must be a [lo, hi] pair" name
  in
  let hd_lo, hd_hi = bound "horner_degree" in
  let bs_lo, bs_hi = bound "bit_slice_lanes" in
  let cl_lo, cl_hi = bound "expander_chord_len" in
  let cr_lo, cr_hi = bound "expander_chord_rate" in
  match member "profiles" json with
  | `List profiles ->
      List.iteri
        (fun idx p ->
          let degree = int_of_member "horner_degree" p in
          let lanes = int_of_member "bit_slice_lanes" p in
          let chord_len = int_of_member "expander_chord_len" p in
          let rate = int_of_member "expander_chord_rate" p in
          Alcotest.(check bool) (Printf.sprintf "profile %d: horner_degree in range" idx) true (degree >= hd_lo && degree <= hd_hi);
          Alcotest.(check bool) (Printf.sprintf "profile %d: bit_slice_lanes in range" idx) true (lanes >= bs_lo && lanes <= bs_hi);
          Alcotest.(check bool) (Printf.sprintf "profile %d: expander_chord_len in range" idx) true (chord_len >= cl_lo && chord_len <= cl_hi);
          Alcotest.(check bool) (Printf.sprintf "profile %d: expander_chord_rate in range" idx) true (rate >= cr_lo && rate <= cr_hi);
          (* runtime constraints *)
          Alcotest.(check bool) (Printf.sprintf "profile %d: degree >= 1" idx) true (degree >= 1);
          Alcotest.(check bool) (Printf.sprintf "profile %d: chord_len >= 1" idx) true (chord_len >= 1);
          Alcotest.(check bool) (Printf.sprintf "profile %d: rate <= 100" idx) true (rate <= 100);
          Alcotest.(check bool)
            (Printf.sprintf "profile %d: anchor ring K = clamp 1..6" idx)
            true (max 1 (min 6 chord_len) >= 1))
        profiles
  | _ -> fail "fixture: profiles must be a list"

(* The mask pool must satisfy the t_0 masking identity used by
   emit_horner_stack_insns: (t_0 ^ m) + 2*(t_0 & m) - m == t_0. *)
let test_mask_pool json =
  match member "mask_pool" json with
  | `List masks ->
      Alcotest.(check bool) "fixture must contain a mask pool" true (List.length masks > 0);
      let t0 = Int64.logor 0x0123456789ABCDEFL 1L in
      let masks = List.map int64_of_string_value masks in
      List.iteri
        (fun idx mask ->
          let lhs =
            Int64.sub
              (Int64.add (Int64.logxor t0 mask)
                 (Int64.add (Int64.logand t0 mask) (Int64.logand t0 mask)))
              mask
          in
          Alcotest.(check int64)
            (Printf.sprintf "mask %d: (t_0^m) + 2*(t_0&m) - m must equal t_0" idx)
            t0 lhs)
        masks
  | _ -> fail "fixture: mask_pool must be a list"

let () =
  let json =
    match Yojson.Safe.from_file fixture_path with
    | result -> result
    | exception Yojson.Json_error msg -> fail "cannot parse %s: %s" fixture_path msg
  in
  Alcotest.run "asgard mba mod64 crosscheck"
    [
      ( "generator output",
        [
          Alcotest.test_case "decimal and hex encodings agree" `Quick
            (fun () -> check_decimal_hex_agreement json);
          Alcotest.test_case "horner vectors reproduce their target" `Quick
            (fun () -> test_horner_vectors json);
          Alcotest.test_case "ring keys are units of Z_{2^64}" `Quick
            (fun () -> test_ring_keys json);
          Alcotest.test_case "reference profiles mirror the runtime" `Quick
            (fun () -> test_reference_profiles json);
          Alcotest.test_case "randomised profiles respect the limits" `Quick
            (fun () -> test_profile_bounds json);
          Alcotest.test_case "mask pool satisfies the t_0 identity" `Quick
            (fun () -> test_mask_pool json);
        ] );
    ]
