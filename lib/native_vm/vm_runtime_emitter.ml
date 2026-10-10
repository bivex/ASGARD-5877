open Jingoo

let generate_wbox_seed_derivation ~rng (key_seed : int32) : string =
  let rotl32 x n =
    let n = n land 31 in
    Int32.logor (Int32.shift_left x n) (Int32.shift_right_logical x (32 - n))
  in
  let rand32 () =
    Int32.logxor (Random.State.int32 rng Int32.max_int)
      (Int32.shift_left (Random.State.int32 rng 2l) 31)
  in
  let s0 = rand32 () in

  let t0_0 = Array.init 256 (fun _ -> rand32 ()) in
  let t0_1 = Array.init 256 (fun _ -> rand32 ()) in
  let t0_2 = Array.init 256 (fun _ -> rand32 ()) in
  let t0_3 = Array.init 256 (fun _ -> rand32 ()) in

  let b0 = Int32.to_int (Int32.logand s0 0xFFl) in
  let b1 = Int32.to_int (Int32.logand (Int32.shift_right_logical s0 8) 0xFFl) in
  let b2 = Int32.to_int (Int32.logand (Int32.shift_right_logical s0 16) 0xFFl) in
  let b3 = Int32.to_int (Int32.logand (Int32.shift_right_logical s0 24) 0xFFl) in

  let x0 = t0_0.(b0) in
  let x1 = t0_1.(b1) in
  let x2 = t0_2.(b2) in
  let x3 = t0_3.(b3) in

  let y0 = Int32.logxor (rotl32 x0 7) x1 in
  let y1 = Int32.logxor (rotl32 x1 11) x2 in
  let y2 = Int32.logxor (rotl32 x2 19) x3 in
  let y3 = Int32.logxor (rotl32 x3 23) x0 in

  let t1_0 = Array.init 256 (fun _ -> rand32 ()) in
  let t1_1 = Array.init 256 (fun _ -> rand32 ()) in
  let t1_2 = Array.init 256 (fun _ -> rand32 ()) in
  let t1_3 = Array.init 256 (fun _ -> rand32 ()) in

  let k0 = Int32.to_int (Int32.logand y0 0xFFl) in
  let k1 = Int32.to_int (Int32.logand y1 0xFFl) in
  let k2 = Int32.to_int (Int32.logand y2 0xFFl) in
  let k3 = Int32.to_int (Int32.logand y3 0xFFl) in

  let required_t1_3_k3 =
    Int32.logxor key_seed (Int32.logxor t1_0.(k0) (Int32.logxor t1_1.(k1) t1_2.(k2)))
  in
  t1_3.(k3) <- required_t1_3_k3;

  let format_table name arr =
    let b = Buffer.create 2048 in
    Buffer.add_string b (Printf.sprintf "static const uint32_t %s[256] = {\n" name);
    Array.iteri (fun i v ->
      if i mod 8 = 0 then Buffer.add_string b "    ";
      Buffer.add_string b (Printf.sprintf "0x%08lXU" v);
      if i < 255 then Buffer.add_string b ", ";
      if i mod 8 = 7 then Buffer.add_string b "\n";
    ) arr;
    Buffer.add_string b "};\n\n";
    Buffer.contents b
  in

  let b = Buffer.create 8192 in
  Buffer.add_string b "namespace asgard_whitebox {\n\n";
  Buffer.add_string b (format_table "T0_0" t0_0);
  Buffer.add_string b (format_table "T0_1" t0_1);
  Buffer.add_string b (format_table "T0_2" t0_2);
  Buffer.add_string b (format_table "T0_3" t0_3);
  Buffer.add_string b (format_table "T1_0" t1_0);
  Buffer.add_string b (format_table "T1_1" t1_1);
  Buffer.add_string b (format_table "T1_2" t1_2);
  Buffer.add_string b (format_table "T1_3" t1_3);
  Buffer.add_string b {|static inline __attribute__((always_inline)) uint32_t rotl32(uint32_t x, uint32_t n) noexcept {
    return (x << n) | (x >> (32 - n));
}

static inline __attribute__((always_inline)) uint32_t derive_seed() noexcept {
|};
  Buffer.add_string b (Printf.sprintf "    const uint32_t s0 = 0x%08lXU;\n" s0);
  Buffer.add_string b {|    uint32_t x0 = T0_0[s0 & 0xFF];
    uint32_t x1 = T0_1[(s0 >> 8) & 0xFF];
    uint32_t x2 = T0_2[(s0 >> 16) & 0xFF];
    uint32_t x3 = T0_3[(s0 >> 24) & 0xFF];

    uint32_t y0 = rotl32(x0, 7) ^ x1;
    uint32_t y1 = rotl32(x1, 11) ^ x2;
    uint32_t y2 = rotl32(x2, 19) ^ x3;
    uint32_t y3 = rotl32(x3, 23) ^ x0;

    uint32_t z0 = T1_0[y0 & 0xFF];
    uint32_t z1 = T1_1[y1 & 0xFF];
    uint32_t z2 = T1_2[y2 & 0xFF];
    uint32_t z3 = T1_3[y3 & 0xFF];

    return z0 ^ z1 ^ z2 ^ z3;
}

} // namespace asgard_whitebox

static inline __attribute__((always_inline)) uint32_t asgard_wbox_derive_seed() noexcept {
    return asgard_whitebox::derive_seed();
}
|};
  Buffer.contents b

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

  let fnv1a s =
    let h = ref 0x811c9dc5l in
    for i = 0 to String.length s - 1 do
      h := Int32.logxor !h (Int32.of_int (Char.code s.[i]));
      h := Int32.mul !h 0x01000193l
    done;
    !h
  in
  let ext_sym_models =
    List.map (fun sym ->
      let h = fnv1a sym in
      let alt_sym =
        if String.length sym > 0 && sym.[0] = '_' then
          String.sub sym 1 (String.length sym - 1)
        else "_" ^ sym
      in
      let alt_h = fnv1a alt_sym in
      let len = String.length sym in
      let enc_bytes =
        List.init len (fun i ->
          let k = (0x5A lxor ((i * 17 + 0x33) land 0xFF)) in
          Printf.sprintf "0x%02X" (Char.code sym.[i] lxor k)
        )
      in
      let enc_bytes_str =
        if enc_bytes = [] then "0x00"
        else String.concat ", " enc_bytes
      in
      Jg_types.Tobj [
        ("hash", Jg_types.Tstr (Printf.sprintf "0x%08lX" h));
        ("alt_hash", Jg_types.Tstr (Printf.sprintf "0x%08lX" alt_h));
        ("len", Jg_types.Tint len);
        ("enc_bytes", Jg_types.Tstr enc_bytes_str);
      ]
    ) external_symbols
  in

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
  let wbox_seed_source = generate_wbox_seed_derivation ~rng key_seed in

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
    ("wbox_seed_source", Jg_types.Tstr wbox_seed_source);
    ("context_source", Jg_types.Tstr context_source);
    ("key_seed_hex", Jg_types.Tstr (Printf.sprintf "0x%08lXU" key_seed));
    ("expected_hash_hex", Jg_types.Tstr (Printf.sprintf "0x%016LXULL" expected_hash));
    ("poly_multiplier_hex", Jg_types.Tstr (Printf.sprintf "0x%016LXULL" (Vm_ir.Rolling_key.poly_multiplier_of_seed key_seed)));
    ("poly_init_hex", Jg_types.Tstr (Printf.sprintf "0x%016LXULL" (Vm_ir.Rolling_key.poly_init_of_seed key_seed)));
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
