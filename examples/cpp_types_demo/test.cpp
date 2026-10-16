#include <iostream>
#include <string_view>
#include <array>
#include <tuple>
#include <vector>
#include <cstdint>
#include <optional>
#include "asgard_obf.h"

enum class SecurityLevel : uint32_t {
    Guest = 0,
    User = 1,
    Admin = 2,
    SuperUser = 3
};

struct TokenPayload {
    uint64_t user_id;
    SecurityLevel level;
    double quota;
    double extra_weight;
    bool is_active;
};

template <typename T>
class SecurityContext {
private:
    T payload_;
    uint64_t secret_salt_;

public:
    constexpr SecurityContext(T p, uint64_t salt)
        : payload_(p), secret_salt_(salt) {}

    const T& payload() const { return payload_; }
    uint64_t salt() const { return secret_salt_; }

    bool validate(uint64_t input_signature) const {
        return (input_signature ^ secret_salt_) == 0x5877;
    }
};

extern "C" __attribute__((noinline)) uint64_t evaluate_security_rules(
    const TokenPayload& token,
    uint64_t seed
) {
    uint64_t result = 0;

    // 🔒 ASGARD MARKER: ULTRA VM PROTECTION
    ASGARD_BEGIN_ULTRA("EvaluateRules");

    SecurityContext<TokenPayload> ctx(token, seed ^ 0xCAFEBABEULL);

    if (!token.is_active) {
        result = 0;
    } else {
        uint64_t base_score = 1000;
        
        switch (token.level) {
            case SecurityLevel::Guest:
                base_score += 10;
                break;
            case SecurityLevel::User:
                base_score += 100;
                break;
            case SecurityLevel::Admin:
                base_score += 500;
                break;
            case SecurityLevel::SuperUser:
                base_score += 1000;
                break;
        }

        // Float / Double arithmetic
        double computed_quota = token.quota * token.extra_weight;
        int64_t quota_int = static_cast<int64_t>(computed_quota);

        // Lambda with capture
        auto transform_score = [&](uint64_t s) -> uint64_t {
            return (s ^ token.user_id) + quota_int;
        };

        uint64_t transformed = transform_score(base_score);

        if (ctx.validate((seed ^ 0xCAFEBABEULL) ^ 0x5877)) {
            result = transformed * 42 + 0x1337;
        } else {
            result = 0xDEADBEEF;
        }
    }

    ASGARD_END();
    // 🔓 END MARKER

    return result;
}

int main(int argc, char** argv) {
    if (argc > 1 && std::string_view(argv[1]) == "--fuzz") {
        std::string s_uid, s_lvl, s_quota, s_weight, s_act, s_seed;
        while (std::cin >> s_uid >> s_lvl >> s_quota >> s_weight >> s_act >> s_seed) {
            uint64_t uid = std::strtoull(s_uid.c_str(), nullptr, 0);
            uint32_t lvl = static_cast<uint32_t>(std::strtoul(s_lvl.c_str(), nullptr, 0));
            double quota = std::strtod(s_quota.c_str(), nullptr);
            double weight = std::strtod(s_weight.c_str(), nullptr);
            int act = std::atoi(s_act.c_str());
            uint64_t seed = std::strtoull(s_seed.c_str(), nullptr, 0);

            TokenPayload token {
                .user_id = uid,
                .level = static_cast<SecurityLevel>(lvl),
                .quota = quota,
                .extra_weight = weight,
                .is_active = (act != 0)
            };
            uint64_t res = evaluate_security_rules(token, seed);
            std::cout << "0x" << std::hex << res << "\n";
        }
        return 0;
    }

    TokenPayload token {
        .user_id = 12345,
        .level = SecurityLevel::Admin,
        .quota = 250.5,
        .extra_weight = 2.0,
        .is_active = true
    };

    uint64_t seed = 0xA1B2C3D4ULL;

    uint64_t res = evaluate_security_rules(token, seed);
    std::cout << "[CPP-TEST] Result: 0x" << std::hex << res << std::dec << " (" << res << ")\n";

    return (res != 0) ? 0 : 1;
}
