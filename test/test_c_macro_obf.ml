open Alcotest
open C_macro_obf

let contains_sub s sub =
  let len_s = String.length s in
  let len_sub = String.length sub in
  if len_sub > len_s then false
  else
    let found = ref false in
    for i = 0 to len_s - len_sub do
      if not !found && String.sub s i len_sub = sub then found := true
    done;
    !found

let test_header_generation () =
  let hdr = generate_header () in
  check bool "contains header guard" true (String.starts_with ~prefix:"/*" hdr);
  check bool "contains ASG_STR" true (String.length hdr > 500);
  check bool "contains ASG_MBA_ADD" true (contains_sub hdr "ASG_MBA_ADD");
  check bool "contains ASG_OPAQUE_TRUE" true (contains_sub hdr "ASG_OPAQUE_TRUE");
  check bool "contains ASG_CFF_BEGIN" true (contains_sub hdr "ASG_CFF_BEGIN");
  check bool "contains ASG_hash_api_str" true (contains_sub hdr "ASG_hash_api_str");
  check bool "contains ASG_TIMING_GUARD" true (contains_sub hdr "ASG_TIMING_GUARD_START");
  check bool "contains ASG_ANTI_DEBUG_GUARD" true (contains_sub hdr "ASG_ANTI_DEBUG_GUARD");
  check bool "contains ASG_is_debugger_present" true (contains_sub hdr "ASG_is_debugger_present")



let test_string_obfuscation () =
  let raw = "Secret_ASGARD_Key_999" in
  let obf = obfuscate_string_literal ~prefix:"ASG_" ~seed:12345 raw in
  check bool "obfuscated macro generated" true (String.starts_with ~prefix:"ASG_STR(" obf);
  check bool "does not contain plain string" false (contains_sub obf raw)

let test_constant_blinding () =
  let c = 0xDEADBEEFCAFEBABEL in
  let obf = obfuscate_constant_i64 ~prefix:"ASG_" ~seed:54321 c in
  check bool "blinded macro generated" true (String.starts_with ~prefix:"ASG_BLIND_I64(" obf)

let test_e2e_c_transformation_and_execution () =
  Test_helpers.with_temp_dir (fun tmp_dir ->
    let in_c = Filename.concat tmp_dir "main.c" in
    let out_c = Filename.concat tmp_dir "obf_main.c" in
    let hdr_file = Filename.concat tmp_dir "asgard_obf.h" in
    let bin_file = Filename.concat tmp_dir "test_bin" in

    let sample_src =
      "#include <stdio.h>\n" ^
      "#include <stdint.h>\n" ^
      "int main() {\n" ^
      "    const char* s = \"ASGARD_C_OBFUSCATION_SUCCESS\";\n" ^
      "    int64_t a = 1337;\n" ^
      "    int64_t b = 42;\n" ^
      "    int64_t sum = a + b;\n" ^
      "    int64_t x = a ^ b;\n" ^
      "    printf(\"[%s] SUM=%lld XOR=%lld\\n\", s, (long long)sum, (long long)x);\n" ^
      "    return 0;\n" ^
      "}\n"
    in

    Test_helpers.write_file_string in_c sample_src;

    let res = transform_file ~in_file:in_c ~out_file:out_c ~header_file:(Some hdr_file) () in
    check (result unit string) "transformation succeeds" (Ok ()) res;

    (* Verify compilation with clang *)
    let comp_cmd = Printf.sprintf "clang -O2 -I%s %s -o %s" tmp_dir out_c bin_file in
    let comp_status = Sys.command comp_cmd in
    check int "clang compilation returns 0" 0 comp_status;

    (* Verify execution *)
    let out_log = Filename.concat tmp_dir "output.log" in
    let run_cmd = Printf.sprintf "%s > %s" bin_file out_log in
    let run_status = Sys.command run_cmd in
    check int "execution returns 0" 0 run_status;

    let line = List.hd (String.split_on_char '\n' (Test_helpers.read_file_string out_log)) in
    check string "output matches expected decrypted string and computation"
      "[ASGARD_C_OBFUSCATION_SUCCESS] SUM=1379 XOR=1299" line)

let test_signal_based_dispatching_e2e () =
  Test_helpers.with_temp_dir (fun tmp_dir ->
    let in_c = Filename.concat tmp_dir "sig_test.c" in
    let hdr_file = Filename.concat tmp_dir "asgard_obf.h" in
    let bin_file = Filename.concat tmp_dir "sig_bin" in

    let hdr_content = generate_header () in
    Test_helpers.write_file_string hdr_file hdr_content;

    let sample_src = {|
#include "asgard_obf.h"
#include <stdio.h>
#include <stdlib.h>

static int g_secret_state = 0;

void secret_handler(void) {
    g_secret_state = 1337;
    printf("[SIGNAL_DISPATCH_OK] State=%d\n", g_secret_state);
    exit(0);
}

int main() {
    ASG_SIG_DISPATCH_SETUP();
    printf("[DISPATCHING_VIA_EXCEPTION]\n");
    ASG_SIG_JUMP(secret_handler);
    // Decompiler sees dead end / unreachable, but program continues into secret_handler!
    return 1;
}
|} in
    Test_helpers.write_file_string in_c sample_src;

    let comp_cmd = Printf.sprintf "clang -O2 -I%s %s -o %s" tmp_dir in_c bin_file in
    let comp_status = Sys.command comp_cmd in
    check int "clang compilation returns 0" 0 comp_status;

    let out_log = Filename.concat tmp_dir "sig_output.log" in
    let run_cmd = Printf.sprintf "%s > %s" bin_file out_log in
    let run_status = Sys.command run_cmd in
    check int "signal dispatch execution returns 0" 0 run_status;

    let out_str = Test_helpers.read_file_string out_log in
    check bool "signal dispatched to secret handler" true (contains_sub out_str "SIGNAL_DISPATCH_OK")
  )

let tests = [
  ("header_generation", `Quick, test_header_generation);
  ("string_obfuscation", `Quick, test_string_obfuscation);
  ("constant_blinding", `Quick, test_constant_blinding);
  ("e2e_c_transformation_and_execution", `Quick, test_e2e_c_transformation_and_execution);
  ("signal_based_dispatching_e2e", `Quick, test_signal_based_dispatching_e2e);
]

