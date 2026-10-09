open Jingoo

let emit_cpp_threaded_header
    ~rng
    ~key_seed
    ~reg_perm
    ~expected_hash
    ?expected_hashes
    ?(runtime_profile : Random_visa_domain.Vm_runtime_profile.t option)
    ?(config : Protection_config.t option)
    ?(external_symbols = [])
    ?(constants = [])
    ?(block_spans = [])
    ?gpu_matrix
    opcode_to_handler =

  let profile = match runtime_profile with
    | Some p -> p
    | None -> Random_visa_domain.Vm_runtime_profile.generate ~seed:(Int64.of_int32 key_seed) ~total_opcodes:256 ()
  in
  let stride = profile.dispatch.context_layout.affine_a in
  let offset = profile.dispatch.context_layout.affine_b in
  let num_domains =
    match config with
    | Some c -> max 1 c.vm_runtime.num_dispatch_domains
    | None -> profile.dispatch.num_domains
  in
  let enable_smc = match config with Some c -> c.anti_tamper.enabled && c.anti_tamper.smc | None -> true in
  let enable_smc_strict = match config with Some c -> c.anti_tamper.enabled && c.anti_tamper.smc && c.anti_tamper.smc_strict | None -> false in
  let enable_anti_emu = match config with Some c -> c.anti_tamper.enabled && c.anti_tamper.anti_emulation | None -> true in
  let enable_mem_scan = match config with Some c -> c.anti_tamper.enabled && c.anti_tamper.memory_integrity_scanner | None -> true in
  let enable_timing_probes = match config with Some c -> c.anti_tamper.enabled && c.anti_tamper.hardware_timing_probes | None -> true in
  let enable_nanomites = match config with Some c -> c.anti_tamper.enabled && c.anti_tamper.nanomites | None -> true in
  let enable_direct_syscalls = match config with Some c -> c.anti_tamper.enabled && c.anti_tamper.direct_syscalls | None -> true in
  let enable_running_key = Protection_config.rolling_key_enabled config in
  let enable_address_bound = Protection_config.address_bound_enabled config in
  let enable_stack_scramble = match config with Some c -> c.vm_runtime.stack_scrambling | None -> true in
  let enable_mem_sanitize = match config with Some c -> c.vm_runtime.memory_sanitization | None -> true in
  let enable_vector_isa = match config with Some c -> c.vm_runtime.vector_isa | None -> true in
  let enable_egraph_expansion = match config with Some c -> c.vm_runtime.egraph_expansion | None -> true in
  let enable_ephemeral_jit = Protection_config.ephemeral_jit_enabled config in

  let rns_header = Vm_ir.Rns.emit_cpp_rns_header () in
  let direct_syscalls_header = if enable_direct_syscalls then Hardened_runtime.emit_direct_syscalls_header () else "" in
  let anti_emulation_header = if enable_anti_emu then Hardened_runtime.emit_anti_emulation_probes () else "" in
  let dual_mapping_header = Hardened_runtime.emit_dual_mapping_header () in
  let smc_header = if enable_smc then Hardened_runtime.emit_introspective_smc_header () else "" in
  let mem_scan_header = if enable_mem_scan then Hardened_runtime.emit_memory_integrity_scanner_header () else "" in
  let nanomite_header = if enable_nanomites then Hardened_runtime.emit_nanomite_engine_header () else "" in
  let ephemeral_jit_header = if enable_ephemeral_jit then Hardened_runtime.emit_ephemeral_jit_header () else "" in

  let (has_gpu_constants, gpu_constants) = match gpu_matrix with
    | Some mat -> (true, Gpu_synth.Gpu_matrix.emit_cpp_constants mat)
    | None -> (false, "")
  in

  let block_spans_models =
    List.map (fun (off, len) ->
      Jg_types.Tobj [
        ("off", Jg_types.Tint off);
        ("len", Jg_types.Tint len);
      ]
    ) block_spans
  in

  let ext_sym_models = List.map (fun s -> Jg_types.Tstr (String.escaped s)) external_symbols in

  let constants_models =
    List.mapi (fun idx (name, bytes) ->
      let hex_b = Buffer.create (String.length bytes * 6) in
      for i = 0 to String.length bytes - 1 do
        Buffer.add_string hex_b (Printf.sprintf "0x%02X, " (Char.code bytes.[i]))
      done;
      Jg_types.Tobj [
        ("index", Jg_types.Tint idx);
        ("escaped_name", Jg_types.Tstr (String.escaped name));
        ("size", Jg_types.Tint (String.length bytes));
        ("hex_bytes", Jg_types.Tstr (Buffer.contents hex_b));
      ]
    ) constants
  in

  let ctx_buf = Buffer.create 2048 in
  Vm_context_emitter.emit_context_hpp ctx_buf ~key_seed ~reg_perm ~stride ~offset
    ~enable_running_key ~enable_stack_scramble ~enable_mem_sanitize;
  let context_source = Buffer.contents ctx_buf in

  let dispatch_domain_models =
    List.init num_domains (fun d ->
      let handlers =
        List.init 256 (fun i ->
          let h = opcode_to_handler.(i) in
          let h =
            if String.starts_with ~prefix:"H_DECOY_" h then
              let base_idx =
                try int_of_string (String.sub h 8 (String.length h - 8))
                with _ -> 0
              in
              let diversified = (base_idx + (d * 7) + (i * 3)) mod 16 in
              Printf.sprintf "H_DECOY_%d" diversified
            else if d = 0 then h
            else Printf.sprintf "%s_D%d" h ((d - 1) mod 2 + 1)
          in
          Jg_types.Tstr h)
      in
      Jg_types.Tobj [
        ("index", Jg_types.Tint d);
        ("handlers", Jg_types.Tlist handlers);
      ]
    )
  in

  let handlers_buf = Buffer.create 4096 in
  Vm_handlers_emitter.emit_handlers_hpp handlers_buf ~rng
    ~enable_running_key ~enable_address_bound ~enable_timing_probes
    ~enable_nanomites ~enable_egraph_expansion ~enable_ephemeral_jit
    ~num_domains ();
  let handlers_source = Buffer.contents handlers_buf in

  let models : (string * Jg_types.tvalue) list = [
    ("enable_vector_isa", Jg_types.Tbool enable_vector_isa);
    ("rns_header", Jg_types.Tstr rns_header);
    ("enable_direct_syscalls", Jg_types.Tbool enable_direct_syscalls);
    ("direct_syscalls_header", Jg_types.Tstr direct_syscalls_header);
    ("enable_anti_emu", Jg_types.Tbool enable_anti_emu);
    ("anti_emulation_header", Jg_types.Tstr anti_emulation_header);
    ("dual_mapping_header", Jg_types.Tstr dual_mapping_header);
    ("enable_smc", Jg_types.Tbool enable_smc);
    ("enable_smc_strict", Jg_types.Tbool enable_smc_strict);
    ("smc_header", Jg_types.Tstr smc_header);
    ("enable_mem_scan", Jg_types.Tbool enable_mem_scan);
    ("mem_scan_header", Jg_types.Tstr mem_scan_header);
    ("enable_nanomites", Jg_types.Tbool enable_nanomites);
    ("nanomite_header", Jg_types.Tstr nanomite_header);
    ("enable_ephemeral_jit", Jg_types.Tbool enable_ephemeral_jit);
    ("ephemeral_jit_header", Jg_types.Tstr ephemeral_jit_header);
    ("has_gpu_constants", Jg_types.Tbool has_gpu_constants);
    ("gpu_constants", Jg_types.Tstr gpu_constants);
    ("enable_address_bound", Jg_types.Tbool enable_address_bound);
    ("num_blocks", Jg_types.Tint (List.length block_spans));
    ("block_spans", Jg_types.Tlist block_spans_models);
    ("has_external_symbols", Jg_types.Tbool (external_symbols <> []));
    ("external_symbols", Jg_types.Tlist ext_sym_models);
    ("has_constants", Jg_types.Tbool (constants <> []));
    ("constants", Jg_types.Tlist constants_models);
    ("context_source", Jg_types.Tstr context_source);
    ("key_seed_hex", Jg_types.Tstr (Printf.sprintf "0x%08lXU" key_seed));
    ("expected_hash_hex", Jg_types.Tstr (Printf.sprintf "0x%016LXULL" expected_hash));
    ("has_multi_hashes", Jg_types.Tbool (match expected_hashes with Some hl when List.length hl > 1 -> true | _ -> false));
    ("expected_hashes", Jg_types.Tlist (match expected_hashes with Some hl when List.length hl > 1 -> List.map (fun h -> Jg_types.Tstr (Printf.sprintf "0x%016LXULL" h)) hl | _ -> []));
    ("enable_mem_sanitize", Jg_types.Tbool enable_mem_sanitize);
    ("dispatch_domains", Jg_types.Tlist dispatch_domain_models);
    ("num_domains", Jg_types.Tint num_domains);
    ("enable_running_key", Jg_types.Tbool enable_running_key);
    ("handlers_source", Jg_types.Tstr handlers_source);
  ] in
  Native_vm_templates.render Native_vm_templates.threaded_header_template models

let emit_runner_cpp ?(key_seed = 0x5877CAFEL) ~reg_perm bytecode =
  let _ = key_seed in
  let _ = reg_perm in
  let bytecode_words =
    List.map (fun w -> Jg_types.Tstr (Printf.sprintf "0x%016LXULL" w)) bytecode
  in
  let models = [
    ("bytecode_words", Jg_types.Tlist bytecode_words);
  ] in
  Native_vm_templates.render Native_vm_templates.runner_template models
