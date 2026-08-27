#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include "metal_runtime.h"
#include <iostream>

static id<MTLDevice> g_device = nil;
static id<MTLCommandQueue> g_queue = nil;
static id<MTLComputePipelineState> g_pipe_mba = nil;
static id<MTLComputePipelineState> g_pipe_encrypt = nil;
static id<MTLComputePipelineState> g_pipe_sac = nil;
static bool g_initialized = false;

static const char* METAL_SOURCE = R"(
#include <metal_stdlib>
using namespace metal;

static inline uint64_t gpu_rol64(uint64_t x, int r) {
    r &= 63;
    return (x << r) | (x >> (64 - r));
}

static inline uint64_t gpu_ror64(uint64_t x, int r) {
    r &= 63;
    return (x >> r) | (x << (64 - r));
}

kernel void synthesize_mba_kernel(
    device const uint64_t* target_patterns  [[buffer(0)]],
    device uint64_t*       out_solutions    [[buffer(1)]],
    device atomic_uint*    solution_counter [[buffer(2)]],
    uint id [[thread_position_in_grid]])
{
    uint64_t seed = (uint64_t)id * 0x9E3779B97F4A7C15ULL + 0x13375877ULL;
    uint64_t a = seed;
    uint64_t b = gpu_rol64(seed, 17) ^ 0xCAFEBABE13375877ULL;
    
    uint64_t candidate = (a ^ b) + (2 * (a & b));
    uint64_t reference = (a + b);
    
    if (candidate == reference) {
        uint idx = atomic_fetch_add_explicit(solution_counter, 1, memory_order_relaxed);
        if (idx < 65536) {
            out_solutions[idx] = seed;
        }
    }
}

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
    
    uint32_t x = (uint32_t)(word >> 32) ^ (uint32_t)(key >> 32);
    uint32_t y = (uint32_t)word ^ (uint32_t)key;
    
    for (int r = 0; r < 6; ++r) {
        x = (gpu_ror64((uint64_t)x, 8) + y) ^ 0x13375877;
        y = (uint32_t)(gpu_rol64((uint64_t)y, 3)) ^ x;
    }
    
    uint64_t scrambled = (((uint64_t)x) << 32) | ((uint64_t)y);
    out_bytecode[build_idx * code_len + word_idx] = scrambled;
}

kernel void affine_bridge_verify_kernel(
    device const uint64_t* matrix_16x16     [[buffer(0)]],
    device uint32_t*       out_bit_flips    [[buffer(1)]],
    uint id [[thread_position_in_grid]])
{
    uint64_t v[16];
    uint64_t seed = (uint64_t)id * 0xD3894A8713375877ULL + 1;
    for (int i = 0; i < 16; ++i) {
        seed = seed * 6364136223846793005ULL + 1442695040888963407ULL;
        v[i] = seed;
    }
    
    uint64_t y0 = 0;
    for (int j = 0; j < 16; ++j) {
        y0 += matrix_16x16[j] * v[j];
    }
    
    v[0] ^= 1ULL;
    uint64_t y1 = 0;
    for (int j = 0; j < 16; ++j) {
        y1 += matrix_16x16[j] * v[j];
    }
    
    uint64_t diff = y0 ^ y1;
    out_bit_flips[id] = popcount(diff);
}
)";

static bool init_metal(void) {
    if (g_initialized) return (g_device != nil);
    g_initialized = true;

    @autoreleasepool {
        g_device = MTLCreateSystemDefaultDevice();
        if (!g_device) return false;

        g_queue = [g_device newCommandQueue];
        if (!g_queue) return false;

        NSError* error = nil;
        NSString* src = [NSString stringWithUTF8String:METAL_SOURCE];
        MTLCompileOptions* opts = [[MTLCompileOptions alloc] init];
        opts.languageVersion = MTLLanguageVersion3_0;

        id<MTLLibrary> lib = [g_device newLibraryWithSource:src options:opts error:&error];
        if (!lib) {
            NSLog(@"[ASGARD-GPU] Metal compilation error: %@", error);
            return false;
        }

        id<MTLFunction> fn_mba = [lib newFunctionWithName:@"synthesize_mba_kernel"];
        id<MTLFunction> fn_enc = [lib newFunctionWithName:@"batch_bytecode_encrypt_kernel"];
        id<MTLFunction> fn_sac = [lib newFunctionWithName:@"affine_bridge_verify_kernel"];

        if (fn_mba) g_pipe_mba = [g_device newComputePipelineStateWithFunction:fn_mba error:&error];
        if (fn_enc) g_pipe_encrypt = [g_device newComputePipelineStateWithFunction:fn_enc error:&error];
        if (fn_sac) g_pipe_sac = [g_device newComputePipelineStateWithFunction:fn_sac error:&error];

        return (g_pipe_mba != nil && g_pipe_encrypt != nil && g_pipe_sac != nil);
    }
}

extern "C" int asgard_gpu_is_available(void) {
    return init_metal() ? 1 : 0;
}

extern "C" int asgard_gpu_synthesize_mba(uint64_t target_val, uint64_t* out_results, uint32_t max_results, uint32_t* out_count) {
    if (!init_metal()) return -1;
    
    @autoreleasepool {
        const uint32_t num_threads = 65536;
        id<MTLBuffer> buf_target = [g_device newBufferWithBytes:&target_val length:sizeof(uint64_t) options:MTLResourceStorageModeShared];
        id<MTLBuffer> buf_out = [g_device newBufferWithLength:max_results * sizeof(uint64_t) options:MTLResourceStorageModeShared];
        
        uint32_t init_cnt = 0;
        id<MTLBuffer> buf_cnt = [g_device newBufferWithBytes:&init_cnt length:sizeof(uint32_t) options:MTLResourceStorageModeShared];

        id<MTLCommandBuffer> cmd = [g_queue commandBuffer];
        id<MTLComputeCommandEncoder> enc = [cmd computeCommandEncoder];

        [enc setComputePipelineState:g_pipe_mba];
        [enc setBuffer:buf_target offset:0 atIndex:0];
        [enc setBuffer:buf_out offset:0 atIndex:1];
        [enc setBuffer:buf_cnt offset:0 atIndex:2];

        MTLSize grid = MTLSizeMake(num_threads, 1, 1);
        NSUInteger tg_size = g_pipe_mba.maxTotalThreadsPerThreadgroup;
        if (tg_size > 256) tg_size = 256;
        MTLSize threadgroup = MTLSizeMake(tg_size, 1, 1);

        [enc dispatchThreads:grid threadsPerThreadgroup:threadgroup];
        [enc endEncoding];
        [cmd commit];
        [cmd waitUntilCompleted];

        uint32_t found = *(uint32_t*)[buf_cnt contents];
        if (found > max_results) found = max_results;
        *out_count = found;
        
        memcpy(out_results, [buf_out contents], found * sizeof(uint64_t));
        return 0;
    }
}

extern "C" int asgard_gpu_batch_encrypt(
    const uint64_t* in_bytecode,
    size_t code_len,
    const uint64_t* build_keys,
    size_t num_builds,
    uint64_t* out_bytecode)
{
    if (!init_metal()) return -1;

    @autoreleasepool {
        size_t bc_bytes = code_len * sizeof(uint64_t);
        size_t keys_bytes = num_builds * sizeof(uint64_t);
        size_t total_out_bytes = code_len * num_builds * sizeof(uint64_t);

        id<MTLBuffer> buf_in = [g_device newBufferWithBytes:in_bytecode length:bc_bytes options:MTLResourceStorageModeShared];
        id<MTLBuffer> buf_keys = [g_device newBufferWithBytes:build_keys length:keys_bytes options:MTLResourceStorageModeShared];
        id<MTLBuffer> buf_out = [g_device newBufferWithLength:total_out_bytes options:MTLResourceStorageModeShared];
        
        uint32_t clen = (uint32_t)code_len;
        id<MTLBuffer> buf_len = [g_device newBufferWithBytes:&clen length:sizeof(uint32_t) options:MTLResourceStorageModeShared];

        id<MTLCommandBuffer> cmd = [g_queue commandBuffer];
        id<MTLComputeCommandEncoder> enc = [cmd computeCommandEncoder];

        [enc setComputePipelineState:g_pipe_encrypt];
        [enc setBuffer:buf_in offset:0 atIndex:0];
        [enc setBuffer:buf_keys offset:0 atIndex:1];
        [enc setBuffer:buf_out offset:0 atIndex:2];
        [enc setBuffer:buf_len offset:0 atIndex:3];

#include <algorithm>

        MTLSize grid = MTLSizeMake(code_len, num_builds, 1);
        MTLSize threadgroup = MTLSizeMake(std::min((size_t)64, code_len), 1, 1);

        [enc dispatchThreads:grid threadsPerThreadgroup:threadgroup];
        [enc endEncoding];
        [cmd commit];
        [cmd waitUntilCompleted];

        memcpy(out_bytecode, [buf_out contents], total_out_bytes);
        return 0;
    }
}

extern "C" int asgard_gpu_verify_sac(const uint64_t* matrix_16x16, uint32_t num_trials, double* out_sac) {
    if (!init_metal()) return -1;

    @autoreleasepool {
        id<MTLBuffer> buf_mat = [g_device newBufferWithBytes:matrix_16x16 length:16 * sizeof(uint64_t) options:MTLResourceStorageModeShared];
        id<MTLBuffer> buf_flips = [g_device newBufferWithLength:num_trials * sizeof(uint32_t) options:MTLResourceStorageModeShared];

        id<MTLCommandBuffer> cmd = [g_queue commandBuffer];
        id<MTLComputeCommandEncoder> enc = [cmd computeCommandEncoder];

        [enc setComputePipelineState:g_pipe_sac];
        [enc setBuffer:buf_mat offset:0 atIndex:0];
        [enc setBuffer:buf_flips offset:0 atIndex:1];

        MTLSize grid = MTLSizeMake(num_trials, 1, 1);
        NSUInteger tg_size = g_pipe_sac.maxTotalThreadsPerThreadgroup;
        if (tg_size > 256) tg_size = 256;
        MTLSize threadgroup = MTLSizeMake(tg_size, 1, 1);

        [enc dispatchThreads:grid threadsPerThreadgroup:threadgroup];
        [enc endEncoding];
        [cmd commit];
        [cmd waitUntilCompleted];

        uint32_t* flips = (uint32_t*)[buf_flips contents];
        uint64_t total_flips = 0;
        for (uint32_t i = 0; i < num_trials; ++i) {
            total_flips += flips[i];
        }

        // Expected bits flipped out of 64
        *out_sac = ((double)total_flips / (double)(num_trials * 64)) * 100.0;
        return 0;
    }
}
