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

  let open Cpp_codegen.Cpp_ast in
  let open Cpp_codegen.Cpp_dsl in
  let open Cpp_codegen.Cpp_printer in

  let format_table_decl name arr =
    global_var ~is_static:true ~is_const:true
      (Array (UInt32, 256))
      name
      ~init:(init_list (Array.to_list (Array.map (fun v -> u32 v) arr)))
  in

  let rotl32_fn =
    func_decl
      ~attrs:[StaticFn; InlineFn; AlwaysInline; NoExcept]
      UInt32
      "rotl32"
      [(UInt32, "x"); (UInt32, "n")]
      [
        ret ((var "x" <<~ var "n") |~ (var "x" >>~ (u32 32l -~ var "n")));
      ]
  in

  let derive_seed_fn =
    func_decl
      ~attrs:[StaticFn; InlineFn; AlwaysInline; NoExcept]
      UInt32
      "derive_seed"
      []
      [
        const_u32 "s0" (u32 s0);
        let_u32 "x0" (idx (var "T0_0") (var "s0" &~ u32 0xFFl));
        let_u32 "x1" (idx (var "T0_1") ((var "s0" >>~ u32 8l) &~ u32 0xFFl));
        let_u32 "x2" (idx (var "T0_2") ((var "s0" >>~ u32 16l) &~ u32 0xFFl));
        let_u32 "x3" (idx (var "T0_3") ((var "s0" >>~ u32 24l) &~ u32 0xFFl));

        let_u32 "y0" (call "rotl32" [var "x0"; u32 7l] ^~ var "x1");
        let_u32 "y1" (call "rotl32" [var "x1"; u32 11l] ^~ var "x2");
        let_u32 "y2" (call "rotl32" [var "x2"; u32 19l] ^~ var "x3");
        let_u32 "y3" (call "rotl32" [var "x3"; u32 23l] ^~ var "x0");

        let_u32 "z0" (idx (var "T1_0") (var "y0" &~ u32 0xFFl));
        let_u32 "z1" (idx (var "T1_1") (var "y1" &~ u32 0xFFl));
        let_u32 "z2" (idx (var "T1_2") (var "y2" &~ u32 0xFFl));
        let_u32 "z3" (idx (var "T1_3") (var "y3" &~ u32 0xFFl));

        ret (((var "z0" ^~ var "z1") ^~ var "z2") ^~ var "z3");
      ]
  in

  let asgard_wbox_derive_seed_fn =
    func_decl
      ~attrs:[StaticFn; InlineFn; AlwaysInline; NoExcept]
      UInt32
      "asgard_wbox_derive_seed"
      []
      [
        ret (call "asgard_whitebox::derive_seed" []);
      ]
  in

  render_top_decls [
    namespace_def "asgard_whitebox" [
      format_table_decl "T0_0" t0_0;
      format_table_decl "T0_1" t0_1;
      format_table_decl "T0_2" t0_2;
      format_table_decl "T0_3" t0_3;
      format_table_decl "T1_0" t1_0;
      format_table_decl "T1_1" t1_1;
      format_table_decl "T1_2" t1_2;
      format_table_decl "T1_3" t1_3;
      rotl32_fn;
      derive_seed_fn;
    ];
    asgard_wbox_derive_seed_fn;
  ]

module Runtime_policy = struct
  type t = {
    num_domains : int;
    enable_smc : bool;
    enable_smc_strict : bool;
    enable_anti_emu : bool;
    enable_mem_scan : bool;
    enable_timing_probes : bool;
    enable_nanomites : bool;
    enable_direct_syscalls : bool;
    enable_running_key : bool;
    enable_address_bound : bool;
    enable_stack_scramble : bool;
    enable_mem_sanitize : bool;
    enable_vector_isa : bool;
    enable_egraph_expansion : bool;
    enable_ephemeral_jit : bool;
  }

  let of_config ?runtime_profile (config : Protection_config.t option) : t =
    let num_domains =
      match config with
      | Some c -> max 1 c.vm_runtime.num_dispatch_domains
      | None ->
          (match runtime_profile with
           | Some (p : Random_visa_domain.Vm_runtime_profile.t) -> p.dispatch.num_domains
           | None -> 1)
    in
    {
      num_domains;
      enable_smc = (match config with Some c -> c.anti_tamper.enabled && c.anti_tamper.smc | None -> true);
      enable_smc_strict = (match config with Some c -> c.anti_tamper.enabled && c.anti_tamper.smc && c.anti_tamper.smc_strict | None -> false);
      enable_anti_emu = (match config with Some c -> c.anti_tamper.enabled && c.anti_tamper.anti_emulation | None -> true);
      enable_mem_scan = (match config with Some c -> c.anti_tamper.enabled && c.anti_tamper.memory_integrity_scanner | None -> true);
      enable_timing_probes = (match config with Some c -> c.anti_tamper.enabled && c.anti_tamper.hardware_timing_probes | None -> true);
      enable_nanomites = (match config with Some c -> c.anti_tamper.enabled && c.anti_tamper.nanomites | None -> true);
      enable_direct_syscalls = (match config with Some c -> c.anti_tamper.enabled && c.anti_tamper.direct_syscalls | None -> true);
      enable_running_key = Protection_config.rolling_key_enabled config;
      enable_address_bound = Protection_config.address_bound_enabled config;
      enable_stack_scramble = (match config with Some c -> c.vm_runtime.stack_scrambling | None -> true);
      enable_mem_sanitize = (match config with Some c -> c.vm_runtime.memory_sanitization | None -> true);
      enable_vector_isa = (match config with Some c -> c.vm_runtime.vector_isa | None -> true);
      enable_egraph_expansion = (match config with Some c -> c.vm_runtime.egraph_expansion | None -> true);
      enable_ephemeral_jit = Protection_config.ephemeral_jit_enabled config;
    }

  let to_models (p : t) : (string * Jg_types.tvalue) list =
    [
      ("num_domains", Jg_types.Tint p.num_domains);
      ("enable_smc", Jg_types.Tbool p.enable_smc);
      ("enable_smc_strict", Jg_types.Tbool p.enable_smc_strict);
      ("enable_anti_emu", Jg_types.Tbool p.enable_anti_emu);
      ("enable_mem_scan", Jg_types.Tbool p.enable_mem_scan);
      ("enable_timing_probes", Jg_types.Tbool p.enable_timing_probes);
      ("enable_nanomites", Jg_types.Tbool p.enable_nanomites);
      ("enable_direct_syscalls", Jg_types.Tbool p.enable_direct_syscalls);
      ("enable_running_key", Jg_types.Tbool p.enable_running_key);
      ("enable_address_bound", Jg_types.Tbool p.enable_address_bound);
      ("enable_stack_scramble", Jg_types.Tbool p.enable_stack_scramble);
      ("enable_mem_sanitize", Jg_types.Tbool p.enable_mem_sanitize);
      ("enable_vector_isa", Jg_types.Tbool p.enable_vector_isa);
      ("enable_egraph_expansion", Jg_types.Tbool p.enable_egraph_expansion);
      ("enable_ephemeral_jit", Jg_types.Tbool p.enable_ephemeral_jit);
    ]
end

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
  let policy = Runtime_policy.of_config ?runtime_profile config in
  let num_domains = policy.num_domains in

  let rns_header = Vm_ir.Rns.emit_cpp_rns_header () in
  let branchless_vip_header = Vm_ir.Branchless_vip.emit_branchless_vip_cpp_header () in
  let direct_syscalls_header = if policy.enable_direct_syscalls then Hardened_runtime.emit_direct_syscalls_header () else "" in
  let anti_emulation_header = if policy.enable_anti_emu then Hardened_runtime.emit_anti_emulation_probes () else "" in
  let dual_mapping_header = Hardened_runtime.emit_dual_mapping_header () in
  let smc_header = if policy.enable_smc then Hardened_runtime.emit_introspective_smc_header () else "" in
  let mem_scan_header = if policy.enable_mem_scan then Hardened_runtime.emit_memory_integrity_scanner_header () else "" in
  let nanomite_header = if policy.enable_nanomites then Hardened_runtime.emit_nanomite_engine_header () else "" in
  let ephemeral_jit_header = if policy.enable_ephemeral_jit then Hardened_runtime.emit_ephemeral_jit_header () else "" in
  let chameleon_header = Chameleon_handlers.emit_chameleon_handlers_hpp rng in

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
      let h = fnv1a name in
      let alt_name =
        if String.length name > 0 && name.[0] = '_' then
          String.sub name 1 (String.length name - 1)
        else "_" ^ name
      in
      let alt_h = fnv1a alt_name in
      let xor_key = ((Random.State.bits rng) land 0x7FFFFFFF) lxor (idx * 0x1337 + 0x5877) in
      let hex_b = Buffer.create (String.length bytes * 6) in
      for i = 0 to String.length bytes - 1 do
        let orig = Char.code bytes.[i] in
        let k = ((xor_key lsr ((i land 3) * 8)) lxor (i * 0x5D + 0x33)) land 0xFF in
        let enc_val = orig lxor k in
        Buffer.add_string hex_b (Printf.sprintf "0x%02X, " enc_val)
      done;
      Jg_types.Tobj [
        ("index", Jg_types.Tint idx);
        ("hash", Jg_types.Tstr (Printf.sprintf "0x%08lX" h));
        ("alt_hash", Jg_types.Tstr (Printf.sprintf "0x%08lX" alt_h));
        ("size", Jg_types.Tint (String.length bytes));
        ("xor_key", Jg_types.Tstr (Printf.sprintf "0x%08X" xor_key));
        ("hex_bytes", Jg_types.Tstr (Buffer.contents hex_b));
      ]
    ) constants
  in

  let ctx_buf = Buffer.create 2048 in
  Vm_context_emitter.emit_context_hpp ctx_buf ~key_seed ~reg_perm ~stride ~offset
    ~enable_running_key:policy.enable_running_key
    ~enable_stack_scramble:policy.enable_stack_scramble
    ~enable_mem_sanitize:policy.enable_mem_sanitize;
  let context_source = Buffer.contents ctx_buf in

  let domain_salts =
    let used = Hashtbl.create num_domains in
    Hashtbl.replace used 0 ();
    Array.init num_domains (fun d ->
      if d = 0 then 0
      else
        let rec pick () =
          let s = (Random.State.int rng 255) + 1 in
          if Hashtbl.mem used s then pick ()
          else (Hashtbl.replace used s (); s)
        in
        pick ()
    )
  in

  let dispatch_domain_models =
    List.init num_domains (fun d ->
      let salt = domain_salts.(d) in
      let handlers =
        List.init 256 (fun i ->
          let raw_opcode = i lxor salt in
          let h = opcode_to_handler.(raw_opcode) in
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
    ~enable_running_key:policy.enable_running_key
    ~enable_address_bound:policy.enable_address_bound
    ~enable_timing_probes:policy.enable_timing_probes
    ~enable_nanomites:policy.enable_nanomites
    ~enable_egraph_expansion:policy.enable_egraph_expansion
    ~enable_ephemeral_jit:policy.enable_ephemeral_jit
    ~num_domains ();
  let handlers_source = Buffer.contents handlers_buf in
  let wbox_seed_source = generate_wbox_seed_derivation ~rng key_seed in

  let models : (string * Jg_types.tvalue) list =
    Runtime_policy.to_models policy @ [
      ("rns_header", Jg_types.Tstr rns_header);
      ("branchless_vip_header", Jg_types.Tstr branchless_vip_header);
      ("chameleon_header", Jg_types.Tstr chameleon_header);
      ("direct_syscalls_header", Jg_types.Tstr direct_syscalls_header);
      ("anti_emulation_header", Jg_types.Tstr anti_emulation_header);
      ("dual_mapping_header", Jg_types.Tstr dual_mapping_header);
      ("smc_header", Jg_types.Tstr smc_header);
      ("mem_scan_header", Jg_types.Tstr mem_scan_header);
      ("nanomite_header", Jg_types.Tstr nanomite_header);
      ("ephemeral_jit_header", Jg_types.Tstr ephemeral_jit_header);
      ("has_gpu_constants", Jg_types.Tbool has_gpu_constants);
      ("gpu_constants", Jg_types.Tstr gpu_constants);
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
      ("dispatch_domains", Jg_types.Tlist dispatch_domain_models);
      ("domain_salts", Jg_types.Tlist (Array.to_list (Array.map (fun s -> Jg_types.Tint s) domain_salts)));
      ("handlers_source", Jg_types.Tstr handlers_source);
    ]
  in
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
