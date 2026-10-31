open Random_visa_domain
open Vanguard_types
open Cpp_codegen.Cpp_ast
open Cpp_codegen.Cpp_dsl
open Random_visa_constants.Magic_numbers

let emit_cpp_decoder (t : t) (spec : Vector_isa_spec.t) =
  let find_field kind =
    match List.find_opt (fun f -> f.kind = kind) t.layout.fields with
    | Some f -> (f.bit_offset, f.bit_width)
    | None -> (0, 0)
  in
  let op_off, op_w = find_field Opcode in
  let dst_off, dst_w = find_field Dst in
  let s1_off, s1_w = find_field Src1 in
  let s2_off, s2_w = find_field Src2 in
  let imm_off, imm_w = find_field Imm in
  let mask_off, _ = find_field Mask in

  let mask_val width =
    if width >= 64 then 0xFFFFFFFFFFFFFFFFL
    else Int64.sub (Int64.shift_left 1L width) 1L
  in

  (* RollingKey class as typed C++ AST *)
  let rolling_key_decl =
    struct_def "RollingKey" [
      member_field UInt32 "state";
      member_field ~init:(u32 0l) UInt32 "counter";
      member_constructor
        ~attrs:[AlwaysInline; NoExcept]
        ~is_explicit:true
        ~params:[ (UInt32, "seed") ]
        ~init_list:[
          ("state", ternary (var "seed" ==~ u32 0l) (LitU32 (Int64.to_int32 salt_leetbeef)) (var "seed"));
          ("counter", u32 0l);
        ]
        "RollingKey"
        [];
      member_method
        ~attrs:[AlwaysInline; NoExcept]
        UInt32 "next" []
        [
          raw "counter++;";
          decl_var ~init:(var "state") UInt32 "x";
          (var "x") ^= (var "x" <<~ i32 13);
          (var "x") ^= (var "x" >>~ i32 17);
          (var "x") ^= (var "x" <<~ i32 5);
          decl_var ~init:((var "x" <<~ i32 7) |~ (var "x" >>~ i32 25)) UInt32 "rot";
          decl_var ~init:(var "rot" +~ (var "counter" *~ LitU32 (Int64.to_int32 golden_ratio_32))) UInt32 "mixed";
          if_then (var "mixed" ==~ u32 0l) [ (var "mixed") := LitU32 (Int64.to_int32 salt_leetbeef) ];
          (var "state") := var "mixed";
          ret (var "mixed");
        ];
      member_method
        ~attrs:[AlwaysInline; NoExcept]
        UInt64 "next64" []
        [
          decl_var ~init:(cast UInt64 (call "next" [])) UInt64 "w1";
          decl_var ~init:(cast UInt64 (call "next" [])) UInt64 "w2";
          ret ((var "w1" <<~ i32 32) |~ var "w2");
        ];
    ]
  in

  let inst_cases =
    List.filter_map
      (fun (inst : Vector_instruction.t) ->
        match Opcode_map.encode t.opcodes inst.mnemonic with
        | None -> None
        | Some code ->
            Some (
              LitU32 (Int32.of_int code),
              [
                comment inst.mnemonic;
                (var "dec.id") := var ("visa_emulator::InstId::" ^ String.uppercase_ascii inst.mnemonic);
                (var "dec.mnemonic") := LitStr inst.mnemonic;
                if_then (Unary (LogNot, call "visa_emulator::InstructionExecutor::execute" [var "state"; var "dec"]))
                  [ ret (LitBool false) ];
                raw "executed_instructions++;";
                ret (LitBool true);
              ]
            ))
      spec.instructions
  in

  let junk_codes = ref [] in
  for c = 0 to (1 lsl (Opcode_map.opcode_bits t.opcodes)) - 1 do
    if Opcode_map.is_junk t.opcodes c then junk_codes.contents <- c :: junk_codes.contents
  done;

  let junk_trap_stmts = [
    raw "std::cerr << \"[VANGUARD-TRAP] Decoy junk opcode caught at runtime: 0x\" << std::hex << opcode << \"\\n\";";
    (var "trapped") := LitBool true;
    ret (LitBool false);
  ] in

  let junk_cases =
    List.map (fun c -> (LitU32 (Int32.of_int c), junk_trap_stmts)) (List.rev !junk_codes)
  in

  let default_case = Some [
    raw "std::cerr << \"[VANGUARD-TRAP] Unmapped opcode caught: 0x\" << std::hex << opcode << \"\\n\";";
    (var "trapped") := LitBool true;
    ret (LitBool false);
  ] in

  let decoder_body = [
    decl_var ~init:(var "raw_word" ^~ call "key.next64" []) UInt64 "word";
    decl_var ~init:(cast UInt32 ((var "word" >>~ i32 op_off) &~ LitU64 (mask_val op_w))) UInt32 "opcode";
    decl_var ~init:(cast SizeT ((var "word" >>~ i32 dst_off) &~ LitU64 (mask_val dst_w))) SizeT "dst";
    decl_var ~init:(cast SizeT ((var "word" >>~ i32 s1_off) &~ LitU64 (mask_val s1_w))) SizeT "src1";
    decl_var ~init:(cast SizeT ((var "word" >>~ i32 s2_off) &~ LitU64 (mask_val s2_w))) SizeT "src2";
    decl_var ~init:(cast Int64 ((var "word" >>~ i32 imm_off) &~ LitU64 (mask_val imm_w))) Int64 "imm";
    decl_var ~init:(((var "word" >>~ i32 mask_off) &~ LitU64 1L) <>~ LitU64 0L) Bool "mask";
    raw "visa_emulator::DecodedInstruction dec;";
    (var "dec.vd") := cast UInt8 (var "dst");
    (var "dec.vs2") := cast UInt8 (var "src2");
    (var "dec.vs1") := cast UInt8 (var "src1");
    (var "dec.rs1") := cast UInt8 (var "src1");
    (var "dec.imm") := cast Int8 (var "imm");
    (var "dec.vm") := ternary (var "mask") (LitInt 1) (LitInt 0);
    switch (var "opcode") (inst_cases @ junk_cases) default_case;
  ] in

  let vanguard_decoder_decl =
    struct_def "VanguardDecoder" [
      member_field (StructType "RollingKey") "key";
      member_field ~init:(LitBool false) Bool "trapped";
      member_field ~init:(LitU64 0L) SizeT "executed_instructions";
      member_constructor
        ~attrs:[NoExcept]
        ~is_explicit:true
        ~params:[ (UInt32, Printf.sprintf "seed = 0x%08lXU" t.key_seed) ]
        ~init_list:[ ("key", var "seed") ]
        "VanguardDecoder"
        [];
      member_method
        Bool "decode_and_execute"
        [ (Ref (StructType "visa_emulator::EmulatorState"), "state"); (UInt64, "raw_word") ]
        decoder_body;
    ]
  in

  let header_ast = [
    IncludeLocal "isa_state.hpp";
    IncludeLocal "decoder.hpp";
    IncludeLocal "instructions.hpp";
    IncludeSys "cstdint";
    IncludeSys "iostream";
    IncludeSys "iomanip";
    Namespace ("vanguard_vm", [
      rolling_key_decl;
      vanguard_decoder_decl;
    ]);
  ] in

  Cpp_codegen.Cpp_printer.render_header_unit header_ast
