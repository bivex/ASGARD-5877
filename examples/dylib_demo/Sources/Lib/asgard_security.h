#ifndef ASGARD_SECURITY_DYLIB_H
#define ASGARD_SECURITY_DYLIB_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32) || defined(__CYGWIN__)
  #ifdef ASGARD_BUILDING_DLL
    #define ASGARD_API __declspec(dllexport)
  #else
    #define ASGARD_API __declspec(dllimport)
  #endif
#else
  #if defined(__GNUC__) || defined(__clang__)
    #define ASGARD_API __attribute__((visibility("default")))
  #else
    #define ASGARD_API
  #endif
#endif

/**
 * Validates a user license key against machine-derived expected signatures.
 * The entire validation algorithm executes inside an obfuscated ASGARD VM.
 *
 * @param license_key User-provided key.
 * @param hwid        Machine-specific hardware identifier / salt.
 * @return 1 if valid, 0 otherwise.
 */
ASGARD_API uint64_t asgard_verify_license(uint64_t license_key, uint64_t hwid);

/**
 * Derives a high-entropy session security token.
 * Evaluates non-linear transformations entirely inside the virtual machine.
 *
 * @param session_id Session sequence number.
 * @param nonce      One-time nonce.
 * @return Computed token.
 */
ASGARD_API uint64_t asgard_derive_token(uint64_t session_id, uint64_t nonce);

#ifdef __cplusplus
}
#endif

#endif // ASGARD_SECURITY_DYLIB_H
