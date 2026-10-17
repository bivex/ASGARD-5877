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
  let header =
    Printf.sprintf
      "/* ========================================================================= */\n\
       /* Sail Formal Specification for %s (V-ISA)                         */\n\
       /* Version: %s                                                   */\n\
       /* Generated via Hexagonal DDD random_vISA Synthesizer                       */\n\
       /* ========================================================================= */\n\n\
       default Order dec\n\
       $include <prelude.sail>\n\n\
       let VLEN : int = %d\n\
       let ELEN : int = %d\n\
       let NUM_VREGS : int = %d\n\n\
       type vreg_idx = range(0, 31)\n\
       type vreg_t = bits(VLEN)\n\n\
       register v0  : vreg_t\n\
       register v1  : vreg_t\n\
       register v2  : vreg_t\n\
       register v3  : vreg_t\n\
       register vl  : bits(64)\n\
       register vtype : bits(64)\n\n\
       val get_velem : (vreg_t, int, int) -> bits(32)\n\
       val set_velem : (vreg_t, int, int, bits(32)) -> unit\n\
       val get_vmask_bit : (vreg_t, int) -> bits(1)\n\n"
      t.name t.version t.config.vlen t.config.elen t.config.num_vregs
  in
  let inst_chunks =
    List.map
      (fun (inst : Vector_instruction.t) ->
        let comment =
          Printf.sprintf "/* Instruction: %s (%s) encoding: funct6=%d, funct3=%d */\n"
            inst.mnemonic
            (Types.Instruction_format.to_string inst.format)
            inst.funct6
            inst.funct3
        in
        let clause = {
          Sail_ast.mnemonic = inst.mnemonic;
          funct6 = inst.funct6;
          funct3 = inst.funct3;
          format_name = Types.Instruction_format.to_string inst.format;
        } in
        let enc = Sail_ast.encoding_clause_to_sail clause ^ "\n" in
        let desc =
          if inst.description <> "" then
            Printf.sprintf "/* %s */\n" inst.description
          else ""
        in
        let fn = Sail_ast.function_to_sail inst.sail_function ^ "\n\n" in
        comment ^ enc ^ desc ^ fn)
      t.instructions
  in
  header ^ String.concat "" inst_chunks
