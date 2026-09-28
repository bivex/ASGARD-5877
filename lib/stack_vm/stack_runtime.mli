open Stack_ir

type target_arch = X86_64 | AArch64 | RV64

type runtime_config = {
  arch : target_arch;
  pcode_reg : string;   (* VIP *)
  stack_reg : string;   (* VSP *)
  crypt_reg : string;   (* VKEY *)
  disp_reg : string;    (* VDISP *)
  ctx_reg : string;     (* VCTX *)
}

val default_config : target_arch -> runtime_config

val emit_entry_stub : runtime_config -> int -> string list

val emit_exit_stub : runtime_config -> int -> string list

val emit_dispatch_epilogue : runtime_config -> string list

val emit_handler : runtime_config -> stack_op -> string list

val scramble_c_runtime :
  ?seed:int64 ->
  ?strip_comments:bool ->
  string ->
  string

val generate_c_runtime :
  ?external_symbols:string list ->
  ?constants:(string * string) list ->
  ?obfuscate_runtime:bool ->
  ?enc:Stack_encoder.encrypted_bytecode ->
  runtime_config ->
  program ->
  string

val emit_runner_cpp : ?header_name:string -> int64 list -> string

val emit_probe_cpp : ?header_name:string -> unit -> string

