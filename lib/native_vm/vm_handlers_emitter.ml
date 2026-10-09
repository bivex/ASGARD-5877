let split_rng rng tag =
  let s = Random.State.int rng 0x3FFFFFFF in
  Random.State.make [| s; tag; 0x5877CAFE |]

let transform_domain_labels src domain_idx =
  let lines = String.split_on_char '\n' src in
  let buf = Buffer.create (String.length src + 1024) in
  List.iter (fun line ->
    if String.starts_with ~prefix:"    H_RET: case_ret:" line then
      let rest = String.sub line 20 (String.length line - 20) in
      Buffer.add_string buf (Printf.sprintf "    H_RET_D%d:%s\n" domain_idx rest)
    else if String.starts_with ~prefix:"    H_" line then
      match String.index_opt line ':' with
      | Some colon_idx ->
          let label = String.sub line 4 (colon_idx - 4) in
          let rest = String.sub line colon_idx (String.length line - colon_idx) in
          Buffer.add_string buf (Printf.sprintf "    %s_D%d%s\n" label domain_idx rest)
      | None ->
          Buffer.add_string buf line;
          Buffer.add_char buf '\n'
    else begin
      Buffer.add_string buf line;
      Buffer.add_char buf '\n'
    end
  ) lines;
  Buffer.contents buf

let emit_handlers_hpp b ~rng ~enable_running_key ~enable_address_bound ~enable_timing_probes ~enable_nanomites ~enable_egraph_expansion ?(enable_ephemeral_jit = false) ?(num_domains = 1) () =
  Vm_alu_handlers.emit_probes b ~enable_timing_probes;
  Vm_alu_handlers.emit_alu_handlers b ~rng:(split_rng rng 101) ~enable_egraph_expansion ~enable_ephemeral_jit ();
  Vm_control_handlers.emit_control_handlers b ~rng:(split_rng rng 102) ~enable_nanomites ~enable_running_key ~enable_address_bound ();
  Vm_control_handlers.emit_super_operators ~rng:(split_rng rng 103) b;
  Vm_mem_handlers.emit_simd_handlers ~rng:(split_rng rng 106) b;
  Vm_mem_handlers.emit_mem_and_ffi_handlers ~rng:(split_rng rng 104) b;
  Vm_mem_handlers.emit_decoy_handlers ~rng:(split_rng rng 105) b;
  let max_extra_domains = min 2 (max 0 (num_domains - 1)) in
  for d = 1 to max_extra_domains do
    let b_d = Buffer.create 4096 in
    Vm_alu_handlers.emit_alu_handlers b_d ~rng:(split_rng rng (201 + d * 10)) ~enable_egraph_expansion ~enable_ephemeral_jit ();
    Vm_control_handlers.emit_control_handlers b_d ~rng:(split_rng rng (202 + d * 10)) ~enable_nanomites ~enable_running_key ~enable_address_bound ();
    Vm_control_handlers.emit_super_operators ~rng:(split_rng rng (203 + d * 10)) b_d;
    Vm_mem_handlers.emit_simd_handlers ~rng:(split_rng rng (206 + d * 10)) b_d;
    Vm_mem_handlers.emit_mem_and_ffi_handlers ~rng:(split_rng rng (204 + d * 10)) b_d;
    let transformed = transform_domain_labels (Buffer.contents b_d) d in
    Buffer.add_string b transformed
  done

