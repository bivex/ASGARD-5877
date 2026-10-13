type payload_error =
  | BadMagic of int32
  | UnsupportedVersion of int32
  | TruncatedPayload of { expected : int; actual : int }
  | AuthenticationFailed
  | CorruptedBlockTable of string

let error_to_string = function
  | BadMagic m -> Printf.sprintf "Invalid payload magic: 0x%08lx (expected 0x5877CAFE)" m
  | UnsupportedVersion v -> Printf.sprintf "Unsupported payload format version: %ld (expected 1)" v
  | TruncatedPayload { expected; actual } ->
      Printf.sprintf "Truncated bytecode payload: expected at least %d bytes, got %d" expected actual
  | AuthenticationFailed ->
      "Bytecode authentication failed: HMAC-SHA256 signature mismatch (tampering/corruption detected)"
  | CorruptedBlockTable msg -> Printf.sprintf "Corrupted block topology table: %s" msg

type block_desc = {
  block_id : int;
  word_offset : int;
  word_count : int;
}

type sealed_payload = {
  header_bytes : bytes;
  block_table_bytes : bytes;
  code_bytes : bytes;
  auth_tag : bytes;
  serialized_blob : bytes;
}

type authenticated_payload = {
  module_name : string;
  version : int;
  total_blocks : int;
  blocks : block_desc list;
  code_words : int64 list;
}

let magic_constant = 0x5877CAFEl
let current_version = 1l

let read_u32_le b off =
  let b0 = Int32.of_int (Char.code (Bytes.get b off)) in
  let b1 = Int32.of_int (Char.code (Bytes.get b (off + 1))) in
  let b2 = Int32.of_int (Char.code (Bytes.get b (off + 2))) in
  let b3 = Int32.of_int (Char.code (Bytes.get b (off + 3))) in
  let open Int32 in
  logor (logor b0 (shift_left b1 8)) (logor (shift_left b2 16) (shift_left b3 24))

let write_u32_le b off (v : int32) =
  for i = 0 to 3 do
    let byte_val = Int32.to_int (Int32.logand (Int32.shift_right_logical v (i * 8)) 0xFFl) in
    Bytes.set b (off + i) (Char.chr byte_val)
  done

let read_u64_le b off =
  let w = ref 0L in
  for i = 0 to 7 do
    let byte_val = Int64.of_int (Char.code (Bytes.get b (off + i))) in
    w := Int64.logor !w (Int64.shift_left byte_val (i * 8))
  done;
  !w

let write_u64_le b off (v : int64) =
  for i = 0 to 7 do
    let byte_val = Int64.to_int (Int64.logand (Int64.shift_right_logical v (i * 8)) 0xFFL) in
    Bytes.set b (off + i) (Char.chr byte_val)
  done

let seal_program
    ~(master_key : bytes)
    ~(module_name : string)
    ~(blocks : (int * int64 list) list) : sealed_payload =
  let total_blocks = List.length blocks in
  let total_words = List.fold_left (fun acc (_, ws) -> acc + List.length ws) 0 blocks in
  let code_size_bytes = total_words * 8 in

  (* 1. Encrypt words with topological block keys *)
  let cipher_words = ref [] in
  let block_descs = ref [] in
  let current_word_offset = ref 0 in

  List.iter (fun (b_id, words) ->
    let w_count = List.length words in
    let b_byte_offset = !current_word_offset * 8 in
    let b_key = Block_key_kdf.derive_block_key ~master_key ~block_id:b_id ~block_offset:b_byte_offset in
    let enc_words = List.mapi (fun j plain_w ->
      let mask = Block_key_kdf.derive_word_mask ~block_key:b_key ~word_index_in_block:j in
      Int64.logxor plain_w mask
    ) words in
    cipher_words := !cipher_words @ enc_words;
    block_descs := !block_descs @ [ { block_id = b_id; word_offset = !current_word_offset; word_count = w_count } ];
    current_word_offset := !current_word_offset + w_count
  ) blocks;

  (* 2. Build code bytes *)
  let code_bytes = Bytes.make code_size_bytes '\000' in
  List.iteri (fun i w -> write_u64_le code_bytes (i * 8) w) !cipher_words;

  (* 3. Build block table bytes: each entry is 12 bytes: id (4), offset (4), count (4) *)
  let table_bytes = Bytes.make (total_blocks * 12) '\000' in
  List.iteri (fun i desc ->
    let off = i * 12 in
    write_u32_le table_bytes off (Int32.of_int desc.block_id);
    write_u32_le table_bytes (off + 4) (Int32.of_int desc.word_offset);
    write_u32_le table_bytes (off + 8) (Int32.of_int desc.word_count)
  ) !block_descs;

  (* 4. Build header: magic (4), version (4), total_blocks (4), total_words (4), code_size (8) = 24 bytes *)
  let header_bytes = Bytes.make 24 '\000' in
  write_u32_le header_bytes 0 magic_constant;
  write_u32_le header_bytes 4 current_version;
  write_u32_le header_bytes 8 (Int32.of_int total_blocks);
  write_u32_le header_bytes 12 (Int32.of_int total_words);
  write_u64_le header_bytes 16 (Int64.of_int code_size_bytes);

  (* 5. Derive AAD and authenticate *)
  let aad = Block_key_kdf.derive_module_aad ~module_name ~version:1 ~total_blocks ~code_size_bytes in
  let auth_data = Bytes.concat Bytes.empty [ header_bytes; table_bytes; code_bytes; aad ] in
  let auth_tag = Hmac_sha256.digest ~key:master_key ~data:auth_data in

  (* 6. Final serialized blob: Header (24) + Tag (32) + BlockTable (total_blocks * 12) + CodeBytes *)
  let serialized_blob = Bytes.concat Bytes.empty [ header_bytes; auth_tag; table_bytes; code_bytes ] in
  {
    header_bytes;
    block_table_bytes = table_bytes;
    code_bytes;
    auth_tag;
    serialized_blob;
  }

let verify_and_unpack
    ~(master_key : bytes)
    ~(module_name : string)
    ~(payload_bytes : bytes) : (authenticated_payload, payload_error) result =
  let total_len = Bytes.length payload_bytes in
  if total_len < 56 then (* 24 header + 32 tag *)
    Error (TruncatedPayload { expected = 56; actual = total_len })
  else
    let magic = read_u32_le payload_bytes 0 in
    if magic <> magic_constant then
      Error (BadMagic magic)
    else
      let ver = read_u32_le payload_bytes 4 in
      if ver <> current_version then
        Error (UnsupportedVersion ver)
      else
        let total_blocks = Int32.to_int (read_u32_le payload_bytes 8) in
        let total_words = Int32.to_int (read_u32_le payload_bytes 12) in
        let code_size_bytes = Int64.to_int (read_u64_le payload_bytes 16) in
        let table_len = total_blocks * 12 in
        let expected_total_len = 24 + 32 + table_len + code_size_bytes in
        if total_len <> expected_total_len then
          Error (TruncatedPayload { expected = expected_total_len; actual = total_len })
        else
          let header_bytes = Bytes.sub payload_bytes 0 24 in
          let expected_tag = Bytes.sub payload_bytes 24 32 in
          let table_bytes = Bytes.sub payload_bytes 56 table_len in
          let code_bytes = Bytes.sub payload_bytes (56 + table_len) code_size_bytes in

          (* Check HMAC-SHA256 signature in constant time *)
          let aad = Block_key_kdf.derive_module_aad ~module_name ~version:1 ~total_blocks ~code_size_bytes in
          let auth_data = Bytes.concat Bytes.empty [ header_bytes; table_bytes; code_bytes; aad ] in
          if not (Hmac_sha256.verify ~key:master_key ~data:auth_data ~expected_mac:expected_tag) then
            Error AuthenticationFailed
          else
            (* Unpack and decrypt block words *)
            let block_descs = ref [] in
            let valid = ref true in
            for i = 0 to total_blocks - 1 do
              let off = i * 12 in
              let b_id = Int32.to_int (read_u32_le table_bytes off) in
              let w_off = Int32.to_int (read_u32_le table_bytes (off + 4)) in
              let w_cnt = Int32.to_int (read_u32_le table_bytes (off + 8)) in
              if w_off + w_cnt > total_words then valid := false
              else block_descs := !block_descs @ [ { block_id = b_id; word_offset = w_off; word_count = w_cnt } ]
            done;
            if not !valid then
              Error (CorruptedBlockTable "Block offsets exceed total words boundary")
            else
              let plain_words = Array.make total_words 0L in
              List.iter (fun desc ->
                let b_key = Block_key_kdf.derive_block_key ~master_key ~block_id:desc.block_id ~block_offset:(desc.word_offset * 8) in
                for j = 0 to desc.word_count - 1 do
                  let enc_w = read_u64_le code_bytes ((desc.word_offset + j) * 8) in
                  let mask = Block_key_kdf.derive_word_mask ~block_key:b_key ~word_index_in_block:j in
                  plain_words.(desc.word_offset + j) <- Int64.logxor enc_w mask
                done
              ) !block_descs;
              Ok {
                module_name;
                version = Int32.to_int ver;
                total_blocks;
                blocks = !block_descs;
                code_words = Array.to_list plain_words;
              }
