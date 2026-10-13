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
  (* 1. Материализация в 128-байтный слот *)
  let active_slot =
    xor_bytes_with_stream ticket.encrypted_bytes ~key:master_key ~nonce:ticket.stream_nonce
  in
  let materialized_snapshot = Bytes.copy active_slot in
  (* 2. Эпилог блока: принудительная перезапись слота криптографической гаммой (Self-Wipe) *)
  let wiped_slot =
    xor_bytes_with_stream active_slot ~key:ticket.wipe_gamma ~nonce:(neg ticket.stream_nonce)
  in
  (* Гарантируем, что исходный буфер затерт и не совпадает с открытым кодом *)
  Bytes.blit wiped_slot 0 active_slot 0 (Bytes.length active_slot);
  (materialized_snapshot, active_slot)

let emit_self_wiping_nano_jit_hpp () : string =
{|#pragma once
// AUTO-GENERATED SINGLE-BLOCK SELF-WIPING NANO-JIT ENGINE (STEP 5 TIER-4+)
#include <cstdint>
#include <cstddef>
#include <atomic>

namespace asgard::nano_jit {

constexpr size_t NANO_SLOT_SIZE = 128;

struct alignas(64) EphemeralSlot {
    uint64_t code_words[NANO_SLOT_SIZE / sizeof(uint64_t)];
};

__attribute__((always_inline)) inline uint64_t splitmix_stream(uint64_t key, uint64_t nonce, size_t idx) noexcept {
    uint64_t z = key + (nonce ^ (idx * 0x9E3779B97F4A7C15ULL));
    z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ULL;
    z = (z ^ (z >> 27)) * 0x94D049BB133111EBULL;
    return z ^ (z >> 31);
}

// Материализует ровно один базовый блок в 128-байтный буфер перед прыжком
__attribute__((always_inline)) inline void materialize_nano_block(
    EphemeralSlot& slot,
    const uint64_t* encrypted_words,
    size_t word_count,
    uint64_t master_key,
    uint64_t nonce
) noexcept {
    volatile uint64_t* dst = slot.code_words;
    for (size_t i = 0; i < word_count && i < 16; ++i) {
        dst[i] = encrypted_words[i] ^ splitmix_stream(master_key, nonce, i);
    }
    std::atomic_signal_fence(std::memory_order_seq_cst);
}

// Вызывается немедленно при выходе из блока: перезаписывает машинный код шумом
__attribute__((always_inline)) inline void wipe_nano_block(
    EphemeralSlot& slot,
    uint64_t wipe_gamma
) noexcept {
    volatile uint64_t* dst = slot.code_words;
    for (size_t i = 0; i < 16; ++i) {
        dst[i] = splitmix_stream(wipe_gamma, i, i ^ 0x5877ULL);
    }
    std::atomic_signal_fence(std::memory_order_seq_cst);
}

} // namespace asgard::nano_jit
|}
