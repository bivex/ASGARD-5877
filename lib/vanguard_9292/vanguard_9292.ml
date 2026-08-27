open Random_visa_domain

type field_kind =
  | Opcode
  | Dst
  | Src1
  | Src2
  | Imm
  | Mask
  | Junk

let field_kind_to_string = function
  | Opcode -> "Opcode"
  | Dst -> "Dst"
  | Src1 -> "Src1"
  | Src2 -> "Src2"
  | Imm -> "Imm"
  | Mask -> "Mask"
  | Junk -> "Junk"

type field_layout = {
  kind : field_kind;
  bit_offset : int;
  bit_width : int;
}

type instruction_word_layout = {
  word_bits : int;
  fields : field_layout list;
}

let fields_overlap (a : field_layout) (b : field_layout) =
  let a_end = a.bit_offset + a.bit_width in
  let b_end = b.bit_offset + b.bit_width in
  not (a_end <= b.bit_offset || b_end <= a.bit_offset)

let make_layout ~word_bits ~fields : (instruction_word_layout, string) result =
  if word_bits <= 0 then
    Error "word_bits must be positive"
  else if List.exists (fun f -> f.bit_width <= 0 || f.bit_offset < 0) fields then
    Error "All fields must have bit_width > 0 and bit_offset >= 0"
  else
    let sorted = List.sort (fun a b -> compare a.bit_offset b.bit_offset) fields in
    let rec check = function
      | [] | [ _ ] -> Ok ()
      | a :: (b :: _ as rest) ->
          if fields_overlap a b then
            Error (Printf.sprintf "Overlapping fields '%s' (offset %d, width %d) and '%s' (offset %d, width %d)"
                     (field_kind_to_string a.kind) a.bit_offset a.bit_width
                     (field_kind_to_string b.kind) b.bit_offset b.bit_width)
          else check rest
    in
    let max_bit = List.fold_left (fun acc f -> max acc (f.bit_offset + f.bit_width)) 0 fields in
    if max_bit > word_bits then
      Error (Printf.sprintf "Fields extend up to bit %d, exceeding word_bits %d" max_bit word_bits)
    else
      match check sorted with
      | Error _ as e -> e
      | Ok () -> Ok { word_bits; fields = sorted }

module Opcode_map = struct
  type t = {
    forward : (string, int) Hashtbl.t;
    reverse : (int, string) Hashtbl.t;
    opcode_bits : int;
  }

  let shuffle rng arr =
    let n = Array.length arr in
    for i = n - 1 downto 1 do
      let j = Random.State.int rng (i + 1) in
      let tmp = arr.(i) in
      arr.(i) <- arr.(j);
      arr.(j) <- tmp
    done

  let generate ~rng ~mnemonics ~opcode_bits : (t, string) result =
    let space = 1 lsl opcode_bits in
    let n = List.length mnemonics in
    if n > space then
      Error (Printf.sprintf "%d instructions do not fit in %d-bit opcode space (%d slots)" n opcode_bits space)
    else begin
      let codes = Array.init space (fun i -> i) in
      shuffle rng codes;
      let forward = Hashtbl.create n in
      let reverse = Hashtbl.create n in
      List.iteri
        (fun i mnemonic ->
          Hashtbl.replace forward mnemonic codes.(i);
          Hashtbl.replace reverse codes.(i) mnemonic)
        mnemonics;
      Ok { forward; reverse; opcode_bits }
    end

  let encode t mnemonic = Hashtbl.find_opt t.forward mnemonic
  let decode t code = Hashtbl.find_opt t.reverse code

  let is_junk t code =
    code >= 0 && code < (1 lsl t.opcode_bits) && Option.is_none (decode t code)
end

module Rolling_key = struct
  type t = { seed : int32; mutable state : int32; mutable counter : int32 }

  let make ~seed =
    let init_state = if seed = 0l then 0x1337BEEFl else seed in
    { seed; state = init_state; counter = 0l }

  let next t =
    t.counter <- Int32.add t.counter 1l;
    let open Int32 in
    let x = t.state in
    let x = logxor x (shift_left x 13) in
    let x = logxor x (shift_right_logical x 17) in
    let x = logxor x (shift_left x 5) in
    let rot = logor (shift_left x 7) (shift_right_logical x 25) in
    let mixed = add rot (mul t.counter 0x9E3779B9l) in
    let next_state = if mixed = 0l then 0x1337BEEFl else mixed in
    t.state <- next_state;
    next_state

  let reset t =
    let init_state = if t.seed = 0l then 0x1337BEEFl else t.seed in
    t.state <- init_state;
    t.counter <- 0l
end

type t = {
  layout : instruction_word_layout;
  opcodes : Opcode_map.t;
  key_seed : int32;
  junk_ratio : float;
}

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

let encode_word (t : t) ~mnemonic ~dst ~src1 ~src2 ~imm ~mask ~key : (int64, string) result =
  match Opcode_map.encode t.opcodes mnemonic with
  | None -> Error (Printf.sprintf "Unknown mnemonic '%s'" mnemonic)
  | Some opcode ->
      let put acc field value =
        let bit_mask =
          if field.bit_width >= 64 then -1L
          else Int64.sub (Int64.shift_left 1L field.bit_width) 1L
        in
        let masked_val = Int64.logand (Int64.of_int value) bit_mask in
        Int64.logor acc (Int64.shift_left masked_val field.bit_offset)
      in
      let find_opt kind = List.find_opt (fun f -> f.kind = kind) t.layout.fields in
      let base_word =
        List.fold_left
          (fun acc (kind, value) ->
            match find_opt kind with
            | Some f -> put acc f value
            | None -> acc)
          0L
          [
            (Opcode, opcode);
            (Mask, if mask then 1 else 0);
            (Dst, dst);
            (Src1, src1);
            (Src2, src2);
            (Imm, imm);
          ]
      in
      let rolling_mask = Int64.of_int32 (Rolling_key.next key) in
      Ok (Int64.logxor base_word rolling_mask)

let decode_word (t : t) ~key (raw : int64) =
  let rolling_mask = Int64.of_int32 (Rolling_key.next key) in
  let word = Int64.logxor raw rolling_mask in
  let get field =
    let bit_mask =
      if field.bit_width >= 64 then -1L
      else Int64.sub (Int64.shift_left 1L field.bit_width) 1L
    in
    Int64.to_int (Int64.logand (Int64.shift_right_logical word field.bit_offset) bit_mask)
  in
  let find_opt kind = List.find_opt (fun f -> f.kind = kind) t.layout.fields in
  match find_opt Opcode with
  | None -> Error (`Corrupted_field "Opcode field missing from layout")
  | Some opcode_field ->
      let opcode = get opcode_field in
      match Opcode_map.decode t.opcodes opcode with
      | None ->
          if Opcode_map.is_junk t.opcodes opcode then Error `Junk_opcode
          else Error (`Unknown_opcode opcode)
      | Some mnemonic ->
          let dst = match find_opt Dst with Some f -> get f | None -> 0 in
          let src1 = match find_opt Src1 with Some f -> get f | None -> 0 in
          let src2 = match find_opt Src2 with Some f -> get f | None -> 0 in
          let imm = match find_opt Imm with Some f -> get f | None -> 0 in
          let mask = match find_opt Mask with Some f -> get f <> 0 | None -> false in
          Ok
            ( mnemonic,
              `Dst dst,
              `Src1 src1,
              `Src2 src2,
              `Imm imm,
              `Mask mask )

let emit_cpp_decoder (t : t) (spec : Vector_isa_spec.t) =
  let find_field kind =
    match List.find_opt (fun f -> f.kind = kind) t.layout.fields with
    | Some f -> (f.bit_offset, f.bit_width)
    | None -> (0, 0)
  in
  let op_off, op_w = find_field Opcode in
  let dst_off, dst_w = find_field Dst in
  let s1_off, s1_w = find_field Src1 in
  let s2_off, s2_w = find_field Src2 in
  let imm_off, imm_w = find_field Imm in
  let mask_off, _ = find_field Mask in

  let mask_expr width =
    if width >= 64 then "0xFFFFFFFFFFFFFFFFULL"
    else Printf.sprintf "0x%LXULL" (Int64.sub (Int64.shift_left 1L width) 1L)
  in

  let b = Buffer.create 4096 in
  Buffer.add_string b "#pragma once\n";
  Buffer.add_string b "#include \"isa_state.hpp\"\n";
  Buffer.add_string b "#include \"decoder.hpp\"\n";
  Buffer.add_string b "#include \"instructions.hpp\"\n";
  Buffer.add_string b "#include <cstdint>\n#include <iostream>\n#include <iomanip>\n\n";
  Buffer.add_string b "namespace vanguard_vm {\n\n";

  (* RollingKey class *)
  Buffer.add_string b "struct RollingKey {\n";
  Buffer.add_string b "    uint32_t state;\n";
  Buffer.add_string b "    uint32_t counter{0};\n";
  Buffer.add_string b "    inline explicit RollingKey(uint32_t seed) noexcept\n";
  Buffer.add_string b "        : state(seed == 0 ? 0x1337BEEFU : seed), counter(0) {}\n\n";
  Buffer.add_string b "    inline uint32_t next() noexcept {\n";
  Buffer.add_string b "        counter++;\n";
  Buffer.add_string b "        uint32_t x = state;\n";
  Buffer.add_string b "        x ^= x << 13;\n";
  Buffer.add_string b "        x ^= x >> 17;\n";
  Buffer.add_string b "        x ^= x << 5;\n";
  Buffer.add_string b "        uint32_t rot = (x << 7) | (x >> 25);\n";
  Buffer.add_string b "        uint32_t mixed = rot + (counter * 0x9E3779B9U);\n";
  Buffer.add_string b "        if (mixed == 0) mixed = 0x1337BEEFU;\n";
  Buffer.add_string b "        state = mixed;\n";
  Buffer.add_string b "        return mixed;\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "};\n\n";

  (* VanguardDecoder class *)
  Buffer.add_string b "class VanguardDecoder {\npublic:\n";
  Buffer.add_string b "    RollingKey key;\n";
  Buffer.add_string b "    bool trapped{false};\n";
  Buffer.add_string b "    size_t executed_instructions{0};\n\n";
  Buffer.add_string b (Printf.sprintf "    explicit VanguardDecoder(uint32_t seed = 0x%08lXU) noexcept : key(seed) {}\n\n" t.key_seed);
  Buffer.add_string b "    bool decode_and_execute(visa_emulator::EmulatorState& state, uint64_t raw_word) {\n";
  Buffer.add_string b "        uint32_t k = key.next();\n";
  Buffer.add_string b "        uint64_t word = raw_word ^ static_cast<uint64_t>(static_cast<int64_t>(static_cast<int32_t>(k)));\n\n";
  Buffer.add_string b (Printf.sprintf "        uint32_t opcode = (word >> %d) & %s;\n" op_off (mask_expr op_w));
  Buffer.add_string b (Printf.sprintf "        size_t dst = (word >> %d) & %s;\n" dst_off (mask_expr dst_w));
  Buffer.add_string b (Printf.sprintf "        size_t src1 = (word >> %d) & %s;\n" s1_off (mask_expr s1_w));
  Buffer.add_string b (Printf.sprintf "        size_t src2 = (word >> %d) & %s;\n" s2_off (mask_expr s2_w));
  Buffer.add_string b (Printf.sprintf "        int64_t imm = (word >> %d) & %s;\n" imm_off (mask_expr imm_w));
  Buffer.add_string b (Printf.sprintf "        bool mask = ((word >> %d) & 1) != 0;\n\n" mask_off);

  Buffer.add_string b "        visa_emulator::DecodedInstruction dec;\n";
  Buffer.add_string b "        dec.vd = static_cast<uint8_t>(dst);\n";
  Buffer.add_string b "        dec.vs2 = static_cast<uint8_t>(src2);\n";
  Buffer.add_string b "        dec.vs1 = static_cast<uint8_t>(src1);\n";
  Buffer.add_string b "        dec.rs1 = static_cast<uint8_t>(src1);\n";
  Buffer.add_string b "        dec.imm = static_cast<int8_t>(imm);\n";
  Buffer.add_string b "        dec.vm = mask ? 1 : 0;\n\n";

  Buffer.add_string b "        switch (opcode) {\n";

  (* Instruction cases *)
  List.iter
    (fun (inst : Vector_instruction.t) ->
      match Opcode_map.encode t.opcodes inst.mnemonic with
      | None -> ()
      | Some code ->
          Buffer.add_string b (Printf.sprintf "            case 0x%02X: // %s\n" code inst.mnemonic);
          Buffer.add_string b (Printf.sprintf "                dec.id = visa_emulator::InstId::%s;\n" (String.uppercase_ascii inst.mnemonic));
          Buffer.add_string b (Printf.sprintf "                dec.mnemonic = \"%s\";\n" inst.mnemonic);
          Buffer.add_string b "                if (!visa_emulator::InstructionExecutor::execute(state, dec)) return false;\n";
          Buffer.add_string b "                executed_instructions++;\n";
          Buffer.add_string b "                return true;\n")
    spec.instructions;

  (* Decoy junk opcode traps *)
  let junk_codes = ref [] in
  for c = 0 to (1 lsl t.opcodes.opcode_bits) - 1 do
    if Opcode_map.is_junk t.opcodes c then junk_codes := c :: !junk_codes
  done;

  if !junk_codes <> [] then begin
    Buffer.add_string b "\n            // Decoy Junk Trap Opcode Handlers\n";
    List.iter
      (fun c -> Buffer.add_string b (Printf.sprintf "            case 0x%02X:\n" c))
      (List.rev !junk_codes);
    Buffer.add_string b "                std::cerr << \"[VANGUARD-TRAP] Decoy junk opcode caught at runtime: 0x\" << std::hex << opcode << \"\\n\";\n";
    Buffer.add_string b "                trapped = true;\n";
    Buffer.add_string b "                return false;\n";
  end;

  Buffer.add_string b "            default:\n";
  Buffer.add_string b "                std::cerr << \"[VANGUARD-TRAP] Unmapped opcode caught: 0x\" << std::hex << opcode << \"\\n\";\n";
  Buffer.add_string b "                trapped = true;\n";
  Buffer.add_string b "                return false;\n";
  Buffer.add_string b "        }\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "};\n\n";
  Buffer.add_string b "} // namespace vanguard_vm\n";
  Buffer.contents b

let split_tokens str =
  let parts = ref [] in
  let buf = Buffer.create 16 in
  let push () =
    if Buffer.length buf > 0 then begin
      parts := Buffer.contents buf :: !parts;
      Buffer.clear buf
    end
  in
  for i = 0 to String.length str - 1 do
    let c = str.[i] in
    if c = ' ' || c = '\t' || c = ',' then push ()
    else Buffer.add_char buf c
  done;
  push ();
  List.rev !parts

let parse_reg reg_str =
  let s = String.trim (String.lowercase_ascii reg_str) in
  let body =
    if String.length s > 0 && (s.[0] = 'v' || s.[0] = 'x') then
      String.sub s 1 (String.length s - 1)
    else s
  in
  match int_of_string_opt body with
  | Some idx when idx >= 0 && idx <= 31 -> Ok idx
  | _ -> Error (Printf.sprintf "Invalid register '%s'" reg_str)

let parse_imm imm_str =
  match int_of_string_opt (String.trim imm_str) with
  | Some v -> Ok v
  | None -> Error (Printf.sprintf "Invalid immediate '%s'" imm_str)

let strip_comments line =
  let rec find_comment i =
    if i >= String.length line then String.length line
    else if line.[i] = '#' then i
    else if i + 1 < String.length line && line.[i] = '/' && line.[i + 1] = '/' then i
    else find_comment (i + 1)
  in
  String.trim (String.sub line 0 (find_comment 0))

let assemble_program (t : t) (spec : Vector_isa_spec.t) source_text =
  let key = Rolling_key.make ~seed:t.key_seed in
  let lines = String.split_on_char '\n' source_text in
  let rec loop line_no acc = function
    | [] -> Ok (List.rev acc)
    | raw_line :: rest ->
        let line = strip_comments raw_line in
        if line = "" || String.ends_with ~suffix:":" line then
          loop (line_no + 1) acc rest
        else
          match split_tokens line with
          | [] -> loop (line_no + 1) acc rest
          | mnem_raw :: operands -> (
              let mnem = String.lowercase_ascii mnem_raw in
              match Vector_isa_spec.get_by_mnemonic spec mnem with
              | None -> Error (Printf.sprintf "Line %d: Unknown instruction '%s'" line_no mnem_raw)
              | Some inst -> (
                  let mask = ref true in
                  let ops = ref operands in
                  if !ops <> [] then begin
                    let last = String.lowercase_ascii (List.hd (List.rev !ops)) in
                    if last = "v0.t" || last = "masked" then begin
                      mask := false;
                      let rec drop_last = function [] | [ _ ] -> [] | x :: xs -> x :: drop_last xs in
                      ops := drop_last !ops
                    end
                  end;
                  let parse_ops =
                    match inst.format with
                    | Types.Instruction_format.OP_VV
                    | Types.Instruction_format.OP_RED
                    | Types.Instruction_format.OP_WIDENING -> (
                        match !ops with
                        | [ d; s2; s1 ] -> (
                            match parse_reg d, parse_reg s2, parse_reg s1 with
                            | Ok rd, Ok rs2, Ok rs1 -> Ok (rd, rs1, rs2, 0)
                            | Error e, _, _ | _, Error e, _ | _, _, Error e -> Error e)
                        | _ -> Error (Printf.sprintf "Line %d: %s expects 3 operands" line_no mnem))
                    | Types.Instruction_format.OP_VX -> (
                        match !ops with
                        | [ d; s2; s1 ] -> (
                            match parse_reg d, parse_reg s2, parse_reg s1 with
                            | Ok rd, Ok rs2, Ok rs1 -> Ok (rd, rs1, rs2, 0)
                            | Error e, _, _ | _, Error e, _ | _, _, Error e -> Error e)
                        | _ -> Error (Printf.sprintf "Line %d: %s expects 3 operands" line_no mnem))
                    | Types.Instruction_format.OP_VI -> (
                        match !ops with
                        | [ d; s2; imm_str ] -> (
                            match parse_reg d, parse_reg s2, parse_imm imm_str with
                            | Ok rd, Ok rs2, Ok imm -> Ok (rd, 0, rs2, imm)
                            | Error e, _, _ | _, Error e, _ | _, _, Error e -> Error e)
                        | _ -> Error (Printf.sprintf "Line %d: %s expects vd, vs2, simm" line_no mnem))
                    | Types.Instruction_format.OP_MVV -> (
                        match !ops with
                        | [ d; s2 ] -> (
                            match parse_reg d, parse_reg s2 with
                            | Ok rd, Ok rs2 -> Ok (rd, 0, rs2, 0)
                            | Error e, _ | _, Error e -> Error e)
                        | _ -> Error (Printf.sprintf "Line %d: %s expects vd, vs2" line_no mnem))
                    | _ -> Error (Printf.sprintf "Line %d: Unsupported format" line_no)
                  in
                  match parse_ops with
                  | Error err -> Error err
                  | Ok (dst, src1, src2, imm) -> (
                      match encode_word t ~mnemonic:inst.mnemonic ~dst ~src1 ~src2 ~imm ~mask:!mask ~key with
                      | Error err -> Error (Printf.sprintf "Line %d: %s" line_no err)
                      | Ok word -> loop (line_no + 1) (word :: acc) rest)))
  in
  loop 1 [] lines

let write_bytecode_file words filepath =
  try
    let oc = open_out_bin filepath in
    List.iter
      (fun w ->
        for byte_idx = 0 to 7 do
          let shift = byte_idx * 8 in
          let b = Int64.to_int (Int64.logand (Int64.shift_right_logical w shift) 0xFFL) in
          output_byte oc b
        done)
      words;
    close_out oc;
    Ok filepath
  with exn ->
    Error (Printf.sprintf "Failed to write bytecode to %s: %s" filepath (Printexc.to_string exn))

let read_bytecode_file filepath =
  try
    let ic = open_in_bin filepath in
    let len = in_channel_length ic in
    let bytes = really_input_string ic len in
    close_in ic;
    let count = len / 8 in
    let words = ref [] in
    for i = 0 to count - 1 do
      let offset = i * 8 in
      let w = ref 0L in
      for byte_idx = 0 to 7 do
        let b = Int64.of_int (Char.code bytes.[offset + byte_idx]) in
        w := Int64.logor !w (Int64.shift_left b (byte_idx * 8))
      done;
      words := !w :: !words
    done;
    Ok (List.rev !words)
  with exn ->
    Error (Printf.sprintf "Failed to read bytecode from %s: %s" filepath (Printexc.to_string exn))
