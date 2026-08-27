#include <stdint.h>

static inline uint16_t rol16(uint16_t v, unsigned int s) {
    s &= 15;
    return (uint16_t)((v << s) | (v >> (16 - s)));
}

uint64_t vm_verify_key(uint64_t b1, uint64_t b2, uint64_t b3, uint64_t b4) {
    uint32_t r1 = (uint32_t)((b1 ^ b2) & 0xFFFF);
    if (r1 != 0xE123) return 0;

    uint32_t r2 = (uint32_t)((b2 * 0x9E37 + b3) & 0xFFFF);
    if (r2 != 0xE892) return 0;

    uint32_t r3 = (uint32_t)((b3 ^ (uint32_t)rol16((uint16_t)b4, 5)) & 0xFFFF);
    if (r3 != 0x80CB) return 0;

    uint32_t r4 = (uint32_t)((b1 + b2 + b3 + b4) & 0xFFFF);
    if (r4 != 0x9153) return 0;

    uint64_t token = (b1 << 48) | (b2 << 32) | (b3 << 16) | b4;
    return token;
}
