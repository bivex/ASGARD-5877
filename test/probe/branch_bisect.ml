open Multi_vm
let corruption_seen = ref false
let run ?(seed=9292) ~label (cfg : Native_vm.Protection_config.t option) =
  let asm = {|
    mov x0, #42
    cmp x0, #40
    b.gt .Lgreater
    mov x0, #1
    ret
.Lgreater:
    add x0, x0, #8
    ret
  |} in
  match Arm64_lifter.lift_function asm with
  | Error e -> Printf.printf "%s: lift fail %s\n" label e
  | Ok func ->
      let rng = Random.State.make [| seed |] in
      (try
        let mba = match cfg with Some c -> c.mba.enabled | None -> false in
        let depth = match cfg with Some c -> c.mba.depth | None -> 2 in
        let pkg = Multi_vm_emitter.compile_and_package ~rng ~enable_cff:false
          ~enable_mba:mba ~mba_depth:depth ?config:cfg func in
        let dir = "/tmp/asg_bb" in
        ignore (Sys.command ("rm -rf " ^ dir));
        Unix.mkdir dir 0o755;
        let oc = open_out (dir ^ "/multi_vm_runtime.hpp") in output_string oc pkg.cpp_runtime_source; close_out oc;
        let oc = open_out (dir ^ "/runner.cpp") in output_string oc pkg.runner_source; close_out oc;
        ignore (Sys.command (Printf.sprintf "clang++ -std=c++20 -O0 -I%s %s/runner.cpp -o %s/app 2>%s/e.txt" dir dir dir dir));
        if Sys.file_exists (dir ^ "/app") then begin
          let ic = Unix.open_process_in (dir ^ "/app") in
          let buf = Buffer.create 128 in
          (try while true do Buffer.add_string buf (input_line ic); Buffer.add_char buf '\n' done with End_of_file -> ());
          close_in ic;
          let s = Buffer.contents buf in
          let rax = try
            let re = Str.regexp "Result (RAX): \\([0-9]+\\)" in
            ignore (Str.search_forward re s 0); int_of_string (Str.matched_group 1 s)
          with e -> Printf.printf "REGEX-FAIL %s (got: %s)\n" (Printexc.to_string e) s; (-999) in
          Printf.printf "%-24s seed=%d trans=%d RAX=%d %s\n" label seed pkg.partition.inter_vm_transitions rax
            (if rax = 50 then "OK" else "*** CORRUPT ***");
          if rax <> 50 then corruption_seen := true
        end else Printf.printf "%-24s BUILD FAILED\n" label
      with e -> Printf.printf "%-24s EXN %s\n" label (Printexc.to_string e))

let () =
  let open Native_vm.Protection_config in
  let seeds = [ 1; 2; 3; 4; 5; 6; 7; 8 ] in
  let avg label cfg =
    let bad = List.fold_left (fun acc s ->
      match (run ~seed:s ~label:label cfg), () with
      | _, () -> acc) 0 seeds in
    ignore bad in
  ignore avg;
  (* single-feature toggles, all seeds *)
  let one_off label mk = List.iter (fun s -> run ~seed:s ~label (Some (mk default))) seeds in
  one_off "junk-ON-only-base" (fun c -> c);
  one_off "junk-OFF" (fun c -> { c with vm_runtime = { c.vm_runtime with enable_junk_instructions = false } });
  one_off "key-OFF" (fun c -> { c with anti_pushan = { c.anti_pushan with running_key = false } });
  one_off "superop-OFF" (fun c -> { c with vm_runtime = { c.vm_runtime with enable_super_operators = false } });
  one_off "junk+key-OFF" (fun c -> { c with vm_runtime = { c.vm_runtime with enable_junk_instructions = false };
                                          anti_pushan = { c.anti_pushan with running_key = false } })
