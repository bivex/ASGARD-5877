#ifndef ASGARD_METAL_RUNTIME_H
#define ASGARD_METAL_RUNTIME_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

int asgard_gpu_is_available(void);
int asgard_gpu_synthesize_mba(uint64_t target_val, uint64_t* out_results, uint32_t max_results, uint32_t* out_count);
int asgard_gpu_batch_encrypt(const uint64_t* in_bytecode, size_t code_len, const uint64_t* build_keys, size_t num_builds, uint64_t* out_bytecode);
int asgard_gpu_verify_sac(const uint64_t* matrix_16x16, uint32_t num_trials, double* out_sac);

#ifdef __cplusplus
}
#endif

#endif
