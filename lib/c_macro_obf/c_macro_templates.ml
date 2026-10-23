(* lib/c_macro_obf/c_macro_templates.ml
   Typed C++20 / C11 EDSL Declarations for Base Obfuscation Macros *)

open Cpp_codegen.Cpp_ast
open Cpp_codegen.Cpp_dsl
open Cpp_codegen.Cpp_printer
open Random_visa_constants.Magic_numbers

let emit_base_macro_decls ?(emit_api_hash = true) ~p () : top_decl list =
  let includes = [
    include_sys "stdint.h";
    include_sys "stddef.h";
    preproc_if "defined(__has_include)"
      [
        preproc_if "__has_include(<stdlib.h>)" [ include_sys "stdlib.h" ];
        preproc_if "__has_include(<string.h>)" [ include_sys "string.h" ];
      ]
      ~else_decls:[
        include_sys "stdlib.h";
        include_sys "string.h";
      ];
    preproc_ifndef "__cplusplus" [ include_sys "stdbool.h" ];
  ] in

  let inline_macro =
    preproc_if "defined(__GNUC__) || defined(__clang__)"
      [ raw_top ("#define " ^ p ^ "INLINE __attribute__((always_inline)) inline") ]
      ~else_decls:[
        preproc_if "defined(_MSC_VER)"
          [ raw_top ("#define " ^ p ^ "INLINE __forceinline") ]
          ~else_decls:[ raw_top ("#define " ^ p ^ "INLINE inline") ]
      ]
  in

  let decrypt_str_func =
    func_decl ~attrs:[StaticFn; AlwaysInline] (Ptr (StructType "char")) (p ^ "decrypt_str")
      [ (Ptr (StructType "char"), "buf");
        (ConstPtr UInt8, "enc");
        (SizeT, "len");
        (UInt32, "key") ]
      [
        DeclVar { align_as = None; is_static = false; is_thread_local = false; is_const = false;
                  is_constexpr = false; is_volatile = true; ty = UInt32; name = "vkey"; init = Some (var "key") };
        DeclVar { align_as = None; is_static = false; is_thread_local = false; is_const = false;
                  is_constexpr = false; is_volatile = true; ty = ConstPtr UInt8; name = "venc"; init = Some (var "enc") };
        for_range "i" (i32 0) (var "len") [
          DeclVar { align_as = None; is_static = false; is_thread_local = false; is_const = false;
                    is_constexpr = false; is_volatile = false; ty = UInt8; name = "k";
                    init = Some (c_cast UInt8 ((var "vkey" ^~ (c_cast UInt32 (var "i" *~ var "0x5DU"))) &~ var "0xFFU")) };
          idx (var "buf") (var "i") := c_cast (StructType "char") (idx (var "venc") (var "i") ^~ var "k");
        ];
        idx (var "buf") (var "len") := LitInt 0;
        ret (var "buf");
      ]
  in

  let str_macro =
    preproc_if "defined(__cplusplus)"
      [
        preproc_if "defined(_MSC_VER) && !defined(__clang__)"
          [ raw_top ("#define " ^ p ^ "STR(len, key, ...) ([&]() -> char* { \\\n    static const uint8_t _enc[] = { __VA_ARGS__ }; \\\n    char* _buf = (char*)_alloca((len) + 1); \\\n    return " ^ p ^ "decrypt_str(_buf, _enc, (len), (key)); \\\n}())") ]
          ~else_decls:[
            raw_top ("#define " ^ p ^ "STR(len, key, ...) ({ \\\n    static const uint8_t _enc[] = { __VA_ARGS__ }; \\\n    char* _buf = (char*)__builtin_alloca((len) + 1); \\\n    " ^ p ^ "decrypt_str(_buf, _enc, (len), (key)); \\\n})")
          ]
      ]
      ~else_decls:[
        preproc_if "defined(__GNUC__) || defined(__clang__)"
          [ raw_top ("#define " ^ p ^ "STR(len, key, ...) ({ \\\n    static const uint8_t _enc[] = { __VA_ARGS__ }; \\\n    char* _buf = (char*)__builtin_alloca((len) + 1); \\\n    " ^ p ^ "decrypt_str(_buf, _enc, (len), (key)); \\\n})") ]
          ~else_decls:[
            raw_top ("#define " ^ p ^ "STR(len, key, ...) ({ \\\n    static const uint8_t _enc[] = { __VA_ARGS__ }; \\\n    char* _buf = (char*)alloca((len) + 1); \\\n    " ^ p ^ "decrypt_str(_buf, _enc, (len), (key)); \\\n})")
          ]
      ]
  in

  let mba_macros = [
    comment_top "/* ------------------------------------------------------------------------- */";
    comment_top "/* 2. MIXED BOOLEAN-ARITHMETIC (MBA) MACROS (Zhou / Eyrolles Identities)     */";
    comment_top "/* ------------------------------------------------------------------------- */";
    comment_top "/* Addition: x + y = (x ^ y) + 2*(x & y) */";
    raw_top ("#define " ^ p ^ "MBA_ADD(a, b) (((a) ^ (b)) + 2 * ((a) & (b)))");
    comment_top "/* Subtraction: x - y = (x ^ y) - 2*(~x & y) */";
    raw_top ("#define " ^ p ^ "MBA_SUB(a, b) (((a) ^ (b)) - 2 * ((~(a)) & (b)))");
    comment_top "/* Bitwise XOR: x ^ y = (x | y) - (x & y) */";
    raw_top ("#define " ^ p ^ "MBA_XOR(a, b) (((a) | (b)) - ((a) & (b)))");
    comment_top "/* Bitwise AND: x y = (x + y) - (x | y) */";
    raw_top ("#define " ^ p ^ "MBA_AND(a, b) (((a) + (b)) - ((a) | (b)))");
    comment_top "/* Bitwise OR: x | y = (x ^ y) + (x & y) */";
    raw_top ("#define " ^ p ^ "MBA_OR(a, b) (((a) ^ (b)) + ((a) & (b)))");
    comment_top "/* Bitwise NOT: ~x = x ^ 0xFFFFFFFFFFFFFFFFULL */";
    raw_top ("#define " ^ p ^ "MBA_NOT(a) ((a) ^ 0xFFFFFFFFFFFFFFFFULL)");
    comment_top "/* Level 2 Nested MBA: x + y expanded through XOR and AND identities */";
    raw_top ("#define " ^ p ^ "MBA_ADD_L2(a, b) (" ^ p ^ "MBA_XOR((a), (b)) + 2 * " ^ p ^ "MBA_AND((a), (b)))");
    raw_top ("#define " ^ p ^ "MBA_SUB_L2(a, b) (" ^ p ^ "MBA_XOR((a), (b)) - 2 * " ^ p ^ "MBA_AND(" ^ p ^ "MBA_NOT(a), (b)))");
    comment_top "/* Non-Linear MBA (NLMBA): Non-linear cross-product expansion resisting 1-bit linear solvers (SiMBA/GAMBA) */";
    raw_top ("#define " ^ p ^ "NLMBA_MUL(a, b) ((((a) & (b)) * ((a) | (b))) + (((a) & (~(b))) * ((~(a)) & (b))))");
    raw_top ("#define " ^ p ^ "ZERO_INV1(a, b) ((((a) | (b)) + ((a) & (b))) - ((a) + (b)))");
    raw_top ("#define " ^ p ^ "ZERO_INV2(a, b) (((a) ^ (b)) - (((a) | (b)) - ((a) & (b))))");
    raw_top ("#define " ^ p ^ "ZERO_INV3(a, b) ((((a) & (b)) + ((a) & (~(b)))) - (a))");
  ] in

  let const_blinding = [
    comment_top "/* ------------------------------------------------------------------------- */";
    comment_top "/* 3. CONSTANT BLINDING MACROS                                              */";
    comment_top "/* ------------------------------------------------------------------------- */";
    raw_top ("#define " ^ p ^ "BLIND_U64(c1, k1, k2) ((((uint64_t)(c1) ^ (uint64_t)(k1)) + (uint64_t)(k2)) - (uint64_t)(k2))");
    raw_top ("#define " ^ p ^ "BLIND_I64(c1, k1, k2) ((int64_t)" ^ p ^ "BLIND_U64(c1, k1, k2))");
    raw_top ("#define " ^ p ^ "BLIND_I32(c1, k1, k2) ((int32_t)" ^ p ^ "BLIND_U64(c1, k1, k2))");
  ] in

  let opaque_predicates = [
    comment_top "/* ------------------------------------------------------------------------- */";
    comment_top "/* 4. POLYMORPHIC OPAQUE PREDICATES (Number-Theoretic, Modular & MBA Ring)  */";
    comment_top "/* 8 distinct invariant generators preventing AST template memorization      */";
    comment_top "/* ------------------------------------------------------------------------- */";
    raw_top ("#define " ^ p ^ "OPAQUE_P1(x) (((((uint64_t)(x)) * (((uint64_t)(x)) + 1ULL)) % 2ULL) == 0ULL)");
    raw_top ("#define " ^ p ^ "OPAQUE_P2(x) (((((uint64_t)(x)) * (((uint64_t)(x)) + 1ULL) * (((uint64_t)(x)) + 2ULL) * (((uint64_t)(x)) + 3ULL)) % 8ULL) == 0ULL)");
    raw_top ("#define " ^ p ^ "OPAQUE_P3(x) (((((((uint64_t)(x)) | 1ULL) * (((uint64_t)(x)) | 1ULL)) - 1ULL) % 8ULL) == 0ULL)");
    raw_top ("#define " ^ p ^ "OPAQUE_P4(x, y) (((((uint64_t)(x)) ^ ((uint64_t)(y))) + 2ULL * (((uint64_t)(x)) & ((uint64_t)(y)))) == (((uint64_t)(x)) + ((uint64_t)(y))))");
    raw_top ("#define " ^ p ^ "OPAQUE_P5(x) (((((uint64_t)(x)) * ((uint64_t)(x))) % 4ULL) < 2ULL)");
    raw_top ("#define " ^ p ^ "OPAQUE_P6(x, y) (((((uint64_t)(x)) & (((uint64_t)(x)) | ((uint64_t)(y))))) == ((uint64_t)(x)))");
    raw_top ("#define " ^ p ^ "OPAQUE_P7(x, y) (((((uint64_t)(x)) ^ (((uint64_t)(x)) & ((uint64_t)(y))))) == (((uint64_t)(x)) & (~((uint64_t)(y)))))");
    raw_top ("#define " ^ p ^ "OPAQUE_P8(x) ((((((uint64_t)(x)) * ((uint64_t)(x))) + ((uint64_t)(x)) + 7ULL) % 2ULL) != 0ULL)");
    raw_top ("#define " ^ p ^ "OPAQUE_TRUE(x) (" ^ p ^ "OPAQUE_P1(x) && " ^ p ^ "OPAQUE_P3(x) && " ^ p ^ "OPAQUE_P5(x))");
    raw_top ("#define " ^ p ^ "OPAQUE_FALSE(x) (!(" ^ p ^ "OPAQUE_TRUE(x)))");
    raw_top ("#define " ^ p ^ "OPAQUE_TRUE_2(x, y) (" ^ p ^ "OPAQUE_P4(x, y) && " ^ p ^ "OPAQUE_P6(x, y) && " ^ p ^ "OPAQUE_P7(x, y))");
    raw_top ("#define " ^ p ^ "OPAQUE_FALSE_2(x, y) (!(" ^ p ^ "OPAQUE_TRUE_2(x, y)))");
    raw_top ("#define " ^ p ^ "IF_OPAQUE(x, true_body, false_body) do { \\\n    if (" ^ p ^ "OPAQUE_TRUE(x)) { true_body; } else { false_body; } \\\n} while(0)");
    raw_top ("#define " ^ p ^ "IF_OPAQUE_2(x, y, true_body, false_body) do { \\\n    if (" ^ p ^ "OPAQUE_TRUE_2(x, y)) { true_body; } else { false_body; } \\\n} while(0)");
  ] in

  let cff_dsl = [
    comment_top "/* ------------------------------------------------------------------------- */";
    comment_top "/* 5. CONTROL-FLOW FLATTENING (CFF) PREPROCESSOR DSL                        */";
    comment_top "/* ------------------------------------------------------------------------- */";
    raw_top ("#define " ^ p ^ "CFF_BEGIN(state_var, init_state) \\\n    uint32_t state_var = (init_state); \\\n    while (state_var != 0U) { \\\n        switch (state_var) {");
    raw_top ("#define " ^ p ^ "CFF_STATE(state_id) case (state_id):");
    raw_top ("#define " ^ p ^ "CFF_NEXT(state_var, next_state) do { \\\n    state_var = (next_state); \\\n} while(0); break");
    raw_top ("#define " ^ p ^ "CFF_EXIT(state_var) do { \\\n    state_var = 0U; \\\n} while(0); break");
    raw_top ("#define " ^ p ^ "CFF_END() \\\n        default: \\\n            state_var = 0U; \\\n            break; \\\n        } \\\n    }");
  ] in

  let region_protection = [
    comment_top "/* ------------------------------------------------------------------------- */";
    comment_top "/* 6. MARKER-BASED REGION PROTECTION (VMProtect Style SDK)                   */";
    comment_top "/* ------------------------------------------------------------------------- */";
    preproc_if "defined(__GNUC__) || defined(__clang__)"
      [
        preproc_if "defined(__arm64__) || defined(__aarch64__)"
          [
            raw_top "#define ASGARD_BEGIN_VIRTUALIZE(tag) \\\n        __asm__ volatile (\"b 1f \\n\\t .ascii \\\"ASGARD_BEG_V____\\\" \\n\\t .balign 4 \\n 1:\\n\\t\" ::: \"memory\")";
            raw_top "#define ASGARD_BEGIN_MUTATION(tag) \\\n        __asm__ volatile (\"b 1f \\n\\t .ascii \\\"ASGARD_BEG_M____\\\" \\n\\t .balign 4 \\n 1:\\n\\t\" ::: \"memory\")";
            raw_top "#define ASGARD_BEGIN_ULTRA(tag) \\\n        __asm__ volatile (\"b 1f \\n\\t .ascii \\\"ASGARD_BEG_U____\\\" \\n\\t .balign 4 \\n 1:\\n\\t\" ::: \"memory\")";
            raw_top "#define ASGARD_BEGIN_PER_ISA(tag) \\\n        __asm__ volatile (\"b 1f \\n\\t .ascii \\\"ASGARD_BEG_P____\\\" \\n\\t .balign 4 \\n 1:\\n\\t\" ::: \"memory\")";
            raw_top "#define ASGARD_BEGIN_RANDOM_ISA(tag) ASGARD_BEGIN_PER_ISA(tag)";
            raw_top "#define ASGARD_BEGIN_POLY_ISA(tag)   ASGARD_BEGIN_PER_ISA(tag)";
            raw_top "#define ASGARD_END() \\\n        __asm__ volatile (\"b 1f \\n\\t .ascii \\\"ASGARD_END______\\\" \\n\\t .balign 4 \\n 1:\\n\\t\" ::: \"memory\")";
          ]
          ~else_decls:[
            raw_top "#define ASGARD_BEGIN_VIRTUALIZE(tag) \\\n        __asm__ volatile (\"jmp 1f \\n\\t .ascii \\\"ASGARD_BEG_V__\\\" \\n 1:\\n\\t\" ::: \"memory\")";
            raw_top "#define ASGARD_BEGIN_MUTATION(tag) \\\n        __asm__ volatile (\"jmp 1f \\n\\t .ascii \\\"ASGARD_BEG_M__\\\" \\n 1:\\n\\t\" ::: \"memory\")";
            raw_top "#define ASGARD_BEGIN_ULTRA(tag) \\\n        __asm__ volatile (\"jmp 1f \\n\\t .ascii \\\"ASGARD_BEG_U__\\\" \\n 1:\\n\\t\" ::: \"memory\")";
            raw_top "#define ASGARD_BEGIN_PER_ISA(tag) \\\n        __asm__ volatile (\"jmp 1f \\n\\t .ascii \\\"ASGARD_BEG_P__\\\" \\n 1:\\n\\t\" ::: \"memory\")";
            raw_top "#define ASGARD_BEGIN_RANDOM_ISA(tag) ASGARD_BEGIN_PER_ISA(tag)";
            raw_top "#define ASGARD_BEGIN_POLY_ISA(tag)   ASGARD_BEGIN_PER_ISA(tag)";
            raw_top "#define ASGARD_END() \\\n        __asm__ volatile (\"jmp 1f \\n\\t .ascii \\\"ASGARD_END____\\\" \\n 1:\\n\\t\" ::: \"memory\")";
          ]
      ]
      ~else_decls:[
        raw_top "#define ASGARD_BEGIN_VIRTUALIZE(tag)";
        raw_top "#define ASGARD_BEGIN_MUTATION(tag)";
        raw_top "#define ASGARD_BEGIN_ULTRA(tag)";
        raw_top "#define ASGARD_BEGIN_PER_ISA(tag)";
        raw_top "#define ASGARD_BEGIN_RANDOM_ISA(tag)";
        raw_top "#define ASGARD_BEGIN_POLY_ISA(tag)";
        raw_top "#define ASGARD_END()";
      ]
  ] in

  let api_hash_decls =
    if emit_api_hash then [
      comment_top "/* ------------------------------------------------------------------------- */";
      comment_top "/* 7. COMPILE-TIME API HASHING & DYNAMIC RESOLUTION (IAT Elimination)        */";
      comment_top "/* ------------------------------------------------------------------------- */";
      func_decl ~attrs:[StaticFn; InlineFn] UInt32 (p ^ "hash_api_str")
        [ (ConstPtr (StructType "char"), "str") ]
        [
          DeclVar { align_as = None; is_static = false; is_thread_local = false; is_const = false;
                    is_constexpr = false; is_volatile = false; ty = UInt32; name = "hash"; init = Some (var ((to_c_literal32 fnv1a_32_offset_basis))) };
          while_loop (deref (var "str")) [
            var "hash" := var "hash" ^~ (c_cast UInt8 (deref (var "str++")));
            var "hash" := var "hash" *~ var (to_c_literal32 fnv1a_32_prime);
          ];
          ret (var "hash");
        ];
      preproc_if "(defined(__APPLE__) || defined(__linux__)) && !defined(_MSC_VER)"
        [
          include_sys "dlfcn.h";
          func_decl ~attrs:[StaticFn; InlineFn] (Ptr Void) (p ^ "resolve_api_by_hash")
            [ (ConstPtr (ConstPtr (StructType "char")), "known_symbols");
              (SizeT, "count");
              (UInt32, "target_hash") ]
            [
              for_range "i" (i32 0) (var "count") [
                if_then (call (p ^ "hash_api_str") [idx (var "known_symbols") (var "i")] ==~ var "target_hash") [
                  ret (call "dlsym" [var "RTLD_DEFAULT"; idx (var "known_symbols") (var "i")]);
                ];
              ];
              ret (c_cast (Ptr Void) (i32 0));
            ]
        ]
    ] else []
  in

  includes
  @ [ inline_macro ]
  @ [ comment_top "/* 1. STACK STRING ENCRYPTION (Alloca / Compound Literal Decryption)         */" ]
  @ [ decrypt_str_func; str_macro ]
  @ mba_macros
  @ const_blinding
  @ opaque_predicates
  @ cff_dsl
  @ region_protection
  @ api_hash_decls

let emit_base_macros ?(emit_api_hash = true) b ~p =
  let decls = emit_base_macro_decls ~emit_api_hash ~p () in
  Buffer.add_string b (render_top_decls decls ^ "\n")
