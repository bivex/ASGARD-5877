#!/usr/bin/env bash
# ==============================================================================
# ASGARD-5877: Android Kotlin + Protected .so JNI Pipeline
#
# Builds an obfuscated Android shared library (libasgard_security.so, arm64-v8a)
# using the ASGARD Protection Engine and Android NDK, compiles the client Kotlin
# application, packages it into Dalvik Executable (classes.dex) using D8, and
# executes it directly on the running Android Emulator (emulator-5554).
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

echo "=================================================================="
echo "🤖  ASGARD-5877: Android NDK (.so) + Kotlin Protection Pipeline"
echo "=================================================================="

# 1. Locate Android SDK, NDK, and Toolchain
ANDROID_HOME="${ANDROID_HOME:-/Users/password9090/android-sdk}"
ADB="${ANDROID_HOME}/platform-tools/adb"
D8="${ANDROID_HOME}/build-tools/35.0.0/d8"
ANDROID_JAR="${ANDROID_HOME}/platforms/android-35/android.jar"

# Locate Android NDK Clang compiler
NDK_CLANG=$(find "${ANDROID_HOME}/ndk" -name "aarch64-linux-android*-clang++" 2>/dev/null | sort -V | tail -n 1)

if [[ -z "${NDK_CLANG}" || ! -x "${NDK_CLANG}" ]]; then
    echo "[-] Android NDK aarch64 clang++ not found under ${ANDROID_HOME}/ndk."
    exit 1
fi

command -v kotlinc >/dev/null 2>&1 || { echo >&2 "[-] kotlinc is required but not found in PATH."; exit 1; }
[[ -x "${ADB}" ]] || { echo >&2 "[-] adb not found at ${ADB}."; exit 1; }
[[ -x "${D8}" ]] || { echo >&2 "[-] d8 not found at ${D8}."; exit 1; }

echo "[+] Android NDK Compiler: ${NDK_CLANG}"
echo "[+] Kotlin Compiler:     $(kotlinc -version 2>&1)"
echo "[+] Android Build Tools: ${D8}"

# 2. Check Android Emulator Status
EMULATOR_DEVICE=$("${ADB}" devices | grep "emulator" | head -n 1 | awk '{print $1}')
if [[ -z "${EMULATOR_DEVICE}" ]]; then
    echo "[-] No Android emulator detected via adb devices."
    echo "[-] Please launch an Android ARM64 emulator (emulator-5554) and re-run."
    exit 1
fi

DEVICE_ABI=$("${ADB}" -s "${EMULATOR_DEVICE}" shell getprop ro.product.cpu.abi | tr -d '\r')
echo "[+] Connected Device:    ${EMULATOR_DEVICE} (${DEVICE_ABI})"

# 3. Build ASGARD CLI if needed
if [[ ! -f "${ROOT_DIR}/_build/default/bin/main.exe" ]]; then
    echo "[*] Compiling ASGARD-5877 compiler toolchain via Dune..."
    (cd "${ROOT_DIR}" && dune build bin/main.exe)
fi

BUILD_DIR="${SCRIPT_DIR}/build"
VM_OUT="${BUILD_DIR}/vm_out"
mkdir -p "${VM_OUT}"

JNI_SRC="${SCRIPT_DIR}/Sources/Jni/asgard_security_jni.c"
SO_PATH="${BUILD_DIR}/libasgard_security.so"

# 4. Virtualize JNI logic using ASGARD Protection Engine
echo ""
echo "[*] Step 1/4: Virtualizing JNI Functions via ASGARD Engine..."
"${ROOT_DIR}/_build/default/bin/main.exe" protect-arm64 \
    -i "${JNI_SRC}" \
    -o "${VM_OUT}" \
    --engine=threaded \
    --compile=false

# 5. Compile Virtualized C++ Code into Android .so Library
echo ""
echo "[*] Step 2/4: Compiling libasgard_security.so via Android NDK (arm64-v8a)..."
"${NDK_CLANG}" -std=c++17 -O2 -shared -fPIC -static-libstdc++ \
    -I"${VM_OUT}" \
    -I"${SCRIPT_DIR}/Sources/Jni" \
    "${VM_OUT}/app_virtualized.cpp" \
    -o "${SO_PATH}"

echo "[+] Android Shared Library Generated: ${SO_PATH}"
file "${SO_PATH}"

# 6. Compile Kotlin Client and Package into Dalvik Executable (classes.dex)
echo ""
echo "[*] Step 3/4: Compiling Kotlin Client & Generating Dalvik Executable (D8)..."
kotlinc \
    "${SCRIPT_DIR}/Sources/Kotlin/AsgardSecurity.kt" \
    "${SCRIPT_DIR}/Sources/Kotlin/Main.kt" \
    -language-version 2.1 \
    -api-version 2.1 \
    -include-runtime \
    -d "${BUILD_DIR}/app.jar"

"${D8}" "${BUILD_DIR}/app.jar" \
    --output "${BUILD_DIR}/" \
    --lib "${ANDROID_JAR}" >/dev/null 2>&1

DEX_PATH="${BUILD_DIR}/classes.dex"
echo "[+] Generated Dalvik DEX: ${DEX_PATH}"

# 7. Push Artifacts to Android Emulator and Execute
echo ""
echo "[*] Step 4/4: Deploying and Running on Android Emulator (${EMULATOR_DEVICE})..."
"${ADB}" -s "${EMULATOR_DEVICE}" push "${SO_PATH}" /data/local/tmp/libasgard_security.so
"${ADB}" -s "${EMULATOR_DEVICE}" push "${DEX_PATH}" /data/local/tmp/classes.dex

echo "------------------------------------------------------------------"
echo "[*] Executing Kotlin Application via app_process on Android:"
echo "------------------------------------------------------------------"
"${ADB}" -s "${EMULATOR_DEVICE}" shell "CLASSPATH=/data/local/tmp/classes.dex app_process /data/local/tmp com.asgard.security.MainKt"
echo "------------------------------------------------------------------"
echo "✅ Android Emulator Verification PASSED."
echo "=================================================================="
