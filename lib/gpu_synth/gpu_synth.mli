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

module Gpu_mba : sig
  type gpu_mba_pool
  val create_pool : ?seed:int64 -> ?max_results:int -> rng:Random.State.t -> unit -> gpu_mba_pool
  val pool_size : gpu_mba_pool -> int
  val is_gpu_backed : gpu_mba_pool -> bool
  val obfuscate_alu :
    pool:gpu_mba_pool ->
    rng:Random.State.t ->
    dst:Vm_ir.Register.t ->
    src1:Vm_ir.Ir.operand ->
    src2:Vm_ir.Ir.operand ->
    Vm_ir.Ir.alu_op ->
    Vm_ir.Ir.instr list
end

module Gpu_matrix : sig
  type substitution_matrix = {
    forward : int64 array array;
    inverse : int64 array array;
    dim : int;
    sac : float;
  }
  val generate :
    ?dim:int ->
    ?target_sac_min:float ->
    ?target_sac_max:float ->
    ?max_attempts:int ->
    rng:Random.State.t ->
    unit ->
    substitution_matrix
  val transform_vector : substitution_matrix -> int64 array -> int64 array
  val inverse_transform_vector : substitution_matrix -> int64 array -> int64 array
  val emit_cpp_constants : substitution_matrix -> string
end
