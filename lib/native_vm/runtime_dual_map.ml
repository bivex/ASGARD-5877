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
        vm_address_t rw_addr = 0;
        if (vm_allocate(mach_task_self(), &rw_addr, buf.size, VM_FLAGS_ANYWHERE) == KERN_SUCCESS) {
            vm_address_t rx_addr = 0;
            vm_prot_t cur_prot, max_prot;
            if (vm_remap(mach_task_self(), &rx_addr, buf.size, 0, VM_FLAGS_ANYWHERE,
                          mach_task_self(), rw_addr, FALSE, &cur_prot, &max_prot, VM_INHERIT_NONE) == KERN_SUCCESS) {
                if (vm_protect(mach_task_self(), rx_addr, buf.size, FALSE, VM_PROT_READ | VM_PROT_EXECUTE) == KERN_SUCCESS) {
                    buf.rw_alias = (void*)rw_addr;
                    buf.rx_alias = (const void*)rx_addr;
                    return buf;
                }
            }
            vm_deallocate(mach_task_self(), rw_addr, buf.size);
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
            if (rw_alias) vm_deallocate(mach_task_self(), (vm_address_t)rw_alias, size);
            if (rx_alias) vm_deallocate(mach_task_self(), (vm_address_t)rx_alias, size);
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
