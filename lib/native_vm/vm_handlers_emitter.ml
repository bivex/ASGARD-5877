let split_rng rng tag =
  let s = Random.State.int rng 0x3FFFFFFF in
  Random.State.make [| s; tag; 0x5877CAFE |]

let emit_handlers_hpp b ~rng ~enable_running_key ~enable_address_bound ~enable_timing_probes ~enable_nanomites ~enable_egraph_expansion ?(enable_ephemeral_jit = false) () =
  Vm_alu_handlers.emit_probes b ~enable_timing_probes;
  Vm_alu_handlers.emit_alu_handlers b ~rng:(split_rng rng 101) ~enable_egraph_expansion ~enable_ephemeral_jit ();
  Vm_control_handlers.emit_control_handlers b ~rng:(split_rng rng 102) ~enable_nanomites ~enable_running_key ~enable_address_bound ();
  Vm_control_handlers.emit_super_operators ~rng:(split_rng rng 103) b;
  Vm_mem_handlers.emit_simd_handlers b;
  Vm_mem_handlers.emit_mem_and_ffi_handlers ~rng:(split_rng rng 104) b;
  Vm_mem_handlers.emit_decoy_handlers ~rng:(split_rng rng 105) b

