(** Apple Metal GPU-Accelerated Synthesis & Polymorphic Batch Engine.
    Executes parallel non-linear MBA truth-table searches, batch bytecode encryption,
    and Strict Avalanche Criterion (SAC) verification directly on Apple Silicon GPU. *)

type gpu_error =
  | Gpu_unavailable
  | Gpu_execution_failed of string

val string_of_error : gpu_error -> string

val is_gpu_available : unit -> bool

(** Synthesize non-linear MBA polynomial seeds on GPU (65,536 threads).
    Returns [Error Gpu_unavailable] if Metal GPU is not supported/detected,
    or [Error (Gpu_execution_failed msg)] on shader/pipeline error. *)
val synthesize_mba_gpu : ?max_results:int -> int64 -> (int64 array, gpu_error) result

(** Batch encrypt polymorphic bytecode variants for N independent builds concurrently on GPU.
    Returns [Error Gpu_unavailable] if Metal GPU is not supported/detected,
    or [Error (Gpu_execution_failed msg)] on failure. Never silently returns plaintext. *)
val batch_encrypt_gpu : bytecode:int64 list -> keys:int64 list -> (int64 list list, gpu_error) result

(** Verify Strict Avalanche Criterion (SAC) bit-flip diffusion of a 16-register transformation on GPU.
    Returns [Error Gpu_unavailable] if Metal GPU is not supported/detected,
    or [Error (Gpu_execution_failed msg)] on failure. *)
val verify_sac_gpu : ?trials:int -> int64 array -> (float, gpu_error) result
