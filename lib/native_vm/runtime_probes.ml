let emit_anti_emulation_probes () =
  {|#pragma once
#include <stdint.h>
#include <stdbool.h>
#if defined(__APPLE__)
#include <mach/mach_time.h>
#elif defined(_WIN32)
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#if defined(_MSC_VER)
#include <intrin.h>
#endif
#endif

namespace asgard_anti_emulation {

static inline __attribute__((always_inline)) uint64_t evaluate_emulation_differential() noexcept {
    uint64_t penalty = 0;

#if defined(__x86_64__) || defined(_M_X64)
    // 1. CPUID Hypervisor Discovery & Cycle Ratio Probe
#if defined(_MSC_VER)
    int cpuInfo[4] = { 0 };
    __cpuid(cpuInfo, 1);
    if ((cpuInfo[2] >> 31) & 1) {
        penalty ^= 0x5877CAFEBABE1337ULL; // Hypervisor bit detected
    }
    uint64_t t0 = __rdtsc();
    for (int i = 0; i < 64; ++i) { YieldProcessor(); }
    uint64_t t1 = __rdtsc();
    if ((t1 - t0) > 25000ULL) {
        penalty ^= 0xDEADBEEF5A5A1337ULL; // Emulation slow-path detected
    }
#else
    uint32_t eax = 1, ebx = 0, ecx = 0, edx = 0;
    __asm__ volatile("cpuid" : "+a"(eax), "=b"(ebx), "=c"(ecx), "=d"(edx));
    if ((ecx >> 31) & 1) {
        penalty ^= 0x5877CAFEBABE1337ULL; // Hypervisor bit detected
    }

    // 2. TSC vs Execution Latency Ratio (QEMU/Unicorn JIT emulators have >50x jitter)
    uint64_t t0 = __builtin_ia32_rdtsc();
    for (int i = 0; i < 64; ++i) { __asm__ volatile("nop"); }
    uint64_t t1 = __builtin_ia32_rdtsc();
    if ((t1 - t0) > 25000ULL) {
        penalty ^= 0xDEADBEEF5A5A1337ULL; // Emulation slow-path detected
    }
#endif
#if defined(_WIN32)
    // Secondary differential via QueryPerformanceCounter
    LARGE_INTEGER q0, q1, freq;
    if (QueryPerformanceFrequency(&freq) && QueryPerformanceCounter(&q0)) {
        for (int i = 0; i < 32; ++i) { YieldProcessor(); }
        QueryPerformanceCounter(&q1);
        if (q1.QuadPart == q0.QuadPart && (t1 - t0) > 1000ULL) {
            penalty ^= 0x5877AABBCCDDEEFFULL;
        }
    }
#endif
#elif defined(__aarch64__) || defined(_M_ARM64)
    // ARM64 Virtual Counter Overhead & Multi-Source Jitter Probe
    uint64_t t0, t1;
    __asm__ volatile("mrs %0, cntvct_el0" : "=r"(t0));
    for (int i = 0; i < 64; ++i) { __asm__ volatile("nop"); }
    __asm__ volatile("mrs %0, cntvct_el0" : "=r"(t1));
    if ((t1 - t0) > 30000ULL) {
        penalty ^= 0xFEEDFACE5877CAFEULL;
    }
#if defined(__APPLE__)
    // Multi-source differential verification (detecting timer spoofing / freeze)
    uint64_t m0 = mach_absolute_time();
    for (int i = 0; i < 32; ++i) { __asm__ volatile("nop"); }
    uint64_t m1 = mach_absolute_time();
    if (m1 == m0 && (t1 - t0) > 1000ULL) {
        penalty ^= 0x5877AABBCCDDEEFFULL;
    }
#endif
#endif

    return penalty;
}

} // namespace asgard_anti_emulation
|}

let emit_memory_integrity_scanner_header () =
  {|#pragma once
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
#if defined(__APPLE__)
#include <mach/mach.h>
#include <mach/thread_act.h>
#include <mach/thread_status.h>
#include <mach/vm_map.h>
#include <mach-o/dyld.h>
#include <mach-o/getsect.h>
#elif defined(__linux__)
#include <stdio.h>
#include <string.h>
#include <link.h>
#elif defined(_WIN32)
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#endif

namespace asgard_mem_integrity {

static inline __attribute__((always_inline)) uint64_t compute_section_integrity_hash() noexcept {
    uint64_t h = 0x5877CAFE1337BEEFULL;

#if defined(__APPLE__)
    const struct mach_header_64* mh = (const struct mach_header_64*)_dyld_get_image_header(0);
    if (mh) {
        unsigned long text_sz = 0;
        uint8_t* text_p = getsectiondata(mh, "__TEXT", "__text", &text_sz);
        if (text_p && text_sz > 0) {
            size_t sample = text_sz < 65536 ? text_sz : 65536;
            for (size_t i = 0; i + 8 <= sample; i += 32) {
                uint64_t w = *reinterpret_cast<const uint64_t*>(text_p + i);
                h ^= w * 0x9E3779B97F4A7C15ULL;
                h = (h << 13) | (h >> 51);
                h *= 0x100000001B3ULL;
            }
        }
        unsigned long const_sz = 0;
        uint8_t* const_p = getsectiondata(mh, "__TEXT", "__const", &const_sz);
        if (const_p && const_sz > 0) {
            size_t sample = const_sz < 16384 ? const_sz : 16384;
            for (size_t i = 0; i + 8 <= sample; i += 32) {
                uint64_t w = *reinterpret_cast<const uint64_t*>(const_p + i);
                h ^= w * 0xBF58476D1CE4E5B9ULL;
                h = (h << 17) | (h >> 47);
            }
        }
    }
#elif defined(__linux__) && !defined(_MSC_VER)
    struct PhdrContext {
        uint64_t hash;
        bool found;
    } pctx = { h, false };

    dl_iterate_phdr([](struct dl_phdr_info* info, size_t, void* data) -> int {
        auto* ctx = reinterpret_cast<PhdrContext*>(data);
        if (ctx->found) return 1;
        for (int i = 0; i < info->dlpi_phnum; ++i) {
            const ElfW(Phdr)& ph = info->dlpi_phdr[i];
            if (ph.p_type == PT_LOAD && (ph.p_flags & PF_X)) {
                const uint8_t* base = reinterpret_cast<const uint8_t*>(info->dlpi_addr + ph.p_vaddr);
                size_t sz = ph.p_filesz < 65536 ? ph.p_filesz : 65536;
                for (size_t j = 0; j + 8 <= sz; j += 32) {
                    uint64_t w = *reinterpret_cast<const uint64_t*>(base + j);
                    ctx->hash ^= w * 0x9E3779B97F4A7C15ULL;
                    ctx->hash = (ctx->hash << 13) | (ctx->hash >> 51);
                    ctx->hash *= 0x100000001B3ULL;
                }
                ctx->found = true;
            }
        }
        return ctx->found ? 1 : 0;
    }, &pctx);
    h = pctx.hash;
#elif defined(_WIN32)
    HMODULE hMod = GetModuleHandleA(nullptr);
    if (hMod) {
        const uint8_t* base = reinterpret_cast<const uint8_t*>(hMod);
        const auto* dos = reinterpret_cast<const IMAGE_DOS_HEADER*>(base);
        if (dos->e_magic == IMAGE_DOS_SIGNATURE) {
            const auto* nt = reinterpret_cast<const IMAGE_NT_HEADERS*>(base + dos->e_lfanew);
            if (nt->Signature == IMAGE_NT_SIGNATURE) {
                const auto* sec = IMAGE_FIRST_SECTION(nt);
                for (WORD i = 0; i < nt->FileHeader.NumberOfSections; ++i, ++sec) {
                    if (sec->Characteristics & (IMAGE_SCN_MEM_EXECUTE | IMAGE_SCN_CNT_INITIALIZED_DATA)) {
                        const uint8_t* p = base + sec->VirtualAddress;
                        size_t sz = sec->Misc.VirtualSize < 65536 ? sec->Misc.VirtualSize : 65536;
                        for (size_t j = 0; j + 8 <= sz; j += 32) {
                            uint64_t w = *reinterpret_cast<const uint64_t*>(p + j);
                            h ^= w * 0x9E3779B97F4A7C15ULL;
                            h = (h << 13) | (h >> 51);
                            h *= 0x100000001B3ULL;
                        }
                    }
                }
            }
        }
    }
#endif

    return h ^ (h >> 31);
}

// MEM-SBOM Style Memory Forensics & Injection Scanner
static inline __attribute__((always_inline)) uint64_t evaluate_memory_integrity() noexcept {
    uint64_t penalty = 0;

    // 1. Executable Section Dynamic Drift Check
    static uint64_t initial_sect_hash = 0;
    uint64_t current_sect_hash = compute_section_integrity_hash();
    if (initial_sect_hash == 0) {
        initial_sect_hash = current_sect_hash;
    } else if (current_sect_hash != initial_sect_hash) {
        penalty ^= 0x5877BAADC0DEDEADULL;
    }

#if defined(__APPLE__)
    // 2. Thread Debug Register Inspection (DR0-DR3 / DBGBVR detection)
    mach_port_t thread = mach_thread_self();
#if defined(__aarch64__) && defined(ARM_DEBUG_STATE64)
    arm_debug_state64_t dbg_state = {};
    mach_msg_type_number_t count = ARM_DEBUG_STATE64_COUNT;
    if (thread_get_state(thread, ARM_DEBUG_STATE64, (thread_state_t)&dbg_state, &count) == KERN_SUCCESS) {
        for (int i = 0; i < 16; ++i) {
            if (dbg_state.__bcr[i] & 1) { // Breakpoint control enabled
                penalty ^= 0xCAFEBABE00000001ULL ^ ((uint64_t)i << 32);
            }
        }
    }
#elif defined(__x86_64__) && defined(x86_DEBUG_STATE64)
    x86_debug_state64_t dbg_state = {};
    mach_msg_type_number_t count = x86_DEBUG_STATE64_COUNT;
    if (thread_get_state(thread, x86_DEBUG_STATE64, (thread_state_t)&dbg_state, &count) == KERN_SUCCESS) {
        if (dbg_state.__dr7 & 0x000000FF) { // DR0-DR3 active
            penalty ^= 0xCAFEBABE00000002ULL;
        }
    }
#endif
    mach_port_deallocate(mach_task_self(), thread);

    // 3. Suspicious Anonymous RWX Memory Scanner (Anti-Frida / Shellcode Injection)
    vm_address_t address = 0;
    vm_size_t size = 0;
    mach_port_t object_name = MACH_PORT_NULL;
    struct vm_region_basic_info_64 info = {};
    mach_msg_type_number_t info_cnt = VM_REGION_BASIC_INFO_COUNT_64;
    int suspicious_rwx = 0;
    while (vm_region_64(mach_task_self(), &address, &size, VM_REGION_BASIC_INFO_64, (vm_region_info_t)&info, &info_cnt, &object_name) == KERN_SUCCESS) {
        if ((info.protection & VM_PROT_WRITE) && (info.protection & VM_PROT_EXECUTE)) {
            suspicious_rwx++;
        }
        address += size;
    }
    if (suspicious_rwx > 2) {
        penalty ^= 0x5877F81DA0000001ULL;
    }
#elif defined(__linux__)
    FILE* fp = fopen("/proc/self/maps", "r");
    if (fp) {
        char line[512];
        while (fgets(line, sizeof(line), fp)) {
            if (strstr(line, "rwxp")) { // Anonymous RWX page
                penalty ^= 0x5877F81DA0000002ULL;
                break;
            }
        }
        fclose(fp);
    }
#elif defined(_WIN32)
    // Thread Debug Register Inspection (DR0-DR3 / DR7 detection)
    CONTEXT dbg_ctx = {};
    dbg_ctx.ContextFlags = CONTEXT_DEBUG_REGISTERS;
    if (GetThreadContext(GetCurrentThread(), &dbg_ctx)) {
        if (dbg_ctx.Dr7 & 0x000000FF) {
            penalty ^= 0xCAFEBABE00000002ULL;
        }
    }

    // Suspicious Anonymous RWX Memory Scanner (VirtualQuery)
    MEMORY_BASIC_INFORMATION mbi = {};
    const uint8_t* addr = nullptr;
    int suspicious_rwx = 0;
    while (VirtualQuery((LPCVOID)addr, &mbi, sizeof(mbi)) == sizeof(mbi)) {
        if ((mbi.State == MEM_COMMIT) && (mbi.Protect == PAGE_EXECUTE_READWRITE)) {
            suspicious_rwx++;
        }
        addr = (const uint8_t*)mbi.BaseAddress + mbi.RegionSize;
        if (addr == nullptr || mbi.RegionSize == 0) break;
    }
    if (suspicious_rwx > 2) {
        penalty ^= 0x5877F81DA0000003ULL;
    }
#endif

    return penalty;
}

} // namespace asgard_mem_integrity
|}
