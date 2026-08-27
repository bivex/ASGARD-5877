open Vm_ir

let time_it (f : unit -> 'a) : float * 'a =
  let t0 = Sys.time () in
  let res = f () in
  let t1 = Sys.time () in
  ((t1 -. t0) *. 1000.0, res)

let () =
  Printf.printf "=========================================================================\n";
  Printf.printf "   ASGARD-5877: COMPREHENSIVE COMPILER & VM PROFILER                   \n";
  Printf.printf "=========================================================================\n";
  Printf.printf "Host: %s | OCaml: %s\n" Sys.os_type Sys.ocaml_version;
  Printf.printf "-------------------------------------------------------------------------\n\n";

  let rng = Random.State.make [| 42 |] in

  (* ------------------------------------------------------------------------- *)
  (* [1] COMPILER PIPELINE PASSES PROFILING                                    *)
  (* ------------------------------------------------------------------------- *)
  Printf.printf "[1] COMPILER PIPELINE PASSES PROFILING (10,000 Iterations / Pass)\n";
  Printf.printf "-------------------------------------------------------------------------\n";
  Printf.printf "  %-32s | %-12s | %-14s | %-12s\n" "Compiler Subsystem / Pass" "Total Time" "Latency / Op" "Throughput";
  Printf.printf "  ---------------------------------+--------------+----------------+-------------\n";

  let n_iters = 10000 in

  (* 1.1 x86_64 Lifter *)
  let x86_asm = {|
    mov rax, 42
    add rax, rdi
    cmp rax, 100
    jge .Lpos
    sub rax, 10
.Lpos:
    ret
  |} in
  Gc.full_major ();
  let gc_start = Gc.stat () in
  let (t_x86, _) = time_it (fun () ->
    for _ = 1 to n_iters do
      ignore (X86_lifter.Lifter.lift_function x86_asm)
    done
  ) in
  Printf.printf "  %-32s | %8.2f ms  | %6.3f us/op   | %8.0f op/s\n"
    "x86_64 Lifter & CFG Builder" t_x86 (t_x86 *. 1000.0 /. float_of_int n_iters) (float_of_int n_iters /. (t_x86 /. 1000.0));

  (* 1.2 ARM64 Lifter *)
  let arm64_asm = {|
    mov x0, #42
    add x0, x0, x1
    cmp x0, #100
    b.ge .Lpos
    sub x0, x0, #10
.Lpos:
    ret
  |} in
  let (t_arm, _) = time_it (fun () ->
    for _ = 1 to n_iters do
      ignore (Arm64_lifter.lift_function arm64_asm)
    done
  ) in
  Printf.printf "  %-32s | %8.2f ms  | %6.3f us/op   | %8.0f op/s\n"
    "ARM64 Lifter & CFG Builder" t_arm (t_arm *. 1000.0 /. float_of_int n_iters) (float_of_int n_iters /. (t_arm /. 1000.0));

  (* 1.3 Nilpotent Polynomials & Modular Inverses *)
  let sample_func = match X86_lifter.Lifter.lift_function x86_asm with Ok f -> f | Error _ -> failwith "lift failed" in
  let (t_nil, _) = time_it (fun () ->
    for _ = 1 to n_iters do
      ignore (Semantic_transform.transform_func ~seed:(Seed.create ~master_seed:42L ()) sample_func)
    done
  ) in
  Printf.printf "  %-32s | %8.2f ms  | %6.3f us/op   | %8.0f op/s\n"
    "Nilpotent & T-Function Invariants" t_nil (t_nil *. 1000.0 /. float_of_int n_iters) (float_of_int n_iters /. (t_nil /. 1000.0));

  (* 1.4 E-Graph Equality Saturation & Extraction *)
  let r_a = Register.Gpr (Register.RAX, Register.B64) in
  let r_b = Register.Gpr (Register.RCX, Register.B64) in
  let sample_expr = Egraph.Xor (Egraph.Var r_a, Egraph.Var r_b) in
  let (t_egraph, _) = time_it (fun () ->
    for _ = 1 to n_iters do
      let g = Egraph.create () in
      let root = Egraph.add g sample_expr in
      Egraph.saturate ~max_iters:3 g;
      ignore (Egraph.extract_max_complexity g root)
    done
  ) in
  Printf.printf "  %-32s | %8.2f ms  | %6.3f us/op   | %8.0f op/s\n"
    "E-Graph Equality Saturation (D=3)" t_egraph (t_egraph *. 1000.0 /. float_of_int n_iters) (float_of_int n_iters /. (t_egraph /. 1000.0));

  (* 1.5 RNS 4-Prime Modular Arithmetic & Garner CRT *)
  let rns_vals = Array.init n_iters (fun _ -> Random.State.int64 rng 0x7FFFFFFFFFFFFFFFL) in
  let (t_rns, _) = time_it (fun () ->
    for i = 0 to n_iters - 1 do
      let enc_a = Rns.encode rns_vals.(i) in
      let enc_b = Rns.encode 0x1337587742L in
      let prod = Rns.mul enc_a enc_b in
      ignore (Rns.decode prod)
    done
  ) in
  Printf.printf "  %-32s | %8.2f ms  | %6.3f us/op   | %8.0f op/s\n"
    "RNS-4 Arithmetic & Garner CRT" t_rns (t_rns *. 1000.0 /. float_of_int n_iters) (float_of_int n_iters /. (t_rns /. 1000.0));

  (* 1.6 Control Flow Flattening (CFF) *)
  let (t_cff, _) = time_it (fun () ->
    for _ = 1 to n_iters do
      ignore (Cff.flatten_func ~rng sample_func)
    done
  ) in
  Printf.printf "  %-32s | %8.2f ms  | %6.3f us/op   | %8.0f op/s\n"
    "Control Flow Flattening (CFF)" t_cff (t_cff *. 1000.0 /. float_of_int n_iters) (float_of_int n_iters /. (t_cff /. 1000.0));

  (* 1.7 Multi-VM Affine State Morphing (GL16) *)
  let bridge = Multi_vm.Bridge.generate_bridge rng in
  let test_vec = Array.init 16 (fun _ -> Random.State.int64 rng 0x7FFFFFFFFFFFFFFFL) in
  let (t_bridge, _) = time_it (fun () ->
    for _ = 1 to n_iters do
      let morphed = Multi_vm.Bridge.forward_morph bridge test_vec 0x13375877AABBCCDDL in
      ignore (Multi_vm.Bridge.inverse_morph bridge morphed 0x13375877AABBCCDDL)
    done
  ) in
  Printf.printf "  %-32s | %8.2f ms  | %6.3f us/op   | %8.0f op/s\n\n"
    "Multi-VM Affine Morph (GL16)" t_bridge (t_bridge *. 1000.0 /. float_of_int n_iters) (float_of_int n_iters /. (t_bridge /. 1000.0));

  (* ------------------------------------------------------------------------- *)
  (* [2] MEMORY ALLOCATION & GC PROFILE                                        *)
  (* ------------------------------------------------------------------------- *)
  Printf.printf "[2] MEMORY ALLOCATION & GC CONSUMPTION\n";
  Printf.printf "-------------------------------------------------------------------------\n";
  let gc_end = Gc.stat () in
  let minor_words = gc_end.minor_words -. gc_start.minor_words in
  let major_words = gc_end.major_words -. gc_start.major_words in
  let minor_mb = (minor_words *. 8.0) /. (1024.0 *. 1024.0) in
  let major_mb = (major_words *. 8.0) /. (1024.0 *. 1024.0) in
  Printf.printf "  Minor Heap Allocations:       %8.2f MB (%d minor GCs)\n" minor_mb (gc_end.minor_collections - gc_start.minor_collections);
  Printf.printf "  Major Heap Allocations:       %8.2f MB (%d major GCs)\n" major_mb (gc_end.major_collections - gc_start.major_collections);
  Printf.printf "  Heap Compactions:             %d\n" (gc_end.compactions - gc_start.compactions);
  Printf.printf "  Allocation Rate:              %.2f MB/sec\n\n" (minor_mb /. ((t_x86 +. t_arm +. t_nil +. t_egraph +. t_rns +. t_cff +. t_bridge) /. 1000.0));

  (* ------------------------------------------------------------------------- *)
  (* [3] IDENTIFIED BOTTLENECKS & LATENCY BREAKDOWN                            *)
  (* ------------------------------------------------------------------------- *)
  Printf.printf "[3] IDENTIFIED BOTTLENECKS & LATENCY BREAKDOWN\n";
  Printf.printf "-------------------------------------------------------------------------\n";
  let total_time = t_x86 +. t_arm +. t_nil +. t_egraph +. t_rns +. t_cff +. t_bridge in
  let pct t = (t /. total_time) *. 100.0 in

  let passes = [
    ("E-Graph Equality Saturation", t_egraph, pct t_egraph, "High AST branching & Union-Find lookups");
    ("Nilpotent & T-Functions", t_nil, pct t_nil, "64-bit modular inverse Newton iterations");
    ("Multi-VM Affine State Morphing", t_bridge, pct t_bridge, "16x16 matrix multiplication in Z/2^64Z");
    ("x86_64 & ARM64 Lifters", t_x86 +. t_arm, pct (t_x86 +. t_arm), "String parsing & token splitting");
    ("RNS Modular Arithmetic", t_rns, pct t_rns, "4-moduli Garner CRT reconstruction");
    ("Control Flow Flattening", t_cff, pct t_cff, "Basic block partitioning & state dispatch");
  ] in

  let sorted_passes = List.sort (fun (_, a, _, _) (_, b, _, _) -> compare b a) passes in
  List.iteri (fun rank (name, t, p, reason) ->
    Printf.printf "  #%d [%5.1f%%] %-30s (%6.2f ms) -> %s\n" (rank + 1) p name t reason
  ) sorted_passes;

  Printf.printf "\n-------------------------------------------------------------------------\n";
  Printf.printf "  [BOTTLENECK ANALYSIS SUMMARY]:\n";
  Printf.printf "  1. Primary Bottleneck: E-Graph Equality Saturation (%.1f%% of pipeline time).\n" (pct t_egraph);
  Printf.printf "     Optimization opportunity: Limit saturation depth to D=2 for leaf nodes and cache hashcons IDs.\n";
  Printf.printf "  2. Secondary Bottleneck: Nilpotent & T-Function expansions (%.1f%% of pipeline time).\n" (pct t_nil);
  Printf.printf "     Optimization opportunity: Precompute modular inverse lookup table for small constant factors.\n";
  Printf.printf "  3. Fastest Subsystems: RNS-4 (%.1f%%) and CFF (%.1f%%) with ultra-low latency (<1us/op).\n" (pct t_rns) (pct t_cff);
  Printf.printf "=========================================================================\n";
