(** bench_mba_par.ml — measures parallel MBA speedup via domainslib.
    Run with: dune exec bench/bench_mba_par.exe *)

open X86_lifter
open Native_vm
open Vm_ir

let asm_stress = {|
func_stress:
    push rbx
    push r12
    push r13
    mov rax, rdi
    mov rbx, rsi
    mov r12, rdx
    mov r13, rcx
    ; branch 1
    cmp rax, 0
    je .zero_path
    add rax, rbx
    imul rax, 3
    xor rax, 0xDEAD
    jmp .merge1
.zero_path:
    xor rax, rbx
    sub rax, 0x42
    or rax, 0xFF
.merge1:
    ; branch 2
    sub rbx, 1
    cmp rbx, 100
    jl .small_path
    imul rbx, 7
    and rbx, rax
    xor rbx, 0x1337
    jmp .merge2
.small_path:
    add rbx, rax
    xor rbx, 0xBEEF
    or  rbx, r12
.merge2:
    ; branch 3
    cmp r12, r13
    jge .big_path
    add r12, rax
    sub r12, rbx
    xor r12, 0xCAFE
    jmp .merge3
.big_path:
    imul r12, 5
    and r12, 0xFFFF
    add r12, rbx
.merge3:
    ; final combine
    add rax, rbx
    xor rax, r12
    imul rax, r13
    and rax, 0xFFFFFFFF
    pop r13
    pop r12
    pop rbx
    ret
|}

let time_it label n f =
  (* warm-up *)
  f ();
  let t0 = Unix.gettimeofday () in
  for _ = 1 to n do f () done;
  let t1 = Unix.gettimeofday () in
  let avg_ms = (t1 -. t0) *. 1000.0 /. float_of_int n in
  Printf.printf "%-45s  %5.1f ms/call  (n=%d)\n%!" label avg_ms n

let () =
  match Lifter.lift_function asm_stress with
  | Error e -> Printf.eprintf "Lift error: %s\n%!" e; exit 1
  | Ok func ->
      let n_blocks = Hashtbl.length func.Ir.cfg.blocks in
      let n_instrs = Hashtbl.fold (fun _ (b : Ir.basic_block) a ->
        a + List.length b.instrs) func.Ir.cfg.blocks 0 in
      Printf.printf "Input: %d blocks, %d instrs\n\n%!" n_blocks n_instrs;

      let make_rng () = Random.State.make [| 0x5877CAFE |] in

      (* Baseline: no MBA *)
      time_it "no MBA (baseline)"       10 (fun () ->
        ignore (Vm_emitter.compile_and_package ~rng:(make_rng ()) func));

      (* default preset: MBA Poly depth=2 *)
      let cfg_default = Protection_config.default in
      time_it "MBA poly depth=2 (default)"  5 (fun () ->
        ignore (Vm_emitter.compile_and_package ~rng:(make_rng ()) ~config:cfg_default func));

      (* max_security: MBA with GPU Metal + CFF + all features *)
      let cfg_max = Protection_config.max_security in
      time_it "MBA GPU Metal + CFF (max_security)"  3 (fun () ->
        ignore (Vm_emitter.compile_and_package ~rng:(make_rng ()) ~config:cfg_max func));

      (* Force CPU Egraph for comparison *)
      let cfg_cpu_egraph = { cfg_max with mba = { cfg_max.mba with engine = `Egraph } } in
      time_it "MBA CPU Egraph + CFF (comparison)"  3 (fun () ->
        ignore (Vm_emitter.compile_and_package ~rng:(make_rng ()) ~config:cfg_cpu_egraph func));

      Printf.printf "\nDomain count: %d\n%!" (Domain.recommended_domain_count ())

let () =
  let rng = Random.State.make [| 99 |] in
  let open Vm_ir in
  let dst = Register.vx20 in
  let src1 = Ir.Reg Register.vx20 in
  let src2 = Ir.Reg Register.vx21 in
  let n = 1000 in
  let t0 = Unix.gettimeofday () in
  for _ = 1 to n do
    ignore (Mba_engine.Egraph.obfuscate_alu ~rng ~dst ~src1 ~src2 Ir.Add)
  done;
  let t1 = Unix.gettimeofday () in
  Printf.printf "\n1 Egraph.obfuscate_alu ADD: %.2f µs avg (n=%d)\n%!"
    ((t1 -. t0) *. 1e6 /. float_of_int n) n;

  (* Measure GPU MBA lowering speed *)
  let pool = Gpu_synth.Gpu_mba.create_pool ~rng () in
  let t2 = Unix.gettimeofday () in
  for _ = 1 to n do
    ignore (Gpu_synth.Gpu_mba.obfuscate_alu ~pool ~rng ~dst ~src1 ~src2 Ir.Add)
  done;
  let t3 = Unix.gettimeofday () in
  Printf.printf "1 GPU_MBA.obfuscate_alu ADD: %.2f µs avg (n=%d, pool_size=%d, gpu_backed=%b)\n%!"
    ((t3 -. t2) *. 1e6 /. float_of_int n) n (Gpu_synth.Gpu_mba.pool_size pool) (Gpu_synth.Gpu_mba.is_gpu_backed pool);
  Printf.printf "GPU Speedup per ALU op: %.1fx\n%!"
    (((t1 -. t0) *. 1e6 /. float_of_int n) /. ((t3 -. t2) *. 1e6 /. float_of_int n))
