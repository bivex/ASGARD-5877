#ifndef _APP_COMMON_H_
#define _APP_COMMON_H_

#include <stdint.h>
#include <stdbool.h>

/* Module 1: License Verification (Ultra VM Protection) */
int64_t verify_license_module(int64_t hwid, int64_t user_serial);

/* Module 2: Cryptographic Key Derivation (Mutation Protection) */
uint64_t derive_session_key(uint64_t master_seed, uint32_t session_id);

/* Module 3: Authentication & Security Tokens (Virtualization Protection) */
bool authenticate_security_token(uint64_t token, uint64_t expected_hash);

#endif /* _APP_COMMON_H_ */
