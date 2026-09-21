open Cmdliner

(* ROOT CLI GROUP *)
let main_cmd =
  let doc = "Random Vector ISA Synthesizer, Formal Sail Exporter, and VM-Protector in OCaml" in
  let info = Cmd.info "random_visa" ~version:"0.2.0" ~doc in
  Cmd.group info [
    Cli_isa.generate_cmd;
    Cli_isa.parse_cmd;
    Cli_isa.assemble_cmd;
    Cli_isa.disassemble_cmd;
    Cli_isa.cost_cmd;
    Cli_vanguard.vanguard_cmd;
    Cli_protect.protect_cmd;
    Cli_protect_arm64.protect_arm64_cmd;
    Cli_protect.c_obf_cmd;
    Cli_project.project_cmd;
    Cli_protect.init_config_cmd;
  ]

let () = exit (Cmd.eval main_cmd)
