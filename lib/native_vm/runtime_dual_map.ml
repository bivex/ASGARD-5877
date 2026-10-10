let emit_dual_mapping_header () =
  {|#pragma once
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
#if defined(__APPLE__)
#include <mach/mach.h>
#include <mach/vm_map.h>
#include <sys/mman.h>
#include <pthread.h>
#include <unistd.h>
#elif defined(__linux__)
#include <sys/mman.h>
#include <unistd.h>
#include <fcntl.h>
#elif defined(_WIN32)
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#endif

#ifndef ASGARD_API_HASH_RESOLVER_DEFINED
#define ASGARD_API_HASH_RESOLVER_DEFINED
static inline int asg_strcmp(const char* s1, const char* s2) noexcept {
    if (!s1 || !s2) return (s1 == s2) ? 0 : (s1 ? 1 : -1);
    while (*s1 && (*s1 == *s2)) { s1++; s2++; }
    return *(const unsigned char*)s1 - *(const unsigned char*)s2;
}

#if defined(__APPLE__) && defined(__MACH__)
#include <mach-o/dyld.h>
#include <mach-o/loader.h>

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
        p++;
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
#endif

namespace asgard_memory {

struct DualMappedBuffer {
    void* rw_alias = nullptr; // Writable view for self-consumption / patching
    const void* rx_alias = nullptr; // Executable view for execution
    size_t size = 0;

    static inline bool is_supported() noexcept {
#if defined(__APPLE__)
        return true;
#elif defined(__linux__) && defined(MFD_CLOEXEC)
        return true;
#elif defined(_WIN32)
        return true;
#else
        return false;
#endif
    }

    static DualMappedBuffer allocate(size_t required_size) noexcept {
        DualMappedBuffer buf = {};
        size_t page_sz = 4096;

#if defined(_WIN32)
        SYSTEM_INFO si;
        GetSystemInfo(&si);
        if (si.dwPageSize) page_sz = (size_t)si.dwPageSize;
#elif defined(__APPLE__) || defined(__linux__)
        long sc_ps = sysconf(_SC_PAGESIZE);
        if (sc_ps > 0) page_sz = (size_t)sc_ps;
#endif
        buf.size = (required_size + page_sz - 1) & ~(page_sz - 1);

#if defined(__APPLE__)
#if defined(MAP_JIT)
        void* jptr = mmap(NULL, buf.size, PROT_READ | PROT_WRITE | PROT_EXEC, MAP_ANON | MAP_PRIVATE | MAP_JIT, -1, 0);
        if (jptr != MAP_FAILED) {
            buf.rw_alias = jptr;
            buf.rx_alias = jptr;
            return buf;
        }
#endif
        typedef kern_return_t (*asg_vm_alloc_fn_t)(vm_map_t, vm_address_t*, vm_size_t, int);
        typedef kern_return_t (*asg_vm_remap_fn_t)(vm_map_t, vm_address_t*, vm_size_t, vm_address_t, int, vm_map_t, vm_address_t, boolean_t, vm_prot_t*, vm_prot_t*, vm_inherit_t);
        typedef kern_return_t (*asg_vm_prot_fn_t)(vm_map_t, vm_address_t, vm_size_t, boolean_t, vm_prot_t);
        typedef kern_return_t (*asg_vm_dealloc_fn_t)(vm_map_t, vm_address_t, vm_size_t);
        static asg_vm_alloc_fn_t p_vm_alloc = nullptr;
        static asg_vm_remap_fn_t p_vm_remap = nullptr;
        static asg_vm_prot_fn_t  p_vm_prot  = nullptr;
        static asg_vm_dealloc_fn_t p_vm_dealloc = nullptr;
        if (!p_vm_alloc) p_vm_alloc = (asg_vm_alloc_fn_t)asgard_resolve_by_api_hash(0xA0E735E5U /* _vm_allocate */);
        if (!p_vm_remap) p_vm_remap = (asg_vm_remap_fn_t)asgard_resolve_by_api_hash(0xF034F085U /* _vm_remap */);
        if (!p_vm_prot)  p_vm_prot  = (asg_vm_prot_fn_t)asgard_resolve_by_api_hash(0x9857D42CU /* _vm_protect */);
        if (!p_vm_dealloc) p_vm_dealloc = (asg_vm_dealloc_fn_t)asgard_resolve_by_api_hash(0xE86CA72AU /* _vm_deallocate */);

        vm_address_t rw_addr = 0;
        if (p_vm_alloc && p_vm_alloc(mach_task_self(), &rw_addr, buf.size, VM_FLAGS_ANYWHERE) == KERN_SUCCESS) {
            vm_address_t rx_addr = 0;
            vm_prot_t cur_prot, max_prot;
            if (p_vm_remap && p_vm_remap(mach_task_self(), &rx_addr, buf.size, 0, VM_FLAGS_ANYWHERE,
                          mach_task_self(), rw_addr, FALSE, &cur_prot, &max_prot, VM_INHERIT_NONE) == KERN_SUCCESS) {
                if (p_vm_prot && p_vm_prot(mach_task_self(), rx_addr, buf.size, FALSE, VM_PROT_READ | VM_PROT_EXECUTE) == KERN_SUCCESS) {
                    buf.rw_alias = (void*)rw_addr;
                    buf.rx_alias = (const void*)rx_addr;
                    return buf;
                }
            }
            if (p_vm_dealloc) p_vm_dealloc(mach_task_self(), rw_addr, buf.size);
        }
#elif defined(__linux__) && defined(MFD_CLOEXEC)
        int fd = memfd_create("asgard_dual_wx", MFD_CLOEXEC);
        if (fd >= 0) {
            if (ftruncate(fd, buf.size) == 0) {
                buf.rw_alias = mmap(NULL, buf.size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
                buf.rx_alias = mmap(NULL, buf.size, PROT_READ | PROT_EXEC, MAP_SHARED, fd, 0);
                close(fd);
                if (buf.rw_alias != MAP_FAILED && buf.rx_alias != MAP_FAILED) return buf;
            }
            close(fd);
        }
#elif defined(_WIN32)
        HANDLE hMap = CreateFileMappingW(INVALID_HANDLE_VALUE, NULL, PAGE_EXECUTE_READWRITE, 0, (DWORD)buf.size, NULL);
        if (hMap != NULL) {
            buf.rw_alias = MapViewOfFile(hMap, FILE_MAP_READ | FILE_MAP_WRITE, 0, 0, buf.size);
            buf.rx_alias = MapViewOfFile(hMap, FILE_MAP_READ | FILE_MAP_EXECUTE, 0, 0, buf.size);
            CloseHandle(hMap);
            if (buf.rw_alias != NULL && buf.rx_alias != NULL) {
                return buf;
            }
            if (buf.rw_alias != NULL) UnmapViewOfFile(buf.rw_alias);
            if (buf.rx_alias != NULL) UnmapViewOfFile((void*)buf.rx_alias);
            buf.rw_alias = nullptr;
            buf.rx_alias = nullptr;
        }
#endif
        return buf;
    }

    void release() noexcept {
#if defined(__APPLE__)
        if (rw_alias == rx_alias && rw_alias != nullptr) {
            munmap(rw_alias, size);
        } else {
            typedef kern_return_t (*asg_vm_dealloc_fn_t)(vm_map_t, vm_address_t, vm_size_t);
            static asg_vm_dealloc_fn_t p_vm_dealloc = nullptr;
            if (!p_vm_dealloc) p_vm_dealloc = (asg_vm_dealloc_fn_t)asgard_resolve_by_api_hash(0xE86CA72AU /* _vm_deallocate */);
            if (p_vm_dealloc) {
                if (rw_alias) p_vm_dealloc(mach_task_self(), (vm_address_t)rw_alias, size);
                if (rx_alias) p_vm_dealloc(mach_task_self(), (vm_address_t)rx_alias, size);
            }
        }
#elif defined(__linux__)
        if (rw_alias && rw_alias != MAP_FAILED) munmap(rw_alias, size);
        if (rx_alias && rx_alias != MAP_FAILED) munmap((void*)rx_alias, size);
#elif defined(_WIN32)
        if (rw_alias != nullptr) UnmapViewOfFile(rw_alias);
        if (rx_alias != nullptr) UnmapViewOfFile((void*)rx_alias);
#endif
        rw_alias = nullptr;
        rx_alias = nullptr;
        size = 0;
    }
};

} // namespace asgard_memory
|}
