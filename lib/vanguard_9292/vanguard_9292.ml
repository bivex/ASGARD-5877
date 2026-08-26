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
  type t = { seed : int32; mutable state : int32 }

  let make ~seed =
    let init_state = if seed = 0l then 0x1337BEEFl else seed in
    { seed; state = init_state }

  let next t =
    let open Int32 in
    let x = t.state in
    let x = logxor x (shift_left x 13) in
    let x = logxor x (shift_right_logical x 17) in
    let x = logxor x (shift_left x 5) in
    let next_state = if x = 0l then 0x1337BEEFl else x in
    t.state <- next_state;
    next_state

  let reset t =
    let init_state = if t.seed = 0l then 0x1337BEEFl else t.seed in
    t.state <- init_state
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
