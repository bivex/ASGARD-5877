#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <time.h>
#include "asgard_obf.h"

/*
 * Production OpenSSL SHA-256 Block Transform (FIPS 180-4)
 * Authentic cryptographic primitives:
 *   - Round constants K[64]
 *   - Non-linear bitwise logic: Ch, Maj
 *   - Sigma rotations: S0, S1, s0, s1
 */

#define ROR32(x, n) (((x) >> (n)) | ((x) << (32 - (n))))
#define Ch(x, y, z)  (((x) & (y)) ^ (~(x) & (z)))
#define Maj(x, y, z) (((x) & (y)) ^ ((x) & (z)) ^ ((y) & (z)))
#define S0(x) (ROR32(x, 2)  ^ ROR32(x, 13) ^ ROR32(x, 22))
#define S1(x) (ROR32(x, 6)  ^ ROR32(x, 11) ^ ROR32(x, 25))
#define s0(x) (ROR32(x, 7)  ^ ROR32(x, 18) ^ ((x) >> 3))
#define s1(x) (ROR32(x, 17) ^ ROR32(x, 19) ^ ((x) >> 10))

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

void openssl_sha256_transform(uint32_t state[8], const uint8_t data[64]) {
    ASGARD_BEGIN_ULTRA("OpenSSL_SHA256_Block");

    uint32_t a = state[0];
    uint32_t b = state[1];
    uint32_t c = state[2];
    uint32_t d = state[3];
    uint32_t e = state[4];
    uint32_t f = state[5];
    uint32_t g = state[6];
    uint32_t h = state[7];
    uint32_t w[64];

    for (int i = 0; i < 16; i++) {
        w[i] = ((uint32_t)data[i * 4] << 24) |
               ((uint32_t)data[i * 4 + 1] << 16) |
               ((uint32_t)data[i * 4 + 2] << 8) |
               ((uint32_t)data[i * 4 + 3]);
    }
    for (int i = 16; i < 64; i++) {
        w[i] = s1(w[i - 2]) + w[i - 7] + s0(w[i - 15]) + w[i - 16];
    }

    for (int i = 0; i < 64; i++) {
        uint32_t t1 = h + S1(e) + Ch(e, f, g) + K[i] + w[i];
        uint32_t t2 = S0(a) + Maj(a, b, c);
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

    /* Standard NIST FIPS 180-4 Test Vector:
       Input: "The quick brown fox jumps over the lazy dog" (padded into 1 block of 64 bytes)
       Expected digest:
       d7a8fbb3 07d78094 69ca930b 0140da2c d42c94a8 f9d068d7 13500041 b4db9402
    */
    static const uint8_t block[64] = {
        0x54, 0x68, 0x65, 0x20, 0x71, 0x75, 0x69, 0x63,
        0x6b, 0x20, 0x62, 0x72, 0x6f, 0x77, 0x6e, 0x20,
        0x66, 0x6f, 0x78, 0x20, 0x6a, 0x75, 0x6d, 0x70,
        0x73, 0x20, 0x6f, 0x76, 0x65, 0x72, 0x20, 0x74,
        0x68, 0x65, 0x20, 0x6c, 0x61, 0x7a, 0x79, 0x20,
        0x64, 0x6f, 0x67, 0x80, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x58
    };

    uint32_t state[8];
    state[0] = 0x6a09e667;
    state[1] = 0xbb67ae85;
    state[2] = 0x3c6ef372;
    state[3] = 0xa54ff53a;
    state[4] = 0x510e527f;
    state[5] = 0x9b05688c;
    state[6] = 0x1f83d9ab;
    state[7] = 0x5be0cd19;

    /* 1. Run Verification Pass */
    uint8_t work_block[64];
    memcpy(work_block, block, 64);
    openssl_sha256_transform(state, work_block);
    printf("[DEBUG] Verification pass state: %08x %08x %08x %08x %08x %08x %08x %08x\n",
           state[0], state[1], state[2], state[3], state[4], state[5], state[6], state[7]);

    int ok = (state[0] == 0xd7a8fbb3 && state[1] == 0x07d78094 &&
              state[2] == 0x69ca9abc && state[3] == 0xb0082e4f &&
              state[4] == 0x8d5651e4 && state[5] == 0x6d3cdb76 &&
              state[6] == 0x2d02d0bf && state[7] == 0x37c9e592);

    /* 2. Run Timed Workload */
    struct timespec ts0, ts1;
    clock_gettime(CLOCK_MONOTONIC, &ts0);

    for (int it = 0; it < iterations; it++) {
        /* Mutate block slightly to avoid compiler loop dead-stripping */
        work_block[0] ^= (uint8_t)it;
        openssl_sha256_transform(state, work_block);
        work_block[0] ^= (uint8_t)it;
    }

    clock_gettime(CLOCK_MONOTONIC, &ts1);
    uint64_t elapsed_ns = (uint64_t)(ts1.tv_sec - ts0.tv_sec) * 1000000000ULL +
                          (uint64_t)(ts1.tv_nsec - ts0.tv_nsec);
    uint64_t elapsed_us = elapsed_ns / 1000ULL;

    printf("[BENCHMARK] Suite: OpenSSL Cryptographic Core\n");
    printf("[BENCHMARK] Target: SHA-256 FIPS 180-4 Block Transform\n");
    printf("[BENCHMARK] Iterations: %d\n", iterations);
    printf("[BENCHMARK] Elapsed: %llu us\n", (unsigned long long)elapsed_us);
    printf("[BENCHMARK] Digest: %08X%08X%08X%08X\n", state[0], state[1], state[2], state[3]);
    printf("[BENCHMARK] Verification: %s\n", ok ? "PASS" : "FAIL");

    return ok ? 0 : 1;
}
