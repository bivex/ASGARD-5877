(** ASGARD-5877: Build-Seed Watermarking Types & Cryptographic Derivation (HKDF-SHA256) *)

type watermark_id = {
  raw_bits       : int64;
  derivation_key : int64;
}

type wm_scheme = {
  payload_bits    : int;
  redundancy      : int;
  total_wm_points : int;
}

let default_scheme : wm_scheme = {
  payload_bits = 48;
  redundancy = 7;
  total_wm_points = 48 * 7; (* 336 points *)
}

let bytes_of_int64 (v : int64) : bytes =
  let b = Bytes.create 8 in
  for i = 0 to 7 do
    let shift = (7 - i) * 8 in
    let byte_val = Int64.to_int (Int64.logand (Int64.shift_right_logical v shift) 0xFFL) in
    Bytes.set b i (Char.chr byte_val)
  done;
  b

let int64_of_bytes (b : bytes) (offset : int) : int64 =
  let v = ref 0L in
  for i = 0 to 7 do
    let byte_val = Int64.of_int (Char.code (Bytes.get b (offset + i))) in
    v := Int64.logor (Int64.shift_left !v 8) byte_val
  done;
  !v

(* RFC 5869 HKDF-Extract(salt, IKM) -> PRK *)
let hkdf_extract ~(salt : bytes) ~(ikm : bytes) : bytes =
  let salt' =
    if Bytes.length salt = 0 then Bytes.make 32 '\000'
    else salt
  in
  Bytecode_crypto.Hmac_sha256.digest ~key:salt' ~data:ikm

(* RFC 5869 HKDF-Expand(PRK, info, L) -> OKM *)
let hkdf_expand ~(prk : bytes) ~(info : bytes) ~(out_len : int) : bytes =
  if out_len <= 0 then Bytes.empty
  else
    let hash_len = 32 in
    let n = (out_len + hash_len - 1) / hash_len in
    if n > 255 then failwith "hkdf_expand: out_len exceeds maximum limit"
    else
      let okm = Bytes.create (n * hash_len) in
      let prev_t = ref Bytes.empty in
      for i = 1 to n do
        let buf = Bytes.create (Bytes.length !prev_t + Bytes.length info + 1) in
        Bytes.blit !prev_t 0 buf 0 (Bytes.length !prev_t);
        Bytes.blit info 0 buf (Bytes.length !prev_t) (Bytes.length info);
        Bytes.set buf (Bytes.length buf - 1) (Char.chr i);
        let ti = Bytecode_crypto.Hmac_sha256.digest ~key:prk ~data:buf in
        Bytes.blit ti 0 okm ((i - 1) * hash_len) hash_len;
        prev_t := ti
      done;
      Bytes.sub okm 0 out_len

let hkdf_sha256 ?(salt = Bytes.empty) ~(ikm : bytes) ~(info : bytes) ~(out_len : int) () : bytes =
  let prk = hkdf_extract ~salt ~ikm in
  hkdf_expand ~prk ~info ~out_len

let derive ~(build_seed : int64) ~(client_payload : int64) : watermark_id =
  let ikm = bytes_of_int64 build_seed in
  let salt = bytes_of_int64 client_payload in
  let info = Bytes.of_string "asgard-wm-v1" in
  let okm = hkdf_sha256 ~salt ~ikm ~info ~out_len:8 () in
  let derivation_key = int64_of_bytes okm 0 in
  {
    raw_bits = client_payload;
    derivation_key;
  }
