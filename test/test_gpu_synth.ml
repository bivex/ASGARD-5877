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

let tests = [
  ("Metal GPU Device Detection", `Quick, test_metal_device_detection);
  ("GPU MBA Parallel Synthesis (65k Threads)", `Quick, test_gpu_mba_synthesis_65k);
  ("Batch Bytecode Encryption on Metal GPU", `Quick, test_gpu_batch_bytecode_encrypt);
  ("GPU SAC Diffusion Verification (65k Vectors)", `Quick, test_gpu_sac_verification_65k);
  ("GPU Error formatting", `Quick, test_gpu_error_formatting);
]
