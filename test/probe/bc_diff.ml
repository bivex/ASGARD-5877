open Multi_vm
let dump ~label (cfg : Native_vm.Protection_config.t) =
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
  | Error _ -> prerr_endline "lift fail"
  | Ok func ->
      let rng = Random.State.make [| 5 |] in
      let pkg = Multi_vm_emitter.compile_and_package ~rng ~enable_cff:false
        ~enable_mba:true ~mba_depth:cfg.mba.depth ~config:cfg func in
      let oc = open_out (Printf.sprintf "/tmp/bc_%s.txt" label) in
      List.iter (fun w -> output_string oc (Printf.sprintf "%016LX\n" w)) pkg.bytecode;
      close_out oc;
      Printf.printf "%s: %d words\n" label (List.length pkg.bytecode)

let () =
  let open Native_vm.Protection_config in
  let bare cfg = { cfg with
    vm_runtime = { cfg.vm_runtime with enable_super_operators = false; enable_junk_instructions = false;
                                       chameleon_handlers = false; num_dispatch_domains = 1;
                                       egraph_expansion = false; stack_scrambling = false;
                                       oblivious_memory = false; memory_sanitization = false; ephemeral_jit = false };
    anti_pushan = { cfg.anti_pushan with running_key = false; address_bound = false };
    mba = { cfg.mba with enabled = true } } in
  let b = bare default in
  dump ~label:"nojunk" b;
  dump ~label:"junk" { b with vm_runtime = { b.vm_runtime with enable_junk_instructions = true } }
