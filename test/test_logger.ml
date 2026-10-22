open Alcotest
open Random_visa_ports.Logger

let test_level_conversions () =
  check string "Debug to string" "DEBUG" (level_to_string Debug);
  check string "Info to string" "INFO" (level_to_string Info);
  check string "Warn to string" "WARN" (level_to_string Warn);
  check string "Error to string" "ERROR" (level_to_string Error);
  check string "Quiet to string" "QUIET" (level_to_string Quiet);

  check bool "parse debug" true (level_of_string "debug" = Some Debug);
  check bool "parse DEBUG" true (level_of_string "DEBUG" = Some Debug);
  check bool "parse info" true (level_of_string "info" = Some Info);
  check bool "parse warn" true (level_of_string "warn" = Some Warn);
  check bool "parse warning" true (level_of_string "warning" = Some Warn);
  check bool "parse error" true (level_of_string "error" = Some Error);
  check bool "parse quiet" true (level_of_string "quiet" = Some Quiet);
  check bool "parse silent" true (level_of_string "silent" = Some Quiet);
  check bool "parse unknown" true (level_of_string "invalid" = None)

let test_level_filtering () =
  let old_level = get_level () in
  let messages = ref [] in
  let test_sink = {
    write = (fun lvl sec loc msg -> messages := (lvl, sec, loc, msg) :: !messages);
    flush = (fun () -> ());
  } in
  set_sink test_sink;
  set_level Warn;

  debug ~section:"TEST" "should be ignored";
  info ~section:"TEST" "should also be ignored";
  warn ~section:"TEST" "warning message";
  error ~section:"TEST" "error message";

  let msgs = List.rev !messages in
  check int "only warn and error recorded" 2 (List.length msgs);

  let lvl1, sec1, _, text1 = List.nth msgs 0 in
  check bool "first is Warn" true (lvl1 = Warn);
  check (option string) "section is TEST" (Some "TEST") sec1;
  check string "text is warning message" "warning message" text1;

  let lvl2, sec2, _, text2 = List.nth msgs 1 in
  check bool "second is Error" true (lvl2 = Error);
  check (option string) "section is TEST" (Some "TEST") sec2;
  check string "text is error message" "error message" text2;

  set_level old_level;
  reset_sink ()

let test_step_formatting () =
  let old_level = get_level () in
  let old_color = is_color_enabled () in
  set_color_enabled false;
  set_level Info;

  let messages = ref [] in
  let test_sink = {
    write = (fun lvl sec loc msg -> messages := (lvl, sec, loc, msg) :: !messages);
    flush = (fun () -> ());
  } in
  set_sink test_sink;

  step ~section:"PIPELINE" ~step:3 ~total:8 "Packaging VM bytecode";
  stepf ~section:"PIPELINE" ~step:4 ~total:8 "Writing %d headers" 3;

  let msgs = List.rev !messages in
  check int "2 step messages recorded" 2 (List.length msgs);

  let lvl1, sec1, _, text1 = List.nth msgs 0 in
  check bool "level is Info" true (lvl1 = Info);
  check (option string) "section is PIPELINE" (Some "PIPELINE") sec1;
  check string "step prefix formatted" "[3/8] Packaging VM bytecode" text1;

  let lvl2, sec2, _, text2 = List.nth msgs 1 in
  check bool "level is Info" true (lvl2 = Info);
  check (option string) "section is PIPELINE" (Some "PIPELINE") sec2;
  check string "stepf prefix formatted" "[4/8] Writing 3 headers" text2;

  set_color_enabled old_color;
  set_level old_level;
  reset_sink ()

let test_formatted_logging () =
  let old_level = get_level () in
  set_level Debug;

  let messages = ref [] in
  let test_sink = {
    write = (fun lvl sec loc msg -> messages := (lvl, sec, loc, msg) :: !messages);
    flush = (fun () -> ());
  } in
  set_sink test_sink;

  debugf ~section:"MATH" "Calculated %s: 0x%08X" "checksum" 0x1337BEEF;
  infof "Simple log with number %d and string '%s'" 42 "alpha";

  let msgs = List.rev !messages in
  check int "2 formatted messages recorded" 2 (List.length msgs);

  let _, sec1, _, text1 = List.nth msgs 0 in
  check (option string) "section is MATH" (Some "MATH") sec1;
  check string "hex formatted" "Calculated checksum: 0x1337BEEF" text1;

  let _, sec2, _, text2 = List.nth msgs 1 in
  check (option string) "no section" None sec2;
  check string "simple log formatted" "Simple log with number 42 and string 'alpha'" text2;

  set_level old_level;
  reset_sink ()

let test_location_formatting () =
  let old_level = get_level () in
  set_level Info;

  check string "parse raw __LOC__" "foo.ml:42"
    (format_loc "File \"lib/application/foo.ml\", line 42, characters 10-20");
  check string "passthrough file:line" "bar.ml:100" (format_loc "bar.ml:100");

  let messages = ref [] in
  let test_sink = {
    write = (fun lvl sec loc msg -> messages := (lvl, sec, loc, msg) :: !messages);
    flush = (fun () -> ());
  } in
  set_sink test_sink;

  info ~section:"PIPELINE" ~loc:"protect_pipeline.ml:50" "Starting pipeline";
  infof ~section:"PACKAGER" ~file:"vm_packagers.ml" ~line:100 "Packaging function %s" "main";

  let msgs = List.rev !messages in
  check int "2 messages with loc" 2 (List.length msgs);

  let _, sec1, loc1, text1 = List.nth msgs 0 in
  check (option string) "section is PIPELINE" (Some "PIPELINE") sec1;
  check string "loc is protect_pipeline.ml:50" "protect_pipeline.ml:50" loc1;
  check string "text is starting pipeline" "Starting pipeline" text1;

  let _, sec2, loc2, text2 = List.nth msgs 1 in
  check (option string) "section is PACKAGER" (Some "PACKAGER") sec2;
  check string "loc is vm_packagers.ml:100" "vm_packagers.ml:100" loc2;
  check string "text is packaging" "Packaging function main" text2;

  set_level old_level;
  reset_sink ()

let tests = [
  ("level_conversions", `Quick, test_level_conversions);
  ("level_filtering", `Quick, test_level_filtering);
  ("step_formatting", `Quick, test_step_formatting);
  ("formatted_logging", `Quick, test_formatted_logging);
  ("location_formatting", `Quick, test_location_formatting);
]
