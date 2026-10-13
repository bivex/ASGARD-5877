#ifndef ASGARD_CRYPTO_HPP
#define ASGARD_CRYPTO_HPP

#include <cstdint>
#include <cstddef>
#include <cstring>
#include <vector>

namespace asgard {
namespace crypto {

// Constant-time memory comparison to prevent timing side-channels
inline bool constant_time_memcmp(const uint8_t* a, const uint8_t* b, size_t len) {
    uint8_t diff = 0;
    for (size_t i = 0; i < len; ++i) {
        diff |= (a[i] ^ b[i]);
    }
    return diff == 0;
}

// RFC 6234 compliant SHA-256 implementation
class Sha256 {
private:
    uint32_t state[8];
    uint64_t count;
    uint8_t buffer[64];

    static inline uint32_t rotr(uint32_t x, uint32_t n) {
        return (x >> n) | (x << (32 - n));
    }
    static inline uint32_t choose(uint32_t x, uint32_t y, uint32_t z) {
        return (x & y) ^ (~x & z);
    }
    static inline uint32_t majority(uint32_t x, uint32_t y, uint32_t z) {
        return (x & y) ^ (x & z) ^ (y & z);
    }
    static inline uint32_t big_sigma0(uint32_t x) {
        return rotr(x, 2) ^ rotr(x, 13) ^ rotr(x, 22);
    }
    static inline uint32_t big_sigma1(uint32_t x) {
        return rotr(x, 6) ^ rotr(x, 11) ^ rotr(x, 25);
    }
    static inline uint32_t small_sigma0(uint32_t x) {
        return rotr(x, 7) ^ rotr(x, 18) ^ (x >> 3);
    }
    static inline uint32_t small_sigma1(uint32_t x) {
        return rotr(x, 17) ^ rotr(x, 19) ^ (x >> 10);
    }

    void transform(const uint8_t block[64]) {
        static const uint32_t K[64] = {
            0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
            0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
            0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
            0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
            0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
            0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
            0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
            0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
            0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
            0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
            0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
            0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
            0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
            0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
            0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
            0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
        };

        uint32_t w[64];
        for (int i = 0; i < 16; ++i) {
            w[i] = ((uint32_t)block[i * 4] << 24) |
                   ((uint32_t)block[i * 4 + 1] << 16) |
                   ((uint32_t)block[i * 4 + 2] << 8) |
                   ((uint32_t)block[i * 4 + 3]);
        }
        for (int i = 16; i < 64; ++i) {
            w[i] = small_sigma1(w[i - 2]) + w[i - 7] + small_sigma0(w[i - 15]) + w[i - 16];
        }

        uint32_t a = state[0], b = state[1], c = state[2], d = state[3];
        uint32_t e = state[4], f = state[5], g = state[6], h = state[7];

        for (int i = 0; i < 64; ++i) {
            uint32_t t1 = h + big_sigma1(e) + choose(e, f, g) + K[i] + w[i];
            uint32_t t2 = big_sigma0(a) + majority(a, b, c);
            h = g;
            g = f;
            f = e;
            e = d + t1;
            d = c;
            c = b;
            b = a;
            a = t1 + t2;
        }

        state[0] += a;
        state[1] += b;
        state[2] += c;
        state[3] += d;
        state[4] += e;
        state[5] += f;
        state[6] += g;
        state[7] += h;
    }

public:
    Sha256() { reset(); }

    void reset() {
        state[0] = 0x6a09e667;
        state[1] = 0xbb67ae85;
        state[2] = 0x3c6ef372;
        state[3] = 0xa54ff53a;
        state[4] = 0x510e527f;
        state[5] = 0x9b05688c;
        state[6] = 0x1f83d9ab;
        state[7] = 0x5be0cd19;
        count = 0;
    }

    void update(const uint8_t* data, size_t len) {
        size_t buffer_index = (size_t)(count & 0x3F);
        count += len;

        size_t part_len = 64 - buffer_index;
        size_t i = 0;

        if (len >= part_len) {
            std::memcpy(&buffer[buffer_index], data, part_len);
            transform(buffer);
            for (i = part_len; i + 63 < len; i += 64) {
                transform(&data[i]);
            }
            buffer_index = 0;
        }
        if (i < len) {
            std::memcpy(&buffer[buffer_index], &data[i], len - i);
        }
    }

    void final(uint8_t digest[32]) {
        uint64_t total_bits = count * 8;
        size_t buffer_index = (size_t)(count & 0x3F);
        size_t pad_len = (buffer_index < 56) ? (56 - buffer_index) : (120 - buffer_index);

        uint8_t pad[128];
        pad[0] = 0x80;
        std::memset(&pad[1], 0, pad_len - 1);
        for (int i = 0; i < 8; ++i) {
            pad[pad_len + i] = (uint8_t)((total_bits >> ((7 - i) * 8)) & 0xFF);
        }
        update(pad, pad_len + 8);

        for (int i = 0; i < 8; ++i) {
            digest[i * 4]     = (uint8_t)((state[i] >> 24) & 0xFF);
            digest[i * 4 + 1] = (uint8_t)((state[i] >> 16) & 0xFF);
            digest[i * 4 + 2] = (uint8_t)((state[i] >> 8) & 0xFF);
            digest[i * 4 + 3] = (uint8_t)(state[i] & 0xFF);
        }
    }

    static void hash(const uint8_t* data, size_t len, uint8_t digest[32]) {
        Sha256 ctx;
        ctx.update(data, len);
        ctx.final(digest);
    }
};

// RFC 2104 compliant HMAC-SHA256
class HmacSha256 {
public:
    static void compute(const uint8_t* key, size_t key_len,
                        const uint8_t* data, size_t data_len,
                        uint8_t out[32]) {
        uint8_t norm_key[64];
        std::memset(norm_key, 0, 64);
        if (key_len > 64) {
            Sha256::hash(key, key_len, norm_key);
        } else {
            std::memcpy(norm_key, key, key_len);
        }

        uint8_t k_ipad[64];
        uint8_t k_opad[64];
        for (int i = 0; i < 64; ++i) {
            k_ipad[i] = norm_key[i] ^ 0x36;
            k_opad[i] = norm_key[i] ^ 0x5c;
        }

        uint8_t inner_hash[32];
        Sha256 inner_ctx;
        inner_ctx.update(k_ipad, 64);
        inner_ctx.update(data, data_len);
        inner_ctx.final(inner_hash);

        Sha256 outer_ctx;
        outer_ctx.update(k_opad, 64);
        outer_ctx.update(inner_hash, 32);
        outer_ctx.final(out);
    }

    static bool verify(const uint8_t* key, size_t key_len,
                       const uint8_t* data, size_t data_len,
                       const uint8_t expected_mac[32]) {
        uint8_t computed[32];
        compute(key, key_len, data, data_len, computed);
        return constant_time_memcmp(computed, expected_mac, 32);
    }
};

// Deterministic Topological Block Key Derivation
class BlockKeyKdf {
public:
    static uint64_t derive_block_key(const uint8_t master_key[32],
                                     uint32_t block_id,
                                     uint32_t block_offset) {
        static const char info[] = "ASGARD_BLOCK_KEY";
        uint8_t msg[16 + 8];
        std::memcpy(msg, info, 16);
        for (int i = 0; i < 4; ++i) {
            msg[16 + i] = (uint8_t)((block_id >> ((3 - i) * 8)) & 0xFF);
            msg[20 + i] = (uint8_t)((block_offset >> ((3 - i) * 8)) & 0xFF);
        }
        uint8_t mac[32];
        HmacSha256::compute(master_key, 32, msg, sizeof(msg), mac);
        uint64_t key = 0;
        for (int i = 0; i < 8; ++i) {
            key = (key << 8) | mac[i];
        }
        return key;
    }

    static uint64_t derive_word_mask(uint64_t block_key, uint32_t word_index) {
        uint64_t s = block_key ^ ((uint64_t)word_index * 0x9E3779B97F4A7C15ULL);
        s ^= (s >> 30);
        s *= 0xBF58476D1CE4E5B9ULL;
        s ^= (s >> 27);
        s *= 0x94D049BB133111EBULL;
        s ^= (s >> 31);
        return s;
    }
};

// Fail-Closed Bytecode Payload Container
class BytecodePayload {
public:
    struct Header {
        uint32_t magic;
        uint32_t version;
        uint32_t entry_offset;
        uint32_t block_count;
        uint32_t payload_words;
    };

    struct BlockEntry {
        uint32_t block_id;
        uint32_t word_offset;
        uint32_t word_count;
    };

    static bool verify_and_unpack(const uint8_t master_key[32],
                                  const uint8_t* container_bytes,
                                  size_t container_len,
                                  Header& out_header,
                                  std::vector<BlockEntry>& out_table,
                                  std::vector<uint64_t>& out_decrypted_words) {
        if (container_len < 20 + 32) return false;

        const uint8_t* p = container_bytes;
        out_header.magic = ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) | ((uint32_t)p[2] << 8) | (uint32_t)p[3];
        out_header.version = ((uint32_t)p[4] << 24) | ((uint32_t)p[5] << 16) | ((uint32_t)p[6] << 8) | (uint32_t)p[7];
        out_header.entry_offset = ((uint32_t)p[8] << 24) | ((uint32_t)p[9] << 16) | ((uint32_t)p[10] << 8) | (uint32_t)p[11];
        out_header.block_count = ((uint32_t)p[12] << 24) | ((uint32_t)p[13] << 16) | ((uint32_t)p[14] << 8) | (uint32_t)p[15];
        out_header.payload_words = ((uint32_t)p[16] << 24) | ((uint32_t)p[17] << 16) | ((uint32_t)p[18] << 8) | (uint32_t)p[19];

        // Fail closed if magic or version mismatch
        if (out_header.magic != 0x41534730) return false; // "ASG0"
        if (out_header.version != 1) return false;

        size_t table_len = (size_t)out_header.block_count * 12;
        size_t words_len = (size_t)out_header.payload_words * 8;
        size_t expected_total = 20 + table_len + words_len + 32;
        if (container_len != expected_total) return false;

        // Verify HMAC-SHA256 authenticated tag over all header + data bytes
        const uint8_t* authenticated_data = container_bytes;
        size_t authenticated_len = 20 + table_len + words_len;
        const uint8_t* expected_tag = container_bytes + authenticated_len;

        if (!HmacSha256::verify(master_key, 32, authenticated_data, authenticated_len, expected_tag)) {
            // Tamper detected! Fail closed immediately without decoding instructions.
            return false;
        }

        // Unpack block table
        out_table.resize(out_header.block_count);
        const uint8_t* table_ptr = container_bytes + 20;
        for (uint32_t i = 0; i < out_header.block_count; ++i) {
            const uint8_t* b = table_ptr + (i * 12);
            out_table[i].block_id = ((uint32_t)b[0] << 24) | ((uint32_t)b[1] << 16) | ((uint32_t)b[2] << 8) | (uint32_t)b[3];
            out_table[i].word_offset = ((uint32_t)b[4] << 24) | ((uint32_t)b[5] << 16) | ((uint32_t)b[6] << 8) | (uint32_t)b[7];
            out_table[i].word_count = ((uint32_t)b[8] << 24) | ((uint32_t)b[9] << 16) | ((uint32_t)b[10] << 8) | (uint32_t)b[11];
        }

        // Read encrypted words
        out_decrypted_words.resize(out_header.payload_words);
        const uint8_t* words_ptr = container_bytes + 20 + table_len;
        for (uint32_t i = 0; i < out_header.payload_words; ++i) {
            uint64_t w = 0;
            for (int b = 0; b < 8; ++b) {
                w = (w << 8) | words_ptr[i * 8 + b];
            }
            out_decrypted_words[i] = w;
        }

        // Decrypt blocks using deterministic topological keys
        for (const auto& blk : out_table) {
            uint64_t blk_key = BlockKeyKdf::derive_block_key(master_key, blk.block_id, blk.word_offset);
            for (uint32_t j = 0; j < blk.word_count; ++j) {
                uint32_t idx = blk.word_offset + j;
                if (idx < out_decrypted_words.size()) {
                    uint64_t mask = BlockKeyKdf::derive_word_mask(blk_key, j);
                    out_decrypted_words[idx] ^= mask;
                }
            }
        }

        return true;
    }
};

} // namespace crypto
} // namespace asgard

#endif // ASGARD_CRYPTO_HPP
