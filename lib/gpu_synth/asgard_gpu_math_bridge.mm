#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <iostream>
#include <vector>
#include <iomanip>

static const char* METAL_MATH_SOURCE = R"(
#include <metal_stdlib>
using namespace metal;

static inline uint32_t gpu_rol32(uint32_t x, int r) {
    r &= 31;
    return (x << r) | (x >> (32 - r));
}

static inline uint32_t gpu_ror32(uint32_t x, int r) {
    r &= 31;
    return (x >> r) | (x << (32 - r));
}

static inline void speck64_round_gpu(thread uint32_t& x, thread uint32_t& y, uint32_t k) {
    x = (gpu_ror32(x, 8) + y) ^ k;
    y = gpu_rol32(y, 3) ^ x;
}

// Compute SAC matrix across 65,536 parallel GPU threads
kernel void gpu_compute_sac_matrix_kernel(
    device const uint32_t* speck_keys [[buffer(0)]],
    device atomic_uint*    sac_counts [[buffer(1)]],
    uint id [[thread_position_in_grid]])
{
    // Generate pseudorandom 64-bit block (l0, r0)
    uint64_t seed = (uint64_t)id * 0x9E3779B97F4A7C15ULL + 0x13375877ULL;
    uint32_t l0 = (uint32_t)(seed >> 32);
    uint32_t r0 = (uint32_t)seed;

    uint32_t cl = l0;
    uint32_t cr = r0;
    for (int r = 0; r < 8; ++r) {
        speck64_round_gpu(cl, cr, speck_keys[r]);
    }

    // For every bit i in 1..64, flip and count diffusion
    for (int in_bit = 0; in_bit < 64; ++in_bit) {
        uint32_t ml0 = l0;
        uint32_t mr0 = r0;
        if (in_bit < 32) {
            ml0 ^= (1U << in_bit);
        } else {
            mr0 ^= (1U << (in_bit - 32));
        }

        uint32_t mcl = ml0;
        uint32_t mcr = mr0;
        for (int r = 0; r < 8; ++r) {
            speck64_round_gpu(mcl, mcr, speck_keys[r]);
        }

        uint32_t diff_l = cl ^ mcl;
        uint32_t diff_r = cr ^ mcr;

        for (int out_bit = 0; out_bit < 32; ++out_bit) {
            if ((diff_l >> out_bit) & 1) {
                atomic_fetch_add_explicit(&sac_counts[in_bit * 64 + out_bit], 1, memory_order_relaxed);
            }
            if ((diff_r >> out_bit) & 1) {
                atomic_fetch_add_explicit(&sac_counts[in_bit * 64 + (out_bit + 32)], 1, memory_order_relaxed);
            }
        }
    }
}
)";

int main(int argc, char** argv) {
    @autoreleasepool {
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        if (!device) {
            std::cout << "STATUS=ERROR_NO_GPU\n";
            return 1;
        }

        id<MTLCommandQueue> queue = [device newCommandQueue];
        NSError* error = nil;
        NSString* src = [NSString stringWithUTF8String:METAL_MATH_SOURCE];
        MTLCompileOptions* opts = [[MTLCompileOptions alloc] init];
        opts.languageVersion = MTLLanguageVersion3_0;

        id<MTLLibrary> lib = [device newLibraryWithSource:src options:opts error:&error];
        if (!lib) {
            std::cout << "STATUS=ERROR_COMPILE\n";
            return 1;
        }

        id<MTLFunction> fn_sac = [lib newFunctionWithName:@"gpu_compute_sac_matrix_kernel"];
        id<MTLComputePipelineState> pipe_sac = [device newComputePipelineStateWithFunction:fn_sac error:&error];

        const uint32_t NUM_THREADS = 65536;
        uint32_t keys[8] = { 305419896, 2309737967, 3735928559, 3405691582, 123456789, 987654321, 2863311530, 1431655765 };
        id<MTLBuffer> buf_keys = [device newBufferWithBytes:keys length:sizeof(keys) options:MTLResourceStorageModeShared];

        size_t matrix_size = 64 * 64 * sizeof(uint32_t);
        id<MTLBuffer> buf_sac = [device newBufferWithLength:matrix_size options:MTLResourceStorageModeShared];
        memset([buf_sac contents], 0, matrix_size);

        id<MTLCommandBuffer> cmd = [queue commandBuffer];
        id<MTLComputeCommandEncoder> enc = [cmd computeCommandEncoder];

        [enc setComputePipelineState:pipe_sac];
        [enc setBuffer:buf_keys offset:0 atIndex:0];
        [enc setBuffer:buf_sac offset:0 atIndex:1];

        MTLSize grid = MTLSizeMake(NUM_THREADS, 1, 1);
        NSUInteger tg_size = pipe_sac.maxTotalThreadsPerThreadgroup;
        if (tg_size > 256) tg_size = 256;
        MTLSize threadgroup = MTLSizeMake(tg_size, 1, 1);

        [enc dispatchThreads:grid threadsPerThreadgroup:threadgroup];
        [enc endEncoding];
        [cmd commit];
        [cmd waitUntilCompleted];

        uint32_t* counts = (uint32_t*)[buf_sac contents];
        double total_p = 0.0;
        double max_p = 0.0;
        double min_p = 1.0;
        double mean_dev = 0.0;

        for (int i = 0; i < 64 * 64; ++i) {
            double p = (double)counts[i] / (double)NUM_THREADS;
            total_p += p;
            if (p > max_p) max_p = p;
            if (p < min_p) min_p = p;
            mean_dev += std::abs(p - 0.5);
        }

        double mean_sac = (total_p / 4096.0) * 100.0;
        mean_dev = mean_dev / 4096.0;

        std::cout << std::fixed << std::setprecision(4);
        std::cout << "STATUS=OK\n";
        std::cout << "GPU_DEVICE=" << [[device name] UTF8String] << "\n";
        std::cout << "GPU_THREADS=" << NUM_THREADS << "\n";
        std::cout << "GPU_SAC_MEAN=" << mean_sac << "\n";
        std::cout << "GPU_SAC_DEV=" << mean_dev << "\n";
        std::cout << "GPU_DP_MIN=" << min_p << "\n";
        std::cout << "GPU_DP_MAX=" << max_p << "\n";
        return 0;
    }
}
