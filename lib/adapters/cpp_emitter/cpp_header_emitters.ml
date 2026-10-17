open Random_visa_domain

let group_by_funct6 (instructions : Vector_instruction.t list) =
  let tbl = Hashtbl.create 16 in
  List.iter
    (fun (inst : Vector_instruction.t) ->
      let cur = Option.value ~default:[] (Hashtbl.find_opt tbl inst.funct6) in
      Hashtbl.replace tbl inst.funct6 (inst :: cur))
    instructions;
  let groups =
    Hashtbl.fold
      (fun f6 insts acc ->
        let sorted =
          List.sort
            (fun (a : Vector_instruction.t) (b : Vector_instruction.t) ->
              Int.compare a.funct3 b.funct3)
            insts
        in
        (f6, sorted) :: acc)
      tbl []
  in
  List.sort (fun (a, _) (b, _) -> Int.compare a b) groups

open Cpp_codegen.Cpp_ast
open Cpp_codegen.Cpp_dsl
open Cpp_codegen.Cpp_printer

let emit_csr_state_def (default_vl : int) : top_decl =
  StructDef {
    align_as = None;
    name = "CSRState";
    members = [
      member_field UInt64 "vl" ~init:(u64 (Int64.of_int default_vl));
      member_field UInt64 "vtype" ~init:(u64 0L);
      member_field UInt64 "vstart" ~init:(u64 0L);
      member_field UInt64 "vxrm" ~init:(u64 0L);
      member_field UInt64 "vxsat" ~init:(u64 0L);
      member_field UInt64 "pc" ~init:(u64 0x80000000L);
    ];
  }

let emit_inst_id_enum (instructions : Vector_instruction.t list) : top_decl =
  EnumDecl {
    name = "class InstId";
    underlying_ty = None;
    items = ("UNKNOWN", Some (i32 0)) :: List.map (fun (inst : Vector_instruction.t) ->
      (String.uppercase_ascii inst.mnemonic, None)
    ) instructions;
  }

let emit_decoded_instruction_def () : top_decl =
  StructDef {
    align_as = None;
    name = "DecodedInstruction";
    members = [
      member_field (StructType "InstId") "id" ~init:(var "InstId::UNKNOWN");
      member_field (StructType "std::string_view") "mnemonic" ~init:(str_lit "unknown");
      member_field UInt8 "opcode" ~init:(u32 0l);
      member_field UInt8 "funct3" ~init:(u32 0l);
      member_field UInt8 "funct6" ~init:(u32 0l);
      member_field UInt8 "vd" ~init:(u32 0l);
      member_field UInt8 "vs2" ~init:(u32 0l);
      member_field UInt8 "vs1" ~init:(u32 0l);
      member_field UInt8 "rs1" ~init:(u32 0l);
      member_field Int8 "imm" ~init:(i32 0);
      member_field UInt8 "vm" ~init:(u32 1l);
      member_field UInt32 "raw_word" ~init:(u32 0l);
    ];
  }

let emit_vreg_file_def () : top_decl =
  ClassDef {
    align_as = None;
    name = "VRegFile";
    members = [
      member_public;
      member_raw "alignas(64) std::array<std::array<uint8_t, VLEN_BYTES>, NUM_VREGS> regs{};";
      member_method ~attrs:[NoExcept] Void "reset" [] [
        raw "for (auto& r : regs) r.fill(0);";
      ];
      member_method ~attrs:[InlineFn; NoExcept] (Ptr UInt8) "get_reg_ptr" [(SizeT, "reg_idx")] [
        ret (call "regs[reg_idx].data" []);
      ];
      member_method ~attrs:[InlineFn; NoExcept] ~is_const:true (ConstPtr UInt8) "get_reg_ptr" [(SizeT, "reg_idx")] [
        ret (call "regs[reg_idx].data" []);
      ];
      member_method ~template_params:["typename T"] ~attrs:[InlineFn; NoExcept] ~is_const:true (StructType "T") "get_elem"
        [(SizeT, "reg_idx"); (SizeT, "elem_idx")] [
        if_then (var "reg_idx" >=~ var "NUM_VREGS") [ret (i32 0)];
        decl_var SizeT "offset" ~init:(var "elem_idx" *~ call "sizeof" [var "T"]);
        if_then ((var "offset" +~ call "sizeof" [var "T"]) >~ var "VLEN_BYTES") [ret (i32 0)];
        decl_var (StructType "T") "val";
        expr_stmt (call "std::memcpy" [addr_of (var "val"); addr_of (Index (Index (var "regs", var "reg_idx"), var "offset")); call "sizeof" [var "T"]]);
        ret (var "val");
      ];
      member_method ~template_params:["typename T"] ~attrs:[InlineFn; NoExcept] Void "set_elem"
        [(SizeT, "reg_idx"); (SizeT, "elem_idx"); (StructType "T", "val")] [
        if_then (var "reg_idx" >=~ var "NUM_VREGS") [ret_void];
        decl_var SizeT "offset" ~init:(var "elem_idx" *~ call "sizeof" [var "T"]);
        if_then ((var "offset" +~ call "sizeof" [var "T"]) >~ var "VLEN_BYTES") [ret_void];
        expr_stmt (call "std::memcpy" [addr_of (Index (Index (var "regs", var "reg_idx"), var "offset")); addr_of (var "val"); call "sizeof" [var "T"]]);
      ];
      member_method ~attrs:[InlineFn; NoExcept] ~is_const:true Bool "is_mask_set"
        [(SizeT, "mask_reg"); (SizeT, "elem_idx")] [
        if_then (var "mask_reg" >=~ var "NUM_VREGS") [ret (bool_lit false)];
        decl_var SizeT "byte_idx" ~init:(var "elem_idx" /~ i32 8);
        decl_var SizeT "bit_idx" ~init:(var "elem_idx" %~ i32 8);
        if_then (var "byte_idx" >=~ var "VLEN_BYTES") [ret (bool_lit false)];
        ret (ne (Index (Index (var "regs", var "mask_reg"), var "byte_idx") &~ (i32 1 <<~ var "bit_idx")) (i32 0));
      ];
    ];
  }

let emit_emulator_state_def () : top_decl =
  StructDef {
    align_as = None;
    name = "EmulatorState";
    members = [
      member_field (StructType "VRegFile") "vregs";
      member_raw "std::array<uint64_t, NUM_XREGS> xregs{};";
      member_field (StructType "CSRState") "csr";
      member_method ~attrs:[NoExcept] Void "reset" [] [
        expr_stmt (call "vregs.reset" []);
        expr_stmt (call "xregs.fill" [i32 0]);
        var "csr" := call "CSRState" [];
      ];
      member_method ~attrs:[InlineFn; NoExcept] ~is_const:true UInt64 "get_xreg" [(SizeT, "idx")] [
        if_then ((var "idx" ==~ i32 0) ||~ (var "idx" >=~ var "NUM_XREGS")) [ret (u64 0L)];
        ret (Index (var "xregs", var "idx"));
      ];
      member_method ~attrs:[InlineFn; NoExcept] Void "set_xreg" [(SizeT, "idx"); (UInt64, "val")] [
        if_then ((var "idx" >~ i32 0) &&~ (var "idx" <~ var "NUM_XREGS")) [
          Index (var "xregs", var "idx") := var "val";
        ];
      ];
    ];
  }

let emit_isa_constants_defs (spec : Vector_isa_spec.t) : top_decl list =
  let vlen = spec.config.vlen in
  let num_vregs = spec.config.num_vregs in
  [
    ConstexprGlobal (SizeT, "VLEN", i32 vlen);
    ConstexprGlobal (SizeT, "VLEN_BYTES", var "VLEN" /~ i32 8);
    ConstexprGlobal (SizeT, "NUM_VREGS", i32 num_vregs);
    ConstexprGlobal (SizeT, "NUM_XREGS", i32 32);
  ]

let emit_isa_state_hpp (spec : Vector_isa_spec.t) =
  let vlen = spec.config.vlen in
  let sew = Types.Sew.to_bits spec.config.default_sew in
  let default_vl = vlen / sew in
  let ns_decls =
    emit_isa_constants_defs spec
    @ [
      emit_csr_state_def default_vl;
      emit_vreg_file_def ();
      emit_emulator_state_def ();
    ]
  in
  let top_decls = [
    pragma "once";
    include_sys "cstdint";
    include_sys "cstddef";
    include_sys "array";
    include_sys "vector";
    include_sys "cstring";
    include_sys "iostream";
    include_sys "iomanip";
    include_sys "algorithm";
    namespace_def "visa_emulator" ns_decls;
  ] in
  render_top_decls top_decls

let emit_decoder_class_def (instructions : Vector_instruction.t list) : top_decl =
  let groups = group_by_funct6 instructions in
  let switch_cases =
    List.map
      (fun (f6, insts) ->
        (i32 f6,
         List.map
           (fun (inst : Vector_instruction.t) ->
             if_then (var "dec.funct3" ==~ i32 inst.funct3) [
               var "dec.id" := var ("InstId::" ^ String.uppercase_ascii inst.mnemonic);
               var "dec.mnemonic" := str_lit inst.mnemonic;
               ret (var "dec");
             ]
           ) insts @ [break_stmt])
      ) groups
  in
  let decode_body = [
    decl_var (StructType "DecodedInstruction") "dec";
    var "dec.raw_word" := var "word";
    var "dec.opcode" := var "word" &~ u32 0x7Fl;
    var "dec.vd" := (var "word" >>~ i32 7) &~ u32 0x1Fl;
    var "dec.funct3" := (var "word" >>~ i32 12) &~ u32 0x7l;
    var "dec.vs1" := (var "word" >>~ i32 15) &~ u32 0x1Fl;
    var "dec.rs1" := var "dec.vs1";
    decl_var Int32 "imm5" ~init:(cast Int32 ((var "word" >>~ i32 15) &~ u32 0x1Fl));
    if_then (ne (var "imm5" &~ i32 0x10) (i32 0)) [
      var "imm5" |= bit_not (i32 0x1F);
    ];
    var "dec.imm" := cast Int8 (var "imm5");
    var "dec.vs2" := (var "word" >>~ i32 20) &~ u32 0x1Fl;
    var "dec.vm" := (var "word" >>~ i32 25) &~ u32 0x1l;
    var "dec.funct6" := (var "word" >>~ i32 26) &~ u32 0x3Fl;
    if_then (ne (var "dec.opcode") (u32 0x57l)) [
      ret (var "dec");
    ];
    switch (var "dec.funct6") switch_cases (Some [break_stmt]);
    ret (var "dec");
  ] in
  ClassDef {
    align_as = None;
    name = "Decoder";
    members = [
      member_public;
      member_method ~attrs:[StaticFn; InlineFn; NoExcept] (StructType "DecodedInstruction") "decode"
        [(UInt32, "word")] decode_body;
    ];
  }

let emit_decoder_hpp (spec : Vector_isa_spec.t) =
  let ns_decls = [
    emit_inst_id_enum spec.instructions;
    emit_decoded_instruction_def ();
    emit_decoder_class_def spec.instructions;
  ] in
  let top_decls = [
    pragma "once";
    include_sys "cstdint";
    include_sys "string_view";
    include_sys "optional";
    namespace_def "visa_emulator" ns_decls;
  ] in
  render_top_decls top_decls

let emit_instruction_executor_class_def (instructions : Vector_instruction.t list) : top_decl =
  ClassDef {
    align_as = None;
    name = "InstructionExecutor";
    members = [
      member_public;
      member_method_decl ~attrs:[StaticFn; NoExcept] Bool "execute"
        [(Ref (StructType "EmulatorState"), "state"); (ConstRef (StructType "DecodedInstruction"), "inst")];
      member_private;
    ] @ List.map (fun (inst : Vector_instruction.t) ->
      member_method_decl ~attrs:[StaticFn; NoExcept] Void ("exec_" ^ inst.mnemonic)
        [(Ref (StructType "EmulatorState"), "state"); (ConstRef (StructType "DecodedInstruction"), "inst")]
    ) instructions;
  }

let emit_instructions_hpp (spec : Vector_isa_spec.t) =
  let top_decls = [
    pragma "once";
    include_local "isa_state.hpp";
    include_local "decoder.hpp";
    namespace_def "visa_emulator" [ emit_instruction_executor_class_def spec.instructions ];
  ] in
  render_top_decls top_decls
