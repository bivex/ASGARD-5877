#pragma once
// HARDENED TECH-2601 SHADOW UNWIND & MEMORY ZEROIZATION ENGINE (P0-02 & P2-02 FIX)
#include <cstdint>
#include <cstddef>
#include <atomic>

namespace asgard::tech_2601 {

constexpr size_t MAX_SHADOW_FRAMES = 64;

struct alignas(64) ShadowFrame {
    uintptr_t vm_entry_sp;
    uintptr_t handler_landing_pad;
    void*     sensitive_ctx_ptr;
    size_t    sensitive_ctx_size;
    uint64_t  frame_cookie;
    uint32_t  active;
};

struct ThreadShadowStack {
    ShadowFrame frames[MAX_SHADOW_FRAMES]{};
    size_t      depth = 0;
};

inline ThreadShadowStack& get_tls_shadow_stack() noexcept {
    thread_local ThreadShadowStack tls_stack{};
    return tls_stack;
}

inline void secure_zeroize(void* ptr, size_t len) noexcept {
    if (!ptr || len == 0) return;
    volatile uint8_t* p = static_cast<volatile uint8_t*>(ptr);
    while (len--) {
        *p++ = 0;
    }
    std::atomic_signal_fence(std::memory_order_seq_cst);
}

inline bool push_shadow_frame(
    uintptr_t entry_sp,
    uintptr_t landing_pad,
    void*     ctx_ptr,
    size_t    ctx_size,
    uint64_t  cookie
) noexcept {
    auto& st = get_tls_shadow_stack();
    if (st.depth >= MAX_SHADOW_FRAMES) return false;
    st.frames[st.depth] = ShadowFrame{
        entry_sp, landing_pad, ctx_ptr, ctx_size, cookie, 1U
    };
    ++st.depth;
    return true;
}

inline uintptr_t tech_2601_rollback_stack(uintptr_t current_sp, uint64_t expected_cookie) noexcept {
    auto& st = get_tls_shadow_stack();
    uintptr_t resolved_pad = 0;
    size_t matched_idx = MAX_SHADOW_FRAMES;

    // Constant-time scan across all slots to eliminate timing side-channels
    for (size_t i = 0; i < MAX_SHADOW_FRAMES; ++i) {
        const uint64_t is_active = st.frames[i].active;
        const uint64_t sp_match  = (st.frames[i].vm_entry_sp >= current_sp);
        const uint64_t ck_match  = (st.frames[i].frame_cookie == expected_cookie);
        const uintptr_t mask     = -static_cast<uintptr_t>(is_active & sp_match & ck_match);

        resolved_pad = (resolved_pad & ~mask) | (st.frames[i].handler_landing_pad & mask);
        if (mask != 0) {
            matched_idx = i;
        }
    }

    if (matched_idx < MAX_SHADOW_FRAMES) {
        for (size_t j = matched_idx; j < st.depth && j < MAX_SHADOW_FRAMES; ++j) {
            secure_zeroize(st.frames[j].sensitive_ctx_ptr, st.frames[j].sensitive_ctx_size);
            st.frames[j].active = 0;
        }
        st.depth = matched_idx;
    }
    return resolved_pad;
}

} // namespace asgard::tech_2601
