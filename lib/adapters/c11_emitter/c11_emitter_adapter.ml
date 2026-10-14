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

let emit_csr_state_c11_def () : top_decl list =
  [
    struct_decl "CSRState" [
      (UInt64, "vl");
      (UInt64, "vtype");
      (UInt64, "vstart");
      (UInt64, "vxrm");
      (UInt64, "vxsat");
      (UInt64, "pc");
    ];
    typedef (StructType "struct CSRState") "CSRState";
  ]

let emit_vreg_file_c11_def () : top_decl list =
  [
    raw_top "typedef struct {\n    _Alignas(64) uint8_t regs[VISA_NUM_VREGS][VISA_VLEN_BYTES];\n} VRegFile;";
  ]

let emit_emulator_state_c11_def () : top_decl list =
  [
    struct_decl "EmulatorState" [
      (StructType "VRegFile", "vregs");
      (Array (UInt64, 32), "xregs");
      (StructType "CSRState", "csr");
    ];
    typedef (StructType "struct EmulatorState") "EmulatorState";
  ]

let emit_decoded_inst_c11_def () : top_decl list =
  [
    struct_decl "DecodedInstruction" [
      (ConstPtr (StructType "char"), "mnemonic");
      (UInt8, "opcode");
      (UInt8, "funct3");
      (UInt8, "funct6");
      (UInt8, "vd");
      (UInt8, "vs2");
      (UInt8, "vs1");
      (UInt8, "rs1");
      (Int8, "imm");
      (UInt8, "vm");
      (UInt32, "raw_word");
    ];
    typedef (StructType "struct DecodedInstruction") "DecodedInstruction";
  ]

let emit_c11_prototypes () : top_decl list =
  let emu_state_ptr = Ptr (StructType "EmulatorState") in
  let const_emu_state_ptr = ConstPtr (StructType "EmulatorState") in
  let const_decoded_ptr = ConstPtr (StructType "DecodedInstruction") in
  [
    func_proto Void "visa_emulator_init" [(emu_state_ptr, "state")];
    func_proto Void "visa_emulator_reset" [(emu_state_ptr, "state")];
    func_proto UInt64 "visa_get_xreg" [(const_emu_state_ptr, "state"); (SizeT, "idx")];
    func_proto Void "visa_set_xreg" [(emu_state_ptr, "state"); (SizeT, "idx"); (UInt64, "val")];
    func_proto Bool "visa_is_mask_set" [(const_emu_state_ptr, "state"); (SizeT, "mask_reg"); (SizeT, "elem_idx")];
    func_proto Void "visa_dump_vregs" [(const_emu_state_ptr, "state")];
    func_proto (StructType "DecodedInstruction") "visa_decode" [(UInt32, "word")];
    func_proto Bool "visa_execute" [(emu_state_ptr, "state"); (const_decoded_ptr, "inst")];
    func_proto Bool "visa_step" [(emu_state_ptr, "state"); (UInt32, "word")];
    func_proto SizeT "visa_run_program" [(emu_state_ptr, "state"); (ConstPtr UInt32, "program"); (SizeT, "count")];
  ]

let emit_header (spec : Vector_isa_spec.t) =
  let b = Buffer.create 2048 in
  let vlen = spec.config.vlen in
  let num_vregs = spec.config.num_vregs in
  Buffer.add_string b "#ifndef VISA_EMULATOR_H\n#define VISA_EMULATOR_H\n\n";
  Buffer.add_string b "#include <stdint.h>\n#include <stddef.h>\n#include <stdbool.h>\n#include <string.h>\n#include <stdio.h>\n\n";
  Buffer.add_string b (Printf.sprintf "#define VISA_VLEN %d\n" vlen);
  Buffer.add_string b "#define VISA_VLEN_BYTES (VISA_VLEN / 8)\n";
  Buffer.add_string b (Printf.sprintf "#define VISA_NUM_VREGS %d\n" num_vregs);
  Buffer.add_string b "#define VISA_NUM_XREGS 32\n\n";
  Buffer.add_string b (render_top_decls (emit_csr_state_c11_def ()));
  Buffer.add_string b "\n\n";
  Buffer.add_string b (render_top_decls (emit_vreg_file_c11_def ()));
  Buffer.add_string b "\n\n";
  Buffer.add_string b (render_top_decls (emit_emulator_state_c11_def ()));
  Buffer.add_string b "\n\n";
  Buffer.add_string b (render_top_decls (emit_decoded_inst_c11_def ()));
  Buffer.add_string b "\n\n";
  Buffer.add_string b (render_top_decls (emit_c11_prototypes ()));
  Buffer.add_string b "\n\n#endif // VISA_EMULATOR_H\n";
  Buffer.contents b

let cast = c_cast

let emit_emulator_c (spec : Vector_isa_spec.t) =
  let b = Buffer.create 2048 in
  let sew = Types.Sew.to_bits spec.config.default_sew in
  let default_vl = spec.config.vlen / sew in
  let groups = group_by_funct6 spec.instructions in
  let decode_cases =
    List.map (fun (f6, insts) ->
      (i32 f6,
       List.map (fun (inst : Vector_instruction.t) ->
         if_then ((var "dec" $. "funct3") ==~ i32 inst.funct3) [
           (var "dec" $. "mnemonic") := str_lit inst.mnemonic;
           ret (var "dec");
         ]
       ) insts @ [break_stmt])
    ) groups
  in
  let funcs = [
    func_decl Void "visa_emulator_init" [(Ptr (StructType "EmulatorState"), "state")] [
      expr_stmt (call "memset" [var "state"; i32 0; call "sizeof" [deref (var "state")]]);
      (var "state" $-> "csr.vl") := i32 default_vl;
      (var "state" $-> "csr.pc") := u64 0x80000000L;
    ];
    func_decl Void "visa_emulator_reset" [(Ptr (StructType "EmulatorState"), "state")] [
      expr_stmt (call "visa_emulator_init" [var "state"]);
    ];
    func_decl UInt64 "visa_get_xreg" [(ConstPtr (StructType "EmulatorState"), "state"); (SizeT, "idx")] [
      if_then ((var "idx" ==~ i32 0) ||~ (var "idx" >=~ var "VISA_NUM_XREGS")) [
        ret (u64 0L);
      ];
      ret (Index (var "state" $-> "xregs", var "idx"));
    ];
    func_decl Void "visa_set_xreg" [(Ptr (StructType "EmulatorState"), "state"); (SizeT, "idx"); (UInt64, "val")] [
      if_then ((var "idx" >~ i32 0) &&~ (var "idx" <~ var "VISA_NUM_XREGS")) [
        Index (var "state" $-> "xregs", var "idx") := var "val";
      ];
    ];
    func_decl Bool "visa_is_mask_set" [(ConstPtr (StructType "EmulatorState"), "state"); (SizeT, "mask_reg"); (SizeT, "elem_idx")] [
      if_then (var "mask_reg" >=~ var "VISA_NUM_VREGS") [ret (bool_lit false)];
      decl_var SizeT "byte_idx" ~init:(var "elem_idx" /~ i32 8);
      decl_var SizeT "bit_idx" ~init:(var "elem_idx" %~ i32 8);
      if_then (var "byte_idx" >=~ var "VISA_VLEN_BYTES") [ret (bool_lit false)];
      ret (ne (Index (Index (var "state" $-> "vregs.regs", var "mask_reg"), var "byte_idx") &~ (i32 1 <<~ var "bit_idx")) (i32 0));
    ];
    func_decl Void "visa_dump_vregs" [(ConstPtr (StructType "EmulatorState"), "state")] [
      for_range "i" (i32 0) (var "VISA_NUM_VREGS") [
        expr_stmt (call "printf" [str_lit "v%02zu: [ "; var "i"]);
        raw "for (int b = (int)VISA_VLEN_BYTES - 1; b >= 0; --b) printf(\"%02x \", state->vregs.regs[i][b]);";
        expr_stmt (call "printf" [str_lit "]\n"]);
      ];
    ];
    func_decl (StructType "DecodedInstruction") "visa_decode" [(UInt32, "word")] [
      decl_var (StructType "DecodedInstruction") "dec";
      expr_stmt (call "memset" [addr_of (var "dec"); i32 0; call "sizeof" [var "dec"]]);
      (var "dec" $. "raw_word") := var "word";
      (var "dec" $. "opcode") := var "word" &~ u32 0x7Fl;
      (var "dec" $. "vd") := (var "word" >>~ i32 7) &~ u32 0x1Fl;
      (var "dec" $. "funct3") := (var "word" >>~ i32 12) &~ u32 0x7l;
      (var "dec" $. "vs1") := (var "word" >>~ i32 15) &~ u32 0x1Fl;
      (var "dec" $. "rs1") := (var "dec" $. "vs1");
      decl_var Int32 "imm5" ~init:(cast Int32 ((var "word" >>~ i32 15) &~ u32 0x1Fl));
      if_then (ne (var "imm5" &~ i32 0x10) (i32 0)) [
        var "imm5" |= bit_not (i32 0x1F);
      ];
      (var "dec" $. "imm") := cast Int8 (var "imm5");
      (var "dec" $. "vs2") := (var "word" >>~ i32 20) &~ u32 0x1Fl;
      (var "dec" $. "vm") := (var "word" >>~ i32 25) &~ u32 0x1l;
      (var "dec" $. "funct6") := (var "word" >>~ i32 26) &~ u32 0x3Fl;
      (var "dec" $. "mnemonic") := str_lit "unknown";
      if_then (ne (var "dec" $. "opcode") (u32 0x57l)) [
        ret (var "dec");
      ];
      switch (var "dec" $. "funct6") decode_cases (Some [break_stmt]);
      ret (var "dec");
    ];
    func_decl Bool "visa_step" [(Ptr (StructType "EmulatorState"), "state"); (UInt32, "word")] [
      decl_var (StructType "DecodedInstruction") "dec" ~init:(call "visa_decode" [var "word"]);
      if_then (call "strcmp" [var "dec" $. "mnemonic"; str_lit "unknown"] ==~ i32 0) [ret (bool_lit false)];
      decl_var Bool "ok" ~init:(call "visa_execute" [var "state"; addr_of (var "dec")]);
      if_then (var "ok") [(var "state" $-> "csr.pc") += i32 4];
      ret (var "ok");
    ];
    func_decl SizeT "visa_run_program" [(Ptr (StructType "EmulatorState"), "state"); (ConstPtr UInt32, "program"); (SizeT, "count")] [
      decl_var SizeT "executed" ~init:(i32 0);
      for_range "i" (i32 0) (var "count") [
        if_then (log_not (call "visa_step" [var "state"; Index (var "program", var "i")])) [break_stmt];
        var "executed" += i32 1;
      ];
      ret (var "executed");
    ];
  ] in
  Buffer.add_string b "#include \"visa_emulator.h\"\n\n";
  Buffer.add_string b (render_top_decls funcs);
  Buffer.contents b

let generate_c11_op_expr (inst : Vector_instruction.t) : expr =
  match inst.binary_op with
  | Some ADD -> cast Int32 (cast UInt32 (var "op2") +~ cast UInt32 (var "op1"))
  | Some SUB -> cast Int32 (cast UInt32 (var "op2") -~ cast UInt32 (var "op1"))
  | Some MUL -> cast Int32 (cast UInt32 (var "op2") *~ cast UInt32 (var "op1"))
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
  | Some SLL -> cast Int32 (cast UInt32 (var "op2") <<~ (var "op1" &~ var "31u"))
  | Some SRL -> cast Int32 (cast UInt32 (var "op2") >>~ (var "op1" &~ var "31u"))
  | Some SRA -> var "op2" >>~ (var "op1" &~ var "31u")
  | Some MIN -> ternary (var "op2" <~ var "op1") (var "op2") (var "op1")
  | Some MAX -> ternary (var "op2" >~ var "op1") (var "op2") (var "op1")
  | Some SADD -> call "clamp_i32" [cast Int64 (var "op2") +~ cast Int64 (var "op1")]
  | Some SSUB -> call "clamp_i32" [cast Int64 (var "op2") -~ cast Int64 (var "op1")]
  | Some CMPEQ -> ternary (var "op2" ==~ var "op1") (i32 1) (i32 0)
  | Some CMPNE -> ternary (ne (var "op2") (var "op1")) (i32 1) (i32 0)
  | Some CMPLT -> ternary (var "op2" <~ var "op1") (i32 1) (i32 0)
  | Some CMPGE -> ternary (var "op2" >=~ var "op1") (i32 1) (i32 0)
  | None -> (
      match inst.unary_op with
      | Some NEG -> cast Int32 (var "0u" -~ cast UInt32 (var "op2"))
      | Some NOT -> bit_not (var "op2")
      | Some ABS ->
          ternary (var "op2" ==~ var "INT32_MIN") (var "INT32_MIN")
            (ternary (var "op2" <~ i32 0) (neg (var "op2")) (var "op2"))
      | Some CLZ -> ternary (var "op2" ==~ i32 0) (i32 32) (call "__builtin_clz" [cast UInt32 (var "op2")])
      | Some CTZ -> ternary (var "op2" ==~ i32 0) (i32 32) (call "__builtin_ctz" [cast UInt32 (var "op2")])
      | Some CPOP -> call "__builtin_popcount" [cast UInt32 (var "op2")]
      | None -> var "op2")

let emit_exec_c11_inst (inst : Vector_instruction.t) : top_decl =
  let body_header = [
    decl_var ~is_const:true SizeT "vl" ~init:(cast SizeT (var "state" $-> "csr.vl"));
    decl_var (Ptr Int32) "vd_ptr" ~init:(cast (Ptr Int32) (Index (var "state" $-> "vregs.regs", var "inst" $-> "vd")));
    decl_var (ConstPtr Int32) "vs2_ptr" ~init:(cast (ConstPtr Int32) (Index (var "state" $-> "vregs.regs", var "inst" $-> "vs2")));
  ] in
  let has_op1_scalar = inst.format = Types.Instruction_format.OP_VX || inst.format = Types.Instruction_format.OP_VI in
  let op1_setup =
    if has_op1_scalar then
      if inst.format = Types.Instruction_format.OP_VX then
        [decl_var ~is_const:true Int32 "op1_scalar" ~init:(cast Int32 (call "visa_get_xreg" [var "state"; var "inst" $-> "rs1"]))]
      else
        [decl_var ~is_const:true Int32 "op1_scalar" ~init:(cast Int32 (var "inst" $-> "imm"))]
    else if inst.binary_op <> None then
      [decl_var (ConstPtr Int32) "vs1_ptr" ~init:(cast (ConstPtr Int32) (Index (var "state" $-> "vregs.regs", var "inst" $-> "vs1")))]
    else
      []
  in
  let expr = generate_c11_op_expr inst in
  let unmasked_loop_body =
    [
      decl_var Int32 "op2" ~init:(Index (var "vs2_ptr", var "i"));
    ] @ (
      if inst.binary_op <> None then
        if has_op1_scalar then
          [decl_var Int32 "op1" ~init:(var "op1_scalar")]
        else
          [decl_var Int32 "op1" ~init:(Index (var "vs1_ptr", var "i"))]
      else []
    ) @ [
      decl_var Int32 "res" ~init:expr;
      Index (var "vd_ptr", var "i") := var "res";
    ]
  in
  let masked_loop_body =
    [
      if_then (log_not (call "visa_is_mask_set" [var "state"; i32 0; var "i"])) [continue_stmt];
      decl_var Int32 "op2" ~init:(Index (var "vs2_ptr", var "i"));
    ] @ (
      if inst.binary_op <> None then
        if has_op1_scalar then
          [decl_var Int32 "op1" ~init:(var "op1_scalar")]
        else
          [decl_var Int32 "op1" ~init:(Index (var "vs1_ptr", var "i"))]
      else []
    ) @ [
      decl_var Int32 "res" ~init:expr;
      Index (var "vd_ptr", var "i") := var "res";
    ]
  in
  let loops =
    if_then_else
      ((var "inst" $-> "vm") ==~ i32 1)
      [for_range "i" (i32 0) (var "vl") unmasked_loop_body]
      [for_range "i" (i32 0) (var "vl") masked_loop_body]
  in
  func_decl ~attrs:[StaticFn] Bool ("exec_" ^ inst.mnemonic)
    [(Ptr (StructType "EmulatorState"), "state"); (ConstPtr (StructType "DecodedInstruction"), "inst")]
    (body_header @ op1_setup @ [loops; ret (bool_lit true)])

let emit_instructions_c (spec : Vector_isa_spec.t) =
  let b = Buffer.create 4096 in
  let clamp_func =
    func_decl ~attrs:[StaticFn; InlineFn] Int32 "clamp_i32" [(Int64, "val")] [
      if_then (var "val" <~ cast Int64 (var "INT32_MIN")) [ret (var "INT32_MIN")];
      if_then (var "val" >~ cast Int64 (var "INT32_MAX")) [ret (var "INT32_MAX")];
      ret (cast Int32 (var "val"));
    ]
  in
  let exec_funcs = List.map emit_exec_c11_inst spec.instructions in
  let visa_execute_func =
    func_decl Bool "visa_execute"
      [(Ptr (StructType "EmulatorState"), "state"); (ConstPtr (StructType "DecodedInstruction"), "inst")]
      (List.map (fun (inst : Vector_instruction.t) ->
         if_then (call "strcmp" [var "inst" $-> "mnemonic"; str_lit inst.mnemonic] ==~ i32 0) [
           ret (call ("exec_" ^ inst.mnemonic) [var "state"; var "inst"]);
         ]
       ) spec.instructions @ [ret (bool_lit false)])
  in
  Buffer.add_string b "#include \"visa_emulator.h\"\n#include <limits.h>\n\n";
  Buffer.add_string b (render_top_decls ([clamp_func] @ exec_funcs @ [visa_execute_func]));
  Buffer.contents b

let emit_main_c (spec : Vector_isa_spec.t) =
  let b = Buffer.create 4096 in
  let setup_test_state =
    func_decl ~attrs:[StaticFn] Void "setup_test_state" [(Ptr (StructType "EmulatorState"), "state")] [
      for_range "i" (i32 0) (var "state" $-> "csr.vl") [
        Index (cast (Ptr Int32) (Index (var "state" $-> "vregs.regs", i32 1)), var "i") :=
          cast Int32 ((var "i" +~ i32 1) *~ i32 10);
        Index (cast (Ptr Int32) (Index (var "state" $-> "vregs.regs", i32 2)), var "i") :=
          cast Int32 ((var "i" +~ i32 1) *~ i32 2);
      ];
      expr_stmt (call "visa_set_xreg" [var "state"; i32 1; u64 5L]);
    ]
  in
  let test_cases =
    List.map (fun (inst : Vector_instruction.t) ->
      let word = Vector_instruction.encode ~vd:3 ~vs2:2 ~vs1_or_rs1_or_imm:1 ~vm:1 inst in
      Block [
        expr_stmt (call "setup_test_state" [var "state"]);
        decl_var UInt32 "word" ~init:(u32 word);
        decl_var Bool "ok" ~init:(call "visa_step" [var "state"; var "word"]);
        if_then (log_not (var "ok")) [
          expr_stmt (call "fprintf" [var "stderr"; str_lit (Printf.sprintf "[FAIL] %s failed to execute\n" inst.mnemonic)]);
          ret (i32 1);
        ];
        expr_stmt (call "printf" [
          str_lit (Printf.sprintf "[TEST] %s: word=0x%%08x res[0]=%%d\n" inst.mnemonic);
          var "word";
          Index (cast (Ptr Int32) (Index (var "state" $-> "vregs.regs", i32 3)), i32 0);
        ]);
        var "passed" += i32 1;
      ]
    ) spec.instructions
  in
  let run_self_tests =
    func_decl ~attrs:[StaticFn] Int32 "run_self_tests" [(Ptr (StructType "EmulatorState"), "state")] (
      [decl_var Int32 "passed" ~init:(i32 0)]
      @ test_cases
      @ [
        expr_stmt (call "printf" [
          str_lit "=== ALL C11 EMULATOR TESTS PASSED (%d instructions verified) ===\n";
          var "passed";
        ]);
        ret (i32 0);
      ]
    )
  in
  let main_func =
    func_decl Int32 "main" [(Int32, "argc"); (Ptr (Ptr (StructType "char")), "argv")] [
      decl_var (StructType "EmulatorState") "state";
      expr_stmt (call "visa_emulator_init" [addr_of (var "state")]);
      if_then (var "argc" >~ i32 1) [
        if_then ((call "strcmp" [Index (var "argv", i32 1); str_lit "--hex"] ==~ i32 0) &&~ (var "argc" >~ i32 2)) [
          decl_var UInt32 "w" ~init:(cast UInt32 (call "strtoul" [Index (var "argv", i32 2); var "NULL"; i32 16]));
          expr_stmt (call "setup_test_state" [addr_of (var "state")]);
          ret (ternary (call "visa_step" [addr_of (var "state"); var "w"]) (i32 0) (i32 1));
        ];
      ];
      ret (call "run_self_tests" [addr_of (var "state")]);
    ]
  in
  Buffer.add_string b "#include \"visa_emulator.h\"\n#include <stdlib.h>\n\n";
  Buffer.add_string b (render_top_decls [setup_test_state; run_self_tests; main_func]);
  Buffer.contents b

let emit_makefile () =
  let b = Buffer.create 512 in
  Buffer.add_string b "CC ?= clang\nCFLAGS ?= -std=c11 -O2 -Wall -Wextra -I.\nOBJS = visa_emulator.o visa_instructions.o main.o\nTARGET = visa_c11_test_runner\n\n";
  Buffer.add_string b "all: $(TARGET)\n\n";
  Buffer.add_string b "$(TARGET): $(OBJS)\n\t$(CC) $(CFLAGS) -o $@ $^\n\n";
  Buffer.add_string b "%.o: %.c visa_emulator.h\n\t$(CC) $(CFLAGS) -c $< -o $@\n\n";
  Buffer.add_string b "clean:\n\trm -f $(OBJS) $(TARGET)\n\n";
  Buffer.add_string b ".PHONY: all clean\n";
  Buffer.contents b

let emit_c_project ?(allow_widening = false) (spec : Vector_isa_spec.t) ~output_dir =
  let has_widening = List.exists (fun (i : Vector_instruction.t) -> i.is_widening) spec.instructions in
  if has_widening && not allow_widening then
    Error (Errors.Unsupported_backend_feature "C11 emitter does not support widening instructions in bare-metal profile")
  else
    try
      ensure_dir output_dir;
      let p_h = write_file (Filename.concat output_dir "visa_emulator.h") (emit_header spec) in
      let p_emu_c = write_file (Filename.concat output_dir "visa_emulator.c") (emit_emulator_c spec) in
      let p_inst_c = write_file (Filename.concat output_dir "visa_instructions.c") (emit_instructions_c spec) in
      let p_main_c = write_file (Filename.concat output_dir "main.c") (emit_main_c spec) in
      let p_make = write_file (Filename.concat output_dir "Makefile") (emit_makefile ()) in
      Ok [ p_h; p_emu_c; p_inst_c; p_main_c; p_make ]
    with exn ->
      Error (Errors.Code_generation_error (Printf.sprintf "Failed to emit C11 project to %s: %s" output_dir (Printexc.to_string exn)))
