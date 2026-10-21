#ifndef ASGARD_SWIFT_LICENSE_BRIDGE_H
#define ASGARD_SWIFT_LICENSE_BRIDGE_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Validates a license key inside the ASGARD-5877 polymorphic virtual machine.
 *
 * @param license_key   The user-provided license key.
 * @param expected_hash The machine/environment-derived expected signature.
 * @return 1 if valid, 0 if invalid or tampered.
 */
uint64_t asgard_verify_license(uint64_t license_key, uint64_t expected_hash);

#ifdef __cplusplus
}
#endif

#endif // ASGARD_SWIFT_LICENSE_BRIDGE_H
