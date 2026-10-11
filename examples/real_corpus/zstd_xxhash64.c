#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <time.h>
#include "asgard_obf.h"

/*
 * Production xxHash64 Fast Checksum (Zstandard / RocksDB / Linux Kernel)
 * Authentic algorithms by Yann Collet:
 *   - 5 64-bit prime multipliers (PRIME64_1 .. PRIME64_5)
 *   - 4-way parallel striped accumulation (32-byte chunks)
 *   - Rotational convergence and merge-round folding
 *   - Avalanche finalizer
 */

static const uint64_t PRIME64_1 = 0x9E3779B185EBCA87ULL;
static const uint64_t PRIME64_2 = 0xC2B2AE3D27D4EB4FULL;
static const uint64_t PRIME64_3 = 0x165667B19E3779F9ULL;
static const uint64_t PRIME64_4 = 0x85EBCA77C2B2AE63ULL;
static const uint64_t PRIME64_5 = 0x27D4EB2F165667C5ULL;

static inline __attribute__((always_inline)) uint64_t XXH_rotl64(uint64_t x, int r) {
    return (x << r) | (x >> (64 - r));
}

static inline __attribute__((always_inline)) uint64_t XXH64_round(uint64_t acc, uint64_t input) {
    acc += input * PRIME64_2;
    acc = XXH_rotl64(acc, 31);
    acc *= PRIME64_1;
    return acc;
}

static inline __attribute__((always_inline)) uint64_t XXH64_mergeRound(uint64_t acc, uint64_t val) {
    val = XXH64_round(0, val);
    acc ^= val;
    acc = acc * PRIME64_1 + PRIME64_4;
    return acc;
}

uint64_t zstd_xxhash64(const uint8_t *input, size_t len, uint64_t seed) {
    ASGARD_BEGIN_ULTRA("Zstd_xxHash64_Engine");

    uint64_t h64;
    size_t idx = 0;

    if (len >= 32) {
        size_t limit = len - 32;
        uint64_t v1 = seed + PRIME64_1 + PRIME64_2;
        uint64_t v2 = seed + PRIME64_2;
        uint64_t v3 = seed + 0;
        uint64_t v4 = seed - PRIME64_1;

        while (idx <= limit) {
            uint64_t k1, k2, k3, k4;
            memcpy(&k1, &input[idx], 8);
            memcpy(&k2, &input[idx + 8], 8);
            memcpy(&k3, &input[idx + 16], 8);
            memcpy(&k4, &input[idx + 24], 8);

            v1 = XXH64_round(v1, k1);
            v2 = XXH64_round(v2, k2);
            v3 = XXH64_round(v3, k3);
            v4 = XXH64_round(v4, k4);
            idx += 32;
        }

        h64 = XXH_rotl64(v1, 1) + XXH_rotl64(v2, 7) + XXH_rotl64(v3, 12) + XXH_rotl64(v4, 18);
        h64 = XXH64_mergeRound(h64, v1);
        h64 = XXH64_mergeRound(h64, v2);
        h64 = XXH64_mergeRound(h64, v3);
        h64 = XXH64_mergeRound(h64, v4);
    } else {
        h64 = seed + PRIME64_5;
    }

    h64 += (uint64_t)len;

    while (idx + 8 <= len) {
        uint64_t k1;
        memcpy(&k1, &input[idx], 8);
        k1 = XXH64_round(0, k1);
        h64 ^= k1;
        h64 = XXH_rotl64(h64, 27) * PRIME64_1 + PRIME64_4;
        idx += 8;
    }

    while (idx < len) {
        h64 ^= ((uint64_t)input[idx]) * PRIME64_5;
        h64 = XXH_rotl64(h64, 11) * PRIME64_1;
        idx++;
    }

    /* Avalanche */
    h64 ^= h64 >> 33;
    h64 *= PRIME64_2;
    h64 ^= h64 >> 29;
    h64 *= PRIME64_3;
    h64 ^= h64 >> 32;

    ASGARD_END();
    return h64;
}

int main(int argc, char** argv) {
    int iterations = 200;
    if (argc > 1) {
        int parsed = 0;
        for (const char* p = argv[1]; *p >= '0' && *p <= '9'; ++p) {
            parsed = parsed * 10 + (*p - '0');
        }
        if (parsed > 0) iterations = parsed;
    }

    /*
     * Reference xxHash64 test vector:
     * Empty string "" -> 0xEF46DB3751D8E999
     * 32-byte string "12345678901234567890123456789012" -> 0x40FD1AA52D98274C
     */
    static const uint8_t test_vec32[32] = {
        '1', '2', '3', '4', '5', '6', '7', '8',
        '9', '0', '1', '2', '3', '4', '5', '6',
        '7', '8', '9', '0', '1', '2', '3', '4',
        '5', '6', '7', '8', '9', '0', '1', '2'
    };
    uint64_t hash_empty = zstd_xxhash64(NULL, 0, 0);
    uint64_t hash_32 = zstd_xxhash64(test_vec32, 32, 0);

    int ok = (hash_empty == 0xEF46DB3751D8E999ULL && hash_32 == 0x40FD1AA52D98274CULL);

    /* 2. Timed Workload: 128-byte streaming buffer */
    uint8_t buffer[128];
    for (int i = 0; i < 128; i++) {
        buffer[i] = (uint8_t)(i * 41 + 17);
    }

    struct timespec ts0, ts1;
    clock_gettime(CLOCK_MONOTONIC, &ts0);

    uint64_t running_hash = hash_32;
    for (int it = 0; it < iterations; it++) {
        buffer[0] = (uint8_t)it;
        buffer[15] = (uint8_t)(running_hash & 0xFF);
        running_hash = zstd_xxhash64(buffer, sizeof(buffer), running_hash ^ (uint64_t)it);
    }

    clock_gettime(CLOCK_MONOTONIC, &ts1);
    uint64_t elapsed_ns = (uint64_t)(ts1.tv_sec - ts0.tv_sec) * 1000000000ULL +
                          (uint64_t)(ts1.tv_nsec - ts0.tv_nsec);
    uint64_t elapsed_us = elapsed_ns / 1000ULL;

    printf("[BENCHMARK] Suite: Zstandard Compression & xxHash\n");
    printf("[BENCHMARK] Target: xxHash64 Streaming Checksum Engine\n");
    printf("[BENCHMARK] Iterations: %d\n", iterations);
    printf("[BENCHMARK] Elapsed: %llu us\n", (unsigned long long)elapsed_us);
    printf("[BENCHMARK] Final Hash: 0x%016llX\n", (unsigned long long)running_hash);
    printf("[BENCHMARK] Verification: %s\n", ok ? "PASS" : "FAIL");

    return ok ? 0 : 1;
}
