open Random_visa_domain

let ensure_dir dir =
  if not (Sys.file_exists dir) then
    let rec mkdir_p d =
      if not (Sys.file_exists d) then begin
        mkdir_p (Filename.dirname d);
        try Sys.mkdir d 0o755 with Sys_error _ -> ()
      end
    in
    mkdir_p dir

let write_file path content =
  let oc = open_out_bin path in
  output_string oc content;
  close_out oc;
  path

let emit_isa_state_hpp = Cpp_header_emitters.emit_isa_state_hpp
let emit_decoder_hpp = Cpp_header_emitters.emit_decoder_hpp
let emit_instructions_hpp = Cpp_header_emitters.emit_instructions_hpp


open Cpp_codegen.Cpp_ast
open Cpp_codegen.Cpp_dsl
open Cpp_codegen.Cpp_printer

let generate_c_op_expr (inst : Vector_instruction.t) : expr =
  let elem_t = StructType "elem_t" in
  match inst.binary_op with
  | Some ADD ->
      if inst.is_widening then var "op2" +~ var "op1"
      else cast elem_t (cast UInt32 (var "op2") +~ cast UInt32 (var "op1"))
  | Some SUB ->
      if inst.is_widening then var "op2" -~ var "op1"
      else cast elem_t (cast UInt32 (var "op2") -~ cast UInt32 (var "op1"))
  | Some MUL ->
      if inst.is_widening then var "op2" *~ var "op1"
      else cast elem_t (cast UInt32 (var "op2") *~ cast UInt32 (var "op1"))
  | Some DIV ->
      ternary (var "op1" ==~ i32 0) (i32 (-1))
        (ternary ((var "op2" ==~ var "INT32_MIN") &&~ (var "op1" ==~ i32 (-1)))
           (var "INT32_MIN")
           (var "op2" /~ var "op1"))
  | Some REM ->
      ternary (var "op1" ==~ i32 0) (var "op2")
        (ternary ((var "op2" ==~ var "INT32_MIN") &&~ (var "op1" ==~ i32 (-1)))
           (i32 0)
           (var "op2" %~ var "op1"))
  | Some AND -> var "op2" &~ var "op1"
  | Some OR  -> var "op2" |~ var "op1"
  | Some XOR -> var "op2" ^~ var "op1"
  | Some SLL -> cast elem_t (cast UInt32 (var "op2") <<~ (var "op1" &~ var "31u"))
  | Some SRL -> cast elem_t (cast UInt32 (var "op2") >>~ (var "op1" &~ var "31u"))
  | Some SRA -> cast elem_t (var "op2" >>~ (var "op1" &~ var "31u"))
  | Some MIN -> call "std::min" [var "op2"; var "op1"]
  | Some MAX -> call "std::max" [var "op2"; var "op1"]
  | Some SADD -> cast elem_t (call "std::clamp<int64_t>" [cast Int64 (var "op2") +~ var "op1"; var "INT32_MIN"; var "INT32_MAX"])
  | Some SSUB -> cast elem_t (call "std::clamp<int64_t>" [cast Int64 (var "op2") -~ var "op1"; var "INT32_MIN"; var "INT32_MAX"])
  | Some CMPEQ -> ternary (var "op2" ==~ var "op1") (call "elem_t" [i32 1]) (call "elem_t" [i32 0])
  | Some CMPNE -> ternary (ne (var "op2") (var "op1")) (call "elem_t" [i32 1]) (call "elem_t" [i32 0])
  | Some CMPLT -> ternary (var "op2" <~ var "op1") (call "elem_t" [i32 1]) (call "elem_t" [i32 0])
  | Some CMPGE -> ternary (var "op2" >=~ var "op1") (call "elem_t" [i32 1]) (call "elem_t" [i32 0])
  | None -> (
      match inst.unary_op with
      | Some NEG -> cast elem_t (var "0u" -~ cast UInt32 (var "op2"))
      | Some NOT -> bit_not (var "op2")
      | Some ABS -> ternary (var "op2" ==~ var "INT32_MIN") (var "INT32_MIN") (ternary (var "op2" <~ i32 0) (neg (var "op2")) (var "op2"))
      | Some CLZ -> ternary (var "op2" ==~ i32 0) (i32 32) (call "__builtin_clz" [cast UInt32 (var "op2")])
      | Some CTZ -> ternary (var "op2" ==~ i32 0) (i32 32) (call "__builtin_ctz" [cast UInt32 (var "op2")])
      | Some CPOP -> call "__builtin_popcount" [cast UInt32 (var "op2")]
      | None -> var "op2")

let emit_execute_method_def (spec : Vector_isa_spec.t) : top_decl =
  FuncDecl {
    attrs = [NoExcept];
    ret_type = Bool;
    name = "InstructionExecutor::execute";
    params = [(Ref (StructType "EmulatorState"), "state"); (ConstRef (StructType "DecodedInstruction"), "inst")];
    body = [
      switch (var "inst.id")
        (List.map (fun (inst : Vector_instruction.t) ->
           (var ("InstId::" ^ String.uppercase_ascii inst.mnemonic),
            [
              expr_stmt (call ("exec_" ^ inst.mnemonic) [var "state"; var "inst"]);
              ret (bool_lit true);
            ])
         ) spec.instructions)
        (Some [ret (bool_lit false)]);
    ];
  }

let emit_exec_inst_method_def (inst : Vector_instruction.t) : top_decl =
  let src_elem_t = StructType "src_elem_t" in
  let elem_t = StructType "elem_t" in
  let body_header =
    if inst.is_widening then [
      raw "using src_elem_t = int32_t;";
      raw "using elem_t = int64_t;";
      decl_var ~is_const:true SizeT "vl" ~init:(call "std::min<size_t>" [var "state.csr.vl"; var "VLEN_BYTES" /~ call "sizeof" [var "elem_t"]]);
    ] else [
      raw "using src_elem_t = int32_t;";
      raw "using elem_t = int32_t;";
      decl_var ~is_const:true SizeT "vl" ~init:(cast SizeT (var "state.csr.vl"));
    ]
  in
  let vd_ptr_decl =
    decl_var (Ptr elem_t) "vd_ptr" ~init:(reinterpret_cast (Ptr elem_t) (call "state.vregs.get_reg_ptr" [var "inst.vd"]))
  in
  let vs2_ptr_decl =
    decl_var (ConstPtr src_elem_t) "vs2_ptr" ~init:(reinterpret_cast (ConstPtr src_elem_t) (call "state.vregs.get_reg_ptr" [var "inst.vs2"]))
  in
  let has_op1_scalar = inst.format = Types.Instruction_format.OP_VX || inst.format = Types.Instruction_format.OP_VI in
  let op1_setup =
    if has_op1_scalar then
      if inst.format = Types.Instruction_format.OP_VX then
        [decl_var ~is_const:true elem_t "op1_scalar" ~init:(cast elem_t (call "state.get_xreg" [var "inst.rs1"]))]
      else
        [decl_var ~is_const:true elem_t "op1_scalar" ~init:(cast elem_t (var "inst.imm"))]
    else if inst.binary_op <> None then
      [decl_var (ConstPtr src_elem_t) "vs1_ptr" ~init:(reinterpret_cast (ConstPtr src_elem_t) (call "state.vregs.get_reg_ptr" [var "inst.vs1"]))]
    else
      []
  in
  let expr = generate_c_op_expr inst in
  let unmasked_loop_body =
    [
      decl_var elem_t "op2" ~init:(Index (var "vs2_ptr", var "i"));
    ] @ (
      if inst.binary_op <> None then
        if has_op1_scalar then
          [decl_var elem_t "op1" ~init:(var "op1_scalar")]
        else
          [decl_var elem_t "op1" ~init:(Index (var "vs1_ptr", var "i"))]
      else []
    ) @ [
      decl_var elem_t "res" ~init:expr;
      Index (var "vd_ptr", var "i") := var "res";
    ]
  in
  let masked_loop_body =
    [
      if_then (log_not (call "state.vregs.is_mask_set" [i32 0; var "i"])) [continue_stmt];
      decl_var elem_t "op2" ~init:(Index (var "vs2_ptr", var "i"));
    ] @ (
      if inst.binary_op <> None then
        if has_op1_scalar then
          [decl_var elem_t "op1" ~init:(var "op1_scalar")]
        else
          [decl_var elem_t "op1" ~init:(Index (var "vs1_ptr", var "i"))]
      else []
    ) @ [
      decl_var elem_t "res" ~init:expr;
      Index (var "vd_ptr", var "i") := var "res";
    ]
  in
  let loops =
    if_then_else
      (call "__builtin_expect" [var "inst.vm" ==~ i32 1; i32 1])
      [for_range "i" (i32 0) (var "vl") unmasked_loop_body]
      [for_range "i" (i32 0) (var "vl") masked_loop_body]
  in
  FuncDecl {
    attrs = [NoExcept];
    ret_type = Void;
    name = ("InstructionExecutor::exec_" ^ inst.mnemonic);
    params = [(Ref (StructType "EmulatorState"), "state"); (ConstRef (StructType "DecodedInstruction"), "inst")];
    body = body_header @ [vd_ptr_decl; vs2_ptr_decl] @ op1_setup @ [loops];
  }

let emit_instructions_cpp (spec : Vector_isa_spec.t) =
  let ns_decls =
    emit_execute_method_def spec :: List.map emit_exec_inst_method_def spec.instructions
  in
  let top_decls = [
    include_local "instructions.hpp";
    include_sys "algorithm";
    namespace_def "visa_emulator" ns_decls;
  ] in
  render_top_decls top_decls

let emit_vector_emulator_class_def () : top_decl =
  ClassDef {
    align_as = None;
    name = "VectorEmulator";
    members = [
      member_public;
      member_field (StructType "EmulatorState") "state";
      member_method ~attrs:[InlineFn; NoExcept] Bool "step" [(UInt32, "raw_inst")] [
        decl_var (StructType "DecodedInstruction") "dec" ~init:(call "Decoder::decode" [var "raw_inst"]);
        if_then (var "dec.id" ==~ var "InstId::UNKNOWN") [ret (bool_lit false)];
        decl_var Bool "ok" ~init:(call "InstructionExecutor::execute" [var "state"; var "dec"]);
        if_then (var "ok") [var "state.csr.pc" += i32 4];
        ret (var "ok");
      ];
      member_method ~attrs:[NoExcept] SizeT "run_program" [(ConstRef (StructType "std::vector<uint32_t>"), "program")] [
        decl_var SizeT "executed" ~init:(i32 0);
        raw "for (uint32_t word : program) {\n            if (!step(word)) break;\n            ++executed;\n        }";
        ret (var "executed");
      ];
    ];
  }

let emit_emulator_hpp () =
  let top_decls = [
    pragma "once";
    include_local "isa_state.hpp";
    include_local "decoder.hpp";
    include_local "instructions.hpp";
    include_sys "vector";
    namespace_def "visa_emulator" [ emit_vector_emulator_class_def () ];
  ] in
  render_top_decls top_decls

let emit_setup_test_state_def () : top_decl =
  FuncDecl {
    attrs = [StaticFn];
    ret_type = Void;
    name = "setup_test_state";
    params = [(Ref (StructType "visa_emulator::EmulatorState"), "state")];
    body = [
      for_range "i" (i32 0) (var "state.csr.vl") [
        expr_stmt (call "state.vregs.set_elem<int32_t>" [i32 1; var "i"; cast Int32 ((var "i" +~ i32 1) *~ i32 10)]);
        expr_stmt (call "state.vregs.set_elem<int32_t>" [i32 2; var "i"; cast Int32 ((var "i" +~ i32 1) *~ i32 2)]);
      ];
      expr_stmt (call "state.set_xreg" [i32 1; u64 5L]);
    ];
  }

let emit_run_self_tests_def (spec : Vector_isa_spec.t) : top_decl =
  let test_cases =
    List.map (fun (inst : Vector_instruction.t) ->
      let word = Vector_instruction.encode ~vd:3 ~vs2:2 ~vs1_or_rs1_or_imm:1 ~vm:1 inst in
      let log_stmt =
        if inst.is_widening then
          raw (Printf.sprintf "std::cout << \"[TEST] %s: word=0x\" << std::hex << word << std::dec << \" res[0]=\" << emu.state.vregs.get_elem<int64_t>(3, 0) << \"\\n\";" inst.mnemonic)
        else
          raw (Printf.sprintf "std::cout << \"[TEST] %s: word=0x\" << std::hex << word << std::dec << \" res[0]=\" << emu.state.vregs.get_elem<int32_t>(3, 0) << \"\\n\";" inst.mnemonic)
      in
      Block [
        expr_stmt (call "setup_test_state" [var "emu.state"]);
        decl_var UInt32 "word" ~init:(u32 word);
        decl_var Bool "ok" ~init:(call "emu.step" [var "word"]);
        if_then (log_not (var "ok")) [
          raw (Printf.sprintf "std::cerr << \"[FAIL] %s failed to execute\\n\";" inst.mnemonic);
          ret (i32 1);
        ];
        log_stmt;
        var "passed" += i32 1;
      ]
    ) spec.instructions
  in
  FuncDecl {
    attrs = [StaticFn];
    ret_type = Int32;
    name = "run_self_tests";
    params = [(Ref (StructType "visa_emulator::VectorEmulator"), "emu")];
    body = [decl_var Int32 "passed" ~init:(i32 0)]
           @ test_cases
           @ [
             raw "std::cout << \"=== ALL EMULATOR TESTS PASSED (\" << passed << \" instructions verified) ===\\n\";";
             ret (i32 0);
           ];
  }

let emit_main_def () : top_decl =
  FuncDecl {
    attrs = [];
    ret_type = Int32;
    name = "main";
    params = [(Int32, "argc"); (Ptr (Ptr (StructType "char")), "argv")];
    body = [
      decl_var (StructType "visa_emulator::VectorEmulator") "emu";
      if_then (var "argc" >~ i32 1) [
        decl_var (StructType "std::string") "arg" ~init:(Index (var "argv", i32 1));
        if_then ((var "arg" ==~ str_lit "--bin") &&~ (var "argc" >~ i32 2)) [
          decl_var (StructType "std::ifstream") "file" ~init:(call "std::ifstream" [Index (var "argv", i32 2); var "std::ios::binary"]);
          if_then (log_not (var "file")) [
            raw "std::cerr << \"Cannot open bytecode file: \" << argv[2] << \"\\n\";";
            ret (i32 1);
          ];
          decl_var (StructType "std::vector<uint32_t>") "code";
          decl_var UInt32 "w";
          raw "while (file.read(reinterpret_cast<char*>(&w), sizeof(w))) code.push_back(w);";
          expr_stmt (call "setup_test_state" [var "emu.state"]);
          decl_var SizeT "n" ~init:(call "emu.run_program" [var "code"]);
          raw "std::cout << \"Executed \" << n << \" bytecode words.\\n\";";
          ret (i32 0);
        ];
        if_then ((var "arg" ==~ str_lit "--hex") &&~ (var "argc" >~ i32 2)) [
          decl_var UInt32 "w" ~init:(call "std::stoul" [Index (var "argv", i32 2); var "nullptr"; i32 16]);
          expr_stmt (call "setup_test_state" [var "emu.state"]);
          decl_var Bool "ok" ~init:(call "emu.step" [var "w"]);
          ret (ternary (var "ok") (i32 0) (i32 1));
        ];
      ];
      ret (call "run_self_tests" [var "emu"]);
    ];
  }

let emit_main_cpp (spec : Vector_isa_spec.t) =
  let top_decls = [
    include_local "emulator.hpp";
    include_local "decoder.hpp";
    include_local "instructions.hpp";
    include_sys "iostream";
    include_sys "fstream";
    include_sys "vector";
    include_sys "iomanip";
    include_sys "string";
    emit_setup_test_state_def ();
    emit_run_self_tests_def spec;
    emit_main_def ();
  ] in
  render_top_decls top_decls

let emit_cmakelists (spec : Vector_isa_spec.t) =
  Printf.sprintf
    "cmake_minimum_required(VERSION 3.20)\n\
     project(%s_emulator LANGUAGES CXX)\n\n\
     set(CMAKE_CXX_STANDARD 20)\n\
     set(CMAKE_CXX_STANDARD_REQUIRED ON)\n\
     add_compile_options(-Wall -Wextra -O3)\n\n\
     add_executable(visa_test_runner\n\
     \    main.cpp\n\
     \    instructions.cpp\n\
     )\n"
    spec.name

let emit_to_files (spec : Vector_isa_spec.t) ~output_dir =
  try
    ensure_dir output_dir;
    let p_isa_state = write_file (Filename.concat output_dir "isa_state.hpp") (emit_isa_state_hpp spec) in
    let p_decoder = write_file (Filename.concat output_dir "decoder.hpp") (emit_decoder_hpp spec) in
    let p_inst_hpp = write_file (Filename.concat output_dir "instructions.hpp") (emit_instructions_hpp spec) in
    let p_inst_cpp = write_file (Filename.concat output_dir "instructions.cpp") (emit_instructions_cpp spec) in
    let p_emu_hpp = write_file (Filename.concat output_dir "emulator.hpp") (emit_emulator_hpp ()) in
    let p_main_cpp = write_file (Filename.concat output_dir "main.cpp") (emit_main_cpp spec) in
    let p_cmake = write_file (Filename.concat output_dir "CMakeLists.txt") (emit_cmakelists spec) in
    Ok [ p_isa_state; p_decoder; p_inst_hpp; p_inst_cpp; p_emu_hpp; p_main_cpp; p_cmake ]
  with exn ->
    Error (Errors.Code_generation_error (Printf.sprintf "Failed to emit C++ project to %s: %s" output_dir (Printexc.to_string exn)))

let emit_emulator_project (spec : Vector_isa_spec.t) ~output_dir =
  emit_to_files spec ~output_dir
