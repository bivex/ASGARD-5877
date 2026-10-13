open Alcotest
open Bytecode_crypto

let test_sha256_canonical_vectors () =
  (* Vector 1: Empty string *)
  let h_empty = Sha256.hexdigest (Sha256.digest_string "") in
  check string "SHA-256 empty string"
    "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" h_empty;

  (* Vector 2: 'abc' *)
  let h_abc = Sha256.hexdigest (Sha256.digest_string "abc") in
  check string "SHA-256 'abc'"
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad" h_abc;

  (* Vector 3: 'The quick brown fox jumps over the lazy dog' *)
  let fox = "The quick brown fox jumps over the lazy dog" in
  let h_fox = Sha256.hexdigest (Sha256.digest_string fox) in
  check string "SHA-256 fox"
    "d7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592" h_fox

let test_hmac_sha256_rfc4231_vectors () =
  (* RFC 4231 Test Case 1: Key = 20x 0x0b, Data = 'Hi There' *)
  let key1 = Bytes.make 20 '\x0b' in
  let data1 = Bytes.of_string "Hi There" in
  let mac1 = Hmac_sha256.digest ~key:key1 ~data:data1 in
  let h_mac1 = Sha256.hexdigest mac1 in
  check string "RFC 4231 Test Case 1"
    "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7" h_mac1;
  check bool "RFC 4231 verify valid" true
    (Hmac_sha256.verify ~key:key1 ~data:data1 ~expected_mac:mac1);

  (* Altered data should fail verification *)
  let data1_tampered = Bytes.of_string "Hi where" in
  check bool "RFC 4231 verify rejects tampering" false
    (Hmac_sha256.verify ~key:key1 ~data:data1_tampered ~expected_mac:mac1);

  (* RFC 4231 Test Case 2: Key = 'Jefe', Data = 'what do ya want for nothing?' *)
  let key2 = Bytes.of_string "Jefe" in
  let data2 = Bytes.of_string "what do ya want for nothing?" in
  let mac2 = Hmac_sha256.digest ~key:key2 ~data:data2 in
  let h_mac2 = Sha256.hexdigest mac2 in
  check string "RFC 4231 Test Case 2"
    "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843" h_mac2

let test_block_key_kdf_determinism () =
  let master = Bytes.of_string "0123456789abcdef0123456789abcdef" in
  let k0_a = Block_key_kdf.derive_block_key ~master_key:master ~block_id:0 ~block_offset:0 in
  let k0_b = Block_key_kdf.derive_block_key ~master_key:master ~block_id:0 ~block_offset:0 in
  check int64 "Block 0 KDF determinism" k0_a k0_b;

  let k1 = Block_key_kdf.derive_block_key ~master_key:master ~block_id:1 ~block_offset:64 in
  check bool "Block 0 vs Block 1 distinct keys" true (k0_a <> k1);

  (* Word masks within a block are position-dependent and distinct *)
  let m0 = Block_key_kdf.derive_word_mask ~block_key:k0_a ~word_index_in_block:0 in
  let m1 = Block_key_kdf.derive_word_mask ~block_key:k0_a ~word_index_in_block:1 in
  check bool "Word masks are position-dependent" true (m0 <> m1)

let test_payload_seal_and_unpack_roundtrip () =
  let master_key = Bytes.of_string "SUPER_SECRET_ASGARD_MASTER_KEY_32" in
  let blocks = [
    (0, [ 0x1122334455667788L; 0x42L; 0x1337L ]);
    (1, [ 0xAABBCCDDEEFF0011L; 0x5877L ]);
    (2, [ 0xDEADBEEFCAFEBABEL ]);
  ] in
  let sealed = Bytecode_payload.seal_program ~master_key ~module_name:"AuthCheck" ~blocks in
  match Bytecode_payload.verify_and_unpack ~master_key ~module_name:"AuthCheck" ~payload_bytes:sealed.serialized_blob with
  | Error err -> fail ("Unpack failed: " ^ Bytecode_payload.error_to_string err)
  | Ok auth ->
      check int "Total blocks match" 3 auth.total_blocks;
      check int "Total words match" 6 (List.length auth.code_words);
      let expected_words = [
        0x1122334455667788L; 0x42L; 0x1337L;
        0xAABBCCDDEEFF0011L; 0x5877L;
        0xDEADBEEFCAFEBABEL;
      ] in
      List.iter2 (fun exp act -> check int64 "Plain word match" exp act) expected_words auth.code_words

let test_payload_tamper_detection_fail_closed () =
  let master_key = Bytes.of_string "SUPER_SECRET_ASGARD_MASTER_KEY_32" in
  let blocks = [ (0, [ 0x10L; 0x20L; 0x30L ]) ] in
  let sealed = Bytecode_payload.seal_program ~master_key ~module_name:"License" ~blocks in

  (* Case 1: Corrupted master key *)
  let wrong_key = Bytes.of_string "WRONG_SECRET_ASGARD_MASTER_KEY_32" in
  (match Bytecode_payload.verify_and_unpack ~master_key:wrong_key ~module_name:"License" ~payload_bytes:sealed.serialized_blob with
   | Error Bytecode_payload.AuthenticationFailed -> ()
   | _ -> fail "Expected AuthenticationFailed on wrong key");

  (* Case 2: Cross-module confusion (wrong module name in AAD) *)
  (match Bytecode_payload.verify_and_unpack ~master_key ~module_name:"OtherModule" ~payload_bytes:sealed.serialized_blob with
   | Error Bytecode_payload.AuthenticationFailed -> ()
   | _ -> fail "Expected AuthenticationFailed on module name mismatch");

  (* Case 3: Single bit flip in ciphertext *)
  let tampered_blob = Bytes.copy sealed.serialized_blob in
  let last_idx = Bytes.length tampered_blob - 1 in
  let original_byte = Char.code (Bytes.get tampered_blob last_idx) in
  Bytes.set tampered_blob last_idx (Char.chr (original_byte lxor 0x01));
  (match Bytecode_payload.verify_and_unpack ~master_key ~module_name:"License" ~payload_bytes:tampered_blob with
   | Error Bytecode_payload.AuthenticationFailed -> ()
   | _ -> fail "Expected AuthenticationFailed on ciphertext bit-flip");

  (* Case 4: Truncated payload *)
  let truncated_blob = Bytes.sub sealed.serialized_blob 0 (Bytes.length sealed.serialized_blob - 4) in
  (match Bytecode_payload.verify_and_unpack ~master_key ~module_name:"License" ~payload_bytes:truncated_blob with
   | Error (Bytecode_payload.TruncatedPayload _) -> ()
   | _ -> fail "Expected TruncatedPayload error");

  (* Case 5: Bad magic *)
  let bad_magic_blob = Bytes.copy sealed.serialized_blob in
  Bytes.set bad_magic_blob 0 '\x00';
  (match Bytecode_payload.verify_and_unpack ~master_key ~module_name:"License" ~payload_bytes:bad_magic_blob with
   | Error (Bytecode_payload.BadMagic _) -> ()
   | _ -> fail "Expected BadMagic error")

let tests = [
  ("SHA-256 Canonical Vectors", `Quick, test_sha256_canonical_vectors);
  ("HMAC-SHA256 RFC 4231 Vectors", `Quick, test_hmac_sha256_rfc4231_vectors);
  ("Block Key KDF Determinism", `Quick, test_block_key_kdf_determinism);
  ("Bytecode Payload Seal & Unpack Roundtrip", `Quick, test_payload_seal_and_unpack_roundtrip);
  ("Bytecode Payload Tamper Fail-Closed", `Quick, test_payload_tamper_detection_fail_closed);
]
