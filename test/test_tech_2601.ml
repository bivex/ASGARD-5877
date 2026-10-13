(** ASGARD-5877: Tech-2601 (arXiv:2601.10261)
    Test Suite for ABI-Compliant Exception Handling Metadata Shadowing,
    Cryptographic Sealing, and Runtime Coordination. *)

open Alcotest
open Tech_2601.Tech_2601_types
open Tech_2601.Tech_2601_engine

let test_abi_shadow_rules () =
  (* Valid 16-byte aligned alloc *)
  let valid_ops = [ AllocStack 32 ] in
  (match validate_abi_shadow_rules valid_ops with
   | Ok () -> ()
   | Error _ -> fail "Expected valid ops to pass ABI check");

  (* Unaligned stack allocation must be rejected *)
  let unaligned_ops = [ AllocStack 24 ] in
  (match validate_abi_shadow_rules unaligned_ops with
   | Error (UnalignedStackAllocation 24) -> ()
   | _ -> fail "Expected UnalignedStackAllocation 24");

  (* Clobbering non-volatile register (RBP) must be rejected *)
  let clobber_rbp = [ AllocStack 32; SaveReg ("rbp", 16) ] in
  (match validate_abi_shadow_rules clobber_rbp with
   | Error (ClobberedNonVolatileReg "rbp") -> ()
   | _ -> fail "Expected ClobberedNonVolatileReg rbp");

  (* Empty ops must be rejected *)
  (match validate_abi_shadow_rules [] with
   | Error EmptyUnwindOps -> ()
   | _ -> fail "Expected EmptyUnwindOps")

let test_shadow_record_generation () =
  let dummy_meta = {
    func_name = "test_func";
    code_start_pc = 0x1000L;
    code_size = 256;
    unwind_ops = [ AllocStack 64; SaveReg ("rbp", 16) ];
    lsdata = { scopes = []; dtors = [] };
  } in
  match generate_shadow_record ~alloc_size:48 ~interceptor_symbol:"asg_eh_interceptor" dummy_meta with
  | Error err -> fail ("Shadow gen failed: " ^ error_to_string err)
  | Ok shadow ->
      check int "Shadow alloc size" 48 shadow.shadow_alloc_size;
      check string "Interceptor symbol" "asg_eh_interceptor" shadow.interceptor_symbol;
      check int "Shadow ops length" 1 (List.length shadow.shadow_ops)

let test_stack_rollback_arithmetic () =
  let shadow = {
    shadow_alloc_size = 64;
    shadow_ops = [ AllocStack 64 ];
    interceptor_symbol = "tech_2601_interceptor";
  } in
  let delta = compute_stack_rollback_delta shadow in
  check int "Stack rollback delta must be -alloc_size" (-64) delta

let test_metadata_serialization_roundtrip () =
  let original = {
    func_name = "critical_license_routine";
    code_start_pc = 0x401000L;
    code_size = 512;
    unwind_ops = [
      AllocStack 128;
      PushReg "rbx";
      SetFramePointer ("r12", 32);
      SaveReg ("r13", 16);
    ];
    lsdata = {
      scopes = [
        { scope_id = 1; start_pc = 0x401050L; end_pc = 0x401180L; landing_pad_pc = 0x401190L; catch_type_tag = 0x01l };
        { scope_id = 2; start_pc = 0x401070L; end_pc = 0x401120L; landing_pad_pc = 0x401140L; catch_type_tag = 0x02l };
      ];
      dtors = [
        { obj_id = 101; live_start_pc = 0x401060L; live_end_pc = 0x401150L; dtor_pc = 0x401200L };
        { obj_id = 102; live_start_pc = 0x401080L; live_end_pc = 0x401100L; dtor_pc = 0x401220L };
      ];
    };
  } in
  let raw = serialize_metadata original in
  match deserialize_metadata raw with
  | Error err -> fail ("Deserialization failed: " ^ error_to_string err)
  | Ok decoded ->
      check string "Func name match" original.func_name decoded.func_name;
      check int64 "Start PC match" original.code_start_pc decoded.code_start_pc;
      check int "Code size match" original.code_size decoded.code_size;
      check int "Unwind ops match" 4 (List.length decoded.unwind_ops);
      check int "Scopes match" 2 (List.length decoded.lsdata.scopes);
      check int "Dtors match" 2 (List.length decoded.lsdata.dtors);
      let sc2 = List.nth decoded.lsdata.scopes 1 in
      check int64 "Scope 2 landing pad" 0x401140L sc2.landing_pad_pc;
      let dt1 = List.hd decoded.lsdata.dtors in
      check int "Dtor obj id" 101 dt1.obj_id

let test_seal_and_unseal_integrity () =
  let master_key = Bytes.of_string "TECH_2601_MASTER_KEY_32BYTES_OK!" in
  let meta = {
    func_name = "crypto_auth_verify";
    code_start_pc = 0x500000L;
    code_size = 384;
    unwind_ops = [ AllocStack 64 ];
    lsdata = {
      scopes = [
        { scope_id = 1; start_pc = 0x500010L; end_pc = 0x500090L; landing_pad_pc = 0x5000A0L; catch_type_tag = 0x42l };
      ];
      dtors = [];
    };
  } in
  let container = seal_metadata ~master_key ~alloc_size:32 meta in

  (* Case 1: Valid unseal *)
  (match unseal_metadata ~master_key container with
   | Error err -> fail ("Unseal failed: " ^ error_to_string err)
   | Ok unsealed ->
       check string "Unsealed func name" meta.func_name unsealed.func_name;
       check int64 "Unsealed start pc" meta.code_start_pc unsealed.code_start_pc;
       check int "Unsealed scopes count" 1 (List.length unsealed.lsdata.scopes));

  (* Case 2: Wrong key fails closed *)
  let wrong_key = Bytes.of_string "WRONG_2601_MASTER_KEY_32BYTES_FAIL" in
  (match unseal_metadata ~master_key:wrong_key container with
   | Error TamperDetected -> ()
   | _ -> fail "Expected TamperDetected on wrong key");

  (* Case 3: Tampered ciphertext fails closed *)
  let tampered_blob = Bytes.copy container.encrypted_metadata_blob in
  let last_idx = Bytes.length tampered_blob - 1 in
  let orig_b = Char.code (Bytes.get tampered_blob last_idx) in
  Bytes.set tampered_blob last_idx (Char.chr (orig_b lxor 0x80));
  let tampered_container = { container with encrypted_metadata_blob = tampered_blob } in
  (match unseal_metadata ~master_key tampered_container with
   | Error TamperDetected -> ()
   | _ -> fail "Expected TamperDetected on bit-flip")

let test_exception_resolution_fsm () =
  let meta = {
    func_name = "protected_computation";
    code_start_pc = 0x1000L;
    code_size = 1000;
    unwind_ops = [ AllocStack 32 ];
    lsdata = {
      scopes = [
        (* Outer scope for general errors *)
        { scope_id = 1; start_pc = 0x1020L; end_pc = 0x1400L; landing_pad_pc = 0x1450L; catch_type_tag = 0x01l };
        (* Inner scope for specific error *)
        { scope_id = 2; start_pc = 0x1050L; end_pc = 0x1200L; landing_pad_pc = 0x1250L; catch_type_tag = 0x02l };
        (* Catch-all handler *)
        { scope_id = 3; start_pc = 0x1020L; end_pc = 0x1400L; landing_pad_pc = 0x1480L; catch_type_tag = -1l };
      ];
      dtors = [
        (* Obj 1 constructed earlier, live from 0x1030 to 0x1300 *)
        { obj_id = 1; live_start_pc = 0x1030L; live_end_pc = 0x1300L; dtor_pc = 0x1800L };
        (* Obj 2 constructed inside inner scope, live from 0x1070 to 0x1180 *)
        { obj_id = 2; live_start_pc = 0x1070L; live_end_pc = 0x1180L; dtor_pc = 0x1850L };
      ];
    };
  } in

  (* Test 1: Exception 0x02 thrown inside inner scope at 0x1100 *)
  (match resolve_exception meta ~throwing_pc:0x1100L ~exception_type:0x02l with
   | Error err -> fail ("Resolution failed: " ^ error_to_string err)
   | Ok (landing_pad, dtors) ->
       check int64 "Inner scope landing pad" 0x1250L landing_pad;
       (* Both Obj 1 and Obj 2 are active; LIFO order: Obj 2 (0x1070) then Obj 1 (0x1030) *)
       check int "Two active dtors" 2 (List.length dtors);
       check int64 "Dtor 1 (Obj 2 LIFO)" 0x1850L (List.nth dtors 0);
       check int64 "Dtor 2 (Obj 1 LIFO)" 0x1800L (List.nth dtors 1));

  (* Test 2: Exception 0x01 thrown outside inner scope at 0x1250 *)
  (match resolve_exception meta ~throwing_pc:0x1250L ~exception_type:0x01l with
   | Error err -> fail ("Resolution failed: " ^ error_to_string err)
   | Ok (landing_pad, dtors) ->
       check int64 "Outer scope landing pad" 0x1450L landing_pad;
       (* Only Obj 1 is active at 0x1250 *)
       check int "One active dtor" 1 (List.length dtors);
       check int64 "Dtor 1 (Obj 1)" 0x1800L (List.nth dtors 0));

  (* Test 3: Unhandled exception outside all scopes *)
  (match resolve_exception meta ~throwing_pc:0x1500L ~exception_type:0x01l with
   | Error (ScopeNotFound 0x1500L) -> ()
   | _ -> fail "Expected ScopeNotFound")

let test_cpp_runtime_e2e () =
  let header_dir =
    let candidates = [
      "lib/tech_2601";
      "../lib/tech_2601";
      "../../lib/tech_2601";
      "../../../lib/tech_2601";
      "/Volumes/External/Code/ASGARD-5877/lib/tech_2601";
    ] in
    match List.find_opt (fun d -> Sys.file_exists (Filename.concat d "asg_tech_2601.hpp")) candidates with
    | Some d -> d
    | None -> failwith "Could not locate lib/tech_2601/asg_tech_2601.hpp"
  in
  let master_key = Bytes.of_string "TECH_2601_CPP_MASTER_KEY_32_BYTE" in
  let meta = {
    func_name = "cpp_test_fn";
    code_start_pc = 0x2000L;
    code_size = 500;
    unwind_ops = [ AllocStack 32 ];
    lsdata = {
      scopes = [
        { scope_id = 1; start_pc = 0x2050L; end_pc = 0x2150L; landing_pad_pc = 0x2160L; catch_type_tag = 0x10l };
      ];
      dtors = [
        { obj_id = 1; live_start_pc = 0x2060L; live_end_pc = 0x2140L; dtor_pc = 0x2300L };
      ];
    };
  } in
  let container = seal_metadata ~master_key ~alloc_size:32 meta in

  let hex_of_bytes b =
    let buf = Buffer.create (Bytes.length b * 4) in
    for i = 0 to Bytes.length b - 1 do
      if i > 0 then Buffer.add_string buf ", ";
      Buffer.add_string buf (Printf.sprintf "0x%02X" (Char.code (Bytes.get b i)))
    done;
    Buffer.contents buf
  in

  let cpp_src = Printf.sprintf {|
#include "asg_tech_2601.hpp"
#include <cassert>
#include <iostream>

int main() {
    using namespace asgard::tech_2601;

    // Test 1: Stack rollback
    uintptr_t current_sp = 0x7FFF0040;
    uintptr_t restored_sp = tech_2601_rollback_stack(current_sp, 32);
    assert(restored_sp == 0x7FFF0020);

    // Test 2: Unseal container
    const uint8_t master_key[] = { %s };
    Tech2601ProtectedContainer container;
    container.func_name = "%s";
    container.code_start_pc = 0x%LXL;
    container.code_size = %d;
    container.shadow.shadow_alloc_size = %d;
    container.shadow.interceptor_symbol = "%s";
    
    const uint8_t cipher_bytes[] = { %s };
    container.encrypted_blob.assign(cipher_bytes, cipher_bytes + sizeof(cipher_bytes));

    const uint8_t tag_bytes[] = { %s };
    std::memcpy(container.auth_tag, tag_bytes, 32);

    Tech2601OriginalMetadata out_meta;
    bool ok = tech_2601_unseal(master_key, sizeof(master_key), container, out_meta);
    assert(ok && "Unseal failed in C++");
    assert(out_meta.func_name == "%s");
    assert(out_meta.scopes.size() == 1);
    assert(out_meta.dtors.size() == 1);

    // Test 3: Resolve exception
    uint64_t landing_pad = 0;
    std::vector<uint64_t> dtors;
    bool resolved = tech_2601_resolve_exception(out_meta, 0x2070, 0x10, &landing_pad, dtors);
    assert(resolved && "Exception resolution failed in C++");
    assert(landing_pad == 0x2160);
    assert(dtors.size() == 1);
    assert(dtors[0] == 0x2300);

    // Test 4: Tamper detection fails closed
    container.auth_tag[0] ^= 0xFF;
    bool tamper_detected = !tech_2601_unseal(master_key, sizeof(master_key), container, out_meta);
    assert(tamper_detected && "Tamper detection failed to fail-closed in C++");

    std::cout << "CPP_TECH_2601_SUCCESS\n";
    return 0;
}
|}
    (hex_of_bytes master_key)
    container.func_name
    container.code_start_pc
    container.code_size
    container.shadow.shadow_alloc_size
    container.shadow.interceptor_symbol
    (hex_of_bytes container.encrypted_metadata_blob)
    (hex_of_bytes container.auth_tag)
    meta.func_name
  in

  let tmp_cpp = Filename.temp_file "tech_2601_test" ".cpp" in
  let tmp_bin = Filename.temp_file "tech_2601_test" ".bin" in
  let oc = open_out tmp_cpp in
  output_string oc cpp_src;
  close_out oc;

  let compile_cmd = Printf.sprintf "clang++ -std=c++17 -I %s %s -o %s" (Filename.quote header_dir) (Filename.quote tmp_cpp) (Filename.quote tmp_bin) in
  let compile_rc = Sys.command compile_cmd in
  check int "Clang++ compile return code" 0 compile_rc;

  let run_cmd = Filename.quote tmp_bin in
  let run_rc = Sys.command run_cmd in
  check int "Runtime C++ binary return code" 0 run_rc;

  (try Sys.remove tmp_cpp; Sys.remove tmp_bin with _ -> ())

let tests = [
  ("ABI Shadow Rules Validation", `Quick, test_abi_shadow_rules);
  ("Shadow Record Generation", `Quick, test_shadow_record_generation);
  ("Stack Rollback Arithmetic", `Quick, test_stack_rollback_arithmetic);
  ("Metadata Serialization Roundtrip", `Quick, test_metadata_serialization_roundtrip);
  ("Cryptographic Seal & Integrity Verification", `Quick, test_seal_and_unseal_integrity);
  ("Exception Resolution FSM & LIFO Destructors", `Quick, test_exception_resolution_fsm);
  ("C++ Runtime Interceptor Roundtrip E2E", `Quick, test_cpp_runtime_e2e);
]
