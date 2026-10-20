open Int64

type nano_block_ticket = {
  block_id        : int;
  encrypted_bytes : bytes;
  stream_nonce    : int64;
  wipe_gamma      : int64;
}

let keystream_word (key : int64) (nonce : int64) (word_idx : int) : int64 =
  let z = add key ( logxor nonce (mul (of_int word_idx) 0x9E3779B97F4A7C15L) ) in
  let z = mul (logxor z (shift_right_logical z 30)) 0xBF58476D1CE4E5B9L in
  let z = mul (logxor z (shift_right_logical z 27)) 0x94D049BB133111EBL in
  logxor z (shift_right_logical z 31)

let xor_bytes_with_stream (src : bytes) ~(key : int64) ~(nonce : int64) : bytes =
  let len = Bytes.length src in
  let dst = Bytes.create len in
  for i = 0 to len - 1 do
    let ks = keystream_word key nonce (i / 8) in
    let byte_mask = to_int (logand (shift_right_logical ks ((i mod 8) * 8)) 0xFFL) in
    let b = Char.code (Bytes.get src i) lxor byte_mask in
    Bytes.set dst i (Char.chr b)
  done;
  dst

let seal_nano_block ~(block_id : int) ~(raw_code : bytes) ~(master_key : int64) ~(nonce : int64)
    : nano_block_ticket =
  let len = Bytes.length raw_code in
  if len > 128 then
    invalid_arg "Nano_jit_slot.seal_nano_block: block exceeds 128-byte single-slot limit";
  let encrypted_bytes = xor_bytes_with_stream raw_code ~key:master_key ~nonce in
  let wipe_gamma = keystream_word master_key nonce 0x5877 in
  { block_id; encrypted_bytes; stream_nonce = nonce; wipe_gamma }

let simulate_nano_slot_lifecycle (ticket : nano_block_ticket) ~(master_key : int64)
    : bytes * bytes =
  (* 1. Materialization into the 128-byte slot *)
  let active_slot =
    xor_bytes_with_stream ticket.encrypted_bytes ~key:master_key ~nonce:ticket.stream_nonce
  in
  let materialized_snapshot = Bytes.copy active_slot in
  (* 2. Block epilogue: forced overwrite of the slot with a cryptographic keystream (Self-Wipe) *)
  let wiped_slot =
    xor_bytes_with_stream active_slot ~key:ticket.wipe_gamma ~nonce:(neg ticket.stream_nonce)
  in
  (* Ensure that the original buffer is wiped and does not match the plaintext code *)
  Bytes.blit wiped_slot 0 active_slot 0 (Bytes.length active_slot);
  (materialized_snapshot, active_slot)

open Cpp_codegen.Cpp_ast
open Cpp_codegen.Cpp_dsl

let build_nano_jit_slot_ast () : top_decl list =
  let splitmix_fn = FuncDecl {
    attrs    = [AlwaysInline; NoExcept];
    ret_type = UInt64;
    name     = "splitmix_stream";
    params   = [(UInt64, "key"); (UInt64, "nonce"); (SizeT, "idx")];
    body     = [
      let_u64 "z" (var "key" +~ (var "nonce" ^~ (var "idx" *~ u64 0x9E3779B97F4A7C15L)));
      var "z" := (var "z" ^~ (var "z" >>~ u64 30L)) *~ u64 0xBF58476D1CE4E5B9L;
      var "z" := (var "z" ^~ (var "z" >>~ u64 27L)) *~ u64 0x94D049BB133111EBL;
      ret (var "z" ^~ (var "z" >>~ u64 31L));
    ];
  } in

  let materialize_fn = FuncDecl {
    attrs    = [AlwaysInline; NoExcept];
    ret_type = Void;
    name     = "materialize_nano_block";
    params   = [
      (Ref (StructType "EphemeralSlot"), "slot");
      (ConstPtr UInt64, "encrypted_words");
      (SizeT, "word_count");
      (UInt64, "master_key");
      (UInt64, "nonce");
    ];
    body     = [
      decl_var ~is_volatile:true (Ptr UInt64) "dst" ~init:(var "slot" $. "code_words");
      ForRange {
        var_name = "i";
        start_e  = u64 0L;
        limit_e  = ternary (var "word_count" <~ u64 16L) (var "word_count") (u64 16L);
        body     = [
          (idx (var "dst") (var "i")) :=
            ((idx (var "encrypted_words") (var "i")) ^~
             (call "splitmix_stream" [var "master_key"; var "nonce"; var "i"]));
        ];
      };
      FenceSeqCst;
    ];
  } in

  let wipe_fn = FuncDecl {
    attrs    = [AlwaysInline; NoExcept];
    ret_type = Void;
    name     = "wipe_nano_block";
    params   = [
      (Ref (StructType "EphemeralSlot"), "slot");
      (UInt64, "wipe_gamma");
    ];
    body     = [
      decl_var ~is_volatile:true (Ptr UInt64) "dst" ~init:(var "slot" $. "code_words");
      ForRange {
        var_name = "i";
        start_e  = u64 0L;
        limit_e  = u64 16L;
        body     = [
          (idx (var "dst") (var "i")) :=
            (call "splitmix_stream" [var "wipe_gamma"; var "i"; var "i" ^~ u64 0x5877L]);
        ];
      };
      FenceSeqCst;
    ];
  } in

  [
    IncludeSys "cstdint";
    IncludeSys "cstddef";
    IncludeSys "atomic";
    Namespace ("asgard::nano_jit", [
      ConstexprGlobal (SizeT, "NANO_SLOT_SIZE", u64 128L);
      StructDecl {
        align_as = Some 64;
        name     = "EphemeralSlot";
        fields   = [(Array (UInt64, 16), "code_words")];
      };
      splitmix_fn;
      materialize_fn;
      wipe_fn;
    ]);
  ]

let emit_self_wiping_nano_jit_hpp () : string =
  Cpp_codegen.Cpp_printer.render_header_unit (build_nano_jit_slot_ast ())

