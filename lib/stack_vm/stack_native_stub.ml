(** Native Micro-Handler Stub Assembler (Phase 6f / Pass 27)
    ─────────────────────────────────────────────────────────────
    Emits tiny position-independent native machine-code stubs that are
    interleaved directly into the encrypted bytecode stream by
    [Stack_native_interleave_pass].  Each stub implements a binary ALU
    micro-operation over two VM context slots:

      ctx[dst] = ctx[a] OP ctx[b],  OP ∈ { add, sub, mul }

    Stub calling contract (host ABI):
      - the VM state pointer arrives in the first integer argument register
        (x0 on AArch64, rdi on SysV x86-64, a0 on RV64);
      - the stub may clobber caller-saved temporaries only;
      - the stub returns immediately ([ret] / [jalr x0, ra]).

    The [stack_vm_t] layout is fixed by [Stack_runtime]:
      vsp[4096] @ 0x0        (32768 bytes)
      vsp_idx    @ 0x8000    (4 bytes + 4 padding)
      ctx[]      @ 0x8008    <- single source of truth: [ctx_offset]
*)

type arch =
  | X86_64
  | AArch64
  | RV64

(** Byte offset of the [ctx] array inside [stack_vm_t]
    (4096 * 8 bytes of vsp + 4 bytes vsp_idx + 4 bytes padding). *)
let ctx_offset = 0x8008

(** Maximum stub length the runtime escape handler accepts. *)
let max_stub_len = 64

(* Kind identifiers shared by encoder, decoder and interpreter. *)
let kind_add = 0
let kind_sub = 1
let kind_mul = 2

let le32 (v : int) : int list =
  [ v land 0xFF; (v lsr 8) land 0xFF; (v lsr 16) land 0xFF; (v lsr 24) land 0xFF ]

(* ── x86-64 (SysV: vm in rdi) ────────────────────────────────────────────
   mov rax, [rdi + disp32]   48 8B 87 dd dd dd dd
   mov rcx, [rdi + disp32]   48 8B 8F dd dd dd dd
   add rax, rcx              48 01 C8
   sub rax, rcx              48 29 C8
   imul rax, rcx             48 0F AF C1
   mov [rdi + disp32], rax   48 89 87 dd dd dd dd
   ret                       C3 *)
let emit_x86_64 kind a b c =
  let off s = ctx_offset + 8 * s in
  let load_rax = 0x48 :: 0x8B :: 0x87 :: le32 (off a) in
  let load_rcx = 0x48 :: 0x8B :: 0x8F :: le32 (off b) in
  let store =
    0x48 :: 0x89 :: 0x87 :: le32 (off c) @ [ 0xC3 ]
  in
  let alu =
    match kind with
    | k when k = kind_add -> [ 0x48; 0x01; 0xC8 ]
    | k when k = kind_sub -> [ 0x48; 0x29; 0xC8 ]
    | _ -> [ 0x48; 0x0F; 0xAF; 0xC1 ]
  in
  load_rax @ load_rcx @ alu @ store

(* ── AArch64 (AAPCS64: vm in x0) ────────────────────────────────────────
   movz x16, #(0x8008 + 8a)  ; ldr x8, [x0, x16]
   movz x17, #(0x8008 + 8b)  ; ldr x9, [x0, x17]
   <add|sub|mul> x10, x8, x9
   movz x16, #(0x8008 + 8c)  ; str x10, [x0, x16]
   ret
   Slot offsets stay below 0x9000, so each fits the movz imm16 field. *)
let a64 word = le32 word

let movz imm rd = 0xD2800000 lor (imm lsl 5) lor rd
let ldr_reg rt rn rm = 0xF8606800 lor (rm lsl 16) lor (rn lsl 5) lor rt
let str_reg rt rn rm = 0xF8206800 lor (rm lsl 16) lor (rn lsl 5) lor rt
let add_reg rd rn rm = 0x8B000000 lor (rm lsl 16) lor (rn lsl 5) lor rd
let sub_reg rd rn rm = 0xCB000000 lor (rm lsl 16) lor (rn lsl 5) lor rd
let mul_reg rd rn rm = 0x9B000000 lor (rm lsl 16) lor (rn lsl 5) lor rd lor (31 lsl 10)
let a64_ret () = 0xD65F03C0

let emit_aarch64 kind a b c =
  let off s = ctx_offset + 8 * s in
  let alu =
    match kind with
    | k when k = kind_add -> add_reg 10 8 9
    | k when k = kind_sub -> sub_reg 10 8 9
    | _ -> mul_reg 10 8 9
  in
  a64 (movz (off a) 16) @ a64 (ldr_reg 8 0 16)
  @ a64 (movz (off b) 17) @ a64 (ldr_reg 9 0 17)
  @ a64 alu
  @ a64 (movz (off c) 16) @ a64 (str_reg 10 0 16)
  @ a64 (a64_ret ())

(* ── RV64 (RISC-V psABI: vm in a0) ──────────────────────────────────────
   li t0, off_a; add t0, t0, a0; ld t1, 0(t0)
   li t2, off_b; add t2, t2, a0; ld t3, 0(t2)
   <add|sub|mul> t4, t1, t3
   li t5, off_c; add t5, t5, a0; sd t4, 0(t5)
   ret *)
let rv word = le32 word

let lui rd imm20 = 0x37 lor (imm20 lsl 12) lor rd
let addi rd rs1 imm = 0x13 lor ((imm land 0xFFF) lsl 20) lor (rs1 lsl 15) lor rd
let add_r rd rs1 rs2 = 0x33 lor (rs2 lsl 20) lor (rs1 lsl 15) lor rd
let sub_r rd rs1 rs2 = 0x33 lor (rs2 lsl 20) lor (rs1 lsl 15) lor rd lor 0x40000000
let mul_r rd rs1 rs2 = 0x33 lor (rs2 lsl 20) lor (rs1 lsl 15) lor rd lor 0x02000000
let ld_r rd rs1 = 0x03 lor (rs1 lsl 15) lor (3 lsl 12) lor rd
let sd_r rs2 rs1 = 0x23 lor (rs2 lsl 20) lor (rs1 lsl 15) lor (3 lsl 12)
let rv_ret () = 0x00008067

let li_off off rd =
  (* off < 0x9000: hi/lo split with sign correction for the low 12 bits *)
  let lo = off land 0xFFF in
  if lo >= 0x800 then
    [ rv (lui rd ((off lsr 12) + 1)); rv (addi rd rd (lo - 0x1000)) ]
  else [ rv (lui rd (off lsr 12)); rv (addi rd rd lo) ]

let emit_rv64 kind a b c =
  let off s = ctx_offset + 8 * s in
  let alu =
    match kind with
    | k when k = kind_add -> add_r 12 6 7
    | k when k = kind_sub -> sub_r 12 6 7
    | _ -> mul_r 12 6 7
  in
  List.concat (
    li_off (off a) 5 @ [ rv (add_r 5 5 10); rv (ld_r 6 5) ]
    @ li_off (off b) 7 @ [ rv (add_r 7 7 10); rv (ld_r 13 7) ]
    @ [ rv alu ]
    @ li_off (off c) 14 @ [ rv (add_r 14 14 10); rv (sd_r 12 14) ]
    @ [ rv (rv_ret ()) ]
  )

(** Emits the native micro-handler stub for
    [ctx[c] = ctx[a] OP ctx[b]] on the target architecture.
    Returns the raw machine-code bytes as an int list (little-endian stream). *)
let emit (arch : arch) (kind : int) (a : int) (b : int) (c : int) : int list =
  assert (a >= 0 && a < 4096 && b >= 0 && b < 4096 && c >= 0 && c < 4096);
  match arch with
  | X86_64 -> emit_x86_64 kind a b c
  | AArch64 -> emit_aarch64 kind a b c
  | RV64 -> emit_rv64 kind a b c
