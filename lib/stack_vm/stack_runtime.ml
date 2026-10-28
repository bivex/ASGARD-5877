open Stack_ir
open Random_visa_constants.Magic_numbers

type target_arch = X86_64 | AArch64 | RV64

type runtime_config = {
  arch : target_arch;
  pcode_reg : string;   (* VIP *)
  stack_reg : string;   (* VSP *)
  crypt_reg : string;   (* VKEY *)
  disp_reg : string;    (* VDISP *)
  ctx_reg : string;     (* VCTX *)
  enable_hw_binding : bool;
  enable_address_bound : bool;
  comp_stall_params : (int * int64 * int64 * int64) option;
  host_stack_size_kb : int;
  (** Pipelined Stage Dispatch plan (docs/Pipelined_stage_dispatch.md):
      [None] emits the legacy centralized dispatch-step macro; [Some plan]
      decouples the dispatch into per-handler ASG_PIPELINED_PREFETCH /
      ASG_PIPELINED_DISPATCH epilogues with a Stage-2 chaff XOR over the
      plan's dead ctx slots. *)
  pipelined : Pipelined_dispatch_pass.dispatch_plan option;
}

let default_config = function
  | X86_64 -> {
      arch = X86_64;
      pcode_reg = "rsi";
      stack_reg = "rbp";
      crypt_reg = "r12";
      disp_reg = "r13";
      ctx_reg = "r14";
      enable_hw_binding = true;
      enable_address_bound = false;
      comp_stall_params = None;
      host_stack_size_kb = 1024;
      pipelined = None;
    }
  | AArch64 -> {
      arch = AArch64;
      pcode_reg = "x19";
      stack_reg = "x20";
      crypt_reg = "x21";
      disp_reg = "x22";
      ctx_reg = "x23";
      enable_hw_binding = true;
      enable_address_bound = false;
      comp_stall_params = None;
      host_stack_size_kb = 1024;
      pipelined = None;
    }
  | RV64 -> {
      arch = RV64;
      pcode_reg = "s1";
      stack_reg = "s2";
      crypt_reg = "s3";
      disp_reg = "s4";
      ctx_reg = "s5";
      enable_hw_binding = true;
      enable_address_bound = false;
      comp_stall_params = None;
      host_stack_size_kb = 1024;
      pipelined = None;
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
    | Dup2 -> [
        Printf.sprintf "mov     rax, [%s]" cfg.stack_reg;
        Printf.sprintf "mov     rdx, [%s + 8]" cfg.stack_reg;
        Printf.sprintf "sub     %s, 16" cfg.stack_reg;
        Printf.sprintf "mov     [%s], rax" cfg.stack_reg;
        Printf.sprintf "mov     [%s + 8], rdx" cfg.stack_reg;
      ]
    | Rot -> [
        Printf.sprintf "mov     rax, [%s]" cfg.stack_reg;
        Printf.sprintf "mov     rdx, [%s + 8]" cfg.stack_reg;
        Printf.sprintf "mov     rcx, [%s + 16]" cfg.stack_reg;
        Printf.sprintf "mov     [%s], rcx" cfg.stack_reg;
        Printf.sprintf "mov     [%s + 8], rax" cfg.stack_reg;
        Printf.sprintf "mov     [%s + 16], rdx" cfg.stack_reg;
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

let identifier_scramble_map seed =
  let tbl = Hashtbl.create 64 in
  let add_id name prefix =
    let h = Hashtbl.hash (name ^ Int64.to_string seed) land 0x7FFFFFFF in
    let new_name = Printf.sprintf "_asg_%s_%08x" prefix h in
    Hashtbl.replace tbl name new_name
  in
  let handlers = [
    "h_push_imm"; "h_push_imm32"; "h_push_reg"; "h_pop_reg"; "h_read_mem"; "h_write_mem";
    "h_add"; "h_sub"; "h_mul"; "h_nor"; "h_nand";
    "h_shl"; "h_shr"; "h_sar"; "h_div"; "h_idiv";
    "h_dup"; "h_dup2"; "h_rot"; "h_swap"; "h_push_flags"; "h_pop_flags";
    "h_jmp_rel"; "h_jcc_rel"; "h_key_adjust"; "h_exit";
    "h_call_extern"; "h_resolve_sym"; "h_setcc"; "h_cmov";
    "h_cmp"; "h_test"; "h_add_imm"; "h_sub_imm";
    "h_add_ii"; "h_sub_ii"; "h_set_reg_imm"; "h_add_reg_imm";
    "h_key_feedback";
  ] in
  List.iter (fun h -> add_id h "h") handlers;
  let helpers = [
    "fetch_byte"; "fetch_i16"; "fetch_i32"; "fetch_i64";
    "read_byte"; "step_key"; "feedback_hash"; "eval_cond"; "parity8";
    "asg_siphash12"; "asg_payload_tag"; "asg_payload_auth_ok";
    "asg_mem_access_ok"; "asg_mem_check_range";
  ] in
  List.iter (fun h -> add_id h "fn") helpers;
  let globals = [
    "g_stack_handler_table"; "g_stack_block_offsets";
    "g_stack_block_keys"; "g_stack_tag_keys";
  ] in
  List.iter (fun g -> add_id g "tbl") globals;
  add_id "stack_vm_t" "stk";
  add_id "VSP_ENCODE" "VE";
  add_id "VSP_MASK" "VM";
  add_id "asg_vsp_mask" "AVM";
  add_id "ASG_UNMASK_OFFSET" "UMO";
  add_id "ASG_UNMASK_KEY" "UMK";
  add_id "ASG_UNMASK_TAG_K0" "UT0";
  add_id "ASG_UNMASK_TAG_K1" "UT1";
  add_id "ASG_PAYLOAD_TAG" "PT";
  add_id "ASG_DISPATCH_STEP" "DS";
  add_id "ASG_PIPELINED_PREFETCH" "PF";
  add_id "ASG_PIPELINED_DISPATCH" "PD";
  add_id "ASG_PIPELINED_DISPATCH_RT" "PDR";
  tbl

let is_ident_start = function
  | 'a'..'z' | 'A'..'Z' | '_' -> true
  | _ -> false

let is_ident_char = function
  | 'a'..'z' | 'A'..'Z' | '0'..'9' | '_' -> true
  | _ -> false

let scramble_c_runtime ?(seed = 0x5877A564D00FL) ?(strip_comments = true) src =
  let rename_map = identifier_scramble_map seed in
  let len = String.length src in
  let buf = Buffer.create len in
  let i = ref 0 in
  while !i < len do
    let c = String.get src !i in
    if strip_comments && c = '/' && !i + 1 < len && String.get src (!i + 1) = '*' then begin
      Buffer.add_char buf ' ';
      i := !i + 2;
      while !i + 1 < len && not (String.get src !i = '*' && String.get src (!i + 1) = '/') do
        incr i
      done;
      if !i + 1 < len then i := !i + 2
      else i := len
    end else if strip_comments && c = '/' && !i + 1 < len && String.get src (!i + 1) = '/' then begin
      i := !i + 2;
      while !i < len && String.get src !i <> '\n' do
        incr i
      done
    end else if c = '"' then begin
      Buffer.add_char buf c;
      incr i;
      while !i < len && String.get src !i <> '"' do
        if String.get src !i = '\\' && !i + 1 < len then begin
          Buffer.add_char buf '\\';
          Buffer.add_char buf (String.get src (!i + 1));
          i := !i + 2
        end else begin
          Buffer.add_char buf (String.get src !i);
          incr i
        end
      done;
      if !i < len then begin
        Buffer.add_char buf '"';
        incr i
      end
    end else if c = '\'' then begin
      Buffer.add_char buf c;
      incr i;
      while !i < len && String.get src !i <> '\'' do
        if String.get src !i = '\\' && !i + 1 < len then begin
          Buffer.add_char buf '\\';
          Buffer.add_char buf (String.get src (!i + 1));
          i := !i + 2
        end else begin
          Buffer.add_char buf (String.get src !i);
          incr i
        end
      done;
      if !i < len then begin
        Buffer.add_char buf '\'';
        incr i
      end
    end else if is_ident_start c then begin
      let start_pos = !i in
      while !i < len && is_ident_char (String.get src !i) do
        incr i
      done;
      let ident = String.sub src start_pos (!i - start_pos) in
      match Hashtbl.find_opt rename_map ident with
      | Some repl -> Buffer.add_string buf repl
      | None -> Buffer.add_string buf ident
    end else begin
      Buffer.add_char buf c;
      incr i
    end
  done;
  Buffer.contents buf

let calc_stack_fnv1a32 (s : string) : int32 =
  let h = ref 0x811c9dc5L in
  for i = 0 to String.length s - 1 do
    let c = Int64.of_int (Char.code s.[i]) in
    Stdlib.(h := Int64.logand (Int64.mul (Int64.logxor !h c) 0x01000193L) 0xFFFFFFFFL)
  done;
  Int64.to_int32 !h

let emit_stack_external_symbols_table_ast external_symbols : Cpp_codegen.Cpp_ast.top_decl =
  let open Cpp_codegen.Cpp_ast in
  let open Cpp_codegen.Cpp_dsl in
  let entries =
    if external_symbols = [] then
      [ init_list [ u32 0l; u32 0l; i32 0; init_list [ i32 0 ] ] ]
    else
      List.map (fun sym ->
        let h = calc_stack_fnv1a32 sym in
        let alt_sym =
          if String.length sym > 0 && sym.[0] = '_' then
            String.sub sym 1 (String.length sym - 1)
          else "_" ^ sym
        in
        let alt_h = calc_stack_fnv1a32 alt_sym in
        let len = String.length sym in
        let enc_bytes =
          List.init len (fun i ->
            let k =
              let seed_h = Int64.logand (Int64.of_int32 h) 0xFFFFFFFFL in
              let k_val =
                Int64.logxor
                  (Int64.shift_right_logical (Int64.mul seed_h 0x5877A55AL) 16)
                  (Int64.of_int ((i * 37 + 0x5A) lxor (len * 13)))
              in
              Int64.to_int (Int64.logand k_val 0xFFL)
            in
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

let emit_stack_constants_tables_ast constants : Cpp_codegen.Cpp_ast.top_decl list =
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
        let xor_key = (0x5877A55A lxor (idx * 0x1337 + 0x42)) land 0x7FFFFFFF in
        let enc_bytes =
          List.init (String.length bytes) (fun i ->
            let orig = Char.code bytes.[i] in
            let k = ((xor_key lsr ((i land 3) * 8)) lxor (i * 0x5D + 0x33)) land 0xFF in
            u8 (orig lxor k)
          ) @ [ u8 0 ]
        in
        let enc_decl =
          global_var ~is_static:true ~is_const:true
            (Array (UInt8, 0))
            (Printf.sprintf "cdata_enc_%d" idx)
            ~init:(init_list enc_bytes)
        in
        let dec_decl =
          global_var ~is_static:true
            (Array (UInt8, String.length bytes + 1))
            (Printf.sprintf "cdata_dec_%d" idx)
        in
        [ enc_decl; dec_decl ]
      ) (List.mapi (fun i c -> (i, c)) constants)
    in
    let table_entries =
      List.mapi (fun idx (name, bytes) ->
        let h = calc_stack_fnv1a32 name in
        let alt_name =
          if String.length name > 0 && name.[0] = '_' then
            String.sub name 1 (String.length name - 1)
          else "_" ^ name
        in
        let alt_h = calc_stack_fnv1a32 alt_name in
        let xor_key = (0x5877A55A lxor (idx * 0x1337 + 0x42)) land 0x7FFFFFFF in
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

let emit_stack_block_tables_ast ~max_bid ~block_offsets ~block_keys ~tag_key0 ~tag_key1 () : Cpp_codegen.Cpp_ast.top_decl list =
  let open Cpp_codegen.Cpp_ast in
  let open Cpp_codegen.Cpp_dsl in
  let count = max_bid + 1 in
  let offsets_exprs = List.map (fun off -> u32 (Int64.to_int32 off)) block_offsets in
  let keys_exprs = List.map u64 block_keys in
  let tag_keys_exprs = [ u64 tag_key0; u64 tag_key1 ] in
  [
    raw_top "#define ASG_UNMASK_OFFSET(bid) ((uint32_t)(g_stack_block_offsets[(bid)] ^ (uint32_t)(0x5877A564UL + (uint32_t)(bid) * 0x19E3779BUL)))";
    raw_top "#define ASG_UNMASK_KEY(bid) (g_stack_block_keys[(bid)] ^ (UINT64_C(0xD00F5877A5640000) + (uint64_t)(bid) * UINT64_C(0x9E3779B97F4A7C15)))";
    global_var ~is_static:true ~is_const:true
      (Array (UInt32, count))
      "g_stack_block_offsets"
      ~init:(init_list offsets_exprs);
    global_var ~is_static:true ~is_const:true
      (Array (UInt64, count))
      "g_stack_block_keys"
      ~init:(init_list keys_exprs);
    comment_top "Payload-tag key halves, masked with the same address-binding scheme as the block keys above";
    global_var ~is_static:true ~is_const:true
      (Array (UInt64, 2))
      "g_stack_tag_keys"
      ~init:(init_list tag_keys_exprs);
    raw_top "#define ASG_UNMASK_TAG_K0() (g_stack_tag_keys[0] ^ (UINT64_C(0xD00F5877A5640000) + UINT64_C(0) * UINT64_C(0x9E3779B97F4A7C15)))";
    raw_top "#define ASG_UNMASK_TAG_K1() (g_stack_tag_keys[1] ^ (UINT64_C(0xD00F5877A5640000) + UINT64_C(1) * UINT64_C(0x9E3779B97F4A7C15)))";
  ]

let emit_stack_dispatch_stmts
    ?(pipelined : Pipelined_dispatch_pass.dispatch_plan option)
    ~entry_bid
    (cases : (int * string * string) list)
    : Cpp_codegen.Cpp_ast.stmt list =
  let open Cpp_codegen.Cpp_ast in
  let open Cpp_codegen.Cpp_dsl in
  let vip_decl =
    decl_var SizeT "vip" ~init:(call "ASG_UNMASK_OFFSET" [ i32 entry_bid ])
  in
  let used_opcodes = Hashtbl.create 256 in
  List.iter (fun (op, _, _) -> Hashtbl.add used_opcodes op true) cases;
  let unused_opcodes = List.filter (fun op -> not (Hashtbl.mem used_opcodes op)) (List.init 256 (fun i -> i)) in
  let gnuc_stmts =
    (* Pipelined Stage Dispatch: each handler ends its own epilogue with the
       decoupled Stage-1 pre-fetch and Stage-3 dispatch of the *next*
       opcode (docs/Pipelined_stage_dispatch.md); legacy mode keeps the
       single centralized dispatch-step macro. *)
    let epilogue_stmt op =
      match pipelined with
      | None -> raw "ASG_DISPATCH_STEP();"
      | Some plan ->
          (* Braced: the epilogue's goto lbl_exit must leave the scope of
             the pre-fetched opcode instead of bypassing its initializer.
             Each epilogue embeds its own compile-time slot mask [K(op)]:
             the 256 handler blocks are no longer textually identical,
             which prevents the C compiler from merging their epilogues
             into one shared trampoline (anti-centralization). *)
          raw
            (Printf.sprintf
               "{ ASG_PIPELINED_PREFETCH(op_%02X);\n\
                \  ASG_PIPELINED_DISPATCH(op_%02X, 0x%016LX, op_%02X); }"
               op op plan.Pipelined_dispatch_pass.mask_add op)
    in
    let dispatch_table_decl =
      decl_var ~is_static:true
        (Array (UIntPtr, 256))
        "dispatch_table"
    in
    let ready_decl =
      decl_var ~is_static:true Bool "dispatch_ready" ~init:(bool_lit false)
    in
    let mask_for_op op =
      match pipelined with
      | Some p ->
          Int64.logxor
            (Int64.mul (Int64.of_int op) p.Pipelined_dispatch_pass.mask_mult)
            p.Pipelined_dispatch_pass.mask_add
      | None ->
          Int64.logxor
            (Int64.mul (Int64.of_int op) cbrt3_fraction_64)
            salt_stack_dispatch_blind
    in
    let table_init_stmts =
      List.init 256 (fun op ->
        let k_slot_op = mask_for_op op in
        idx (var "dispatch_table") (u8 op) :=
          (c_cast UIntPtr (label_addr (Printf.sprintf "lbl_%02X" op))
           ^~ u64 k_slot_op
           ^~ c_cast UIntPtr (var "vm" $-> "addr_key"))
      )
    in
    let init_loop =
      if_then (call "__builtin_expect" [ log_not (var "dispatch_ready"); i32 0 ])
        (table_init_stmts @ [ var "dispatch_ready" := bool_lit true ])
    in
    let handler_blocks =
      List.concat_map (fun (op, _name, fn) ->
        [
          label (Printf.sprintf "lbl_%02X" op);
          expr_stmt (call fn [ var "vm"; var "bytecode"; addr_of (var "vip") ]);
          epilogue_stmt op;
        ]
      ) cases
    in
    let decoy_blocks =
      List.concat_map (fun op ->
        let decoy_body =
          match op mod 6 with
          | 0 ->
              [
                idx (var "vm" $-> "ctx") (i32 (op land 15)) ^= ((var "vm" $-> "vkey") +~ u64 (Int64.of_int op));
                epilogue_stmt op;
              ]
          | 1 ->
              [
                if_then ((var "vm" $-> "vsp_idx") <~ i32 4095) [
                  idx (var "vm" $-> "vsp") (var "vm" $-> "vsp_idx") := ((var "vm" $-> "vkey") ^~ u64 (Int64.of_int op));
                  (var "vm" $-> "vsp_idx") += i32 1;
                ];
                epilogue_stmt op;
              ]
          | 2 ->
              [
                if_then ((var "vm" $-> "vsp_idx") >~ i32 0) [
                  idx (var "vm" $-> "vsp") ((var "vm" $-> "vsp_idx") -~ i32 1) :=
                    (idx (var "vm" $-> "vsp") ((var "vm" $-> "vsp_idx") -~ i32 1) *~ u64 golden_ratio_64) +~ u64 (Int64.of_int op);
                ];
                epilogue_stmt op;
              ]
          | 3 ->
              [
                (var "vm" $-> "cf") := (if op land 1 <> 0 then u8 1 else u8 0);
                (var "vm" $-> "zf") := (if op land 2 <> 0 then u8 1 else u8 0);
                epilogue_stmt op;
              ]
          | 4 ->
              [
                expr_stmt (call "fetch_byte" [ var "vm"; var "bytecode"; addr_of (var "vip") ]);
                epilogue_stmt op;
              ]
          | _ ->
              [
                (var "vm" $-> "vkey") := ((var "vm" $-> "vkey") >>~ i32 7) ^~ ((var "vm" $-> "vkey") <<~ i32 57) ^~ u64 (Int64.of_int op);
                epilogue_stmt op;
              ]
        in
        [ label (Printf.sprintf "lbl_%02X" op) ] @ decoy_body
      ) unused_opcodes
    in
    let step_macro_str =
      Printf.sprintf
        "#define ASG_DISPATCH_STEP() do { \\\n\
        \        if (vm->halted || vip >= size) goto lbl_exit; \\\n\
        \        uint8_t op = fetch_byte(vm, bytecode, &vip); \\\n\
        \        uintptr_t k_slot = ((uintptr_t)op * UINT64_C(0x%016LX)) ^ UINT64_C(0x%016LX) ^ (uintptr_t)(vm->addr_key); \\\n\
        \        goto *(void*)(dispatch_table[op] ^ k_slot); \\\n\
        \    } while (0)"
        cbrt3_fraction_64 salt_stack_dispatch_blind
    in
    (* Pipelined Stage Dispatch primitives: Stage 1 decouples the opcode
       pre-fetch into each handler epilogue, Stage 2 blinds the slot with a
       constant-time chaff XOR over dead ctx slots (branchless mul/xor, no
       software-flag or vsp writes), Stage 3 unmasks the pre-blinded
       dispatch entry with the affine k_slot and jumps.  There is no shared
       re-entry label: control never returns to a central dispatch block. *)
    let pipelined_macro_str =
      match pipelined with
      | None -> None
      | Some p ->
          let base = p.Pipelined_dispatch_pass.chaff_slot_base in
          let mask = p.Pipelined_dispatch_pass.chaff_slot_count - 1 in
          Some
            (Printf.sprintf
               "#if defined(__GNUC__) || defined(__clang__)\n\
                #define ASG_INDIRECT_JUMP(target, uid) do { \\\n\
               \        __asm__ volatile (\"# asg_epilogue_\" #uid : \"+r\"(target)); \\\n\
               \        goto *(target); \\\n\
               \    } while (0)\n\
                #else\n\
                #define ASG_INDIRECT_JUMP(target, uid) goto *(target)\n\
                #endif\n\
               #define ASG_PIPELINED_PREFETCH(opv) \\\n\
               \        if (vm->halted || vip >= size) goto lbl_exit; \\\n\
               \        const uint8_t opv = fetch_byte(vm, bytecode, &vip)\n\
               \    #define ASG_PIPELINED_DISPATCH(opv, k, uid) do { \\\n\
               \        vm->ctx[(%d) + (((((uint64_t)(opv) * UINT64_C(0x%016LX)) ^ UINT64_C(0x%016LX)) >> 56) & (%d))] ^= vm->vkey + (uint64_t)(opv); \\\n\
               \        uintptr_t k_slot = ((uintptr_t)(opv) * UINT64_C(0x%016LX)) ^ UINT64_C(k) ^ (uintptr_t)(vm->addr_key); \\\n\
               \        void* target = (void*)(dispatch_table[(opv)] ^ k_slot); \\\n\
               \        ASG_INDIRECT_JUMP(target, uid); \\\n\
               \    } while (0)\n\
               \    #define ASG_PIPELINED_DISPATCH_RT(opv, uid) do { \\\n\
               \        vm->ctx[(%d) + (((((uint64_t)(opv) * UINT64_C(0x%016LX)) ^ UINT64_C(0x%016LX)) >> 56) & (%d))] ^= vm->vkey + (uint64_t)(opv); \\\n\
               \        uintptr_t k_slot = ((uintptr_t)(opv) * UINT64_C(0x%016LX)) ^ UINT64_C(0x%016LX) ^ (uintptr_t)(vm->addr_key); \\\n\
               \        void* target = (void*)(dispatch_table[opv] ^ k_slot); \\\n\
               \        ASG_INDIRECT_JUMP(target, uid); \\\n\
               \    } while (0)"
               base golden_ratio_64 p.Pipelined_dispatch_pass.chaff_salt mask
               p.Pipelined_dispatch_pass.mask_mult
               base golden_ratio_64 p.Pipelined_dispatch_pass.chaff_salt mask
               p.Pipelined_dispatch_pass.mask_mult p.Pipelined_dispatch_pass.mask_add)
    in
    let macro_defs =
      match pipelined_macro_str with
      | Some pm -> raw pm
      | None -> raw step_macro_str
    in
    (* Priming pre-fetch of I_0 before entering the handler matrix
       (Invariant 1: the entry stub owns the fetch the first handler's
       epilogue would otherwise have performed). *)
    let priming_stmts =
      match pipelined with
      | Some _ ->
          [
            raw
              "{ ASG_PIPELINED_PREFETCH(op_primer);\n\
               \  ASG_PIPELINED_DISPATCH_RT(op_primer, primer); }";
          ]
      | None -> [ raw "ASG_DISPATCH_STEP();" ]
    in
    [
      dispatch_table_decl;
      ready_decl;
      init_loop;
      macro_defs;
    ]
    @ priming_stmts
    @ handler_blocks
    @ decoy_blocks
    @ [
      label "lbl_default";
      var "vm" $-> "halted" := i32 1;
      goto "lbl_exit";
      label "lbl_exit";
      ret_void;
      raw
        (match pipelined with
         | Some _ ->
             "#undef ASG_PIPELINED_PREFETCH\n    #undef ASG_PIPELINED_DISPATCH\n    #undef ASG_PIPELINED_DISPATCH_RT"
         | None -> "#undef ASG_DISPATCH_STEP");
    ]
  in
  let fallback_cases =
    List.map (fun (op, name, fn) ->
      case ~comment:name (u8 op) [
        expr_stmt (call fn [ var "vm"; var "bytecode"; addr_of (var "vip") ]);
        break_stmt;
      ]
    ) cases
    @ List.map (fun op ->
      case (u8 op) [
        idx (var "vm" $-> "ctx") (i32 (op land 15)) ^= ((var "vm" $-> "vkey") +~ u64 (Int64.of_int op));
        break_stmt;
      ]
    ) unused_opcodes
  in
  let fallback_stmts =
    [
      while_loop (log_not (var "vm" $-> "halted") &&~ (var "vip" <~ var "size")) [
        decl_var UInt8 "op" ~init:(call "fetch_byte" [ var "vm"; var "bytecode"; addr_of (var "vip") ]);
        switch_annotated (var "op") fallback_cases (Some [ var "vm" $-> "halted" := i32 1; break_stmt ]);
      ]
    ]
  in
  [
    vip_decl;
    preproc_if_stmt "defined(__GNUC__) || defined(__clang__)" gnuc_stmts ~else_stmts:fallback_stmts;
  ]

let emit_stack_dispatch_source
    ?(pipelined : Pipelined_dispatch_pass.dispatch_plan option)
    ~entry_bid
    (cases : (int * string * string) list)
    : string =
  let stmts = emit_stack_dispatch_stmts ?pipelined ~entry_bid cases in
  Cpp_codegen.Cpp_printer.string_of_stmts stmts

let emit_h_call_extern arch : Cpp_codegen.Cpp_ast.top_decl =
  let open Cpp_codegen.Cpp_dsl in
  let reg_setup = match arch with
    | RV64 ->
        {|        uint64_t a0 = vm->ctx[0];  /* a0 (RAX) */
        uint64_t a1 = vm->ctx[2];  /* a1 (RDX) */
        uint64_t a2 = vm->ctx[1];  /* a2 (RCX) */
        uint64_t a3 = vm->ctx[6];  /* a3 (RSI) */
        uint64_t a4 = vm->ctx[7];  /* a4 (RDI) */
        uint64_t a5 = vm->ctx[8];  /* a5 (R8)  */
        uint64_t a6 = vm->ctx[9];  /* a6 (R9)  */
        uint64_t a7 = vm->ctx[12]; /* a7 (R12) */|}
    | AArch64 ->
        {|        uint64_t a0 = vm->ctx[0]; /* X0 (RAX) */
        uint64_t a1 = vm->ctx[1]; /* X1 (RCX) */
        uint64_t a2 = vm->ctx[2]; /* X2 (RDX) */
        uint64_t a3 = vm->ctx[3]; /* X3 (RBX) */
        uint64_t a4 = vm->ctx[6]; /* X4 (RSI) */
        uint64_t a5 = vm->ctx[7]; /* X5 (RDI) */
        uint64_t a6 = vm->ctx[8]; /* X6 (R8)  */
        uint64_t a7 = vm->ctx[9]; /* X7 (R9)  */|}
    | X86_64 ->
        {|        uint64_t a0 = vm->ctx[7]; /* RDI */
        uint64_t a1 = vm->ctx[6]; /* RSI */
        uint64_t a2 = vm->ctx[2]; /* RDX */
        uint64_t a3 = vm->ctx[1]; /* RCX */
        uint64_t a4 = vm->ctx[8]; /* R8  */
        uint64_t a5 = vm->ctx[9]; /* R9  */
        uint64_t a6 = vm->ctx[0]; /* RAX */
        uint64_t a7 = vm->ctx[3]; /* RBX */|}
  in
  raw_top (Printf.sprintf {|static void h_call_extern(stack_vm_t *vm, const uint8_t *bytecode, size_t *vip) {
    int32_t sym_idx = fetch_i32(vm, bytecode, vip);
    void* sym_ptr = asgard_resolve_sym_idx(sym_idx);
    if (sym_ptr) {
%s
        uint32_t sym_h = g_external_symbols[sym_idx].hash;
        uint32_t sym_ah = g_external_symbols[sym_idx].alt_hash;
        const uint64_t* stk = (const uint64_t*)vm->ctx[4];
        uint64_t ret = 0;
        if (sym_h == 0x42FCF5CFU || sym_ah == 0x42FCF5CFU || sym_h == 0x07554ACDU || sym_ah == 0x07554ACDU || sym_h == 0xE76FB4AAU || sym_ah == 0xE76FB4AAU) {
            typedef int (*printf_fn_t)(const char*, ...);
            printf_fn_t pfn = (printf_fn_t)sym_ptr;
#if defined(__APPLE__) && defined(__aarch64__)
            ret = (uint64_t)pfn((const char*)a0, stk[0], stk[1], stk[2], stk[3], stk[4], stk[5], stk[6], stk[7]);
#else
            ret = (uint64_t)pfn((const char*)a0, a1, a2, a3, a4, a5, a6, a7);
#endif
        } else if (sym_h == 0xFCB512E2U || sym_ah == 0xFCB512E2U || sym_h == 0x4B3C5330U || sym_ah == 0x4B3C5330U || sym_h == 0x937D1EF6U || sym_ah == 0x937D1EF6U || sym_h == 0xCB76D42BU || sym_ah == 0xCB76D42BU || sym_h == 0xD54CE817U || sym_ah == 0xD54CE817U || sym_h == 0xBBED3905U || sym_ah == 0xBBED3905U || sym_h == 0x42C07C7CU || sym_ah == 0x42C07C7CU || sym_h == 0x24559DBDU || sym_ah == 0x24559DBDU) {
            typedef int (*fprintf_fn_t)(void*, const char*, ...);
            fprintf_fn_t fpfn = (fprintf_fn_t)sym_ptr;
#if defined(__APPLE__) && defined(__aarch64__)
            ret = (uint64_t)fpfn((void*)a0, (const char*)a1, stk[0], stk[1], stk[2], stk[3], stk[4], stk[5], stk[6], stk[7]);
#else
            ret = (uint64_t)fpfn((void*)a0, (const char*)a1, a2, a3, a4, a5, a6, a7);
#endif
        } else if (sym_h == 0x7FE32B00U || sym_ah == 0x7FE32B00U || sym_h == 0xBCBF60EEU || sym_ah == 0xBCBF60EEU || sym_h == 0x70E2D349U || sym_ah == 0x70E2D349U || sym_h == 0x44FA3468U || sym_ah == 0x44FA3468U) {
            typedef int (*sprintf_fn_t)(char*, const char*, ...);
            sprintf_fn_t spfn = (sprintf_fn_t)sym_ptr;
#if defined(__APPLE__) && defined(__aarch64__)
            ret = (uint64_t)spfn((char*)a0, (const char*)a1, stk[0], stk[1], stk[2], stk[3], stk[4], stk[5], stk[6], stk[7]);
#else
            ret = (uint64_t)spfn((char*)a0, (const char*)a1, a2, a3, a4, a5, a6, a7);
#endif
        } else if (sym_h == 0x54EE11FAU || sym_ah == 0x54EE11FAU || sym_h == 0x933075F4U || sym_ah == 0x933075F4U || sym_h == 0x3FD5EB6FU || sym_ah == 0x3FD5EB6FU || sym_h == 0x5B3553B4U || sym_ah == 0x5B3553B4U) {
            typedef int (*snprintf_fn_t)(char*, size_t, const char*, ...);
            snprintf_fn_t snpfn = (snprintf_fn_t)sym_ptr;
#if defined(__APPLE__) && defined(__aarch64__)
            ret = (uint64_t)snpfn((char*)a0, (size_t)a1, (const char*)a2, stk[0], stk[1], stk[2], stk[3], stk[4], stk[5], stk[6], stk[7]);
#else
            ret = (uint64_t)snpfn((char*)a0, (size_t)a1, (const char*)a2, a3, a4, a5, a6, a7);
#endif
        } else {
            typedef uint64_t (*ext_fn_8)(uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t);
            ret = ((ext_fn_8)sym_ptr)(a0, a1, a2, a3, a4, a5, a6, a7);
        }
        vm->ctx[0] = ret;
    } else {
        vm->halted = 1; /* fail-closed: extern symbol unresolved */
    }
}|} reg_setup)

let emit_stack_runtime_hpp_decls
    ?(external_symbols = [])
    ?(constants = [])
    ?enc
    cfg
    prog : Cpp_codegen.Cpp_ast.top_decl list =
  let enc = match enc with
    | Some e -> e
    | None -> Stack_encoder.encode_program prog
  in
  let max_bid = Hashtbl.fold (fun id _ acc -> max id acc) enc.block_offsets 0 in
  let mask32 i =
    let base = 0x5877A564L in
    let stride = Int64.mul (Int64.of_int i) 0x19E3779BL in
    Int64.logand (Int64.add base stride) 0xFFFFFFFFL
  in
  let mask64 i =
    let base = 0xD00F5877A5640000L in
    let stride = Int64.mul (Int64.of_int i) 0x9E3779B97F4A7C15L in
    Int64.add base stride
  in
  let raw_block_offsets =
    let l = ref [] in
    for i = 0 to max_bid do
      let off = match Hashtbl.find_opt enc.block_offsets i with Some o -> o | None -> 0 in
      let masked_off = Int64.logxor (Int64.of_int off) (mask32 i) in
      l := masked_off :: !l
    done;
    List.rev !l
  in
  let raw_block_keys =
    let l = ref [] in
    for i = 0 to max_bid do
      let k = match Hashtbl.find_opt enc.block_keys i with Some k -> k | None -> enc.seed_key in
      let masked_k = Int64.logxor k (mask64 i) in
      l := masked_k :: !l
    done;
    List.rev !l
  in
  let raw_tag_key i =
    match Hashtbl.find_opt enc.tag_keys i with
    | Some k -> Int64.logxor k (mask64 i)
    | None ->
        failwith
          (Printf.sprintf
             "stack_runtime: encrypted_bytecode is missing tag key %d — \
              rebuild it with Stack_encoder.encode_program" i)
  in
  let raw_tag_key0 = raw_tag_key 0 and raw_tag_key1 = raw_tag_key 1 in

  let raw_dispatch_cases = [
    (enc.op_map.op_push_imm, "PUSH_IMM", "h_push_imm");
    (enc.op_map.op_push_imm32, "PUSH_IMM32", "h_push_imm32");
    (enc.op_map.op_push_reg, "PUSH_REG", "h_push_reg");
    (enc.op_map.op_pop_reg, "POP_REG", "h_pop_reg");
    (enc.op_map.op_read_mem, "READ_MEM", "h_read_mem");
    (enc.op_map.op_write_mem, "WRITE_MEM", "h_write_mem");
    (enc.op_map.op_add, "ADD", "h_add");
    (enc.op_map.op_sub, "SUB", "h_sub");
    (enc.op_map.op_mul, "MUL", "h_mul");
    (enc.op_map.op_nor, "NOR", "h_nor");
    (enc.op_map.op_nand, "NAND", "h_nand");
    (enc.op_map.op_shl, "SHL", "h_shl");
    (enc.op_map.op_shr, "SHR", "h_shr");
    (enc.op_map.op_sar, "SAR", "h_sar");
    (enc.op_map.op_div, "DIV", "h_div");
    (enc.op_map.op_idiv, "IDIV", "h_idiv");
    (enc.op_map.op_dup, "DUP", "h_dup");
    (enc.op_map.op_dup2, "DUP2", "h_dup2");
    (enc.op_map.op_rot, "ROT", "h_rot");
    (enc.op_map.op_swap, "SWAP", "h_swap");
    (enc.op_map.op_push_flags, "PUSH_FLAGS", "h_push_flags");
    (enc.op_map.op_pop_flags, "POP_FLAGS", "h_pop_flags");
    (enc.op_map.op_jmp_rel, "JMP_REL", "h_jmp_rel");
    (enc.op_map.op_jcc_rel, "JCC_REL", "h_jcc_rel");
    (enc.op_map.op_key_adjust, "KEY_ADJUST", "h_key_adjust");
    (enc.op_map.op_exit, "EXIT", "h_exit");
    (enc.op_map.op_call_extern, "CALL_EXTERN", "h_call_extern");
    (enc.op_map.op_resolve_sym, "RESOLVE_SYM", "h_resolve_sym");
    (enc.op_map.op_setcc, "SETCC", "h_setcc");
    (enc.op_map.op_cmov, "CMOV", "h_cmov");
    (enc.op_map.op_cmp, "CMP", "h_cmp");
    (enc.op_map.op_test, "TEST", "h_test");
    (enc.op_map.op_add_imm, "ADD_IMM", "h_add_imm");
    (enc.op_map.op_sub_imm, "SUB_IMM", "h_sub_imm");
    (enc.op_map.op_add_ii, "ADD_II", "h_add_ii");
    (enc.op_map.op_sub_ii, "SUB_II", "h_sub_ii");
    (enc.op_map.op_set_reg_imm, "SET_REG_IMM", "h_set_reg_imm");
    (enc.op_map.op_add_reg_imm, "ADD_REG_IMM", "h_add_reg_imm");
    (enc.op_map.op_key_feedback, "KEY_FEEDBACK", "h_key_feedback");
  ] in

  let open Cpp_codegen.Cpp_ast in
  let open Cpp_codegen.Cpp_dsl in
  let preamble_decls = [
    include_sys "stdint.h";
    include_sys "stdlib.h";
    include_sys "string.h";
    include_sys "stdio.h";
    preproc_if "defined(__APPLE__) && defined(__MACH__)" [
      include_sys "mach-o/dyld.h";
      include_sys "mach-o/loader.h";
    ] ~else_decls:[
      preproc_if "defined(_WIN32) || defined(_WIN64)" [
        include_sys "windows.h";
        preproc_if "defined(_MSC_VER) && !defined(__clang__)" [
          preproc_ifndef "__attribute__" [
            macro_def "__attribute__(x)";
          ];
        ];
      ] ~else_decls:[
        include_sys "dlfcn.h";
      ];
    ];
    raw_top {|static inline int asg_strcmp(const char* s1, const char* s2) noexcept {
    while (*s1 && (*s1 == *s2)) { ++s1; ++s2; }
    return *(const unsigned char*)s1 - *(const unsigned char*)s2;
}|};
  ] in

  let constants_decls = [
    struct_def "AsgardConstantEntry" [
      member_field UInt32 "hash";
      member_field UInt32 "alt_hash";
      member_field (ConstPtr UInt8) "enc_data";
      member_field (Ptr UInt8) "dec_data";
      member_field SizeT "size";
      member_field UInt32 "xor_key";
      member_field ~is_volatile:true Int32 "ready";
    ];
  ]
  @ emit_stack_constants_tables_ast constants
  @ [
    raw_top {|static inline void* asgard_resolve_constant(uint32_t hash, uint32_t alt_hash) noexcept {
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
    uint32_t h = 0x811C9DC5U;
    const char* p = name;
    while (*p) {
        h = (h ^ (uint8_t)*p++) * 0x01000193U;
    }
    uint32_t ah = 0;
    if (name[0] == '_') {
        ah = 0x811C9DC5U;
        p = name + 1;
        while (*p) {
            ah = (ah ^ (uint8_t)*p++) * 0x01000193U;
        }
    }
    return asgard_resolve_constant(h, ah);
}|};
  ] in

  let symbols_decls = [
    struct_def "asgard_ext_sym_t" [
      member_field UInt32 "hash";
      member_field UInt32 "alt_hash";
      member_field UInt16 "len";
      member_field (Array (UInt8, 64)) "enc_bytes";
    ];
    emit_stack_external_symbols_table_ast external_symbols;
    raw_top {|#if defined(__APPLE__) && defined(__MACH__)
static inline uint64_t asg_read_uleb128(const uint8_t** p) {
    uint64_t result = 0;
    int shift = 0;
    while (1) {
        uint8_t byte = *(*p)++;
        result |= ((uint64_t)(byte & 0x7f)) << shift;
        if ((byte & 0x80) == 0) break;
        shift += 7;
    }
    return result;
}

static void* asg_find_sym_in_trie(const uint8_t* trie_base, const uint8_t* node, uint32_t cur_h, uint32_t target_h, uintptr_t base) {
    const uint8_t* p = node;
    uint64_t terminal_size = asg_read_uleb128(&p);
    if (terminal_size > 0 && cur_h == target_h) {
        uint64_t flags = asg_read_uleb128(&p);
        if ((flags & 0x08) == 0) {
            uint64_t addr = asg_read_uleb128(&p);
            return (void*)(addr + base);
        }
        return nullptr;
    }
    p += terminal_size;
    uint8_t child_count = *p++;
    for (uint8_t i = 0; i < child_count; i++) {
        uint32_t child_h = cur_h;
        while (*p) {
            child_h = (child_h ^ (uint8_t)*p++) * 0x01000193U;
        }
        p++; /* skip null terminator */
        uint64_t child_offset = asg_read_uleb128(&p);
        void* res = asg_find_sym_in_trie(trie_base, trie_base + child_offset, child_h, target_h, base);
        if (res) return res;
    }
    return nullptr;
}

static void* asgard_resolve_by_api_hash(uint32_t target_hash) {
    if (target_hash == 0) return nullptr;
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const struct mach_header_64* hdr = (const struct mach_header_64*)_dyld_get_image_header(i);
        if (!hdr || hdr->magic != MH_MAGIC_64) continue;
        intptr_t slide = _dyld_get_image_vmaddr_slide(i);
        const struct load_command* cmd = (const struct load_command*)(hdr + 1);
        uintptr_t linkedit_base = 0;
        uint32_t dataoff = 0;
        for (uint32_t c = 0; c < hdr->ncmds; c++) {
            if (cmd->cmd == LC_SEGMENT_64) {
                const struct segment_command_64* seg = (const struct segment_command_64*)cmd;
                if (asg_strcmp(seg->segname, "__LINKEDIT") == 0) {
                    linkedit_base = seg->vmaddr + slide - seg->fileoff;
                }
            } else if (cmd->cmd == 0x80000033 /* LC_DYLD_EXPORTS_TRIE */) {
                const struct linkedit_data_command* lc = (const struct linkedit_data_command*)cmd;
                dataoff = lc->dataoff;
            }
            cmd = (const struct load_command*)((const char*)cmd + cmd->cmdsize);
        }
        if (linkedit_base && dataoff) {
            const uint8_t* trie = (const uint8_t*)(linkedit_base + dataoff);
            void* resolved = asg_find_sym_in_trie(trie, trie, 0x811c9dc5U, target_hash, (uintptr_t)hdr);
            if (resolved) return resolved;
        }
    }
    return nullptr;
}
#endif

static inline void asg_decrypt_sym(const asgard_ext_sym_t* sym, char* out_buf, size_t out_cap) {
    size_t n = sym->len < out_cap - 1 ? sym->len : out_cap - 1;
    uint64_t seed_h = (uint64_t)sym->hash;
    for (size_t i = 0; i < n; i++) {
        uint8_t k = (uint8_t)(((seed_h * UINT64_C(0x5877A55A)) >> 16) ^ (uint64_t)((i * 37 + 0x5A) ^ ((size_t)sym->len * 13)));
        out_buf[i] = (char)(sym->enc_bytes[i] ^ k);
    }
    out_buf[n] = '\0';
}

static void* asgard_resolve_sym_idx(int32_t sym_idx) {
    if (sym_idx < 0 || (size_t)sym_idx >= sizeof(g_external_symbols) / sizeof(g_external_symbols[0])) {
        return nullptr;
    }
    const asgard_ext_sym_t* sym = &g_external_symbols[sym_idx];
    if (sym->len == 0) return nullptr;

    void* sym_ptr = asgard_resolve_constant(sym->hash, sym->alt_hash);
    if (sym_ptr) return sym_ptr;

#if defined(__APPLE__) && defined(__MACH__)
    /* 1. Primary: Direct Mach-O export trie walking by 32-bit API Hash (0 imports) */
    sym_ptr = asgard_resolve_by_api_hash(sym->hash);
    if (!sym_ptr && sym->alt_hash != 0) {
        sym_ptr = asgard_resolve_by_api_hash(sym->alt_hash);
    }
    if (sym_ptr) return sym_ptr;
#endif

    /* 2. Secondary: Decrypt symbol name on stack */
    char dec_name[64];
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
                char alt[66];
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
            char alt[66];
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
                char alt[66];
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
}|};
  ] in

  let block_tables_decls =
    emit_stack_block_tables_ast ~max_bid ~block_offsets:raw_block_offsets ~block_keys:raw_block_keys ~tag_key0:raw_tag_key0 ~tag_key1:raw_tag_key1 ()
  in

  (* With Pipelined Stage Dispatch the ctx array must also cover the
     Stage-2 dead chaff region on top of every slot the program addresses. *)
  let context_slots =
    max 64
      (match cfg.pipelined with
       | Some p -> p.Pipelined_dispatch_pass.ctx_slots_required
       | None -> prog.context_slots)
  in
  let stack_vm_t_def =
    struct_def "stack_vm_t" [
      member_field (Array (UInt64, 4096)) "vsp";
      member_field Int32 "vsp_idx";
      member_field (Array (UInt64, context_slots)) "ctx";
      member_field UInt64 "vkey";
      member_field UInt64 "vsp_key";
      member_field UInt64 "addr_key";
      member_field SizeT "bc_size";
      member_field UInt8 "zf";
      member_field UInt8 "sf";
      member_field UInt8 "cf";
      member_field UInt8 "pf";
      member_field UInt8 "of";
      member_field Int32 "halted";
      member_field Int32 "auth_failed";
    ]
  in

  let run_func =
    func_decl ~attrs:[StaticFn; InlineFn] Void "stack_vm_run"
      [ (Ptr (StructType "stack_vm_t"), "vm"); (ConstPtr UInt8, "bytecode"); (SizeT, "size") ]
      ([
        (var "vm" $-> "bc_size") := var "size";
        var "g_last_auth_failed" := i32 0;
        if_then (log_not (call "asg_payload_auth_ok" [ var "bytecode"; var "size"; var "vm" $-> "addr_key" ])) [
          var "g_last_auth_failed" := i32 1;
          (var "vm" $-> "auth_failed") := i32 1;
          (var "vm" $-> "halted") := i32 1;
          expr_stmt (call "memset" [ var "vm" $-> "ctx"; i32 0; sizeof_expr (var "vm" $-> "ctx") ]);
          (var "vm" $-> "vsp_idx") := i32 0;
          ret_void;
        ];
      ] @ emit_stack_dispatch_stmts ?pipelined:cfg.pipelined ~entry_bid:prog.entry_id raw_dispatch_cases)
  in

  let is_addr_bound = enc.addr_mask <> 0L in
  let call_func =
    func_decl ~attrs:[StaticFn; InlineFn] UInt64 "stack_vm_call"
      [
        (ConstPtr UInt64, "bc_words");
        (SizeT, "len_words");
        (UInt64, "a0 = 0"); (UInt64, "a1 = 0"); (UInt64, "a2 = 0"); (UInt64, "a3 = 0");
        (UInt64, "a4 = 0"); (UInt64, "a5 = 0"); (UInt64, "a6 = 0"); (UInt64, "a7 = 0");
      ]
      [
        decl_var (StructType "stack_vm_t") "vm";
        expr_stmt (call "memset" [ addr_of (var "vm"); i32 0; sizeof_expr (var "vm") ]);
        (if is_addr_bound then
           block [
             (var "vm" $. "addr_key") := call "derive_addr_key" [];
             (var "vm" $. "vkey") := call "ASG_UNMASK_KEY" [ i32 prog.entry_id ] ^~ (var "vm" $. "addr_key");
           ]
         else
           block [
             (var "vm" $. "vkey") := call "ASG_UNMASK_KEY" [ i32 prog.entry_id ];
           ]);
        (if cfg.enable_hw_binding then
           raw
             "vm.vkey ^= asgard_anti_emulation::evaluate_emulation_differential();"
         else raw "");
        (if cfg.enable_address_bound then
           raw
             "vm.vkey ^= asgard_stack_vm::verify_handler_integrity();"
         else raw "");
        raw "vm.vsp_key = vm.vkey ^ UINT64_C(0x9E3779B97F4A7C15);";
        decl_var ~align_as:16 ~is_static:true ~is_thread_local:true (Array (UInt8, max 64 cfg.host_stack_size_kb * 1024)) "host_stack";
        let_u64 "sp_val" (c_cast UInt64 (var "host_stack" +~ sizeof_expr (var "host_stack") -~ u64 8192L));
        idx (var "vm" $. "ctx") (i32 4) := var "sp_val";
        idx (var "vm" $. "ctx") (i32 5) := var "sp_val";
        (match cfg.arch with
         | RV64 ->
             block [
               idx (var "vm" $. "ctx") (i32 0) := var "a0";
               idx (var "vm" $. "ctx") (i32 2) := var "a1";
               idx (var "vm" $. "ctx") (i32 1) := var "a2";
               idx (var "vm" $. "ctx") (i32 6) := var "a3";
               idx (var "vm" $. "ctx") (i32 7) := var "a4";
               idx (var "vm" $. "ctx") (i32 8) := var "a5";
               idx (var "vm" $. "ctx") (i32 9) := var "a6";
               idx (var "vm" $. "ctx") (i32 12) := var "a7";
             ]
         | AArch64 ->
             block [
               idx (var "vm" $. "ctx") (i32 0) := var "a0";
               idx (var "vm" $. "ctx") (i32 1) := var "a1";
               idx (var "vm" $. "ctx") (i32 2) := var "a2";
               idx (var "vm" $. "ctx") (i32 3) := var "a3";
               idx (var "vm" $. "ctx") (i32 6) := var "a4";
               idx (var "vm" $. "ctx") (i32 7) := var "a5";
               idx (var "vm" $. "ctx") (i32 8) := var "a6";
               idx (var "vm" $. "ctx") (i32 9) := var "a7";
             ]
         | X86_64 ->
             block [
               idx (var "vm" $. "ctx") (i32 7) := var "a0";
               idx (var "vm" $. "ctx") (i32 6) := var "a1";
               idx (var "vm" $. "ctx") (i32 2) := var "a2";
               idx (var "vm" $. "ctx") (i32 1) := var "a3";
               idx (var "vm" $. "ctx") (i32 8) := var "a4";
               idx (var "vm" $. "ctx") (i32 9) := var "a5";
               idx (var "vm" $. "ctx") (i32 0) := var "a6";
               idx (var "vm" $. "ctx") (i32 3) := var "a7";
             ]);
        decl_var (ConstPtr UInt8) "bc_bytes" ~init:(c_cast (ConstPtr UInt8) (var "bc_words"));
        expr_stmt (call "stack_vm_run" [ addr_of (var "vm"); var "bc_bytes"; var "len_words" *~ u64 8L ]);
        ret (idx (var "vm" $. "ctx") (i32 0));
      ]
  in

  let stack_vm_ns =
    namespace_def "asgard_stack_vm" (
      [
        stack_vm_t_def;
        typedef (StructType "stack_vm_t") "stack_vm_t";
        raw_top {|static inline uint64_t rotl64(uint64_t v, int k) {
    return (v << (k & 63)) | (v >> ((64 - k) & 63));
}

static inline uint64_t feedback_hash(uint64_t v) {
    v ^= v >> 33;
    v *= UINT64_C(0xFF51AFD7ED558CCD);
    v ^= v >> 33;
    v *= UINT64_C(0xC4CEB9FE1A85EC53);
    v ^= v >> 33;
    return v;
}

static inline void step_key(uint64_t *key, uint8_t p) {
    /* Non-linear: feedback_hash diffusion breaks affine key recovery. */
    *key = feedback_hash(rotl64(*key, 3) + (p ^ 0x5A));
}
|};
        raw_top {|
static inline uint8_t fetch_byte(stack_vm_t *vm, const uint8_t *bc, size_t *vip) {
    if (*vip >= vm->bc_size) {
        vm->halted = 1;
        return 0;
    }
    uint8_t c = bc[(*vip)++];
    uint8_t op = c ^ (uint8_t)(vm->vkey & 0xFF);
    step_key(&vm->vkey, op);
    return op;
}

static inline int16_t fetch_i16(stack_vm_t *vm, const uint8_t *bc, size_t *vip) {
    uint16_t b0 = fetch_byte(vm, bc, vip);
    uint16_t b1 = fetch_byte(vm, bc, vip);
    return (int16_t)(b0 | (b1 << 8));
}

static inline int32_t fetch_i32(stack_vm_t *vm, const uint8_t *bc, size_t *vip) {
    uint32_t b0 = fetch_byte(vm, bc, vip);
    uint32_t b1 = fetch_byte(vm, bc, vip);
    uint32_t b2 = fetch_byte(vm, bc, vip);
    uint32_t b3 = fetch_byte(vm, bc, vip);
    return (int32_t)(b0 | (b1 << 8) | (b2 << 16) | (b3 << 24));
}

static inline int64_t fetch_i64(stack_vm_t *vm, const uint8_t *bc, size_t *vip) {
    uint64_t res = 0;
    for (int i = 0; i < 8; ++i) {
        uint64_t b = fetch_byte(vm, bc, vip);
        res |= (b << (i * 8));
    }
    return (int64_t)res;
}

static inline uint64_t asg_vsp_mask(uint64_t key, uint32_t slot) {
    uint64_t z = key + (uint64_t)slot * UINT64_C(0x9E3779B97F4A7C15);
    z = (z ^ (z >> 30)) * UINT64_C(0xBF58476D1CE4E5B9);
    z = (z ^ (z >> 27)) * UINT64_C(0x94D049BB133111EB);
    return z ^ (z >> 31);
}
#define VSP_MASK(slot) asg_vsp_mask(vm->vsp_key, (uint32_t)(slot))
#define VSP_ENCODE(slot, v) ((v) ^ VSP_MASK(slot))

static inline uint8_t parity8(uint64_t v) {
    uint8_t x = (uint8_t)(v & 0xFF);
    x ^= x >> 4; x ^= x >> 2; x ^= x >> 1;
    return (~x) & 1;
}

static inline int eval_cond(const stack_vm_t *vm, uint8_t cond) {
    switch (cond) {
        case 0: return vm->zf;
        case 1: return !vm->zf;
        case 2: return vm->cf;
        case 3: return !vm->cf;
        case 4: return vm->cf || vm->zf;
        case 5: return !vm->cf && !vm->zf;
        case 6: return vm->sf;
        case 7: return !vm->sf;
        case 8: return vm->sf != vm->of;
        case 9: return vm->sf == vm->of;
        case 10: return vm->zf || (vm->sf != vm->of);
        case 11: return !vm->zf && (vm->sf == vm->of);
        case 12: return vm->of;
        case 13: return !vm->of;
        case 14: return vm->pf;
        case 15: return !vm->pf;
        case 16: return 1;
        default: return 1;
    }
}|};
      ]
      @ Stack_handlers_emitter.emit_push_pop_handlers ()
      @ [
        raw_top {|static inline int asg_addr_canonical(uint64_t addr) {
    uint64_t top = addr >> 48;
    return top == 0 || top == UINT64_C(0xFFFF) || (addr >> 52) == 0;
}

static inline int asg_mem_access_ok(uint64_t addr, uint8_t w) {
    if (w != 1 && w != 2 && w != 4 && w != 8) return 0;
    if (addr == 0) return 0;
    if ((addr & (uint64_t)(w - 1)) != 0) return 0;
    if (!asg_addr_canonical(addr)) return 0;
    if (addr > UINT64_MAX - (uint64_t)(w - 1)) return 0;
    return 1;
}|};
      ]
      @ Vm_ir.Branchless_vip.build_branchless_vip_ast ()
      @ Stack_handlers_emitter.emit_mem_handlers ()
      @ Stack_handlers_emitter.emit_alu_handlers ()
      @ Stack_handlers_emitter.emit_dup_swap_handlers ()
      @ Stack_handlers_emitter.emit_flags_handlers ()
      @ Stack_handlers_emitter.emit_control_handlers ~jcc_target_first:enc.layout.jcc_target_first ()
      @ [ emit_h_call_extern cfg.arch ]
      @ Stack_handlers_emitter.emit_cond_handlers ~cmov_slot_first:enc.layout.cmov_slot_first ()
      @ Stack_handlers_emitter.emit_superop_handlers
          ~add_ii_b_first:enc.layout.add_ii_b_first
          ~sub_ii_b_first:enc.layout.sub_ii_b_first ()
      @ Stack_handlers_emitter.emit_reg_imm_handlers
          ~set_reg_imm_first:enc.layout.set_reg_imm_first
          ~add_reg_imm_first:enc.layout.add_reg_imm_first ()
      @ [
        raw_top (Printf.sprintf {|static void (*const g_stack_handler_table[])(stack_vm_t *, const uint8_t *, size_t *) = {
    &h_push_imm, &h_push_imm32, &h_push_reg, &h_pop_reg, &h_read_mem, &h_write_mem,
    &h_add, &h_sub, &h_mul, &h_nor, &h_nand,
    &h_shl, &h_shr, &h_sar, &h_div, &h_idiv,
    &h_dup, &h_dup2, &h_rot, &h_swap, &h_push_flags, &h_pop_flags, &h_jmp_rel,
    &h_jcc_rel, &h_key_adjust, &h_exit, &h_call_extern, &h_resolve_sym,
    &h_setcc, &h_cmov, &h_cmp, &h_test,
    &h_add_imm, &h_sub_imm, &h_add_ii, &h_sub_ii, &h_set_reg_imm, &h_add_reg_imm,
    &h_key_feedback
};
__attribute__((always_inline))
static inline uint64_t verify_handler_integrity(void) {
    uint64_t penalty = 0;
    const uintptr_t base = (uintptr_t)&h_push_imm;
    const size_t n = sizeof(g_stack_handler_table) / sizeof(g_stack_handler_table[0]);
    for (size_t i = 0; i < n; ++i) {
        uintptr_t p = (uintptr_t)g_stack_handler_table[i];
        uintptr_t diff = (p > base) ? (p - base) : (base - p);
        if (__builtin_expect(p == 0 || diff > 0x400000, 0)) {
            penalty ^= (uint64_t)(p ^ UINT64_C(0x%016LX));
        }
    }
    return penalty;
}
__attribute__((noinline))
static uint64_t derive_addr_key(void) {
    const size_t n = sizeof(g_stack_handler_table) / sizeof(g_stack_handler_table[0]);
    uint64_t acc = UINT64_C(0x9E3779B97F4A7C15);
#if defined(__clang__)
    #pragma clang loop unroll(disable)
#elif defined(__GNUC__)
    #pragma GCC unroll 0
#endif
    for (size_t i = 0; i + 1 < n; ++i) {
        uint64_t d = (uint64_t)((uintptr_t)g_stack_handler_table[i + 1] - (uintptr_t)g_stack_handler_table[i]);
        acc ^= d + UINT64_C(0x165667B19E3779F9) + (acc << 6) + (acc >> 2);
    }
    return rotl64(acc, 31) ^ UINT64_C(0xA5A5A5A5A5A5A5A5);
}|} salt_deadbeef_5877cafe);
        macro_def ~value:(var (Printf.sprintf "UINT64_C(0x%016LX)" enc.payload_tag)) "ASG_PAYLOAD_TAG";
        raw_top {|static inline uint64_t asg_siphash12(uint64_t k0, uint64_t k1, uint64_t m) {
    uint64_t v0 = k0 ^ UINT64_C(0x736F6D6570736575);
    uint64_t v1 = k1 ^ UINT64_C(0x646F72616E646F6D);
    uint64_t v2 = k0 ^ UINT64_C(0x6C7967656E657261);
    uint64_t v3 = k1 ^ UINT64_C(0x7465646279746573);
    v3 ^= m;
    v0 += v1; v1 = rotl64(v1, 13); v1 ^= v0;
    v0 = rotl64(v0, 32);
    v2 += v3; v3 = rotl64(v3, 16); v3 ^= v2;
    v0 += v3; v3 = rotl64(v3, 21); v3 ^= v0;
    v2 += v1; v1 = rotl64(v1, 17); v1 ^= v2;
    v2 = rotl64(v2, 32);
    v0 ^= m;
    v2 ^= UINT64_C(0xFF);
    for (int r = 0; r < 2; ++r) {
        v0 += v1; v1 = rotl64(v1, 13); v1 ^= v0;
        v0 = rotl64(v0, 32);
        v2 += v3; v3 = rotl64(v3, 16); v3 ^= v2;
        v0 += v3; v3 = rotl64(v3, 21); v3 ^= v0;
        v2 += v1; v1 = rotl64(v1, 17); v1 ^= v2;
        v2 = rotl64(v2, 32);
    }
    return v0 ^ v1 ^ v2 ^ v3;
}

static uint64_t asg_payload_tag(uint64_t k0, uint64_t k1, const uint8_t *bc, size_t size) {
    uint64_t acc = asg_siphash12(k0, k1, UINT64_C(0x5041594C4F414421) ^ (uint64_t)size);
    for (size_t i = 0; i < size; i += 8) {
        uint64_t w = 0;
        for (int j = 7; j >= 0; --j) w = (w << 8) | (uint64_t)bc[i + (size_t)j];
        acc = asg_siphash12(k0, k1, acc ^ w);
    }
    return acc;
}

static inline int asg_payload_auth_ok(const uint8_t *bc, size_t size, uint64_t addr_key) {
    if (size == 0 || (size & 7) != 0) return 0;
    uint64_t k0 = ASG_UNMASK_TAG_K0() ^ addr_key;
    uint64_t k1 = ASG_UNMASK_TAG_K1() ^ addr_key;
    uint64_t diff = asg_payload_tag(k0, k1, bc, size) ^ ASG_PAYLOAD_TAG;
    return ((diff | (0 - diff)) >> 63) == 0;
}|};
        global_var ~is_static:true ~is_thread_local:true ~init:(i32 0) Int32 "g_last_auth_failed";
        run_func;
        call_func;
      ]
    )
  in

  let vanguard_ns =
    namespace_def "vanguard_threaded_vm" [
      func_decl ~attrs:[StaticFn; InlineFn] UInt64 "asgard_vm_call"
        [
          (ConstPtr UInt64, "bc");
          (SizeT, "len");
          (UInt64, "a0 = 0"); (UInt64, "a1 = 0"); (UInt64, "a2 = 0"); (UInt64, "a3 = 0");
          (UInt64, "a4 = 0"); (UInt64, "a5 = 0"); (UInt64, "a6 = 0"); (UInt64, "a7 = 0");
          (UInt8, "macro_salt = 0");
        ]
        [
          let_u64 "res" (call "asgard_stack_vm::stack_vm_call" [
            var "bc"; var "len";
            var "a0"; var "a1"; var "a2"; var "a3";
            var "a4"; var "a5"; var "a6"; var "a7";
          ]);
          if_then (call "__builtin_expect" [ var "asgard_stack_vm::g_last_auth_failed"; i32 0 ]) [
            ret (u64 1L);
          ];
          ret (var "res");
        ];
      func_decl ~attrs:[StaticFn; InlineFn] UInt64 "asgard_vm_call_with_salt"
        [
          (UInt8, "macro_salt");
          (ConstPtr UInt64, "bc");
          (SizeT, "len");
          (UInt64, "a0 = 0"); (UInt64, "a1 = 0"); (UInt64, "a2 = 0"); (UInt64, "a3 = 0");
          (UInt64, "a4 = 0"); (UInt64, "a5 = 0"); (UInt64, "a6 = 0"); (UInt64, "a7 = 0");
        ]
        [
          ret (call "asgard_vm_call" [
            var "bc"; var "len";
            var "a0"; var "a1"; var "a2"; var "a3";
            var "a4"; var "a5"; var "a6"; var "a7";
            var "macro_salt";
          ]);
        ];
    ]
  in

  preamble_decls
  @ constants_decls
  @ symbols_decls
  @ block_tables_decls
  @ [ stack_vm_ns; vanguard_ns ]

let generate_c_runtime
    ?(external_symbols = [])
    ?(constants = [])
    ?(obfuscate_runtime = false)
    ?enc
    cfg
    prog =
  let enc = match enc with
    | Some e -> e
    | None -> Stack_encoder.encode_program prog
  in
  let decls = emit_stack_runtime_hpp_decls ~external_symbols ~constants ~enc cfg prog in
  (* The emulation differential probe (CPUID / timer consistency).  It is
     mixed into the decryption key, so the header has to carry it. *)
  let hw_binding_header =
    if cfg.enable_hw_binding then
      Cpp_codegen.Runtime_probes.emit_anti_emulation_probes ()
    else ""
  in
  (* The probe namespace has to come FIRST: the runtime body calls
     evaluate_emulation_differential() while initialising the key. *)
  let raw =
    (if hw_binding_header = "" then "" else hw_binding_header ^ "\n")
    ^ Cpp_codegen.Cpp_printer.render_top_decls decls
  in
  if obfuscate_runtime then
    scramble_c_runtime ~seed:enc.seed_key ~strip_comments:true raw
  else
    raw

let emit_stack_runner_main_def () : Cpp_codegen.Cpp_ast.top_decl =
  let open Cpp_codegen.Cpp_ast in
  let open Cpp_codegen.Cpp_dsl in
  func_decl Int32 "main" [(Int32, "argc"); (Ptr (Ptr (StructType "char")), "argv")] [
    decl_var (Ptr UInt64) "bc_ptr" ~init:(var "embedded_bytecode");
    decl_var SizeT "bc_len" ~init:(sizeof_expr (var "embedded_bytecode") /~ sizeof_expr (idx (var "embedded_bytecode") (i32 0)));
    if_then (var "argc" >=~ i32 2) [
      decl_var (Ptr (StructType "FILE")) "f" ~init:(call "fopen" [idx (var "argv") (i32 1); str_lit "rb"]);
      if_then (ne (var "f") nullptr) [
        expr_stmt (call "fseek" [var "f"; i32 0; var "SEEK_END"]);
        decl_var (StructType "long") "sz" ~init:(call "ftell" [var "f"]);
        expr_stmt (call "fseek" [var "f"; i32 0; var "SEEK_SET"]);
        if_then ((var "sz" >~ i32 0) &&~ ((var "sz" %~ i32 8) ==~ i32 0)) [
          decl_var SizeT "count" ~init:(c_cast SizeT (var "sz") /~ u64 8L);
          decl_var (Ptr UInt64) "heap_bc" ~init:(c_cast (Ptr UInt64) (call "malloc" [c_cast SizeT (var "sz")]));
          if_then ((ne (var "heap_bc") nullptr) &&~ (call "fread" [var "heap_bc"; u64 8L; var "count"; var "f"] ==~ var "count")) [
            var "bc_ptr" := var "heap_bc";
            var "bc_len" := var "count";
          ];
        ];
        expr_stmt (call "fclose" [var "f"]);
      ];
    ];
    let_u64 "ret" (call "vanguard_threaded_vm::asgard_vm_call" [var "bc_ptr"; var "bc_len"]);
    (* A tampered payload aborts the run: the result value alone does not
       say so (the failure sentinel is 1, a legitimate result can be 1
       too), so the authentication failure is reported explicitly. *)
    if_then ((var "asgard_stack_vm::g_last_auth_failed") <>~ i32 0) [
      expr_stmt (call "printf" [
        str_lit "[Stack-VM] Execution ABORTED: payload authentication FAILED (the protected image was modified)\n";
      ]);
    ];
    expr_stmt (call "printf" [
      str_lit "[Stack-VM] Execution SUCCESS! Result: %llu\n";
      c_cast (StructType "unsigned long long") (var "ret");
    ]);
    ret (i32 0);
  ]

let emit_stack_probe_main_def () : Cpp_codegen.Cpp_ast.top_decl =
  let open Cpp_codegen.Cpp_ast in
  let open Cpp_codegen.Cpp_dsl in
  func_decl Int32 "main" [(Void, "")] [
    expr_stmt (call "printf" [
      str_lit "ADDR_KEY: %016llX\n";
      c_cast (StructType "unsigned long long") (call "asgard_stack_vm::derive_addr_key" []);
    ]);
    ret (i32 0);
  ]

let emit_runner_cpp ?(header_name = "stack_vm_runtime.hpp") bytecode =
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
    include_local header_name;
    include_sys "stdio.h";
    include_sys "stdlib.h";
    embedded_bc_decl;
    emit_stack_runner_main_def ();
  ] in
  render_top_decls top_decls ^ "\n"

let emit_probe_cpp ?(header_name = "stack_vm_runtime.hpp") () =
  let open Cpp_codegen.Cpp_dsl in
  let open Cpp_codegen.Cpp_printer in
  let top_decls = [
    include_local header_name;
    include_sys "stdio.h";
    emit_stack_probe_main_def ();
  ] in
  render_top_decls top_decls ^ "\n"
