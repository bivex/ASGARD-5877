open Random_visa_domain
include Vanguard_types

let shuffle_list rng list =
  let arr = Array.of_list list in
  Opcode_map.shuffle rng arr;
  Array.to_list arr

let generate
    ?word_bits
    ?(min_reg_bits = 5)
    ?(min_imm_bits = 5)
    ~rng
    ~mnemonics
    () : (t, string) result =
  let opcode_bits =
    max 6 (int_of_float (ceil (log (float_of_int (List.length mnemonics + 8)) /. log 2.0)))
  in
  let min_needed_bits = opcode_bits + 1 + (min_reg_bits * 3) + min_imm_bits in
  let w_bits =
    match word_bits with
    | Some w -> w
    | None ->
        let candidates =
          if min_needed_bits <= 16 then [| 16; 32; 48; 64 |]
          else if min_needed_bits <= 32 then [| 32; 48; 64 |]
          else if min_needed_bits <= 48 then [| 48; 64 |]
          else [| 64 |]
        in
        candidates.(Random.State.int rng (Array.length candidates))
  in
  if w_bits < min_needed_bits then
    Error (Printf.sprintf "word_bits %d is too small; requires at least %d bits" w_bits min_needed_bits)
  else
    match Opcode_map.generate ~rng ~mnemonics ~opcode_bits with
    | Error _ as e -> e
    | Ok opcodes ->
        let remaining = w_bits - opcode_bits - 1 in (* -1 for Mask *)
        let base_reg_w = max min_reg_bits (remaining / 4) in
        let dst_w = base_reg_w in
        let src1_w = base_reg_w in
        let src2_w = base_reg_w in
        let imm_w = remaining - dst_w - src1_w - src2_w in

        (* Randomized non-overlapping layout permutation *)
        let field_specs = [
          (Opcode, opcode_bits);
          (Mask, 1);
          (Dst, dst_w);
          (Src1, src1_w);
          (Src2, src2_w);
          (Imm, imm_w);
        ] in
        let permuted_specs = shuffle_list rng field_specs in

        let offset = ref 0 in
        let fields =
          List.map
            (fun (kind, width) ->
              let f = { kind; bit_offset = !offset; bit_width = width } in
              offset := !offset + width;
              f)
            permuted_specs
        in

        (* Optional junk field if any spare bits remain *)
        let all_fields =
          if !offset < w_bits then
            let junk_w = w_bits - !offset in
            fields @ [ { kind = Junk; bit_offset = !offset; bit_width = junk_w } ]
          else fields
        in

        match make_layout ~word_bits:w_bits ~fields:all_fields with
        | Error _ as e -> e
        | Ok layout ->
            let key_seed = Random.State.int32 rng Int32.max_int in
            let junk_ratio = 0.1 +. (Random.State.float rng 0.2) in
            Ok { layout; opcodes; key_seed; junk_ratio }

let of_isa_spec
    ?word_bits
    ?min_reg_bits
    ?min_imm_bits
    ~rng
    (spec : Vector_isa_spec.t) =
  let mnemonics = List.map (fun (i : Vector_instruction.t) -> i.mnemonic) spec.instructions in
  let unique_mnemonics = List.sort_uniq String.compare mnemonics in
  generate ?word_bits ?min_reg_bits ?min_imm_bits ~rng ~mnemonics:unique_mnemonics ()

let emit_cpp_decoder = Vanguard_decoder.emit_cpp_decoder

let assemble_program = Vanguard_asm.assemble_program
let write_bytecode_file = Vanguard_asm.write_bytecode_file
let read_bytecode_file = Vanguard_asm.read_bytecode_file
