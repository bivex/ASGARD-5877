(* lib/tech_2601/tech_2601_emitter.ml
   ASGARD-5877: Tech-2601 (arXiv:2601.10261)
   C++20/C11 Typed EDSL AST Emitter for Cryptographic Shadow Unwind & Exception FSM Runtime *)

open Cpp_codegen.Cpp_ast
open Cpp_codegen.Cpp_dsl
open Cpp_codegen.Cpp_printer

let constant_time_memcmp_decl () : top_decl =
  func_decl ~attrs:[InlineFn] Bool "constant_time_memcmp"
    [(ConstPtr UInt8, "a"); (ConstPtr UInt8, "b"); (SizeT, "len")]
    [
      decl_var UInt8 "diff" ~init:(u8 0);
      for_range "i" (u64 0L) (var "len") [
        var "diff" |= ((idx (var "a") (var "i")) ^~ (idx (var "b") (var "i")));
      ];
      ret (eq (var "diff") (u8 0));
    ]

let secure_zeroize_decl () : top_decl =
  func_decl ~attrs:[InlineFn] Void "secure_zeroize"
    [(Ptr Void, "ptr"); (SizeT, "len")]
    [
      raw "volatile uint8_t* p = static_cast<volatile uint8_t*>(ptr);";
      while_loop (var "len--") [
        raw "*p++ = 0;";
      ];
    ]

let secure_zero_decl () : top_decl =
  func_decl ~attrs:[InlineFn] Void "secure_zero"
    [(Ptr Void, "ptr"); (SizeT, "len")]
    [
      expr_stmt (call "secure_zeroize" [var "ptr"; var "len"]);
    ]

let sha256_class_def () : top_decl =
  class_def "Sha256" [
    member_private;
    member_field (Array (UInt32, 8)) "state";
    member_field UInt64 "count";
    member_field (Array (UInt8, 64)) "buffer";

    member_method ~attrs:[InlineFn] ~is_static:true UInt32 "rotr" [(UInt32, "x"); (UInt32, "n")] [
      ret (((var "x") >>~ (var "n")) |~ ((var "x") <<~ ((i32 32) -~ (var "n"))));
    ];
    member_method ~attrs:[InlineFn] ~is_static:true UInt32 "choose" [(UInt32, "x"); (UInt32, "y"); (UInt32, "z")] [
      ret (((var "x") &~ (var "y")) ^~ ((bit_not (var "x")) &~ (var "z")));
    ];
    member_method ~attrs:[InlineFn] ~is_static:true UInt32 "majority" [(UInt32, "x"); (UInt32, "y"); (UInt32, "z")] [
      ret ((((var "x") &~ (var "y")) ^~ ((var "x") &~ (var "z"))) ^~ ((var "y") &~ (var "z")));
    ];
    member_method ~attrs:[InlineFn] ~is_static:true UInt32 "big_sigma0" [(UInt32, "x")] [
      ret (((call "rotr" [var "x"; i32 2]) ^~ (call "rotr" [var "x"; i32 13])) ^~ (call "rotr" [var "x"; i32 22]));
    ];
    member_method ~attrs:[InlineFn] ~is_static:true UInt32 "big_sigma1" [(UInt32, "x")] [
      ret (((call "rotr" [var "x"; i32 6]) ^~ (call "rotr" [var "x"; i32 11])) ^~ (call "rotr" [var "x"; i32 25]));
    ];
    member_method ~attrs:[InlineFn] ~is_static:true UInt32 "small_sigma0" [(UInt32, "x")] [
      ret (((call "rotr" [var "x"; i32 7]) ^~ (call "rotr" [var "x"; i32 18])) ^~ ((var "x") >>~ (i32 3)));
    ];
    member_method ~attrs:[InlineFn] ~is_static:true UInt32 "small_sigma1" [(UInt32, "x")] [
      ret (((call "rotr" [var "x"; i32 17]) ^~ (call "rotr" [var "x"; i32 19])) ^~ ((var "x") >>~ (i32 10)));
    ];

    member_method Void "transform" [(ConstPtr UInt8, "block")] [
      raw "static const uint32_t K[64] = {
            0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
            0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
            0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
            0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
            0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
            0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
            0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
            0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
            0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
            0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
            0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
            0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
            0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
            0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
            0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
            0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
        };";
      decl_var (Array (UInt32, 64)) "W";
      raw "for (int t = 0; t < 16; ++t) {
            W[t] = (static_cast<uint32_t>(block[t * 4]) << 24) |
                   (static_cast<uint32_t>(block[t * 4 + 1]) << 16) |
                   (static_cast<uint32_t>(block[t * 4 + 2]) << 8) |
                   (static_cast<uint32_t>(block[t * 4 + 3]));
        }";
      raw "for (int t = 16; t < 64; ++t) {
            W[t] = small_sigma1(W[t - 2]) + W[t - 7] + small_sigma0(W[t - 15]) + W[t - 16];
        }";
      decl_var UInt32 "a" ~init:(idx (var "state") (i32 0));
      decl_var UInt32 "b" ~init:(idx (var "state") (i32 1));
      decl_var UInt32 "c" ~init:(idx (var "state") (i32 2));
      decl_var UInt32 "d" ~init:(idx (var "state") (i32 3));
      decl_var UInt32 "e" ~init:(idx (var "state") (i32 4));
      decl_var UInt32 "f" ~init:(idx (var "state") (i32 5));
      decl_var UInt32 "g" ~init:(idx (var "state") (i32 6));
      decl_var UInt32 "h" ~init:(idx (var "state") (i32 7));

      raw "for (int t = 0; t < 64; ++t) {
            uint32_t T1 = h + big_sigma1(e) + choose(e, f, g) + K[t] + W[t];
            uint32_t T2 = big_sigma0(a) + majority(a, b, c);
            h = g; g = f; f = e; e = d + T1;
            d = c; c = b; b = a; a = T1 + T2;
        }";

      idx (var "state") (i32 0) += var "a";
      idx (var "state") (i32 1) += var "b";
      idx (var "state") (i32 2) += var "c";
      idx (var "state") (i32 3) += var "d";
      idx (var "state") (i32 4) += var "e";
      idx (var "state") (i32 5) += var "f";
      idx (var "state") (i32 6) += var "g";
      idx (var "state") (i32 7) += var "h";
    ];

    member_public;
    member_constructor "Sha256" [
      expr_stmt (call "reset" []);
    ];
    member_method Void "reset" [] [
      idx (var "state") (i32 0) := (u32 0x6a09e667l);
      idx (var "state") (i32 1) := (c_cast UInt32 (u32 (-0x4498517bl)));
      idx (var "state") (i32 2) := (u32 0x3c6ef372l);
      idx (var "state") (i32 3) := (c_cast UInt32 (u32 (-0x5ab00ac6l)));
      idx (var "state") (i32 4) := (u32 0x510e527fl);
      idx (var "state") (i32 5) := (c_cast UInt32 (u32 (-0x64fa9774l)));
      idx (var "state") (i32 6) := (u32 0x1f83d9abl);
      idx (var "state") (i32 7) := (u32 0x5be0cd19l);
      var "count" := u64 0L;
    ];
    member_method Void "update" [(ConstPtr UInt8, "data"); (SizeT, "len")] [
      decl_var SizeT "buffer_idx" ~init:((var "count") %~ (u64 64L));
      var "count" += var "len";
      for_range "i" (u64 0L) (var "len") [
        idx (var "buffer") (var "buffer_idx++") := idx (var "data") (var "i");
        if_then ((var "buffer_idx") ==~ (u64 64L)) [
          expr_stmt (call "transform" [var "buffer"]);
          var "buffer_idx" := u64 0L;
        ];
      ];
    ];
    member_method Void "finalize" [(Ptr UInt8, "digest")] [
      decl_var SizeT "buffer_idx" ~init:((var "count") %~ (u64 64L));
      idx (var "buffer") (var "buffer_idx++") := u8 0x80;
      if_then ((var "buffer_idx") >~ (u64 56L)) [
        while_loop ((var "buffer_idx") <~ (u64 64L)) [
          idx (var "buffer") (var "buffer_idx++") := u8 0x00;
        ];
        expr_stmt (call "transform" [var "buffer"]);
        var "buffer_idx" := u64 0L;
      ];
      while_loop ((var "buffer_idx") <~ (u64 56L)) [
        idx (var "buffer") (var "buffer_idx++") := u8 0x00;
      ];
      decl_var UInt64 "bits" ~init:((var "count") *~ (u64 8L));
      raw "for (int i = 7; i >= 0; --i) {
            buffer[56 + (7 - i)] = static_cast<uint8_t>((bits >> (i * 8)) & 0xFF);
        }";
      expr_stmt (call "transform" [var "buffer"]);
      raw "for (int i = 0; i < 8; ++i) {
            digest[i * 4] = static_cast<uint8_t>((state[i] >> 24) & 0xFF);
            digest[i * 4 + 1] = static_cast<uint8_t>((state[i] >> 16) & 0xFF);
            digest[i * 4 + 2] = static_cast<uint8_t>((state[i] >> 8) & 0xFF);
            digest[i * 4 + 3] = static_cast<uint8_t>(state[i] & 0xFF);
        }";
    ];
    member_method ~is_static:true Void "hash" [(ConstPtr UInt8, "data"); (SizeT, "len"); (Ptr UInt8, "digest")] [
      decl_var (StructType "Sha256") "ctx";
      expr_stmt (call "ctx.update" [var "data"; var "len"]);
      expr_stmt (call "ctx.finalize" [var "digest"]);
    ];
  ]

let hmac_sha256_class_def () : top_decl =
  class_def "HmacSha256" [
    member_public;
    member_method ~is_static:true Void "compute"
      [(ConstPtr UInt8, "key"); (SizeT, "key_len"); (ConstPtr UInt8, "data"); (SizeT, "data_len"); (Ptr UInt8, "mac")]
      [
        decl_var (Array (UInt8, 64)) "norm_key";
        expr_stmt (call "std::memset" [var "norm_key"; i32 0; u64 64L]);
        if_then_else ((var "key_len") >~ (u64 64L))
          [ expr_stmt (call "Sha256::hash" [var "key"; var "key_len"; var "norm_key"]) ]
          [ expr_stmt (call "std::memcpy" [var "norm_key"; var "key"; var "key_len"]) ];

        decl_var (Array (UInt8, 64)) "k_ipad";
        decl_var (Array (UInt8, 64)) "k_opad";
        for_range "i" (u64 0L) (u64 64L) [
          idx (var "k_ipad") (var "i") := (idx (var "norm_key") (var "i")) ^~ (u8 0x36);
          idx (var "k_opad") (var "i") := (idx (var "norm_key") (var "i")) ^~ (u8 0x5c);
        ];

        decl_var (Array (UInt8, 32)) "inner_hash";
        decl_var (StructType "Sha256") "inner_ctx";
        expr_stmt (call "inner_ctx.update" [var "k_ipad"; u64 64L]);
        expr_stmt (call "inner_ctx.update" [var "data"; var "data_len"]);
        expr_stmt (call "inner_ctx.finalize" [var "inner_hash"]);

        decl_var (StructType "Sha256") "outer_ctx";
        expr_stmt (call "outer_ctx.update" [var "k_opad"; u64 64L]);
        expr_stmt (call "outer_ctx.update" [var "inner_hash"; u64 32L]);
        expr_stmt (call "outer_ctx.finalize" [var "mac"]);

        expr_stmt (call "secure_zero" [var "norm_key"; u64 64L]);
        expr_stmt (call "secure_zero" [var "k_ipad"; u64 64L]);
        expr_stmt (call "secure_zero" [var "k_opad"; u64 64L]);
        expr_stmt (call "secure_zero" [var "inner_hash"; u64 32L]);
      ];
  ]

let try_scope_struct_def () : top_decl =
  struct_def "Tech2601TryScope" [
    member_field Int32 "scope_id";
    member_field UInt64 "start_pc";
    member_field UInt64 "end_pc";
    member_field UInt64 "landing_pad_pc";
    member_field Int32 "catch_type_tag";
  ]

let destructor_struct_def () : top_decl =
  struct_def "Tech2601Destructor" [
    member_field Int32 "obj_id";
    member_field UInt64 "live_start_pc";
    member_field UInt64 "live_end_pc";
    member_field UInt64 "dtor_pc";
  ]

let shadow_record_struct_def () : top_decl =
  struct_def "Tech2601ShadowRecord" [
    member_field UInt32 "shadow_alloc_size";
    member_field (StructType "std::string") "interceptor_symbol";
  ]

let original_metadata_struct_def () : top_decl =
  struct_def "Tech2601OriginalMetadata" [
    member_field (StructType "std::string") "func_name";
    member_field UInt64 "code_start_pc";
    member_field UInt32 "code_size";
    member_field (StructType "std::vector<Tech2601TryScope>") "scopes";
    member_field (StructType "std::vector<Tech2601Destructor>") "dtors";
    member_method Void "secure_wipe" [] [
      if_then (log_not (call "scopes.empty" [])) [
        expr_stmt (call "secure_zeroize" [
          call "scopes.data" [];
          (call "scopes.size" []) *~ (sizeof_ty (StructType "Tech2601TryScope"))
        ]);
        expr_stmt (call "scopes.clear" []);
      ];
      if_then (log_not (call "dtors.empty" [])) [
        expr_stmt (call "secure_zeroize" [
          call "dtors.data" [];
          (call "dtors.size" []) *~ (sizeof_ty (StructType "Tech2601Destructor"))
        ]);
        expr_stmt (call "dtors.clear" []);
      ];
      if_then (log_not (call "func_name.empty" [])) [
        expr_stmt (call "secure_zeroize" [
          addr_of (idx (var "func_name") (i32 0));
          call "func_name.size" []
        ]);
        expr_stmt (call "func_name.clear" []);
      ];
      var "code_start_pc" := u64 0L;
      var "code_size" := u32 0l;
    ];
    member_destructor "Tech2601OriginalMetadata" [
      expr_stmt (call "secure_wipe" []);
    ];
  ]

let shadow_frame_struct_def () : top_decl =
  struct_def "ShadowFrame" [
    member_field UInt64 "func_pc";
    member_field UIntPtr "shadow_sp";
    member_field UInt32 "shadow_alloc_size";
    member_field UInt64 "return_address";
  ]

let thread_shadow_stack_class_def () : top_decl =
  class_def "ThreadShadowStack" [
    member_private;
    member_field (StructType "std::vector<ShadowFrame>") "frames";
    member_public;
    member_method Void "push"
      [(UInt64, "func_pc"); (UIntPtr, "shadow_sp"); (UInt32, "alloc_size"); (UInt64, "ret_addr")]
      [
        raw "frames.push_back({func_pc, shadow_sp, alloc_size, ret_addr});";
      ];
    member_method Bool "pop"
      [(Ref (StructType "ShadowFrame"), "out")]
      [
        if_then (call "frames.empty" []) [ ret (bool_lit false) ];
        var "out" := call "frames.back" [];
        expr_stmt (call "frames.pop_back" []);
        ret (bool_lit true);
      ];
    member_method ~is_const:true (ConstPtr (StructType "ShadowFrame")) "top" []
      [
        if_then (call "frames.empty" []) [ ret nullptr ];
        ret (addr_of (call "frames.back" []));
      ];
    member_method ~is_const:true SizeT "size" []
      [
        ret (call "frames.size" []);
      ];
    member_method Void "clear" []
      [
        raw "for (auto& f : frames) {
            secure_zeroize(&f, sizeof(ShadowFrame));
        }";
        expr_stmt (call "frames.clear" []);
      ];
    member_destructor "ThreadShadowStack"
      [
        expr_stmt (call "clear" []);
      ];
  ]

let get_tls_shadow_stack_decl () : top_decl =
  func_decl ~attrs:[InlineFn] (Ref (StructType "ThreadShadowStack")) "get_tls_shadow_stack" []
    [
      decl_var ~is_thread_local:true (StructType "ThreadShadowStack") "tls_stack";
      ret (var "tls_stack");
    ]

let protected_container_struct_def () : top_decl =
  struct_def "Tech2601ProtectedContainer" [
    member_field (StructType "std::string") "func_name";
    member_field UInt64 "code_start_pc";
    member_field UInt32 "code_size";
    member_field (StructType "Tech2601ShadowRecord") "shadow";
    member_field (StructType "std::vector<uint8_t>") "encrypted_blob";
    member_field (Array (UInt8, 32)) "auth_tag";
  ]

let rollback_stack_decl () : top_decl =
  func_decl ~attrs:[InlineFn] UIntPtr "tech_2601_rollback_stack"
    [(UIntPtr, "current_sp"); (UInt32, "shadow_alloc_size")]
    [
      comment "In downward-growing stack (x86-64/ARM64), global unwind restored frame by adding alloc_size.";
      comment "Rollback subtracts the shadow allocation to return SP to inner frame state.";
      preproc_if_stmt "defined(_WIN32) || defined(_WIN64)"
        ~else_stmts:[
          ret ((var "current_sp") -~ (var "shadow_alloc_size"));
        ]
        [
          decl_var UIntPtr "target_sp" ~init:(((var "current_sp") -~ (var "shadow_alloc_size")) &~ (bit_not (cast UIntPtr (u64 0xFL))));
          ret (var "target_sp");
        ];
    ]

let scrub_stack_decl () : top_decl =
  func_decl ~attrs:[InlineFn; NoExcept] Void "tech_2601_scrub_stack"
    [(UIntPtr, "target_sp"); (UIntPtr, "current_sp")]
    [
      if_then (((var "current_sp") >~ (var "target_sp")) &&~ (ne (var "target_sp") (u64 0L))) [
        expr_stmt (call "secure_zeroize" [
          reinterpret_cast (Ptr Void) (var "target_sp");
          (var "current_sp") -~ (var "target_sp");
        ]);
      ];
    ]

let xor_keystream_decl () : top_decl =
  func_decl ~attrs:[InlineFn] Void "xor_keystream"
    [(ConstPtr UInt8, "enc_key"); (ConstPtr UInt8, "in"); (Ptr UInt8, "out"); (SizeT, "len")]
    [
      decl_var SizeT "block_count" ~init:(((var "len") +~ (u64 31L)) /~ (u64 32L));
      decl_var SizeT "cur" ~init:(u64 0L);
      for_range "blk" (u64 0L) (var "block_count") [
        decl_var (Array (UInt8, 4)) "counter";
        idx (var "counter") (i32 0) := cast UInt8 ((var "blk") &~ (u64 0xFFL));
        idx (var "counter") (i32 1) := cast UInt8 (((var "blk") >>~ (i32 8)) &~ (u64 0xFFL));
        idx (var "counter") (i32 2) := cast UInt8 (((var "blk") >>~ (i32 16)) &~ (u64 0xFFL));
        idx (var "counter") (i32 3) := cast UInt8 (((var "blk") >>~ (i32 24)) &~ (u64 0xFFL));

        decl_var (Array (UInt8, 32)) "key_block";
        expr_stmt (call "HmacSha256::compute" [var "enc_key"; u64 32L; var "counter"; u64 4L; var "key_block"]);

        decl_var SizeT "to_copy" ~init:(call "std::min" [cast SizeT (u64 32L); (var "len") -~ (var "cur")]);
        for_range "i" (u64 0L) (var "to_copy") [
          idx (var "out") ((var "cur") +~ (var "i")) :=
            (idx (var "in") ((var "cur") +~ (var "i"))) ^~ (idx (var "key_block") (var "i"));
        ];
        var "cur" += var "to_copy";
        expr_stmt (call "secure_zero" [var "key_block"; u64 32L]);
      ];
    ]

let compute_container_mac_decl () : top_decl =
  func_decl ~attrs:[InlineFn] Void "compute_container_mac"
    [
      (ConstPtr UInt8, "mac_key");
      (ConstRef (StructType "std::string"), "func_name");
      (UInt64, "code_start_pc");
      (UInt32, "code_size");
      (ConstRef (StructType "Tech2601ShadowRecord"), "shadow");
      (ConstPtr UInt8, "ciphertext");
      (SizeT, "ciphertext_len");
      (Ptr UInt8, "out_tag");
    ]
    [
      decl_var (StructType "std::vector<uint8_t>") "buf";
      decl_var UInt16 "name_len" ~init:(cast UInt16 (call "func_name.length" []));
      expr_stmt (call "buf.push_back" [cast UInt8 ((var "name_len") &~ (u32 0xFFl))]);
      expr_stmt (call "buf.push_back" [cast UInt8 (((var "name_len") >>~ (i32 8)) &~ (u32 0xFFl))]);
      expr_stmt (call "buf.insert" [call "buf.end" []; call "func_name.begin" []; call "func_name.end" []]);

      for_range "i" (u64 0L) (u64 8L) [
        expr_stmt (call "buf.push_back" [cast UInt8 (((var "code_start_pc") >>~ ((var "i") *~ (u64 8L))) &~ (u64 0xFFL))]);
      ];
      for_range "i" (u64 0L) (u64 4L) [
        expr_stmt (call "buf.push_back" [cast UInt8 (((var "code_size") >>~ ((var "i") *~ (u64 8L))) &~ (u64 0xFFL))]);
      ];
      for_range "i" (u64 0L) (u64 4L) [
        expr_stmt (call "buf.push_back" [cast UInt8 ((((var "shadow") $. "shadow_alloc_size") >>~ ((var "i") *~ (u64 8L))) &~ (u64 0xFFL))]);
      ];

      decl_var UInt16 "sym_len" ~init:(cast UInt16 (call "shadow.interceptor_symbol.length" []));
      expr_stmt (call "buf.push_back" [cast UInt8 ((var "sym_len") &~ (u32 0xFFl))]);
      expr_stmt (call "buf.push_back" [cast UInt8 (((var "sym_len") >>~ (i32 8)) &~ (u32 0xFFl))]);
      expr_stmt (call "buf.insert" [call "buf.end" []; call "shadow.interceptor_symbol.begin" []; call "shadow.interceptor_symbol.end" []]);

      expr_stmt (call "buf.insert" [call "buf.end" []; var "ciphertext"; (var "ciphertext") +~ (var "ciphertext_len")]);

      expr_stmt (call "HmacSha256::compute" [var "mac_key"; u64 32L; call "buf.data" []; call "buf.size" []; var "out_tag"]);
    ]

let unseal_decl () : top_decl =
  func_decl ~attrs:[InlineFn] Bool "tech_2601_unseal"
    [
      (ConstPtr UInt8, "master_key");
      (SizeT, "master_key_len");
      (ConstRef (StructType "Tech2601ProtectedContainer"), "container");
      (Ref (StructType "Tech2601OriginalMetadata"), "out_meta");
    ]
    [
      comment "1. Derive mac key";
      decl_var (StructType "std::string") "mac_label" ~init:((str_lit "TECH-2601-MAC:") +~ ((var "container") $. "func_name"));
      decl_var (Array (UInt8, 32)) "mac_key";
      expr_stmt (call "HmacSha256::compute" [
        var "master_key";
        var "master_key_len";
        reinterpret_cast (ConstPtr UInt8) (call "mac_label.data" []);
        call "mac_label.length" [];
        var "mac_key"
      ]);

      comment "2. Verify MAC tag";
      decl_var (Array (UInt8, 32)) "expected_tag";
      expr_stmt (call "compute_container_mac" [
        var "mac_key";
        (var "container") $. "func_name";
        (var "container") $. "code_start_pc";
        (var "container") $. "code_size";
        (var "container") $. "shadow";
        call "container.encrypted_blob.data" [];
        call "container.encrypted_blob.size" [];
        var "expected_tag"
      ]);

      if_then (log_not (call "constant_time_memcmp" [var "expected_tag"; (var "container") $. "auth_tag"; u64 32L])) [
        expr_stmt (call "secure_zero" [var "mac_key"; u64 32L]);
        ret (bool_lit false);
      ];

      comment "3. Derive enc key";
      decl_var (StructType "std::string") "enc_label" ~init:((str_lit "TECH-2601-ENC:") +~ ((var "container") $. "func_name"));
      decl_var (Array (UInt8, 32)) "enc_key";
      expr_stmt (call "HmacSha256::compute" [
        var "master_key";
        var "master_key_len";
        reinterpret_cast (ConstPtr UInt8) (call "enc_label.data" []);
        call "enc_label.length" [];
        var "enc_key"
      ]);

      comment "4. Decrypt";
      raw "std::vector<uint8_t> plaintext(container.encrypted_blob.size());";
      expr_stmt (call "xor_keystream" [
        var "enc_key";
        call "container.encrypted_blob.data" [];
        call "plaintext.data" [];
        call "plaintext.size" []
      ]);

      expr_stmt (call "secure_zero" [var "mac_key"; u64 32L]);
      expr_stmt (call "secure_zero" [var "enc_key"; u64 32L]);

      comment "5. Deserialize";
      if_then ((call "plaintext.size" []) <~ (u64 18L)) [
        expr_stmt (call "secure_zero" [call "plaintext.data" []; call "plaintext.size" []]);
        ret (bool_lit false);
      ];

      decl_var SizeT "off" ~init:(u64 0L);
      raw "uint32_t magic = plaintext[off] | (plaintext[off+1]<<8) | (plaintext[off+2]<<16) | (plaintext[off+3]<<24);";
      var "off" += u64 4L;
      if_then (ne (var "magic") (u32 0x54454348l)) [
        expr_stmt (call "secure_zero" [call "plaintext.data" []; call "plaintext.size" []]);
        ret (bool_lit false);
      ];
      raw "uint16_t ver = plaintext[off] | (plaintext[off+1]<<8);";
      var "off" += u64 2L;
      if_then (ne (var "ver") (i32 1)) [
        expr_stmt (call "secure_zero" [call "plaintext.data" []; call "plaintext.size" []]);
        ret (bool_lit false);
      ];

      raw "uint16_t name_len = plaintext[off] | (plaintext[off+1]<<8);";
      var "off" += u64 2L;
      decl_var (StructType "std::string") "fn_name" ~init:(call "std::string" [reinterpret_cast (Ptr (StructType "char")) (addr_of (idx (var "plaintext") (var "off"))); var "name_len"]);
      var "off" += var "name_len";

      raw "uint64_t start_pc = 0;";
      raw "for (int i = 0; i < 8; ++i) start_pc |= (static_cast<uint64_t>(plaintext[off + i]) << (i * 8));";
      var "off" += u64 8L;

      raw "uint32_t code_sz = plaintext[off] | (plaintext[off+1]<<8) | (plaintext[off+2]<<16) | (plaintext[off+3]<<24);";
      var "off" += u64 4L;

      comment "Skip unwind ops in C++ parser for dispatch";
      raw "uint16_t op_count = plaintext[off] | (plaintext[off+1]<<8);";
      var "off" += u64 2L;
      raw "for (uint16_t i = 0; i < op_count; ++i) {
        uint8_t tag = plaintext[off++];
        if (tag == 1) { off += 4; }
        else if (tag == 2) { uint16_t sl = plaintext[off] | (plaintext[off+1]<<8); off += 2 + sl; }
        else if (tag == 3 || tag == 4) { uint16_t sl = plaintext[off] | (plaintext[off+1]<<8); off += 2 + sl + 4; }
    }";

      comment "Read scopes";
      raw "uint16_t scope_count = plaintext[off] | (plaintext[off+1]<<8);";
      var "off" += u64 2L;
      decl_var (StructType "std::vector<Tech2601TryScope>") "scopes";
      raw "for (uint16_t i = 0; i < scope_count; ++i) {
        Tech2601TryScope sc;
        sc.scope_id = static_cast<int32_t>(plaintext[off] | (plaintext[off+1]<<8) | (plaintext[off+2]<<16) | (plaintext[off+3]<<24));
        off += 4;
        sc.start_pc = 0;
        for (int b = 0; b < 8; ++b) sc.start_pc |= (static_cast<uint64_t>(plaintext[off + b]) << (b * 8));
        off += 8;
        sc.end_pc = 0;
        for (int b = 0; b < 8; ++b) sc.end_pc |= (static_cast<uint64_t>(plaintext[off + b]) << (b * 8));
        off += 8;
        sc.landing_pad_pc = 0;
        for (int b = 0; b < 8; ++b) sc.landing_pad_pc |= (static_cast<uint64_t>(plaintext[off + b]) << (b * 8));
        off += 8;
        sc.catch_type_tag = static_cast<int32_t>(plaintext[off] | (plaintext[off+1]<<8) | (plaintext[off+2]<<16) | (plaintext[off+3]<<24));
        off += 4;
        scopes.push_back(sc);
    }";

      comment "Read dtors";
      raw "uint16_t dtor_count = plaintext[off] | (plaintext[off+1]<<8);";
      var "off" += u64 2L;
      decl_var (StructType "std::vector<Tech2601Destructor>") "dtors";
      raw "for (uint16_t i = 0; i < dtor_count; ++i) {
        Tech2601Destructor dt;
        dt.obj_id = static_cast<int32_t>(plaintext[off] | (plaintext[off+1]<<8) | (plaintext[off+2]<<16) | (plaintext[off+3]<<24));
        off += 4;
        dt.live_start_pc = 0;
        for (int b = 0; b < 8; ++b) dt.live_start_pc |= (static_cast<uint64_t>(plaintext[off + b]) << (b * 8));
        off += 8;
        dt.live_end_pc = 0;
        for (int b = 0; b < 8; ++b) dt.live_end_pc |= (static_cast<uint64_t>(plaintext[off + b]) << (b * 8));
        off += 8;
        dt.dtor_pc = 0;
        for (int b = 0; b < 8; ++b) dt.dtor_pc |= (static_cast<uint64_t>(plaintext[off + b]) << (b * 8));
        off += 8;
        dtors.push_back(dt);
    }";

      (var "out_meta") $. "func_name" := var "fn_name";
      (var "out_meta") $. "code_start_pc" := var "start_pc";
      (var "out_meta") $. "code_size" := var "code_sz";
      (var "out_meta") $. "scopes" := var "scopes";
      (var "out_meta") $. "dtors" := var "dtors";

      expr_stmt (call "secure_zero" [call "plaintext.data" []; call "plaintext.size" []]);
      ret (bool_lit true);
    ]

let resolve_exception_decl () : top_decl =
  func_decl ~attrs:[InlineFn] Bool "tech_2601_resolve_exception"
    [
      (ConstRef (StructType "Tech2601OriginalMetadata"), "meta");
      (UInt64, "throwing_pc");
      (Int32, "exception_tag");
      (Ptr UInt64, "out_landing_pad");
      (Ref (StructType "std::vector<uint64_t>"), "out_dtors");
    ]
    [
      decl_var ~is_const:true Int32 "catch_all_tag" ~init:(i32 (-1));
      decl_var (ConstPtr (StructType "Tech2601TryScope")) "matched_scope" ~init:nullptr;
      decl_var UInt64 "min_span" ~init:(var "UINT64_MAX");

      raw "for (const auto& sc : meta.scopes) {
        if (throwing_pc >= sc.start_pc && throwing_pc < sc.end_pc) {
            if (sc.catch_type_tag == exception_tag || sc.catch_type_tag == catch_all_tag) {
                uint64_t span = sc.end_pc - sc.start_pc;
                if (span < min_span) {
                    min_span = span;
                    matched_scope = &sc;
                }
            }
        }
    }";

      if_then (log_not (var "matched_scope")) [ ret (bool_lit false) ];
      deref (var "out_landing_pad") := (var "matched_scope") $-> "landing_pad_pc";

      comment "Collect active destructors";
      decl_var (StructType "std::vector<Tech2601Destructor>") "active_dtors";
      raw "for (const auto& dt : meta.dtors) {
        if (throwing_pc >= dt.live_start_pc && throwing_pc < dt.live_end_pc) {
            active_dtors.push_back(dt);
        }
    }";

      comment "Sort in LIFO order (descending start_pc, then obj_id)";
      raw "std::sort(active_dtors.begin(), active_dtors.end(), [](const Tech2601Destructor& a, const Tech2601Destructor& b) {
        if (a.live_start_pc != b.live_start_pc)
            return a.live_start_pc > b.live_start_pc;
        return a.obj_id > b.obj_id;
    });";

      expr_stmt (call "out_dtors.clear" []);
      raw "for (const auto& dt : active_dtors) {
        out_dtors.push_back(dt.dtor_pc);
    }";

      ret (bool_lit true);
    ]

let tech_2601_namespace_decls () : top_decl list = [
  comment_top "Constant-time memory comparison for authentication tag validation";
  constant_time_memcmp_decl ();
  comment_top "In-place secure buffer sanitization (P2-02)";
  secure_zeroize_decl ();
  secure_zero_decl ();
  comment_top "RFC 6234 SHA-256";
  sha256_class_def ();
  comment_top "RFC 2104 HMAC-SHA256";
  hmac_sha256_class_def ();
  comment_top "--- Tech-2601 Data Structures ---";
  try_scope_struct_def ();
  destructor_struct_def ();
  shadow_record_struct_def ();
  original_metadata_struct_def ();
  comment_top "Thread-safe shadow stack state (P0-02)";
  shadow_frame_struct_def ();
  thread_shadow_stack_class_def ();
  get_tls_shadow_stack_decl ();
  protected_container_struct_def ();
  comment_top "Stack pointer rollback arithmetic";
  rollback_stack_decl ();
  comment_top "Memory Remanence Protection: zero-scrub stack region (P2-01)";
  scrub_stack_decl ();
  comment_top "Stream keystream XOR";
  xor_keystream_decl ();
  comment_top "Compute authentication MAC for container";
  compute_container_mac_decl ();
  comment_top "Unseal and verify container";
  unseal_decl ();
  comment_top "Exception Resolution FSM";
  resolve_exception_decl ();
]

let runtime_header_decls () : top_decl list = [
  preproc_ifndef "ASGARD_TECH_2601_HPP" [
    macro_def "ASGARD_TECH_2601_HPP";
    include_sys "cstdint";
    include_sys "cstddef";
    include_sys "cstring";
    include_sys "vector";
    include_sys "string";
    include_sys "algorithm";
    namespace_def "asgard" [
      namespace_def "tech_2601" (tech_2601_namespace_decls ())
    ]
  ]
]

let emit_runtime_header () : string =
  render_header_unit (runtime_header_decls ())
