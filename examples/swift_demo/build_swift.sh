#!/usr/bin/env bash
# ==============================================================================
# ASGARD-5877: Pure Swift Zero-Bridge Protection Pipeline
#
# Automates the entire compilation, ARM64 extraction, Stack-VM bytecode
# synthesis, in-place assembly trampoline patching, and native Mach-O linking.
# The developer writes 100% pure Swift; all VM bridge code is auto-synthesized.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

echo "=================================================================="
echo "🛡️  ASGARD-5877: Pure Swift Zero-Bridge Protection Pipeline"
echo "=================================================================="

# 1. Verify Prerequisites
command -v swiftc >/dev/null 2>&1 || { echo >&2 "[-] swiftc is required but not found in PATH."; exit 1; }
command -v clang++ >/dev/null 2>&1 || { echo >&2 "[-] clang++ is required but not found in PATH."; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo >&2 "[-] python3 is required but not found in PATH."; exit 1; }

# 2. Build ASGARD-5877 CLI if needed
if [[ ! -f "${ROOT_DIR}/_build/default/bin/main.exe" ]]; then
    echo "[*] Compiling ASGARD-5877 compiler toolchain via Dune..."
    (cd "${ROOT_DIR}" && dune build bin/main.exe)
fi

BUILD_DIR="${SCRIPT_DIR}/build"
VM_OUT="${BUILD_DIR}/vm_out"
mkdir -p "${VM_OUT}"

# 3. Compile Swift source directly to ARM64 assembly
echo "[*] Step 1/6: Compiling pure Swift to ARM64 assembly via swiftc..."
swiftc -O -parse-as-library -emit-assembly \
    "${SCRIPT_DIR}/Sources/App/main.swift" \
    -o "${BUILD_DIR}/app_raw.s"

# 4. Extract targeted function instructions for ASGARD virtualization
echo "[*] Step 2/6: Extracting target Swift function (_verify_license)..."
python3 - << EOF
with open("${BUILD_DIR}/app_raw.s", "r") as f:
    lines = f.readlines()

snip_lines = [".globl verify_license\n", "verify_license:\n"]
in_func = False
for line in lines:
    if line.startswith("_verify_license:"):
        in_func = True
        continue
    if in_func:
        snip_lines.append(line)
        if line.strip() == "ret":
            break

with open("${BUILD_DIR}/target_func.s", "w") as out:
    out.writelines(snip_lines)
EOF

# 5. Virtualize the extracted ARM64 routine using ASGARD Stack-VM Engine
echo "[*] Step 3/6: Virtualizing ARM64 logic into ASGARD Stack-VM Bytecode..."
"${ROOT_DIR}/_build/default/bin/main.exe" protect-arm64 \
    -i "${BUILD_DIR}/target_func.s" \
    -o "${VM_OUT}" \
    --engine=stack \
    --cff \
    --mba \
    --mba-depth 4 \
    --seed 1337 \
    --compile=false

# 6. Extract bytecode array into C++ header
python3 - << EOF
import re

with open("${VM_OUT}/runner.cpp", "r") as f:
    content = f.read()

match = re.search(r'static uint64_t embedded_bytecode\[\] = \{[\s\S]*?\};', content)
if not match:
    raise RuntimeError("Failed to extract embedded_bytecode from runner.cpp")

arr = match.group(0).replace("static uint64_t", "alignas(16) static const uint64_t")

with open("${VM_OUT}/embedded_bytecode.hpp", "w") as out:
    out.write("#pragma once\n#include <stdint.h>\n" + arr + "\n")
EOF

# 7. Auto-synthesize the zero-overhead C++ VM dispatcher
echo "[*] Step 4/6: Synthesizing automated VM entrypoint dispatcher..."
cat << 'EOF' > "${BUILD_DIR}/asgard_auto_dispatch.cpp"
#include "stack_vm_runtime.hpp"
#include "embedded_bytecode.hpp"
#include <stdint.h>
#include <stddef.h>

extern "C" uint64_t asgard_vm_entry_verify_license(uint64_t a0, uint64_t a1) {
    size_t bc_len = sizeof(embedded_bytecode) / sizeof(embedded_bytecode[0]);
    return vanguard_threaded_vm::asgard_vm_call(
        embedded_bytecode,
        bc_len,
        a0,
        a1
    );
}
EOF

clang++ -std=c++17 -O2 \
    -I"${VM_OUT}" \
    -c "${BUILD_DIR}/asgard_auto_dispatch.cpp" \
    -o "${BUILD_DIR}/asgard_auto_dispatch.o"

# 8. In-place assembly patching: replace function body with jump to VM entrypoint
echo "[*] Step 5/6: Patching Swift ARM64 assembly with opaque VM trampoline..."
python3 - "${BUILD_DIR}" << 'EOF'
import sys
build_dir = sys.argv[1]
with open(f"{build_dir}/app_raw.s", "r") as f:
    lines = f.readlines()

new_lines = []
skip = False
for line in lines:
    if line.startswith("_") and "verify_license" in line and line.strip().endswith(":"):
        new_lines.append(line)
        new_lines.append("\tb\t_asgard_vm_entry_verify_license\n")
        skip = True
    elif skip and line.strip() == "ret":
        skip = False
    elif not skip:
        new_lines.append(line)

with open(f"{build_dir}/app_protected.s", "w") as f:
    f.writelines(new_lines)
EOF

# 9. Assemble patched assembly and link protected executable
echo "[*] Step 6/6: Linking protected Swift Mach-O binary..."
clang -c "${BUILD_DIR}/app_protected.s" -o "${BUILD_DIR}/app_protected.o"

swiftc -O \
    "${BUILD_DIR}/app_protected.o" \
    "${BUILD_DIR}/asgard_auto_dispatch.o" \
    -lc++ \
    -o "${BUILD_DIR}/protected_swift_app"

echo "=================================================================="
echo "✅ Build Successful: ${BUILD_DIR}/protected_swift_app"
echo "=================================================================="
echo ""
echo "[*] Executing Protected Swift Application:"
echo "------------------------------------------------------------------"
"${BUILD_DIR}/protected_swift_app"
echo "------------------------------------------------------------------"
