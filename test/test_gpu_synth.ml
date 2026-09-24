open Alcotest

let test_metal_device_detection () =
  let available = Gpu_synth.is_gpu_available () in
  check bool "Metal GPU device available on Darwin ARM64" true available

let test_gpu_mba_synthesis_65k () =
  match Gpu_synth.synthesize_mba_gpu ~max_results:128 42L with
  | Ok solutions ->
      check bool "Found GPU MBA solutions" true (Array.length solutions > 0)
  | Error err ->
      fail (Gpu_synth.string_of_error err)

let test_gpu_batch_bytecode_encrypt () =
  let bytecode = [ 0x1000L; 0x2000L; 0x3000L; 0x4000L ] in
  let keys = [ 0x1111L; 0x2222L; 0x3333L; 0x4444L ] in
  match Gpu_synth.batch_encrypt_gpu ~bytecode ~keys with
  | Ok encrypted_builds ->
      check int "Encrypted 4 builds in parallel" 4 (List.length encrypted_builds);
      List.iter (fun enc ->
        check int "Each build has 4 words" 4 (List.length enc);
        check bool "Ciphertext differs from plaintext" true (enc <> bytecode)
      ) encrypted_builds
  | Error err ->
      fail (Gpu_synth.string_of_error err)

let test_gpu_sac_verification_65k () =
  let matrix_row = Array.make 16 0xD3894A8713375877L in
  matrix_row.(0) <- 0x1234567890ABCDEFL;
  match Gpu_synth.verify_sac_gpu ~trials:65536 matrix_row with
  | Ok sac ->
      check bool "SAC within bounds [20.0 .. 80.0]" true (sac >= 20.0 && sac <= 80.0)
  | Error err ->
      fail (Gpu_synth.string_of_error err)

let test_gpu_error_formatting () =
  check string "GPU unavailable error string"
    "GPU Metal device unavailable or unsupported on this platform"
    (Gpu_synth.string_of_error Gpu_synth.Gpu_unavailable);
  check string "GPU execution failure string"
    "GPU Metal execution failed: shader compilation error"
    (Gpu_synth.string_of_error (Gpu_synth.Gpu_execution_failed "shader compilation error"))

let test_gpu_mba_pool_and_lowering () =
  let rng = Random.State.make [| 2026 |] in
  let pool = Gpu_synth.Gpu_mba.create_pool ~rng () in
  check bool "GPU MBA pool size > 0" true (Gpu_synth.Gpu_mba.pool_size pool > 0);
  let dst = Vm_ir.Register.vx20 in
  let src1 = Vm_ir.Ir.Reg Vm_ir.Register.vx20 in
  let src2 = Vm_ir.Ir.Reg Vm_ir.Register.vx21 in
  let ops = [ Vm_ir.Ir.Add; Vm_ir.Ir.Sub; Vm_ir.Ir.Xor; Vm_ir.Ir.And; Vm_ir.Ir.Or; Vm_ir.Ir.Imul ] in
  List.iter (fun op ->
    let instrs = Gpu_synth.Gpu_mba.obfuscate_alu ~pool ~rng ~dst ~src1 ~src2 op in
    check bool "GPU MBA lowering produces non-empty instructions" true (List.length instrs > 0)
  ) ops

let test_gpu_substitution_matrix_invertibility () =
  let rng = Random.State.make [| 9999 |] in
  let mat = Gpu_synth.Gpu_matrix.generate ~rng () in
  check int "Matrix dimension is 16" 16 mat.dim;
  check bool "SAC diffusion is in valid range" true (mat.sac >= 30.0 && mat.sac <= 70.0);
  (* Test exact invertible roundtrip over Z_{2^64} *)
  let orig_vec = Array.init 16 (fun i -> Int64.of_int (i * 1337 + 42)) in
  let transformed = Gpu_synth.Gpu_matrix.transform_vector mat orig_vec in
  let restored = Gpu_synth.Gpu_matrix.inverse_transform_vector mat transformed in
  check bool "M * M^{-1} = Identity roundtrip" true (orig_vec = restored);
  let cpp = Gpu_synth.Gpu_matrix.emit_cpp_constants mat in
  check bool "Emits C++ forward matrix" true (String.contains cpp 'F');
  check bool "Emits C++ inverse matrix" true (String.contains cpp 'I')

let test_vm_compilation_with_gpu_mba () =
  let rng = Random.State.make [| 54321 |] in
  let asm = {|
func_gpu_test:
    mov rax, 10
    add rax, 20
    imul rax, 3
    xor rax, 0x5877
    ret
|} in
  match X86_lifter.Lifter.lift_function asm with
  | Error e -> fail e
  | Ok func ->
      let config = Native_vm.Protection_config.max_security in
      let pkg = Native_vm.Vm_emitter.compile_and_package ~rng ~config func in
      check bool "Bytecode generated" true (List.length pkg.bytecode > 0);
      check bool "C++ runtime contains GPU MBA matrix" true
        (let s = pkg.cpp_runtime_source in
         let needle = "GPU_MBA_FWD_MATRIX" in
         let len = String.length s in
         let nlen = String.length needle in
         let rec search i =
           if i + nlen > len then false
           else if String.sub s i nlen = needle then true
           else search (i + 1)
         in search 0)

let tests = [
  ("Metal GPU Device Detection", `Quick, test_metal_device_detection);
  ("GPU MBA Parallel Synthesis (65k Threads)", `Quick, test_gpu_mba_synthesis_65k);
  ("Batch Bytecode Encryption on Metal GPU", `Quick, test_gpu_batch_bytecode_encrypt);
  ("GPU SAC Diffusion Verification (65k Vectors)", `Quick, test_gpu_sac_verification_65k);
  ("GPU Error formatting", `Quick, test_gpu_error_formatting);
  ("GPU MBA Pool Creation & IR Lowering", `Quick, test_gpu_mba_pool_and_lowering);
  ("GPU MBA Substitution Matrix Invertibility & SAC", `Quick, test_gpu_substitution_matrix_invertibility);
  ("VM Compilation with GPU MBA Engine", `Quick, test_vm_compilation_with_gpu_mba);
]
