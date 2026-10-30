let () =
  match Native_vm.Protection_config.from_file "samples/protection_config.multivm.json" with
  | Ok c -> Printf.printf "PARSE OK: opt=%s ephemeral_jit=%b cff=%b mba=%b\n"
              c.toolchain.opt_level c.vm_runtime.ephemeral_jit c.cff.enabled c.mba.enabled
  | Error e -> Printf.printf "PARSE FAIL: %s\n" e; exit 1
