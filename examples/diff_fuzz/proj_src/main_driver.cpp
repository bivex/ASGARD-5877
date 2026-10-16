/* ========================================================================= */
/*  ASGARD-5877 Differential Fuzzing - Streaming Driver Main                 */
/*                                                                           */
/*  `--fuzz` mode turns the binary (native golden or protected alike) into   */
/*  a line-oriented oracle so the Python differential runner can stream      */
/*  thousands of vectors through one process instead of paying process       */
/*  startup per vector.                                                      */
/*                                                                           */
/*  Input line:  <a_hex> <b_dec> <c_hex> <d> <e> <flags_dec> <seed_hex> <blob_hex>
    Output line: 0x<r1> 0x<r2>                                                */
/*                                                                           */
/*  <blob_hex> is a plain hex string (may be empty -> "00"): raw bytes fed   */
/*  to asgard_fuzz_mix. Doubles are printed by the runner with repr() so     */
/*  strtod recovers the exact same bit pattern on this side.                 */
/* ========================================================================= */
#include "../fuzz_types.h"

#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <string>
#include <string_view>

extern "C" uint64_t asgard_fuzz_compute(const TestPayload& p);
extern "C" uint64_t asgard_fuzz_mix(uint64_t seed, const uint8_t* data, size_t n);

static int hexval(char ch) {
    if (ch >= '0' && ch <= '9') return ch - '0';
    if (ch >= 'a' && ch <= 'f') return ch - 'a' + 10;
    if (ch >= 'A' && ch <= 'F') return ch - 'A' + 10;
    return -1;
}

static size_t parse_hex_blob(const std::string& hex, uint8_t* out, size_t cap) {
    size_t n = 0;
    size_t i = 0;
    if (hex.size() >= 2 && hex[0] == '0' && (hex[1] == 'x' || hex[1] == 'X')) i = 2;
    while (i + 1 < hex.size() && n < cap) {
        int hi = hexval(hex[i]);
        int lo = hexval(hex[i + 1]);
        if (hi < 0 || lo < 0) break;
        out[n++] = (uint8_t)((hi << 4) | lo);
        i += 2;
    }
    return n;
}

int main(int argc, char** argv) {
    if (argc > 1 && std::string_view(argv[1]) == "--fuzz") {
        std::string s_a, s_b, s_c, s_d, s_e, s_f, s_seed, s_blob;
        while (std::cin >> s_a >> s_b >> s_c >> s_d >> s_e >> s_f >> s_seed >> s_blob) {
            TestPayload p;
            std::memset(&p, 0, sizeof p);
            p.a     = (uint64_t)strtoull(s_a.c_str(), nullptr, 0);
            p.b     = (int32_t)(int64_t)strtoll(s_b.c_str(), nullptr, 0);
            p.c     = (uint32_t)strtoul(s_c.c_str(), nullptr, 0);
            p.d     = strtod(s_d.c_str(), nullptr);
            p.e     = strtod(s_e.c_str(), nullptr);
            p.flags = (uint8_t)strtoul(s_f.c_str(), nullptr, 0);
            uint64_t seed = (uint64_t)strtoull(s_seed.c_str(), nullptr, 0);

            uint8_t blob[64];
            size_t n = parse_hex_blob(s_blob, blob, sizeof blob);

            uint64_t r1 = asgard_fuzz_compute(p);
            uint64_t r2 = asgard_fuzz_mix(seed, blob, n);
            std::cout << "0x" << std::hex << r1 << " 0x" << r2 << "\n";
        }
        return 0;
    }

    /* Self-test mode: one fixed vector, sanity output. */
    TestPayload p;
    p.a = 0x0123456789ABCDEFULL;
    p.b = -12345;
    p.c = 0x1337;
    p.d = 250.5;
    p.e = 2.0;
    p.flags = 0xAB;

    const uint8_t blob[8] = {0xDE, 0xAD, 0xBE, 0xEF, 0x58, 0x77, 0x00, 0xFF};
    uint64_t r1 = asgard_fuzz_compute(p);
    uint64_t r2 = asgard_fuzz_mix(0xDEADBEEFULL, blob, sizeof blob);
    std::cout << "[DIFF-FUZZ-SELFTEST] compute=0x" << std::hex << r1
              << " mix=0x" << r2 << std::dec << "\n";
    return (r1 != 0 && r2 != 0) ? 0 : 1;
}
