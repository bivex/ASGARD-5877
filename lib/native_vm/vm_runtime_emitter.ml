open Random_visa_constants.Magic_numbers
let generate_wbox_seed_derivation_decls ~rng (key_seed : int32) : Cpp_codegen.Cpp_ast.top_decl list =
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

  [
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

let generate_wbox_seed_derivation ~rng (key_seed : int32) : string =
  Cpp_codegen.Cpp_printer.render_top_decls (generate_wbox_seed_derivation_decls ~rng key_seed)

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
    enable_oblivious_mem : bool;
    context_epochs : int;
    oblivious_decoys : int;
  }

  let of_config ?runtime_profile (config : Protection_config.t option) : t =
    let num_domains =
      match config with
      | Some c -> max 1 c.vm_runtime.num_dispatch_domains
      | None ->
          (match runtime_profile with
           | Some (p : Random_visa_domain.Vm_runtime_profile.t) -> p.dispatch.num_domains
           | None -> 4)
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
      enable_oblivious_mem = Protection_config.oblivious_memory_enabled config;
      context_epochs = (match config with Some c -> max 1 c.vm_runtime.context_epochs | None -> 4);
      oblivious_decoys = (match config with Some c -> max 0 c.vm_runtime.oblivious_decoys | None -> 3);
    }
end

let calc_fnv1a32 (s : string) : int32 =
  let h = ref (Int64.to_int32 fnv1a_32_offset_basis) in
  for i = 0 to String.length s - 1 do
    Stdlib.(h := Int32.logxor !h (Int32.of_int (Char.code s.[i])));
    Stdlib.(h := Int32.mul !h 0x01000193l)
  done;
  !h

let emit_external_symbols_table_ast external_symbols : Cpp_codegen.Cpp_ast.top_decl =
  let open Cpp_codegen.Cpp_ast in
  let open Cpp_codegen.Cpp_dsl in
  let entries =
    if external_symbols = [] then
      [ init_list [ u32 0l; u32 0l; i32 0; init_list [ i32 0 ] ] ]
    else
      List.map (fun sym ->
        let h = calc_fnv1a32 sym in
        let alt_sym =
          if String.length sym > 0 && sym.[0] = '_' then
            String.sub sym 1 (String.length sym - 1)
          else "_" ^ sym
        in
        let alt_h = calc_fnv1a32 alt_sym in
        let len = String.length sym in
        let enc_bytes =
          List.init len (fun i ->
            let k = (0x5A lxor ((i * 17 + 0x33) land 0xFF)) in
            u8 (Char.code sym.[i] lxor k)
          )
        in
        let enc_list = if enc_bytes = [] then [ u8 0 ] else enc_bytes in
        init_list [ u32 h; u32 alt_h; i32 len; init_list enc_list ]
      ) external_symbols
  in
  global_var ~is_static:true ~is_const:true
    (Array (StructType "asgard_ext_sym_t", 0))
    "g_external_symbols"
    ~init:(init_list entries)

let emit_constants_tables_ast ~rng constants : Cpp_codegen.Cpp_ast.top_decl list =
  let open Cpp_codegen.Cpp_ast in
  let open Cpp_codegen.Cpp_dsl in
  if constants = [] then
    [
      global_var ~is_static:true
        (Array (StructType "AsgardConstantEntry", 0))
        "g_asgard_constants"
        ~init:(init_list [ init_list [ u32 0l; u32 0l; nullptr; nullptr; u64 0L; u32 0l; i32 1 ] ])
    ]
  else
    let cdata_decls =
      List.concat_map (fun (idx, (_name, bytes)) ->
        let xor_key = ((Random.State.bits rng) land 0x7FFFFFFF) lxor (idx * 0x1337 + 0x5877) in
        let enc_bytes =
          List.init (String.length bytes) (fun i ->
            let orig = Char.code bytes.[i] in
            let k = ((xor_key lsr ((i land 3) * 8)) lxor (i * 0x5D + 0x33)) land 0xFF in
            u8 (orig lxor k)
          ) @ [ u8 0 ]
        in
        let enc_decl =
          global_var ~align_as:16 ~is_static:true ~is_const:true
            (Array (UInt8, 0))
            (Printf.sprintf "cdata_enc_%d" idx)
            ~init:(init_list enc_bytes)
        in
        let dec_decl =
          global_var ~align_as:16 ~is_static:true
            (Array (UInt8, String.length bytes + 1))
            (Printf.sprintf "cdata_dec_%d" idx)
        in
        [ enc_decl; dec_decl ]
      ) (List.mapi (fun i c -> (i, c)) constants)
    in
    let table_entries =
      List.mapi (fun idx (name, bytes) ->
        let h = calc_fnv1a32 name in
        let alt_name =
          if String.length name > 0 && name.[0] = '_' then
            String.sub name 1 (String.length name - 1)
          else "_" ^ name
        in
        let alt_h = calc_fnv1a32 alt_name in
        let xor_key = ((Random.State.bits rng) land 0x7FFFFFFF) lxor (idx * 0x1337 + 0x5877) in
        init_list [
          u32 h;
          u32 alt_h;
          var (Printf.sprintf "cdata_enc_%d" idx);
          var (Printf.sprintf "cdata_dec_%d" idx);
          u64 (Int64.of_int (String.length bytes));
          u32 (Int32.of_int xor_key);
          i32 0;
        ]
      ) constants
    in
    let table_decl =
      global_var ~is_static:true
        (Array (StructType "AsgardConstantEntry", 0))
        "g_asgard_constants"
        ~init:(init_list table_entries)
    in
    cdata_decls @ [ table_decl ]

let emit_block_spans_tables_ast (block_spans : (int * int) list) : Cpp_codegen.Cpp_ast.top_decl list =
  let open Cpp_codegen.Cpp_ast in
  let open Cpp_codegen.Cpp_dsl in
  if block_spans = [] then []
  else
    let num_blocks_decl =
      global_var ~is_static:true ~is_const:true SizeT "g_num_blocks"
        ~init:(i32 (List.length block_spans))
    in
    let offsets_decl =
      global_var ~is_static:true ~is_const:true
        (Array (SizeT, 0)) "g_block_offsets"
        ~init:(init_list (List.map (fun (off, _) -> i32 off) block_spans))
    in
    let lengths_decl =
      global_var ~is_static:true ~is_const:true
        (Array (SizeT, 0)) "g_block_lengths"
        ~init:(init_list (List.map (fun (_, len) -> i32 len) block_spans))
    in
    [
      macro_def ~value:(i32 1) "ASGARD_ADDRESS_BOUND_BYTECODE";
      num_blocks_decl;
      offsets_decl;
      lengths_decl;
    ]

let emit_native_domain_salt_ast (domain_salts : int array) : Cpp_codegen.Cpp_ast.stmt =
  let open Cpp_codegen.Cpp_ast in
  let open Cpp_codegen.Cpp_dsl in
  let num_domains = Array.length domain_salts in
  let exprs = List.map (fun s -> u8 s) (Array.to_list domain_salts) in
  decl_var ~is_static:true ~is_const:true
    (Array (UInt8, num_domains))
    "domain_salt"
    ~init:(init_list exprs)

let emit_native_dispatch_domains_stmts (dispatch_domains : (int * string list) list) : Cpp_codegen.Cpp_ast.stmt list =
  let open Cpp_codegen.Cpp_ast in
  let open Cpp_codegen.Cpp_dsl in
  let num_domains = List.length dispatch_domains in
  let raw_domains =
    List.map (fun (domain_idx, handlers) ->
      let label_exprs = List.map (fun h -> label_addr h) handlers in
      decl_var ~is_static:true
        (Array (Ptr Void, 256))
        (Printf.sprintf "raw_domain%d" domain_idx)
        ~init:(init_list label_exprs)
    ) dispatch_domains
  in
  let raw_all_init =
    init_list (List.map (fun (d_idx, _) -> var (Printf.sprintf "raw_domain%d" d_idx)) dispatch_domains)
  in
  let raw_all_decl =
    decl_var ~is_static:true
      (Array (Ptr (Ptr Void), num_domains))
      "raw_all_domains"
      ~init:raw_all_init
  in
  raw_domains @ [ raw_all_decl ]

let emit_native_msvc_switch_cases_source (dispatch_domains : (int * string list) list) : string =
  let buf = Buffer.create 2048 in
  List.iter (fun (d_idx, handlers) ->
    List.iteri (fun slot_idx h ->
      Buffer.add_string buf (Printf.sprintf "        case (%d * 256 + %d): goto %s;\n" d_idx slot_idx h)
    ) handlers
  ) dispatch_domains;
  Buffer.contents buf

let emit_native_valid_hashes_ast (hashes : int64 list) : Cpp_codegen.Cpp_ast.stmt =
  let open Cpp_codegen.Cpp_ast in
  let open Cpp_codegen.Cpp_dsl in
  let exprs = List.map u64 hashes in
  decl_var ~is_static:true ~is_const:true
    (Array (UInt64, List.length hashes))
    "valid_hashes"
    ~init:(init_list exprs)

let emit_native_runtime_hpp_decls
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
    opcode_to_handler : Cpp_codegen.Cpp_ast.top_decl list =

  let profile = match runtime_profile with
    | Some p -> p
    | None -> Random_visa_domain.Vm_runtime_profile.generate ~seed:(Int64.of_int32 key_seed) ~total_opcodes:256 ()
  in
  let stride = profile.dispatch.context_layout.affine_a in
  let offset = profile.dispatch.context_layout.affine_b in
  let policy = Runtime_policy.of_config ?runtime_profile config in
  let num_domains = policy.num_domains in
  let word_layout = Vm_ir.Rolling_key.layout_of_seed key_seed in

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
  let oblivious_mem_header = if policy.enable_oblivious_mem then Oblivious_mem.emit_oblivious_mem_hpp rng else "" in

  let (has_gpu_constants, gpu_constants) = match gpu_matrix with
    | Some mat -> (true, Gpu_synth.Gpu_matrix.emit_cpp_constants mat)
    | None -> (false, "")
  in

  let domain_salts =
    Domain_salt_optimizer.optimize_domain_salts ~rng ~num_domains ()
  in

  let raw_dispatch_domains =
    List.init num_domains (fun d ->
      let salt = domain_salts.(d) in
      let handlers =
        List.init 256 (fun i ->
          let raw_opcode = i lxor salt in
          let h = opcode_to_handler.(raw_opcode) in
          if String.starts_with ~prefix:"H_DECOY_" h then
            let base_idx =
              try int_of_string (String.sub h 8 (String.length h - 8))
              with _ -> 0
            in
            let diversified = (base_idx + (d * 7) + (i * 3)) mod 16 in
            Printf.sprintf "H_DECOY_%d" diversified
          else if d = 0 then h
          else Printf.sprintf "%s_D%d" h d
        )
      in
      (d, handlers)
    )
  in
  let msvc_switch_cases_source =
    emit_native_msvc_switch_cases_source raw_dispatch_domains
  in

  (* --- ASG_VM_TRACE: handler classes canonical across builds ---------------
     The nn_metamorph trace bench needs a token stream that is comparable
     between builds: raw opcode bytes are re-randomized per seed, so we map
     every slot to the *semantic* handler class (name with decoy index and
     domain suffix stripped). ASG_VM_TRACE=1 at runtime makes the VM emit
     one "%u" line per dispatched handler plus "# B"/"# E" invocation
     markers to stderr. *)
  let canonical_handler_name (h : string) : string =
    let h =
      if String.starts_with ~prefix:"H_DECOY_" h then "H_DECOY" else h
    in
    match String.rindex_opt h '_' with
    | Some idx when idx + 2 < String.length h && h.[idx + 1] = 'D' ->
        let is_digits =
          let rec check i =
            if i >= String.length h then true
            else if h.[i] >= '0' && h.[i] <= '9' then check (i + 1)
            else false
          in
          check (idx + 2)
        in
        if is_digits then String.sub h 0 idx else h
    | _ -> h
  in
  let trace_class_names =
    List.sort_uniq compare
      (List.concat_map
         (fun (_, handlers) -> List.map canonical_handler_name handlers)
         raw_dispatch_domains)
  in
  assert (List.length trace_class_names <= 255);
  let trace_class_id = Hashtbl.create 256 in
  List.iteri
    (fun i name -> Hashtbl.replace trace_class_id name i)
    trace_class_names;
  let trace_tables_source =
    Printf.sprintf
      {|    /* ASG_VM_TRACE: semantic handler classes, stable across builds. */
    static const char* ASG_TRC_NAMES[%d] = { %s };
    static const uint8_t ASG_TRC_CLASS[%d][256] = {
%s
    };
    /* Function-local static: legal at this (function) scope, initialized once. */
    static const bool asg_vm_trace_on = (getenv("ASG_VM_TRACE") != nullptr);|}
      (List.length trace_class_names)
      (String.concat ", " (List.map (fun s -> "\"" ^ s ^ "\"") trace_class_names))
      num_domains
      (String.concat "\n"
         (List.map
            (fun (d, handlers) ->
              Printf.sprintf "    { /* domain %d */ %s },"
                d
                (String.concat ", "
                   (List.map
                      (fun h ->
                        string_of_int
                          (Hashtbl.find trace_class_id
                             (canonical_handler_name h)))
                      handlers)))
            raw_dispatch_domains))
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

  let open Cpp_codegen.Cpp_ast in
  let open Cpp_codegen.Cpp_dsl in

  let preamble_decls : top_decl list = [
    pragma "once";
    raw_top ({|#if __has_include("vanguard/platform_compat.hpp")
#include "vanguard/platform_compat.hpp"
#include "vanguard/crypto_primitives.hpp"
#include "vanguard/sanitization.hpp"
#else
|} ^ Native_vm_templates.platform_compat_header ^ "\n"
  ^ Native_vm_templates.crypto_primitives_header ^ "\n"
  ^ Native_vm_templates.sanitization_header ^ "\n#endif");
  ]
  @ (if policy.enable_vector_isa then [
      macro_def ~value:(i32 1) "ASGARD_VECTOR_ISA";
      raw_top {|#if defined(__aarch64__)
#include <arm_neon.h>
#elif defined(__x86_64__)
#include <immintrin.h>
#endif|};
    ] else [])
  @ [
    raw_top rns_header;
    raw_top branchless_vip_header;
    raw_top chameleon_header;
    raw_top oblivious_mem_header;
  ]
  @ (if policy.enable_oblivious_mem then [
      macro_def ~value:(i32 1) "ASGARD_OBLIVIOUS_MEM";
    ] else [])
  @ (if policy.enable_direct_syscalls then [ raw_top direct_syscalls_header ] else [])
  @ (if policy.enable_anti_emu then [ raw_top anti_emulation_header ] else [])
  @ [ raw_top dual_mapping_header ]
  @ (if policy.enable_smc then
       (if policy.enable_smc_strict then [ macro_def ~value:(i32 1) "ASGARD_SMC_STRICT" ] else [])
       @ [ raw_top smc_header ]
     else [])
  @ (if policy.enable_mem_scan then [ raw_top mem_scan_header ]
     else [
       raw_top ({|namespace asgard_mem_integrity {
    static inline uint64_t compute_section_integrity_hash() noexcept { return |} ^
        (to_c_literal salt_xwcafe_leetbeef) ^
        {|; }
    static inline uint64_t evaluate_memory_integrity() noexcept { return 0; }
}|});
     ])
  @ (if policy.enable_nanomites then [ raw_top nanomite_header ] else [])
  @ (if policy.enable_ephemeral_jit then [
      macro_def ~value:(i32 1) "ASGARD_EPHEMERAL_JIT";
      raw_top ephemeral_jit_header;
    ] else [])
  @ (if has_gpu_constants then [ raw_top gpu_constants ] else [])
  in

  let dynamic_resolvers : top_decl list = [
    raw_top ({|static inline void* asgard_resolve_constant(uint32_t hash, uint32_t alt_hash) noexcept {
    for (size_t i = 0; i < sizeof(g_asgard_constants) / sizeof(g_asgard_constants[0]); ++i) {
        AsgardConstantEntry* c = &g_asgard_constants[i];
        if (c->size > 0) {
            if (c->hash == hash ||
                (alt_hash != 0 && c->hash == alt_hash) ||
                (c->alt_hash != 0 && (c->alt_hash == hash || c->alt_hash == alt_hash))) {
                if (__builtin_expect(!c->ready, 0)) {
                    for (size_t j = 0; j < c->size; ++j) {
                        uint8_t k = (uint8_t)(((c->xor_key >> ((j & 3) * 8)) ^ (j * 0x5D + 0x33)) & 0xFF);
                        c->dec_data[j] = (uint8_t)(c->enc_data[j] ^ k);
                    }
                    c->dec_data[c->size] = 0;
                    c->ready = 1;
                }
                return (void*)c->dec_data;
            }
        }
    }
    return nullptr;
}

static inline void* asgard_resolve_constant_name(const char* name) noexcept {
    if (!name || name[0] == '\0') return nullptr;
    uint32_t h = |} ^
        (to_c_literal32 fnv1a_32_offset_basis) ^
        {|;
    const char* p = name;
    while (*p) {
        h = (h ^ (uint8_t)*p++) * 0x01000193U;
    }
    uint32_t ah = 0;
    if (name[0] == '_') {
        ah = |} ^
        (to_c_literal32 fnv1a_32_offset_basis) ^
        {|;
        p = name + 1;
        while (*p) {
            ah = (ah ^ (uint8_t)*p++) * 0x01000193U;
        }
    }
    return asgard_resolve_constant(h, ah);
}

static inline void* asgard_resolve_sym_idx(int32_t sym_idx) noexcept {
    if (sym_idx < 0 || (size_t)sym_idx >= sizeof(g_external_symbols) / sizeof(g_external_symbols[0])) {
        return nullptr;
    }
    const asgard_ext_sym_t* sym = &g_external_symbols[sym_idx];
    if (sym->len == 0) return nullptr;

    void* sym_ptr = asgard_resolve_constant(sym->hash, sym->alt_hash);
    if (sym_ptr) return sym_ptr;

#if defined(__APPLE__) && defined(__MACH__)
    sym_ptr = asgard_resolve_by_api_hash(sym->hash);
    if (!sym_ptr && sym->alt_hash != 0) {
        sym_ptr = asgard_resolve_by_api_hash(sym->alt_hash);
    }
    if (sym_ptr) return sym_ptr;
#endif

    char dec_name[512];
    asg_decrypt_sym(sym, dec_name, sizeof(dec_name));
    if (!sym_ptr) sym_ptr = asgard_resolve_constant_name(dec_name);

#if defined(__APPLE__) && defined(__MACH__)
    if (!sym_ptr) {
        typedef void* (*dlsym_fn_t)(void*, const char*);
        dlsym_fn_t dyn_dlsym = (dlsym_fn_t)asgard_resolve_by_api_hash(0xE628BBCDU /* FNV1a("_dlsym") */);
        if (dyn_dlsym) {
            sym_ptr = dyn_dlsym((void*)-2, dec_name);
            if (!sym_ptr && dec_name[0] == '_') sym_ptr = dyn_dlsym((void*)-2, dec_name + 1);
            if (!sym_ptr) {
                char alt[514];
                alt[0] = '_';
                memcpy(alt + 1, dec_name, sym->len + 1);
                sym_ptr = dyn_dlsym((void*)-2, alt);
            }
        }
    }
#elif defined(_WIN32) || defined(_WIN64)
    if (!sym_ptr) {
        HMODULE hMain = GetModuleHandleA(NULL);
        sym_ptr = (void*)GetProcAddress(hMain, dec_name);
        if (!sym_ptr && dec_name[0] == '_') sym_ptr = (void*)GetProcAddress(hMain, dec_name + 1);
        if (!sym_ptr) {
            char alt[514];
            alt[0] = '_';
            memcpy(alt + 1, dec_name, sym->len + 1);
            sym_ptr = (void*)GetProcAddress(hMain, alt);
        }
    }
#else
    if (!sym_ptr) {
        if (strcmp(dec_name, "___stdoutp") == 0 || strcmp(dec_name, "__stdoutp") == 0) sym_ptr = dlsym(RTLD_DEFAULT, "stdout");
        else if (strcmp(dec_name, "___stdinp") == 0 || strcmp(dec_name, "__stdinp") == 0) sym_ptr = dlsym(RTLD_DEFAULT, "stdin");
        else if (strcmp(dec_name, "___stderrp") == 0 || strcmp(dec_name, "__stderrp") == 0) sym_ptr = dlsym(RTLD_DEFAULT, "stderr");
        else {
            sym_ptr = dlsym(RTLD_DEFAULT, dec_name);
            if (!sym_ptr && dec_name[0] == '_') sym_ptr = dlsym(RTLD_DEFAULT, dec_name + 1);
            if (!sym_ptr) {
                char alt[514];
                alt[0] = '_';
                memcpy(alt + 1, dec_name, sym->len + 1);
                sym_ptr = dlsym(RTLD_DEFAULT, alt);
            }
        }
    }
#endif

    volatile char* p = dec_name;
    while (*p) *p++ = 0;

    return sym_ptr;
}|});
  ] in

  let wbox_decls = generate_wbox_seed_derivation_decls ~rng key_seed in
  let context_decls =
    Vm_context_emitter.emit_context_decls
      ~context_epochs:policy.context_epochs
      ~key_seed ~reg_perm ~stride ~offset
      ~enable_running_key:policy.enable_running_key
      ~enable_stack_scramble:policy.enable_stack_scramble
      ~enable_mem_sanitize:policy.enable_mem_sanitize
      ()
  in
  let decoy_mnemonics =
    let list = ref [] in
    Array.iteri (fun op h ->
      if not (String.starts_with ~prefix:"H_DECOY" h) then
        list.contents <- (op, h) :: list.contents
    ) opcode_to_handler;
    List.rev !list
  in
  let fn_honeypot_switch =
    Honeypot_dispatch.emit_honeypot_switch_fn rng decoy_mnemonics
  in

  let fn_execute_threaded =
    func_decl ~attrs:[StaticFn; InlineFn] Bool "execute_threaded"
      [
        (Ref (StructType "VMContext"), "ctx");
        (ConstPtr UInt64, "bytecode");
        (SizeT, "count");
        (UInt32, Printf.sprintf "seed = asgard_wbox_derive_seed() /* seed = 0x%08lXU */" key_seed);
        (Bool, "scrub_source = false");
      ]
      ([
        if_then (var "ctx.reg_mask" ==~ u64 0L) [ expr_stmt (call "ctx.init" [var "seed"]) ];
      ]
      @ (if policy.enable_nanomites then [
          expr_stmt (call "asgard_nanomites::install_nanomite_handlers" [var "seed"]);
        ] else [])
      @ [
        let_u64 "full_hash" (u64 (Vm_ir.Rolling_key.poly_init_of_seed key_seed));
        for_range "i" (u64 0L) (var "count") [
          (var "full_hash" := (((var "full_hash" ^~ idx (var "bytecode") (var "i")) *~ u64 (Vm_ir.Rolling_key.poly_multiplier_of_seed key_seed)) +~ c_cast UInt64 (var "i")));
        ];
      ]
      @ (match expected_hashes with
         | Some hl when List.length hl > 1 ->
             [
               emit_native_valid_hashes_ast hl;
               raw ({|    bool hash_ok = false;
    for (size_t hi = 0; hi < sizeof(valid_hashes)/sizeof(valid_hashes[0]); ++hi) {
        if (full_hash == valid_hashes[hi]) { hash_ok = true; break; }
    }
    if (!hash_ok) {
        ctx.reg_mask ^= |} ^
        (to_c_literal salt_deadbeef_5a5a5a5a) ^
        {| ^ full_hash;
        ctx.trapped = true;
        return false;
    }|});
             ]
         | _ ->
             [
               let_u64 "hash_diff" (var "full_hash" ^~ u64 expected_hash);
               (var "ctx.running_key" ^= var "hash_diff");
               (var "ctx.reg_mask" ^= (var "hash_diff" *~ u64 salt_xwcafe_beef));
               if_then (var "hash_diff" <>~ u64 0L) [
                 (var "ctx.trapped" := bool_lit true);
                 ret (bool_lit false);
               ];
             ])
      @ (if policy.enable_direct_syscalls then [
          if_then (call "asgard_syscalls::sys_check_debugger_present" []) [
            (var "ctx.reg_mask" ^= u64 salt_cafebabe_leet);
            (var "ctx.trapped" := bool_lit true);
            ret (bool_lit false);
          ];
        ] else [
          raw ({|#if defined(__APPLE__)
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid() };
    struct kinfo_proc kinfo = {};
    size_t ksize = sizeof(kinfo);
    if (false && sysctl(mib, 4, &kinfo, &ksize, (void*)0, 0) == 0 && (kinfo.kp_proc.p_flag & P_TRACED)) {
        ctx.reg_mask ^= |} ^
        (to_c_literal salt_cafebabe_leet) ^
        {|;
        ctx.trapped = true;
        return false;
    }
#endif|});
        ])
      @ (if policy.enable_anti_emu then [
          let_u64 "emu_penalty" (call "asgard_anti_emulation::evaluate_emulation_differential" []);
          if_then (var "emu_penalty" <>~ u64 0L) [ (var "ctx.reg_mask" ^= var "emu_penalty") ];
        ] else [])
      @ (if policy.enable_smc then [
          let_u64 "smc_penalty" (call "asgard_smc::execute_introspective_smc_probe" [c_cast UInt64 (var "seed")]);
          if_then (var "smc_penalty" <>~ u64 0L) [ (var "ctx.reg_mask" ^= var "smc_penalty") ];
        ] else [])
      @ (if policy.enable_mem_scan then [
          let_u64 "mem_penalty" (call "asgard_mem_integrity::evaluate_memory_integrity" []);
          if_then (var "mem_penalty" <>~ u64 0L) [ (var "ctx.reg_mask" ^= var "mem_penalty") ];
        ] else [])
      @ [
        decl_var (Array (UInt64, 256)) "stack_buf";
        decl_var (Ptr UInt64) "heap_work_bc" ~init:(ternary (var "count" <=~ u64 256L) nullptr (c_cast (Ptr UInt64) (call "malloc" [var "count" *~ sizeof_ty UInt64])));
        decl_var (Ptr UInt64) "work_bc" ~init:(ternary (var "count" <=~ u64 256L) (var "stack_buf") (var "heap_work_bc"));
        if_then (call "__builtin_expect" [log_not (var "work_bc"); i32 0]) [
          (var "ctx.trapped" := bool_lit true);
          ret (bool_lit false);
        ];
      ]
      @ (if policy.enable_mem_sanitize then [
          for_range "i" (u64 0L) (var "count") [
            idx (var "work_bc") (var "i") := u64 salt_xwcafe_leetbeef ^~ (c_cast UInt64 (var "seed") +~ c_cast UInt64 (var "i"));
          ];
        ] else [
          for_range "i" (u64 0L) (var "count") [
            idx (var "work_bc") (var "i") := idx (var "bytecode") (var "i");
          ];
        ])
      @ [
        decl_var SizeT "vIP_idx" ~init:(u64 0L);
      ]
      @ (if policy.enable_ephemeral_jit then [
          raw "#if defined(ASGARD_EPHEMERAL_JIT)\n    static thread_local asgard_memory::DualMappedBuffer g_ephemeral_jit_buf = asgard_memory::DualMappedBuffer::allocate(16384);\n#endif";
        ] else [])
      @ [
        raw trace_tables_source;
        emit_native_domain_salt_ast domain_salts;
        raw (Printf.sprintf "static uintptr_t all_dispatch_domains[%d][256];\n    static bool dispatch_domains_ready = false;\n    if (__builtin_expect(!dispatch_domains_ready, 0)) {\n#if !defined(_MSC_VER) || defined(__clang__)" num_domains);
      ]
      @ emit_native_dispatch_domains_stmts raw_dispatch_domains
      @ [
        raw (Printf.sprintf {|        for (size_t d = 0; d < %d; ++d) {
            for (size_t o = 0; o < 256; ++o) {
                uintptr_t k_slot = ((uintptr_t)seed * 0x517CC1B727220A95ULL) ^ (((uintptr_t)d * 256ULL + (uintptr_t)o) * 0x6A09E667F3BCC908ULL);
                all_dispatch_domains[d][o] = (uintptr_t)raw_all_domains[d][o] ^ k_slot;
                *(reinterpret_cast<volatile uintptr_t*>(&raw_all_domains[d][o])) = k_slot ^ %s;
            }
        }
#else
        for (size_t d = 0; d < %d; ++d) {
            for (size_t o = 0; o < 256; ++o) {
                uintptr_t k_slot = ((uintptr_t)seed * 0x517CC1B727220A95ULL) ^ (((uintptr_t)d * 256ULL + (uintptr_t)o) * 0x6A09E667F3BCC908ULL);
                all_dispatch_domains[d][o] = ((uintptr_t)(d * 256 + o) + 0x1337) ^ k_slot;
            }
        }
#endif
        dispatch_domains_ready = true;
    }|} num_domains (to_c_literal salt_deadbeef_5a5a5a5a) num_domains);
        let_u64 "g_handlers_hash" (call "compute_handlers_hash" [c_cast (ConstPtr (StructType "uintptr_t")) (var "all_dispatch_domains"); i32 num_domains]);
      ]
      @ (if policy.enable_address_bound then [
          raw (Printf.sprintf {|    uint64_t bound_buf[256];
    uint64_t* heap_bound_bc = (count <= 256) ? nullptr : (uint64_t*)malloc(count * sizeof(uint64_t));
    uint64_t* bound_bc = (count <= 256) ? bound_buf : heap_bound_bc;
    if (__builtin_expect(!bound_bc, 0)) {
        if (heap_work_bc) free(heap_work_bc);
        ctx.trapped = true;
        return false;
    }
    for (size_t b = 0; b < g_num_blocks; ++b) {
        size_t off = g_block_offsets[b];
        size_t len = g_block_lengths[b];
        uint64_t rk = VMContext::anchor_key(seed, (uint64_t)off, g_handlers_hash);
        for (size_t j = 0; j < len; ++j) {
            size_t idx = off + j;
            uint64_t k_pos = key64_for_offset(seed, idx);
            uint64_t plain = bytecode[idx] ^ k_pos;
            bound_bc[idx] = plain ^ k_pos ^ rk;
            uint8_t b_op = (uint8_t)((((plain >> %d) + 0xFFULL) - ((plain >> %d) | 0xFFULL)));
            uint8_t b_dst = (uint8_t)((((plain >> %d) + 0x1FULL) - ((plain >> %d) | 0x1FULL)));
            int64_t b_imm = (int64_t)((int32_t)((((plain >> 18) + 0xFFFFFFFFULL) - ((plain >> 18) | 0xFFFFFFFFULL))));
            rk = VMContext::advance_key_step(rk, b_op, b_dst, b_imm);
        }
    }|} word_layout.op_shift word_layout.op_shift word_layout.dst_shift word_layout.dst_shift);
        ] else [])
      @ [
        raw (Printf.sprintf {|    uint64_t word = 0;
    uint64_t k_dyn = 0;
    uint8_t op = 0;
    uint8_t dst = 0;
    uint8_t src = 0;
    int64_t imm = 0;
    size_t next_canary_step = 47 + ((uint64_t)seed & 0x3FULL);
    if (__builtin_expect(ctx.format_version_tag < 0, 0)) {
        legacy_bytecode_interpreter_fallback(op, dst, ctx.decoy_regs);
    }

#if defined(__x86_64__)
    #define ASG_READ_HW_CYCLES() __builtin_ia32_rdtsc()
#elif defined(__aarch64__)
    #define ASG_READ_HW_CYCLES() ([]() noexcept -> uint64_t { uint64_t v; __asm__ volatile("mrs %%0, cntvct_el0" : "=r"(v)); return v; }())
#else
    #define ASG_READ_HW_CYCLES() (0ULL)
#endif

#if defined(_MSC_VER) && !defined(__clang__)
    #define DISPATCH_OPCODE() do { \
        if (__builtin_expect(ctx.format_version_tag < 0, 0)) { \
            legacy_bytecode_interpreter_fallback(op, dst, ctx.decoy_regs); \
        } \
        goto DISPATCH_MSVC; \
    } while(0)
#else
    #define DISPATCH_OPCODE() do { \
        if (__builtin_expect(ctx.format_version_tag < 0, 0)) { \
            legacy_bytecode_interpreter_fallback(op, dst, ctx.decoy_regs); \
        } \
        uint8_t domain_idx = (uint8_t)(((k_dyn >> 32) ^ (ctx.data_key >> 40) ^ ((uint64_t)ctx.pressure_tier * 0x5AULL)) %% %d); \
        uint8_t permuted_slot = (uint8_t)(op ^ domain_salt[domain_idx] ^ ctx.macro_salt); \
        uintptr_t k_slot = ((uintptr_t)seed * 0x517CC1B727220A95ULL) ^ (((uintptr_t)domain_idx * 256ULL + (uintptr_t)permuted_slot) * 0x6A09E667F3BCC908ULL); \
        void* target = (void*)(all_dispatch_domains[domain_idx][permuted_slot] ^ k_slot); \
        goto *target; \
    } while(0)
#endif

    #define FETCH_NEXT() do { \
        if (__builtin_expect(vIP_idx >= count, 0)) goto EXIT_VM; \
        if (__builtin_expect(ctx.executed_instructions > (count * 10000ULL + 1000000ULL), 0)) { \
            ctx.trapped = true; \
            goto EXIT_VM; \
        } \
        uint64_t _tsc_cur = ASG_READ_HW_CYCLES(); \
        if (__builtin_expect(ctx.last_step_tsc != 0, 1)) { \
            ctx.check_analysis_pressure(_tsc_cur - ctx.last_step_tsc); \
        } \
        ctx.last_step_tsc = _tsc_cur; \
        uint64_t k_pos = key64_for_offset(seed, vIP_idx); \
        %s \
        if (__builtin_expect(ctx.executed_instructions >= next_canary_step, 0)) { \
            if (__builtin_expect(!ctx.verify_canaries(), 0)) { \
                ctx.reg_mask ^= (0xCAFEBABE13375877ULL ^ (k_dyn * 0x9E3779B97F4A7C15ULL)) | 1ULL; \
            } \
            next_canary_step = ctx.executed_instructions + 47 + ((k_dyn >> 21) & 0x7FULL); \
        } \
        %s \
        word = work_bc[vIP_idx] ^ k_dyn; \
        %s \
        vIP_idx++; \
        op = (uint8_t)((((word >> %d) + 0xFFULL) - ((word >> %d) | 0xFFULL))); \
        dst = (uint8_t)((((word >> %d) + 0x1FULL) - ((word >> %d) | 0x1FULL))); \
        src = (uint8_t)((((word >> %d) + 0x1FULL) - ((word >> %d) | 0x1FULL))); \
        imm = (int64_t)((int32_t)((((word >> 18) + 0xFFFFFFFFULL) - ((word >> 18) | 0xFFFFFFFFULL)))); \
        ctx.evolve_mask((uint32_t)k_dyn); \
        ctx.evolve_slot_mask(dst, (uint32_t)k_dyn); \
        %s \
        if (__builtin_expect(asg_vm_trace_on, 0)) { uint8_t t_dom = (uint8_t)((k_dyn >> 32) %% %d); fprintf(stderr, "%%u\n", (unsigned)ASG_TRC_CLASS[t_dom][(uint8_t)(op ^ domain_salt[t_dom])]); } \
        DISPATCH_OPCODE(); \
    } while(0)|}
          num_domains
          (if policy.enable_running_key then "k_dyn = k_pos ^ ctx.running_key;" else "k_dyn = k_pos;")
          (if policy.enable_address_bound then "work_bc[vIP_idx] = bound_bc[vIP_idx];" else "work_bc[vIP_idx] = bytecode[vIP_idx];")
          (if policy.enable_mem_sanitize then ("SCRUB_WORD(&work_bc[vIP_idx], (k_dyn * 0x6A09E667F3BCC908ULL) ^ " ^
        (to_c_literal salt_xwcafe_leetbeef) ^
        ");") else "")
          word_layout.op_shift word_layout.op_shift
          word_layout.dst_shift word_layout.dst_shift
          word_layout.src_shift word_layout.src_shift
          (if policy.enable_running_key then "ctx.advance_running_key(op, dst, imm);" else "")
          num_domains
        );
      ]
      @ (if policy.enable_running_key then [
          if policy.enable_address_bound then
            expr_stmt (call "ctx.reanchor_running_key" [u64 0L; var "g_handlers_hash"])
          else
            expr_stmt (call "ctx.reanchor_running_key" [u64 0L])
        ] else [])
      @ [
        raw (Printf.sprintf {|#if defined(_MSC_VER) && !defined(__clang__)
    goto START_VM_MSVC;
    DISPATCH_MSVC: {
        uint8_t d_idx = (uint8_t)(((k_dyn >> 32) ^ (ctx.data_key >> 40) ^ ((uint64_t)ctx.pressure_tier * 0x5AULL)) %% %d);
        uint8_t permuted_slot = (uint8_t)(op ^ domain_salt[d_idx]);
        if (__builtin_expect(asg_vm_trace_on, 0)) { fprintf(stderr, "%%u\n", (unsigned)ASG_TRC_CLASS[d_idx][permuted_slot]); }
        switch ((uint32_t)d_idx * 256U + (uint32_t)permuted_slot) {
%s
        default: goto EXIT_VM;
        }
    }
    START_VM_MSVC:
#endif|} num_domains msvc_switch_cases_source);
        raw "if (__builtin_expect(asg_vm_trace_on, 0)) { fputs(\"# B\\n\", stderr); }";
        raw "FETCH_NEXT();";
        raw handlers_source;
        label "EXIT_VM";
        raw "if (__builtin_expect(asg_vm_trace_on, 0)) { fputs(\"# E\\n\", stderr); }";
      ]
      @ (if policy.enable_mem_sanitize then [
          raw ({|    for (size_t i = 0; i < count; ++i) {
        SCRUB_WORD(&work_bc[i], |} ^
        (to_c_literal salt_regmask) ^
        {| ^ ((uint64_t)seed + (uint64_t)i));
    }|});
        ] else [])
      @ (if policy.enable_mem_sanitize && policy.enable_address_bound then [
          raw ({|    for (size_t i = 0; i < count; ++i) {
        SCRUB_WORD(&bound_bc[i], |} ^
        (to_c_literal salt_deadbeef_5877cafe) ^
        {| ^ ((uint64_t)seed + (uint64_t)i));
    }|});
        ] else [])
      @ (if policy.enable_mem_sanitize then [
          raw ({|    if (scrub_source && bytecode) {
        for (size_t i = 0; i < count; ++i) {
            SCRUB_WORD(&const_cast<uint64_t*>(bytecode)[i], |} ^
        (to_c_literal salt_deadbeef_cafebabe) ^
        {| ^ ((uint64_t)seed + (uint64_t)i));
        }
    }|});
        ] else [])
      @ [
        if_then (ne (var "heap_work_bc") nullptr) [ expr_stmt (call "free" [var "heap_work_bc"]) ];
      ]
      @ (if policy.enable_address_bound then [
          raw "if (heap_bound_bc) free(heap_bound_bc);";
        ] else [])
      @ [
        macro_undef_stmt "DISPATCH_OPCODE";
        macro_undef_stmt "FETCH_NEXT";
        ret (log_not (var "ctx.trapped"));
      ])
  in

  let fn_execute_threaded_short =
    func_decl ~attrs:[StaticFn; InlineFn] Bool "execute_threaded"
      [
        (Ref (StructType "VMContext"), "ctx");
        (ConstPtr UInt64, "bytecode");
        (SizeT, "count");
        (Bool, "scrub_source");
      ]
      [
        ret (call "execute_threaded" [
          var "ctx"; var "bytecode"; var "count"; call "asgard_wbox_derive_seed" []; var "scrub_source"
        ]);
      ]
  in

  let fn_asgard_vm_call_with_salt =
    func_decl ~attrs:[StaticFn; InlineFn; NoInline] UInt64 "asgard_vm_call_with_salt"
      [
        (UInt8, "macro_salt");
        (ConstPtr UInt64, "bc");
        (SizeT, "len");
        (UInt64, "a0 = 0"); (UInt64, "a1 = 0"); (UInt64, "a2 = 0"); (UInt64, "a3 = 0");
        (UInt64, "a4 = 0"); (UInt64, "a5 = 0"); (UInt64, "a6 = 0"); (UInt64, "a7 = 0");
      ]
      [
        decl_var (StructType "vanguard_threaded_vm::VMContext") "ctx" ~init:(init_list []);
        expr_stmt (call "ctx.init" [call "asgard_wbox_derive_seed" []]);
        expr_stmt (call "ctx.set_macro_salt" [var "macro_salt"]);
        decl_var ~align_as:16 ~is_static:true ~is_thread_local:true (Array (UInt8, 1048576)) "host_stack";
        expr_stmt (call "ctx.set_reg" [var "vanguard_threaded_vm::REG_RSP"; c_cast UInt64 (var "host_stack" +~ sizeof_expr (var "host_stack") -~ u64 8192L)]);
        expr_stmt (call "ctx.set_reg" [var "vanguard_threaded_vm::REG_RBP"; c_cast UInt64 (var "host_stack" +~ sizeof_expr (var "host_stack") -~ u64 8192L)]);
        raw {|#if defined(ASGARD_GUEST_ARM64) || (!defined(ASGARD_GUEST_X86_64) && !defined(ASGARD_GUEST_RISCV64) && (defined(__aarch64__) || defined(_M_ARM64)))
    // ARM64 guest calling convention mapping (x0->RAX, x1->RCX, x2->RDX, x3->RBX, x4->RSI, x5->RDI, x6->R8, x7->R9)
    ctx.set_reg(vanguard_threaded_vm::REG_RAX, a0);
    ctx.set_reg(vanguard_threaded_vm::REG_RCX, a1);
    ctx.set_reg(vanguard_threaded_vm::REG_RDX, a2);
    ctx.set_reg(vanguard_threaded_vm::REG_RBX, a3);
    ctx.set_reg(vanguard_threaded_vm::REG_RSI, a4);
    ctx.set_reg(vanguard_threaded_vm::REG_RDI, a5);
    ctx.set_reg(vanguard_threaded_vm::REG_R8,  a6);
    ctx.set_reg(vanguard_threaded_vm::REG_R9,  a7);
#elif defined(ASGARD_GUEST_RISCV64)
    // RISC-V LP64 ABI argument mapping (a0->RAX, a1->RDX, a2->RCX, a3->RSI, a4->RDI, a5->R8, a6->R9, a7->R12)
    ctx.set_reg(vanguard_threaded_vm::REG_RAX, a0);
    ctx.set_reg(vanguard_threaded_vm::REG_RDX, a1);
    ctx.set_reg(vanguard_threaded_vm::REG_RCX, a2);
    ctx.set_reg(vanguard_threaded_vm::REG_RSI, a3);
    ctx.set_reg(vanguard_threaded_vm::REG_RDI, a4);
    ctx.set_reg(vanguard_threaded_vm::REG_R8,  a5);
    ctx.set_reg(vanguard_threaded_vm::REG_R9,  a6);
    ctx.set_reg(vanguard_threaded_vm::REG_R12, a7);
#else
    // x86_64 guest calling convention (System V / Windows x64 ABI argument registers)
    ctx.set_reg(vanguard_threaded_vm::REG_RDI, a0);
    ctx.set_reg(vanguard_threaded_vm::REG_RSI, a1);
    ctx.set_reg(vanguard_threaded_vm::REG_RDX, a2);
    ctx.set_reg(vanguard_threaded_vm::REG_RCX, a3);
    ctx.set_reg(vanguard_threaded_vm::REG_R8,  a4);
    ctx.set_reg(vanguard_threaded_vm::REG_R9,  a5);
    ctx.set_reg(vanguard_threaded_vm::REG_RAX, 0);
#endif|};
        expr_stmt (call "vanguard_threaded_vm::execute_threaded" [var "ctx"; var "bc"; var "len"; call "asgard_wbox_derive_seed" []; bool_lit false]);
        let_u64 "ret_val" (call "ctx.get_rax" []);
        raw ({|if (__builtin_expect(ctx.trapped || ctx.canary_head != vanguard_threaded_vm::VMContext::CANARY_VAL || ctx.canary_tail != vanguard_threaded_vm::VMContext::CANARY_VAL, 0)) {
        ret_val ^= |} ^
        (to_c_literal salt_deadbeef_5a5a5a5a) ^
        {| ^ ctx.reg_mask;
    }|});
        ret (((var "ret_val" ^~ u64 salt_xwcafe_leetbeef) +~ (u64 2L *~ (var "ret_val" &~ u64 salt_xwcafe_leetbeef))) -~ u64 salt_xwcafe_leetbeef);
      ]
  in
  let fn_asgard_vm_call =
    func_decl ~attrs:[StaticFn; InlineFn] UInt64 "asgard_vm_call"
      [
        (ConstPtr UInt64, "bc");
        (SizeT, "len");
        (UInt64, "a0 = 0"); (UInt64, "a1 = 0"); (UInt64, "a2 = 0"); (UInt64, "a3 = 0");
        (UInt64, "a4 = 0"); (UInt64, "a5 = 0"); (UInt64, "a6 = 0"); (UInt64, "a7 = 0");
      ]
      [
        ret (call "asgard_vm_call_with_salt" [
          i32 0;
          var "bc"; var "len";
          var "a0"; var "a1"; var "a2"; var "a3";
          var "a4"; var "a5"; var "a6"; var "a7";
        ]);
      ]
  in

  let vanguard_ns =
    namespace_def "vanguard_threaded_vm" (
      (if policy.enable_address_bound then emit_block_spans_tables_ast block_spans else [])
      @ [ emit_external_symbols_table_ast external_symbols ]
      @ emit_constants_tables_ast ~rng constants
      @ dynamic_resolvers
      @ wbox_decls
      @ context_decls
      @ [
        fn_honeypot_switch;
        fn_execute_threaded;
        fn_execute_threaded_short;
        fn_asgard_vm_call_with_salt;
        fn_asgard_vm_call;
      ]
    )
  in

  preamble_decls @ [ vanguard_ns ]

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
  let decls = emit_native_runtime_hpp_decls
    ~rng ~key_seed ~reg_perm ~expected_hash ?expected_hashes ?runtime_profile ?config
    ~external_symbols ~constants ~block_spans ?gpu_matrix opcode_to_handler
  in
  Cpp_codegen.Cpp_printer.render_top_decls decls ^ "\n"

let emit_native_runner_main_def () : Cpp_codegen.Cpp_ast.top_decl =
  let open Cpp_codegen.Cpp_ast in
  let open Cpp_codegen.Cpp_dsl in
  func_decl Int32 "main" [(Int32, "argc"); (Ptr (Ptr (StructType "char")), "argv")] [
    decl_var (Ptr UInt64) "bc_ptr" ~init:(var "embedded_bytecode");
    decl_var SizeT "bc_len" ~init:(sizeof_expr (var "embedded_bytecode") /~ sizeof_expr (idx (var "embedded_bytecode") (i32 0)));
    decl_var (Ptr UInt64) "heap_bc" ~init:nullptr;
    if_then (var "argc" >=~ i32 2) [
      decl_var (Ptr (StructType "FILE")) "f" ~init:(call "fopen" [idx (var "argv") (i32 1); str_lit "rb"]);
      if_then (ne (var "f") nullptr) [
        expr_stmt (call "fseek" [var "f"; i32 0; var "SEEK_END"]);
        decl_var (StructType "long") "sz" ~init:(call "ftell" [var "f"]);
        expr_stmt (call "fseek" [var "f"; i32 0; var "SEEK_SET"]);
        if_then ((var "sz" >~ i32 0) &&~ ((var "sz" %~ i32 8) ==~ i32 0)) [
          decl_var SizeT "count" ~init:(c_cast SizeT (var "sz") /~ u64 8L);
          var "heap_bc" := c_cast (Ptr UInt64) (call "malloc" [c_cast SizeT (var "sz")]);
          if_then ((ne (var "heap_bc") nullptr) &&~ (call "fread" [var "heap_bc"; u64 8L; var "count"; var "f"] ==~ var "count")) [
            var "bc_ptr" := var "heap_bc";
            var "bc_len" := var "count";
          ];
        ];
        expr_stmt (call "fclose" [var "f"]);
      ];
    ];
    decl_var (StructType "vanguard_threaded_vm::VMContext") "ctx" ~init:(init_list []);
    decl_var Bool "ok" ~init:(call "vanguard_threaded_vm::execute_threaded" [var "ctx"; var "bc_ptr"; var "bc_len"; bool_lit true]);
    if_then (ne (var "heap_bc") nullptr) [
      comment "Ephemeral Heap Sanitization: Scrub all dynamically allocated bytecode before free";
      for_range "i" (u64 0L) (var "bc_len") [
        expr_stmt (call "SCRUB_WORD" [addr_of (idx (var "heap_bc") (var "i")); u64 salt_deadbeef_cafebabe ^~ c_cast UInt64 (var "i")]);
      ];
      expr_stmt (call "free" [var "heap_bc"]);
    ];
    if_then (log_not (var "ok")) [
      ret (i32 2);
    ];
    expr_stmt (call "printf" [
      str_lit "[VM] Execution SUCCESS! Verified %zu instructions. RAX: %llu\n";
      var "ctx.executed_instructions";
      c_cast (StructType "unsigned long long") (call "ctx.get_rax" []);
    ]);
    ret (i32 0);
  ]

let emit_runner_cpp ?(key_seed = salt_xwcafe) ~reg_perm bytecode =
  let _ = key_seed in
  let _ = reg_perm in
  let open Cpp_codegen.Cpp_ast in
  let open Cpp_codegen.Cpp_dsl in
  let open Cpp_codegen.Cpp_printer in
  let embedded_bc_decl =
    global_var ~is_static:true
      (Array (UInt64, 0))
      "embedded_bytecode"
      ~init:(init_list (List.map u64 bytecode))
  in
  let top_decls = [
    include_local "threaded_vm.hpp";
    include_sys "stdio.h";
    include_sys "stdlib.h";
    comment_top "Self-contained embedded encrypted bytecode (Mutable for Ephemeral Memory Scrubbing)";
    embedded_bc_decl;
    emit_native_runner_main_def ();
  ] in
  render_top_decls top_decls ^ "\n"
