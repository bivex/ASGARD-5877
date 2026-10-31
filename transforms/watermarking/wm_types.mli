(* ASGARD-5877: Build-Seed Watermarking Types & Cryptographic Derivation (HKDF-SHA256) *)

type watermark_id = {
  raw_bits       : int64;
  derivation_key : int64;
}

type wm_scheme = {
  payload_bits    : int;
  redundancy      : int;
  total_wm_points : int;
}

val default_scheme : wm_scheme

val hkdf_extract : salt:bytes -> ikm:bytes -> bytes

val hkdf_expand : prk:bytes -> info:bytes -> out_len:int -> bytes

val hkdf_sha256 : ?salt:bytes -> ikm:bytes -> info:bytes -> out_len:int -> unit -> bytes

val derive : build_seed:int64 -> client_payload:int64 -> watermark_id

val bytes_of_int64 : int64 -> bytes
val int64_of_bytes : bytes -> int -> int64
