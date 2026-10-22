open Stack_ir

type target_arch = X86_64 | AArch64 | RV64

type runtime_config = {
  arch : target_arch;
  pcode_reg : string;   (* VIP *)
  stack_reg : string;   (* VSP *)
  crypt_reg : string;   (* VKEY *)
  disp_reg : string;    (* VDISP *)
  ctx_reg : string;     (* VCTX *)
  (** [enable_hw_binding] mixes the emulation differential (CPUID/timer
      consistency) into the rolling key: zero on real hardware, so the
      decryption is unaffected, but non-zero in a slow emulator, where
      the bytecode then decrypts into garbage.  Patching the probe out
      breaks the decryption as well. *)
  enable_hw_binding : bool;
  enable_address_bound : bool;
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

val emit_stack_external_symbols_table_ast :
  string list ->
  Cpp_codegen.Cpp_ast.top_decl

val emit_stack_constants_tables_ast :
  (string * string) list ->
  Cpp_codegen.Cpp_ast.top_decl list

val emit_stack_block_tables_ast :
  max_bid:int ->
  block_offsets:int64 list ->
  block_keys:int64 list ->
  tag_key0:int64 ->
  tag_key1:int64 ->
  unit ->
  Cpp_codegen.Cpp_ast.top_decl list

val emit_stack_dispatch_stmts :
  entry_bid:int ->
  (int * string * string) list ->
  Cpp_codegen.Cpp_ast.stmt list

val emit_stack_dispatch_source :
  entry_bid:int ->
  (int * string * string) list ->
  string

val emit_h_call_extern : target_arch -> Cpp_codegen.Cpp_ast.top_decl

val emit_stack_runtime_hpp_decls :
  ?external_symbols:string list ->
  ?constants:(string * string) list ->
  ?enc:Stack_encoder.encrypted_bytecode ->
  runtime_config ->
  program ->
  Cpp_codegen.Cpp_ast.top_decl list

val generate_c_runtime :
  ?external_symbols:string list ->
  ?constants:(string * string) list ->
  ?obfuscate_runtime:bool ->
  ?enc:Stack_encoder.encrypted_bytecode ->
  runtime_config ->
  program ->
  string

val emit_stack_runner_main_def : unit -> Cpp_codegen.Cpp_ast.top_decl

val emit_stack_probe_main_def : unit -> Cpp_codegen.Cpp_ast.top_decl

val emit_runner_cpp : ?header_name:string -> int64 list -> string

val emit_probe_cpp : ?header_name:string -> unit -> string

