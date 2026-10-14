#pragma once
// ============================================================================
// ASGARD-5877 Vanguard Runtime: Cryptographic Primitives & Dynamic Resolution
// FNV-1a, Mach-O Dyld Exports Trie Resolver, Dynamic Symbol Decryption
// ============================================================================

#include "platform_compat.hpp"

#ifndef ASGARD_CRYPTO_PRIMITIVES_DEFINED
#define ASGARD_CRYPTO_PRIMITIVES_DEFINED
#define ASGARD_API_HASH_RESOLVER_DEFINED 1

// Constant 32-bit FNV-1a hash
static constexpr inline uint32_t asgard_fnv1a_const(const char* str, uint32_t hash = 0x811C9DC5U) noexcept {
    return (*str == 0) ? hash : asgard_fnv1a_const(str + 1, (hash ^ static_cast<uint8_t>(*str)) * 0x01000193U);
}

static inline int asg_strcmp(const char* s1, const char* s2) noexcept {
    if (!s1 || !s2) return (s1 == s2) ? 0 : (s1 ? 1 : -1);
    while (*s1 && (*s1 == *s2)) { s1++; s2++; }
    return *(const unsigned char*)s1 - *(const unsigned char*)s2;
}

#if defined(__APPLE__) && defined(__MACH__)
static inline uint64_t asg_read_uleb128(const uint8_t** p) noexcept {
    uint64_t result = 0;
    int shift = 0;
    while (1) {
        uint8_t byte = *(*p)++;
        result |= ((uint64_t)(byte & 0x7f)) << shift;
        if ((byte & 0x80) == 0) break;
        shift += 7;
    }
    return result;
}

static inline void* asg_find_sym_in_trie(const uint8_t* trie_base, const uint8_t* node, uint32_t cur_h, uint32_t target_h, uintptr_t base) noexcept {
    const uint8_t* p = node;
    uint64_t terminal_size = asg_read_uleb128(&p);
    if (terminal_size > 0 && cur_h == target_h) {
        uint64_t flags = asg_read_uleb128(&p);
        if ((flags & 0x08) == 0) {
            uint64_t addr = asg_read_uleb128(&p);
            return (void*)(addr + base);
        }
        return nullptr;
    }
    p += terminal_size;
    uint8_t child_count = *p++;
    for (uint8_t i = 0; i < child_count; i++) {
        uint32_t child_h = cur_h;
        while (*p) {
            child_h = (child_h ^ (uint8_t)*p++) * 0x01000193U;
        }
        p++; /* skip null terminator */
        uint64_t child_offset = asg_read_uleb128(&p);
        void* res = asg_find_sym_in_trie(trie_base, trie_base + child_offset, child_h, target_h, base);
        if (res) return res;
    }
    return nullptr;
}

static inline void* asgard_resolve_by_api_hash(uint32_t target_hash) noexcept {
    if (target_hash == 0) return nullptr;
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const struct mach_header_64* hdr = (const struct mach_header_64*)_dyld_get_image_header(i);
        if (!hdr || hdr->magic != MH_MAGIC_64) continue;
        intptr_t slide = _dyld_get_image_vmaddr_slide(i);
        const struct load_command* cmd = (const struct load_command*)(hdr + 1);
        uintptr_t linkedit_base = 0;
        uint32_t dataoff = 0;
        for (uint32_t c = 0; c < hdr->ncmds; c++) {
            if (cmd->cmd == LC_SEGMENT_64) {
                const struct segment_command_64* seg = (const struct segment_command_64*)cmd;
                if (asg_strcmp(seg->segname, "__LINKEDIT") == 0) {
                    linkedit_base = seg->vmaddr + slide - seg->fileoff;
                }
            } else if (cmd->cmd == 0x80000033 /* LC_DYLD_EXPORTS_TRIE */) {
                const struct linkedit_data_command* lc = (const struct linkedit_data_command*)cmd;
                dataoff = lc->dataoff;
            }
            cmd = (const struct load_command*)((const char*)cmd + cmd->cmdsize);
        }
        if (linkedit_base && dataoff) {
            const uint8_t* trie = (const uint8_t*)(linkedit_base + dataoff);
            void* resolved = asg_find_sym_in_trie(trie, trie, 0x811c9dc5U, target_hash, (uintptr_t)hdr);
            if (resolved) return resolved;
        }
    }
    return nullptr;
}
#else
static inline void* asgard_resolve_by_api_hash(uint32_t) noexcept { return nullptr; }
#endif

typedef struct {
    uint32_t hash;
    uint32_t alt_hash;
    uint16_t len;
    uint8_t enc_bytes[64];
} asgard_ext_sym_t;

static inline void asg_decrypt_sym(const asgard_ext_sym_t* sym, char* out_buf, size_t out_cap) noexcept {
    size_t n = sym->len < out_cap - 1 ? sym->len : out_cap - 1;
    for (size_t i = 0; i < n; i++) {
        uint8_t k = (uint8_t)(0x5A ^ ((i * 17 + 0x33) & 0xFF));
        out_buf[i] = (char)(sym->enc_bytes[i] ^ k);
    }
    out_buf[n] = '\0';
}

struct AsgardConstantEntry {
    uint32_t hash;
    uint32_t alt_hash;
    const uint8_t* enc_data;
    uint8_t* dec_data;
    size_t size;
    uint32_t xor_key;
    volatile int ready;
};

#endif // ASGARD_CRYPTO_PRIMITIVES_DEFINED
