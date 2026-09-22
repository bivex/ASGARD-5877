(** Port signatures for Hexagonal VM Protection & Obfuscation architecture. *)

open Vm_ir
open Native_vm

type error = string

type target_arch = X86_64 | Arm64

type vm_engine_kind = Threaded | Jit | MultiVm

type package_result = {
  cpp_runtime_source : string;
  runner_source : string;
  bytecode : int64 list;
  metrics : Metrics.metrics_report;
  header_name : string;
}

type protect_result = {
  header_path : string;
  runner_path : string;
  bytecode_path : string;
  bytecode_length_bytes : int;
  metrics : Metrics.metrics_report;
  binary_path : string option;
  execution_output : (int * string) option;
}

(** Lifter Port: parses target assembly text into lifted VM-IR functions and extracts constants. *)
module type Lifter = sig
  val arch_name : string
  val target_arch : target_arch
  val lift_source : string -> (Ir.func * (string * string) list, error) result
end

(** C Macro Obfuscator Port: pre-transforms C/C++ source code before assembly compilation. *)
module type C_macro_obfuscator = sig
  val transform_source :
    config:Protection_config.t ->
    in_file:string ->
    out_c_file:string ->
    out_header_file:string ->
    rng:Random.State.t ->
    (unit, error) result
end

(** VM Packaging and Runtime Emitter Port: compiles IR to bytecode and generates C++ VM runtime *)
module type Vm_packager = sig
  val engine_kind : vm_engine_kind
  val package :
    rng:Random.State.t ->
    config:Protection_config.t ->
    ?constants:(string * string) list ->
    Ir.func ->
    package_result
end

(** Trampoline Synthesizer Port: embeds bytecode and replaces marked function body with VM call. *)
module type Trampoline_engine = sig
  val embed_vm_trampoline :
    c_src:string ->
    bytecode:int64 list ->
    out_path:string ->
    unit
end

(** Native Toolchain Port: invokes Clang for C->ASM and C++20->Binary compilation. *)
module type Toolchain = sig
  val compile_to_asm :
    arch:target_arch ->
    c_source:string ->
    out_asm:string ->
    include_dir:string ->
    (unit, error) result

  val compile_native_binary :
    is_c:bool ->
    source_file:string ->
    out_binary:string ->
    include_dir:string ->
    (unit, error) result

  val execute_binary :
    binary_path:string ->
    (int * string, error) result
end
