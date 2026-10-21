#include "LicenseBridge.h"
#include "stack_vm_runtime.hpp"
#include "embedded_bytecode.hpp"
#include <stddef.h>

extern "C" uint64_t asgard_verify_license(uint64_t license_key, uint64_t expected_hash) {
    size_t bc_len = sizeof(embedded_bytecode) / sizeof(embedded_bytecode[0]);
    return vanguard_threaded_vm::asgard_vm_call(
        embedded_bytecode,
        bc_len,
        license_key,
        expected_hash
    );
}
