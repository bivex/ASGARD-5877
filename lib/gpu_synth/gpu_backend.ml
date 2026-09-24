type gpu_error =
  | Gpu_unavailable
  | Gpu_execution_failed of string

let string_of_error = function
  | Gpu_unavailable -> "GPU Metal device unavailable or unsupported on this platform"
  | Gpu_execution_failed msg -> "GPU Metal execution failed: " ^ msg

external c_is_gpu_available : unit -> bool = "caml_asgard_gpu_is_available"
external c_synthesize_mba : int64 -> int -> int64 array = "caml_asgard_gpu_synthesize_mba"
external c_batch_encrypt : int64 list -> int64 list -> int64 list list = "caml_asgard_gpu_batch_encrypt"
external c_verify_sac : int64 array -> int -> float = "caml_asgard_gpu_verify_sac"

let is_gpu_available () =
  try c_is_gpu_available ()
  with Failure _ | Sys_error _ -> false

let synthesize_mba_gpu ?(max_results = 256) target =
  if not (is_gpu_available ()) then
    Error Gpu_unavailable
  else
    try Ok (c_synthesize_mba target max_results)
    with
    | Failure msg -> Error (Gpu_execution_failed msg)
    | Sys_error msg -> Error (Gpu_execution_failed msg)
    | exn -> Error (Gpu_execution_failed (Printexc.to_string exn))

let batch_encrypt_gpu ~bytecode ~keys =
  if not (is_gpu_available ()) then
    Error Gpu_unavailable
  else
    try Ok (c_batch_encrypt bytecode keys)
    with
    | Failure msg -> Error (Gpu_execution_failed msg)
    | Sys_error msg -> Error (Gpu_execution_failed msg)
    | exn -> Error (Gpu_execution_failed (Printexc.to_string exn))

let verify_sac_gpu ?(trials = 65536) matrix_row =
  if not (is_gpu_available ()) then
    Error Gpu_unavailable
  else
    try Ok (c_verify_sac matrix_row trials)
    with
    | Failure msg -> Error (Gpu_execution_failed msg)
    | Sys_error msg -> Error (Gpu_execution_failed msg)
    | exn -> Error (Gpu_execution_failed (Printexc.to_string exn))
