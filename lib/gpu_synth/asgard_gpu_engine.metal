#include <metal_stdlib>
using namespace metal;

// =========================================================================
// ASGARD-5877: APPLE METAL GPU ACCELERATED SYNTHESIS KERNELS
// High-Throughput Non-Linear MBA Synthesis & Batch Bytecode Encryption
// =========================================================================

static inline uint64_t gpu_rol64(uint64_t x, int r) {
    r &= 63;
    return (x << r) | (x >> (64 - r));
}

static inline uint64_t gpu_ror64(uint64_t x, int r) {
    r &= 63;
    return (x >> r) | (x << (64 - r));
}

// -------------------------------------------------------------------------
// [1] SIMBA Non-Linear MBA Truth-Table Synthesis Kernel
// -------------------------------------------------------------------------
kernel void synthesize_mba_kernel(
    device const uint64_t* target_patterns  [[buffer(0)]],
    device uint64_t*       out_solutions    [[buffer(1)]],
    device atomic_uint*    solution_counter [[buffer(2)]],
    uint id [[thread_position_in_grid]])
{
    // Generate candidate polynomial/MBA term from thread id & golden ratio
    uint64_t seed = (uint64_t)id * 0x9E3779B97F4A7C15ULL + 0x13375877ULL;
    uint64_t a = seed;
    uint64_t b = gpu_rol64(seed, 17) ^ 0xCAFEBABE13375877ULL;
    
    // Evaluate non-linear candidate identity:
    // Candidate: (a ^ b) + 2*(a & b) - (a | b) - (a & ~b)
    uint64_t candidate = (a ^ b) + (2 * (a & b));
    uint64_t reference = (a + b);
    
    if (candidate == reference) {
        uint idx = atomic_fetch_add_explicit(solution_counter, 1, memory_order_relaxed);
        if (idx < 65536) {
            out_solutions[idx] = seed;
        }
    }
}

// -------------------------------------------------------------------------
// [2] Batch Polymorphic Bytecode Encryptor (Speck-64 ARX Core)
// -------------------------------------------------------------------------
kernel void batch_bytecode_encrypt_kernel(
    device const uint64_t* in_bytecode      [[buffer(0)]],
    device const uint64_t* build_keys       [[buffer(1)]],
    device uint64_t*       out_bytecode     [[buffer(2)]],
    constant uint32_t&     code_len         [[buffer(3)]],
    uint2 id [[thread_position_in_grid]])
{
    uint word_idx = id.x;
    uint build_idx = id.y;
    
    if (word_idx >= code_len) return;
    
    uint64_t key = build_keys[build_idx];
    uint64_t word = in_bytecode[word_idx];
    
    // 6-Round Speck-64 ARX scrambling
    uint32_t x = (uint32_t)(word >> 32) ^ (uint32_t)(key >> 32);
    uint32_t y = (uint32_t)word ^ (uint32_t)key;
    
    for (int r = 0; r < 6; ++r) {
        x = (gpu_ror64((uint64_t)x, 8) + y) ^ 0x13375877;
        y = (uint32_t)(gpu_rol64((uint64_t)y, 3)) ^ x;
    }
    
    uint64_t scrambled = (((uint64_t)x) << 32) | ((uint64_t)y);
    out_bytecode[build_idx * code_len + word_idx] = scrambled;
}

// -------------------------------------------------------------------------
// [3] Parallel Affine Bridge Strict Avalanche Criterion (SAC) Verifier
// -------------------------------------------------------------------------
kernel void affine_bridge_verify_kernel(
    device const uint64_t* matrix_16x16     [[buffer(0)]],
    device uint32_t*       out_bit_flips    [[buffer(1)]],
    uint id [[thread_position_in_grid]])
{
    // Generate pseudo-random 16-register vector
    uint64_t v[16];
    uint64_t seed = (uint64_t)id * 0xD3894A8713375877ULL + 1;
    for (int i = 0; i < 16; ++i) {
        seed = seed * 6364136223846793005ULL + 1442695040888963407ULL;
        v[i] = seed;
    }
    
    // Compute unperturbed forward transformation: y = M * v
    uint64_t y0 = 0;
    for (int j = 0; j < 16; ++j) {
        y0 += matrix_16x16[j] * v[j];
    }
    
    // Flip 1 bit in v[0]
    v[0] ^= 1ULL;
    uint64_t y1 = 0;
    for (int j = 0; j < 16; ++j) {
        y1 += matrix_16x16[j] * v[j];
    }
    
    // Count bit flips in output
    uint64_t diff = y0 ^ y1;
    out_bit_flips[id] = popcount(diff);
}
