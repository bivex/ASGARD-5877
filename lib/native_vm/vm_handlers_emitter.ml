let emit_handlers_hpp b ~rng ~enable_running_key ~enable_address_bound ~enable_timing_probes ~enable_nanomites ~enable_egraph_expansion =
  Vm_alu_handlers.emit_probes b ~enable_timing_probes;
  Vm_alu_handlers.emit_alu_handlers b ~rng ~enable_egraph_expansion;
  Vm_control_handlers.emit_control_handlers b ~enable_nanomites ~enable_running_key ~enable_address_bound ();
  Vm_control_handlers.emit_super_operators b;
  Vm_mem_handlers.emit_simd_handlers b;
  Vm_mem_handlers.emit_mem_and_ffi_handlers b;
  Vm_mem_handlers.emit_decoy_handlers b
