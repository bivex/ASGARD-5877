#pragma once
// ============================================================================
// ASGARD-5877 Vanguard Runtime: Memory Sanitization & Anti-Forensics
// Ephemeral Memory Scrubbing, Rolling Noise Invalidation, Canary Verification
// ============================================================================

#include "platform_compat.hpp"

#ifndef ASGARD_SANITIZATION_DEFINED
#define ASGARD_SANITIZATION_DEFINED

#define SCRUB_WORD(ptr, val) do { \
    *(reinterpret_cast<volatile uint64_t*>(ptr)) = (val); \
} while(0)

namespace asgard_sanitization {

static inline void scrub_memory_range(volatile uint64_t* ptr, size_t count, uint64_t noise_seed) noexcept {
    if (!ptr || count == 0) return;
    for (size_t i = 0; i < count; ++i) {
        ptr[i] = (noise_seed * 0x6A09E667F3BCC908ULL) ^ 0x5877CAFE1337BEEFULL ^ (uint64_t)i;
    }
}

static inline void ephemeral_wipe_buffer(void* ptr, size_t byte_count) noexcept {
    if (!ptr || byte_count == 0) return;
    volatile uint8_t* p = reinterpret_cast<volatile uint8_t*>(ptr);
    for (size_t i = 0; i < byte_count; ++i) {
        p[i] = static_cast<uint8_t>(0x5A ^ ((i * 37 + 0x7F) & 0xFF));
    }
    for (size_t i = 0; i < byte_count; ++i) {
        p[i] = 0;
    }
}

} // namespace asgard_sanitization

#endif // ASGARD_SANITIZATION_DEFINED
