type t = {
  name : string;
  version : string;
  config : Vector_config.t;
  instructions : Vector_instruction.t list;
  metadata : (string * string) list;
}

let make
    ~name
    ?(version = "1.0-draft")
    ?(config = Vector_config.default)
    ?(metadata = [])
    () =
  { name; version; config; instructions = []; metadata }

let add_instruction t inst =
  let check_collision existing =
    if existing.Vector_instruction.funct6 = inst.Vector_instruction.funct6
       && existing.Vector_instruction.funct3 = inst.Vector_instruction.funct3
       && existing.Vector_instruction.opcode = inst.Vector_instruction.opcode
    then
      Error
        (Errors.Encoding_collision
           ( existing.Vector_instruction.mnemonic,
             inst.Vector_instruction.mnemonic,
             inst.Vector_instruction.funct6,
             inst.Vector_instruction.funct3 ))
    else if existing.Vector_instruction.mnemonic = inst.Vector_instruction.mnemonic then
      Error (Errors.Duplicate_mnemonic inst.Vector_instruction.mnemonic)
    else
      Ok ()
  in
  let rec loop = function
    | [] -> Ok { t with instructions = t.instructions @ [ inst ] }
    | ex :: rest -> (
        match check_collision ex with
        | Ok () -> loop rest
        | Error err -> Error err)
  in
  loop t.instructions

let of_instructions ~name ?(version = "1.0-draft") ?(config = Vector_config.default) ?(metadata = []) insts =
  let initial = make ~name ~version ~config ~metadata () in
  List.fold_left
    (fun acc_res inst ->
      match acc_res with
      | Ok acc -> add_instruction acc inst
      | Error err -> Error err)
    (Ok initial)
    insts

let get_by_mnemonic t mnemonic =
  let m_lower = String.lowercase_ascii mnemonic in
  List.find_opt
    (fun inst ->
      inst.Vector_instruction.mnemonic = mnemonic
      || String.lowercase_ascii inst.Vector_instruction.mnemonic = m_lower)
    t.instructions

let decode t word =
  let opcode = Int32.to_int (Int32.logand word 0x7Fl) in
  let funct3 = Int32.to_int (Int32.logand (Int32.shift_right_logical word 12) 0x7l) in
  let funct6 = Int32.to_int (Int32.logand (Int32.shift_right_logical word 26) 0x3Fl) in
  List.find_opt
    (fun (inst : Vector_instruction.t) ->
      inst.opcode = opcode && inst.funct3 = funct3 && inst.funct6 = funct6)
    t.instructions

let to_sail_specification t =
  let b = Buffer.create 2048 in
  Buffer.add_string b "/* ========================================================================= */\n";
  Buffer.add_string b (Printf.sprintf "/* Sail Formal Specification for %s (V-ISA)                         */\n" t.name);
  Buffer.add_string b (Printf.sprintf "/* Version: %s                                                   */\n" t.version);
  Buffer.add_string b "/* Generated via Hexagonal DDD random_vISA Synthesizer                       */\n";
  Buffer.add_string b "/* ========================================================================= */\n\n";

  Buffer.add_string b "default Order dec\n";
  Buffer.add_string b "$include <prelude.sail>\n\n";

  Buffer.add_string b (Printf.sprintf "let VLEN : int = %d\n" t.config.vlen);
  Buffer.add_string b (Printf.sprintf "let ELEN : int = %d\n" t.config.elen);
  Buffer.add_string b (Printf.sprintf "let NUM_VREGS : int = %d\n\n" t.config.num_vregs);

  Buffer.add_string b "type vreg_idx = range(0, 31)\n";
  Buffer.add_string b "type vreg_t = bits(VLEN)\n\n";

  Buffer.add_string b "register v0  : vreg_t\n";
  Buffer.add_string b "register v1  : vreg_t\n";
  Buffer.add_string b "register v2  : vreg_t\n";
  Buffer.add_string b "register v3  : vreg_t\n";
  Buffer.add_string b "register vl  : bits(64)\n";
  Buffer.add_string b "register vtype : bits(64)\n\n";

  Buffer.add_string b "val get_velem : (vreg_t, int, int) -> bits(32)\n";
  Buffer.add_string b "val set_velem : (vreg_t, int, int, bits(32)) -> unit\n";
  Buffer.add_string b "val get_vmask_bit : (vreg_t, int) -> bits(1)\n\n";

  List.iter
    (fun (inst : Vector_instruction.t) ->
      Buffer.add_string b
        (Printf.sprintf "/* Instruction: %s (%s) encoding: funct6=%d, funct3=%d */\n"
           inst.mnemonic
           (Types.Instruction_format.to_string inst.format)
           inst.funct6
           inst.funct3);
      let clause = {
        Sail_ast.mnemonic = inst.mnemonic;
        funct6 = inst.funct6;
        funct3 = inst.funct3;
        format_name = Types.Instruction_format.to_string inst.format;
      } in
      Buffer.add_string b (Sail_ast.encoding_clause_to_sail clause);
      Buffer.add_char b '\n';
      if inst.description <> "" then begin
        Buffer.add_string b (Printf.sprintf "/* %s */\n" inst.description);
      end;
      Buffer.add_string b (Sail_ast.function_to_sail inst.sail_function);
      Buffer.add_string b "\n\n")
    t.instructions;

  Buffer.contents b
