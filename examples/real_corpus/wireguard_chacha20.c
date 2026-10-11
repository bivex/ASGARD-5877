#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <time.h>
#include "asgard_obf.h"

/*
 * Production ChaCha20 Block Function (RFC 8439 / WireGuard / OpenSSL)
 * Authentic cryptographic primitives:
 *   - 16-word state matrix (4 constants, 8 key words, 1 counter, 3 nonce words)
 *   - Quarter-round ARX operations: add, xor, rol (16, 12, 8, 7)
 *   - 20 rounds (10 column rounds + 10 diagonal rounds)
 *   - Keystream block state summation
 */

#define ROTL32(v, n) (((v) << (n)) | ((v) >> (32 - (n))))

#define CHACHA20_QUARTERROUND(a, b, c, d) \
    do { \
        a += b; d ^= a; d = ROTL32(d, 16); \
        c += d; b ^= c; b = ROTL32(b, 12); \
        a += b; d ^= a; d = ROTL32(d, 8);  \
        c += d; b ^= c; b = ROTL32(b, 7);  \
    } while (0)

void wireguard_chacha20_block(uint32_t out[16], const uint32_t key[8], uint32_t counter, const uint32_t nonce[3]) {
    ASGARD_BEGIN_ULTRA("WireGuard_ChaCha20_Block");

    uint32_t state[16];
    state[0]  = 0x61707865U; /* "expa" */
    state[1]  = 0x3320646eU; /* "nd 3" */
    state[2]  = 0x79622d32U; /* "2-by" */
    state[3]  = 0x6b206574U; /* "te k" */
    state[4]  = key[0];
    state[5]  = key[1];
    state[6]  = key[2];
    state[7]  = key[3];
    state[8]  = key[4];
    state[9]  = key[5];
    state[10] = key[6];
    state[11] = key[7];
    state[12] = counter;
    state[13] = nonce[0];
    state[14] = nonce[1];
    state[15] = nonce[2];

    uint32_t x[16];
    for (int i = 0; i < 16; i++) {
        x[i] = state[i];
    }

    /* 10 double rounds = 20 rounds */
    for (int r = 0; r < 10; r++) {
        /* Column rounds */
        CHACHA20_QUARTERROUND(x[0], x[4], x[8],  x[12]);
        CHACHA20_QUARTERROUND(x[1], x[5], x[9],  x[13]);
        CHACHA20_QUARTERROUND(x[2], x[6], x[10], x[14]);
        CHACHA20_QUARTERROUND(x[3], x[7], x[11], x[15]);

        /* Diagonal rounds */
        CHACHA20_QUARTERROUND(x[0], x[5], x[10], x[15]);
        CHACHA20_QUARTERROUND(x[1], x[6], x[11], x[12]);
        CHACHA20_QUARTERROUND(x[2], x[7], x[8],  x[13]);
        CHACHA20_QUARTERROUND(x[3], x[4], x[9],  x[14]);
    }

    /* Add original state */
    for (int i = 0; i < 16; i++) {
        out[i] = x[i] + state[i];
    }

    ASGARD_END();
}

int main(int argc, char** argv) {
    int iterations = 100;
    if (argc > 1) {
        int parsed = 0;
        for (const char* p = argv[1]; *p >= '0' && *p <= '9'; ++p) {
            parsed = parsed * 10 + (*p - '0');
        }
        if (parsed > 0) iterations = parsed;
    }

    /*
     * Standard RFC 8439 Section 2.3.2 Test Vector:
     * Key: 00:01:02:03:04:05:06:07:08:09:0a:0b:0c:0d:0e:0f:10:11:12:13:14:15:16:17:18:19:1a:1b:1c:1d:1e:1f
     * Nonce: 00:00:00:09:00:00:00:4a:00:00:00:00
     * Counter: 1
     * Expected first 4 words of block:
     * 0xe4e7f110, 0x15593bd1, 0x1fdd0f50, 0xc47120a3
     */
    static const uint32_t test_key[8] = {
        0x03020100U, 0x07060504U, 0x0b0a0908U, 0x0f0e0d0cU,
        0x13121110U, 0x17161514U, 0x1b1a1918U, 0x1f1e1d1cU
    };
    static const uint32_t test_nonce[3] = {
        0x09000000U, 0x4a000000U, 0x00000000U
    };

    uint32_t block_out[16];
    memset(block_out, 0, sizeof(block_out));

    /* 1. Verification Pass */
    wireguard_chacha20_block(block_out, test_key, 1, test_nonce);

    int ok = (block_out[0] == 0xe4e7f110U &&
              block_out[1] == 0x15593bd1U &&
              block_out[2] == 0x1fdd0f50U &&
              block_out[3] == 0xc47120a3U);

    /* 2. Timed Workload */
    struct timespec ts0, ts1;
    clock_gettime(CLOCK_MONOTONIC, &ts0);

    uint32_t running_state[16];
    memcpy(running_state, block_out, sizeof(running_state));

    for (int it = 0; it < iterations; it++) {
        uint32_t dynamic_key[8];
        for (int k = 0; k < 8; k++) {
            dynamic_key[k] = test_key[k] ^ (uint32_t)it;
        }
        wireguard_chacha20_block(running_state, dynamic_key, (uint32_t)(it + 1), test_nonce);
    }

    clock_gettime(CLOCK_MONOTONIC, &ts1);
    uint64_t elapsed_ns = (uint64_t)(ts1.tv_sec - ts0.tv_sec) * 1000000000ULL +
                          (uint64_t)(ts1.tv_nsec - ts0.tv_nsec);
    uint64_t elapsed_us = elapsed_ns / 1000ULL;

    printf("[BENCHMARK] Suite: WireGuard & RFC 8439 Cryptography\n");
    printf("[BENCHMARK] Target: ChaCha20 Stream Cipher Block Transform\n");
    printf("[BENCHMARK] Iterations: %d\n", iterations);
    printf("[BENCHMARK] Elapsed: %llu us\n", (unsigned long long)elapsed_us);
    printf("[BENCHMARK] Final Word0: 0x%08X\n", running_state[0]);
    printf("[BENCHMARK] Verification: %s\n", ok ? "PASS" : "FAIL");

    return ok ? 0 : 1;
}
