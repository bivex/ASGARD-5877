let block_size = 64

let digest ~key ~data =
  let key_len = Bytes.length key in
  let norm_key =
    if key_len > block_size then
      let hashed = Sha256.digest_bytes key in
      let k = Bytes.make block_size '\000' in
      Bytes.blit hashed 0 k 0 32;
      k
    else if key_len < block_size then
      let k = Bytes.make block_size '\000' in
      Bytes.blit key 0 k 0 key_len;
      k
    else
      Bytes.copy key
  in
  let k_ipad = Bytes.make block_size '\000' in
  let k_opad = Bytes.make block_size '\000' in
  for i = 0 to block_size - 1 do
    let b = Char.code (Bytes.get norm_key i) in
    Bytes.set k_ipad i (Char.chr (b lxor 0x36));
    Bytes.set k_opad i (Char.chr (b lxor 0x5c))
  done;

  let inner_msg = Bytes.concat Bytes.empty [ k_ipad; data ] in
  let inner_hash = Sha256.digest_bytes inner_msg in

  let outer_msg = Bytes.concat Bytes.empty [ k_opad; inner_hash ] in
  Sha256.digest_bytes outer_msg

let verify ~key ~data ~expected_mac =
  let computed = digest ~key ~data in
  Sha256.constant_time_equal computed expected_mac
