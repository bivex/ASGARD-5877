type error = string

type target_arch = X86_64 | Arm64 | Riscv64

type vm_engine_kind = Threaded | Jit | MultiVm

type ir_func = Ir_repr of Obj.t

let wrap_ir x = Ir_repr (Obj.repr x)
let unwrap_ir (Ir_repr x) = Obj.obj x

type protection_config = {
  c_macro_enabled : bool;
  cff_enabled : bool;
  mba_enabled : bool;
  mba_depth : int;
  seed : int option;
  raw : Obj.t;
}

let is_c_macro_enabled c = c.c_macro_enabled
let is_cff_enabled c = c.cff_enabled
let is_mba_enabled c = c.mba_enabled
let mba_depth c = c.mba_depth
let seed c = c.seed

let wrap_config ~c_macro_enabled ~cff_enabled ~mba_enabled ~mba_depth ~seed raw =
  {
    c_macro_enabled;
    cff_enabled;
    mba_enabled;
    mba_depth;
    seed;
    raw = Obj.repr raw;
  }

let unwrap_config c = Obj.obj c.raw

type metrics_report = {
  cyclomatic_complexity : int;
  shannon_entropy : float;
  uniform_entropy : float;
  drs_score : float;
  formatted_summary : string;
}

type package_result = {
  cpp_runtime_source : string;
  runner_source : string;
  bytecode : int64 list;
  metrics : metrics_report;
  header_name : string;
}

type protect_result = {
  header_path : string;
  runner_path : string;
  bytecode_path : string;
  bytecode_length_bytes : int;
  metrics : metrics_report;
  binary_path : string option;
  execution_output : (int * string) option;
}

module type Lifter = sig
  val arch_name : string
  val target_arch : target_arch
  val lift_source : string -> (ir_func * (string * string) list, error) result
end

module type C_macro_obfuscator = sig
  val transform_source :
    config:protection_config ->
    in_file:string ->
    out_c_file:string ->
    out_header_file:string ->
    rng:Random.State.t ->
    (unit, error) result
end

module type Vm_packager = sig
  val engine_kind : vm_engine_kind
  val package :
    rng:Random.State.t ->
    config:protection_config ->
    ?constants:(string * string) list ->
    ir_func ->
    package_result
end

module type Trampoline_engine = sig
  val embed_vm_trampoline :
    c_src:string ->
    bytecode:int64 list ->
    out_path:string ->
    unit
end

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
