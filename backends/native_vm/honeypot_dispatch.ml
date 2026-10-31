(** Decoy classic switch-case VM interpreter.
    Pattern-matches the "textbook VM dispatcher" shape that a reverse engineer
    or an automated devirtualizer (D810-style) expects to find FIRST —
    but routes to semantically inert handlers, never the real opcode path. *)

open Cpp_codegen.Cpp_ast
open Cpp_codegen.Cpp_dsl

let default_decoy_mnemonics : (int * string) list = [
  (0x00, "OP_NOP");
  (0x01, "OP_ADD");
  (0x02, "OP_SUB");
  (0x03, "OP_XOR");
  (0x04, "OP_AND");
  (0x05, "OP_OR");
  (0x06, "OP_MOV_RR");
  (0x07, "OP_MOV_RI");
  (0x08, "OP_SHL");
  (0x09, "OP_SHR");
  (0x0A, "OP_SAR");
  (0x0B, "OP_CMP");
  (0x0C, "OP_MUL");
  (0x0D, "OP_DIV");
  (0x0E, "OP_PUSH");
  (0x0F, "OP_POP");
  (0x10, "OP_LOAD");
  (0x11, "OP_STORE");
  (0x12, "OP_JMP");
  (0x13, "OP_JZ");
  (0x14, "OP_JNZ");
  (0x15, "OP_CALL");
  (0x16, "OP_RET");
  (0x17, "OP_TEST");
  (0x18, "OP_NEG");
  (0x19, "OP_NOT");
]

let synth_decoy_case (rng : Random.State.t) (opcode : int) (mnemonic : string) : expr * string option * stmt list =
  let imm = Random.State.int64 rng Int64.max_int in
  let noise_r = Printf.sprintf "decoy_r%d" (Random.State.int rng 8) in
  let code =
    if String.contains mnemonic '+' || (String.contains mnemonic 'A' && String.contains mnemonic 'D') then
      Printf.sprintf
        "volatile uint64_t %s = decoy_regs[op & 0x1F] + decoy_regs[(op >> 3) & 0x1F]; decoy_regs[dst & 0x1F] = %s + 0x%LXULL;"
        noise_r noise_r imm
    else if String.contains mnemonic 'S' && String.contains mnemonic 'U' then
      Printf.sprintf
        "volatile uint64_t %s = decoy_regs[op & 0x1F] - decoy_regs[(op >> 3) & 0x1F]; decoy_regs[dst & 0x1F] = %s ^ 0x%LXULL;"
        noise_r noise_r imm
    else if String.contains mnemonic 'X' || (String.contains mnemonic 'R' && String.contains mnemonic 'O') then
      Printf.sprintf
        "volatile uint64_t %s = decoy_regs[op & 0x1F] ^ decoy_regs[(op >> 3) & 0x1F]; decoy_regs[dst & 0x1F] = %s + 0x%LXULL;"
        noise_r noise_r imm
    else if String.contains mnemonic 'A' && String.contains mnemonic 'N' then
      Printf.sprintf
        "volatile uint64_t %s = decoy_regs[op & 0x1F] & decoy_regs[(op >> 3) & 0x1F]; decoy_regs[dst & 0x1F] = (%s << 1) | 0x%LXULL;"
        noise_r noise_r (Int64.logor imm 1L)
    else if String.contains mnemonic 'M' && String.contains mnemonic 'O' then
      Printf.sprintf
        "decoy_regs[dst & 0x1F] = decoy_regs[op & 0x1F] ^ 0x%LXULL;"
        imm
    else if String.contains mnemonic 'C' && String.contains mnemonic 'M' then
      Printf.sprintf
        "decoy_regs[0] = (decoy_regs[dst & 0x1F] == decoy_regs[op & 0x1F]) ? 0x%LXULL : 0ULL;"
        imm
    else
      Printf.sprintf
        "volatile uint64_t %s = decoy_regs[op & 0x1F] ^ decoy_regs[(op >> 5) & 0x1F]; decoy_regs[dst & 0x1F] = %s + 0x%LXULL;"
        noise_r noise_r imm
  in
  let body = [
    raw code;
    break_stmt;
  ] in
  (u8 opcode, Some mnemonic, body)

let emit_honeypot_switch_fn (rng : Random.State.t) (mnemonics : (int * string) list) : top_decl =
  let chosen_mnemonics =
    if List.length mnemonics < 10 then
      default_decoy_mnemonics
    else
      (* Deduplicate by opcode *)
      let seen = Hashtbl.create 32 in
      let filtered = ref [] in
      List.iter (fun (op, m) ->
        let op_byte = op land 0xFF in
        if not (Hashtbl.mem seen op_byte) then begin
          Hashtbl.add seen op_byte ();
          filtered.contents <- (op_byte, m) :: filtered.contents
        end
      ) mnemonics;
      List.rev !filtered
  in
  let cases =
    List.map (fun (op, mnemonic) -> synth_decoy_case rng op mnemonic) chosen_mnemonics
  in
  let switch_stmt =
    switch_annotated (var "op") cases (Some [
      comment "default: unreachable legacy opcode";
      raw "__builtin_trap();"
    ])
  in
  func_decl
    ~attrs:[NoInline; StaticFn]
    Void
    "legacy_bytecode_interpreter_fallback"
    [ (UInt8, "op"); (UInt8, "dst"); (VolatilePtr UInt64, "decoy_regs") ]
    [
      comment "Compatibility interpreter for pre-5877 bytecode format (deprecated path)";
      switch_stmt;
    ]
