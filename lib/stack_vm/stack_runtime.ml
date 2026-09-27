open Stack_ir

type target_arch = X86_64 | AArch64 | RV64

type runtime_config = {
  arch : target_arch;
  pcode_reg : string;   (* VIP *)
  stack_reg : string;   (* VSP *)
  crypt_reg : string;   (* VKEY *)
  disp_reg : string;    (* VDISP *)
  ctx_reg : string;     (* VCTX *)
}

let default_config = function
  | X86_64 -> {
      arch = X86_64;
      pcode_reg = "rsi";
      stack_reg = "rbp";
      crypt_reg = "r12";
      disp_reg = "r13";
      ctx_reg = "r14";
    }
  | AArch64 -> {
      arch = AArch64;
      pcode_reg = "x19";
      stack_reg = "x20";
      crypt_reg = "x21";
      disp_reg = "x22";
      ctx_reg = "x23";
    }
  | RV64 -> {
      arch = RV64;
      pcode_reg = "s1";
      stack_reg = "s2";
      crypt_reg = "s3";
      disp_reg = "s4";
      ctx_reg = "s5";
    }

let emit_entry_stub cfg total_slots =
  match cfg.arch with
  | X86_64 -> [
      "push    rbx";
      "push    rbp";
      "push    r12";
      "push    r13";
      "push    r14";
      "push    r15";
      Printf.sprintf "sub     rsp, %d" (total_slots * 8 + 4096);
      Printf.sprintf "lea     %s, [rsp]" cfg.ctx_reg;
      Printf.sprintf "lea     %s, [rsp + %d]" cfg.stack_reg (total_slots * 8 + 4000);
    ]
  | AArch64 -> [
      "stp     x19, x20, [sp, #-80]!";
      "stp     x21, x22, [sp, #16]";
      "stp     x23, x24, [sp, #32]";
      "stp     x29, x30, [sp, #48]";
      Printf.sprintf "sub     sp, sp, #%d" (total_slots * 8 + 4096);
      Printf.sprintf "mov     %s, sp" cfg.ctx_reg;
      Printf.sprintf "add     %s, sp, #%d" cfg.stack_reg (total_slots * 8 + 4000);
    ]
  | RV64 -> [
      "addi    sp, sp, -64";
      "sd      s1, 0(sp)";
      "sd      s2, 8(sp)";
      "sd      s3, 16(sp)";
      "sd      s4, 24(sp)";
      "sd      s5, 32(sp)";
      Printf.sprintf "addi    sp, sp, -%d" (total_slots * 8 + 4096);
      Printf.sprintf "mv      %s, sp" cfg.ctx_reg;
    ]

let emit_exit_stub cfg total_slots =
  match cfg.arch with
  | X86_64 -> [
      Printf.sprintf "add     rsp, %d" (total_slots * 8 + 4096);
      "pop     r15";
      "pop     r14";
      "pop     r13";
      "pop     r12";
      "pop     rbp";
      "pop     rbx";
      "ret";
    ]
  | AArch64 -> [
      Printf.sprintf "add     sp, sp, #%d" (total_slots * 8 + 4096);
      "ldp     x29, x30, [sp, #48]";
      "ldp     x23, x24, [sp, #32]";
      "ldp     x21, x22, [sp, #16]";
      "ldp     x19, x20, [sp], #80";
      "ret";
    ]
  | RV64 -> [
      Printf.sprintf "addi    sp, sp, %d" (total_slots * 8 + 4096);
      "ld      s1, 0(sp)";
      "ld      s2, 8(sp)";
      "ld      s3, 16(sp)";
      "ld      s4, 24(sp)";
      "ld      s5, 32(sp)";
      "addi    sp, sp, 64";
      "ret";
    ]

let emit_dispatch_epilogue cfg =
  match cfg.arch with
  | X86_64 -> [
      Printf.sprintf "movzx   eax, byte ptr [%s]" cfg.pcode_reg;
      Printf.sprintf "add     %s, 1" cfg.pcode_reg;
      Printf.sprintf "xor     eax, %sd" cfg.crypt_reg;
      Printf.sprintf "add     %sd, eax" cfg.crypt_reg;
      Printf.sprintf "add     %s, rax" cfg.disp_reg;
      Printf.sprintf "jmp     %s" cfg.disp_reg;
    ]
  | AArch64 -> [
      Printf.sprintf "ldrb    w0, [%s], #1" cfg.pcode_reg;
      Printf.sprintf "eor     w0, w0, %s" cfg.crypt_reg;
      Printf.sprintf "add     %s, %s, w0" cfg.crypt_reg cfg.crypt_reg;
      Printf.sprintf "add     %s, %s, x0" cfg.disp_reg cfg.disp_reg;
      Printf.sprintf "br      %s" cfg.disp_reg;
    ]
  | RV64 -> [
      Printf.sprintf "lbu     t0, 0(%s)" cfg.pcode_reg;
      Printf.sprintf "addi    %s, %s, 1" cfg.pcode_reg cfg.pcode_reg;
      Printf.sprintf "xor     t0, t0, %s" cfg.crypt_reg;
      Printf.sprintf "add     %s, %s, t0" cfg.crypt_reg cfg.crypt_reg;
      Printf.sprintf "add     %s, %s, t0" cfg.disp_reg cfg.disp_reg;
      Printf.sprintf "jr      %s" cfg.disp_reg;
    ]

let emit_handler cfg op =
  let body = match op with
    | Add -> [
        Printf.sprintf "mov     rax, [%s]" cfg.stack_reg;
        Printf.sprintf "add     rax, [%s + 8]" cfg.stack_reg;
        Printf.sprintf "add     %s, 8" cfg.stack_reg;
        Printf.sprintf "mov     [%s], rax" cfg.stack_reg;
      ]
    | Sub -> [
        Printf.sprintf "mov     rax, [%s]" cfg.stack_reg;
        Printf.sprintf "sub     rax, [%s + 8]" cfg.stack_reg;
        Printf.sprintf "add     %s, 8" cfg.stack_reg;
        Printf.sprintf "mov     [%s], rax" cfg.stack_reg;
      ]
    | Nor -> [
        Printf.sprintf "mov     rax, [%s]" cfg.stack_reg;
        Printf.sprintf "or      rax, [%s + 8]" cfg.stack_reg;
        "not     rax";
        Printf.sprintf "add     %s, 8" cfg.stack_reg;
        Printf.sprintf "mov     [%s], rax" cfg.stack_reg;
      ]
    | Nand -> [
        Printf.sprintf "mov     rax, [%s]" cfg.stack_reg;
        Printf.sprintf "and     rax, [%s + 8]" cfg.stack_reg;
        "not     rax";
        Printf.sprintf "add     %s, 8" cfg.stack_reg;
        Printf.sprintf "mov     [%s], rax" cfg.stack_reg;
      ]
    | Dup -> [
        Printf.sprintf "mov     rax, [%s]" cfg.stack_reg;
        Printf.sprintf "sub     %s, 8" cfg.stack_reg;
        Printf.sprintf "mov     [%s], rax" cfg.stack_reg;
      ]
    | Swap -> [
        Printf.sprintf "mov     rax, [%s]" cfg.stack_reg;
        Printf.sprintf "mov     rdx, [%s + 8]" cfg.stack_reg;
        Printf.sprintf "mov     [%s], rdx" cfg.stack_reg;
        Printf.sprintf "mov     [%s + 8], rax" cfg.stack_reg;
      ]
    | _ -> [
        Printf.sprintf "nop";
      ]
  in
  body @ emit_dispatch_epilogue cfg

let generate_c_runtime
    ?(external_symbols = [])
    ?(constants = [])
    ?enc
    _cfg
    prog =
  let enc = match enc with
    | Some e -> e
    | None -> Stack_encoder.encode_program prog
  in
  let has_constants = constants <> [] in
  let constants_model =
    List.mapi (fun idx (name, bytes) ->
      let hex_bytes =
        String.concat "" (List.init (String.length bytes) (fun i ->
          Printf.sprintf "0x%02X, " (Char.code bytes.[i])))
      in
      Jingoo.Jg_types.Tobj [
        ("index", Jingoo.Jg_types.Tint idx);
        ("escaped_name", Jingoo.Jg_types.Tstr (String.escaped name));
        ("hex_bytes", Jingoo.Jg_types.Tstr hex_bytes);
        ("size", Jingoo.Jg_types.Tint (String.length bytes));
      ]
    ) constants
  in
  let has_symbols = external_symbols <> [] in
  let symbols_model =
    List.map (fun sym -> Jingoo.Jg_types.Tstr (String.escaped sym)) external_symbols
  in
  let max_bid = Hashtbl.fold (fun id _ acc -> max id acc) enc.block_offsets 0 in
  let block_offsets_model =
    let l = ref [] in
    for i = 0 to max_bid do
      let off = match Hashtbl.find_opt enc.block_offsets i with Some o -> o | None -> 0 in
      l := Jingoo.Jg_types.Tint off :: !l
    done;
    List.rev !l
  in
  let block_keys_model =
    let l = ref [] in
    for i = 0 to max_bid do
      let k = match Hashtbl.find_opt enc.block_keys i with Some k -> k | None -> enc.seed_key in
      l := Jingoo.Jg_types.Tstr (Printf.sprintf "%016LX" k) :: !l
    done;
    List.rev !l
  in
  let mk_case op_val name fn =
    Jingoo.Jg_types.Tobj [
      ("hex", Jingoo.Jg_types.Tstr (Printf.sprintf "%02X" op_val));
      ("name", Jingoo.Jg_types.Tstr name);
      ("fn", Jingoo.Jg_types.Tstr fn);
    ]
  in
  let dispatch_cases = [
    mk_case enc.op_map.op_push_imm "PUSH_IMM" "h_push_imm";
    mk_case enc.op_map.op_push_reg "PUSH_REG" "h_push_reg";
    mk_case enc.op_map.op_pop_reg "POP_REG" "h_pop_reg";
    mk_case enc.op_map.op_read_mem "READ_MEM" "h_read_mem";
    mk_case enc.op_map.op_write_mem "WRITE_MEM" "h_write_mem";
    mk_case enc.op_map.op_add "ADD" "h_add";
    mk_case enc.op_map.op_sub "SUB" "h_sub";
    mk_case enc.op_map.op_mul "MUL" "h_mul";
    mk_case enc.op_map.op_nor "NOR" "h_nor";
    mk_case enc.op_map.op_nand "NAND" "h_nand";
    mk_case enc.op_map.op_shl "SHL" "h_shl";
    mk_case enc.op_map.op_shr "SHR" "h_shr";
    mk_case enc.op_map.op_sar "SAR" "h_sar";
    mk_case enc.op_map.op_div "DIV" "h_div";
    mk_case enc.op_map.op_idiv "IDIV" "h_idiv";
    mk_case enc.op_map.op_dup "DUP" "h_dup";
    mk_case enc.op_map.op_swap "SWAP" "h_swap";
    mk_case enc.op_map.op_push_flags "PUSH_FLAGS" "h_push_flags";
    mk_case enc.op_map.op_pop_flags "POP_FLAGS" "h_pop_flags";
    mk_case enc.op_map.op_jmp_rel "JMP_REL" "h_jmp_rel";
    mk_case enc.op_map.op_jcc_rel "JCC_REL" "h_jcc_rel";
    mk_case enc.op_map.op_key_adjust "KEY_ADJUST" "h_key_adjust";
    mk_case enc.op_map.op_exit "EXIT" "h_exit";
    mk_case enc.op_map.op_call_extern "CALL_EXTERN" "h_call_extern";
    mk_case enc.op_map.op_resolve_sym "RESOLVE_SYM" "h_resolve_sym";
    mk_case enc.op_map.op_setcc "SETCC" "h_setcc";
    mk_case enc.op_map.op_cmov "CMOV" "h_cmov";
    mk_case enc.op_map.op_cmp "CMP" "h_cmp";
    mk_case enc.op_map.op_test "TEST" "h_test";
  ] in
  let models = [
    ("has_constants", Jingoo.Jg_types.Tbool has_constants);
    ("constants", Jingoo.Jg_types.Tlist constants_model);
    ("has_symbols", Jingoo.Jg_types.Tbool has_symbols);
    ("external_symbols", Jingoo.Jg_types.Tlist symbols_model);
    ("block_offsets_count", Jingoo.Jg_types.Tint (max_bid + 1));
    ("block_offsets", Jingoo.Jg_types.Tlist block_offsets_model);
    ("block_keys_count", Jingoo.Jg_types.Tint (max_bid + 1));
    ("block_keys", Jingoo.Jg_types.Tlist block_keys_model);
    ("context_slots", Jingoo.Jg_types.Tint (max 64 prog.context_slots));
    ("dispatch_cases", Jingoo.Jg_types.Tlist dispatch_cases);
    ("is_address_bound", Jingoo.Jg_types.Tbool (enc.addr_mask <> 0L));
    ("seed_key_hex", Jingoo.Jg_types.Tstr (Printf.sprintf "%016LX" enc.seed_key));
  ] in
  Stack_vm_templates.render Stack_vm_templates.runtime_hpp_template models

let emit_runner_cpp ?(header_name = "stack_vm_runtime.hpp") bytecode =
  let words =
    List.map (fun w -> Jingoo.Jg_types.Tstr (Printf.sprintf "%016LX" w)) bytecode
  in
  let models = [
    ("header_name", Jingoo.Jg_types.Tstr header_name);
    ("words", Jingoo.Jg_types.Tlist words);
  ] in
  Stack_vm_templates.render Stack_vm_templates.runner_cpp_template models

let emit_probe_cpp ?(header_name = "stack_vm_runtime.hpp") () =
  let models = [
    ("header_name", Jingoo.Jg_types.Tstr header_name);
  ] in
  Stack_vm_templates.render Stack_vm_templates.probe_cpp_template models
