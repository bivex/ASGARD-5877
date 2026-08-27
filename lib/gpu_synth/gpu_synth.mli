(** Apple Metal GPU-Accelerated Synthesis & Polymorphic Batch Engine.
    Executes parallel non-linear MBA truth-table searches, batch bytecode encryption,
    and Strict Avalanche Criterion (SAC) verification directly on Apple Silicon GPU. *)

val is_gpu_available : unit -> bool

(** Synthesize non-linear MBA polynomial seeds on GPU (65,536 threads). *)
val synthesize_mba_gpu : ?max_results:int -> int64 -> int64 array

(** Batch encrypt polymorphic bytecode variants for N independent builds concurrently on GPU. *)
val batch_encrypt_gpu : bytecode:int64 list -> keys:int64 list -> int64 list list

(** Verify Strict Avalanche Criterion (SAC) bit-flip diffusion of a 16-register transformation on GPU. *)
val verify_sac_gpu : ?trials:int -> int64 array -> float
