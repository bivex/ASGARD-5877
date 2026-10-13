let phi64 = 0x9E3779B97F4A7C15L

let splitmix64 (v : int64) : int64 =
  let z = Int64.add v phi64 in
  let z = Int64.mul (Int64.logxor z (Int64.shift_right_logical z 30)) 0xBF58476D1CE4E5B9L in
  let z = Int64.mul (Int64.logxor z (Int64.shift_right_logical z 27)) 0x94D049BB133111EBL in
  Int64.logxor z (Int64.shift_right_logical z 31)

let derive_block_key ~master_key ~block_id ~block_offset : int64 =
  let info = Bytes.make 24 '\000' in
  Bytes.blit_string "ASG_BLK_KDF\x00" 0 info 0 12;
  (* uint32 block_id *)
  let bid = Int32.of_int block_id in
  for i = 0 to 3 do
    let b = Int32.to_int (Int32.logand (Int32.shift_right_logical bid (i * 8)) 0xFFl) in
    Bytes.set info (12 + i) (Char.chr b)
  done;
  (* uint64 block_offset *)
  let boff = Int64.of_int block_offset in
  for i = 0 to 7 do
    let b = Int64.to_int (Int64.logand (Int64.shift_right_logical boff (i * 8)) 0xFFL) in
    Bytes.set info (16 + i) (Char.chr b)
  done;
  let mac = Hmac_sha256.digest ~key:master_key ~data:info in
  (* Extract first 8 bytes as 64-bit integer *)
  let w = ref 0L in
  for i = 0 to 7 do
    let b = Int64.of_int (Char.code (Bytes.get mac i)) in
    w := Int64.logor !w (Int64.shift_left b (i * 8))
  done;
  !w

let derive_word_mask ~block_key ~word_index_in_block : int64 =
  let step = Int64.mul (Int64.of_int word_index_in_block) phi64 in
  splitmix64 (Int64.logxor block_key step)

let derive_module_aad ~module_name ~version ~total_blocks ~code_size_bytes : bytes =
  let name_bytes = Bytes.of_string module_name in
  let name_len = Bytes.length name_bytes in
  let buf = Buffer.create (32 + name_len) in
  Buffer.add_string buf "ASG_MOD_AAD\x01";
  Buffer.add_int32_le buf (Int32.of_int version);
  Buffer.add_int32_le buf (Int32.of_int total_blocks);
  Buffer.add_int64_le buf (Int64.of_int code_size_bytes);
  Buffer.add_int32_le buf (Int32.of_int name_len);
  Buffer.add_bytes buf name_bytes;
  Buffer.to_bytes buf
