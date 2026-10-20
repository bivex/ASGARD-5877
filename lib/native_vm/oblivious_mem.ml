open Int64

type frame_scrambler = {
  n_slots   : int;
  coprime_p : int;
  inv_p     : int;
  offset_q  : int;
  frame_key : int64;
}

let rec gcd a b = if b = 0 then a else gcd b (a mod b)

let mod_inv (a : int) (m : int) : int =
  let rec ext_gcd a b =
    if b = 0 then (1, 0)
    else
      let (q, r) = (a / b, a mod b) in
      let (x, y) = ext_gcd b r in
      (y, x - q * y)
  in
  let (x, _) = ext_gcd a m in
  ((x mod m) + m) mod m

let gen_frame_scrambler (rng : Random.State.t) ~(n_slots : int) : frame_scrambler =
  assert (n_slots >= 4);
  let rec pick_coprime () =
    let cand = 1 + Random.State.int rng (n_slots - 1) in
    if gcd cand n_slots = 1 then cand else pick_coprime ()
  in
  let coprime_p = pick_coprime () in
  let inv_p = mod_inv coprime_p n_slots in
  let offset_q = Random.State.int rng n_slots in
  let frame_key = Random.State.int64 rng max_int in
  { n_slots; coprime_p; inv_p; offset_q; frame_key }

let logical_to_physical_slot (s : frame_scrambler) (logical_idx : int) : int =
  ((s.coprime_p * logical_idx + s.offset_q) mod s.n_slots + s.n_slots) mod s.n_slots

let physical_to_logical_slot (s : frame_scrambler) (phys_idx : int) : int =
  let diff = ((phys_idx - s.offset_q) mod s.n_slots + s.n_slots) mod s.n_slots in
  (diff * s.inv_p) mod s.n_slots

let slot_tweak_mask (s : frame_scrambler) ~(logical_idx : int) : int64 =
  let z = add s.frame_key (mul (of_int logical_idx) 0x9E3779B97F4A7C15L) in
  let z = mul (logxor z (shift_right_logical z 30)) 0xBF58476D1CE4E5B9L in
  let z = mul (logxor z (shift_right_logical z 27)) 0x94D049BB133111EBL in
  logxor z (shift_right_logical z 31)

let oblivious_store (s : frame_scrambler) (mem : int64 array) ~(logical_idx : int) (v : int64) : unit =
  let p_idx = logical_to_physical_slot s logical_idx in
  let mask  = slot_tweak_mask s ~logical_idx in
  mem.(p_idx) <- logxor v mask

let oblivious_load_with_decoys (s : frame_scrambler) (mem : int64 array)
    ~(logical_idx : int) ~(noise_seed : int64) : int64 * int list =
  let real_phys = logical_to_physical_slot s logical_idx in
  let base_rot  = (to_int (logand noise_seed 3L)) in
  (* We build 4 physical indices: 1 real one (at position base_rot) and 3 false ones *)
  let accessed_indices = List.init 4 (fun k ->
    if k = base_rot then real_phys
    else
      let fake_step = ((k * 7 + to_int (logand (shift_right_logical noise_seed (k * 5)) 0xFL)) mod (s.n_slots - 1)) + 1 in
      (real_phys + fake_step) mod s.n_slots
  ) in
  (* Branchless arithmetic selection from the 4 read cells *)
  let acc = ref 0L in
  List.iteri (fun k p_idx ->
    let raw_val = mem.(p_idx) in
    (* is_target = 1L if k == base_rot, otherwise 0L *)
    let d = of_int (k lxor base_rot) in
    let is_target = sub 1L (shift_right_logical (logor d (neg d)) 63) in
    let bit_mask = neg is_target in
    acc := logor !acc (logand raw_val bit_mask)
  ) accessed_indices;
  let unmasked = logxor !acc (slot_tweak_mask s ~logical_idx) in
  (unmasked, accessed_indices)

let emit_oblivious_mem_decls (rng : Random.State.t) : Cpp_codegen.Cpp_ast.top_decl list =
  let open Cpp_codegen.Cpp_ast in
  let open Cpp_codegen.Cpp_dsl in

  let slot_tweak_mask_fn = FuncDecl {
    attrs    = [AlwaysInline; NoExcept];
    ret_type = UInt64;
    name     = "slot_tweak_mask";
    params   = [(UInt64, "frame_key"); (SizeT, "logical_idx")];
    body     = [
      let_u64 "z" (var "frame_key" +~ (cast UInt64 (var "logical_idx") *~ u64 0x9E3779B97F4A7C15L));
      let_u64 "z1" ((var "z" ^~ (var "z" >>~ u64 30L)) *~ u64 0xBF58476D1CE4E5B9L);
      let_u64 "z2" ((var "z1" ^~ (var "z1" >>~ u64 27L)) *~ u64 0x94D049BB133111EBL);
      ret (var "z2" ^~ (var "z2" >>~ u64 31L));
    ];
  } in

  let logical_to_phys_fn = FuncDecl {
    attrs    = [AlwaysInline; NoExcept];
    ret_type = SizeT;
    name     = "logical_to_physical_slot";
    params   = [(SizeT, "logical_idx"); (SizeT, "coprime_p"); (SizeT, "offset_q"); (SizeT, "n_slots")];
    body     = [
      ret (((var "coprime_p" *~ var "logical_idx") +~ var "offset_q") %~ var "n_slots");
    ];
  } in

  let phys_to_logical_fn = FuncDecl {
    attrs    = [AlwaysInline; NoExcept];
    ret_type = SizeT;
    name     = "physical_to_logical_slot";
    params   = [(SizeT, "phys_idx"); (SizeT, "inv_p"); (SizeT, "offset_q"); (SizeT, "n_slots")];
    body     = [
      decl_var SizeT "diff" ~init:(((var "phys_idx" +~ var "n_slots") -~ (var "offset_q" %~ var "n_slots")) %~ var "n_slots");
      ret ((var "diff" *~ var "inv_p") %~ var "n_slots");
    ];
  } in

  let read_quad_fn = FuncDecl {
    attrs    = [AlwaysInline; NoExcept];
    ret_type = UInt64;
    name     = "oblivious_read_quad";
    params   = [(ConstPtr UInt64, "quad_base"); (SizeT, "target_slot")];
    body     = [
      let_u64 "w0" (idx (var "quad_base") (i32 0));
      let_u64 "w1" (idx (var "quad_base") (i32 1));
      let_u64 "w2" (idx (var "quad_base") (i32 2));
      let_u64 "w3" (idx (var "quad_base") (i32 3));
      let_u64 "m0" (neg_u64 (cast UInt64 (var "target_slot" ==~ i32 0)));
      let_u64 "m1" (neg_u64 (cast UInt64 (var "target_slot" ==~ i32 1)));
      let_u64 "m2" (neg_u64 (cast UInt64 (var "target_slot" ==~ i32 2)));
      let_u64 "m3" (neg_u64 (cast UInt64 (var "target_slot" ==~ i32 3)));
      ret (((var "w0" &~ var "m0") |~ (var "w1" &~ var "m1")) |~ ((var "w2" &~ var "m2") |~ (var "w3" &~ var "m3")));
    ];
  } in

  let load_u64_fn = FuncDecl {
    attrs    = [AlwaysInline; NoExcept];
    ret_type = UInt64;
    name     = "oblivious_load_u64";
    params   = [(UIntPtr, "addr")];
    body     = [
      decl_var UIntPtr "line_base" ~init:(var "addr" &~ bit_not (cast UIntPtr (i32 31)));
      decl_var SizeT "slot" ~init:(cast SizeT ((var "addr" -~ var "line_base") >>~ i32 3));
      decl_var UInt64 "val" ~init:(call "oblivious_read_quad" [reinterpret_cast (ConstPtr UInt64) (var "line_base"); var "slot"]);
      decl_var SizeT "byte_shift" ~init:(cast SizeT ((var "addr" &~ cast UIntPtr (i32 7)) *~ cast UIntPtr (i32 8)));
      if_then (var "byte_shift" <>~ i32 0) [
        if_then_else ((var "addr" &~ cast UIntPtr (i32 31)) <=~ cast UIntPtr (i32 24)) [
          let_u64 "next_val" (idx (reinterpret_cast (ConstPtr UInt64) (var "line_base")) (var "slot" +~ i32 1));
          (var "val" := (var "val" >>~ var "byte_shift") |~ (var "next_val" <<~ (i32 64 -~ var "byte_shift")));
        ] [
          decl_var UInt64 "direct_val" ~init:(u64 0L);
          expr_stmt (call "std::memcpy" [addr_of (var "direct_val"); reinterpret_cast (ConstPtr Void) (var "addr"); sizeof_ty UInt64]);
          (var "val" := var "direct_val");
        ];
      ];
      ret (var "val");
    ];
  } in

  let load_u32_fn = FuncDecl {
    attrs    = [AlwaysInline; NoExcept];
    ret_type = UInt32;
    name     = "oblivious_load_u32";
    params   = [(UIntPtr, "addr")];
    body     = [
      decl_var UIntPtr "line_base" ~init:(var "addr" &~ bit_not (cast UIntPtr (i32 31)));
      decl_var SizeT "slot" ~init:(cast SizeT ((var "addr" -~ var "line_base") >>~ i32 3));
      decl_var UInt64 "val" ~init:(call "oblivious_read_quad" [reinterpret_cast (ConstPtr UInt64) (var "line_base"); var "slot"]);
      decl_var SizeT "byte_shift" ~init:(cast SizeT ((var "addr" &~ cast UIntPtr (i32 7)) *~ cast UIntPtr (i32 8)));
      if_then (var "byte_shift" <>~ i32 0) [
        if_then_else ((var "addr" &~ cast UIntPtr (i32 31)) <=~ cast UIntPtr (i32 28)) [
          let_u64 "next_val" (idx (reinterpret_cast (ConstPtr UInt64) (var "line_base")) ((var "slot" +~ i32 1) &~ i32 3));
          (var "val" := (var "val" >>~ var "byte_shift") |~ (var "next_val" <<~ (i32 64 -~ var "byte_shift")));
        ] [
          decl_var UInt32 "direct_val" ~init:(u32 0l);
          expr_stmt (call "std::memcpy" [addr_of (var "direct_val"); reinterpret_cast (ConstPtr Void) (var "addr"); sizeof_ty UInt32]);
          ret (var "direct_val");
        ];
      ];
      ret (cast UInt32 (var "val"));
    ];
  } in

  let load_u16_fn = FuncDecl {
    attrs    = [AlwaysInline; NoExcept];
    ret_type = UInt16;
    name     = "oblivious_load_u16";
    params   = [(UIntPtr, "addr")];
    body     = [
      decl_var UIntPtr "line_base" ~init:(var "addr" &~ bit_not (cast UIntPtr (i32 31)));
      decl_var SizeT "slot" ~init:(cast SizeT ((var "addr" -~ var "line_base") >>~ i32 3));
      decl_var UInt64 "val" ~init:(call "oblivious_read_quad" [reinterpret_cast (ConstPtr UInt64) (var "line_base"); var "slot"]);
      decl_var SizeT "byte_shift" ~init:(cast SizeT ((var "addr" &~ cast UIntPtr (i32 7)) *~ cast UIntPtr (i32 8)));
      if_then (var "byte_shift" <>~ i32 0) [
        if_then_else ((var "addr" &~ cast UIntPtr (i32 31)) <=~ cast UIntPtr (i32 30)) [
          let_u64 "next_val" (idx (reinterpret_cast (ConstPtr UInt64) (var "line_base")) ((var "slot" +~ i32 1) &~ i32 3));
          (var "val" := (var "val" >>~ var "byte_shift") |~ (var "next_val" <<~ (i32 64 -~ var "byte_shift")));
        ] [
          decl_var UInt16 "direct_val" ~init:(cast UInt16 (i32 0));
          expr_stmt (call "std::memcpy" [addr_of (var "direct_val"); reinterpret_cast (ConstPtr Void) (var "addr"); sizeof_ty UInt16]);
          ret (var "direct_val");
        ];
      ];
      ret (cast UInt16 (var "val"));
    ];
  } in

  let load_u8_fn = FuncDecl {
    attrs    = [AlwaysInline; NoExcept];
    ret_type = UInt8;
    name     = "oblivious_load_u8";
    params   = [(UIntPtr, "addr")];
    body     = [
      decl_var UIntPtr "line_base" ~init:(var "addr" &~ bit_not (cast UIntPtr (i32 31)));
      decl_var SizeT "slot" ~init:(cast SizeT ((var "addr" -~ var "line_base") >>~ i32 3));
      decl_var UInt64 "val" ~init:(call "oblivious_read_quad" [reinterpret_cast (ConstPtr UInt64) (var "line_base"); var "slot"]);
      decl_var SizeT "byte_shift" ~init:(cast SizeT ((var "addr" &~ cast UIntPtr (i32 7)) *~ cast UIntPtr (i32 8)));
      ret (cast UInt8 (var "val" >>~ var "byte_shift"));
    ];
  } in

  let store_u64_fn = FuncDecl {
    attrs    = [AlwaysInline; NoExcept];
    ret_type = Void;
    name     = "oblivious_store_u64";
    params   = [(UIntPtr, "addr"); (UInt64, "val"); (Ptr UInt64, "decoy_sink")];
    body     = [
      (deref (reinterpret_cast (Ptr UInt64) (var "addr")) := var "val");
      if_then (var "decoy_sink" <>~ nullptr) [
        (deref (var "decoy_sink") := (var "val" ^~ u64 0x5877CAFE1337BEEFL));
      ];
    ];
  } in

  let store_u32_fn = FuncDecl {
    attrs    = [AlwaysInline; NoExcept];
    ret_type = Void;
    name     = "oblivious_store_u32";
    params   = [(UIntPtr, "addr"); (UInt32, "val"); (Ptr UInt64, "decoy_sink")];
    body     = [
      (deref (reinterpret_cast (Ptr UInt32) (var "addr")) := var "val");
      if_then (var "decoy_sink" <>~ nullptr) [
        (deref (var "decoy_sink") := (cast UInt64 (var "val") ^~ u64 0x5877CAFE1337BEEFL));
      ];
    ];
  } in

  let store_u16_fn = FuncDecl {
    attrs    = [AlwaysInline; NoExcept];
    ret_type = Void;
    name     = "oblivious_store_u16";
    params   = [(UIntPtr, "addr"); (UInt16, "val"); (Ptr UInt64, "decoy_sink")];
    body     = [
      (deref (reinterpret_cast (Ptr UInt16) (var "addr")) := var "val");
      if_then (var "decoy_sink" <>~ nullptr) [
        (deref (var "decoy_sink") := (cast UInt64 (var "val") ^~ u64 0x5877CAFE1337BEEFL));
      ];
    ];
  } in

  let store_u8_fn = FuncDecl {
    attrs    = [AlwaysInline; NoExcept];
    ret_type = Void;
    name     = "oblivious_store_u8";
    params   = [(UIntPtr, "addr"); (UInt8, "val"); (Ptr UInt64, "decoy_sink")];
    body     = [
      (deref (reinterpret_cast (Ptr UInt8) (var "addr")) := var "val");
      if_then (var "decoy_sink" <>~ nullptr) [
        (deref (var "decoy_sink") := (cast UInt64 (var "val") ^~ u64 0x5877CAFE1337BEEFL));
      ];
    ];
  } in

  let ast = [
    IncludeSys "cstdint";
    IncludeSys "cstddef";
    IncludeSys "cstring";
    Namespace ("asgard::oblivious_mem", [
      slot_tweak_mask_fn;
      logical_to_phys_fn;
      phys_to_logical_fn;
      read_quad_fn;
      load_u64_fn;
      load_u32_fn;
      load_u16_fn;
      load_u8_fn;
      store_u64_fn;
      store_u32_fn;
      store_u16_fn;
      store_u8_fn;
    ]);
  ] in
  List.map (Cpp_codegen.Cpp_ast_obf.scramble_top_decl rng) ast

let emit_oblivious_mem_hpp (rng : Random.State.t) : string =
  let decls = emit_oblivious_mem_decls rng in
  Cpp_codegen.Cpp_printer.render_header_unit decls

