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

let tests = [
  Alcotest.test_case "native_div_idiv_with_remainder" `Slow test_native_div_idiv_with_remainder;
  Alcotest.test_case "native_b32_subregister_semantics" `Slow test_native_b32_subregister_semantics;
  Alcotest.test_case "native_b16_word_memory" `Slow test_native_b16_word_memory;
  Alcotest.test_case "native_signed_loads" `Slow test_native_signed_loads;
  Alcotest.test_case "e2e_uint16_pipeline" `Slow test_e2e_uint16_pipeline;
  Alcotest.test_case "e2e_uint16_clang_o2_o3" `Slow test_e2e_uint16_clang_o2_o3;
  Alcotest.test_case "e2e_signed_loads_clang_o2_o3" `Slow test_e2e_signed_loads_clang_o2_o3;
  Alcotest.test_case "canonicalize_3addr_alu_unit" `Quick test_canonicalize_3addr_alu_unit;
  Alcotest.test_case "native_3addr_alu" `Slow test_native_3addr_alu;
  Alcotest.test_case "native_arm64_3addr_madd_msub_sdiv_bic" `Slow test_native_arm64_3addr_madd_msub_sdiv_bic;
]
