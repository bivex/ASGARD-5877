type gpu_error =
  | Gpu_unavailable
  | Gpu_execution_failed of string

val string_of_error : gpu_error -> string
val is_gpu_available : unit -> bool
val synthesize_mba_gpu : ?max_results:int -> int64 -> (int64 array, gpu_error) result
val batch_encrypt_gpu : bytecode:int64 list -> keys:int64 list -> (int64 list list, gpu_error) result
val verify_sac_gpu : ?trials:int -> int64 array -> (float, gpu_error) result
