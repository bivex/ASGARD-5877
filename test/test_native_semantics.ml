(* Sub-width native semantics acceptance (TODO items 1/5/6): division with
   remainder, B32 zero-extension, and B16 word-granular memory through the
   width-blind threaded VM, each driven by a custom C++ runner against real
   x86/arm64 lifted code.  Shared runners live in [Test_helpers]. *)
open X86_lifter
open Native_vm
open Vm_ir
open Test_helpers
open Protect_adapters

let mk_pkg ~seed asm =
  let rng = Random.State.make [| seed |] in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func -> Vm_emitter.compile_and_package ~rng func

(* TODO item 5, native side: idiv/div at B64 through the custom runner, checking
   both halves of the division — quotient in rax, remainder in rdx (the rdx
   accessor exists only via the RegMap enum, there is no get_rdx method). *)
let test_native_div_idiv_with_remainder () =
  let pkg_idiv64 =
    mk_pkg ~seed:20260924 {|
func_native_idiv64:
    mov rax, rdi
    cqo
    idiv rsi
    ret
|}
  in
  let pkg_div64 =
    mk_pkg ~seed:20260925 {|
func_native_div64:
    mov rax, rdi
    xor rdx, rdx
    div rsi
    ret
|}
  in
  with_temp_dir (fun tmp_dir ->
      run_custom_vm ~name:"idiv64" tmp_dir pkg_idiv64 {|
    vanguard_threaded_vm::VMContext ctx = {};
    ctx.init();
    ctx.set_rdi((uint64_t)(-47));
    ctx.set_rsi(5);
    if (!vanguard_threaded_vm::execute_threaded(ctx, embedded_bytecode, count)) return 1;
    if (ctx.get_rax() != (uint64_t)(-9)) return 2;
    if (ctx.get_reg(vanguard_threaded_vm::REG_RDX) != (uint64_t)(-2)) return 3;
|};
      run_custom_vm ~name:"div64" tmp_dir pkg_div64 {|
    vanguard_threaded_vm::VMContext ctx = {};
    ctx.init();
    ctx.set_rdi(0xFFFFFFFFFFFFFFFFULL);
    ctx.set_rsi(2);
    if (!vanguard_threaded_vm::execute_threaded(ctx, embedded_bytecode, count)) return 1;
    if (ctx.get_rax() != 0x7FFFFFFFFFFFFFFFULL) return 2;
    if (ctx.get_reg(vanguard_threaded_vm::REG_RDX) != 1ULL) return 3;
|})

(* TODO item 6, native side: a B32 write must zero the upper half of the backing
   slot in the width-blind VM.  The first runner drives the whole 32-bit idiv
   lowering (which interleaves B32 writes with the div reconstruction); the
   second isolates the zero-extension itself — mov eax, esi after esi was loaded
   with garbage in the upper half, which previously diverged natively. *)
let test_native_b32_subregister_semantics () =
  let pkg_idiv32 =
    mk_pkg ~seed:20260926 {|
func_native_idiv32:
    mov eax, edi
    cdq
    idiv esi
    ret
|}
  in
  let pkg_zext =
    mk_pkg ~seed:20260927 {|
func_native_zext:
    mov rsi, rdi
    mov eax, esi
    ret
|}
  in
  with_temp_dir (fun tmp_dir ->
      run_custom_vm ~name:"idiv32" tmp_dir pkg_idiv32 {|
    vanguard_threaded_vm::VMContext ctx = {};
    ctx.init();
    ctx.set_rdi((uint64_t)(-47));
    ctx.set_rsi(5);
    if (!vanguard_threaded_vm::execute_threaded(ctx, embedded_bytecode, count)) return 1;
    if (ctx.get_rax() != 0xFFFFFFF7ULL) return 2;
    if (ctx.get_reg(vanguard_threaded_vm::REG_RDX) != 0xFFFFFFFEULL) return 3;
|};
      run_custom_vm ~name:"zext32" tmp_dir pkg_zext {|
    vanguard_threaded_vm::VMContext ctx = {};
    ctx.init();
    ctx.set_rdi(0x123456789AULL);
    if (!vanguard_threaded_vm::execute_threaded(ctx, embedded_bytecode, count)) return 1;
    if (ctx.get_rax() != 0x3456789AULL) return 2;
|})

(* TODO item 1, native side: word-granular memory must move two bytes through
   H_STORE_16/H_LOAD_16 (previously the B16 width fell into the byte handlers,
   so the high byte was silently dropped).  The function zeroes a word slot,
   stores 0xCAFE into it and re-reads both halves: the word load plus the
   shifted high byte must reconstitute 0xCA_CAFE — with the old byte-only
   handlers this returns 0xFE.  VMContext::init does not set REG_RSP, so the
   runner points it at a real scratch buffer first. *)
let test_native_b16_word_memory () =
  let pkg =
    mk_pkg ~seed:20260928 {|
func_native_b16_word:
    mov rax, rdi
    xor rcx, rcx
    mov word ptr [rsp - 16], cx
    mov word ptr [rsp - 16], ax
    movzx eax, word ptr [rsp - 16]
    movzx ecx, byte ptr [rsp - 15]
    shl ecx, 16
    add rax, rcx
    ret
|}
  in
  with_temp_dir (fun tmp_dir ->
      run_custom_vm ~name:"b16word" tmp_dir pkg {|
    static uint64_t scratch[8] = {0};
    vanguard_threaded_vm::VMContext ctx = {};
    ctx.init();
    ctx.set_rdi(0xCAFEULL);
    ctx.set_reg(vanguard_threaded_vm::REG_RSP, (uint64_t)(scratch + 4));
    if (!vanguard_threaded_vm::execute_threaded(ctx, embedded_bytecode, count)) return 1;
    if (ctx.get_rax() != 0x00CACAFEULL) return 2;
|})

(* MOVZX acceptance in the threaded native VM: all five encodings
   (0F B6 / 0F B7 with 32- and 64-bit destinations, register and memory
   sources) must zero-extend, a 32-bit destination must end up with the
   upper half of its parent register cleared, and MOVZX must leave the flags
   alone ("Flags Affected: None").  The leading [cmp] makes ZF true; every
   MOVZX below runs between that compare and the end of the function, so a
   flag-clobbering lowering shows up as a cleared ZF. *)
let test_native_movzx_zero_extend () =
  let pkg =
    mk_pkg ~seed:20261020 {|
func_native_movzx:
    cmp rsi, rdi
    movzx r8, cl
    movzx r9d, dl
    movzx r10, cx
    movzx r11d, dx
    movzx r12, byte ptr [rdi]
    movzx r13d, byte ptr [rdi]
    movzx r14, word ptr [rdi + 2]
    movzx r15d, word ptr [rdi + 2]
    ret
|}
  in
  with_temp_dir (fun tmp_dir ->
      run_custom_vm ~name:"movzx" tmp_dir pkg {|
    static unsigned char scratch[16];
    for (int i = 0; i < 16; i++) scratch[i] = (unsigned char)(i + 1);
    vanguard_threaded_vm::VMContext ctx = {};
    ctx.init();
    ctx.set_rdi((uint64_t)(scratch + 4));
    ctx.set_rsi((uint64_t)(scratch + 4));
    ctx.set_reg(vanguard_threaded_vm::REG_RCX, 0x1234A5ULL);
    ctx.set_reg(vanguard_threaded_vm::REG_RDX, 0xBEEF5CULL);
    ctx.set_reg(vanguard_threaded_vm::REG_RSP, (uint64_t)(scratch + 12));
    if (!vanguard_threaded_vm::execute_threaded(ctx, embedded_bytecode, count)) return 1;
    // cl = 0xA5, cx = 0x34A5, dl = 0x5C, dx = 0xEF5C
    if (ctx.get_reg(vanguard_threaded_vm::REG_R8) != 0xA5ULL) return 2;
    if (ctx.get_reg(vanguard_threaded_vm::REG_R9) != 0x5CULL) return 3;
    if (ctx.get_reg(vanguard_threaded_vm::REG_R10) != 0x34A5ULL) return 4;
    if (ctx.get_reg(vanguard_threaded_vm::REG_R11) != 0xEF5CULL) return 5;
    // the byte at [rdi] is 0x05, the word at [rdi + 2] is 0x0807
    if (ctx.get_reg(vanguard_threaded_vm::REG_R12) != 0x05ULL) return 6;
    if (ctx.get_reg(vanguard_threaded_vm::REG_R13) != 0x05ULL) return 7;
    if (ctx.get_reg(vanguard_threaded_vm::REG_R14) != 0x0807ULL) return 8;
    if (ctx.get_reg(vanguard_threaded_vm::REG_R15) != 0x0807ULL) return 9;
    // MOVZX affects no flags: the compare above set ZF and it must still hold
    if (!ctx.zf) return 10;
|})

(* TODO item 1 acceptance, part 1: full C pipeline — a uint16_t computation
   inside ASGARD_BEGIN_VIRTUALIZE goes through macro obfuscation, the clang
   frontend, the ARM64 lifter, the threaded-VM packager and the C trampoline;
   the protected app itself checks the virtualized result against the native
   C semantics (0x9ABC + 0x1234 = 0xACF0; ^0x5A5A = 0xF6AA) and exits 0 only
   when they match. *)
let test_e2e_uint16_pipeline () =
  let c_src = {|
#include <stdio.h>
#include <stdint.h>
#include "asgard_obf.h"

static uint64_t u16_math(uint64_t input) {
    ASGARD_BEGIN_VIRTUALIZE("u16math");
    volatile uint16_t acc = (uint16_t)(input & 0xFFFFu);
    acc = (uint16_t)(acc + (uint16_t)(input >> 16));
    acc = (uint16_t)(acc ^ 0x5A5Au);
    ASGARD_END();
    return acc;
}

int main(void) {
    uint64_t v = u16_math(0x12349ABCU);
    printf("u16_math = 0x%llX\n", (unsigned long long)v);
    return (v == 0xF6AAULL) ? 0 : 1;
}
|} in
  with_temp_dir (fun tmp_dir ->
      let c_path = Filename.concat tmp_dir "u16_app.c" in
      write_file_string c_path c_src;
      let out_dir = Filename.concat tmp_dir "out" in
      let cfg =
        Config_adapter.resolve
          ~config_file:None
          ~preset:None
          ~enable_cff:false
          ~enable_mba:false
          ~mba_depth:2
          ~seed:(Some 20260930)
      in
      let rng = Random.State.make [| 20260930 |] in
      let lifter = (module Arm64_lifter_adapter : Random_visa_ports.Protect_ports.Lifter) in
      let vm_packager = (module Vm_packagers.Threaded_vm_packager : Random_visa_ports.Protect_ports.Vm_packager) in
      let trampoline = (module C_trampoline_adapter.C_trampoline_engine : Random_visa_ports.Protect_ports.Trampoline_engine) in
      let toolchain = (module Clang_toolchain_adapter : Random_visa_ports.Protect_ports.Toolchain) in
      let c_macro = (module C_macro_obf_adapter : Random_visa_ports.Protect_ports.C_macro_obfuscator) in
      match
        Random_visa_application.Protect_pipeline.run
          ~lifter
          ~c_macro_obfuscator:c_macro
          ~vm_packager
          ~trampoline_engine:trampoline
          ~toolchain
          ~rng
          ~config:cfg
          ~input_file:c_path
          ~out_dir
          ~compile_and_run:true
          ()
      with
      | Error err -> Alcotest.fail ("uint16 pipeline failed: " ^ err)
      | Ok res ->
          (match res.execution_output with
          | Some (code, out) ->
              Alcotest.(check bool) "protected app exit code 0 (VM result matches native)" true (code = 0);
              Alcotest.(check bool) "app printed the expected halfword 0xF6AA" true (String.contains out 'F' && String.contains out '6')
          | None -> Alcotest.fail "uint16 pipeline produced no execution output"))

let contains_sub s sub =
  let len_s = String.length s in
  let len_sub = String.length sub in
  if len_sub > len_s then false
  else
    let found = ref false in
    for i = 0 to len_s - len_sub do
      if not !found && String.sub s i len_sub = sub then found := true
    done;
    !found

let test_e2e_multi_function_pipeline () =
  let c_src = {|
#include <stdio.h>
#include <stdint.h>
#include "asgard_obf.h"

static uint64_t func_one(uint64_t a, uint64_t b) {
    ASGARD_BEGIN_VIRTUALIZE("func_one");
    volatile uint64_t res = a + b;
    ASGARD_END();
    return res;
}

static uint64_t func_two(uint64_t a, uint64_t b) {
    ASGARD_BEGIN_VIRTUALIZE("func_two");
    volatile uint64_t res = (a ^ b) + 0x1337ULL;
    ASGARD_END();
    return res;
}

int main(void) {
    uint64_t v1 = func_one(100, 200);
    uint64_t v2 = func_two(0x5555, 0x1111);
    printf("func_one = %llu, func_two = %llu\n", (unsigned long long)v1, (unsigned long long)v2);
    uint64_t expected_v2 = (0x5555ULL ^ 0x1111ULL) + 0x1337ULL;
    return (v1 == 300ULL && v2 == expected_v2) ? 0 : 1;
}
|} in
  with_temp_dir (fun tmp_dir ->
      let c_path = Filename.concat tmp_dir "multi_app.c" in
      write_file_string c_path c_src;
      let out_dir = Filename.concat tmp_dir "out" in
      let cfg =
        Config_adapter.resolve
          ~config_file:None
          ~preset:None
          ~enable_cff:false
          ~enable_mba:false
          ~mba_depth:2
          ~seed:(Some 20261001)
      in
      let rng = Random.State.make [| 20261001 |] in
      let lifter = (module Arm64_lifter_adapter : Random_visa_ports.Protect_ports.Lifter) in
      let vm_packager = (module Vm_packagers.Threaded_vm_packager : Random_visa_ports.Protect_ports.Vm_packager) in
      let trampoline = (module C_trampoline_adapter.C_trampoline_engine : Random_visa_ports.Protect_ports.Trampoline_engine) in
      let toolchain = (module Clang_toolchain_adapter : Random_visa_ports.Protect_ports.Toolchain) in
      let c_macro = (module C_macro_obf_adapter : Random_visa_ports.Protect_ports.C_macro_obfuscator) in
      match
        Random_visa_application.Protect_pipeline.run
          ~lifter
          ~c_macro_obfuscator:c_macro
          ~vm_packager
          ~trampoline_engine:trampoline
          ~toolchain
          ~rng
          ~config:cfg
          ~input_file:c_path
          ~out_dir
          ~compile_and_run:true
          ()
      with
      | Error err -> Alcotest.fail ("multi-function pipeline failed: " ^ err)
      | Ok res ->
          let virt_cpp = Filename.concat out_dir "app_virtualized.cpp" in
          let virt_src = read_file_string virt_cpp in
          Alcotest.(check bool) "virt_cpp has embedded_bytecode_func_one" true
            (contains_sub virt_src "embedded_bytecode_func_one");
          Alcotest.(check bool) "virt_cpp has embedded_bytecode_func_two" true
            (contains_sub virt_src "embedded_bytecode_func_two");
          let hpp_path = Filename.concat out_dir "threaded_vm.hpp" in
          let hpp_src = read_file_string hpp_path in
          Alcotest.(check bool) "threaded_vm.hpp has valid_hashes" true
            (contains_sub hpp_src "valid_hashes");
          (match res.execution_output with
          | Some (code, out) ->
              Alcotest.(check bool) "multi-function protected app exit code 0" true (code = 0);
              Alcotest.(check bool) "app printed expected output" true (contains_sub out "func_one = 300")
          | None -> Alcotest.fail "multi-function pipeline produced no execution output"))

(* TODO item 1 acceptance, part 2: the same uint16_t region compiled by clang
   at -O2 and -O3 (both emit identical codegen here), lifted from the marker
   region and executed natively through asgard_vm_call with the real argument.
   Old byte-only handlers yield 0x5A instead of 0xF6AA; the shifted-add
   catch-all bug (fixed alongside) would additionally yield 0xC1E6. *)
let test_e2e_uint16_clang_o2_o3 () =
  let c_src = {|
#include <stdint.h>
#define ASGARD_BEGIN_VIRTUALIZE(tag) \
    __asm__ volatile ("b 1f \n\t .ascii \"ASGARD_BEG_V____\" \n\t .balign 4 \n 1:\n\t")
#define ASGARD_END() \
    __asm__ volatile ("b 1f \n\t .ascii \"ASGARD_END______\" \n\t .balign 4 \n 1:\n\t")

static uint64_t u16_math(uint64_t input) {
    ASGARD_BEGIN_VIRTUALIZE("u16math");
    volatile uint16_t acc = (uint16_t)(input & 0xFFFFu);
    acc = (uint16_t)(acc + (uint16_t)(input >> 16));
    acc = (uint16_t)(acc ^ 0x5A5Au);
    ASGARD_END();
    return acc;
}

/* Without a caller clang dead-strips the unused static function at -O2/-O3 and
   the marker region disappears from the asm entirely.  main keeps it alive; it
   also constant-folds the region constants for exactly the argument value the
   runner later feeds to asgard_vm_call (0x12349ABC), so the expected result is
   unchanged. */
int main(void) {
    return (u16_math(0x12349ABCU) & 1) ? 0 : 1;
}
|} in
  let cfg =
    Config_adapter.resolve
      ~config_file:None
      ~preset:None
      ~enable_cff:false
      ~enable_mba:false
      ~mba_depth:2
      ~seed:(Some 20260931)
  in
  with_temp_dir (fun tmp_dir ->
      let c_path = Filename.concat tmp_dir "u16_o.c" in
      write_file_string c_path c_src;
      List.iter
        (fun (opt, name) ->
          let asm_path = Filename.concat tmp_dir (name ^ ".s") in
          (* -fno-inline mirrors the pipeline's clang flags: without it clang
             inlines u16_math into main and the collect-until-ret region would
             swallow main's `and w0, w8, #1` tail.  IPA constant-prop still
             folds the region constants for 0x12349ABC — the exact value the
             runner feeds to asgard_vm_call — so the expected result holds. *)
          let comp_status =
            Sys.command
              (Printf.sprintf
                 "clang -S %s -fno-inline -fno-stack-protector -fno-asynchronous-unwind-tables -o %s %s"
                 opt asm_path c_path)
          in
          Alcotest.(check int) (name ^ ": clang -S compiles") 0 comp_status;
          let asm_text = read_file_string asm_path in
          let lifted = Arm64_lifter_adapter.lift_source asm_text in
          let func =
            match lifted with
            | Error err -> Alcotest.fail (Printf.sprintf "%s: lift failed: %s" name err)
            | Ok (f, _) -> f
          in
          (* The marker region must actually contain B16 memory traffic. *)
          let unwrapped : Ir.func = Random_visa_ports.Protect_ports.unwrap_ir func in
          let b16_ops = ref 0 in
          Hashtbl.iter
            (fun _ (b : Ir.basic_block) ->
              List.iter
                (function
                  | Ir.Mov { dst = Ir.Mem { width = Register.B16; _ }; _ }
                  | Ir.Mov { src = Ir.Mem { width = Register.B16; _ }; _ } -> incr b16_ops
                  | _ -> ())
                b.instrs)
            unwrapped.cfg.blocks;
          Alcotest.(check bool) (name ^ ": lifted region contains B16 loads/stores") true (!b16_ops >= 4);
          let rng = Random.State.make [| 20260931 |] in
          let native_cfg : Protection_config.t = Random_visa_ports.Protect_ports.unwrap_config cfg in
          let pkg = Vm_emitter.compile_and_package ~rng ~config:native_cfg unwrapped in
          run_custom_vm ~name tmp_dir pkg {|
    uint64_t r = vanguard_threaded_vm::asgard_vm_call(embedded_bytecode, count, 0x12349ABCULL);
    if (r != 0xF6AAULL) return 1;
|})
        [ ("-O2", "u16o2"); ("-O3", "u16o3") ])

(* TODO item 2 acceptance, part 1: native execution of signed loads (movsx/movsxd)
   through the width-blind threaded VM.  Values -5 (int8), -300 (int16), -100000 (int32)
   are written to the stack, loaded with sign-extension, and summed.  Old zero-extending
   handlers yield positive numbers (>4 billion for int32), making the sum diverge. *)
let test_native_signed_loads () =
  let pkg =
    mk_pkg ~seed:20260935 {|
func_native_signed_loads:
    mov byte ptr [rsp - 8], dil
    mov word ptr [rsp - 16], si
    mov dword ptr [rsp - 24], edx
    movsx rax, byte ptr [rsp - 8]
    movsx rcx, word ptr [rsp - 16]
    add rax, rcx
    movsxd rcx, dword ptr [rsp - 24]
    add rax, rcx
    ret
|}
  in
  with_temp_dir (fun tmp_dir ->
      run_custom_vm ~name:"native_signed_loads" tmp_dir pkg {|
    static uint64_t scratch[8] = {0};
    vanguard_threaded_vm::VMContext ctx = {};
    ctx.init();
    ctx.set_reg(vanguard_threaded_vm::REG_RSP, (uint64_t)(scratch + 4));
    ctx.set_rdi((uint64_t)(-5LL));
    ctx.set_rsi((uint64_t)(-300LL));
    ctx.set_reg(vanguard_threaded_vm::REG_RDX, (uint64_t)(-100000LL));
    if (!vanguard_threaded_vm::execute_threaded(ctx, embedded_bytecode, count)) return 1;
    int64_t sum = (int64_t)ctx.get_rax();
    if (sum != -100305LL) return 2;
|})

(* TODO item 2 acceptance, part 2: E2E C code with signed char, short, and int
   compiled under clang -O2 and -O3, lifted via the marker region and executed
   natively via asgard_vm_call. *)
let test_e2e_signed_loads_clang_o2_o3 () =
  let c_src = {|
#include <stdint.h>
#define ASGARD_BEGIN_VIRTUALIZE(tag) \
    __asm__ volatile ("b 1f \n\t .ascii \"ASGARD_BEG_V____\" \n\t .balign 4 \n 1:\n\t")
#define ASGARD_END() \
    __asm__ volatile ("b 1f \n\t .ascii \"ASGARD_END______\" \n\t .balign 4 \n 1:\n\t")

static int64_t signed_math(int64_t a, int64_t b, int64_t c) {
    ASGARD_BEGIN_VIRTUALIZE("signed_math");
    volatile signed char x = (signed char)a;
    volatile short y = (short)b;
    volatile int z = (int)c;
    int64_t sum = (int64_t)x + (int64_t)y + (int64_t)z;
    ASGARD_END();
    return sum;
}

int main(void) {
    return (signed_math(-5, -300, -100000) == -100305LL) ? 0 : 1;
}
|} in
  let cfg =
    Config_adapter.resolve
      ~config_file:None
      ~preset:None
      ~enable_cff:false
      ~enable_mba:false
      ~mba_depth:2
      ~seed:(Some 20260936)
  in
  with_temp_dir (fun tmp_dir ->
      let c_path = Filename.concat tmp_dir "s_math.c" in
      write_file_string c_path c_src;
      List.iter
        (fun (opt, name) ->
          let asm_path = Filename.concat tmp_dir (name ^ ".s") in
          let comp_status =
            Sys.command
              (Printf.sprintf
                 "clang -S %s -fno-inline -fno-stack-protector -fno-asynchronous-unwind-tables -o %s %s"
                 opt asm_path c_path)
          in
          Alcotest.(check int) (name ^ ": clang -S compiles") 0 comp_status;
          let asm_text = read_file_string asm_path in
          let lifted = Arm64_lifter_adapter.lift_source asm_text in
          let func =
            match lifted with
            | Error err -> Alcotest.fail (Printf.sprintf "%s: lift failed: %s" name err)
            | Ok (f, _) -> f
          in
          let unwrapped : Ir.func = Random_visa_ports.Protect_ports.unwrap_ir func in
          let signed_ops = ref 0 in
          Hashtbl.iter
            (fun _ (b : Ir.basic_block) ->
              List.iter
                (function
                  | Ir.Mov { src = Ir.Mem { is_signed = true; _ }; _ } -> incr signed_ops
                  | _ -> ())
                b.instrs)
            unwrapped.cfg.blocks;
          Alcotest.(check bool) (name ^ ": lifted region contains signed loads") true (!signed_ops >= 3);
          let rng = Random.State.make [| 20260936 |] in
          let native_cfg : Protection_config.t = Random_visa_ports.Protect_ports.unwrap_config cfg in
          let pkg = Vm_emitter.compile_and_package ~rng ~config:native_cfg unwrapped in
          run_custom_vm ~name tmp_dir pkg {|
    uint64_t r = vanguard_threaded_vm::asgard_vm_call(embedded_bytecode, count, (uint64_t)(-5LL), (uint64_t)(-300LL), (uint64_t)(-100000LL));
    if ((int64_t)r != -100305LL) return 1;
|})
        [ ("-O2", "s_o2"); ("-O3", "s_o3") ])

let test_e2e_sub64_signed_comparisons_clang_o2_o3 () =
  let c_src = {|
#include <stdint.h>

int32_t classify_range(int32_t x) {
    if (x < -100) return -1;
    if (x < 0) return -2;
    if (x == 0) return 0;
    if (x <= 100) return 1;
    return 2;
}
|} in
  let cfg =
    Config_adapter.resolve
      ~config_file:None
      ~preset:None
      ~enable_cff:false
      ~enable_mba:false
      ~mba_depth:2
      ~seed:(Some 20261012)
  in
  with_temp_dir (fun tmp_dir ->
      let c_path = Filename.concat tmp_dir "sub64_cmp.c" in
      write_file_string c_path c_src;
      List.iter
        (fun (opt, name) ->
          let asm_path = Filename.concat tmp_dir (name ^ ".s") in
          let comp_status =
            Sys.command
              (Printf.sprintf
                 "clang -S %s -fno-inline -fno-stack-protector -fno-asynchronous-unwind-tables -o %s %s"
                 opt asm_path c_path)
          in
          Alcotest.(check int) (name ^ ": clang -S compiles") 0 comp_status;
          let asm_text = read_file_string asm_path in
          let lifted = Arm64_lifter.lift_function asm_text in
          let func =
            match lifted with
            | Error err -> Alcotest.fail (Printf.sprintf "%s: lift failed: %s" name err)
            | Ok f -> f
          in
          let rng = Random.State.make [| 20261012 |] in
          let native_cfg : Protection_config.t = Random_visa_ports.Protect_ports.unwrap_config cfg in
          let pkg = Vm_emitter.compile_and_package ~rng ~config:native_cfg func in
          run_custom_vm ~name tmp_dir pkg {|
    int32_t r1 = (int32_t)vanguard_threaded_vm::asgard_vm_call(embedded_bytecode, count, (uint64_t)(-500LL));
    int32_t r2 = (int32_t)vanguard_threaded_vm::asgard_vm_call(embedded_bytecode, count, (uint64_t)(-50LL));
    int32_t r3 = (int32_t)vanguard_threaded_vm::asgard_vm_call(embedded_bytecode, count, 0ULL);
    int32_t r4 = (int32_t)vanguard_threaded_vm::asgard_vm_call(embedded_bytecode, count, 50ULL);
    int32_t r5 = (int32_t)vanguard_threaded_vm::asgard_vm_call(embedded_bytecode, count, 500ULL);
    printf("classify_range results: r1=%d r2=%d r3=%d r4=%d r5=%d\n", r1, r2, r3, r4, r5);
    if (r1 != -1 || r2 != -2 || r3 != 0 || r4 != 1 || r5 != 2) return 1;
|})
        [ ("-O2", "cmp_o2"); ("-O3", "cmp_o3") ])

let test_e2e_stack_frame_sync_clang_o2_o3 () =
  let c_src = {|
#include <stdint.h>

int64_t stack_sort(int64_t a, int64_t b, int64_t c, int64_t d) {
    volatile int64_t arr[4];
    arr[0] = a;
    arr[1] = b;
    arr[2] = c;
    arr[3] = d;
    for (int i = 0; i < 3; i++) {
        for (int j = 0; j < 3 - i; j++) {
            if (arr[j] > arr[j + 1]) {
                int64_t tmp = arr[j];
                arr[j] = arr[j + 1];
                arr[j + 1] = tmp;
            }
        }
    }
    return (arr[0] * 1000) + (arr[1] * 100) + (arr[2] * 10) + arr[3];
}
|} in
  let cfg =
    Config_adapter.resolve
      ~config_file:None
      ~preset:None
      ~enable_cff:false
      ~enable_mba:false
      ~mba_depth:2
      ~seed:(Some 20261013)
  in
  with_temp_dir (fun tmp_dir ->
      let c_path = Filename.concat tmp_dir "stack_sync.c" in
      write_file_string c_path c_src;
      List.iter
        (fun (opt, name) ->
          let asm_path = Filename.concat tmp_dir (name ^ ".s") in
          let comp_status =
            Sys.command
              (Printf.sprintf
                 "clang -S %s -fno-inline -fno-stack-protector -fno-asynchronous-unwind-tables -o %s %s"
                 opt asm_path c_path)
          in
          Alcotest.(check int) (name ^ ": clang -S compiles") 0 comp_status;
          let asm_text = read_file_string asm_path in
          let lifted = Arm64_lifter.lift_function asm_text in
          let func =
            match lifted with
            | Error err -> Alcotest.fail (Printf.sprintf "%s: lift failed: %s" name err)
            | Ok f -> f
          in
          let rng = Random.State.make [| 20261013 |] in
          let native_cfg : Protection_config.t = Random_visa_ports.Protect_ports.unwrap_config cfg in
          let pkg = Vm_emitter.compile_and_package ~rng ~config:native_cfg func in
          run_custom_vm ~name tmp_dir pkg {|
    // Input: 40, 10, 30, 20 -> Sorted: 10, 20, 30, 40 -> Result: 10*1000 + 20*100 + 30*10 + 40 = 12340
    uint64_t r = vanguard_threaded_vm::asgard_vm_call(embedded_bytecode, count, 40ULL, 10ULL, 30ULL, 20ULL);
    printf("stack_sort result: r=%llu\n", (unsigned long long)r);
    if (r != 12340ULL) return 1;
|})
        [ ("-O2", "stk_o2"); ("-O3", "stk_o3") ])

let test_e2e_switch_jump_table_clang_o2_o3 () =
  let c_src = {|
#include <stdint.h>

int32_t dispatch_op(int32_t op, int32_t a, int32_t b) {
    switch (op) {
        case 0: return a + b;
        case 1: return a - b;
        case 2: return a * b;
        case 3: return (b != 0) ? (a / b) : 0;
        case 4: return a ^ b;
        case 5: return a | b;
        case 6: return a & b;
        case 7: return (a << 3) + b;
        default: return -1;
    }
}
|} in
  let cfg =
    Config_adapter.resolve
      ~config_file:None
      ~preset:None
      ~enable_cff:false
      ~enable_mba:false
      ~mba_depth:2
      ~seed:(Some 20261014)
  in
  with_temp_dir (fun tmp_dir ->
      let c_path = Filename.concat tmp_dir "switch_dispatch.c" in
      write_file_string c_path c_src;
      List.iter
        (fun (opt, name) ->
          let asm_path = Filename.concat tmp_dir (name ^ ".s") in
          let comp_status =
            Sys.command
              (Printf.sprintf
                 "clang -S %s -fno-inline -fno-stack-protector -fno-asynchronous-unwind-tables -o %s %s"
                 opt asm_path c_path)
          in
          Alcotest.(check int) (name ^ ": clang -S compiles") 0 comp_status;
          let asm_text = read_file_string asm_path in
          let lifted = Arm64_lifter.lift_function asm_text in
          let func =
            match lifted with
            | Error err -> Alcotest.fail (Printf.sprintf "%s: lift failed: %s" name err)
            | Ok f -> f
          in
          let rng = Random.State.make [| 20261014 |] in
          let native_cfg : Protection_config.t = Random_visa_ports.Protect_ports.unwrap_config cfg in
          let pkg = Vm_emitter.compile_and_package ~rng ~config:native_cfg func in
          run_custom_vm ~name tmp_dir pkg {|
    int32_t r0 = (int32_t)vanguard_threaded_vm::asgard_vm_call(embedded_bytecode, count, 0ULL, 10ULL, 20ULL);
    int32_t r1 = (int32_t)vanguard_threaded_vm::asgard_vm_call(embedded_bytecode, count, 1ULL, 10ULL, 20ULL);
    int32_t r2 = (int32_t)vanguard_threaded_vm::asgard_vm_call(embedded_bytecode, count, 2ULL, 10ULL, 20ULL);
    int32_t r3 = (int32_t)vanguard_threaded_vm::asgard_vm_call(embedded_bytecode, count, 3ULL, 100ULL, 5ULL);
    int32_t r4 = (int32_t)vanguard_threaded_vm::asgard_vm_call(embedded_bytecode, count, 4ULL, 0x12ULL, 0x34ULL);
    int32_t r5 = (int32_t)vanguard_threaded_vm::asgard_vm_call(embedded_bytecode, count, 5ULL, 0x10ULL, 0x02ULL);
    int32_t r6 = (int32_t)vanguard_threaded_vm::asgard_vm_call(embedded_bytecode, count, 6ULL, 0x12ULL, 0x02ULL);
    int32_t r7 = (int32_t)vanguard_threaded_vm::asgard_vm_call(embedded_bytecode, count, 7ULL, 5ULL, 4ULL);
    int32_t r_def = (int32_t)vanguard_threaded_vm::asgard_vm_call(embedded_bytecode, count, 99ULL, 10ULL, 20ULL);
    printf("switch dispatch results: r0=%d r1=%d r2=%d r3=%d r4=%d r5=%d r6=%d r7=%d r_def=%d\n",
           r0, r1, r2, r3, r4, r5, r6, r7, r_def);
    if (r0 != 30 || r1 != -10 || r2 != 200 || r3 != 20 || r4 != 0x26 || r5 != 0x12 || r6 != 0x02 || r7 != 44 || r_def != -1) return 1;
|})
        [ ("-O2", "sw_o2"); ("-O3", "sw_o3") ])

let test_e2e_indirect_branch_clang_o2_o3 () =
  let c_src = {|
#include <stdint.h>

typedef int32_t (*binop_fn)(int32_t, int32_t);

int32_t dispatch_fn(binop_fn fn, int32_t a, int32_t b) {
    if (!fn) return -1;
    return fn(a, b);
}
|} in
  let cfg =
    Config_adapter.resolve
      ~config_file:None
      ~preset:None
      ~enable_cff:false
      ~enable_mba:false
      ~mba_depth:2
      ~seed:(Some 20261015)
  in
  with_temp_dir (fun tmp_dir ->
      let c_path = Filename.concat tmp_dir "indirect_dispatch.c" in
      write_file_string c_path c_src;
      List.iter
        (fun (opt, name) ->
          let asm_path = Filename.concat tmp_dir (name ^ ".s") in
          let comp_status =
            Sys.command
              (Printf.sprintf
                 "clang -S %s -fno-inline -fno-stack-protector -fno-asynchronous-unwind-tables -o %s %s"
                 opt asm_path c_path)
          in
          Alcotest.(check int) (name ^ ": clang -S compiles") 0 comp_status;
          let asm_text = read_file_string asm_path in
          let lifted = Arm64_lifter.lift_function asm_text in
          let func =
            match lifted with
            | Error err -> Alcotest.fail (Printf.sprintf "%s: lift failed: %s" name err)
            | Ok f -> f
          in
          let rng = Random.State.make [| 20261015 |] in
          let native_cfg : Protection_config.t = Random_visa_ports.Protect_ports.unwrap_config cfg in
          let pkg = Vm_emitter.compile_and_package ~rng ~config:native_cfg func in
          run_custom_vm ~name tmp_dir pkg {|
    typedef int32_t (*host_fn_t)(int32_t, int32_t);
    host_fn_t p_add = [](int32_t a, int32_t b) -> int32_t { return a + b; };
    host_fn_t p_mul = [](int32_t a, int32_t b) -> int32_t { return a * b; };
    int32_t r1 = (int32_t)vanguard_threaded_vm::asgard_vm_call(embedded_bytecode, count, (uint64_t)p_add, 10ULL, 20ULL);
    int32_t r2 = (int32_t)vanguard_threaded_vm::asgard_vm_call(embedded_bytecode, count, (uint64_t)p_mul, 10ULL, 20ULL);
    int32_t r3 = (int32_t)vanguard_threaded_vm::asgard_vm_call(embedded_bytecode, count, 0ULL, 10ULL, 20ULL);
    printf("indirect branch results: r1=%d r2=%d r3=%d\n", r1, r2, r3);
    if (r1 != 30 || r2 != 200 || r3 != -1) return 1;
|})
        [ ("-O2", "ibr_o2"); ("-O3", "ibr_o3") ])

let test_e2e_bit_test_and_branch_clang_o2_o3 () =
  let c_src = {|
#include <stdint.h>

uint64_t bit_test_func(uint64_t val, uint64_t mask) {
    uint64_t acc = 0;
    if (val & 0x04) {
        acc += 100;
    } else {
        acc += 20;
    }
    if ((val & 0x08) == 0) {
        acc += 200;
    } else {
        acc += 40;
    }
    if (val == mask) {
        acc += 500;
    }
    if (val < mask) {
        acc += 1000;
    }
    return acc;
}
|} in
  let cfg =
    Config_adapter.resolve
      ~config_file:None
      ~preset:None
      ~enable_cff:false
      ~enable_mba:false
      ~mba_depth:2
      ~seed:(Some 20261016)
  in
  with_temp_dir (fun tmp_dir ->
      let c_path = Filename.concat tmp_dir "bit_test.c" in
      write_file_string c_path c_src;
      List.iter
        (fun (opt, name) ->
          let asm_path = Filename.concat tmp_dir (name ^ ".s") in
          let comp_status =
            Sys.command
              (Printf.sprintf
                 "clang -S %s -fno-inline -fno-stack-protector -fno-asynchronous-unwind-tables -o %s %s"
                 opt asm_path c_path)
          in
          Alcotest.(check int) (name ^ ": clang -S compiles") 0 comp_status;
          let asm_text = read_file_string asm_path in
          let lifted = Arm64_lifter.lift_function asm_text in
          let func =
            match lifted with
            | Error err -> Alcotest.fail (Printf.sprintf "%s: lift failed: %s" name err)
            | Ok f -> f
          in
          let rng = Random.State.make [| 20261016 |] in
          let native_cfg : Protection_config.t = Random_visa_ports.Protect_ports.unwrap_config cfg in
          let pkg = Vm_emitter.compile_and_package ~rng ~config:native_cfg func in
          run_custom_vm ~name tmp_dir pkg {|
    uint64_t r1 = vanguard_threaded_vm::asgard_vm_call(embedded_bytecode, count, 0x04ULL, 0x04ULL);
    uint64_t r2 = vanguard_threaded_vm::asgard_vm_call(embedded_bytecode, count, 0x08ULL, 0x10ULL);
    printf("bit_test results: r1=%llu r2=%llu\n", (unsigned long long)r1, (unsigned long long)r2);
    if (r1 != 800ULL || r2 != 1060ULL) return 1;
|})
        [ ("-O2", "bt_o2"); ("-O3", "bt_o3") ])

(* Item 9: 3-address ALU canonicalization unit test *)
let test_canonicalize_3addr_alu_unit () =
  (* 1. Distinct registers: add rax, rbx, rcx *)
  let i1 = Ir.Alu { op = Ir.Add; dst = Register.rax; src1 = Ir.Reg Register.rbx; src2 = Ir.Reg Register.rcx; set_flags = false } in
  let c1 = Vm_transform.canonicalize_3addr_alu [ i1 ] in
  Alcotest.(check int) "distinct 3addr decomposes into 2 instrs" 2 (List.length c1);
  (match c1 with
   | [ Ir.Mov { dst = Ir.Reg d; src = Ir.Reg s };
       Ir.Alu { op = Ir.Add; dst = d2; src1 = Ir.Reg s1; src2 = Ir.Reg s2; _ } ] ->
       Alcotest.(check string) "mov dst is rax" "rax" (Register.to_string d);
       Alcotest.(check string) "mov src is rbx" "rbx" (Register.to_string s);
       Alcotest.(check string) "alu dst is rax" "rax" (Register.to_string d2);
       Alcotest.(check string) "alu src1 is rax" "rax" (Register.to_string s1);
       Alcotest.(check string) "alu src2 is rcx" "rcx" (Register.to_string s2)
   | _ -> Alcotest.fail "unexpected decomposition for distinct 3addr");

  (* 2. Commutative hazard: add rax, rbx, rax (dst == src2) *)
  let i2 = Ir.Alu { op = Ir.Add; dst = Register.rax; src1 = Ir.Reg Register.rbx; src2 = Ir.Reg Register.rax; set_flags = false } in
  let c2 = Vm_transform.canonicalize_3addr_alu [ i2 ] in
  Alcotest.(check int) "commutative hazard swaps operands with 0 extra mov" 1 (List.length c2);
  (match c2 with
   | [ Ir.Alu { op = Ir.Add; dst = d; src1 = Ir.Reg s1; src2 = Ir.Reg s2; _ } ] ->
       Alcotest.(check string) "alu dst is rax" "rax" (Register.to_string d);
       Alcotest.(check string) "alu src1 is rax" "rax" (Register.to_string s1);
       Alcotest.(check string) "alu src2 is rbx" "rbx" (Register.to_string s2)
   | _ -> Alcotest.fail "unexpected decomposition for commutative hazard");

  (* 3. Non-commutative hazard: sub rax, rbx, rax (dst == src2) *)
  let i3 = Ir.Alu { op = Ir.Sub; dst = Register.rax; src1 = Ir.Reg Register.rbx; src2 = Ir.Reg Register.rax; set_flags = false } in
  let c3 = Vm_transform.canonicalize_3addr_alu [ i3 ] in
  Alcotest.(check int) "non-commutative hazard uses scratch with 3 instrs" 3 (List.length c3);
  (match c3 with
   | [ Ir.Mov { dst = Ir.Reg scratch; src = Ir.Reg old_dst };
       Ir.Mov { dst = Ir.Reg d; src = Ir.Reg s1 };
       Ir.Alu { op = Ir.Sub; dst = d2; src1 = Ir.Reg s1_2; src2 = Ir.Reg s2; _ } ] ->
       Alcotest.(check string) "scratch saved from rax" "rax" (Register.to_string old_dst);
       Alcotest.(check string) "dst loaded from rbx" "rax" (Register.to_string d);
       Alcotest.(check string) "src was rbx" "rbx" (Register.to_string s1);
       Alcotest.(check string) "alu dst is rax" "rax" (Register.to_string d2);
       Alcotest.(check string) "alu src1 is rax" "rax" (Register.to_string s1_2);
       Alcotest.(check string) "alu src2 is scratch" (Register.to_string scratch) (Register.to_string s2)
   | _ -> Alcotest.fail "unexpected decomposition for non-commutative hazard");

  (* 4. 3-address with immediate: add rax, rbx, 42 *)
  let i4 = Ir.Alu { op = Ir.Add; dst = Register.rax; src1 = Ir.Reg Register.rbx; src2 = Ir.Imm 42L; set_flags = false } in
  let c4 = Vm_transform.canonicalize_3addr_alu [ i4 ] in
  Alcotest.(check int) "immediate 3addr decomposes into 2 instrs" 2 (List.length c4);
  (match c4 with
   | [ Ir.Mov { dst = Ir.Reg d; src = Ir.Reg s };
       Ir.Alu { op = Ir.Add; dst = d2; src1 = Ir.Reg s1; src2 = Ir.Imm 42L; _ } ] ->
       Alcotest.(check string) "mov dst is rax" "rax" (Register.to_string d);
       Alcotest.(check string) "mov src is rbx" "rbx" (Register.to_string s);
       Alcotest.(check string) "alu dst is rax" "rax" (Register.to_string d2);
       Alcotest.(check string) "alu src1 is rax" "rax" (Register.to_string s1)
   | _ -> Alcotest.fail "unexpected decomposition for immediate 3addr")

(* Item 9: Native threaded VM execution with 3-address ALU IR (distinct + hazard) *)
let test_native_3addr_alu () =
  let block = {
    Ir.id = 0;
    label = "entry";
    instrs = [
      (* rax = rdi + rsi = 10 + 20 = 30 *)
      Ir.Alu { op = Ir.Add; dst = Register.rax; src1 = Ir.Reg Register.rdi; src2 = Ir.Reg Register.rsi; set_flags = false };
      (* rax = rdx - rax = 50 - 30 = 20 (hazard: s2 == dst with non-commutative Sub) *)
      Ir.Alu { op = Ir.Sub; dst = Register.rax; src1 = Ir.Reg Register.rdx; src2 = Ir.Reg Register.rax; set_flags = false };
      (* rcx = rdi * rsi = 10 * 20 = 200 *)
      Ir.Alu { op = Ir.Imul; dst = Register.rcx; src1 = Ir.Reg Register.rdi; src2 = Ir.Reg Register.rsi; set_flags = false };
      (* rcx = rcx / rdx = 200 / 50 = 4 *)
      Ir.Alu { op = Ir.Idiv; dst = Register.rcx; src1 = Ir.Reg Register.rcx; src2 = Ir.Reg Register.rdx; set_flags = false };
      (* rax = rax + rcx = 20 + 4 = 24 *)
      Ir.Alu { op = Ir.Add; dst = Register.rax; src1 = Ir.Reg Register.rax; src2 = Ir.Reg Register.rcx; set_flags = false };
      Ir.Ret;
    ];
  } in
  let blocks = Hashtbl.create 1 in
  Hashtbl.replace blocks 0 block;
  let func = { Ir.name = "func_3addr_test"; cfg = { entry_id = 0; blocks } } in
  let rng = Random.State.make [| 20260937 |] in
  let pkg = Vm_emitter.compile_and_package ~rng func in
  with_temp_dir (fun tmp_dir ->
      run_custom_vm ~name:"native_3addr" tmp_dir pkg {|
    vanguard_threaded_vm::VMContext ctx = {};
    ctx.init();
    ctx.set_rdi(10);
    ctx.set_rsi(20);
    ctx.set_reg(vanguard_threaded_vm::REG_RDX, 50);
    if (!vanguard_threaded_vm::execute_threaded(ctx, embedded_bytecode, count)) return 1;
    if (ctx.get_rax() != 24) return 2;
|})

(* Item 9: Native threaded VM execution of ARM64 madd/msub/sdiv/bic *)
let test_native_arm64_3addr_madd_msub_sdiv_bic () =
  let asm = {|
    mov x1, #7
    mov x2, #6
    mov x3, #100
    madd x4, x1, x2, x3
    msub x5, x1, x2, x3
    sdiv x6, x3, x1
    bic x7, x3, x1
    add x0, x4, x5
    add x0, x0, x6
    add x0, x0, x7
    ret
  |} in
  let lifted = Arm64_lifter_adapter.lift_source asm in
  let func =
    match lifted with
    | Error err -> Alcotest.fail ("lift failed: " ^ err)
    | Ok (f, _) -> f
  in
  let unwrapped : Ir.func = Random_visa_ports.Protect_ports.unwrap_ir func in
  let rng = Random.State.make [| 20260938 |] in
  let pkg = Vm_emitter.compile_and_package ~rng unwrapped in
  with_temp_dir (fun tmp_dir ->
      run_custom_vm ~name:"arm64_3addr_native" tmp_dir pkg {|
    vanguard_threaded_vm::VMContext ctx = {};
    ctx.init();
    if (!vanguard_threaded_vm::execute_threaded(ctx, embedded_bytecode, count)) return 1;
    if (ctx.get_rax() != 310) return 2;
|})

let test_native_b8_b16_merge () =
  let pkg =
    mk_pkg ~seed:20260940 {|
func_native_merge:
    mov rax, 0x1122334455667788
    mov al, 0x99
    mov ax, 0xAABB
    ret
|}
  in
  with_temp_dir (fun tmp_dir ->
      run_custom_vm ~name:"native_b8_b16_merge" tmp_dir pkg {|
    vanguard_threaded_vm::VMContext ctx = {};
    ctx.init();
    if (!vanguard_threaded_vm::execute_threaded(ctx, embedded_bytecode, count)) return 1;
    if (ctx.get_rax() != 0x112233445566AABBULL) return 2;
|})

let test_native_vector_fp () =
  let pkg =
    mk_pkg ~seed:20260939 {|
func_native_vector_fp:
    vaddps ymm3, ymm4, ymm5
    ret
|}
  in
  with_temp_dir (fun tmp_dir ->
      run_custom_vm ~name:"native_vector_fp" tmp_dir pkg {|
    vanguard_threaded_vm::VMContext ctx = {};
    ctx.init();
    ctx.vregs[4][0] = static_cast<uint64_t>(std::bit_cast<uint32_t>(1.0f)) |
                       (static_cast<uint64_t>(std::bit_cast<uint32_t>(2.0f)) << 32);
    ctx.vregs[4][1] = static_cast<uint64_t>(std::bit_cast<uint32_t>(3.0f)) |
                       (static_cast<uint64_t>(std::bit_cast<uint32_t>(4.0f)) << 32);
    ctx.vregs[5][0] = static_cast<uint64_t>(std::bit_cast<uint32_t>(10.0f)) |
                       (static_cast<uint64_t>(std::bit_cast<uint32_t>(20.0f)) << 32);
    ctx.vregs[5][1] = static_cast<uint64_t>(std::bit_cast<uint32_t>(30.0f)) |
                       (static_cast<uint64_t>(std::bit_cast<uint32_t>(40.0f)) << 32);
    if (!vanguard_threaded_vm::execute_threaded(ctx, embedded_bytecode, count)) return 1;
    uint32_t lane0 = static_cast<uint32_t>(ctx.vregs[3][0]);
    uint32_t lane1 = static_cast<uint32_t>(ctx.vregs[3][0] >> 32);
    uint32_t lane2 = static_cast<uint32_t>(ctx.vregs[3][1]);
    uint32_t lane3 = static_cast<uint32_t>(ctx.vregs[3][1] >> 32);
    if (std::bit_cast<float>(lane0) != 11.0f) return 2;
    if (std::bit_cast<float>(lane1) != 22.0f) return 3;
    if (std::bit_cast<float>(lane2) != 33.0f) return 4;
    if (std::bit_cast<float>(lane3) != 44.0f) return 5;
|})

(* The x86 SHA extensions (SHA-NI) in the native runtime: the same values as
   the reference VM produces. *)
let test_native_x86_sha_ni () =
  let pkg =
    mk_pkg ~seed:20260943 {|
func_native_sha:
    sha1rnds4 xmm3, xmm4, 0x0
    sha1nexte xmm5, xmm6
    sha1msg1 xmm7, xmm8
    sha1msg2 xmm9, xmm10
    sha256rnds2 xmm11, xmm12
    sha256msg1 xmm13, xmm14
    sha256msg2 xmm15, xmm16
    ret
|}
  in
  with_temp_dir (fun tmp_dir ->
      run_custom_vm ~name:"native_x86_sha_ni" tmp_dir pkg {|
    vanguard_threaded_vm::VMContext ctx = {};
    ctx.init();
    const uint64_t state_words[2] = {0x89ABCDEF01234567ULL, 0x76543210FEDCBA98ULL};
    const uint64_t src_words[2] = {0x2222222211111111ULL, 0x4444444433333333ULL};
    for (int reg : {3, 5, 7, 9, 11, 13, 15}) {
        ctx.vregs[reg][0] = state_words[0];
        ctx.vregs[reg][1] = state_words[1];
    }
    for (int reg : {4, 6, 8, 10, 12, 14, 16}) {
        ctx.vregs[reg][0] = src_words[0];
        ctx.vregs[reg][1] = src_words[1];
    }
    ctx.vregs[0][0] = 0x0BADF00DCAFEBABEULL;
    ctx.vregs[0][1] = 0;
    if (!vanguard_threaded_vm::execute_threaded(ctx, embedded_bytecode, count)) return 1;
    auto word = [&ctx](int reg, int i) -> uint32_t {
        return static_cast<uint32_t>(ctx.vregs[reg][i / 2] >> ((i % 2) * 32));
    };
    const uint32_t expected[7][4] = {
        {0xFA700561u, 0x0FBEFBB6u, 0xF3458385u, 0xA3B63C88u},
        {0xD159E26Au, 0x22222222u, 0x33333333u, 0x44444444u},
        {0xFFFFFFFFu, 0xFFFFFFFFu, 0xEFCDAB89u, 0x54761032u},
        {0x4602CE8Au, 0x7531FDB9u, 0x7531FDB9u, 0x60ADF934u},
        {0xC1C9B1D2u, 0xCAFE3234u, 0x64E9BCB2u, 0xCAFE7678u},
        {0x0FEEEDC8u, 0x20FDBA9Bu, 0xF0111236u, 0x89ABCDEFu},
        {0x54320FEDu, 0xEDCBA986u, 0xDBA986C3u, 0xCFE19A0Cu},
    };
    const int regs[7] = {3, 5, 7, 9, 11, 13, 15};
    for (int k = 0; k < 7; k++) {
        for (int i = 0; i < 4; i++) {
            if (word(regs[k], i) != expected[k][i]) return 2 + k;
        }
    }
|})

(* PCLMULQDQ and the CET shadow stack instructions in the native runtime: the
   same values as the reference VM produces. *)
let test_native_x86_pclmul_cet () =
  let pkg =
    mk_pkg ~seed:20260944 {|
func_native_pclmul_cet:
    pclmulqdq xmm3, xmm4, 0x00
    pclmulqdq xmm5, xmm6, 0x11
    rdsspq rax
    rdsspd ecx
    incsspq
    incsspd
    rdsspq rdx
    ret
|}
  in
  with_temp_dir (fun tmp_dir ->
      run_custom_vm ~name:"native_x86_pclmul_cet" tmp_dir pkg {|
    vanguard_threaded_vm::VMContext ctx = {};
    ctx.init();
    ctx.vregs[3][0] = 0x0123456789ABCDEFULL; ctx.vregs[3][1] = 0xFEDCBA9876543210ULL;
    ctx.vregs[4][0] = 0x1111111111111111ULL; ctx.vregs[4][1] = 0x2222222222222222ULL;
    ctx.vregs[5][0] = 0x0123456789ABCDEFULL; ctx.vregs[5][1] = 0xFEDCBA9876543210ULL;
    ctx.vregs[6][0] = 0x1111111111111111ULL; ctx.vregs[6][1] = 0x2222222222222222ULL;
    const uint64_t rsp_before = ctx.get_reg(vanguard_threaded_vm::REG_RSP);
    if (!vanguard_threaded_vm::execute_threaded(ctx, embedded_bytecode, count)) return 1;
    if (ctx.vregs[3][0] != 0x00130417081B0C1FULL) return 2;
    if (ctx.vregs[3][1] != 0x00130417081B0C1FULL) return 3;
    if (ctx.vregs[5][0] != 0x1E3816300E280620ULL) return 4;
    if (ctx.vregs[5][1] != 0xFEDCBA9876543210ULL) return 5;
    if (ctx.get_reg(vanguard_threaded_vm::REG_RAX) != 0x50000000ULL) return 6;
    if (ctx.get_reg(vanguard_threaded_vm::REG_RCX) != 0x50000000ULL) return 7;
    if (ctx.get_reg(vanguard_threaded_vm::REG_RDX) != 0x50000050ULL) return 8;
    if (ctx.get_reg(vanguard_threaded_vm::REG_RSP) != rsp_before - 80ULL) return 9;
|})

(* CPUID dynamic leaf execution in the native runtime: tests vendor string and leaf 0 *)
let test_native_x86_cpuid () =
  let pkg =
    mk_pkg ~seed:20260945 {|
func_native_cpuid:
    mov eax, 0
    cpuid
    ret
|}
  in
  with_temp_dir (fun tmp_dir ->
      run_custom_vm ~name:"native_x86_cpuid" tmp_dir pkg {|
    vanguard_threaded_vm::VMContext ctx = {};
    ctx.init();
    if (!vanguard_threaded_vm::execute_threaded(ctx, embedded_bytecode, count)) return 1;
    if (ctx.get_rax() < 1ULL) return 2;
    if (ctx.get_reg(vanguard_threaded_vm::REG_RBX) != 0x756E6547ULL) return 3;
    if (ctx.get_reg(vanguard_threaded_vm::REG_RDX) != 0x49656E69ULL) return 4;
    if (ctx.get_reg(vanguard_threaded_vm::REG_RCX) != 0x6C65746EULL) return 5;
|})

(* The FSGSBASE family (RDFSBASE, RDGSBASE, WRFSBASE, WRGSBASE) reaches the
   segment base registers of the VM context: the base is written into the
   context slot and read back through the same slot. *)
let test_native_x86_fsgsbase () =
  let pkg =
    mk_pkg ~seed:20260942 {|
func_native_fsgsbase:
    mov r10, 0x1122334455667788
    wrfsbase r10
    mov r11, 0x8877665544332211
    wrgsbase r11
    rdfsbase r8
    rdgsbase r9
    ret
|}
  in
  with_temp_dir (fun tmp_dir ->
      run_custom_vm ~name:"native_x86_fsgsbase" tmp_dir pkg {|
    vanguard_threaded_vm::VMContext ctx = {};
    ctx.init();
    if (!vanguard_threaded_vm::execute_threaded(ctx, embedded_bytecode, count)) return 1;
    if (ctx.get_reg(vanguard_threaded_vm::REG_R8) != 0x1122334455667788ULL) return 2;
    if (ctx.get_reg(vanguard_threaded_vm::REG_R9) != 0x8877665544332211ULL) return 3;
|})

let test_native_x86_shld_shrd_mem_and_cdq () =
  let pkg =
    mk_pkg ~seed:20260940 {|
func_native_shld_shrd:
    # 1. shld / shrd on memory
    mov [rsp - 16], rdi
    shld [rsp - 16], rsi, 16
    mov rax, [rsp - 16]
    mov [rsp - 24], rdi
    shrd [rsp - 24], rsi, 16
    mov r8, [rsp - 24]

    # 2. count 0 preserving dest on memory
    mov [rsp - 32], rdi
    shld [rsp - 32], rsi, 0
    mov r9, [rsp - 32]

    # 3. cdq with dirty upper 32-bit rax
    mov rax, 0x1234567800000005
    cdq
    mov r10, rdx
    mov rax, 0x1234567880000000
    cdq
    mov r11, rdx
    mov rax, [rsp - 16]
    ret
|}
  in
  with_temp_dir (fun tmp_dir ->
      run_custom_vm ~name:"native_shld_shrd_mem_cdq" tmp_dir pkg {|
    static uint64_t scratch[16] = {0};
    vanguard_threaded_vm::VMContext ctx = {};
    ctx.init();
    ctx.set_reg(vanguard_threaded_vm::REG_RSP, (uint64_t)(scratch + 8));
    ctx.set_rdi(0x1234567890ABCDEFULL);
    ctx.set_rsi(0xFEDCBA0987654321ULL);
    if (!vanguard_threaded_vm::execute_threaded(ctx, embedded_bytecode, count)) return 1;
    if (ctx.get_rax() != 0x567890ABCDEFFEDCULL) return 2;
    if (ctx.get_reg(vanguard_threaded_vm::REG_R8) != 0x43211234567890ABULL) return 3;
    if (ctx.get_reg(vanguard_threaded_vm::REG_R9) != 0x1234567890ABCDEFULL) return 4;
    if (ctx.get_reg(vanguard_threaded_vm::REG_R10) != 0ULL) return 5;
    if (ctx.get_reg(vanguard_threaded_vm::REG_R11) != 0xFFFFFFFFFFFFFFFFULL) return 6;
|})

(* Legacy x87 FPU stack execution, arithmetic, comparisons, and status word in native threaded VM *)
let test_native_x86_fpu () =
  let pkg =
    mk_pkg ~seed:20260946 {|
func_native_fpu:
    fld1
    fld1
    faddp
    fldpi
    fmulp
    fld1
    fchs
    fabs
    fldz
    fcomi st, st(1)
    setb dl
    fldln2
    fstsw ax
    ret
|}
  in
  with_temp_dir (fun tmp_dir ->
      run_custom_vm ~name:"native_x86_fpu" tmp_dir pkg {|
    vanguard_threaded_vm::VMContext ctx = {};
    ctx.init();
    if (!vanguard_threaded_vm::execute_threaded(ctx, embedded_bytecode, count)) return 1;
    // st(0) should be ln(2) (~0.693147)
    if (std::fabs(ctx.get_st(0) - 0.6931471805599453) > 1e-6) return 2;
    // st(1) was fldz (0.0)
    if (std::fabs(ctx.get_st(1) - 0.0) > 1e-6) return 3;
    // st(2) was fabs(fchs(fld1)) = 1.0
    if (std::fabs(ctx.get_st(2) - 1.0) > 1e-6) return 4;
    // st(3) was (1 + 1) * pi = 2 * pi (~6.283185)
    if (std::fabs(ctx.get_st(3) - 6.283185307179586) > 1e-5) return 5;
    // RDX low byte (dl) set by setb (CF=1 because 0.0 < 1.0)
    if ((ctx.get_reg(vanguard_threaded_vm::REG_RDX) & 0xFF) != 1) return 6;
|})

let test_native_x86_scalar_and_vector_moves () =
  let pkg =
    mk_pkg ~seed:20261021 {|
func_native_moves:
    movss xmm0, xmm1
    movsd xmm2, xmm3
    movss dword ptr [rsp + 16], xmm0
    movss xmm5, dword ptr [rsp + 16]
    movsd qword ptr [rsp + 24], xmm2
    movsd xmm6, qword ptr [rsp + 24]
    movaps xmm7, xmm1
    movups xmm8, xmm2
    movdqa xmm9, xmm3
    movdqu xmm10, xmm0
    ret
|}
  in
  with_temp_dir (fun tmp_dir ->
      run_custom_vm ~name:"native_x86_moves" tmp_dir pkg {|
    vanguard_threaded_vm::VMContext ctx = {};
    ctx.init();
    ctx.vregs[0][0] = 0x1111111122222222ULL;
    ctx.vregs[0][1] = 0x3333333344444444ULL;
    ctx.vregs[1][0] = 0xAAAABBBBCCCCDDDDULL;
    ctx.vregs[1][1] = 0xEEEEFFFF00001111ULL;
    ctx.vregs[2][0] = 0x123456789ABCDEF0ULL;
    ctx.vregs[2][1] = 0xFEDCBA9876543210ULL;
    ctx.vregs[3][0] = 0x0102030405060708ULL;
    ctx.vregs[3][1] = 0x090A0B0C0D0E0F00ULL;

    alignas(16) uint8_t stack_mem[64] = {};
    *reinterpret_cast<uint32_t*>(&stack_mem[20]) = 0xA5A5A5A5U;
    ctx.set_reg(vanguard_threaded_vm::REG_RSP, reinterpret_cast<uint64_t>(stack_mem));

    if (!vanguard_threaded_vm::execute_threaded(ctx, embedded_bytecode, count)) return 1;

    if (ctx.vregs[0][0] != 0x11111111CCCCDDDDULL) return 2;
    if (ctx.vregs[0][1] != 0x3333333344444444ULL) return 3;
    if (ctx.vregs[2][0] != 0x0102030405060708ULL) return 4;
    if (ctx.vregs[2][1] != 0xFEDCBA9876543210ULL) return 5;
    if (*reinterpret_cast<uint32_t*>(&stack_mem[20]) != 0xA5A5A5A5U) return 6;
    if (ctx.vregs[5][0] != 0x00000000CCCCDDDDULL) return 7;
    if (ctx.vregs[5][1] != 0ULL) return 8;
    if (ctx.vregs[6][0] != 0x0102030405060708ULL) return 9;
    if (ctx.vregs[6][1] != 0ULL) return 10;
    if (ctx.vregs[7][0] != 0xAAAABBBBCCCCDDDDULL || ctx.vregs[7][1] != 0xEEEEFFFF00001111ULL) return 11;
    if (ctx.vregs[8][0] != 0x0102030405060708ULL || ctx.vregs[8][1] != 0xFEDCBA9876543210ULL) return 12;
    if (ctx.vregs[9][0] != 0x0102030405060708ULL || ctx.vregs[9][1] != 0x090A0B0C0D0E0F00ULL) return 13;
    if (ctx.vregs[10][0] != 0x11111111CCCCDDDDULL || ctx.vregs[10][1] != 0x3333333344444444ULL) return 14;
|})

let test_native_x86_scalar_and_packed_fp_arithmetic () =
  let pkg =
    mk_pkg ~seed:20261022 {|
func_native_fp_arith:
    addss xmm0, xmm1
    subss xmm2, xmm3
    mulss xmm4, xmm5
    divss xmm6, xmm7
    addsd xmm8, xmm9
    subsd xmm10, xmm11
    mulsd xmm12, xmm13
    divsd xmm14, xmm15
    addpd xmm16, xmm17
    subpd xmm18, xmm19
    mulpd xmm20, xmm21
    divpd xmm22, xmm23
    ret
|}
  in
  with_temp_dir (fun tmp_dir ->
      run_custom_vm ~name:"native_fp_arith" tmp_dir pkg {|
    vanguard_threaded_vm::VMContext ctx = {};
    ctx.init();
    auto fbits = [](float f) { return static_cast<uint64_t>(std::bit_cast<uint32_t>(f)); };
    auto dbits = [](double d) { return std::bit_cast<uint64_t>(d); };

    ctx.vregs[0][0] = fbits(10.0f) | 0x1111111100000000ULL;
    ctx.vregs[0][1] = 0x2222222233333333ULL;
    ctx.vregs[1][0] = fbits(2.5f);

    ctx.vregs[2][0] = fbits(10.0f) | 0x4444444400000000ULL;
    ctx.vregs[2][1] = 0x5555555566666666ULL;
    ctx.vregs[3][0] = fbits(2.5f);

    ctx.vregs[4][0] = fbits(10.0f);
    ctx.vregs[4][1] = 0x7777777788888888ULL;
    ctx.vregs[5][0] = fbits(2.5f);

    ctx.vregs[6][0] = fbits(10.0f);
    ctx.vregs[6][1] = 0x99999999AAAAAAAAULL;
    ctx.vregs[7][0] = fbits(2.5f);

    ctx.vregs[8][0] = dbits(10.0);
    ctx.vregs[8][1] = 0xBBBBBBBBCCCCCCCCULL;
    ctx.vregs[9][0] = dbits(2.5);

    ctx.vregs[10][0] = dbits(10.0);
    ctx.vregs[10][1] = 0xDDDDDDDDEEEEEEEEULL;
    ctx.vregs[11][0] = dbits(2.5);

    ctx.vregs[12][0] = dbits(10.0);
    ctx.vregs[12][1] = 0xFFFFFFFF00000000ULL;
    ctx.vregs[13][0] = dbits(2.5);

    ctx.vregs[14][0] = dbits(10.0);
    ctx.vregs[14][1] = 0x1234567812345678ULL;
    ctx.vregs[15][0] = dbits(2.5);

    ctx.vregs[16][0] = dbits(1.0); ctx.vregs[16][1] = dbits(2.0);
    ctx.vregs[17][0] = dbits(3.0); ctx.vregs[17][1] = dbits(4.0);

    ctx.vregs[18][0] = dbits(10.0); ctx.vregs[18][1] = dbits(20.0);
    ctx.vregs[19][0] = dbits(1.0); ctx.vregs[19][1] = dbits(2.0);

    ctx.vregs[20][0] = dbits(2.0); ctx.vregs[20][1] = dbits(3.0);
    ctx.vregs[21][0] = dbits(4.0); ctx.vregs[21][1] = dbits(5.0);

    ctx.vregs[22][0] = dbits(10.0); ctx.vregs[22][1] = dbits(20.0);
    ctx.vregs[23][0] = dbits(2.0); ctx.vregs[23][1] = dbits(4.0);

    if (!vanguard_threaded_vm::execute_threaded(ctx, embedded_bytecode, count)) return 1;

    if ((ctx.vregs[0][0] & 0xFFFFFFFFULL) != fbits(12.5f)) return 2;
    if ((ctx.vregs[0][0] & 0xFFFFFFFF00000000ULL) != 0x1111111100000000ULL) return 3;
    if (ctx.vregs[0][1] != 0x2222222233333333ULL) return 4;

    if ((ctx.vregs[2][0] & 0xFFFFFFFFULL) != fbits(7.5f)) return 5;
    if (ctx.vregs[2][1] != 0x5555555566666666ULL) return 6;

    if ((ctx.vregs[4][0] & 0xFFFFFFFFULL) != fbits(25.0f)) return 7;
    if (ctx.vregs[4][1] != 0x7777777788888888ULL) return 8;

    if ((ctx.vregs[6][0] & 0xFFFFFFFFULL) != fbits(4.0f)) return 9;
    if (ctx.vregs[6][1] != 0x99999999AAAAAAAAULL) return 10;

    if (ctx.vregs[8][0] != dbits(12.5)) return 11;
    if (ctx.vregs[8][1] != 0xBBBBBBBBCCCCCCCCULL) return 12;

    if (ctx.vregs[10][0] != dbits(7.5)) return 13;
    if (ctx.vregs[10][1] != 0xDDDDDDDDEEEEEEEEULL) return 14;

    if (ctx.vregs[12][0] != dbits(25.0)) return 15;
    if (ctx.vregs[12][1] != 0xFFFFFFFF00000000ULL) return 16;

    if (ctx.vregs[14][0] != dbits(4.0)) return 17;
    if (ctx.vregs[14][1] != 0x1234567812345678ULL) return 18;

    if (ctx.vregs[16][0] != dbits(4.0) || ctx.vregs[16][1] != dbits(6.0)) return 19;
    if (ctx.vregs[18][0] != dbits(9.0) || ctx.vregs[18][1] != dbits(18.0)) return 20;
    if (ctx.vregs[20][0] != dbits(8.0) || ctx.vregs[20][1] != dbits(15.0)) return 21;
    if (ctx.vregs[22][0] != dbits(5.0) || ctx.vregs[22][1] != dbits(5.0)) return 22;
|})

let test_native_x86_conversions () =
  let pkg =
    mk_pkg ~seed:20261023 {|
func_native_conv:
    cvtsi2ss xmm0, edi
    cvtsi2sd xmm1, rsi
    cvttss2si r8d, xmm0
    cvttsd2si r9, xmm1
    cvtsd2ss xmm2, xmm1
    cvtss2sd xmm3, xmm0
    cvtsi2sd xmm4, dword ptr [rsp + 16]
    cvttss2si r10d, dword ptr [rsp + 24]
    ret
|}
  in
  with_temp_dir (fun tmp_dir ->
      run_custom_vm ~name:"native_conv" tmp_dir pkg {|
    vanguard_threaded_vm::VMContext ctx = {};
    ctx.init();
    auto fbits = [](float f) { return static_cast<uint64_t>(std::bit_cast<uint32_t>(f)); };
    auto dbits = [](double d) { return std::bit_cast<uint64_t>(d); };

    ctx.set_rdi(42ULL);
    ctx.set_rsi(static_cast<uint64_t>(-100LL));

    alignas(16) uint8_t stack_mem[64] = {};
    *reinterpret_cast<int32_t*>(&stack_mem[16]) = -5;
    *reinterpret_cast<float*>(&stack_mem[24]) = 12.5f;
    ctx.set_reg(vanguard_threaded_vm::REG_RSP, reinterpret_cast<uint64_t>(stack_mem));

    ctx.vregs[0][0] = 0x1111111100000000ULL;
    ctx.vregs[0][1] = 0x2222222233333333ULL;
    ctx.vregs[1][1] = 0x4444444455555555ULL;
    ctx.vregs[2][0] = 0x6666666600000000ULL;
    ctx.vregs[2][1] = 0x7777777788888888ULL;
    ctx.vregs[3][1] = 0x99999999AAAAAAAAULL;

    if (!vanguard_threaded_vm::execute_threaded(ctx, embedded_bytecode, count)) return 1;

    if ((ctx.vregs[0][0] & 0xFFFFFFFFULL) != fbits(42.0f)) return 2;
    if ((ctx.vregs[0][0] & 0xFFFFFFFF00000000ULL) != 0x1111111100000000ULL) return 3;
    if (ctx.vregs[0][1] != 0x2222222233333333ULL) return 4;

    if (ctx.vregs[1][0] != dbits(-100.0)) return 5;
    if (ctx.vregs[1][1] != 0x4444444455555555ULL) return 6;

    if ((ctx.get_reg(vanguard_threaded_vm::REG_R8) & 0xFFFFFFFFULL) != 42ULL) return 7;

    if (ctx.get_reg(vanguard_threaded_vm::REG_R9) != static_cast<uint64_t>(-100LL)) return 8;

    if ((ctx.vregs[2][0] & 0xFFFFFFFFULL) != fbits(-100.0f)) return 9;
    if ((ctx.vregs[2][0] & 0xFFFFFFFF00000000ULL) != 0x6666666600000000ULL) return 10;
    if (ctx.vregs[2][1] != 0x7777777788888888ULL) return 11;

    if (ctx.vregs[3][0] != dbits(42.0)) return 12;
    if (ctx.vregs[3][1] != 0x99999999AAAAAAAAULL) return 13;

    if (ctx.vregs[4][0] != dbits(-5.0)) return 14;

    if ((ctx.get_reg(vanguard_threaded_vm::REG_R10) & 0xFFFFFFFFULL) != 12ULL) return 15;
|})

let test_native_x86_float_comparisons () =
  let pkg =
    mk_pkg ~seed:20261024 {|
func_native_fcmp:
    mov rax, 0
    ucomiss xmm0, xmm1
    jbe .L_native_skip1
    mov rax, 1
.L_native_skip1:
    mov rbx, 0
    comiss xmm2, xmm3
    jae .L_native_skip2
    mov rbx, 1
.L_native_skip2:
    mov rcx, 0
    ucomisd xmm4, xmm5
    jne .L_native_skip3
    mov rcx, 1
.L_native_skip3:
    mov rdx, 0
    comisd xmm6, xmm7
    jnp .L_native_skip4
    mov rdx, 1
.L_native_skip4:
    ret
|}
  in
  with_temp_dir (fun tmp_dir ->
      run_custom_vm ~name:"native_fcmp" tmp_dir pkg {|
    vanguard_threaded_vm::VMContext ctx = {};
    ctx.init();
    auto fbits = [](float f) { return static_cast<uint64_t>(std::bit_cast<uint32_t>(f)); };
    auto dbits = [](double d) { return std::bit_cast<uint64_t>(d); };

    ctx.vregs[0][0] = fbits(10.0f);
    ctx.vregs[1][0] = fbits(2.5f);
    ctx.vregs[2][0] = fbits(1.0f);
    ctx.vregs[3][0] = fbits(5.0f);
    ctx.vregs[4][0] = dbits(7.5);
    ctx.vregs[5][0] = dbits(7.5);
    ctx.vregs[6][0] = dbits(std::numeric_limits<double>::quiet_NaN());
    ctx.vregs[7][0] = dbits(1.0);

    if (!vanguard_threaded_vm::execute_threaded(ctx, embedded_bytecode, count)) return 1;
    std::printf("DEBUG: zf=%d pf=%d cf=%d rax=%llu rbx=%llu rcx=%llu rdx=%llu\n", (int)ctx.zf, (int)ctx.pf, (int)ctx.cf, (unsigned long long)ctx.get_rax(), (unsigned long long)ctx.get_reg(vanguard_threaded_vm::REG_RBX), (unsigned long long)ctx.get_reg(vanguard_threaded_vm::REG_RCX), (unsigned long long)ctx.get_reg(vanguard_threaded_vm::REG_RDX));

    if (ctx.get_rax() != 1ULL) return 2;
    if (ctx.get_reg(vanguard_threaded_vm::REG_RBX) != 1ULL) return 3;
    if (ctx.get_reg(vanguard_threaded_vm::REG_RCX) != 1ULL) return 4;
    if (ctx.get_reg(vanguard_threaded_vm::REG_RDX) != 1ULL) return 5;
|})

let test_native_x86_pand_por_pxor_pandn () =
  let pkg =
    mk_pkg ~seed:20261025 {|
func_native_xmm_bitwise:
    pand xmm0, xmm1
    por xmm2, xmm3
    pxor xmm4, xmm5
    pxor xmm6, xmm6
    pandn xmm7, xmm8
    vpandn xmm9, xmm7, xmm8
    ret
|}
  in
  with_temp_dir (fun tmp_dir ->
      run_custom_vm ~name:"native_xmm_bitwise" tmp_dir pkg {|
    vanguard_threaded_vm::VMContext ctx = {};
    ctx.init();

    ctx.vregs[0][0] = 0xAAAAAAAAAAAAAAAAULL; ctx.vregs[0][1] = 0xCCCCCCCCCCCCCCCCULL;
    ctx.vregs[1][0] = 0xFFFFFFFF00000000ULL; ctx.vregs[1][1] = 0x123456789ABCDEF0ULL;

    ctx.vregs[2][0] = 0xAAAAAAAAAAAAAAAAULL; ctx.vregs[2][1] = 0x1111111111111111ULL;
    ctx.vregs[3][0] = 0x5555555555555555ULL; ctx.vregs[3][1] = 0x2222222222222222ULL;

    ctx.vregs[4][0] = 0xAAAAAAAAAAAAAAAAULL; ctx.vregs[4][1] = 0x123456789ABCDEF0ULL;
    ctx.vregs[5][0] = 0xFFFFFFFFFFFFFFFFULL; ctx.vregs[5][1] = 0x123456789ABCDEF0ULL;

    ctx.vregs[6][0] = 0xDEADBEEFCAFEBA00ULL; ctx.vregs[6][1] = 0xFEEDFACEDEADBEEFULL;

    ctx.vregs[7][0] = 0x00000000FFFFFFFFULL; ctx.vregs[7][1] = 0x1111111111111111ULL;
    ctx.vregs[8][0] = 0xFFFFFFFFFFFFFFFFULL; ctx.vregs[8][1] = 0xFFFFFFFFFFFFFFFFULL;

    ctx.vregs[9][2] = 0xDEADBEEFCAFEBA00ULL; ctx.vregs[9][3] = 0xDEADBEEFCAFEBA00ULL;

    if (!vanguard_threaded_vm::execute_threaded(ctx, embedded_bytecode, count)) return 1;

    if (ctx.vregs[0][0] != 0xAAAAAAAA00000000ULL) return 2;
    if (ctx.vregs[0][1] != (0xCCCCCCCCCCCCCCCCULL & 0x123456789ABCDEF0ULL)) return 3;

    if (ctx.vregs[2][0] != 0xFFFFFFFFFFFFFFFFULL) return 4;
    if (ctx.vregs[2][1] != 0x3333333333333333ULL) return 5;

    if (ctx.vregs[4][0] != 0x5555555555555555ULL) return 6;
    if (ctx.vregs[4][1] != 0ULL) return 7;

    if (ctx.vregs[6][0] != 0ULL || ctx.vregs[6][1] != 0ULL) return 8;

    if (ctx.vregs[7][0] != 0xFFFFFFFF00000000ULL) return 9;
    if (ctx.vregs[7][1] != 0xEEEEEEEEEEEEEEEEULL) return 10;

    if (ctx.vregs[9][0] != 0x00000000FFFFFFFFULL) return 11;
    if (ctx.vregs[9][1] != 0x1111111111111111ULL) return 12;
    if (ctx.vregs[9][2] != 0ULL || ctx.vregs[9][3] != 0ULL) return 13;
|})

let test_native_x86_movmskps_movmskpd () =
  let pkg =
    mk_pkg ~seed:20261020 {|
func_native_movmsk:
    movmskps eax, xmm1
    vmovmskps ebx, ymm2
    movmskpd ecx, xmm3
    vmovmskpd edx, ymm4
    ret
|}
  in
  with_temp_dir (fun tmp_dir ->
      run_custom_vm ~name:"native_movmsk" tmp_dir pkg {|
    vanguard_threaded_vm::VMContext ctx = {};
    ctx.init();

    /* xmm1: 32-bit lanes 0 and 1 signed -> movmskps = 0b0011 */
    ctx.vregs[1][0] = 0x8000000080000000ULL; ctx.vregs[1][1] = 0ULL;

    /* ymm2: 32-bit lanes 1 and 5 signed -> vmovmskps = 0b100010 */
    ctx.vregs[2][0] = 0x8000000000000000ULL; ctx.vregs[2][1] = 0ULL;
    ctx.vregs[2][2] = 0x8000000000000000ULL; ctx.vregs[2][3] = 0ULL;

    /* xmm3: 64-bit lane 0 signed -> movmskpd = 0b01 */
    ctx.vregs[3][0] = 0x8000000000000000ULL; ctx.vregs[3][1] = 0ULL;

    /* ymm4: 64-bit lanes 0 and 2 signed -> vmovmskpd = 0b0101 */
    ctx.vregs[4][0] = 0x8000000000000000ULL; ctx.vregs[4][1] = 0ULL;
    ctx.vregs[4][2] = 0x8000000000000000ULL; ctx.vregs[4][3] = 0ULL;

    if (!vanguard_threaded_vm::execute_threaded(ctx, embedded_bytecode, count)) return 1;
    if (ctx.get_rax() != 0x3ULL) return 2;
    if (ctx.get_reg(vanguard_threaded_vm::REG_RBX) != 0x22ULL) return 3;
    if (ctx.get_reg(vanguard_threaded_vm::REG_RCX) != 0x1ULL) return 4;
    if (ctx.get_reg(vanguard_threaded_vm::REG_RDX) != 0x5ULL) return 5;
|})

(* PTEST and VPTEST set ZF when (SRC1 AND SRC2) is zero and CF when
   (SRC2 ANDNOT SRC1) is zero, and leave every other flag alone.  The
   expected values come from a real x86-64 machine. *)
let test_native_x86_ptest () =
  let pkg_128 =
    mk_pkg ~seed:20261022 {|
func_native_ptest:
    ptest xmm1, xmm2
    ret
|}
  in
  let pkg_256 =
    mk_pkg ~seed:20261023 {|
func_native_vptest:
    vptest ymm1, ymm2
    ret
|}
  in
  with_temp_dir (fun tmp_dir ->
      run_custom_vm ~name:"native_ptest" tmp_dir pkg_128 {|
    vanguard_threaded_vm::VMContext ctx = {};
    ctx.init();

    /* SRC1 = 0xF0, SRC2 = 0x0F: the AND is zero (ZF = 1) and SRC2 has a bit
       SRC1 lacks (CF = 0). */
    ctx.vregs[1][0] = 0x00000000000000F0ULL; ctx.vregs[1][1] = 0ULL;
    ctx.vregs[2][0] = 0x000000000000000FULL; ctx.vregs[2][1] = 0ULL;
    ctx.sf = true;

    if (!vanguard_threaded_vm::execute_threaded(ctx, embedded_bytecode, count)) return 1;

    if (!ctx.zf) return 2;
    if (ctx.cf) return 3;
    if (!ctx.sf) return 4;
|};
      run_custom_vm ~name:"native_vptest" tmp_dir pkg_256 {|
    vanguard_threaded_vm::VMContext ctx = {};
    ctx.init();

    /* SRC1 = all ones, SRC2 = 0x0F per lane: the AND is not zero (ZF = 0)
       and SRC2 has no bit SRC1 lacks (CF = 1). */
    ctx.vregs[1][0] = 0xFFFFFFFFFFFFFFFFULL; ctx.vregs[1][1] = 0xFFFFFFFFFFFFFFFFULL;
    ctx.vregs[1][2] = 0ULL; ctx.vregs[1][3] = 0ULL;
    ctx.vregs[2][0] = 0x000000000000000FULL; ctx.vregs[2][1] = 0x000000000000000FULL;
    ctx.vregs[2][2] = 0ULL; ctx.vregs[2][3] = 0ULL;

    if (!vanguard_threaded_vm::execute_threaded(ctx, embedded_bytecode, count)) return 1;

    if (ctx.zf) return 2;
    if (!ctx.cf) return 3;
|})

let test_native_x86_unpck_fp () =
  let pkg =
    mk_pkg ~seed:20261021 {|
func_native_unpck:
    unpcklps xmm1, xmm2
    unpckhps xmm3, xmm4
    unpcklpd xmm5, xmm6
    unpckhpd xmm7, xmm8
    vunpcklps ymm9, ymm1, ymm2
    ret
|}
  in
  with_temp_dir (fun tmp_dir ->
      run_custom_vm ~name:"native_unpck" tmp_dir pkg {|
    vanguard_threaded_vm::VMContext ctx = {};
    ctx.init();

    ctx.vregs[1][0] = 0x2222222211111111ULL; ctx.vregs[1][1] = 0x4444444433333333ULL;
    ctx.vregs[1][2] = 0xAAAAAAAABBBBBBBBULL; ctx.vregs[1][3] = 0ULL;
    ctx.vregs[2][0] = 0x6666666655555555ULL; ctx.vregs[2][1] = 0x8888888877777777ULL;
    ctx.vregs[2][2] = 0xDDDDDDDDCCCCCCCCULL; ctx.vregs[2][3] = 0ULL;
    ctx.vregs[3][0] = 0x2222222211111111ULL; ctx.vregs[3][1] = 0x4444444433333333ULL;
    ctx.vregs[4][0] = 0x6666666655555555ULL; ctx.vregs[4][1] = 0x8888888877777777ULL;
    ctx.vregs[5][0] = 0x2222222211111111ULL; ctx.vregs[5][1] = 0x4444444433333333ULL;
    ctx.vregs[6][0] = 0x6666666655555555ULL; ctx.vregs[6][1] = 0x8888888877777777ULL;
    ctx.vregs[7][0] = 0x2222222211111111ULL; ctx.vregs[7][1] = 0x4444444433333333ULL;
    ctx.vregs[8][0] = 0x6666666655555555ULL; ctx.vregs[8][1] = 0x8888888877777777ULL;

    if (!vanguard_threaded_vm::execute_threaded(ctx, embedded_bytecode, count)) return 1;

    if (ctx.vregs[1][0] != 0x5555555511111111ULL) return 2;
    if (ctx.vregs[1][1] != 0x6666666622222222ULL) return 3;
    if (ctx.vregs[3][0] != 0x7777777733333333ULL) return 4;
    if (ctx.vregs[3][1] != 0x8888888844444444ULL) return 5;
    if (ctx.vregs[5][0] != 0x2222222211111111ULL) return 6;
    if (ctx.vregs[5][1] != 0x6666666655555555ULL) return 7;
    if (ctx.vregs[7][0] != 0x4444444433333333ULL) return 8;
    if (ctx.vregs[7][1] != 0x8888888877777777ULL) return 9;
    if (ctx.vregs[9][0] != 0x5555555511111111ULL) return 10;
    if (ctx.vregs[9][1] != 0x6666666655555555ULL) return 11;
    if (ctx.vregs[9][2] != 0xCCCCCCCCBBBBBBBBULL) return 12;
    if (ctx.vregs[9][3] != 0xDDDDDDDDAAAAAAAAULL) return 13;
|})


let test_native_x86_aes_ni () =
  let pkg =
    mk_pkg ~seed:20261026 {|
func_native_aes:
    aesenc xmm0, xmm1
    aesimc xmm2, xmm1
    aeskeygenassist xmm3, xmm4, 0x01
    vaesenc xmm5, xmm0, xmm1
    ret
|}
  in
  with_temp_dir (fun tmp_dir ->
      run_custom_vm ~name:"native_aes" tmp_dir pkg {|
    vanguard_threaded_vm::VMContext ctx = {};
    ctx.init();

    ctx.vregs[0][0] = 0x2BE2F4A0BEE33D19ULL; ctx.vregs[0][1] = 0x0848F8E92A8DC69AULL;
    ctx.vregs[1][0] = 0xB12C548817FEFAA0ULL; ctx.vregs[1][1] = 0x05766C2A3939A323ULL;
    ctx.vregs[4][0] = 0xA6D2AE2816157E2BULL; ctx.vregs[4][1] = 0x3C4FCF098815F7ABULL;
    ctx.vregs[5][2] = 0xDEADBEEFCAFEBA00ULL; ctx.vregs[5][3] = 0xDEADBEEFCAFEBA00ULL;

    if (!vanguard_threaded_vm::execute_threaded(ctx, embedded_bytecode, count)) return 1;

    if (ctx.vregs[0][0] != 0x2B359F68F27F9CA4ULL) return 2;
    if (ctx.vregs[0][1] != 0x49506A0243EA5B6BULL) return 3;

    if (ctx.vregs[2][0] != 0x05D462F2A708372BULL) return 4;
    if (ctx.vregs[2][1] != 0x627D614BBFBD3EBCULL) return 5;

    if (ctx.vregs[3][0] != 0x3424B5E524B5E434ULL) return 6;
    if (ctx.vregs[3][1] != 0x01EB848BEB848A01ULL) return 7;

    if (ctx.vregs[5][2] != 0ULL || ctx.vregs[5][3] != 0ULL) return 8;
|})

let test_native_x86_aes_ni_fips197_full_cycle () =
  let pkg =
    mk_pkg ~seed:20261027 {|
func_native_aes_full_cycle:
    pxor xmm0, xmm1
    aesenc xmm0, xmm2
    aesenc xmm0, xmm3
    aesenc xmm0, xmm4
    aesenc xmm0, xmm5
    aesenc xmm0, xmm6
    aesenc xmm0, xmm7
    aesenc xmm0, xmm8
    aesenc xmm0, xmm9
    aesenc xmm0, xmm10
    aesenclast xmm0, xmm11
    movaps xmm12, xmm0
    aesimc xmm2, xmm2
    aesimc xmm3, xmm3
    aesimc xmm4, xmm4
    aesimc xmm5, xmm5
    aesimc xmm6, xmm6
    aesimc xmm7, xmm7
    aesimc xmm8, xmm8
    aesimc xmm9, xmm9
    aesimc xmm10, xmm10
    pxor xmm12, xmm11
    aesdec xmm12, xmm10
    aesdec xmm12, xmm9
    aesdec xmm12, xmm8
    aesdec xmm12, xmm7
    aesdec xmm12, xmm6
    aesdec xmm12, xmm5
    aesdec xmm12, xmm4
    aesdec xmm12, xmm3
    aesdec xmm12, xmm2
    aesdeclast xmm12, xmm1
    ret
|}
  in
  with_temp_dir (fun tmp_dir ->
      run_custom_vm ~name:"native_aes_full_cycle" tmp_dir pkg {|
    vanguard_threaded_vm::VMContext ctx = {};
    ctx.init();

    /* Plaintext */
    ctx.vregs[0][0] = 0x8D305A88A8F64332ULL; ctx.vregs[0][1] = 0x340737E0A2983131ULL;
    /* Round keys 0..10 */
    ctx.vregs[1][0] = 0xA6D2AE2816157E2BULL; ctx.vregs[1][1] = 0x3C4FCF098815F7ABULL;
    ctx.vregs[2][0] = 0xB12C548817FEFAA0ULL; ctx.vregs[2][1] = 0x05766C2A3939A323ULL;
    ctx.vregs[3][0] = 0x43B9967AF295C2F2ULL; ctx.vregs[3][1] = 0x7FF659737A803559ULL;
    ctx.vregs[4][0] = 0x3EFE16477D47803DULL; ctx.vregs[4][1] = 0x3B887A6D447E231EULL;
    ctx.vregs[5][0] = 0x7F5B52A841A544EFULL; ctx.vregs[5][1] = 0x00AD0BDB3B2571B6ULL;
    ctx.vregs[6][0] = 0x879D837CF8C6D1D4ULL; ctx.vregs[6][1] = 0xBC15F911BCB8F2CAULL;
    ctx.vregs[7][0] = 0xFD3E0B117AA3886DULL; ctx.vregs[7][1] = 0xFD9300CA4186F9DBULL;
    ctx.vregs[8][0] = 0xF3C95F5F0EF7544EULL; ctx.vregs[8][1] = 0x4FDCA64EB24FA684ULL;
    ctx.vregs[9][0] = 0xD2BA8DB52173D2EAULL; ctx.vregs[9][1] = 0x2F298D7F60F52B31ULL;
    ctx.vregs[10][0] = 0x21DCFA19F36677ACULL; ctx.vregs[10][1] = 0x6E005C574129D128ULL;
    ctx.vregs[11][0] = 0x8925EEC9A8F914D0ULL; ctx.vregs[11][1] = 0xA60C63B6C80C3FE1ULL;

    if (!vanguard_threaded_vm::execute_threaded(ctx, embedded_bytecode, count)) return 1;

    /* Encrypted ciphertext must match NIST FIPS-197 */
    if (ctx.vregs[0][0] != 0xFB09DC021D842539ULL) return 2;
    if (ctx.vregs[0][1] != 0x320B6A19978511DCULL) return 3;

    /* Decrypted plaintext must match original plaintext */
    if (ctx.vregs[12][0] != 0x8D305A88A8F64332ULL) return 4;
    if (ctx.vregs[12][1] != 0x340737E0A2983131ULL) return 5;

    /* Decryption keys */
    if (ctx.vregs[2][0] != 0x05D462F2A708372BULL) return 6;
    if (ctx.vregs[2][1] != 0x627D614BBFBD3EBCULL) return 7;
    if (ctx.vregs[10][0] != 0xFEEA1913635A7B0CULL) return 8;
    if (ctx.vregs[10][1] != 0xB4FB4C66908839B0ULL) return 9;
|})

let test_native_x86_shufps_shufpd () =
  let pkg =
    mk_pkg ~seed:20261028 {|
func_native_shuf:
    vshufps xmm4, xmm0, xmm1, 0xD8
    vshufpd xmm5, xmm2, xmm3, 0x01
    shufps xmm0, xmm1, 0xD8
    shufpd xmm2, xmm3, 0x01
    vshufps ymm7, ymm8, ymm9, 0xD8
    vshufpd ymm10, ymm11, ymm12, 0x05
    ret
|}
  in
  with_temp_dir (fun tmp_dir ->
      run_custom_vm ~name:"native_shuf" tmp_dir pkg {|
    vanguard_threaded_vm::VMContext ctx = {};
    ctx.init();

    /* xmm0, xmm1: [1, 2, 3, 4] and [5, 6, 7, 8] */
    ctx.vregs[0][0] = 0x0000000200000001ULL; ctx.vregs[0][1] = 0x0000000400000003ULL;
    ctx.vregs[1][0] = 0x0000000600000005ULL; ctx.vregs[1][1] = 0x0000000800000007ULL;

    /* xmm2, xmm3: [0x1111..., 0x2222...] and [0x3333..., 0x4444...] */
    ctx.vregs[2][0] = 0x1111111111111111ULL; ctx.vregs[2][1] = 0x2222222222222222ULL;
    ctx.vregs[3][0] = 0x3333333333333333ULL; ctx.vregs[3][1] = 0x4444444444444444ULL;

    /* xmm4, xmm5: upper lanes pre-filled to verify VEX-128 zeroing */
    ctx.vregs[4][2] = 0xDEADBEEFCAFEBA00ULL; ctx.vregs[4][3] = 0xDEADBEEFCAFEBA00ULL;
    ctx.vregs[5][2] = 0xDEADBEEFCAFEBA00ULL; ctx.vregs[5][3] = 0xDEADBEEFCAFEBA00ULL;

    /* ymm8, ymm9: 256-bit vshufps */
    ctx.vregs[8][0] = 0x0000000200000001ULL; ctx.vregs[8][1] = 0x0000000400000003ULL;
    ctx.vregs[8][2] = 0x0000000B0000000AULL; ctx.vregs[8][3] = 0x0000000D0000000CULL;

    ctx.vregs[9][0] = 0x0000000600000005ULL; ctx.vregs[9][1] = 0x0000000800000007ULL;
    ctx.vregs[9][2] = 0x0000000F0000000EULL; ctx.vregs[9][3] = 0x0000001100000010ULL;

    /* ymm11, ymm12: 256-bit vshufpd */
    ctx.vregs[11][0] = 0x1111111111111111ULL; ctx.vregs[11][1] = 0x2222222222222222ULL;
    ctx.vregs[11][2] = 0x5555555555555555ULL; ctx.vregs[11][3] = 0x6666666666666666ULL;

    ctx.vregs[12][0] = 0x3333333333333333ULL; ctx.vregs[12][1] = 0x4444444444444444ULL;
    ctx.vregs[12][2] = 0x7777777777777777ULL; ctx.vregs[12][3] = 0x8888888888888888ULL;

    if (!vanguard_threaded_vm::execute_threaded(ctx, embedded_bytecode, count)) return 1;

    /* shufps xmm0, xmm1, 0xD8 -> [1, 3, 6, 8] */
    if (ctx.vregs[0][0] != 0x0000000300000001ULL) return 2;
    if (ctx.vregs[0][1] != 0x0000000800000006ULL) return 3;

    /* shufpd xmm2, xmm3, 0x01 -> [0x2222..., 0x3333...] */
    if (ctx.vregs[2][0] != 0x2222222222222222ULL) return 4;
    if (ctx.vregs[2][1] != 0x3333333333333333ULL) return 5;

    /* vshufps zeroing of upper lanes */
    if (ctx.vregs[4][2] != 0ULL || ctx.vregs[4][3] != 0ULL) return 6;

    /* vshufpd zeroing of upper lanes */
    if (ctx.vregs[5][0] != 0x2222222222222222ULL) return 7;
    if (ctx.vregs[5][1] != 0x3333333333333333ULL) return 8;
    if (ctx.vregs[5][2] != 0ULL || ctx.vregs[5][3] != 0ULL) return 9;

    /* 256-bit vshufps */
    if (ctx.vregs[7][0] != 0x0000000300000001ULL) return 10;
    if (ctx.vregs[7][1] != 0x0000000800000006ULL) return 11;
    if (ctx.vregs[7][2] != 0x0000000C0000000AULL) return 12;
    if (ctx.vregs[7][3] != 0x000000110000000FULL) return 13;

    /* 256-bit vshufpd */
    if (ctx.vregs[10][0] != 0x2222222222222222ULL) return 14;
    if (ctx.vregs[10][1] != 0x3333333333333333ULL) return 15;
    if (ctx.vregs[10][2] != 0x6666666666666666ULL) return 16;
    if (ctx.vregs[10][3] != 0x7777777777777777ULL) return 17;
|})

let test_native_x86_packed_conversions () =
  let pkg =
    mk_pkg ~seed:20261029 {|
func_native_packed_conv:
    cvtps2pd xmm0, xmm1
    cvtpd2ps xmm2, xmm3
    cvtdq2ps xmm4, xmm5
    cvtps2dq xmm6, xmm7
    cvttps2dq xmm8, xmm7
    cvtdq2pd xmm9, xmm10
    cvtpd2dq xmm11, xmm12
    cvttpd2dq xmm13, xmm12
    vcvtps2pd ymm14, xmm1
    ret
|}
  in
  with_temp_dir (fun tmp_dir ->
      run_custom_vm ~name:"native_packed_conv" tmp_dir pkg {|
    vanguard_threaded_vm::VMContext ctx = {};
    ctx.init();

    /* xmm1: floats 1.5, -2.5 */
    ctx.vregs[1][0] = 0xC02000003FC00000ULL; ctx.vregs[1][1] = 0ULL;
    /* xmm3: doubles 3.25, -4.75 */
    ctx.vregs[3][0] = 0x400A000000000000ULL; ctx.vregs[3][1] = 0xC013000000000000ULL;
    /* xmm5: ints 10, -20, 1000, -50000 */
    ctx.vregs[5][0] = 0xFFFFFFEC0000000AULL; ctx.vregs[5][1] = 0xFFFF3CB0000003E8ULL;
    /* xmm7: floats 1.2, 1.8, -1.8, -1.2 */
    ctx.vregs[7][0] = 0x3FE666663F99999AULL; ctx.vregs[7][1] = 0xBF99999ABFE66666ULL;
    /* xmm10: ints 42, -99 */
    ctx.vregs[10][0] = 0xFFFFFF9D0000002AULL; ctx.vregs[10][1] = 0ULL;
    /* xmm12: doubles 42.7, -99.8 */
    ctx.vregs[12][0] = 0x404559999999999AULL; ctx.vregs[12][1] = 0xC058F33333333333ULL;

    if (!vanguard_threaded_vm::execute_threaded(ctx, embedded_bytecode, count)) return 1;

    /* cvtps2pd */
    if (ctx.vregs[0][0] != 0x3FF8000000000000ULL) return 2;
    if (ctx.vregs[0][1] != 0xC004000000000000ULL) return 3;

    /* cvtpd2ps (upper 64 bits zeroed) */
    if (ctx.vregs[2][0] != 0xC098000040500000ULL) return 4;
    if (ctx.vregs[2][1] != 0ULL) return 5;

    /* cvtdq2ps */
    if (ctx.vregs[4][0] != 0xC1A0000041200000ULL) return 6;
    if (ctx.vregs[4][1] != 0xC7435000447A0000ULL) return 7;

    /* cvtps2dq (round nearest even: [1, 2, -2, -1]) */
    if (ctx.vregs[6][0] != 0x0000000200000001ULL) return 8;
    if ((ctx.vregs[6][1] & 0xFFFFFFFF00000000ULL) != 0xFFFFFFFF00000000ULL) return 9;

    /* cvttps2dq (truncate: [1, 1, -1, -1]) */
    if (ctx.vregs[8][0] != 0x0000000100000001ULL) return 10;
    if ((ctx.vregs[8][1] & 0xFFFFFFFF00000000ULL) != 0xFFFFFFFF00000000ULL) return 11;

    /* cvtdq2pd */
    if (ctx.vregs[9][0] != 0x4045000000000000ULL) return 12;
    if (ctx.vregs[9][1] != 0xC058C00000000000ULL) return 13;

    /* cvtpd2dq (upper 64 bits zeroed) */
    if ((ctx.vregs[11][0] & 0xFFFFFFFFULL) != 43ULL) return 14;
    if (ctx.vregs[11][1] != 0ULL) return 15;

    /* cvttpd2dq (upper 64 bits zeroed) */
    if ((ctx.vregs[13][0] & 0xFFFFFFFFULL) != 42ULL) return 16;
    if (ctx.vregs[13][1] != 0ULL) return 17;

    /* 256-bit vcvtps2pd */
    if (ctx.vregs[14][0] != 0x3FF8000000000000ULL) return 18;
    if (ctx.vregs[14][1] != 0xC004000000000000ULL) return 19;
|})

let test_native_x86_movlhps_movhlps_movlps_movhps () =
  let pkg =
    mk_pkg ~seed:20261030 {|
func_native_subvec:
    vmovlhps xmm4, xmm0, xmm1
    vmovhlps xmm5, xmm2, xmm3
    movlhps xmm0, xmm1
    movhlps xmm2, xmm3
    movlps xmm6, qword ptr [rsp + 16]
    movhps xmm7, qword ptr [rsp + 16]
    vmovlps xmm8, xmm0, qword ptr [rsp + 16]
    vmovhps xmm9, xmm0, qword ptr [rsp + 16]
    ret
|}
  in
  with_temp_dir (fun tmp_dir ->
      run_custom_vm ~name:"native_subvec" tmp_dir pkg {|
    vanguard_threaded_vm::VMContext ctx = {};
    ctx.init();

    /* rsp + 16 = 0x1234567890ABCDEF */
    uint64_t vsp = ctx.get_vsp();
    ctx.write_mem_u64(vsp + 16, 0x1234567890ABCDEFULL);

    ctx.vregs[0][0] = 0x1111111111111111ULL; ctx.vregs[0][1] = 0x2222222222222222ULL;
    ctx.vregs[1][0] = 0x3333333333333333ULL; ctx.vregs[1][1] = 0x4444444444444444ULL;
    ctx.vregs[2][0] = 0x5555555555555555ULL; ctx.vregs[2][1] = 0x6666666666666666ULL;
    ctx.vregs[3][0] = 0x7777777777777777ULL; ctx.vregs[3][1] = 0x8888888888888888ULL;

    ctx.vregs[4][2] = 0xDEADBEEFCAFEBA00ULL; ctx.vregs[4][3] = 0xDEADBEEFCAFEBA00ULL;
    ctx.vregs[5][2] = 0xDEADBEEFCAFEBA00ULL; ctx.vregs[5][3] = 0xDEADBEEFCAFEBA00ULL;

    ctx.vregs[6][0] = 0xAAAAAAAAAAAAAAAAULL; ctx.vregs[6][1] = 0xBBBBBBBBBBBBBBBBULL;
    ctx.vregs[7][0] = 0xAAAAAAAAAAAAAAAAULL; ctx.vregs[7][1] = 0xBBBBBBBBBBBBBBBBULL;

    if (!vanguard_threaded_vm::execute_threaded(ctx, embedded_bytecode, count)) return 1;

    /* movlhps xmm0, xmm1 */
    if (ctx.vregs[0][0] != 0x1111111111111111ULL) return 2;
    if (ctx.vregs[0][1] != 0x3333333333333333ULL) return 3;

    /* movhlps xmm2, xmm3 */
    if (ctx.vregs[2][0] != 0x8888888888888888ULL) return 4;
    if (ctx.vregs[2][1] != 0x6666666666666666ULL) return 5;

    /* vmovlhps xmm4 */
    if (ctx.vregs[4][0] != 0x1111111111111111ULL) return 6;
    if (ctx.vregs[4][1] != 0x3333333333333333ULL) return 7;
    if (ctx.vregs[4][2] != 0ULL || ctx.vregs[4][3] != 0ULL) return 8;

    /* vmovhlps xmm5 */
    if (ctx.vregs[5][0] != 0x8888888888888888ULL) return 9;
    if (ctx.vregs[5][1] != 0x6666666666666666ULL) return 10;
    if (ctx.vregs[5][2] != 0ULL || ctx.vregs[5][3] != 0ULL) return 11;

    /* movlps xmm6, m64 */
    if (ctx.vregs[6][0] != 0x1234567890ABCDEFULL) return 12;
    if (ctx.vregs[6][1] != 0xBBBBBBBBBBBBBBBBULL) return 13;

    /* movhps xmm7, m64 */
    if (ctx.vregs[7][0] != 0xAAAAAAAAAAAAAAAAULL) return 14;
    if (ctx.vregs[7][1] != 0x1234567890ABCDEFULL) return 15;

    /* vmovlps xmm8 */
    if (ctx.vregs[8][0] != 0x1234567890ABCDEFULL) return 16;
    if (ctx.vregs[8][1] != 0x3333333333333333ULL) return 17;
    if (ctx.vregs[8][2] != 0ULL) return 18;

    /* vmovhps xmm9 */
    if (ctx.vregs[9][0] != 0x1111111111111111ULL) return 19;
    if (ctx.vregs[9][1] != 0x1234567890ABCDEFULL) return 20;
    if (ctx.vregs[9][2] != 0ULL) return 21;
|})

let tests = [
  Alcotest.test_case "native_div_idiv_with_remainder" `Slow test_native_div_idiv_with_remainder;
  Alcotest.test_case "native_b32_subregister_semantics" `Slow test_native_b32_subregister_semantics;
  Alcotest.test_case "native_b16_word_memory" `Slow test_native_b16_word_memory;
  Alcotest.test_case "native_movzx_zero_extend" `Slow test_native_movzx_zero_extend;
  Alcotest.test_case "native_signed_loads" `Slow test_native_signed_loads;
  Alcotest.test_case "e2e_uint16_pipeline" `Slow test_e2e_uint16_pipeline;
  Alcotest.test_case "e2e_multi_function_pipeline" `Slow test_e2e_multi_function_pipeline;
  Alcotest.test_case "e2e_uint16_clang_o2_o3" `Slow test_e2e_uint16_clang_o2_o3;
  Alcotest.test_case "e2e_signed_loads_clang_o2_o3" `Slow test_e2e_signed_loads_clang_o2_o3;
  Alcotest.test_case "e2e_sub64_signed_comparisons_clang_o2_o3" `Slow test_e2e_sub64_signed_comparisons_clang_o2_o3;
  Alcotest.test_case "e2e_stack_frame_sync_clang_o2_o3" `Slow test_e2e_stack_frame_sync_clang_o2_o3;
  Alcotest.test_case "e2e_switch_jump_table_clang_o2_o3" `Slow test_e2e_switch_jump_table_clang_o2_o3;
  Alcotest.test_case "e2e_indirect_branch_clang_o2_o3" `Slow test_e2e_indirect_branch_clang_o2_o3;
  Alcotest.test_case "e2e_bit_test_and_branch_clang_o2_o3" `Slow test_e2e_bit_test_and_branch_clang_o2_o3;
  Alcotest.test_case "canonicalize_3addr_alu_unit" `Quick test_canonicalize_3addr_alu_unit;
  Alcotest.test_case "native_3addr_alu" `Slow test_native_3addr_alu;
  Alcotest.test_case "native_arm64_3addr_madd_msub_sdiv_bic" `Slow test_native_arm64_3addr_madd_msub_sdiv_bic;
  Alcotest.test_case "native_b8_b16_merge" `Slow test_native_b8_b16_merge;
  Alcotest.test_case "native_vector_fp" `Slow test_native_vector_fp;
  Alcotest.test_case "native_x86_shld_shrd_mem_and_cdq" `Slow test_native_x86_shld_shrd_mem_and_cdq;
  Alcotest.test_case "native_x86_fsgsbase" `Slow test_native_x86_fsgsbase;
  Alcotest.test_case "native_x86_sha_ni" `Slow test_native_x86_sha_ni;
  Alcotest.test_case "native_x86_pclmul_cet" `Slow test_native_x86_pclmul_cet;
  Alcotest.test_case "native_x86_cpuid" `Slow test_native_x86_cpuid;
  Alcotest.test_case "native_x86_fpu" `Slow test_native_x86_fpu;
  Alcotest.test_case "native_x86_scalar_and_vector_moves" `Slow test_native_x86_scalar_and_vector_moves;
  Alcotest.test_case "native_x86_scalar_and_packed_fp_arithmetic" `Slow test_native_x86_scalar_and_packed_fp_arithmetic;
  Alcotest.test_case "native_x86_conversions" `Slow test_native_x86_conversions;
  Alcotest.test_case "native_x86_float_comparisons" `Slow test_native_x86_float_comparisons;
  Alcotest.test_case "native_x86_pand_por_pxor_pandn" `Slow test_native_x86_pand_por_pxor_pandn;
  Alcotest.test_case "native_x86_unpck_fp" `Slow test_native_x86_unpck_fp;
  Alcotest.test_case "native_x86_ptest" `Slow test_native_x86_ptest;
  Alcotest.test_case "native_x86_aes_ni" `Slow test_native_x86_aes_ni;
  Alcotest.test_case "native_x86_aes_ni_fips197_full_cycle" `Slow test_native_x86_aes_ni_fips197_full_cycle;
  Alcotest.test_case "native_x86_shufps_shufpd" `Slow test_native_x86_shufps_shufpd;
  Alcotest.test_case "native_x86_packed_conversions" `Slow test_native_x86_packed_conversions;
  Alcotest.test_case "native_x86_movlhps_movhlps_movlps_movhps" `Slow test_native_x86_movlhps_movhlps_movlps_movhps;
]
