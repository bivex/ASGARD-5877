open Cpp_codegen.Cpp_ast
open Cpp_codegen.Cpp_dsl
open Cpp_codegen.Cpp_printer
open Random_visa_constants.Magic_numbers

let emit_context_decls ?(context_epochs = 4) ~key_seed ~reg_perm ~stride ~offset ~enable_running_key ~enable_stack_scramble ~enable_mem_sanitize () : top_decl list =
  ignore enable_running_key;

  let gpr_names = [|
    "REG_RAX"; "REG_RCX"; "REG_RDX"; "REG_RBX"; "REG_RSP"; "REG_RBP"; "REG_RSI"; "REG_RDI";
    "REG_R8";  "REG_R9";  "REG_R10"; "REG_R11"; "REG_R12"; "REG_R13"; "REG_R14"; "REG_R15";
    "REG_VTMP0"; "REG_VTMP1"; "REG_VTMP2"; "REG_VTMP3"; "REG_VIP"; "REG_VSP"; "REG_VKEY";
    "REG_VX18"; "REG_VX19"; "REG_VX20"; "REG_VX21"; "REG_VX22"; "REG_VX23"; "REG_VX24"; "REG_VX25"; "REG_VX26"
  |] in

  (* 1. Randomized Architectural Register Map (π ∈ S_32) *)
  let enum_reg_map = enum_decl ~underlying_ty:UInt8 "RegMap" (
    Array.to_list (Array.mapi (fun i name -> (name, Some (i32 reg_perm.(i)))) gpr_names)
  ) in

  (* 2. SplitMix64 Cryptographic Key Derivation *)
  let fn_key64 = FuncDecl {
    attrs = [AlwaysInline; NoExcept; StaticFn];
    ret_type = UInt64;
    name = "key64_for_offset";
    params = [(UInt32, "seed"); (SizeT, "offset")];
    body = [
      let_u64 "s64" (cast UInt64 (var "seed"));
      let_u64 "x0" (((var "s64" <<~ u64 32L) |~ (var "s64" ^~ u64 golden_ratio_32)) ^~ (cast UInt64 (var "offset") *~ u64 sqrt2_fraction_64));
      let_u64 "x1" ((var "x0" ^~ (var "x0" >>~ u64 30L)) *~ u64 splitmix64_gamma);
      let_u64 "x2" ((var "x1" ^~ (var "x1" >>~ u64 27L)) *~ u64 splitmix64_mix);
      ret (var "x2" ^~ (var "x2" >>~ u64 31L));
    ];
  } in

  (* 3. Compute Handlers Integrity Hash *)
  let fn_handlers_hash = FuncDecl {
    attrs = [AlwaysInline; NoExcept; StaticFn];
    ret_type = UInt64;
    name = "compute_handlers_hash";
    params = [(ConstPtr UIntPtr, "all_domains"); (SizeT, "num_domains")];
    body = [
      let_u64 "h" (u64 salt_xwcafe_cafebabe1337);
      for_range "d" (u64 0L) (var "num_domains") [
        for_range "op" (u64 0L) (u64 256L) [
          let_u64 "ptr_val" (cast UInt64 (idx (var "all_domains") ((var "d" *~ u64 256L) +~ var "op")));
          (var "h" ^= (var "ptr_val" *~ u64 golden_ratio_64));
          (var "h" := ((var "h" >>~ u64 27L) |~ (var "h" <<~ u64 37L)));
          (var "h" *= u64 splitmix64_gamma);
        ];
      ];
      (var "h" ^= call "asgard_mem_integrity::compute_section_integrity_hash" []);
      ret (var "h" ^~ (var "h" >>~ u64 31L));
    ];
  } in

  (* 4. VMContext Structure with Affine Register Map & Security Guards *)
  let affine_a = ((Int32.to_int (Int32.shift_right_logical key_seed 16)) land 0x1E) lor 1 in
  let affine_b = (Int32.to_int key_seed) land 31 in

  let num_epochs = max 1 context_epochs in
  let sched = Context_permutation.gen_epoch_schedule
    (Random.State.make [| Int32.to_int key_seed; 0x1337 |]) ~n_regs:16 ~n_epochs:num_epochs in

  let rotate_cases =
    let cases = ref [] in
    for from_e = 0 to num_epochs - 1 do
      for to_e = 0 to num_epochs - 1 do
        if from_e <> to_e then begin
          let target = Array.init 16 (fun s ->
            let r = sched.inv_perms.(from_e).(s) in
            sched.epoch_perms.(to_e).(r)
          ) in
          let swaps = Context_permutation.decompose_into_swaps target in
          let swap_stmts = List.fold_left (fun acc (u, v) ->
            let idx_u = call "reg_phys_idx" [i32 u] in
            let idx_v = call "reg_phys_idx" [i32 v] in
            acc @ [
              expr_stmt (call "std::swap" [idx (var "gprs") idx_u; idx (var "gprs") idx_v]);
              expr_stmt (call "std::swap" [idx (var "slot_masks") idx_u; idx (var "slot_masks") idx_v]);
            ]
          ) [] swaps in
          cases.contents <- (i32 ((from_e lsl 2) lor to_e), swap_stmts @ [ break_stmt ]) :: cases.contents;
        end
      done
    done;
    List.rev cases.contents
  in

  let vm_context_members : struct_member list = [
    member_static_constexpr UInt64 "CANARY_VAL" (u64 salt_cafebabe_leet);
    member_field ~init:(var "CANARY_VAL") UInt64 "canary_head";
    member_field (Array (UInt64, 32)) "mid_canaries";
    member_field (Array (UInt64, 32)) "gprs";
    member_field (Array (UInt64, 32)) "slot_masks";
    member_field (Array (Array (UInt64, 8), 32)) "vregs";
    member_field (Array (UInt64, 512)) "stack";
    member_field SizeT "sp";
    member_field UInt64 "reg_mask";
    member_field UInt32 "init_seed";
    member_field UInt64 "poison_penalty";
    member_field UInt64 "running_key";
    member_field ~init:(u64 salt_xwcafe_leetbeef) UInt64 "data_key";
    (* The shadow stack pointer of the CET extensions (RDSSP, INCSSP). *)
    member_field ~init:(u64 0x50000000L) UInt64 "ssp";
    member_field Bool "cf";
    (* ARM64-view carry: C = NOT borrow after SUB-family flag writers,
       carry-out after ADD-family.  ctx.cf stays in the x86 convention
       (CF = borrow) for eval_condition; ADC/SBC words tagged with the
       ARM64 dialect read this shadow instead (todo item 8). *)
    member_field Bool "cf_arm64";
    member_field Bool "zf";
    member_field Bool "sf";
    member_field Bool "of";
    member_field Bool "pf";
    member_field Bool "trapped";
    member_field SizeT "executed_instructions";
    member_field ~init:(var "CANARY_VAL") UInt64 "canary_tail";
    member_field ~init:(u64 0L) UInt64 "decoy_sink";
    member_field (Array (UInt64, 64)) "oblivious_frame";
    (* x87 FPU circular register stack (8 doubles), top pointer and status word *)
    member_field (Array (Double, 8)) "fpu_stack";
    member_field ~init:(i32 0) UInt8 "fpu_top";
    member_field ~init:(i32 0) UInt16 "fpu_status";
    member_field ~init:(i32 0) UInt8 "macro_salt";
    member_field (Array (UInt64, 32)) "decoy_regs";
    member_field ~init:(i32 1) Int32 "format_version_tag";
    member_field ~init:(u32 0l) UInt32 "analysis_pressure";
    member_field ~init:(i32 0) UInt8 "pressure_tier";
    member_field ~init:(u64 0L) UInt64 "last_step_tsc";

    member_method ~attrs:[AlwaysInline; NoExcept] Void "check_analysis_pressure" [(UInt64, "delta_cycles")] [
      raw ({|if (__builtin_expect(delta_cycles > 2000000ULL, 0)) {
        analysis_pressure++;
        if (__builtin_expect(analysis_pressure >= 4, 0)) {
            analysis_pressure = 0;
            pressure_tier = (pressure_tier + 1) & 3;
            data_key ^= |} ^
        (to_c_literal salt_xwcafe_leetbeef) ^
        {|;
        }
    }|});
    ];

    member_method ~attrs:[AlwaysInline; NoExcept] Void "set_macro_salt" [(UInt8, "s")] [
      (var "macro_salt" := var "s");
    ];

    (* Affine Register Mapping Constants & Helper *)
    member_static_constexpr SizeT "REG_AFFINE_A" (i32 affine_a);
    member_static_constexpr SizeT "REG_AFFINE_B" (i32 affine_b);
    member_method ~attrs:[AlwaysInline; NoExcept] ~is_static:true UInt8 "reg_phys_idx" [(UInt8, "i")] [
      ret (cast UInt8 (((cast SizeT (var "i" &~ i32 31) *~ var "REG_AFFINE_A") +~ var "REG_AFFINE_B") &~ i32 31));
    ];

    (* VMContext Initialization *)
    member_method ~attrs:[AlwaysInline; NoExcept] Void "init" [(UInt32, "seed = asgard_wbox_derive_seed()")] [
      (var "init_seed" := var "seed");
      (var "poison_penalty" := ((call "key64_for_offset" [var "seed"; u64 0x5877L] ^~ u64 salt_poison_penalty) |~ u64 1L));
      (var "running_key" := (call "key64_for_offset" [var "seed"; u64 salt_leet_13375877] ^~ u64 salt_cafebabe_leet));
      (var "reg_mask" := (u64 salt_regmask ^~ (cast UInt64 (var "seed") *~ u64 golden_ratio_64)));
      (var "data_key" := (call "key64_for_offset" [var "seed"; u64 0x5877A5A5L] ^~ u64 salt_xwcafe_leetbeef));
      (var "macro_salt" := i32 0);
      (var "format_version_tag" := (cast Int32 (call "key64_for_offset" [var "seed"; u64 0x7758L] &~ u64 0x7FFFFFFFL)) +~ i32 1);
      for_range "d" (u64 0L) (u64 32L) [
        (idx (var "decoy_regs") (var "d") := (call "key64_for_offset" [var "seed"; u64 0xDEC00000L +~ var "d"]));
      ];
      for_range "i" (u64 0L) (u64 32L) [
        (idx (var "slot_masks") (var "i") := (call "key64_for_offset" [var "seed"; u64 0x1000L +~ var "i"] ^~ u64 salt_canary_mid));
        (idx (var "gprs") (var "i") := (idx (var "slot_masks") (var "i") ^~ var "reg_mask"));
        (idx (var "mid_canaries") (var "i") := (var "CANARY_VAL" ^~ (cast UInt64 (var "i") *~ u64 sqrt2_fraction_64) ^~ cast UInt64 (var "seed")));
        (idx (idx (var "vregs") (var "i")) (i32 0) := u64 0L);
        for_range "v" (u64 1L) (u64 8L) [
          (idx (idx (var "vregs") (var "i")) (var "v") := u64 0L);
        ];
      ];
      (var "sp" := u64 0L);
      (var "cf" := bool_lit false); (var "zf" := bool_lit false);
      (var "cf_arm64" := bool_lit false);
      (var "sf" := bool_lit false); (var "of" := bool_lit false);
      (var "pf" := bool_lit false);
      (var "trapped" := bool_lit false);
      (var "executed_instructions" := u64 0L);
      (var "canary_head" := var "CANARY_VAL");
      (var "canary_tail" := var "CANARY_VAL");
      (var "decoy_sink" := u64 0L);
      for_range "i" (u64 0L) (u64 64L) [
        (idx (var "oblivious_frame") (var "i") := u64 0L);
      ];
      (var "fpu_top" := i32 0);
      (var "fpu_status" := i32 0);
      for_range "i" (u64 0L) (u64 8L) [
        (idx (var "fpu_stack") (var "i") := i32 0);
      ];
      (var "analysis_pressure" := u32 0l);
      (var "pressure_tier" := i32 0);
      (var "last_step_tsc" := u64 0L);
    ];

    (* Rolling Key Derivations *)
    member_method ~attrs:[AlwaysInline; NoExcept] ~is_static:true UInt64 "advance_key_step"
      [(UInt64, "k"); (UInt8, "op"); (UInt8, "dst"); (Int64, "imm")] [
      let_u64 "x" (var "k" ^~ (((cast UInt64 (var "op") *~ u64 golden_ratio_64) +~ (cast UInt64 (var "dst") <<~ u64 24L)) +~ cast UInt64 (var "imm")));
      let_u64 "rot" ((var "x" >>~ u64 23L) |~ (var "x" <<~ u64 41L));
      ret ((var "rot" *~ u64 splitmix64_gamma) ^~ u64 salt_xwcafe_leetbeef);
    ];

    member_method ~attrs:[AlwaysInline; NoExcept] Void "advance_running_key"
      [(UInt8, "op"); (UInt8, "dst"); (Int64, "imm")] [
      (var "running_key" := call "advance_key_step" [var "running_key"; var "op"; var "dst"; var "imm"]);
    ];
    member_method ~attrs:[AlwaysInline; NoExcept] ~is_static:true UInt64 "advance_data_key_step"
      [(UInt64, "data_k"); (UInt64, "res_val")] [
      let_u64 "rot" ((var "data_k" >>~ u64 47L) |~ (var "data_k" <<~ u64 17L));
      ret (var "rot" ^~ (var "res_val" *~ u64 golden_ratio_64));
    ];

    member_method ~attrs:[AlwaysInline; NoExcept] Void "advance_data_key"
      [(UInt64, "res_val")] [
      (var "data_key" := call "advance_data_key_step" [var "data_key"; var "res_val"]);
    ];

    member_method ~attrs:[AlwaysInline; NoExcept] ~is_static:true UInt64 "anchor_key"
      [(UInt32, "seed"); (UInt64, "off"); (UInt64, "addr_hash = 0")] [
      ret (call "key64_for_offset" [var "seed" ^~ u32 murmur3_32_c1; cast SizeT (var "off" ^~ u64 salt_leet_13375877)] ^~ var "addr_hash");
    ];

    member_method ~attrs:[AlwaysInline; NoExcept] Void "reanchor_running_key"
      [(UInt64, "off"); (UInt64, "addr_hash = 0")] [
      (var "running_key" := call "anchor_key" [var "init_seed"; var "off"; var "addr_hash"]);
    ];

    member_method ~attrs:[AlwaysInline; NoExcept] ~is_static:true UInt64 "poly_hash64" [(UInt64, "x")] [
      let_u64 "x1" ((var "x" ^~ (var "x" >>~ u64 30L)) *~ u64 splitmix64_gamma);
      let_u64 "x2" ((var "x1" ^~ (var "x1" >>~ u64 27L)) *~ u64 splitmix64_mix);
      ret (var "x2" ^~ (var "x2" >>~ u64 31L));
    ];

    member_method ~attrs:[AlwaysInline; NoExcept] ~is_static:true UInt64 "branch_invariant_poly_update"
      [(UInt64, "key"); (UInt64, "delta"); (UInt64, "poly_const")] [
      let_u64 "c" (var "poly_const" |~ u64 1L);
      ret (call "poly_hash64" [var "key" ^~ (var "c" *~ var "delta")]);
    ];

    member_method ~attrs:[AlwaysInline; NoExcept] Void "apply_poly_merge_update"
      [(UInt64, "delta"); (UInt64, "poly_const")] [
      (var "running_key" := call "branch_invariant_poly_update" [var "running_key"; var "delta"; var "poly_const"]);
    ];

    member_method ~attrs:[AlwaysInline; NoExcept] ~is_const:true UInt64 "get_vkey" [] [
      ret (var "running_key");
    ];

    (* Dynamic Canary Guard Validator *)
    member_method ~attrs:[AlwaysInline; NoExcept] ~is_const:true Bool "verify_canaries" [] [
      if_then ((var "canary_head" <>~ var "CANARY_VAL") ||~ (var "canary_tail" <>~ var "CANARY_VAL")) [
        ret (bool_lit false);
      ];
      decl_var ~init:((var "sp" >>~ u64 4L) &~ u64 31L) SizeT "frame";
      let_u64 "expected" ((var "CANARY_VAL" ^~ (cast UInt64 (var "frame") *~ u64 sqrt2_fraction_64)) ^~ cast UInt64 (var "init_seed"));
      ret (idx (var "mid_canaries") (var "frame") ==~ var "expected");
    ];

    (* Register Accessors with Per-Slot Masking and Affine Permutation *)
    member_method ~attrs:[AlwaysInline; NoExcept] ~is_const:true UInt64 "get_reg" [(UInt8, "i")] [
      decl_var ~init:(cast SizeT (call "reg_phys_idx" [var "i"])) SizeT "idx";
      ret ((idx (var "gprs") (var "idx") ^~ idx (var "slot_masks") (var "idx")) ^~ var "reg_mask");
    ];

    member_method ~attrs:[AlwaysInline; NoExcept] Void "set_reg" [(UInt8, "i"); (UInt64, "v")] [
      decl_var ~init:(cast SizeT (call "reg_phys_idx" [var "i"])) SizeT "idx";
      let_u64 "new_m" ((idx (var "slot_masks") (var "idx") ^~ var "running_key") *~ u64 golden_ratio_64);
      (idx (var "slot_masks") (var "idx") := var "new_m");
      (idx (var "gprs") (var "idx") := (var "v" ^~ var "new_m" ^~ var "reg_mask"));
      expr_stmt (call "advance_data_key" [var "v"]);
    ];

    member_method ~attrs:[AlwaysInline; NoExcept] Void "evolve_slot_mask" [(UInt8, "i"); (UInt32, "k")] [
      decl_var ~init:(cast SizeT (call "reg_phys_idx" [var "i"])) SizeT "idx";
      let_u64 "cur_val" (idx (var "gprs") (var "idx") ^~ idx (var "slot_masks") (var "idx") ^~ var "reg_mask");
      let_u64 "delta" ((cast UInt64 (var "k") *~ u64 cbrt3_fraction_64) ^~ (cast UInt64 (var "idx") *~ u64 sqrt2_fraction_64));
      (idx (var "slot_masks") (var "idx") := (idx (var "slot_masks") (var "idx") ^~ var "delta") *~ u64 splitmix64_gamma);
      (idx (var "gprs") (var "idx") := var "cur_val" ^~ idx (var "slot_masks") (var "idx") ^~ var "reg_mask");
    ];

    (* Vector Register Accessors *)
    member_method ~attrs:[AlwaysInline; NoExcept] ~is_const:true UInt64 "get_vreg_lane" [(UInt8, "i"); (SizeT, "lane")] [
      ret (idx (idx (var "vregs") (var "i" &~ i32 31)) (var "lane" &~ i32 7));
    ];

    member_method ~attrs:[AlwaysInline; NoExcept] Void "set_vreg_lane" [(UInt8, "i"); (SizeT, "lane"); (UInt64, "value")] [
      (idx (idx (var "vregs") (var "i" &~ i32 31)) (var "lane" &~ i32 7) := var "value");
    ];

    member_method ~attrs:[AlwaysInline; NoExcept] Void "set_vreg" [(UInt8, "i"); (UInt64, "lo"); (UInt64, "hi")] [
      (idx (idx (var "vregs") (var "i" &~ i32 31)) (i32 0) := var "lo");
      (idx (idx (var "vregs") (var "i" &~ i32 31)) (i32 1) := var "hi");
      for_range "v" (u64 2L) (u64 8L) [
        (idx (idx (var "vregs") (var "i" &~ i32 31)) (var "v") := u64 0L);
      ];
    ];

    (* Named Architectural Register Accessors *)
    member_method ~attrs:[AlwaysInline; NoExcept] ~is_const:true UInt64 "get_rax" [] [ ret (call "get_reg" [var "REG_RAX"]) ];
    member_method ~attrs:[AlwaysInline; NoExcept] Void "set_rax" [(UInt64, "v")] [ expr_stmt (call "set_reg" [var "REG_RAX"; var "v"]) ];
    member_method ~attrs:[AlwaysInline; NoExcept] ~is_const:true UInt64 "get_rdi" [] [ ret (call "get_reg" [var "REG_RDI"]) ];
    member_method ~attrs:[AlwaysInline; NoExcept] Void "set_rdi" [(UInt64, "v")] [ expr_stmt (call "set_reg" [var "REG_RDI"; var "v"]) ];
    member_method ~attrs:[AlwaysInline; NoExcept] ~is_const:true UInt64 "get_rsi" [] [ ret (call "get_reg" [var "REG_RSI"]) ];
    member_method ~attrs:[AlwaysInline; NoExcept] Void "set_rsi" [(UInt64, "v")] [ expr_stmt (call "set_reg" [var "REG_RSI"; var "v"]) ];
    member_method ~attrs:[AlwaysInline; NoExcept] ~is_const:true UInt64 "get_fs_base" [] [ ret (call "get_reg" [var "REG_VX25"]) ];
    member_method ~attrs:[AlwaysInline; NoExcept] Void "set_fs_base" [(UInt64, "v")] [ expr_stmt (call "set_reg" [var "REG_VX25"; var "v"]) ];
    member_method ~attrs:[AlwaysInline; NoExcept] ~is_const:true UInt64 "get_gs_base" [] [ ret (call "get_reg" [var "REG_VX26"]) ];
    member_method ~attrs:[AlwaysInline; NoExcept] Void "set_gs_base" [(UInt64, "v")] [ expr_stmt (call "set_reg" [var "REG_VX26"; var "v"]) ];
    member_method ~attrs:[AlwaysInline; NoExcept] ~is_const:true UInt64 "get_ssp" [] [ ret (var "ssp") ];
    member_method ~attrs:[AlwaysInline; NoExcept] Void "set_ssp" [(UInt64, "v")] [ var "ssp" := var "v" ];

    (* x87 FPU Register Accessors *)
    member_method ~attrs:[AlwaysInline; NoExcept] ~is_const:true Double "get_st" [(UInt8, "i")] [
      ret (idx (var "fpu_stack") (((cast SizeT (var "fpu_top") +~ cast SizeT (var "i" &~ i32 7))) &~ i32 7));
    ];
    member_method ~attrs:[AlwaysInline; NoExcept] Void "set_st" [(UInt8, "i"); (Double, "v")] [
      (idx (var "fpu_stack") (((cast SizeT (var "fpu_top") +~ cast SizeT (var "i" &~ i32 7))) &~ i32 7) := var "v");
    ];
    member_method ~attrs:[AlwaysInline; NoExcept] Void "fpu_push" [(Double, "v")] [
      (var "fpu_top" := cast UInt8 ((cast SizeT (var "fpu_top") +~ i32 7) &~ i32 7));
      (idx (var "fpu_stack") (cast SizeT (var "fpu_top")) := var "v");
    ];
    member_method ~attrs:[AlwaysInline; NoExcept] Double "fpu_pop" [] [
      decl_var Double "val" ~init:(idx (var "fpu_stack") (cast SizeT (var "fpu_top")));
      (var "fpu_top" := cast UInt8 ((cast SizeT (var "fpu_top") +~ i32 1) &~ i32 7));
      ret (var "val");
    ];
    member_method ~attrs:[AlwaysInline; NoExcept] ~is_const:true UInt16 "get_fsw" [] [
      ret (cast UInt16 ((var "fpu_status" &~ i32 0xC7FF) |~ (cast UInt16 (var "fpu_top" &~ i32 7) <<~ i32 11)));
    ];
    member_method ~attrs:[AlwaysInline; NoExcept] Void "set_fsw" [(UInt16, "sw")] [
      (var "fpu_status" := var "sw");
    ];

    (* RNS-4 Residue Arithmetic Engine *)
    member_method ~attrs:[AlwaysInline; NoExcept] ~is_const:true UInt64 "rns_add" [(UInt64, "a"); (UInt64, "b")] [
      ret (call "asgard_rns::decode" [call "asgard_rns::add" [call "asgard_rns::encode" [var "a"]; call "asgard_rns::encode" [var "b"]]]);
    ];
    member_method ~attrs:[AlwaysInline; NoExcept] ~is_const:true UInt64 "rns_sub" [(UInt64, "a"); (UInt64, "b")] [
      ret (call "asgard_rns::decode" [call "asgard_rns::sub" [call "asgard_rns::encode" [var "a"]; call "asgard_rns::encode" [var "b"]]]);
    ];
    member_method ~attrs:[AlwaysInline; NoExcept] ~is_const:true UInt64 "rns_mul" [(UInt64, "a"); (UInt64, "b")] [
      ret (call "asgard_rns::decode" [call "asgard_rns::mul" [call "asgard_rns::encode" [var "a"]; call "asgard_rns::encode" [var "b"]]]);
    ];

    (* Global Mask Evolution *)
    member_method ~attrs:[AlwaysInline; NoExcept] Void "evolve_mask" [(UInt32, "k")] [
      let_u64 "delta" ((cast UInt64 (var "k") *~ u64 cbrt3_fraction_64) ^~ u64 0x1337L);
      let_u64 "old_mask" (var "reg_mask");
      let_u64 "new_mask" ((var "reg_mask" ^~ var "delta") +~ u64 0x5877L);
      for_range "i" (u64 0L) (u64 32L) [
        (idx (var "gprs") (var "i") := (idx (var "gprs") (var "i") ^~ var "old_mask") ^~ var "new_mask");
      ];
      (var "reg_mask" := var "new_mask");
    ];

    (* Dynamic Epoch Rotation *)
    member_method ~attrs:[AlwaysInline; NoExcept] Void "rotate_registers_epoch" [(UInt32, "from_ep"); (UInt32, "to_ep")] [
      decl_var ~init:(((var "from_ep" &~ i32 3) <<~ i32 2) |~ (var "to_ep" &~ i32 3)) UInt32 "tr";
      switch (var "tr") rotate_cases (Some [ break_stmt ]);
    ];

    (* Virtual Stack Scrambling *)
    member_static_constexpr SizeT "STACK_SIZE" (i32 512);
    member_static_constexpr SizeT "STACK_STRIDE" (i32 stride);
    member_static_constexpr SizeT "STACK_OFFSET" (i32 offset);

    member_method ~attrs:[AlwaysInline; NoExcept] ~is_const:true SizeT "scramble_stack_idx" [(SizeT, "index")] [
      ret (if enable_stack_scramble then
        cast SizeT (((var "index" *~ var "STACK_STRIDE") +~ var "STACK_OFFSET") &~ (var "STACK_SIZE" -~ i32 1))
      else
        var "index");
    ];

    member_method ~attrs:[AlwaysInline; NoExcept] Void "push" [(UInt64, "v")] [
      if_then (log_not (call "verify_canaries" [])) [
        (var "reg_mask" ^= var "poison_penalty");
        (var "trapped" := bool_lit true);
      ];
      if_then (var "sp" <~ var "STACK_SIZE") [
        decl_var ~init:(call "scramble_stack_idx" [var "sp"]) SizeT "phys_idx";
        let_u64 "enc_mask" ((cast UInt64 (var "sp") *~ u64 golden_ratio_64) ^~ u64 salt_canary_stack);
        (idx (var "stack") (var "phys_idx") := var "v" ^~ var "enc_mask");
        (var "sp" += i32 1);
      ];
    ];

    member_method ~attrs:[AlwaysInline; NoExcept] UInt64 "pop" [] ([
      if_then (log_not (call "verify_canaries" [])) [
        (var "reg_mask" ^= var "poison_penalty");
        (var "trapped" := bool_lit true);
      ];
      if_then (var "sp" >~ i32 0) ([
        (var "sp" -= i32 1);
        decl_var ~init:(call "scramble_stack_idx" [var "sp"]) SizeT "phys_idx";
        let_u64 "enc_mask" ((cast UInt64 (var "sp") *~ u64 golden_ratio_64) ^~ u64 salt_canary_stack);
        let_u64 "val" (idx (var "stack") (var "phys_idx") ^~ var "enc_mask");
      ] @ (if enable_mem_sanitize then [
        (idx (var "stack") (var "phys_idx") := u64 salt_deadbeef_cafe1337 ^~ var "enc_mask");
      ] else []) @ [
        ret (var "val");
      ]);
      ret (u64 0L);
    ]);

    (* Oblivious Frame Scratchpad Engine *)
    member_method ~attrs:[AlwaysInline; NoExcept] Void "oblivious_frame_store" [(SizeT, "logical_idx"); (UInt64, "v")] [
      preproc_if_stmt "defined(ASGARD_OBLIVIOUS_MEM)" [
        decl_var SizeT "p_idx" ~init:(call "asgard::oblivious_mem::logical_to_physical_slot" [var "logical_idx" &~ i32 63; i32 37; i32 17; i32 64]);
        let_u64 "mask" (call "asgard::oblivious_mem::slot_tweak_mask" [var "running_key"; var "logical_idx" &~ i32 63]);
        (idx (var "oblivious_frame") (var "p_idx") := (var "v" ^~ var "mask"));
        (var "decoy_sink" := (var "v" ^~ u64 salt_xwcafe_leetbeef));
      ] ~else_stmts:[
        (idx (var "oblivious_frame") (var "logical_idx" &~ i32 63) := var "v");
      ]
    ];

    member_method ~attrs:[AlwaysInline; NoExcept] ~is_const:true UInt64 "oblivious_frame_load" [(SizeT, "logical_idx")] [
      preproc_if_stmt "defined(ASGARD_OBLIVIOUS_MEM)" [
        decl_var SizeT "p_idx" ~init:(call "asgard::oblivious_mem::logical_to_physical_slot" [var "logical_idx" &~ i32 63; i32 37; i32 17; i32 64]);
        decl_var SizeT "quad_base_idx" ~init:(var "p_idx" &~ bit_not (cast SizeT (i32 3)));
        decl_var SizeT "target_slot" ~init:(var "p_idx" &~ i32 3);
        let_u64 "raw_val" (call "asgard::oblivious_mem::oblivious_read_quad" [
          addr_of (idx (var "oblivious_frame") (var "quad_base_idx"));
          var "target_slot";
        ]);
        let_u64 "mask" (call "asgard::oblivious_mem::slot_tweak_mask" [var "running_key"; var "logical_idx" &~ i32 63]);
        ret (var "raw_val" ^~ var "mask");
      ] ~else_stmts:[
        ret (idx (var "oblivious_frame") (var "logical_idx" &~ i32 63));
      ]
    ];

    (* Multi-VM Domain morphing *)
    member_field ~init:(u64 0x53B7D9F7A1B4283EL) UInt64 "trace_digest";
    member_field (Array (UInt64, 16)) "bridge_state";

    member_raw ("    inline void morph_math_to_flow(uint64_t target_digest = 0) noexcept {
#if defined(ASGARD_MULTI_VM_ENABLED)
        uint64_t dig = target_digest ? target_digest : trace_digest;
        uint64_t regs[16];
        for (int i = 0; i < 16; ++i) regs[i] = get_reg(i);
        in_place_morph_math_to_flow(regs, bridge_state, dig);
        trace_digest = bridge_rol64(dig, 13) ^ " ^
        (to_c_literal salt_xwcafe) ^
        ";
#else
        (void)target_digest;
#endif
    }");

    member_raw ("    inline void morph_flow_to_math(uint64_t target_digest = 0) noexcept {
#if defined(ASGARD_MULTI_VM_ENABLED)
        uint64_t dig = target_digest ? target_digest : (bridge_rol64(trace_digest, 51) ^ " ^
        (to_c_literal salt_xwcafe) ^
        ");
        uint64_t regs[16];
        for (int i = 0; i < 16; ++i) regs[i] = get_reg(i);
        in_place_morph_flow_to_math(bridge_state, regs, dig);
        trace_digest = dig;
#else
        (void)target_digest;
#endif
    }");
  ] in

  let struct_vm_context = struct_def "VMContext" vm_context_members in

  (* 5. Standalone Flag Evaluation Functions *)
  let fn_eval_condition = FuncDecl {
    attrs = [AlwaysInline; NoExcept; StaticFn];
    ret_type = Bool;
    name = "eval_condition";
    params = [(ConstRef (StructType "VMContext"), "ctx"); (UInt8, "cond")];
    body = [
      switch (var "cond") [
        (i32 0,  [ ret (var "ctx.zf") ]);
        (i32 1,  [ ret (log_not (var "ctx.zf")) ]);
        (i32 2,  [ ret (var "ctx.cf") ]);
        (i32 3,  [ ret (log_not (var "ctx.cf")) ]);
        (i32 4,  [ ret (var "ctx.cf" ||~ var "ctx.zf") ]);
        (i32 5,  [ ret (log_not (var "ctx.cf") &&~ log_not (var "ctx.zf")) ]);
        (i32 6,  [ ret (var "ctx.sf") ]);
        (i32 7,  [ ret (log_not (var "ctx.sf")) ]);
        (i32 8,  [ ret (var "ctx.sf" <>~ var "ctx.of") ]);
        (i32 9,  [ ret (var "ctx.sf" ==~ var "ctx.of") ]);
        (i32 10, [ ret (var "ctx.zf" ||~ (var "ctx.sf" <>~ var "ctx.of")) ]);
        (i32 11, [ ret (log_not (var "ctx.zf") &&~ (var "ctx.sf" ==~ var "ctx.of")) ]);
        (i32 12, [ ret (var "ctx.of") ]);
        (i32 13, [ ret (log_not (var "ctx.of")) ]);
        (i32 14, [ ret (bool_lit true) ]);
        (i32 15, [ ret (var "ctx.pf") ]);
        (i32 16, [ ret (log_not (var "ctx.pf")) ]);
      ] (Some [ ret (bool_lit true) ]);
    ];
  } in

  let fn_compute_sub_flags = FuncDecl {
    attrs = [AlwaysInline; NoExcept; StaticFn];
    ret_type = Void;
    name = "compute_sub_flags";
    params = [
      (Ref (StructType "VMContext"), "ctx");
      (UInt64, "a");
      (UInt64, "b");
      (UInt32, "bits");
    ];
    body = [
      if_then_else ((var "bits" ==~ i32 0) ||~ (var "bits" >=~ i32 64)) [
        let_u64 "res" (var "a" -~ var "b");
        (var "ctx.zf" := (var "res" ==~ u64 0L));
        (var "ctx.sf" := (cast Int64 (var "res") <~ i64 0L));
        (var "ctx.cf" := (var "a" <~ var "b"));
        (var "ctx.cf_arm64" := (var "a" >=~ var "b"));
        (var "ctx.of" := ((((var "a" ^~ var "b") &~ (var "a" ^~ var "res")) >>~ u64 63L) <>~ u64 0L));
      ] [
        let_u64 "mask" ((u64 1L <<~ var "bits") -~ u64 1L);
        let_u64 "sign_bit" (u64 1L <<~ (var "bits" -~ i32 1));
        let_u64 "a_val" (var "a" &~ var "mask");
        let_u64 "b_val" (var "b" &~ var "mask");
        let_u64 "res" ((var "a_val" -~ var "b_val") &~ var "mask");
        (var "ctx.zf" := (var "res" ==~ u64 0L));
        (var "ctx.sf" := ((var "res" &~ var "sign_bit") <>~ u64 0L));
        (var "ctx.cf" := (var "a_val" <~ var "b_val"));
        (var "ctx.cf_arm64" := (var "a_val" >=~ var "b_val"));
        (var "ctx.of" := ((((var "a_val" ^~ var "b_val") &~ (var "a_val" ^~ var "res")) &~ var "sign_bit") <>~ u64 0L));
      ];
    ];
  } in

  let fn_compute_add_flags = FuncDecl {
    attrs = [AlwaysInline; NoExcept; StaticFn];
    ret_type = Void;
    name = "compute_add_flags";
    params = [
      (Ref (StructType "VMContext"), "ctx");
      (UInt64, "a");
      (UInt64, "b");
      (UInt32, "bits");
    ];
    body = [
      if_then_else ((var "bits" ==~ i32 0) ||~ (var "bits" >=~ i32 64)) [
        let_u64 "res" (var "a" +~ var "b");
        (var "ctx.zf" := (var "res" ==~ u64 0L));
        (var "ctx.sf" := (cast Int64 (var "res") <~ i64 0L));
        (var "ctx.cf" := (var "res" <~ var "a"));
        (var "ctx.cf_arm64" := (var "res" <~ var "a"));
        (var "ctx.of" := (((bit_not (var "a" ^~ var "b") &~ (var "a" ^~ var "res")) >>~ u64 63L) <>~ u64 0L));
      ] [
        let_u64 "mask" ((u64 1L <<~ var "bits") -~ u64 1L);
        let_u64 "sign_bit" (u64 1L <<~ (var "bits" -~ i32 1));
        let_u64 "a_val" (var "a" &~ var "mask");
        let_u64 "b_val" (var "b" &~ var "mask");
        let_u64 "res" ((var "a_val" +~ var "b_val") &~ var "mask");
        (var "ctx.zf" := (var "res" ==~ u64 0L));
        (var "ctx.sf" := ((var "res" &~ var "sign_bit") <>~ u64 0L));
        (var "ctx.cf" := (var "res" <~ var "a_val"));
        (var "ctx.cf_arm64" := (var "res" <~ var "a_val"));
        (var "ctx.of" := (((bit_not (var "a_val" ^~ var "b_val") &~ (var "a_val" ^~ var "res")) &~ var "sign_bit") <>~ u64 0L));
      ];
    ];
  } in

  let decls : top_decl list = [
    comment_top "Randomized Architectural Register Map (π ∈ S_32)";
    enum_reg_map;
    comment_top "64-bit Cryptographic Key Derivation for Bytecode Offset (SplitMix64)";
    fn_key64;
    comment_top "Handlers Table Integrity Hash";
    fn_handlers_hash;
    comment_top "Blinded VMContext with Canary Guard Zones & Per-Slot Masking (P1-04b)";
    struct_vm_context;
    comment_top "Flag Evaluation and Condition Check Helpers";
    fn_eval_condition;
    fn_compute_sub_flags;
    fn_compute_add_flags;
  ] in
  decls

let emit_context_hpp b ~key_seed ~reg_perm ~stride ~offset ~enable_running_key ~enable_stack_scramble ~enable_mem_sanitize =
  let decls = emit_context_decls ~key_seed ~reg_perm ~stride ~offset ~enable_running_key ~enable_stack_scramble ~enable_mem_sanitize () in
  let rendered = render_top_decls decls in
  Buffer.add_string b rendered

