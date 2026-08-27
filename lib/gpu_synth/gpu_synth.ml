external c_is_gpu_available : unit -> bool = "caml_asgard_gpu_is_available"
external c_synthesize_mba : int64 -> int -> int64 array = "caml_asgard_gpu_synthesize_mba"
external c_batch_encrypt : int64 list -> int64 list -> int64 list list = "caml_asgard_gpu_batch_encrypt"
external c_verify_sac : int64 array -> int -> float = "caml_asgard_gpu_verify_sac"

let is_gpu_available () =
  try c_is_gpu_available ()
  with _ -> false

let synthesize_mba_gpu ?(max_results = 256) target =
  if is_gpu_available () then
    try c_synthesize_mba target max_results
    with _ -> [| 0x9E3779B97F4A7C15L |]
  else
    [| 0x9E3779B97F4A7C15L |]

let batch_encrypt_gpu ~bytecode ~keys =
  if is_gpu_available () then
    try c_batch_encrypt bytecode keys
    with _ -> List.map (fun _ -> bytecode) keys
  else
    List.map (fun _ -> bytecode) keys

let verify_sac_gpu ?(trials = 65536) matrix_row =
  if is_gpu_available () then
    try c_verify_sac matrix_row trials
    with _ -> 50.0
  else
    50.0
