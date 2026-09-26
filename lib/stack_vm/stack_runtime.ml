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

let generate_c_runtime _cfg prog =
  let buf = Buffer.create 2048 in
  Buffer.add_string buf "#include <stdint.h>\n#include <stdlib.h>\n#include <string.h>\n\n";
  Buffer.add_string buf "typedef struct {\n";
  Buffer.add_string buf "    uint64_t vsp[1024];\n";
  Buffer.add_string buf "    int vsp_idx;\n";
  Buffer.add_string buf (Printf.sprintf "    uint64_t ctx[%d];\n" (max 32 prog.context_slots));
  Buffer.add_string buf "    uint64_t vkey;\n";
  Buffer.add_string buf "    int halted;\n";
  Buffer.add_string buf "} stack_vm_t;\n\n";
  Buffer.add_string buf "static inline uint64_t rotl64(uint64_t v, int k) {\n";
  Buffer.add_string buf "    return (v << (k & 63)) | (v >> ((64 - k) & 63));\n";
  Buffer.add_string buf "}\n\n";
  Buffer.add_string buf "static inline void step_key(uint64_t *key, uint8_t p) {\n";
  Buffer.add_string buf "    *key = rotl64(*key, 3) + (p ^ 0x5A);\n";
  Buffer.add_string buf "}\n\n";
  Buffer.add_string buf "void stack_vm_run(stack_vm_t *vm, const uint8_t *bytecode, size_t size) {\n";
  Buffer.add_string buf "    size_t vip = 0;\n";
  Buffer.add_string buf "    while (!vm->halted && vip < size) {\n";
  Buffer.add_string buf "        uint8_t c = bytecode[vip++];\n";
  Buffer.add_string buf "        uint8_t op = c ^ (uint8_t)(vm->vkey & 0xFF);\n";
  Buffer.add_string buf "        step_key(&vm->vkey, op);\n";
  Buffer.add_string buf "        switch (op) {\n";
  Buffer.add_string buf "            case 0x06: /* ADD */ {\n";
  Buffer.add_string buf "                uint64_t a = vm->vsp[--vm->vsp_idx];\n";
  Buffer.add_string buf "                uint64_t b = vm->vsp[--vm->vsp_idx];\n";
  Buffer.add_string buf "                vm->vsp[vm->vsp_idx++] = a + b;\n";
  Buffer.add_string buf "                break;\n";
  Buffer.add_string buf "            }\n";
  Buffer.add_string buf "            case 0x09: /* NOR */ {\n";
  Buffer.add_string buf "                uint64_t a = vm->vsp[--vm->vsp_idx];\n";
  Buffer.add_string buf "                uint64_t b = vm->vsp[--vm->vsp_idx];\n";
  Buffer.add_string buf "                vm->vsp[vm->vsp_idx++] = ~(a | b);\n";
  Buffer.add_string buf "                break;\n";
  Buffer.add_string buf "            }\n";
  Buffer.add_string buf "            case 0x0D: /* DUP */ {\n";
  Buffer.add_string buf "                uint64_t top = vm->vsp[vm->vsp_idx - 1];\n";
  Buffer.add_string buf "                vm->vsp[vm->vsp_idx++] = top;\n";
  Buffer.add_string buf "                break;\n";
  Buffer.add_string buf "            }\n";
  Buffer.add_string buf "            case 0x14: /* EXIT */\n";
  Buffer.add_string buf "                vm->halted = 1;\n";
  Buffer.add_string buf "                break;\n";
  Buffer.add_string buf "            default: break;\n";
  Buffer.add_string buf "        }\n";
  Buffer.add_string buf "    }\n";
  Buffer.add_string buf "}\n";
  Buffer.contents buf
