// [ASGARD Tech-2608] Anti-Trace-Synthesis & Memory Chaffing Active
#include "asg_tech_2608.hpp"

// [ASGARD Tech-2603] Anti-VPC-Tracking & Non-Linear Dispatch Active
#include "asg_tech_2603.hpp"

// [ASGARD Tech-2601] ABI-Compliant Exception Handling Shadowing Active
// Shadow Allocation: 32 bytes | Interceptor: tech_2601_interceptor
#include "asg_tech_2601.hpp"

#pragma once

#define ASGARD_MULTI_VM_ENABLED 1

// =========================================================================

// ASGARD-5877: HETEROGENEOUS DUAL-VM RUNTIME (MATH-VM & FLOW-VM)

// In-Place Affine State Morphing & Zero-Native Dispatch

// =========================================================================

#include <stdint.h>

#include <stdbool.h>

#include <string.h>

// ASGARD-5877: ZERO-NATIVE IN-PLACE INTER-VM DISPATCH BRIDGE

// Affine GL_16(Z/2^64Z) State Morphing with Dynamic Trace Coupling

#define ASGARD_MULTI_VM_DIM 16

static const uint64_t ASGARD_INITIAL_DIGEST = 0x7fbf5f7fbf4fa6d1ULL;

static const uint64_t BRIDGE_FWD_MAT[16][16] = {
    {
        0x38ee0d7add15dc5dULL,
        0x633ec95dcb9b9154ULL,
        0x2fc8302fd6105acdULL,
        0x2a65276894683ed4ULL,
        0x32c808629f3c207fULL,
        0x594e13e8806177edULL,
        0x3d7f98d8d9ffd4d1ULL,
        0x4ad0a957823505e9ULL,
        0x6c6b0d0b4ed367f1ULL,
        0x1ead4bbccc7568c9ULL,
        0x7dd102f5a5f0f8f7ULL,
        0x1c66ab6a4e412ad6ULL,
        0x6be349758ff9e143ULL,
        0x161196b8c37a8e0dULL,
        0x6ec58de435c0ab0dULL,
        0x49937bc15a9fe302ULL
    },
    {
        0x0000000000000000ULL,
        0x43ef30aab7536d41ULL,
        0x0612870fc432d22bULL,
        0x1457ff3f80c2f519ULL,
        0x29417fc388801d24ULL,
        0x1b62a41491e7ee00ULL,
        0x4e485f5bf0017c85ULL,
        0x42ca76ac36ea9cc5ULL,
        0x4942f99cdc53c3a6ULL,
        0x758fff0893ce115bULL,
        0x7ac2664a1959a9ffULL,
        0x25b6db1139134463ULL,
        0x640476e0499c7fa9ULL,
        0x12ece6344af62347ULL,
        0x288fa3ef75e03d31ULL,
        0x0f4622f6f6e5a7feULL
    },
    {
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0c44ad4cadadfdcfULL,
        0x7fa4dede56bf6f4dULL,
        0x57a4641c28b1e7bfULL,
        0x3d1d252dd4277ca8ULL,
        0x14cbbb1d60cfb1e4ULL,
        0x1af32f2fb6f5d241ULL,
        0x496f01f0430c0f4cULL,
        0x1e4abd0d42d71238ULL,
        0x6551ccd91df8e203ULL,
        0x05e58ee0e89b5dc7ULL,
        0x1188995031c205c9ULL,
        0x1e87a42d8d1d77f9ULL,
        0x005848688acced6bULL,
        0x74fcbf5815017f36ULL
    },
    {
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x7343947eb1e9a96fULL,
        0x654ac2e047737614ULL,
        0x109d0aa79277684aULL,
        0x4b71680b6a089d9dULL,
        0x3545e0680bfa0565ULL,
        0x0bf7c4df934839ebULL,
        0x66fbac54763e96bbULL,
        0x73399a98544c6c38ULL,
        0x0f5a980872334834ULL,
        0x24f3d67990f392faULL,
        0x6631f466c6a94577ULL,
        0x1108f994e7b20f77ULL,
        0x4a4a0526a8820b5bULL
    },
    {
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x554c0219569d2eddULL,
        0x77a2168532087bb7ULL,
        0x139709909b212972ULL,
        0x4b93c9110c6dfbecULL,
        0x38aec46bd512afe9ULL,
        0x354bf90f1b350599ULL,
        0x53b670e4646bb516ULL,
        0x6513c534f3869c44ULL,
        0x08ef8a5059d7bde2ULL,
        0x3476da8db70149c0ULL,
        0x3cac74e056287ff9ULL,
        0x6c8c218ea81a7478ULL
    },
    {
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x45a2c1afc7aa5ab5ULL,
        0x3d37c0e701ba0cf4ULL,
        0x541f5c4dd0ff3179ULL,
        0x512538690279348dULL,
        0x240f0360541cfba6ULL,
        0x2298fc2b24d20d94ULL,
        0x7778ac452c51ea65ULL,
        0x1996593c29a1f18eULL,
        0x10920013f4d9e8e7ULL,
        0x39002ab9de48a674ULL,
        0x002d2000b0c8de0cULL
    },
    {
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x4f90926d775e3d47ULL,
        0x10aa00ef3c3dd120ULL,
        0x018dc4d47403931cULL,
        0x1e5fda362f17ca18ULL,
        0x38540cf75614f80aULL,
        0x2b947f10a9e14eb4ULL,
        0x1063081186983146ULL,
        0x00e137c3aa1af8bdULL,
        0x302c3d48df7b3a7fULL,
        0x23ce4b3de702b582ULL
    },
    {
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x71157847e2709733ULL,
        0x7738ea199e7e11acULL,
        0x1b04d03451d88b7bULL,
        0x15652116580f1e16ULL,
        0x0e6bb0a09f22b330ULL,
        0x7f815b4b74bb271eULL,
        0x6c24b31a87655c8eULL,
        0x119f6c751bbe1bbcULL,
        0x2e39c7681972a66bULL
    },
    {
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x72f43df943f4092fULL,
        0x05d706a0402c9828ULL,
        0x1948f499e509ad73ULL,
        0x35c4d441e6e8661eULL,
        0x4938a27fdf6919f1ULL,
        0x377f61a21e104314ULL,
        0x61f5aec83de33e7aULL,
        0x1651e0538158f2daULL
    },
    {
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x3318fb3c9e46cdd3ULL,
        0x3c86b90392671c55ULL,
        0x1e29d2aaeceeea3fULL,
        0x14cdd3a77b263083ULL,
        0x76d7fd967d4635abULL,
        0x628bfd26200bf2e4ULL,
        0x31a3f1ff1e25dc43ULL
    },
    {
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x5aee17579872a2f3ULL,
        0x451a8798670e14fbULL,
        0x76ecf674013a2f0dULL,
        0x1353635dd6b3566cULL,
        0x2808e85448a8d288ULL,
        0x53d678bdfac568c2ULL
    },
    {
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x24d91cae3269c36bULL,
        0x6022bf8b9c260587ULL,
        0x456d56efe29a72deULL,
        0x179f2ae1898804c6ULL,
        0x615f890192acb348ULL
    },
    {
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x74985a0d2f475bbdULL,
        0x26b1d5980e5b0af8ULL,
        0x36e46209b7bc22bdULL,
        0x004aea8f1cef987aULL
    },
    {
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x31e015568a498173ULL,
        0x3f712f18d1d6638dULL,
        0x09870df17948b169ULL
    },
    {
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x67cc99c0391e3067ULL,
        0x1052a7f80b5b18b7ULL
    },
    {
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x103ba2caa95da7adULL
    }
};

static const uint64_t BRIDGE_INV_MAT[16][16] = {
    {
        0x97d0708615ead7f5ULL,
        0xfc2155f945c00b9cULL,
        0xbf2c9c45bcb4bc75ULL,
        0xbf1def6f2755a2c1ULL,
        0x3e5e012556faeb5eULL,
        0xfddaaee1fe82729fULL,
        0xbad972430681625aULL,
        0x5e8a9018dfc89ebaULL,
        0xe70fc77efee4c995ULL,
        0x826154b57527bd0aULL,
        0xf2ed60a6d9d323dbULL,
        0x8e4eea4273b07d65ULL,
        0xb693dce6e5c53bafULL,
        0x7bbf5e7f7134d434ULL,
        0xc7701f7c86ae03eaULL,
        0xab20b2fee4c3ba15ULL
    },
    {
        0x0000000000000000ULL,
        0xe4588f59179822c1ULL,
        0xae3f90439230315bULL,
        0x11fb86679c26bfb8ULL,
        0x08ac72f49f4ecd03ULL,
        0xbec38058885a5e07ULL,
        0x52a893f1b755ff03ULL,
        0x2f274d2f9deffa57ULL,
        0x5b63f86cc0f4b470ULL,
        0x3ef22ff28c335a49ULL,
        0xedcdae7bbe40e34fULL,
        0x7de692b2719c2b6bULL,
        0xf80e5c8e94f120b1ULL,
        0xcf2f34c323eeb0c9ULL,
        0xfc623eb73327418aULL,
        0x408921cfc408a5e3ULL
    },
    {
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x9e5a01874663e92fULL,
        0x2280caf74de11173ULL,
        0x5e2cab0769920b0fULL,
        0x766e9a8a9857120dULL,
        0x0bc07b71189b209dULL,
        0x355d5cac6c6f3083ULL,
        0x78ac0cd833f30775ULL,
        0xfaaa6da16f225f7bULL,
        0xc3ddc107758e7741ULL,
        0x8724a1c5b455d6fcULL,
        0xcde1447f53de5568ULL,
        0x3dc516b1a7297067ULL,
        0xb1a95afa7a564475ULL,
        0x1e978334c374644bULL
    },
    {
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x6e1400d8a90fd58fULL,
        0x373f814b69dfb2e4ULL,
        0x3dc3cedf6e6a17b6ULL,
        0x0ef7bb8a1d4422cbULL,
        0xef455716dafcee05ULL,
        0xdfe60a49b9fd4fe7ULL,
        0x9c4fb7b22a2409d4ULL,
        0xa8bc6356d8ff8cd1ULL,
        0xa8b84c9f89ec6483ULL,
        0xad23822af48ea675ULL,
        0x81eabd4ba9d79816ULL,
        0xf409e4833bc27d9dULL,
        0x1fae3196cb4a1da3ULL
    },
    {
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x773f77483a8e1975ULL,
        0xc159d4b6962f8e09ULL,
        0x924458b2bb7a7e1eULL,
        0x8b2a3c29b40baf51ULL,
        0x2e9c3b81c8319946ULL,
        0xbe234874d97275e6ULL,
        0x15e95cb59dc9ed04ULL,
        0xbc4b876d93446c57ULL,
        0x24b8a34ab24535cdULL,
        0x8310fc17af66bca3ULL,
        0x301f6e9ca4084005ULL,
        0x15b63aba6ef3b3f3ULL
    },
    {
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0xa2093d8af445439dULL,
        0x94acecec8f3278c4ULL,
        0xfea27e98d8852d89ULL,
        0xf1bf7af51ea7dbe5ULL,
        0x217808dab3014e8dULL,
        0xa758826616b447eaULL,
        0xa141949f521641c8ULL,
        0xb30761421c4168c6ULL,
        0xf432137e42dbe108ULL,
        0xc6bafb61d8802688ULL,
        0x3333007e64775380ULL
    },
    {
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x901e8d2997745c77ULL,
        0x4fd92eb315720d60ULL,
        0x2fd34907bdd80f44ULL,
        0xe4dcbf1d2904bd88ULL,
        0xa3934eb8ffb64882ULL,
        0x1186bafddc1770caULL,
        0x8332fcc3d98d3b02ULL,
        0x33f2daad2a5bdcd3ULL,
        0xa040368c192e4f3eULL,
        0xa36dc0102a0188a1ULL
    },
    {
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0xa742b1b788313bfbULL,
        0x0d4befcf3e542e64ULL,
        0x25baf60f6ce0cbbdULL,
        0x27830297a13bbd7bULL,
        0x0794e55644ceb054ULL,
        0xb675e14b490014f0ULL,
        0x17d6ed4f51b1ffd9ULL,
        0x4dec6fa303af8e1dULL,
        0x2e4283bf65eaa65eULL
    },
    {
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x17ac94b7ec71ddcfULL,
        0x1ba1c569b0bb80b8ULL,
        0x5ef378f486f13129ULL,
        0xa5911c4c3784cd89ULL,
        0x43600000da7ca709ULL,
        0xcc6441e88bebf5feULL,
        0xed137dbd7dbd34a7ULL,
        0x6cfa255dfbc47c7bULL
    },
    {
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0xfbf0b9c58eb4125bULL,
        0xe60ae0b8f9652553ULL,
        0x14a7a80d2f2a542eULL,
        0x6387bde38fb9df2eULL,
        0x284ac7eb67b95885ULL,
        0xf988b0f52606fec7ULL,
        0xbbc3be93bf1e28fbULL
    },
    {
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0xd1a9092a4c62463bULL,
        0xf7dcb95a3462f935ULL,
        0xf0a633067f492826ULL,
        0xdc0ef73c63a622d2ULL,
        0x946bc811a500dd3eULL,
        0xcb691b73ff823f5aULL
    },
    {
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0xdc8693bf72b75143ULL,
        0x3297e5273610ae87ULL,
        0x274c128e6adc62eaULL,
        0x5ad7bd65aea640b7ULL,
        0xe052cd6f5da36203ULL
    },
    {
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x164398c53cea3795ULL,
        0x22726c4972c5c9b8ULL,
        0xf0fc0e616e220bc1ULL,
        0x7a5d041101a0d3abULL
    },
    {
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x338111659ba78bbbULL,
        0x9a3b2a26ce2fca57ULL,
        0x101539b08a3f510cULL
    },
    {
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0xfc7f72e6bfd9eb57ULL,
        0xa87d5e9ff0b795ebULL
    },
    {
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0xc8859ac8aa7a5425ULL
    }
};

static __attribute__((always_inline)) inline uint64_t bridge_rol64(uint64_t v, int32_t s) {

    s &= 63;
    return ((v << s) | (v >> (64 - s)));
}

static __attribute__((always_inline)) inline uint64_t bridge_update_digest(uint64_t prev, uint64_t op, uint64_t vip) {

    uint64_t k1 = bridge_rol64(prev, 13);
    uint64_t term = (op + (vip * 0x9e3779b97f4a7c15ULL));
    return (k1 ^ term);
}

static __attribute__((always_inline)) inline void in_place_morph_math_to_flow(uint64_t* math_regs, uint64_t* flow_stack, uint64_t trace_digest) {

    uint64_t temp[16];
    for (size_t i = 0; i < 16; ++i) {
                                         uint64_t sum = 0x0000000000000000ULL;
                                         for (size_t j = 0; j < 16; ++j) {
                                         
                                             sum += (BRIDGE_FWD_MAT[i][j] * math_regs[j]);
                                         }
                                         temp[i] = (sum ^ bridge_rol64(trace_digest, ((i * 3) + 7)));
    }
    for (size_t i = 0; i < 16; ++i) {
                                         flow_stack[i] = temp[i];
    }
}

static __attribute__((always_inline)) inline void in_place_morph_flow_to_math(uint64_t* flow_stack, uint64_t* math_regs, uint64_t trace_digest) {

    uint64_t unmasked[16];
    for (size_t i = 0; i < 16; ++i) {
                                         unmasked[i] = (flow_stack[i] ^ bridge_rol64(trace_digest, ((i * 3) + 7)));
    }
    for (size_t i = 0; i < 16; ++i) {
                                         uint64_t sum = 0x0000000000000000ULL;
                                         for (size_t j = 0; j < 16; ++j) {
                                         
                                             sum += (BRIDGE_INV_MAT[i][j] * unmasked[j]);
                                         }
                                         math_regs[i] = sum;
    }
}


namespace asgard_multi_vm {
                           
                           struct MathVMContext {
                                                     uint64_t gprs[32];
                                                     uint64_t vip;
                                                     uint64_t rns_slots[4];
                                                     uint64_t trace_digest;
                                                     __attribute__((always_inline)) inline void init(uint64_t init_digest) {
                                                     
                                                         memset(this, 0, sizeof((*this)));
                                                         trace_digest = init_digest;
                                                     }
                                                     
                           };
                           
                           struct FlowVMContext {
                                                     uint64_t vstack[64];
                                                     uint64_t vsp;
                                                     uint64_t vip;
                                                     uint64_t state_var;
                                                     uint64_t trace_digest;
                                                     __attribute__((always_inline)) inline void init(uint64_t init_digest) {
                                                     
                                                         memset(this, 0, sizeof((*this)));
                                                         trace_digest = init_digest;
                                                     }
                                                     
                           };
                           
                           union SharedVMContext {
                                                      MathVMContext math;
                                                      FlowVMContext flow;
                                                      uint8_t raw[1024];
                                                      
                           };
                           
                           static __attribute__((always_inline)) inline void bridge_switch_to_flow(SharedVMContext& ctx) {
                           
                               uint64_t cur_digest = ctx.math.trace_digest;
                               uint64_t temp_math_regs[16];
                               for (size_t i = 0; i < 16; ++i) {
                                                                    temp_math_regs[i] = ctx.math.gprs[i];
                               }
                               ctx.flow.init(cur_digest);
                               in_place_morph_math_to_flow(temp_math_regs, ctx.flow.vstack, cur_digest);
                           }
                           
                           static __attribute__((always_inline)) inline void bridge_switch_to_math(SharedVMContext& ctx) {
                           
                               uint64_t cur_digest = ctx.flow.trace_digest;
                               uint64_t temp_flow_stack[16];
                               for (size_t i = 0; i < 16; ++i) {
                                                                    temp_flow_stack[i] = ctx.flow.vstack[i];
                               }
                               ctx.math.init(cur_digest);
                               in_place_morph_flow_to_math(temp_flow_stack, ctx.math.gprs, cur_digest);
                           }

} // namespace asgard_multi_vm


// Threaded base engine integration

#pragma once

#if __has_include("vanguard/platform_compat.hpp")
#include "vanguard/platform_compat.hpp"
#include "vanguard/crypto_primitives.hpp"
#include "vanguard/sanitization.hpp"
#else
#pragma once
// ============================================================================
// ASGARD-5877 Vanguard Runtime: Platform Compatibility Layer
// Supports Clang, GCC, and MSVC across macOS, Linux, and Windows.
// ============================================================================

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <atomic>
#include <bit>
#include <cstring>
#include <algorithm>
#include <cmath>

#if !defined(_WIN32) && !defined(_WIN64)
#include <dlfcn.h>
#endif

#if !defined(RTLD_DEFAULT)
#define RTLD_DEFAULT ((void*)0)
#endif

#if defined(__APPLE__)
#include <sys/types.h>
#include <sys/sysctl.h>
#include <unistd.h>
#include <mach/mach.h>
#include <mach/thread_act.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#elif defined(__linux__)
#include <fcntl.h>
#include <unistd.h>
#include <string.h>
#elif defined(_WIN32) || defined(_WIN64)
#include <windows.h>
#include <time.h>
#ifndef CLOCK_MONOTONIC
#define CLOCK_MONOTONIC 1
#endif
#ifndef CLOCK_REALTIME
#define CLOCK_REALTIME 0
#endif
static inline int clock_gettime(int, struct timespec* ts) {
    if (!ts) return -1;
    LARGE_INTEGER freq, counter;
    QueryPerformanceFrequency(&freq);
    QueryPerformanceCounter(&counter);
    ts->tv_sec = (time_t)(counter.QuadPart / freq.QuadPart);
    ts->tv_nsec = (long)(((counter.QuadPart % freq.QuadPart) * 1000000000LL) / freq.QuadPart);
    return 0;
}
#endif

#if defined(_MSC_VER) && !defined(__clang__)
#include <intrin.h>
#include <malloc.h>
#ifndef __attribute__
#define __attribute__(x)
#endif
#ifndef __builtin_expect
#define __builtin_expect(expr, c) (expr)
#endif
#ifndef __builtin_bswap16
#define __builtin_bswap16(x) _byteswap_ushort(x)
#endif
#ifndef __builtin_bswap32
#define __builtin_bswap32(x) _byteswap_ulong(x)
#endif
#ifndef __builtin_bswap64
#define __builtin_bswap64(x) _byteswap_uint64(x)
#endif
#ifndef __builtin_alloca
#define __builtin_alloca(x) _alloca(x)
#endif
static inline int __builtin_clz(uint32_t x) { return std::countl_zero(x); }
static inline int __builtin_clzll(uint64_t x) { return std::countl_zero(x); }
static inline int __builtin_ctz(uint32_t x) { return std::countr_zero(x); }
static inline int __builtin_ctzll(uint64_t x) { return std::countr_zero(x); }
static inline int __builtin_popcount(uint32_t x) { return std::popcount(x); }
static inline int __builtin_popcountll(uint64_t x) { return std::popcount(x); }
static inline uint64_t __builtin_ia32_rdtsc() {
#if defined(_M_X64) || defined(_M_IX86)
    return __rdtsc();
#elif defined(_M_ARM64)
    return (uint64_t)_ReadStatusReg(ARM64_CNTVCT);
#else
    return 0;
#endif
}
#define __ATOMIC_RELAXED 0
#define __ATOMIC_CONSUME 1
#define __ATOMIC_ACQUIRE 2
#define __ATOMIC_RELEASE 3
#define __ATOMIC_ACQ_REL 4
#define __ATOMIC_SEQ_CST 5

template <typename T>
static inline T __atomic_load_n(const volatile T* ptr, int) {
    return std::atomic_ref<T>(*const_cast<T*>(ptr)).load();
}
template <typename T, typename V>
static inline void __atomic_store_n(volatile T* ptr, V val, int) {
    std::atomic_ref<T>(*const_cast<T*>(ptr)).store(static_cast<T>(val));
}
template <typename T, typename V>
static inline T __atomic_exchange_n(volatile T* ptr, V val, int) {
    return std::atomic_ref<T>(*const_cast<T*>(ptr)).exchange(static_cast<T>(val));
}
template <typename T, typename V>
static inline bool __atomic_compare_exchange_n(volatile T* ptr, T* expected, V desired, bool, int, int) {
    return std::atomic_ref<T>(*const_cast<T*>(ptr)).compare_exchange_strong(*expected, static_cast<T>(desired));
}
template <typename T, typename V>
static inline T __atomic_fetch_add(volatile T* ptr, V val, int) {
    return std::atomic_ref<T>(*const_cast<T*>(ptr)).fetch_add(static_cast<T>(val));
}
static inline void __atomic_thread_fence(int) {
    std::atomic_thread_fence(std::memory_order_seq_cst);
}
#endif

#if defined(__GNUC__) || defined(__clang__)
#define ASG_CALL_NOINLINE __attribute__((noinline))
#elif defined(_MSC_VER)
#define ASG_CALL_NOINLINE __declspec(noinline)
#else
#define ASG_CALL_NOINLINE
#endif

#pragma once
// ============================================================================
// ASGARD-5877 Vanguard Runtime: Cryptographic Primitives & Dynamic Resolution
// FNV-1a, Mach-O Dyld Exports Trie Resolver, Dynamic Symbol Decryption
// ============================================================================

#ifndef ASGARD_CRYPTO_PRIMITIVES_DEFINED
#define ASGARD_CRYPTO_PRIMITIVES_DEFINED
#define ASGARD_API_HASH_RESOLVER_DEFINED 1

static constexpr inline uint32_t asgard_fnv1a_const(const char* str, uint32_t hash = 0x811C9DC5U) noexcept {
    return (*str == 0) ? hash : asgard_fnv1a_const(str + 1, (hash ^ static_cast<uint8_t>(*str)) * 0x01000193U);
}

static inline int asg_strcmp(const char* s1, const char* s2) noexcept {
    if (!s1 || !s2) return (s1 == s2) ? 0 : (s1 ? 1 : -1);
    while (*s1 && (*s1 == *s2)) { s1++; s2++; }
    return *(const unsigned char*)s1 - *(const unsigned char*)s2;
}

#if defined(__APPLE__) && defined(__MACH__)
#include <mach-o/dyld.h>
#include <mach-o/loader.h>

static inline uint64_t asg_read_uleb128(const uint8_t** p) noexcept {
    uint64_t result = 0;
    int shift = 0;
    while (1) {
        uint8_t byte = *(*p)++;
        result |= ((uint64_t)(byte & 0x7f)) << shift;
        if ((byte & 0x80) == 0) break;
        shift += 7;
    }
    return result;
}

static inline void* asg_find_sym_in_trie(const uint8_t* trie_base, const uint8_t* node, uint32_t cur_h, uint32_t target_h, uintptr_t base) noexcept {
    const uint8_t* p = node;
    uint64_t terminal_size = asg_read_uleb128(&p);
    if (terminal_size > 0 && cur_h == target_h) {
        uint64_t flags = asg_read_uleb128(&p);
        if ((flags & 0x08) == 0) {
            uint64_t addr = asg_read_uleb128(&p);
            return (void*)(addr + base);
        }
        return nullptr;
    }
    p += terminal_size;
    uint8_t child_count = *p++;
    for (uint8_t i = 0; i < child_count; i++) {
        uint32_t child_h = cur_h;
        while (*p) {
            child_h = (child_h ^ (uint8_t)*p++) * 0x01000193U;
        }
        p++; /* skip null terminator */
        uint64_t child_offset = asg_read_uleb128(&p);
        void* res = asg_find_sym_in_trie(trie_base, trie_base + child_offset, child_h, target_h, base);
        if (res) return res;
    }
    return nullptr;
}

static inline void* asgard_resolve_by_api_hash(uint32_t target_hash) noexcept {
    if (target_hash == 0) return nullptr;
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const struct mach_header_64* hdr = (const struct mach_header_64*)_dyld_get_image_header(i);
        if (!hdr || hdr->magic != MH_MAGIC_64) continue;
        intptr_t slide = _dyld_get_image_vmaddr_slide(i);
        const struct load_command* cmd = (const struct load_command*)(hdr + 1);
        uintptr_t linkedit_base = 0;
        uint32_t dataoff = 0;
        for (uint32_t c = 0; c < hdr->ncmds; c++) {
            if (cmd->cmd == LC_SEGMENT_64) {
                const struct segment_command_64* seg = (const struct segment_command_64*)cmd;
                if (asg_strcmp(seg->segname, "__LINKEDIT") == 0) {
                    linkedit_base = seg->vmaddr + slide - seg->fileoff;
                }
            } else if (cmd->cmd == 0x80000033 /* LC_DYLD_EXPORTS_TRIE */) {
                const struct linkedit_data_command* lc = (const struct linkedit_data_command*)cmd;
                dataoff = lc->dataoff;
            }
            cmd = (const struct load_command*)((const char*)cmd + cmd->cmdsize);
        }
        if (linkedit_base && dataoff) {
            const uint8_t* trie = (const uint8_t*)(linkedit_base + dataoff);
            void* resolved = asg_find_sym_in_trie(trie, trie, 0x811c9dc5U, target_hash, (uintptr_t)hdr);
            if (resolved) return resolved;
        }
    }
    return nullptr;
}
#else
static inline void* asgard_resolve_by_api_hash(uint32_t) noexcept { return nullptr; }
#endif

typedef struct {
    uint32_t hash;
    uint32_t alt_hash;
    uint16_t len;
    uint8_t enc_bytes[64];
} asgard_ext_sym_t;

static inline void asg_decrypt_sym(const asgard_ext_sym_t* sym, char* out_buf, size_t out_cap) noexcept {
    size_t n = sym->len < out_cap - 1 ? sym->len : out_cap - 1;
    for (size_t i = 0; i < n; i++) {
        uint8_t k = (uint8_t)(0x5A ^ ((i * 17 + 0x33) & 0xFF));
        out_buf[i] = (char)(sym->enc_bytes[i] ^ k);
    }
    out_buf[n] = '\0';
}

struct AsgardConstantEntry {
    uint32_t hash;
    uint32_t alt_hash;
    const uint8_t* enc_data;
    uint8_t* dec_data;
    size_t size;
    uint32_t xor_key;
    volatile int ready;
};

#endif // ASGARD_CRYPTO_PRIMITIVES_DEFINED

#pragma once
// ============================================================================
// ASGARD-5877 Vanguard Runtime: Memory Sanitization & Anti-Forensics
// Ephemeral Memory Scrubbing, Rolling Noise Invalidation, Canary Verification
// ============================================================================

#ifndef ASGARD_SANITIZATION_DEFINED
#define ASGARD_SANITIZATION_DEFINED

#define SCRUB_WORD(ptr, val) do { \
    *(reinterpret_cast<volatile uint64_t*>(ptr)) = (val); \
} while(0)

namespace asgard_sanitization {

static inline void scrub_memory_range(volatile uint64_t* ptr, size_t count, uint64_t noise_seed) noexcept {
    if (!ptr || count == 0) return;
    for (size_t i = 0; i < count; ++i) {
        ptr[i] = (noise_seed * 0x6A09E667F3BCC908ULL) ^ 0x5877CAFE1337BEEFULL ^ (uint64_t)i;
    }
}

static inline void ephemeral_wipe_buffer(void* ptr, size_t byte_count) noexcept {
    if (!ptr || byte_count == 0) return;
    volatile uint8_t* p = reinterpret_cast<volatile uint8_t*>(ptr);
    for (size_t i = 0; i < byte_count; ++i) {
        p[i] = static_cast<uint8_t>(0x5A ^ ((i * 37 + 0x7F) & 0xFF));
    }
    for (size_t i = 0; i < byte_count; ++i) {
        p[i] = 0;
    }
}

} // namespace asgard_sanitization

#endif // ASGARD_SANITIZATION_DEFINED

#endif

#define ASGARD_VECTOR_ISA 1

#if defined(__aarch64__)
#include <arm_neon.h>
#elif defined(__x86_64__)
#include <immintrin.h>
#endif

#pragma once
// =========================================================================

// ASGARD-5877: RESIDUE NUMBER SYSTEM (RNS-4) & GARNER CRT ARITHMETIC

// Non-Linear Diophantine Residue Channels for Anti-SMT Hardening

// =========================================================================

#include <stdint.h>

namespace asgard_rns {
                      
                      static constexpr uint64_t M1 = 0x0000000000010001ULL;
                      
                      static constexpr uint64_t M2 = 0x000000000000fff1ULL;
                      
                      static constexpr uint64_t M3 = 0x000000000000ffefULL;
                      
                      static constexpr uint64_t M4 = 0x000000000000ffd9ULL;
                      
                      static constexpr uint64_t INV_M1_M2 = 0x000000000000eff2ULL;
                      
                      static constexpr uint64_t INV_M1_M3 = 0x0000000000000e38ULL;
                      
                      static constexpr uint64_t INV_M1_M4 = 0x0000000000002cc6ULL;
                      
                      static constexpr uint64_t INV_M2_M3 = 0x0000000000007ff8ULL;
                      
                      static constexpr uint64_t INV_M2_M4 = 0x000000000000f530ULL;
                      
                      static constexpr uint64_t INV_M3_M4 = 0x0000000000005168ULL;
                      
                      struct RNSVal {
                                         uint64_t r1;
                                         uint64_t r2;
                                         uint64_t r3;
                                         uint64_t r4;
                                         
                      };
                      
                      static __attribute__((always_inline)) inline RNSVal encode(uint64_t x) noexcept {
                      
                          return { (x % M1), (x % M2), (x % M3), (x % M4) };
                      }
                      
                      static __attribute__((always_inline)) inline RNSVal add(RNSVal a, RNSVal b) noexcept {
                      
                          return { ((a.r1 + b.r1) % M1), ((a.r2 + b.r2) % M2), ((a.r3 + b.r3) % M3), ((a.r4 + b.r4) % M4) };
                      }
                      
                      static __attribute__((always_inline)) inline RNSVal sub(RNSVal a, RNSVal b) noexcept {
                      
                          return { (((a.r1 + M1) - (b.r1 % M1)) % M1), (((a.r2 + M2) - (b.r2 % M2)) % M2), (((a.r3 + M3) - (b.r3 % M3)) % M3), (((a.r4 + M4) - (b.r4 % M4)) % M4) };
                      }
                      
                      static __attribute__((always_inline)) inline RNSVal mul(RNSVal a, RNSVal b) noexcept {
                      
                          return { ((a.r1 * (b.r1 % M1)) % M1), ((a.r2 * (b.r2 % M2)) % M2), ((a.r3 * (b.r3 % M3)) % M3), ((a.r4 * (b.r4 % M4)) % M4) };
                      }
                      
                      static __attribute__((always_inline)) inline uint64_t decode(RNSVal r) noexcept {
                      
                          uint64_t v1 = r.r1;
                          uint64_t diff2 = (((r.r2 + M2) - (v1 % M2)) % M2);
                          uint64_t v2 = ((diff2 * INV_M1_M2) % M2);
                          uint64_t diff1_3 = (((r.r3 + M3) - (v1 % M3)) % M3);
                          uint64_t term1_3 = ((diff1_3 * INV_M1_M3) % M3);
                          uint64_t diff2_3 = (((term1_3 + M3) - (v2 % M3)) % M3);
                          uint64_t v3 = ((diff2_3 * INV_M2_M3) % M3);
                          uint64_t diff1_4 = (((r.r4 + M4) - (v1 % M4)) % M4);
                          uint64_t term1_4 = ((diff1_4 * INV_M1_M4) % M4);
                          uint64_t diff2_4 = (((term1_4 + M4) - (v2 % M4)) % M4);
                          uint64_t term2_4 = ((diff2_4 * INV_M2_M4) % M4);
                          uint64_t diff3_4 = (((term2_4 + M4) - (v3 % M4)) % M4);
                          uint64_t v4 = ((diff3_4 * INV_M3_M4) % M4);
                          uint64_t term_v2 = (v2 * M1);
                          uint64_t term_v3 = (v3 * (M1 * M2));
                          uint64_t term_v4 = (v4 * ((M1 * M2) * M3));
                          return (((v1 + term_v2) + term_v3) + term_v4);
                      }

} // namespace asgard_rns


#pragma once
// AUTO-GENERATED BY ASGARD-5877 TYPED C++20 EDSL

#include <cstdint>

namespace asgard::branchless_vip {
                                  
                                  __attribute__((always_inline)) inline constexpr uint64_t is_zero_u64(uint64_t d) noexcept {
                                  
                                      return (0x0000000000000001ULL - ((d | (0x0000000000000000ULL - d)) >> 0x000000000000003fULL));
                                  }
                                  
                                  __attribute__((always_inline)) inline constexpr uint64_t is_ult_u64(uint64_t x, uint64_t y) noexcept {
                                  
                                      uint64_t diff = (x - y);
                                      uint64_t borrow = (((~x) & y) | (((~x) | y) & diff));
                                      return (borrow >> 0x000000000000003fULL);
                                  }
                                  
                                  __attribute__((always_inline)) inline constexpr uint64_t is_slt_u64(uint64_t x, uint64_t y) noexcept {
                                  
                                      constexpr uint64_t SIGN_BIT = 0x8000000000000000ULL;
                                      return is_ult_u64((x ^ SIGN_BIT), (y ^ SIGN_BIT));
                                  }
                                  
                                  __attribute__((always_inline)) inline constexpr uint64_t select_vip(uint64_t cond_bit, uint64_t target_vip, uint64_t fallthrough_vip) noexcept {
                                  
                                      return (fallthrough_vip + (cond_bit * (target_vip - fallthrough_vip)));
                                  }

} // namespace asgard::branchless_vip



#pragma once
// AUTO-GENERATED BY ASGARD-5877 TYPED C++20 EDSL

#include <cstdint>

namespace asgard::chameleon_vm {
                                
                                struct alignas(32) DelayedCommitCtx {
                                
                                    uint64_t regs[32];
                                    uint32_t pending_reg;
                                    uint32_t has_pending;
                                    uint64_t pending_val;
                                    uint64_t pending_mask;
                                    
                                };
                                
                                __attribute__((always_inline)) inline void exec_chameleon_delayed_step(DelayedCommitCtx& ctx, uint32_t dst_reg, uint64_t x, uint64_t y, uint64_t w_xor, uint64_t w_and, uint64_t w_or, uint64_t next_mask) noexcept {
                                
                                    // 1. Commit result of PREVIOUS instruction (T-1) to break single-handler I/O oracle
                                    if (0 != ctx.has_pending) {
                                                                   ctx.regs[ctx.pending_reg] = (ctx.pending_val ^ ctx.pending_mask);
                                    }
                                    // 2. Evaluate universal polymorphic Chameleon ALU kernel for step T
                                    uint64_t tx = ((x ^ y) * w_xor);
                                    uint64_t ta = (w_and * (y & x));
                                    uint64_t to = (w_or * (x | y));
                                    uint64_t res = ((tx + ta) + to);
                                    // 3. Latch masked result into delayed pipeline queue for step T+1
                                    ctx.pending_reg = dst_reg;
                                    ctx.pending_mask = next_mask;
                                    ctx.pending_val = (next_mask ^ res);
                                    ctx.has_pending = 1;
                                }
                                
                                __attribute__((always_inline)) inline void flush_chameleon_pipeline(DelayedCommitCtx& ctx) noexcept {
                                
                                    if (0 != ctx.has_pending) {
                                                                   ctx.regs[ctx.pending_reg] = (ctx.pending_val ^ ctx.pending_mask);
                                                                   ctx.has_pending = 0;
                                    }
                                }

} // namespace asgard::chameleon_vm



#pragma once
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#if defined(__APPLE__) || defined(ASGARD_TARGET_DARWIN)
#include <sys/types.h>
#include <sys/sysctl.h>
#include <unistd.h>
#elif defined(__linux__) || defined(ASGARD_TARGET_LINUX)
#include <sys/types.h>
#include <unistd.h>
#include <fcntl.h>
#elif defined(_WIN32) || defined(ASGARD_TARGET_WINDOWS)
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <winternl.h>
#if defined(_MSC_VER)
#include <intrin.h>
#endif
#endif

#if defined(_WIN32) || defined(ASGARD_TARGET_WINDOWS)
#ifndef _PID_T_DEFINED
#define _PID_T_DEFINED
typedef int pid_t;
#endif
#endif

#define ASGARD_DIRECT_SYSCALLS_ENABLED 1

namespace asgard_syscalls {

#if (defined(__APPLE__) || defined(ASGARD_TARGET_DARWIN)) && (defined(__arm64__) || defined(__aarch64__))
// Direct Darwin ARM64 Syscall Stub (SVC #0x80 with BSD class 0x2000000)
static inline __attribute__((always_inline)) int64_t direct_syscall_0(int64_t sys_num) noexcept {
    register int64_t x16 __asm__("x16") = sys_num;
    register int64_t x0  __asm__("x0");
    __asm__ volatile("svc #0x80" : "=r"(x0) : "r"(x16) : "memory", "cc");
    return x0;
}
static inline __attribute__((always_inline)) int64_t direct_syscall_1(int64_t sys_num, int64_t a1) noexcept {
    register int64_t x16 __asm__("x16") = sys_num;
    register int64_t x0  __asm__("x0")  = a1;
    __asm__ volatile("svc #0x80" : "+r"(x0) : "r"(x16) : "memory", "cc");
    return x0;
}
static inline __attribute__((always_inline)) int64_t direct_syscall_2(int64_t sys_num, int64_t a1, int64_t a2) noexcept {
    register int64_t x16 __asm__("x16") = sys_num;
    register int64_t x0  __asm__("x0")  = a1;
    register int64_t x1  __asm__("x1")  = a2;
    __asm__ volatile("svc #0x80" : "+r"(x0) : "r"(x16), "r"(x1) : "memory", "cc");
    return x0;
}
static inline __attribute__((always_inline)) int64_t direct_syscall_3(int64_t sys_num, int64_t a1, int64_t a2, int64_t a3) noexcept {
    register int64_t x16 __asm__("x16") = sys_num;
    register int64_t x0  __asm__("x0")  = a1;
    register int64_t x1  __asm__("x1")  = a2;
    register int64_t x2  __asm__("x2")  = a3;
    __asm__ volatile("svc #0x80" : "+r"(x0) : "r"(x16), "r"(x1), "r"(x2) : "memory", "cc");
    return x0;
}
static inline __attribute__((always_inline)) int64_t direct_syscall_4(int64_t sys_num, int64_t a1, int64_t a2, int64_t a3, int64_t a4) noexcept {
    register int64_t x16 __asm__("x16") = sys_num;
    register int64_t x0  __asm__("x0")  = a1;
    register int64_t x1  __asm__("x1")  = a2;
    register int64_t x2  __asm__("x2")  = a3;
    register int64_t x3  __asm__("x3")  = a4;
    __asm__ volatile("svc #0x80" : "+r"(x0) : "r"(x16), "r"(x1), "r"(x2), "r"(x3) : "memory", "cc");
    return x0;
}
static inline __attribute__((always_inline)) int64_t direct_syscall_6(int64_t sys_num, int64_t a1, int64_t a2, int64_t a3, int64_t a4, int64_t a5, int64_t a6) noexcept {
    register int64_t x16 __asm__("x16") = sys_num;
    register int64_t x0  __asm__("x0")  = a1;
    register int64_t x1  __asm__("x1")  = a2;
    register int64_t x2  __asm__("x2")  = a3;
    register int64_t x3  __asm__("x3")  = a4;
    register int64_t x4  __asm__("x4")  = a5;
    register int64_t x5  __asm__("x5")  = a6;
    __asm__ volatile("svc #0x80" : "+r"(x0) : "r"(x16), "r"(x1), "r"(x2), "r"(x3), "r"(x4), "r"(x5) : "memory", "cc");
    return x0;
}
#elif defined(__x86_64__)
// Direct x86_64 Syscall Stub (syscall instruction)
static inline __attribute__((always_inline)) int64_t direct_syscall_0(int64_t sys_num) noexcept {
#if defined(__APPLE__) || defined(ASGARD_TARGET_DARWIN)
    int64_t num = (sys_num < 0x2000000) ? (0x2000000 | sys_num) : sys_num;
#else
    int64_t num = sys_num;
#endif
    int64_t ret;
    __asm__ volatile("syscall" : "=a"(ret) : "a"(num) : "rcx", "r11", "memory", "cc");
    return ret;
}
static inline __attribute__((always_inline)) int64_t direct_syscall_1(int64_t sys_num, int64_t a1) noexcept {
#if defined(__APPLE__) || defined(ASGARD_TARGET_DARWIN)
    int64_t num = (sys_num < 0x2000000) ? (0x2000000 | sys_num) : sys_num;
#else
    int64_t num = sys_num;
#endif
    int64_t ret;
    __asm__ volatile("syscall" : "=a"(ret) : "a"(num), "D"(a1) : "rcx", "r11", "memory", "cc");
    return ret;
}
static inline __attribute__((always_inline)) int64_t direct_syscall_2(int64_t sys_num, int64_t a1, int64_t a2) noexcept {
#if defined(__APPLE__) || defined(ASGARD_TARGET_DARWIN)
    int64_t num = (sys_num < 0x2000000) ? (0x2000000 | sys_num) : sys_num;
#else
    int64_t num = sys_num;
#endif
    int64_t ret;
    __asm__ volatile("syscall" : "=a"(ret) : "a"(num), "D"(a1), "S"(a2) : "rcx", "r11", "memory", "cc");
    return ret;
}
static inline __attribute__((always_inline)) int64_t direct_syscall_3(int64_t sys_num, int64_t a1, int64_t a2, int64_t a3) noexcept {
#if defined(__APPLE__) || defined(ASGARD_TARGET_DARWIN)
    int64_t num = (sys_num < 0x2000000) ? (0x2000000 | sys_num) : sys_num;
#else
    int64_t num = sys_num;
#endif
    int64_t ret;
    __asm__ volatile("syscall" : "=a"(ret) : "a"(num), "D"(a1), "S"(a2), "d"(a3) : "rcx", "r11", "memory", "cc");
    return ret;
}
static inline __attribute__((always_inline)) int64_t direct_syscall_4(int64_t sys_num, int64_t a1, int64_t a2, int64_t a3, int64_t a4) noexcept {
#if defined(__APPLE__) || defined(ASGARD_TARGET_DARWIN)
    int64_t num = (sys_num < 0x2000000) ? (0x2000000 | sys_num) : sys_num;
#else
    int64_t num = sys_num;
#endif
    int64_t ret;
    register int64_t r10 __asm__("r10") = a4;
    __asm__ volatile("syscall" : "=a"(ret) : "a"(num), "D"(a1), "S"(a2), "d"(a3), "r"(r10) : "rcx", "r11", "memory", "cc");
    return ret;
}
static inline __attribute__((always_inline)) int64_t direct_syscall_6(int64_t sys_num, int64_t a1, int64_t a2, int64_t a3, int64_t a4, int64_t a5, int64_t a6) noexcept {
#if defined(__APPLE__) || defined(ASGARD_TARGET_DARWIN)
    int64_t num = (sys_num < 0x2000000) ? (0x2000000 | sys_num) : sys_num;
#else
    int64_t num = sys_num;
#endif
    int64_t ret;
    register int64_t r10 __asm__("r10") = a4;
    register int64_t r8  __asm__("r8")  = a5;
    register int64_t r9  __asm__("r9")  = a6;
    __asm__ volatile("syscall" : "=a"(ret) : "a"(num), "D"(a1), "S"(a2), "d"(a3), "r"(r10), "r"(r8), "r"(r9) : "rcx", "r11", "memory", "cc");
    return ret;
}
#elif defined(__linux__) && (defined(__arm64__) || defined(__aarch64__))
// Linux AArch64 Direct Syscalls (SVC #0 with x8 syscall number)
static inline __attribute__((always_inline)) int64_t direct_syscall_0(int64_t sys_num) noexcept {
    register int64_t x8 __asm__("x8") = sys_num;
    register int64_t x0 __asm__("x0");
    __asm__ volatile("svc #0" : "=r"(x0) : "r"(x8) : "memory", "cc");
    return x0;
}
static inline __attribute__((always_inline)) int64_t direct_syscall_1(int64_t sys_num, int64_t a1) noexcept {
    register int64_t x8 __asm__("x8") = sys_num;
    register int64_t x0 __asm__("x0") = a1;
    __asm__ volatile("svc #0" : "+r"(x0) : "r"(x8) : "memory", "cc");
    return x0;
}
static inline __attribute__((always_inline)) int64_t direct_syscall_2(int64_t sys_num, int64_t a1, int64_t a2) noexcept {
    register int64_t x8 __asm__("x8") = sys_num;
    register int64_t x0 __asm__("x0") = a1;
    register int64_t x1 __asm__("x1") = a2;
    __asm__ volatile("svc #0" : "+r"(x0) : "r"(x8), "r"(x1) : "memory", "cc");
    return x0;
}
static inline __attribute__((always_inline)) int64_t direct_syscall_3(int64_t sys_num, int64_t a1, int64_t a2, int64_t a3) noexcept {
    register int64_t x8 __asm__("x8") = sys_num;
    register int64_t x0 __asm__("x0") = a1;
    register int64_t x1 __asm__("x1") = a2;
    register int64_t x2 __asm__("x2") = a3;
    __asm__ volatile("svc #0" : "+r"(x0) : "r"(x8), "r"(x1), "r"(x2) : "memory", "cc");
    return x0;
}
static inline __attribute__((always_inline)) int64_t direct_syscall_4(int64_t sys_num, int64_t a1, int64_t a2, int64_t a3, int64_t a4) noexcept {
    register int64_t x8 __asm__("x8") = sys_num;
    register int64_t x0 __asm__("x0") = a1;
    register int64_t x1 __asm__("x1") = a2;
    register int64_t x2 __asm__("x2") = a3;
    register int64_t x3 __asm__("x3") = a4;
    __asm__ volatile("svc #0" : "+r"(x0) : "r"(x8), "r"(x1), "r"(x2), "r"(x3) : "memory", "cc");
    return x0;
}
static inline __attribute__((always_inline)) int64_t direct_syscall_6(int64_t sys_num, int64_t a1, int64_t a2, int64_t a3, int64_t a4, int64_t a5, int64_t a6) noexcept {
    register int64_t x8 __asm__("x8") = sys_num;
    register int64_t x0 __asm__("x0") = a1;
    register int64_t x1 __asm__("x1") = a2;
    register int64_t x2 __asm__("x2") = a3;
    register int64_t x3 __asm__("x3") = a4;
    register int64_t x4 __asm__("x4") = a5;
    register int64_t x5 __asm__("x5") = a6;
    __asm__ volatile("svc #0" : "+r"(x0) : "r"(x8), "r"(x1), "r"(x2), "r"(x3), "r"(x4), "r"(x5) : "memory", "cc");
    return x0;
}
#elif defined(__linux__) && (defined(__riscv) || defined(__riscv__))
// Linux RISC-V Direct Syscalls (ECALL with a7 syscall number, return in a0)
static inline __attribute__((always_inline)) int64_t direct_syscall_0(int64_t sys_num) noexcept {
    register int64_t a7_reg __asm__("a7") = sys_num;
    register int64_t a0_reg __asm__("a0");
    __asm__ volatile("ecall" : "=r"(a0_reg) : "r"(a7_reg) : "memory");
    return a0_reg;
}
static inline __attribute__((always_inline)) int64_t direct_syscall_1(int64_t sys_num, int64_t a1) noexcept {
    register int64_t a7_reg __asm__("a7") = sys_num;
    register int64_t a0_reg __asm__("a0") = a1;
    __asm__ volatile("ecall" : "+r"(a0_reg) : "r"(a7_reg) : "memory");
    return a0_reg;
}
static inline __attribute__((always_inline)) int64_t direct_syscall_2(int64_t sys_num, int64_t a1, int64_t a2) noexcept {
    register int64_t a7_reg __asm__("a7") = sys_num;
    register int64_t a0_reg __asm__("a0") = a1;
    register int64_t a1_reg __asm__("a1") = a2;
    __asm__ volatile("ecall" : "+r"(a0_reg) : "r"(a7_reg), "r"(a1_reg) : "memory");
    return a0_reg;
}
static inline __attribute__((always_inline)) int64_t direct_syscall_3(int64_t sys_num, int64_t a1, int64_t a2, int64_t a3) noexcept {
    register int64_t a7_reg __asm__("a7") = sys_num;
    register int64_t a0_reg __asm__("a0") = a1;
    register int64_t a1_reg __asm__("a1") = a2;
    register int64_t a2_reg __asm__("a2") = a3;
    __asm__ volatile("ecall" : "+r"(a0_reg) : "r"(a7_reg), "r"(a1_reg), "r"(a2_reg) : "memory");
    return a0_reg;
}
static inline __attribute__((always_inline)) int64_t direct_syscall_4(int64_t sys_num, int64_t a1, int64_t a2, int64_t a3, int64_t a4) noexcept {
    register int64_t a7_reg __asm__("a7") = sys_num;
    register int64_t a0_reg __asm__("a0") = a1;
    register int64_t a1_reg __asm__("a1") = a2;
    register int64_t a2_reg __asm__("a2") = a3;
    register int64_t a3_reg __asm__("a3") = a4;
    __asm__ volatile("ecall" : "+r"(a0_reg) : "r"(a7_reg), "r"(a1_reg), "r"(a2_reg), "r"(a3_reg) : "memory");
    return a0_reg;
}
static inline __attribute__((always_inline)) int64_t direct_syscall_6(int64_t sys_num, int64_t a1, int64_t a2, int64_t a3, int64_t a4, int64_t a5, int64_t a6) noexcept {
    register int64_t a7_reg __asm__("a7") = sys_num;
    register int64_t a0_reg __asm__("a0") = a1;
    register int64_t a1_reg __asm__("a1") = a2;
    register int64_t a2_reg __asm__("a2") = a3;
    register int64_t a3_reg __asm__("a3") = a4;
    register int64_t a4_reg __asm__("a4") = a5;
    register int64_t a5_reg __asm__("a5") = a6;
    __asm__ volatile("ecall" : "+r"(a0_reg) : "r"(a7_reg), "r"(a1_reg), "r"(a2_reg), "r"(a3_reg), "r"(a4_reg), "r"(a5_reg) : "memory");
    return a0_reg;
}
#else
static inline int64_t direct_syscall_0(int64_t s) noexcept { (void)s; return 0; }
static inline int64_t direct_syscall_1(int64_t s, int64_t a) noexcept { (void)s; (void)a; return 0; }
static inline int64_t direct_syscall_2(int64_t s, int64_t a, int64_t b) noexcept { (void)s; (void)a; (void)b; return 0; }
static inline int64_t direct_syscall_3(int64_t s, int64_t a, int64_t b, int64_t c) noexcept { (void)s; (void)a; (void)b; (void)c; return 0; }
static inline int64_t direct_syscall_4(int64_t s, int64_t a, int64_t b, int64_t c, int64_t d) noexcept { (void)s; (void)a; (void)b; (void)c; (void)d; return 0; }
static inline int64_t direct_syscall_6(int64_t s, int64_t a, int64_t b, int64_t c, int64_t d, int64_t e, int64_t f) noexcept { (void)s; (void)a; (void)b; (void)c; (void)d; (void)e; (void)f; return 0; }
#endif

static inline pid_t sys_getpid() noexcept {
#if defined(__APPLE__) || defined(ASGARD_TARGET_DARWIN)
    return (pid_t)direct_syscall_0(20); // SYS_getpid
#elif defined(__linux__) && defined(__x86_64__)
    return (pid_t)direct_syscall_0(39); // SYS_getpid
#elif (defined(__linux__) || defined(ASGARD_TARGET_LINUX)) && (defined(__arm64__) || defined(__aarch64__) || defined(__riscv) || defined(__riscv__))
    return (pid_t)direct_syscall_0(172); // SYS_getpid
#elif defined(_WIN32) || defined(ASGARD_TARGET_WINDOWS)
    return (pid_t)GetCurrentProcessId();
#else
    return 0;
#endif
}

static inline int64_t sys_write(int fd, const void* buf, size_t count) noexcept {
#if defined(__APPLE__) || defined(ASGARD_TARGET_DARWIN)
    return direct_syscall_3(4, (int64_t)fd, (int64_t)buf, (int64_t)count); // SYS_write
#elif defined(__linux__) && defined(__x86_64__)
    return direct_syscall_3(1, (int64_t)fd, (int64_t)buf, (int64_t)count); // SYS_write
#elif (defined(__linux__) || defined(ASGARD_TARGET_LINUX)) && (defined(__arm64__) || defined(__aarch64__) || defined(__riscv) || defined(__riscv__))
    return direct_syscall_3(64, (int64_t)fd, (int64_t)buf, (int64_t)count); // SYS_write
#elif defined(_WIN32) || defined(ASGARD_TARGET_WINDOWS)
    HANDLE h = (fd == 1) ? GetStdHandle(STD_OUTPUT_HANDLE) :
               (fd == 2) ? GetStdHandle(STD_ERROR_HANDLE) : (HANDLE)(intptr_t)fd;
    if (h == NULL || h == INVALID_HANDLE_VALUE) return -1;
    DWORD written = 0;
    if (WriteFile(h, buf, (DWORD)count, &written, NULL)) return (int64_t)written;
    return -1;
#else
    return 0;
#endif
}

static inline void sys_exit(int status) noexcept {
#if defined(__APPLE__) || defined(ASGARD_TARGET_DARWIN)
    direct_syscall_1(1, (int64_t)status); // SYS_exit
#elif defined(__linux__) && defined(__x86_64__)
    direct_syscall_1(60, (int64_t)status); // SYS_exit
#elif (defined(__linux__) || defined(ASGARD_TARGET_LINUX)) && (defined(__arm64__) || defined(__aarch64__) || defined(__riscv) || defined(__riscv__))
    direct_syscall_1(93, (int64_t)status); // SYS_exit
#elif defined(_WIN32) || defined(ASGARD_TARGET_WINDOWS)
    ExitProcess((UINT)status);
#else
    _exit(status);
#endif
}

static inline bool sys_check_debugger_present() noexcept {
#if defined(__APPLE__) || defined(ASGARD_TARGET_DARWIN)
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_PID, (int)sys_getpid() };
    struct kinfo_proc kinfo = {};
    size_t ksize = sizeof(kinfo);
    int64_t res = direct_syscall_6(202, (int64_t)mib, 4, (int64_t)&kinfo, (int64_t)&ksize, 0, 0);
    if (res == 0 && (kinfo.kp_proc.p_flag & P_TRACED)) {
        return true;
    }
    return false;
#elif defined(__linux__) || defined(ASGARD_TARGET_LINUX)
    int fd = -1;
#if defined(__x86_64__)
    fd = (int)direct_syscall_2(2, (int64_t)"/proc/self/status", 0);
#elif defined(__arm64__) || defined(__aarch64__) || defined(__riscv) || defined(__riscv__)
    fd = (int)direct_syscall_4(56, -100, (int64_t)"/proc/self/status", 0, 0);
#endif
    if (fd < 0) return false;
    char buf[512];
    int64_t n = direct_syscall_3(0, (int64_t)fd, (int64_t)buf, sizeof(buf) - 1);
    direct_syscall_1(3, (int64_t)fd);
    if (n <= 0) return false;
    buf[n] = '\0';
    for (int64_t i = 0; i + 11 < n; ++i) {
        if (buf[i] == 'T' && buf[i+1] == 'r' && buf[i+2] == 'a' && buf[i+3] == 'c' &&
            buf[i+4] == 'e' && buf[i+5] == 'r' && buf[i+6] == 'P' && buf[i+7] == 'i' &&
            buf[i+8] == 'd' && buf[i+9] == ':') {
            int64_t j = i + 10;
            while (j < n && (buf[j] == ' ' || buf[j] == '\t')) j++;
            if (j < n && buf[j] > '0' && buf[j] <= '9') return true;
        }
    }
    return false;
#elif defined(_WIN32) || defined(ASGARD_TARGET_WINDOWS)
#if defined(_M_X64) || defined(__x86_64__)
    // Stealth PEB interrogation on x64: GS:[0x60]
    const uint8_t* peb = (const uint8_t*)__readgsqword(0x60);
    if (peb) {
        // PEB.BeingDebugged at offset +0x02
        if (peb[2] != 0) return true;
        // PEB.NtGlobalFlag at offset +0xBC
        const uint32_t nt_global_flag = *(const uint32_t*)(peb + 0xBC);
        // 0x70 = FLG_HEAP_ENABLE_TAIL_CHECK | FLG_HEAP_ENABLE_FREE_CHECK | FLG_HEAP_VALIDATE_PARAMETERS
        if ((nt_global_flag & 0x70) == 0x70) return true;
    }
#elif defined(_M_IX86) || defined(__i386__)
    // Stealth PEB interrogation on x86: FS:[0x30]
    const uint8_t* peb = (const uint8_t*)__readfsdword(0x30);
    if (peb) {
        if (peb[2] != 0) return true;
        const uint32_t nt_global_flag = *(const uint32_t*)(peb + 0x68);
        if ((nt_global_flag & 0x70) == 0x70) return true;
    }
#endif
    return IsDebuggerPresent() != 0;
#else
    return false;
#endif
}

} // namespace asgard_syscalls


#pragma once
#include <stdint.h>
#include <stdbool.h>
#if defined(__APPLE__)
#include <mach/mach_time.h>
#include <mach-o/dyld.h>
#elif defined(_WIN32)
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#if defined(_MSC_VER)
#include <intrin.h>
#endif
#endif

namespace asgard_anti_emulation {

static inline __attribute__((always_inline)) uint64_t evaluate_emulation_differential() noexcept {
    uint64_t penalty = 0;

#if defined(__x86_64__) || defined(_M_X64)
    // 1. CPUID Hypervisor Discovery & Cycle Ratio Probe
#if defined(_MSC_VER)
    int cpuInfo[4] = { 0 };
    __cpuid(cpuInfo, 1);
    if ((cpuInfo[2] >> 31) & 1) {
        penalty ^= 0x5877CAFEBABE1337ULL; // Hypervisor bit detected
    }
    uint64_t t0 = __rdtsc();
    for (int i = 0; i < 64; ++i) { YieldProcessor(); }
    uint64_t t1 = __rdtsc();
    if ((t1 - t0) > 25000ULL) {
        penalty ^= 0xDEADBEEF5A5A1337ULL; // Emulation slow-path detected
    }
#else
    uint32_t eax = 1, ebx = 0, ecx = 0, edx = 0;
    __asm__ volatile("cpuid" : "+a"(eax), "=b"(ebx), "=c"(ecx), "=d"(edx));
    if ((ecx >> 31) & 1) {
        penalty ^= 0x5877CAFEBABE1337ULL; // Hypervisor bit detected
    }

    // 2. TSC vs Execution Latency Ratio (QEMU/Unicorn JIT emulators have >50x jitter)
    uint64_t t0 = __builtin_ia32_rdtsc();
    for (int i = 0; i < 64; ++i) { __asm__ volatile("nop"); }
    uint64_t t1 = __builtin_ia32_rdtsc();
    if ((t1 - t0) > 25000ULL) {
        penalty ^= 0xDEADBEEF5A5A1337ULL; // Emulation slow-path detected
    }
#endif
#if defined(_WIN32)
    // Secondary differential via QueryPerformanceCounter
    LARGE_INTEGER q0, q1, freq;
    if (QueryPerformanceFrequency(&freq) && QueryPerformanceCounter(&q0)) {
        for (int i = 0; i < 32; ++i) { YieldProcessor(); }
        QueryPerformanceCounter(&q1);
        if (q1.QuadPart == q0.QuadPart && (t1 - t0) > 1000ULL) {
            penalty ^= 0x5877AABBCCDDEEFFULL;
        }
    }
#endif
#elif defined(__aarch64__) || defined(_M_ARM64)
    // ARM64 Virtual Counter Overhead & Multi-Source Jitter Probe
    uint64_t t0, t1;
#if defined(_MSC_VER)
    t0 = (uint64_t)_ReadStatusReg(ARM64_CNTVCT);
    for (int i = 0; i < 64; ++i) { __nop(); }
    t1 = (uint64_t)_ReadStatusReg(ARM64_CNTVCT);
#else
    __asm__ volatile("mrs %0, cntvct_el0" : "=r"(t0));
    for (int i = 0; i < 64; ++i) { __asm__ volatile("nop"); }
    __asm__ volatile("mrs %0, cntvct_el0" : "=r"(t1));
#endif
    if ((t1 - t0) > 30000ULL) {
        penalty ^= 0xFEEDFACE5877CAFEULL;
    }
#if defined(__APPLE__)
    // Multi-source differential verification (detecting timer spoofing / freeze)
    uint64_t m0 = mach_absolute_time();
    for (int i = 0; i < 32; ++i) { __asm__ volatile("nop"); }
    uint64_t m1 = mach_absolute_time();
    if (m1 == m0 && (t1 - t0) > 1000ULL) {
        penalty ^= 0x5877AABBCCDDEEFFULL;
    }
#endif
#endif

#if defined(__APPLE__)
    // In-memory DBI & Dynamic Instrumentation Detection (Frida, Gum, Substrate)
    uint32_t img_count = _dyld_image_count();
    for (uint32_t i = 0; i < img_count; ++i) {
        const char* name = _dyld_get_image_name(i);
        if (name) {
            for (const char* p = name; *p != '\0'; ++p) {
                // "frida"
                if ((p[0] == 'f' || p[0] == 'F') &&
                    (p[1] == 'r' || p[1] == 'R') &&
                    (p[2] == 'i' || p[2] == 'I') &&
                    (p[3] == 'd' || p[3] == 'D') &&
                    (p[4] == 'a' || p[4] == 'A')) {
                    penalty ^= 0xFA15ECAFE1337BEEULL;
                    break;
                }
                // "gum-"
                if ((p[0] == 'g' || p[0] == 'G') &&
                    (p[1] == 'u' || p[1] == 'U') &&
                    (p[2] == 'm' || p[2] == 'M') &&
                    p[3] == '-') {
                    penalty ^= 0xFA15ECAFE1337BEEULL;
                    break;
                }
                // "substrate"
                if ((p[0] == 's' || p[0] == 'S') &&
                    (p[1] == 'u' || p[1] == 'U') &&
                    (p[2] == 'b' || p[2] == 'B') &&
                    (p[3] == 's' || p[3] == 'S') &&
                    (p[4] == 't' || p[4] == 'T') &&
                    (p[5] == 'r' || p[5] == 'R') &&
                    (p[6] == 'a' || p[6] == 'A') &&
                    (p[7] == 't' || p[7] == 'T') &&
                    (p[8] == 'e' || p[8] == 'E')) {
                    penalty ^= 0xFA15ECAFE1337BEEULL;
                    break;
                }
            }
        }
    }
#endif

    return penalty;
}

} // namespace asgard_anti_emulation


#pragma once
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

#if !defined(ASGARD_API_HASH_RESOLVER_DEFINED) && !defined(ASGARD_CRYPTO_PRIMITIVES_DEFINED)
#define ASGARD_API_HASH_RESOLVER_DEFINED 1
#define ASGARD_CRYPTO_PRIMITIVES_DEFINED 1
static inline int asg_strcmp(const char* s1, const char* s2) noexcept {
    if (!s1 || !s2) return (s1 == s2) ? 0 : (s1 ? 1 : -1);
    while (*s1 && (*s1 == *s2)) { s1++; s2++; }
    return *(const unsigned char*)s1 - *(const unsigned char*)s2;
}

#if defined(__APPLE__) && defined(__MACH__)
#include <mach-o/dyld.h>
#include <mach-o/loader.h>

static inline uint64_t asg_read_uleb128(const uint8_t** p) noexcept {
    uint64_t result = 0;
    int shift = 0;
    while (1) {
        uint8_t byte = *(*p)++;
        result |= ((uint64_t)(byte & 0x7f)) << shift;
        if ((byte & 0x80) == 0) break;
        shift += 7;
    }
    return result;
}

static inline void* asg_find_sym_in_trie(const uint8_t* trie_base, const uint8_t* node, uint32_t cur_h, uint32_t target_h, uintptr_t base) noexcept {
    const uint8_t* p = node;
    uint64_t terminal_size = asg_read_uleb128(&p);
    if (terminal_size > 0 && cur_h == target_h) {
        uint64_t flags = asg_read_uleb128(&p);
        if ((flags & 0x08) == 0) {
            uint64_t addr = asg_read_uleb128(&p);
            return (void*)(addr + base);
        }
        return nullptr;
    }
    p += terminal_size;
    uint8_t child_count = *p++;
    for (uint8_t i = 0; i < child_count; i++) {
        uint32_t child_h = cur_h;
        while (*p) {
            child_h = (child_h ^ (uint8_t)*p++) * 0x01000193U;
        }
        p++;
        uint64_t child_offset = asg_read_uleb128(&p);
        void* res = asg_find_sym_in_trie(trie_base, trie_base + child_offset, child_h, target_h, base);
        if (res) return res;
    }
    return nullptr;
}

static inline void* asgard_resolve_by_api_hash(uint32_t target_hash) noexcept {
    if (target_hash == 0) return nullptr;
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const struct mach_header_64* hdr = (const struct mach_header_64*)_dyld_get_image_header(i);
        if (!hdr || hdr->magic != MH_MAGIC_64) continue;
        intptr_t slide = _dyld_get_image_vmaddr_slide(i);
        const struct load_command* cmd = (const struct load_command*)(hdr + 1);
        uintptr_t linkedit_base = 0;
        uint32_t dataoff = 0;
        for (uint32_t c = 0; c < hdr->ncmds; c++) {
            if (cmd->cmd == LC_SEGMENT_64) {
                const struct segment_command_64* seg = (const struct segment_command_64*)cmd;
                if (asg_strcmp(seg->segname, "__LINKEDIT") == 0) {
                    linkedit_base = seg->vmaddr + slide - seg->fileoff;
                }
            } else if (cmd->cmd == 0x80000033 /* LC_DYLD_EXPORTS_TRIE */) {
                const struct linkedit_data_command* lc = (const struct linkedit_data_command*)cmd;
                dataoff = lc->dataoff;
            }
            cmd = (const struct load_command*)((const char*)cmd + cmd->cmdsize);
        }
        if (linkedit_base && dataoff) {
            const uint8_t* trie = (const uint8_t*)(linkedit_base + dataoff);
            void* resolved = asg_find_sym_in_trie(trie, trie, 0x811c9dc5U, target_hash, (uintptr_t)hdr);
            if (resolved) return resolved;
        }
    }
    return nullptr;
}
#else
static inline void* asgard_resolve_by_api_hash(uint32_t) noexcept { return nullptr; }
#endif
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
        typedef kern_return_t (*asg_vm_alloc_fn_t)(vm_map_t, vm_address_t*, vm_size_t, int);
        typedef kern_return_t (*asg_vm_remap_fn_t)(vm_map_t, vm_address_t*, vm_size_t, vm_address_t, int, vm_map_t, vm_address_t, boolean_t, vm_prot_t*, vm_prot_t*, vm_inherit_t);
        typedef kern_return_t (*asg_vm_prot_fn_t)(vm_map_t, vm_address_t, vm_size_t, boolean_t, vm_prot_t);
        typedef kern_return_t (*asg_vm_dealloc_fn_t)(vm_map_t, vm_address_t, vm_size_t);
        static asg_vm_alloc_fn_t p_vm_alloc = nullptr;
        static asg_vm_remap_fn_t p_vm_remap = nullptr;
        static asg_vm_prot_fn_t  p_vm_prot  = nullptr;
        static asg_vm_dealloc_fn_t p_vm_dealloc = nullptr;
        if (!p_vm_alloc) p_vm_alloc = (asg_vm_alloc_fn_t)asgard_resolve_by_api_hash(0xA0E735E5U /* _vm_allocate */);
        if (!p_vm_remap) p_vm_remap = (asg_vm_remap_fn_t)asgard_resolve_by_api_hash(0xF034F085U /* _vm_remap */);
        if (!p_vm_prot)  p_vm_prot  = (asg_vm_prot_fn_t)asgard_resolve_by_api_hash(0x9857D42CU /* _vm_protect */);
        if (!p_vm_dealloc) p_vm_dealloc = (asg_vm_dealloc_fn_t)asgard_resolve_by_api_hash(0xE86CA72AU /* _vm_deallocate */);

        vm_address_t rw_addr = 0;
        if (p_vm_alloc && p_vm_alloc(mach_task_self(), &rw_addr, buf.size, VM_FLAGS_ANYWHERE) == KERN_SUCCESS) {
            vm_address_t rx_addr = 0;
            vm_prot_t cur_prot, max_prot;
            if (p_vm_remap && p_vm_remap(mach_task_self(), &rx_addr, buf.size, 0, VM_FLAGS_ANYWHERE,
                          mach_task_self(), rw_addr, FALSE, &cur_prot, &max_prot, VM_INHERIT_NONE) == KERN_SUCCESS) {
                if (p_vm_prot && p_vm_prot(mach_task_self(), rx_addr, buf.size, FALSE, VM_PROT_READ | VM_PROT_EXECUTE) == KERN_SUCCESS) {
                    buf.rw_alias = (void*)rw_addr;
                    buf.rx_alias = (const void*)rx_addr;
                    return buf;
                }
            }
            if (p_vm_dealloc) p_vm_dealloc(mach_task_self(), rw_addr, buf.size);
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
            typedef kern_return_t (*asg_vm_dealloc_fn_t)(vm_map_t, vm_address_t, vm_size_t);
            static asg_vm_dealloc_fn_t p_vm_dealloc = nullptr;
            if (!p_vm_dealloc) p_vm_dealloc = (asg_vm_dealloc_fn_t)asgard_resolve_by_api_hash(0xE86CA72AU /* _vm_deallocate */);
            if (p_vm_dealloc) {
                if (rw_alias) p_vm_dealloc(mach_task_self(), (vm_address_t)rw_alias, size);
                if (rx_alias) p_vm_dealloc(mach_task_self(), (vm_address_t)rx_alias, size);
            }
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


#pragma once
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
#include <stdio.h>
#if defined(__APPLE__)
#include <libkern/OSCacheControl.h>
#include <pthread.h>
#elif defined(_WIN32)
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#if defined(_MSC_VER)
#include <intrin.h>
#endif
#endif

#if defined(ASGARD_SMC_STRICT)
#  if !defined(__APPLE__) && (!defined(__linux__) || !defined(MFD_CLOEXEC)) && !defined(_WIN32)
#    error "ASGARD Security Violation: Strict SMC requested (max_security profile), but target platform does not support dual-mapping W^X memory aliasing!"
#  endif
#endif

namespace asgard_smc {

enum SmcStatus : uint32_t {
    SMC_STATUS_NOT_EXECUTED = 0,
    SMC_STATUS_ACTIVE       = 1,
    SMC_STATUS_DEGRADED     = 2,
    SMC_STATUS_FAILED       = 3
};

inline volatile uint32_t g_smc_status = SMC_STATUS_NOT_EXECUTED;

static inline __attribute__((always_inline)) uint32_t get_smc_status() noexcept {
    return g_smc_status;
}

static inline __attribute__((always_inline)) const char* get_smc_status_string() noexcept {
    switch (g_smc_status) {
        case SMC_STATUS_ACTIVE:   return "FULL_SMC";
        case SMC_STATUS_DEGRADED: return "DEGRADED_NO_DUAL_MAP";
        case SMC_STATUS_FAILED:   return "FAILED_VERIFICATION";
        default:                  return "NOT_EXECUTED";
    }
}

static inline __attribute__((always_inline)) bool is_smc_active() noexcept {
    return g_smc_status == SMC_STATUS_ACTIVE;
}

static inline __attribute__((always_inline)) bool is_smc_degraded() noexcept {
    return g_smc_status == SMC_STATUS_DEGRADED;
}

// Introspective Self-Modifying Code (SMC) + Hardware Timing Probe (Morse & Kojsik, 2026)
static inline __attribute__((always_inline)) uint64_t execute_introspective_smc_probe(uint64_t seed) noexcept {
    uint64_t penalty = 0;
    asgard_memory::DualMappedBuffer buf = asgard_memory::DualMappedBuffer::allocate(4096);
    if (!buf.rw_alias || !buf.rx_alias) {
#if defined(ASGARD_SMC_STRICT)
        g_smc_status = SMC_STATUS_FAILED;
#if defined(ASGARD_DEBUG_DIAGNOSTICS)
        fprintf(stderr, "[SMC_ERROR] Strict SMC required by max_security profile, but dual-mapping buffer allocation failed!\n");
#endif
        return 0xDEAD53C0CAFE0001ULL; // Non-zero penalty that corrupts VM context and forces abort/divergence
#else
        g_smc_status = SMC_STATUS_DEGRADED;
#if defined(ASGARD_DEBUG_DIAGNOSTICS)
        fprintf(stderr, "[SMC_WARN] Dual-mapping unsupported or failed; SMC degraded gracefully.\n");
#endif
        return 0; // If dual-mapping is unsupported and not in strict mode, degrade gracefully
#endif
    }

#if defined(__aarch64__) || defined(_M_ARM64)
#if defined(__APPLE__)
    pthread_jit_write_protect_np(0);
#endif
    // Emit ARM64:
    // movz w0, #0x5877, lsl #0  -> 0x528b0ee0
    // add w0, w0, #0x12         -> 0x11004800
    // ret                       -> 0xd65f03c0
    uint32_t* code_rw = (uint32_t*)buf.rw_alias;
    code_rw[0] = 0x528b0ee0; // movz w0, #0x5877
    code_rw[1] = 0x11004800; // add w0, w0, #0x12
    code_rw[2] = 0xd65f03c0; // ret

    uint64_t t0;
#if defined(_MSC_VER)
    t0 = (uint64_t)_ReadStatusReg(ARM64_CNTVCT);
#else
    __asm__ volatile("mrs %0, cntvct_el0" : "=r"(t0));
#endif

    // Dynamic Self-Modification via RW alias: mutate immediate in add (bits 10..21)
    uint32_t imm_val = (uint32_t)(seed & 0x7F);
    code_rw[1] = 0x11000000 | (imm_val << 10);

    // Hardware icache invalidation & pipeline clear
#if defined(__APPLE__)
    sys_dcache_flush(buf.rw_alias, 16);
    sys_icache_invalidate((void*)buf.rx_alias, 16);
    pthread_jit_write_protect_np(1);
#elif defined(_WIN32)
    FlushInstructionCache(GetCurrentProcess(), (void*)buf.rx_alias, 16);
#else
    __builtin___clear_cache((char*)buf.rw_alias, (char*)buf.rw_alias + 16);
#endif

    // Execute via RX alias
    typedef uint32_t (*smc_fn_t)();
    smc_fn_t fn = (smc_fn_t)buf.rx_alias;
    uint32_t result = fn();

#if defined(__APPLE__)
    pthread_jit_write_protect_np(0);
#endif

    uint64_t t1;
#if defined(_MSC_VER)
    t1 = (uint64_t)_ReadStatusReg(ARM64_CNTVCT);
#else
    __asm__ volatile("mrs %0, cntvct_el0" : "=r"(t1));
#endif

    uint32_t expected = 0x5877 + imm_val;
    if (result != expected) {
        penalty ^= 0xBAD5A5A558771337ULL;
    }
    if ((t1 - t0) > 100000ULL) {
        penalty ^= 0xDEAD1337CAFE5877ULL; // JIT/hypervisor emulation slow-path
    }
#elif defined(__x86_64__) || defined(_M_X64)
    // Emit x86_64:
    // mov eax, 0x5877  -> B8 77 58 00 00
    // add eax, 0x12    -> 05 12 00 00 00
    // ret              -> C3
    uint8_t* code_rw = (uint8_t*)buf.rw_alias;
    code_rw[0] = 0xB8; code_rw[1] = 0x77; code_rw[2] = 0x58; code_rw[3] = 0x00; code_rw[4] = 0x00;
    code_rw[5] = 0x05; code_rw[6] = 0x12; code_rw[7] = 0x00; code_rw[8] = 0x00; code_rw[9] = 0x00;
    code_rw[10] = 0xC3;

#if defined(_MSC_VER)
    uint64_t t0 = __rdtsc();
#else
    uint64_t t0 = __builtin_ia32_rdtsc();
#endif

    // Dynamic Self-Modification via RW alias
    uint8_t imm_val = (uint8_t)(seed & 0x7F);
    code_rw[6] = imm_val;

    // Hardware icache invalidation & pipeline clear
#if defined(_WIN32)
    FlushInstructionCache(GetCurrentProcess(), (void*)buf.rx_alias, 16);
#else
    __builtin___clear_cache((char*)buf.rw_alias, (char*)buf.rw_alias + 16);
#endif

    // Execute via RX alias
    typedef uint32_t (*smc_fn_t)();
    smc_fn_t fn = (smc_fn_t)buf.rx_alias;
    uint32_t result = fn();

#if defined(_MSC_VER)
    uint64_t t1 = __rdtsc();
#else
    uint64_t t1 = __builtin_ia32_rdtsc();
#endif

    uint32_t expected = 0x5877 + imm_val;
    if (result != expected) {
        penalty ^= 0xBAD5A5A558771337ULL;
    }
    if ((t1 - t0) > 100000ULL) {
        penalty ^= 0xDEAD1337CAFE5877ULL;
    }
#else
#if defined(ASGARD_SMC_STRICT)
    penalty ^= 0xDEAD53C0CAFE0002ULL;
#endif
#endif

    buf.release();
    if (penalty != 0) {
        g_smc_status = SMC_STATUS_FAILED;
    } else {
        g_smc_status = SMC_STATUS_ACTIVE;
    }
    return penalty;
}

} // namespace asgard_smc


#pragma once
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
#if defined(__APPLE__)
#include <mach/mach.h>
#include <mach/thread_act.h>
#include <mach/thread_status.h>
#include <mach/vm_map.h>
#include <mach-o/dyld.h>
#include <mach-o/getsect.h>
#elif defined(__linux__)
#include <stdio.h>
#include <string.h>
#include <link.h>
#elif defined(_WIN32)
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#endif

namespace asgard_mem_integrity {

static inline __attribute__((always_inline)) uint64_t compute_section_integrity_hash() noexcept {
    uint64_t h = 0x5877CAFE1337BEEFULL;

#if defined(__APPLE__)
    const struct mach_header_64* mh = (const struct mach_header_64*)_dyld_get_image_header(0);
    if (mh) {
        unsigned long text_sz = 0;
        uint8_t* text_p = getsectiondata(mh, "__TEXT", "__text", &text_sz);
        if (text_p && text_sz > 0) {
            size_t sample = text_sz < 65536 ? text_sz : 65536;
            for (size_t i = 0; i + 8 <= sample; i += 32) {
                uint64_t w = *reinterpret_cast<const uint64_t*>(text_p + i);
                h ^= w * 0x9E3779B97F4A7C15ULL;
                h = (h << 13) | (h >> 51);
                h *= 0x100000001B3ULL;
            }
        }
        unsigned long const_sz = 0;
        uint8_t* const_p = getsectiondata(mh, "__TEXT", "__const", &const_sz);
        if (const_p && const_sz > 0) {
            size_t sample = const_sz < 16384 ? const_sz : 16384;
            for (size_t i = 0; i + 8 <= sample; i += 32) {
                uint64_t w = *reinterpret_cast<const uint64_t*>(const_p + i);
                h ^= w * 0xBF58476D1CE4E5B9ULL;
                h = (h << 17) | (h >> 47);
            }
        }
    }
#elif defined(__linux__) && !defined(_MSC_VER)
    struct PhdrContext {
        uint64_t hash;
        bool found;
    } pctx = { h, false };

    dl_iterate_phdr([](struct dl_phdr_info* info, size_t, void* data) -> int {
        auto* ctx = reinterpret_cast<PhdrContext*>(data);
        if (ctx->found) return 1;
        for (int i = 0; i < info->dlpi_phnum; ++i) {
            const ElfW(Phdr)& ph = info->dlpi_phdr[i];
            if (ph.p_type == PT_LOAD && (ph.p_flags & PF_X)) {
                const uint8_t* base = reinterpret_cast<const uint8_t*>(info->dlpi_addr + ph.p_vaddr);
                size_t sz = ph.p_filesz < 65536 ? ph.p_filesz : 65536;
                for (size_t j = 0; j + 8 <= sz; j += 32) {
                    uint64_t w = *reinterpret_cast<const uint64_t*>(base + j);
                    ctx->hash ^= w * 0x9E3779B97F4A7C15ULL;
                    ctx->hash = (ctx->hash << 13) | (ctx->hash >> 51);
                    ctx->hash *= 0x100000001B3ULL;
                }
                ctx->found = true;
            }
        }
        return ctx->found ? 1 : 0;
    }, &pctx);
    h = pctx.hash;
#elif defined(_WIN32)
    HMODULE hMod = GetModuleHandleA(nullptr);
    if (hMod) {
        const uint8_t* base = reinterpret_cast<const uint8_t*>(hMod);
        const auto* dos = reinterpret_cast<const IMAGE_DOS_HEADER*>(base);
        if (dos->e_magic == IMAGE_DOS_SIGNATURE) {
            const auto* nt = reinterpret_cast<const IMAGE_NT_HEADERS*>(base + dos->e_lfanew);
            if (nt->Signature == IMAGE_NT_SIGNATURE) {
                const auto* sec = IMAGE_FIRST_SECTION(nt);
                for (WORD i = 0; i < nt->FileHeader.NumberOfSections; ++i, ++sec) {
                    if ((sec->Characteristics & IMAGE_SCN_MEM_EXECUTE) && !(sec->Characteristics & IMAGE_SCN_MEM_WRITE)) {
                        const uint8_t* p = base + sec->VirtualAddress;
                        size_t sz = sec->Misc.VirtualSize < 65536 ? sec->Misc.VirtualSize : 65536;
                        for (size_t j = 0; j + 8 <= sz; j += 32) {
                            uint64_t w = *reinterpret_cast<const uint64_t*>(p + j);
                            h ^= w * 0x9E3779B97F4A7C15ULL;
                            h = (h << 13) | (h >> 51);
                            h *= 0x100000001B3ULL;
                        }
                    }
                }
            }
        }
    }
#endif

    return h ^ (h >> 31);
}

// MEM-SBOM Style Memory Forensics & Injection Scanner
static inline __attribute__((always_inline)) uint64_t evaluate_memory_integrity() noexcept {
    uint64_t penalty = 0;

    // 1. Executable Section Dynamic Drift Check
    static uint64_t initial_sect_hash = 0;
    uint64_t current_sect_hash = compute_section_integrity_hash();
    if (initial_sect_hash == 0) {
        initial_sect_hash = current_sect_hash;
    } else if (current_sect_hash != initial_sect_hash) {
        penalty ^= 0x5877BAADC0DEDEADULL;
    }

#if defined(__APPLE__)
    // 2. Thread Debug Register Inspection (DR0-DR3 / DBGBVR detection)
    mach_port_t thread = mach_thread_self();
#if defined(__aarch64__) && defined(ARM_DEBUG_STATE64)
    arm_debug_state64_t dbg_state = {};
    mach_msg_type_number_t count = ARM_DEBUG_STATE64_COUNT;
    if (thread_get_state(thread, ARM_DEBUG_STATE64, (thread_state_t)&dbg_state, &count) == KERN_SUCCESS) {
        for (int i = 0; i < 16; ++i) {
            if (dbg_state.__bcr[i] & 1) { // Breakpoint control enabled
                penalty ^= 0xCAFEBABE00000001ULL ^ ((uint64_t)i << 32);
            }
        }
    }
#elif defined(__x86_64__) && defined(x86_DEBUG_STATE64)
    x86_debug_state64_t dbg_state = {};
    mach_msg_type_number_t count = x86_DEBUG_STATE64_COUNT;
    if (thread_get_state(thread, x86_DEBUG_STATE64, (thread_state_t)&dbg_state, &count) == KERN_SUCCESS) {
        if (dbg_state.__dr7 & 0x000000FF) { // DR0-DR3 active
            penalty ^= 0xCAFEBABE00000002ULL;
        }
    }
#endif
    mach_port_deallocate(mach_task_self(), thread);

    // 3. Suspicious Anonymous RWX Memory Scanner (Anti-Frida / Shellcode Injection)
    vm_address_t address = 0;
    vm_size_t size = 0;
    mach_port_t object_name = MACH_PORT_NULL;
    struct vm_region_basic_info_64 info = {};
    mach_msg_type_number_t info_cnt = VM_REGION_BASIC_INFO_COUNT_64;
    int suspicious_rwx = 0;
    while (vm_region_64(mach_task_self(), &address, &size, VM_REGION_BASIC_INFO_64, (vm_region_info_t)&info, &info_cnt, &object_name) == KERN_SUCCESS) {
        if ((info.protection & VM_PROT_WRITE) && (info.protection & VM_PROT_EXECUTE)) {
            suspicious_rwx++;
        }
        address += size;
    }
    if (suspicious_rwx > 2) {
        penalty ^= 0x5877F81DA0000001ULL;
    }
#elif defined(__linux__)
    FILE* fp = fopen("/proc/self/maps", "r");
    if (fp) {
        char line[512];
        while (fgets(line, sizeof(line), fp)) {
            if (strstr(line, "rwxp")) { // Anonymous RWX page
                penalty ^= 0x5877F81DA0000002ULL;
                break;
            }
        }
        fclose(fp);
    }
#elif defined(_WIN32)
    // Thread Debug Register Inspection (DR0-DR3 / DR7 detection)
    CONTEXT dbg_ctx = {};
    dbg_ctx.ContextFlags = CONTEXT_DEBUG_REGISTERS;
    if (GetThreadContext(GetCurrentThread(), &dbg_ctx)) {
#if defined(_M_ARM64) || defined(__aarch64__)
        for (size_t b = 0; b < sizeof(dbg_ctx.Bcr)/sizeof(dbg_ctx.Bcr[0]); ++b) {
            if (dbg_ctx.Bcr[b] & 1) {
                penalty ^= 0xCAFEBABE00000002ULL;
                break;
            }
        }
#elif defined(_M_X64) || defined(_M_IX86) || defined(__x86_64__) || defined(__i386__)
        if (dbg_ctx.Dr7 & 0x000000FF) {
            penalty ^= 0xCAFEBABE00000002ULL;
        }
#endif
    }

    // Suspicious Anonymous RWX Memory Scanner (VirtualQuery)
    MEMORY_BASIC_INFORMATION mbi = {};
    const uint8_t* addr = nullptr;
    int suspicious_rwx = 0;
    while (VirtualQuery((LPCVOID)addr, &mbi, sizeof(mbi)) == sizeof(mbi)) {
        if ((mbi.State == MEM_COMMIT) && (mbi.Protect == PAGE_EXECUTE_READWRITE)) {
            suspicious_rwx++;
        }
        addr = (const uint8_t*)mbi.BaseAddress + mbi.RegionSize;
        if (addr == nullptr || mbi.RegionSize == 0) break;
    }
    if (suspicious_rwx > 2) {
        penalty ^= 0x5877F81DA0000003ULL;
    }
#endif

    return penalty;
}

} // namespace asgard_mem_integrity


#pragma once
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
#include <signal.h>
#include <string.h>
#include <atomic>

#if defined(__APPLE__)
#include <mach/mach.h>
#include <mach/thread_act.h>
#include <sys/ucontext.h>
#elif defined(__linux__)
#include <ucontext.h>
#endif

#define ASGARD_NANOMITES_ENABLED 1

namespace asgard_nanomites {

struct NanomiteEntry {
    uint32_t trap_id;
    uint64_t target_true;
    uint64_t target_false;
    uint64_t key;
};

// Cryptographically keyed 64-bit Murmur3 Finalizer Mix
static inline uint64_t murmur3_mix64(uint64_t k) noexcept {
    k ^= k >> 33;
    k *= 0xff51afd7ed558ccdULL;
    k ^= k >> 33;
    k *= 0xc4ceb9fe1a85ec53ULL;
    k ^= k >> 33;
    return k;
}

class NanomiteDispatcher {
public:
    static constexpr size_t TABLE_CAPACITY = 2048;
    NanomiteEntry table[TABLE_CAPACITY];
    volatile uint32_t current_trap_id = 0;
    volatile uint32_t current_condition = 0;
    volatile uint64_t resolved_target = 0;
    volatile uint64_t traps_handled = 0;
    uint32_t seed = 0x5877CAFEU;
    bool installed = false;

    void register_nanomite(uint32_t trap_id, uint64_t t_true, uint64_t t_false, uint64_t key) noexcept {
        size_t idx = (size_t)(trap_id % TABLE_CAPACITY);
        table[idx].trap_id = trap_id;
        table[idx].target_true = t_true ^ key;
        table[idx].target_false = t_false ^ key;
        table[idx].key = key;
    }

    uint64_t resolve_target(uint32_t trap_id, uint32_t cond, uint64_t pc_val) noexcept {
        volatile uint64_t mixed = murmur3_mix64(pc_val ^ (uint64_t)seed);
        (void)mixed;
        size_t idx = (size_t)(trap_id % TABLE_CAPACITY);
        if (table[idx].trap_id == trap_id) {
            uint64_t enc = cond ? table[idx].target_true : table[idx].target_false;
            return enc ^ table[idx].key;
        }
        return 0;
    }
};

/* P0-02a: The SIGTRAP / VEH handler executes synchronously on the trapping
   thread, so all per-trap communication state (current_trap_id, current_condition,
   resolved_target, the keyed nanomite table) is thread-local. This removes the
   inter-thread data race when several threads run virtualized nanomite code
   concurrently without any locking on the hot path. */
static thread_local NanomiteDispatcher g_nanomite_dispatcher;

#if defined(__APPLE__)
static inline void install_nanomite_handlers(uint32_t seed = 0x5877CAFEU) noexcept {
    g_nanomite_dispatcher.seed = seed;
    g_nanomite_dispatcher.installed = true;
}
#elif defined(_WIN32)
static LONG WINAPI nanomite_vectored_handler(PEXCEPTION_POINTERS pExceptionInfo) {
    if (pExceptionInfo && pExceptionInfo->ExceptionRecord) {
        DWORD code = pExceptionInfo->ExceptionRecord->ExceptionCode;
        if (code == EXCEPTION_BREAKPOINT || code == EXCEPTION_ILLEGAL_INSTRUCTION) {
            uint64_t pc_val = 0;
#if defined(_M_X64) || defined(__x86_64__)
            if (pExceptionInfo->ContextRecord) {
                pc_val = (uint64_t)pExceptionInfo->ContextRecord->Rip;
            }
#elif defined(_M_ARM64) || defined(__aarch64__)
            if (pExceptionInfo->ContextRecord) {
                pc_val = (uint64_t)pExceptionInfo->ContextRecord->Pc;
            }
#endif
            g_nanomite_dispatcher.traps_handled = g_nanomite_dispatcher.traps_handled + 1;
            uint32_t tid = g_nanomite_dispatcher.current_trap_id;
            uint32_t cond = g_nanomite_dispatcher.current_condition;
            g_nanomite_dispatcher.resolved_target = g_nanomite_dispatcher.resolve_target(tid, cond, pc_val);
#if defined(_M_X64) || defined(__x86_64__)
            if (code == EXCEPTION_BREAKPOINT && pExceptionInfo->ContextRecord) {
                pExceptionInfo->ContextRecord->Rip += 1;
            }
#elif defined(_M_ARM64) || defined(__aarch64__)
            if (code == EXCEPTION_BREAKPOINT && pExceptionInfo->ContextRecord) {
                pExceptionInfo->ContextRecord->Pc += 4;
            }
#endif
            return EXCEPTION_CONTINUE_EXECUTION;
        }
    }
    return EXCEPTION_CONTINUE_SEARCH;
}

static inline void install_nanomite_handlers(uint32_t seed = 0x5877CAFEU) noexcept {
    g_nanomite_dispatcher.seed = seed;
    /* Process-wide one-shot guard: per-thread dispatchers must not re-register
       the VEH chain on every thread (leaks handlers under heavy threading). */
    static std::atomic<bool> g_veh_installed{false};
    if (!g_veh_installed.exchange(true)) {
        AddVectoredExceptionHandler(1, nanomite_vectored_handler);
    }
    g_nanomite_dispatcher.installed = true;
}
#elif defined(__linux__) && !defined(_MSC_VER)
static void nanomite_trap_handler(int sig, siginfo_t* info, void* ucontext_ptr) {
    (void)sig; (void)info;
    uint64_t pc_val = 0;
#if defined(__APPLE__)
    ucontext_t* uc = (ucontext_t*)ucontext_ptr;
#if defined(__arm64__) || defined(__aarch64__)
    if (uc && uc->uc_mcontext) {
        pc_val = (uint64_t)uc->uc_mcontext->__ss.__pc;
    }
#elif defined(__x86_64__)
    if (uc && uc->uc_mcontext) {
        pc_val = (uint64_t)uc->uc_mcontext->__ss.__rip;
    }
#endif
#elif defined(__linux__)
    ucontext_t* uc = (ucontext_t*)ucontext_ptr;
#if defined(__arm64__) || defined(__aarch64__)
    if (uc) {
        pc_val = (uint64_t)uc->uc_mcontext.pc;
    }
#elif defined(__x86_64__)
    if (uc) {
        pc_val = (uint64_t)uc->uc_mcontext.gregs[REG_RIP];
    }
#endif
#endif

    g_nanomite_dispatcher.traps_handled = g_nanomite_dispatcher.traps_handled + 1;
    uint32_t tid = g_nanomite_dispatcher.current_trap_id;
    uint32_t cond = g_nanomite_dispatcher.current_condition;
    g_nanomite_dispatcher.resolved_target = g_nanomite_dispatcher.resolve_target(tid, cond, pc_val);
}

static inline void install_nanomite_handlers(uint32_t seed = 0x5877CAFEU) noexcept {
    g_nanomite_dispatcher.seed = seed;
    /* Process-wide one-shot guard: sigaction() is process-wide, so per-thread
       dispatchers only need to install the signal handler once. */
    static std::atomic<bool> g_sigaction_installed{false};
    if (!g_sigaction_installed.exchange(true)) {
        struct sigaction sa;
        memset(&sa, 0, sizeof(sa));
        sa.sa_sigaction = nanomite_trap_handler;
        sa.sa_flags = SA_SIGINFO;
        sigemptyset(&sa.sa_mask);
        sigaction(SIGTRAP, &sa, NULL);
        sigaction(SIGILL, &sa, NULL);
    }
    g_nanomite_dispatcher.installed = true;
}
#else
static inline void install_nanomite_handlers(uint32_t seed = 0x5877CAFEU) noexcept {
    g_nanomite_dispatcher.seed = seed;
    g_nanomite_dispatcher.installed = true;
}
#endif

} // namespace asgard_nanomites


// GPU-Synthesized MBA Substitution Matrix (SAC Diffusion: 48.02%)

static constexpr uint64_t GPU_MBA_FWD_MATRIX[16][16] = {
    {
        0x280c76e4f9d1adf1ULL,
        0x3981d599d010de45ULL,
        0x24cfb6dd13c840fdULL,
        0x152521080a1f17a0ULL,
        0x737e969ab51ed595ULL,
        0x1efdcb9a7d1b307cULL,
        0x4d1c30c99b034d28ULL,
        0x1ca356ec66d435d7ULL,
        0x0bc6c975e2f9af5fULL,
        0x6848d7c8f5af082cULL,
        0x77d26b4a7e6facafULL,
        0x3c38deaceceb9c91ULL,
        0x0f1644a08c54703cULL,
        0x2c4c780723750262ULL,
        0x77c2ab889f38c640ULL,
        0x511b547ca8d3e8ffULL
    },
    {
        0x0000000000000000ULL,
        0x3850355fa77f95b1ULL,
        0x65230bedc2149444ULL,
        0x0c9f2356bba73dfdULL,
        0x4da1020f1ee2dbe7ULL,
        0x50b0a7fa1f23fb03ULL,
        0x75ec70b9ae56f7f3ULL,
        0x6091775b38338657ULL,
        0x7c4dbad69537b990ULL,
        0x3b03569142767550ULL,
        0x037a719ef3023cb6ULL,
        0x568a2e47fadad780ULL,
        0x4dfd6a920866f551ULL,
        0x265f1242661a5e3dULL,
        0x77bd1a645dc5d3d1ULL,
        0x631cd9a66b0dfcdaULL
    },
    {
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0ae25142fcd84cc7ULL,
        0x310fec55841fbf81ULL,
        0x7074333d9b0734a2ULL,
        0x332899bdf52f8eafULL,
        0x664a892fd1d264fdULL,
        0x0ff8f8f38b4d79b3ULL,
        0x43f5e17bc8501188ULL,
        0x07ef017f3c726e6dULL,
        0x423721f53c593d37ULL,
        0x22d9d0c11d38c047ULL,
        0x4068dcf105be5c2fULL,
        0x0f597b6b91e09a59ULL,
        0x6c21eb2364f74ab4ULL,
        0x71eee93cce8d2d46ULL
    },
    {
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x3d47209eb57ef64bULL,
        0x43a45d1908369c5aULL,
        0x4079fb7519f60558ULL,
        0x182a58fb629d1149ULL,
        0x00b8d028271d8d1eULL,
        0x6030c5b188a48f9cULL,
        0x68c93631bffd95a6ULL,
        0x7cd0c640ca0b169bULL,
        0x570e0310d313242bULL,
        0x647ba04efb83a27aULL,
        0x3f2d4e90c67f7b13ULL,
        0x79e3cd59acfa247eULL,
        0x50d808464e319f32ULL
    },
    {
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x7682b0ed9667dd11ULL,
        0x1376f630cc9cdc34ULL,
        0x77a4797b1ab6532bULL,
        0x3ae0b50368d7ab6bULL,
        0x08960d2f7d449063ULL,
        0x6ddec687fe26ba72ULL,
        0x4111c1c04f7257d8ULL,
        0x4ee888c35b464282ULL,
        0x707d50040664fc84ULL,
        0x06f4798dddf3b123ULL,
        0x22d7bb6d412ef8a6ULL,
        0x119c9c815466cdd9ULL
    },
    {
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x5c677e9939652e7bULL,
        0x531f400e75377b72ULL,
        0x7bec90b84052f372ULL,
        0x6cc93b7faa3b3600ULL,
        0x614ce2adae275385ULL,
        0x0e782a5d491fcc48ULL,
        0x79c6d0408e5ce447ULL,
        0x10307d9cd638e02fULL,
        0x34905097d6de0f70ULL,
        0x527841836cb3729cULL,
        0x03ed97c683af75afULL
    },
    {
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x566140c7f429ecc9ULL,
        0x0b40d2dcad53ba02ULL,
        0x2a2c634e827e0c83ULL,
        0x0d232206e4a948b8ULL,
        0x746add6855d6375dULL,
        0x5a90f3fa122edcd4ULL,
        0x2fd685b7bdfd87b9ULL,
        0x688af628be3a0888ULL,
        0x06d795461613d55bULL,
        0x2a3491a559dce6ebULL
    },
    {
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x51d9f7082bae8031ULL,
        0x01dee0269236173bULL,
        0x0135171d078723ffULL,
        0x2510e2a68cc3273cULL,
        0x7b67a9f79f951a0bULL,
        0x2b60e375d16e8adaULL,
        0x736ba66d69e8f153ULL,
        0x2aa4a8b9765037ceULL,
        0x52a43e8c9d880e70ULL
    },
    {
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x681576b2e9d6008dULL,
        0x77f23f616d64edf1ULL,
        0x5cc12e4029c6c3bdULL,
        0x13b169df2054bcdcULL,
        0x5527e9bfa39f431eULL,
        0x07aea5dd92d388ecULL,
        0x255944cc0cc3591fULL,
        0x06f8f8bb382c4f07ULL
    },
    {
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x07555549d64a2e59ULL,
        0x16cf78bbe75a9410ULL,
        0x592ba803c9879c42ULL,
        0x2d9e87375bbec135ULL,
        0x430730cfc93ed7b3ULL,
        0x1e27d87d12f5b4e8ULL,
        0x65dfb6c28db85f33ULL
    },
    {
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x6b7ab95d312ac7ffULL,
        0x1b3bcd07c6cdf230ULL,
        0x6c5984f2cf6b9902ULL,
        0x528a4844b85ec6eeULL,
        0x327443cd76c7a3c7ULL,
        0x35acbfb3c37ee889ULL
    },
    {
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x5b5eb94362e1dfe5ULL,
        0x5897218769786a6dULL,
        0x4070e720a8f63595ULL,
        0x13245e7cfac8df3dULL,
        0x4f62f1733f7b6b96ULL
    },
    {
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x67524ed69dfc0785ULL,
        0x2627bb715f81d7feULL,
        0x4e13888a35c41f7aULL,
        0x384ff8492d49a550ULL
    },
    {
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x572b572ee437fdd9ULL,
        0x696473966bd0416bULL,
        0x1885751cec77f9c4ULL
    },
    {
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x588b50bd7512e729ULL,
        0x5951e3a2744f1151ULL
    },
    {
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x038d6ab311e86323ULL
    }
};

static constexpr uint64_t GPU_MBA_INV_MATRIX[16][16] = {
    {
        0xbb8ddb2c3583a311ULL,
        0xfb4446a172eb40dbULL,
        0xc84e4bedb81f20c1ULL,
        0xfaae399e541de610ULL,
        0xdfac5298576877fcULL,
        0x9b13637dccceca7cULL,
        0x0a8eb4722d037baeULL,
        0x6193fe0257a68661ULL,
        0xf7b453ef6e9b07e0ULL,
        0xe6906ac3e2336884ULL,
        0xa6ec80893423588aULL,
        0xaeebdf65186a090dULL,
        0xa4067d0e6f9820c9ULL,
        0x016a7a90b64acf18ULL,
        0xdc836a26dfff3510ULL,
        0xcabacd0f8dba1575ULL
    },
    {
        0x0000000000000000ULL,
        0x06464a7c5abd9351ULL,
        0xee15dd7e0e9b4da4ULL,
        0x405b0b23a3d94b8dULL,
        0xfa87e2333197cc9fULL,
        0x3843faad2f29a577ULL,
        0x8988fd828931e499ULL,
        0x17263c568a9b2942ULL,
        0x043323570d9c2a7eULL,
        0x9df638a7d552ef21ULL,
        0x963a1292423a05f4ULL,
        0x8d4c7755c86a695aULL,
        0xd7c1a6b6c1ab0154ULL,
        0xa514189f23c12e70ULL,
        0x679da50d364f040cULL,
        0x399baf8ffa3011b0ULL
    },
    {
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0xde2f26c95a1eb4f7ULL,
        0xd2989e975d9f41fbULL,
        0x953b07adc7252234ULL,
        0xc02f9068e1549a3dULL,
        0x58f7e2b98d998e0cULL,
        0x11ca27bbe4e47c53ULL,
        0x0f76263df1f1b7ffULL,
        0x4e336f2dcc039a0eULL,
        0x6606b93acca97205ULL,
        0xfd667614df5b676aULL,
        0x1caed55b810b9958ULL,
        0xaa5b106b28da11edULL,
        0xd65d3cab4d86346bULL,
        0x48e46bf8f3fe9abeULL
    },
    {
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x1484d450b21fa363ULL,
        0x612d35d2a0d5b012ULL,
        0x1c0aa552a036c8f0ULL,
        0x6b80a856a068f567ULL,
        0xd5c62b7fa24b22d2ULL,
        0x03aeb2c413e65ac7ULL,
        0x40056333a166e355ULL,
        0x2a2dc88670a5797fULL,
        0x9a025b6a93ea977fULL,
        0x7938838f24a055bfULL,
        0xd74289297d8ad769ULL,
        0xfce059c592fa0343ULL,
        0x1cf05eed69dfc641ULL
    },
    {
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x6f90c3f6f646b3f1ULL,
        0x30f775f2e51add64ULL,
        0xe1d4c3a6b0f0b095ULL,
        0x6d8c79e8c7767903ULL,
        0x40dd67ad5e42f591ULL,
        0x562873ac026dffc4ULL,
        0x4b422e1a62c6049aULL,
        0xbf1263443a111765ULL,
        0x91acff4b50fdba46ULL,
        0x16372ce56f0d4083ULL,
        0x46ff926d45d06b66ULL,
        0x334e24609531c4ddULL
    },
    {
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x1c25df5c271980b3ULL,
        0x65f44edcddd55bfaULL,
        0xb6408e2f5a403136ULL,
        0x15bd828db4757a20ULL,
        0x0e82c32fdf9c93bfULL,
        0xf2c3164d49e17a62ULL,
        0xfa0c8cba78c5c127ULL,
        0x9803675049e07377ULL,
        0x0b096c777795b2f0ULL,
        0xe1fb553baa41936bULL,
        0xa8fac580d1842d0bULL
    },
    {
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x3e2ca18b09b1ed79ULL,
        0xd7b3b74d60cb066eULL,
        0x6f387aea6af45d67ULL,
        0x4f9fa9a707ccf897ULL,
        0x20972e312cd18738ULL,
        0x29120dbc19cc3ca0ULL,
        0x0d5c06d24b6e3466ULL,
        0x318b02f71f23df89ULL,
        0xedd7949efc8ccab9ULL,
        0x65da87c8548181b6ULL
    },
    {
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x06c2721f8860d8d1ULL,
        0xfe515cc6c2c2e369ULL,
        0x473b01afe8966ab8ULL,
        0xbce3fc385e4a5b01ULL,
        0x288f64909d1e13f5ULL,
        0x0907247f38cc7629ULL,
        0x36f61bbd3f6b80b4ULL,
        0xd3e1c48a3cf497a5ULL,
        0x32449a2be390bebfULL
    },
    {
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0xc2fb1b4d4843c245ULL,
        0x949f5f3aa5bb1903ULL,
        0x4b111c500e981021ULL,
        0xd3ef13435b7632e6ULL,
        0x158ea21645b76a1fULL,
        0x7d3c8a183a2b50c5ULL,
        0x98823a9bdaa80ae3ULL,
        0x70ad0238ba19f840ULL
    },
    {
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0xd0971274423a39e9ULL,
        0xf9d74c2a6828d290ULL,
        0xe24f027ad0d5f456ULL,
        0x29ea029edc9f3e81ULL,
        0x8bee2bd60b3b34d1ULL,
        0xacbdcf03a92e028dULL,
        0xa1396e4cad385010ULL
    },
    {
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x9f0bfd5a929537ffULL,
        0xb9a56a2b7627a670ULL,
        0x8272cbb1477f49aaULL,
        0xeecf359f83adce62ULL,
        0x70094c3d2e20f8d5ULL,
        0x361c02a5e44ffbf4ULL
    },
    {
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0xbfecba100eaf45edULL,
        0x0ae399810b2fbdebULL,
        0x0622107945ed1eedULL,
        0xf60b75a9bc592feaULL,
        0xb222bbf6a345423cULL
    },
    {
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x6b2a9d1a392ad94dULL,
        0x13bbd52f15a29d2aULL,
        0xe07620c8c38dddc0ULL,
        0xa906b2e16afbb958ULL
    },
    {
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x8f2c52782dc8b269ULL,
        0x8d6666e68f90f0d5ULL,
        0x38095fc0dac353ddULL
    },
    {
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0xe000538ca81aa519ULL,
        0xeb6d26426601a67dULL
    },
    {
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x66a753bbdf4de48bULL
    }
};


namespace vanguard_threaded_vm {
                                
                                static const asgard_ext_sym_t g_external_symbols[] = {
                                    {
                                        0x00000000U,
                                        0x00000000U,
                                        0,
                                        { 0 }
                                    }
                                };
                                
                                static AsgardConstantEntry g_asgard_constants[] = {
                                    { 0x00000000U, 0x00000000U, nullptr, nullptr, 0x0000000000000000ULL, 0x00000000U, 1 }
                                };
                                
                                static inline void* asgard_resolve_constant(uint32_t hash, uint32_t alt_hash) noexcept {
    for (size_t i = 0; i < sizeof(g_asgard_constants) / sizeof(g_asgard_constants[0]); ++i) {
        AsgardConstantEntry* c = &g_asgard_constants[i];
        if (c->size > 0) {
            if (c->hash == hash ||
                (alt_hash != 0 && c->hash == alt_hash) ||
                (c->alt_hash != 0 && (c->alt_hash == hash || c->alt_hash == alt_hash))) {
                if (__builtin_expect(!c->ready, 0)) {
                    for (size_t j = 0; j < c->size; ++j) {
                        uint8_t k = (uint8_t)(((c->xor_key >> ((j & 3) * 8)) ^ (j * 0x5D + 0x33)) & 0xFF);
                        c->dec_data[j] = (uint8_t)(c->enc_data[j] ^ k);
                    }
                    c->dec_data[c->size] = 0;
                    c->ready = 1;
                }
                return (void*)c->dec_data;
            }
        }
    }
    return nullptr;
}

static inline void* asgard_resolve_constant_name(const char* name) noexcept {
    if (!name || name[0] == '\0') return nullptr;
    uint32_t h = 0x811C9DC5U;
    const char* p = name;
    while (*p) {
        h = (h ^ (uint8_t)*p++) * 0x01000193U;
    }
    uint32_t ah = 0;
    if (name[0] == '_') {
        ah = 0x811C9DC5U;
        p = name + 1;
        while (*p) {
            ah = (ah ^ (uint8_t)*p++) * 0x01000193U;
        }
    }
    return asgard_resolve_constant(h, ah);
}

static inline void* asgard_resolve_sym_idx(int32_t sym_idx) noexcept {
    if (sym_idx < 0 || (size_t)sym_idx >= sizeof(g_external_symbols) / sizeof(g_external_symbols[0])) {
        return nullptr;
    }
    const asgard_ext_sym_t* sym = &g_external_symbols[sym_idx];
    if (sym->len == 0) return nullptr;

    void* sym_ptr = asgard_resolve_constant(sym->hash, sym->alt_hash);
    if (sym_ptr) return sym_ptr;

#if defined(__APPLE__) && defined(__MACH__)
    sym_ptr = asgard_resolve_by_api_hash(sym->hash);
    if (!sym_ptr && sym->alt_hash != 0) {
        sym_ptr = asgard_resolve_by_api_hash(sym->alt_hash);
    }
    if (sym_ptr) return sym_ptr;
#endif

    char dec_name[64];
    asg_decrypt_sym(sym, dec_name, sizeof(dec_name));
    if (!sym_ptr) sym_ptr = asgard_resolve_constant_name(dec_name);

#if defined(__APPLE__) && defined(__MACH__)
    if (!sym_ptr) {
        typedef void* (*dlsym_fn_t)(void*, const char*);
        dlsym_fn_t dyn_dlsym = (dlsym_fn_t)asgard_resolve_by_api_hash(0xE628BBCDU /* FNV1a("_dlsym") */);
        if (dyn_dlsym) {
            sym_ptr = dyn_dlsym((void*)-2, dec_name);
            if (!sym_ptr && dec_name[0] == '_') sym_ptr = dyn_dlsym((void*)-2, dec_name + 1);
            if (!sym_ptr) {
                char alt[66];
                alt[0] = '_';
                memcpy(alt + 1, dec_name, sym->len + 1);
                sym_ptr = dyn_dlsym((void*)-2, alt);
            }
        }
    }
#elif defined(_WIN32) || defined(_WIN64)
    if (!sym_ptr) {
        HMODULE hMain = GetModuleHandleA(NULL);
        sym_ptr = (void*)GetProcAddress(hMain, dec_name);
        if (!sym_ptr && dec_name[0] == '_') sym_ptr = (void*)GetProcAddress(hMain, dec_name + 1);
        if (!sym_ptr) {
            char alt[66];
            alt[0] = '_';
            memcpy(alt + 1, dec_name, sym->len + 1);
            sym_ptr = (void*)GetProcAddress(hMain, alt);
        }
    }
#else
    if (!sym_ptr) {
        sym_ptr = dlsym(RTLD_DEFAULT, dec_name);
        if (!sym_ptr && dec_name[0] == '_') sym_ptr = dlsym(RTLD_DEFAULT, dec_name + 1);
        if (!sym_ptr) {
            char alt[66];
            alt[0] = '_';
            memcpy(alt + 1, dec_name, sym->len + 1);
            sym_ptr = dlsym(RTLD_DEFAULT, alt);
        }
    }
#endif

    volatile char* p = dec_name;
    while (*p) *p++ = 0;

    return sym_ptr;
}
                                
                                namespace asgard_whitebox {
                                                           
                                                           static const uint32_t T0_0[256] = {
                                                               0xc954512fU,
                                                               0x30563c0eU,
                                                               0x47f6b003U,
                                                               0x3da7d0e5U,
                                                               0x3326d56fU,
                                                               0x360b8769U,
                                                               0x6ae2fe9bU,
                                                               0xd4641f2dU,
                                                               0x2ba21b2aU,
                                                               0x1ccb1848U,
                                                               0xb6c7ad7eU,
                                                               0x5bc40902U,
                                                               0x07085602U,
                                                               0x4b50b88dU,
                                                               0xd5cc82d2U,
                                                               0xa7701b69U,
                                                               0x656ab294U,
                                                               0xe4891984U,
                                                               0xe91de76fU,
                                                               0x9d55e5f8U,
                                                               0xcf258c03U,
                                                               0xdefc09b7U,
                                                               0x42cdf298U,
                                                               0x07d131cdU,
                                                               0xbd22b773U,
                                                               0xce204a23U,
                                                               0xb3ccb807U,
                                                               0x93791f5dU,
                                                               0xc7e911bcU,
                                                               0x851f4c64U,
                                                               0x839c7085U,
                                                               0x781ca7b1U,
                                                               0x4559d2b7U,
                                                               0xd33ca861U,
                                                               0x8a3e41ecU,
                                                               0xb1ed5d87U,
                                                               0x51fbb50cU,
                                                               0x8205be6bU,
                                                               0x5f46ef6dU,
                                                               0x73f2151dU,
                                                               0x4dc4c1d6U,
                                                               0x6540c8e2U,
                                                               0x059edb31U,
                                                               0x64d9d770U,
                                                               0xa39f4d16U,
                                                               0x4dab1e9eU,
                                                               0xb384e19aU,
                                                               0xbc4ebc20U,
                                                               0x8f26f16eU,
                                                               0xd5f29a3dU,
                                                               0xeb225257U,
                                                               0x20d9e201U,
                                                               0x390ff4e8U,
                                                               0xdf3c6e61U,
                                                               0x257029e7U,
                                                               0x69cf941eU,
                                                               0xe559df42U,
                                                               0x247349b7U,
                                                               0x5c320ebaU,
                                                               0x13d657a2U,
                                                               0x498fb006U,
                                                               0xe862e018U,
                                                               0x0db61c43U,
                                                               0x0cf9d77aU,
                                                               0xabba757cU,
                                                               0x84690f19U,
                                                               0x6cf270d0U,
                                                               0x4e47f0a2U,
                                                               0xbad3deabU,
                                                               0x85794d6bU,
                                                               0x390150edU,
                                                               0xd871dd39U,
                                                               0x95b902b2U,
                                                               0x59bc0bbaU,
                                                               0x45240e1cU,
                                                               0x0c9803b8U,
                                                               0xf0537c94U,
                                                               0x70610898U,
                                                               0x3d75692aU,
                                                               0x20804423U,
                                                               0xea365a7fU,
                                                               0x44ec8756U,
                                                               0xac90780aU,
                                                               0x72f9d683U,
                                                               0xe788d723U,
                                                               0xb76490bfU,
                                                               0x50769745U,
                                                               0xb2eb34feU,
                                                               0xb5620bc3U,
                                                               0xb7e6f97bU,
                                                               0x377f2675U,
                                                               0xf89c6864U,
                                                               0xffa4cb1dU,
                                                               0xdad3f884U,
                                                               0xef2fb74eU,
                                                               0x41ddad3aU,
                                                               0x9ef2e235U,
                                                               0x56335410U,
                                                               0x58ba5ffbU,
                                                               0xbf5ef018U,
                                                               0x2aacaa27U,
                                                               0x44010b1eU,
                                                               0x428adb82U,
                                                               0xe4bfe750U,
                                                               0x945963dfU,
                                                               0x7242ee3bU,
                                                               0xa9588f2bU,
                                                               0x94c78f28U,
                                                               0xd40e3950U,
                                                               0xa4e8c102U,
                                                               0x9d995e0aU,
                                                               0x4a9d37bfU,
                                                               0x5a7d2fb5U,
                                                               0xe0d61c5fU,
                                                               0xa8bc9eabU,
                                                               0xfc5eb459U,
                                                               0xafe95dfaU,
                                                               0xe434daebU,
                                                               0x2ed9b063U,
                                                               0xf6f68654U,
                                                               0xdaa0f68bU,
                                                               0x9ee6cfe1U,
                                                               0x71e96c78U,
                                                               0x24c96abbU,
                                                               0x7ed90836U,
                                                               0xcdb5b882U,
                                                               0x93d41b6bU,
                                                               0x40f8ce87U,
                                                               0xb3cd9906U,
                                                               0x05ef11f2U,
                                                               0x5dbc8ebeU,
                                                               0x6af6abc3U,
                                                               0x52b9940cU,
                                                               0x18682492U,
                                                               0xbd64743dU,
                                                               0x8758624dU,
                                                               0x2d9a5bf0U,
                                                               0x7d6df57dU,
                                                               0x63cd8c6eU,
                                                               0xe40a05b6U,
                                                               0xef207adfU,
                                                               0x998b23d7U,
                                                               0x2d433e94U,
                                                               0xa72bd27dU,
                                                               0x056902a4U,
                                                               0x8fd893e8U,
                                                               0xb401f5c1U,
                                                               0xca8fa0a6U,
                                                               0x55731cc3U,
                                                               0x390a4f3bU,
                                                               0x4a41b1b6U,
                                                               0x2413a7deU,
                                                               0xeb2ff0acU,
                                                               0xa546a387U,
                                                               0x1544bc0fU,
                                                               0x1c3dc7ddU,
                                                               0xda203942U,
                                                               0xa00e377aU,
                                                               0x9a3d23b0U,
                                                               0x19051923U,
                                                               0xe187ee07U,
                                                               0x037146faU,
                                                               0x06ddb835U,
                                                               0x7ce0e341U,
                                                               0xf8d512acU,
                                                               0x00041079U,
                                                               0xfd839e81U,
                                                               0x24dc880fU,
                                                               0x7f893aafU,
                                                               0x578e33dcU,
                                                               0x07f573c1U,
                                                               0x2e69c767U,
                                                               0x16526207U,
                                                               0x4830d556U,
                                                               0xba3d6371U,
                                                               0xe55e0b7eU,
                                                               0xc5dd337aU,
                                                               0xc9804455U,
                                                               0x8549eee9U,
                                                               0x38d9d06dU,
                                                               0xeb30c5ecU,
                                                               0xf3399bf1U,
                                                               0x6bf77b3aU,
                                                               0x9629554bU,
                                                               0xb857c11cU,
                                                               0x5428dd5cU,
                                                               0xe867d160U,
                                                               0x1f60fb39U,
                                                               0x23372518U,
                                                               0xfd277fc8U,
                                                               0xda6dcec2U,
                                                               0xe16775a3U,
                                                               0x5694423cU,
                                                               0xf85e44d8U,
                                                               0x672f281dU,
                                                               0xe68b1766U,
                                                               0xbbe36244U,
                                                               0x00cfdd47U,
                                                               0xfeb8e913U,
                                                               0x5d7c3225U,
                                                               0xa16ecdfeU,
                                                               0xffdf1382U,
                                                               0x7852d222U,
                                                               0x92ae2596U,
                                                               0x134e07f8U,
                                                               0x496f8d3eU,
                                                               0x8687c5f0U,
                                                               0x179bc7bfU,
                                                               0xc320f1beU,
                                                               0xccc9b0a4U,
                                                               0xc1b6b817U,
                                                               0xd8ae51b0U,
                                                               0xacb96b63U,
                                                               0xc03affb6U,
                                                               0x470c0f18U,
                                                               0x5796e040U,
                                                               0x9bea2ff0U,
                                                               0xc102b825U,
                                                               0x337dab63U,
                                                               0x464d7331U,
                                                               0x6dd283a1U,
                                                               0x3173d895U,
                                                               0x1b697864U,
                                                               0x2c66b27bU,
                                                               0x6c363553U,
                                                               0x768d3c3fU,
                                                               0x4e4bba53U,
                                                               0xab478b7fU,
                                                               0xb2072233U,
                                                               0xed0b1307U,
                                                               0x450d04b8U,
                                                               0x6060333aU,
                                                               0x83eb1d6aU,
                                                               0x50b06b72U,
                                                               0xf58f08dfU,
                                                               0xfe40dbdcU,
                                                               0x1ac0bbe2U,
                                                               0x49fc2741U,
                                                               0xd40d8f64U,
                                                               0x11363be1U,
                                                               0xb56e04dfU,
                                                               0x351b1e2bU,
                                                               0x08777f28U,
                                                               0x9fb3a216U,
                                                               0x9eabd19eU,
                                                               0xcbb8e2c0U,
                                                               0xd5d19241U,
                                                               0x364beb95U,
                                                               0xd3d378ddU,
                                                               0x8bf812f9U,
                                                               0xdc161a30U,
                                                               0x874a78e0U,
                                                               0x735274ccU,
                                                               0x5f0d5214U,
                                                               0xac51e0f2U,
                                                               0x79141511U
                                                           };
                                                           
                                                           static const uint32_t T0_1[256] = {
                                                               0x35057b2bU,
                                                               0x46fb41a7U,
                                                               0x153fb766U,
                                                               0x23a93295U,
                                                               0x10f4fad4U,
                                                               0x82d8ae2aU,
                                                               0xd22052c8U,
                                                               0x4e563438U,
                                                               0xbb5f8fffU,
                                                               0xa766df2fU,
                                                               0x058825b9U,
                                                               0x0b0771adU,
                                                               0x94f2a660U,
                                                               0xcba3359bU,
                                                               0xed7f343bU,
                                                               0xc3aae91dU,
                                                               0x8733b974U,
                                                               0xfc43ba99U,
                                                               0x3267a6e3U,
                                                               0xed694e09U,
                                                               0xfdb84cbaU,
                                                               0x8193871cU,
                                                               0x490ef550U,
                                                               0x921ab216U,
                                                               0xf6c8bb23U,
                                                               0xd5a59d64U,
                                                               0x520ce8e5U,
                                                               0xbd51669cU,
                                                               0x4c87ee06U,
                                                               0x93e2f336U,
                                                               0x73b7015fU,
                                                               0x712cdaecU,
                                                               0xc1b99538U,
                                                               0x9e9b3509U,
                                                               0xa43ee522U,
                                                               0x6a7c01dcU,
                                                               0x6dc9d58aU,
                                                               0x060aa30dU,
                                                               0x61396183U,
                                                               0x0b7378feU,
                                                               0x5071f5c6U,
                                                               0x869430b3U,
                                                               0x7c160df4U,
                                                               0xa01ec557U,
                                                               0xecf853bfU,
                                                               0xd79c4865U,
                                                               0xd8abef89U,
                                                               0x25800850U,
                                                               0x781fec15U,
                                                               0x030713adU,
                                                               0x5e304e8bU,
                                                               0xd149c92aU,
                                                               0x65535e08U,
                                                               0x04bcc94cU,
                                                               0xdcdbbe0fU,
                                                               0x88516428U,
                                                               0xb4ee541fU,
                                                               0x7134bcb0U,
                                                               0xe0904021U,
                                                               0xf6fd10eeU,
                                                               0x428677a0U,
                                                               0x6d024b81U,
                                                               0x2eb93144U,
                                                               0x9cb73333U,
                                                               0x5d89eb1bU,
                                                               0xa946bc50U,
                                                               0xabd24d98U,
                                                               0xe9e18292U,
                                                               0x1d26ee24U,
                                                               0x5329cc23U,
                                                               0xf483ef14U,
                                                               0x5a0f3d77U,
                                                               0x5e16978aU,
                                                               0xe47ebda8U,
                                                               0x7f8f37adU,
                                                               0xd73e2599U,
                                                               0x349a8ffcU,
                                                               0xf91a9534U,
                                                               0xb1c70ac4U,
                                                               0x4ac05ab7U,
                                                               0x892f1df8U,
                                                               0x54fcba7cU,
                                                               0xa093df3eU,
                                                               0xd0db1310U,
                                                               0x735f1041U,
                                                               0x59c50974U,
                                                               0xbd9acd51U,
                                                               0xa778d7c0U,
                                                               0x59e65fe5U,
                                                               0xac90d52cU,
                                                               0x3156f416U,
                                                               0x6b738616U,
                                                               0xf9b91842U,
                                                               0x73cccca4U,
                                                               0x7aaf74ffU,
                                                               0xd3e4c190U,
                                                               0x17ac4364U,
                                                               0x989bd9e6U,
                                                               0xc9e8938dU,
                                                               0xb6941d21U,
                                                               0x2f3383caU,
                                                               0x80941fc7U,
                                                               0xc825b6c9U,
                                                               0x33538246U,
                                                               0xd35d8f5bU,
                                                               0x60d95c3aU,
                                                               0x29ea0bdeU,
                                                               0xbad08351U,
                                                               0x75ce7a3bU,
                                                               0xdc775e4eU,
                                                               0x0cc551dbU,
                                                               0x4a4719a7U,
                                                               0xa74e45f6U,
                                                               0x3d7c5d3cU,
                                                               0x3c53fce9U,
                                                               0x4ec68f69U,
                                                               0x12520882U,
                                                               0xbacadc5fU,
                                                               0xd4c6c067U,
                                                               0xa2a5f34aU,
                                                               0x99679fe7U,
                                                               0x7330beccU,
                                                               0x26b23524U,
                                                               0x8f88bcf4U,
                                                               0x410035e7U,
                                                               0xec6516c4U,
                                                               0xe94fb79cU,
                                                               0x1bacf981U,
                                                               0x22fba729U,
                                                               0xdd5963b3U,
                                                               0x5f2704fbU,
                                                               0x8f236a09U,
                                                               0x1daf19b8U,
                                                               0x6088dfc5U,
                                                               0x051a024cU,
                                                               0x4e88065eU,
                                                               0xb3668efaU,
                                                               0x33955634U,
                                                               0x0f79282bU,
                                                               0x62419348U,
                                                               0x1b14a96eU,
                                                               0x767e3a66U,
                                                               0x5855f16bU,
                                                               0x387f22c5U,
                                                               0xce9c5247U,
                                                               0xc54fae32U,
                                                               0x91b457fdU,
                                                               0xe7ce2c94U,
                                                               0x7cdef936U,
                                                               0x21790474U,
                                                               0xd22a6abdU,
                                                               0x97006439U,
                                                               0x1572f94cU,
                                                               0x446edbd9U,
                                                               0x29153877U,
                                                               0x7806a2d1U,
                                                               0xeb949728U,
                                                               0x92313cc0U,
                                                               0x5c014eeeU,
                                                               0x1721703dU,
                                                               0x13846c1dU,
                                                               0xd40de92dU,
                                                               0xaf698bbaU,
                                                               0x1f01eba6U,
                                                               0xa07e0bf6U,
                                                               0x24fcacecU,
                                                               0x8a9c2e15U,
                                                               0xe8f80b88U,
                                                               0x8a922297U,
                                                               0xc05d38f3U,
                                                               0x8a58210bU,
                                                               0xb47df2abU,
                                                               0x9c5ddd20U,
                                                               0xbcb5b066U,
                                                               0xf9b4b711U,
                                                               0x7f47a7dbU,
                                                               0xd6e2bbf9U,
                                                               0xc1866c5dU,
                                                               0xf8fe733eU,
                                                               0xedb44accU,
                                                               0x371430f8U,
                                                               0x514ee93aU,
                                                               0x222cb7d4U,
                                                               0x96bcd178U,
                                                               0xbb8052f3U,
                                                               0x5c594e32U,
                                                               0x45e8d107U,
                                                               0x2223d9f4U,
                                                               0x25b3c9d8U,
                                                               0xe1441eacU,
                                                               0x08d61eb4U,
                                                               0x286e8455U,
                                                               0x93cd03abU,
                                                               0xc43ce40eU,
                                                               0x74dab9fbU,
                                                               0x3c5d8da6U,
                                                               0x85299220U,
                                                               0xe39bea05U,
                                                               0x54056013U,
                                                               0xbc2622d1U,
                                                               0x47befcfdU,
                                                               0xfcbd0fb9U,
                                                               0xd15c2103U,
                                                               0x0d72e4abU,
                                                               0x14883a1fU,
                                                               0x544a6934U,
                                                               0x1b4e7f87U,
                                                               0x1db75318U,
                                                               0xd49bb2beU,
                                                               0x53b0e512U,
                                                               0xd135b7a6U,
                                                               0x9a960d78U,
                                                               0x89874712U,
                                                               0x0824e0eaU,
                                                               0xb13551c7U,
                                                               0xf17c6636U,
                                                               0x01694267U,
                                                               0xa3cd2c29U,
                                                               0x262175a2U,
                                                               0x9875f696U,
                                                               0x431e8ab5U,
                                                               0x7c52b846U,
                                                               0x84cfa402U,
                                                               0x78a0617fU,
                                                               0x07db57ffU,
                                                               0x426fdb64U,
                                                               0xe788cf62U,
                                                               0x41da5047U,
                                                               0x2958df71U,
                                                               0x8824c683U,
                                                               0xe8dcc888U,
                                                               0x3fa2bbf5U,
                                                               0x633a02a8U,
                                                               0xbdba00a2U,
                                                               0x6fbeaf79U,
                                                               0x01b656d9U,
                                                               0x39b2afceU,
                                                               0xf3d14110U,
                                                               0x398ac9d1U,
                                                               0xcfc3175bU,
                                                               0xbc423a52U,
                                                               0x2a3d5538U,
                                                               0x60cd1146U,
                                                               0xde8f12bfU,
                                                               0xc46001a6U,
                                                               0x729ef846U,
                                                               0xc438bd7cU,
                                                               0xa88160e6U,
                                                               0x4cf95699U,
                                                               0xa0da7b4eU,
                                                               0xa46a3afbU,
                                                               0xdc3945bdU,
                                                               0x34ef4402U,
                                                               0x32174d90U,
                                                               0xa3c75d31U,
                                                               0x4785ec9fU
                                                           };
                                                           
                                                           static const uint32_t T0_2[256] = {
                                                               0x37c742cbU,
                                                               0x56df769aU,
                                                               0xe4a7e172U,
                                                               0xd569318aU,
                                                               0xf7c2f953U,
                                                               0x90c1e103U,
                                                               0xd1afb8f8U,
                                                               0xd176cd28U,
                                                               0xbfb41465U,
                                                               0x440322f6U,
                                                               0xf1d775feU,
                                                               0x3811652dU,
                                                               0x1be2e81aU,
                                                               0x3a447852U,
                                                               0xe5a89cdcU,
                                                               0x65161ab8U,
                                                               0x2814d4b3U,
                                                               0x201b5375U,
                                                               0xd282842cU,
                                                               0xa4f825ccU,
                                                               0x0d223ec8U,
                                                               0xbdef9f0eU,
                                                               0x459f2e6aU,
                                                               0x5883e086U,
                                                               0x9b84c322U,
                                                               0x437d8f0bU,
                                                               0xc4224745U,
                                                               0x81454abdU,
                                                               0xa710bd1fU,
                                                               0x3c5a2b41U,
                                                               0x7d1cc8e1U,
                                                               0x7e3453e0U,
                                                               0xdc3af806U,
                                                               0x1c653aeeU,
                                                               0xcf1ded50U,
                                                               0xb6ee82dcU,
                                                               0xdd1e67dfU,
                                                               0x90c0cf34U,
                                                               0x229af916U,
                                                               0x5e18be18U,
                                                               0x89042dd0U,
                                                               0x33af6f03U,
                                                               0xb38413c0U,
                                                               0x99625f7bU,
                                                               0x6f364d12U,
                                                               0x54d74a21U,
                                                               0x1abe85f5U,
                                                               0x5cb3dc0dU,
                                                               0x0f4654a1U,
                                                               0x1f57b880U,
                                                               0xfc841ec2U,
                                                               0x33de9eeeU,
                                                               0x344805cfU,
                                                               0x5e2a0609U,
                                                               0x871081b6U,
                                                               0x3b0e7135U,
                                                               0x49352f5fU,
                                                               0x3b5d6f61U,
                                                               0xfabeb2beU,
                                                               0xf63253d7U,
                                                               0x55d01296U,
                                                               0x7569e530U,
                                                               0x6f26b2c7U,
                                                               0xcde73b52U,
                                                               0x8dc299dbU,
                                                               0x504ce167U,
                                                               0xd16cfc2dU,
                                                               0x7bf5fccaU,
                                                               0x36cfe5d9U,
                                                               0xec32c3a9U,
                                                               0x62cb48cfU,
                                                               0x95b7b4cdU,
                                                               0xf31c7638U,
                                                               0x8e869171U,
                                                               0xea38baa6U,
                                                               0x1a416d19U,
                                                               0x7ac03673U,
                                                               0xc687ba59U,
                                                               0x84df308fU,
                                                               0xd78ee88cU,
                                                               0x28bbc55cU,
                                                               0x58593edcU,
                                                               0x2792c667U,
                                                               0x5f5cc895U,
                                                               0xda19d2acU,
                                                               0x804a75b6U,
                                                               0xdcd70198U,
                                                               0x5efa4bdbU,
                                                               0x0cf3dc9cU,
                                                               0x8c77980dU,
                                                               0xd3446f81U,
                                                               0x028660adU,
                                                               0xba1f6d11U,
                                                               0xb7206da7U,
                                                               0xe8b683e7U,
                                                               0xf0d09056U,
                                                               0xdcdfbd81U,
                                                               0x92afeeb6U,
                                                               0x8a105002U,
                                                               0xe9a450f8U,
                                                               0xeb11d74cU,
                                                               0x74ecd909U,
                                                               0xbf425275U,
                                                               0x25500a02U,
                                                               0xddb07d14U,
                                                               0x9d68dda7U,
                                                               0x4e879f60U,
                                                               0xe9ceda24U,
                                                               0xa7366154U,
                                                               0x054724d0U,
                                                               0xc299e941U,
                                                               0xafba4d65U,
                                                               0xb77bd6f5U,
                                                               0xd7f16299U,
                                                               0xd08ca269U,
                                                               0x174e2f23U,
                                                               0xb1af638aU,
                                                               0xec963263U,
                                                               0x7093df4aU,
                                                               0xcaa7a140U,
                                                               0x6da2984fU,
                                                               0x887431d0U,
                                                               0xfa3451ceU,
                                                               0x47c4fb89U,
                                                               0xb2836f7cU,
                                                               0xcf9a4647U,
                                                               0x8f1577ebU,
                                                               0xd169c019U,
                                                               0x67e5a103U,
                                                               0x50bd0ce3U,
                                                               0x8a9df8d1U,
                                                               0x80ed596eU,
                                                               0x5933af25U,
                                                               0x70b75dccU,
                                                               0xe72cb6c6U,
                                                               0x3d9c44ccU,
                                                               0x647932f3U,
                                                               0xacb26e43U,
                                                               0x50c0174eU,
                                                               0x854cbb88U,
                                                               0xe53f4d63U,
                                                               0x713cf28eU,
                                                               0xd9f55f5dU,
                                                               0xcac3cdc6U,
                                                               0xb0d615a2U,
                                                               0x053efeb0U,
                                                               0x3c073189U,
                                                               0x5e7c3590U,
                                                               0x9f05ead1U,
                                                               0xa1e36d78U,
                                                               0xc85c5000U,
                                                               0xf2f0e590U,
                                                               0xf494083dU,
                                                               0xe6f531a8U,
                                                               0xbfb462ddU,
                                                               0x45139bebU,
                                                               0xd1904d55U,
                                                               0x919c2131U,
                                                               0x7e56a218U,
                                                               0xdc4a32aeU,
                                                               0xae1cb8f7U,
                                                               0x015e2796U,
                                                               0x357a4715U,
                                                               0x31294217U,
                                                               0xe7f9973fU,
                                                               0x6cd374fcU,
                                                               0xe0f8abbdU,
                                                               0xcb0d68a5U,
                                                               0xdeae04bdU,
                                                               0xce8a33faU,
                                                               0xe9fae5deU,
                                                               0xdbc88ce0U,
                                                               0x4214d550U,
                                                               0x52610158U,
                                                               0xecbc53ddU,
                                                               0xd8af76b9U,
                                                               0x8e73b3efU,
                                                               0x1df1ae32U,
                                                               0x65961fb6U,
                                                               0x87709cadU,
                                                               0xe0e78b52U,
                                                               0x0f50da41U,
                                                               0xd969d9bbU,
                                                               0x52367404U,
                                                               0x84c010d7U,
                                                               0x2a854418U,
                                                               0x5e5f8d46U,
                                                               0xec886299U,
                                                               0xb33971d4U,
                                                               0xdc2b5120U,
                                                               0x89502fc1U,
                                                               0x818a7593U,
                                                               0x03b9806bU,
                                                               0xcb661d84U,
                                                               0x19c5a1b2U,
                                                               0x6be45812U,
                                                               0xdb59b13cU,
                                                               0x2237cf34U,
                                                               0xe185f4c5U,
                                                               0xe89e6e48U,
                                                               0x908c7b42U,
                                                               0xcdb4a7d3U,
                                                               0x2bf4ada5U,
                                                               0x0665bbc8U,
                                                               0x3bd12530U,
                                                               0x0363142eU,
                                                               0x0bdd4892U,
                                                               0xb34224a5U,
                                                               0x0777f837U,
                                                               0x38f7e2c7U,
                                                               0x479f85b6U,
                                                               0x760f4010U,
                                                               0xb13af499U,
                                                               0x3ec4edd6U,
                                                               0xca7a78deU,
                                                               0xf3cef715U,
                                                               0x00439cf8U,
                                                               0xdd97ca6fU,
                                                               0x5889ad94U,
                                                               0x881d2076U,
                                                               0x733c7d71U,
                                                               0xe67e4e4fU,
                                                               0x75e68af7U,
                                                               0x35a4d3e7U,
                                                               0x05cfebe3U,
                                                               0x38745beaU,
                                                               0x16cfab9fU,
                                                               0x21d21562U,
                                                               0x8220a11dU,
                                                               0x75b1304dU,
                                                               0x203552f9U,
                                                               0xb5e518c9U,
                                                               0x4ac007e7U,
                                                               0x4289c369U,
                                                               0xcb97486dU,
                                                               0xa694d706U,
                                                               0x805a4931U,
                                                               0x017651ceU,
                                                               0x08be14d6U,
                                                               0xe82399faU,
                                                               0x12806f1eU,
                                                               0x7bd32e5aU,
                                                               0xea303fc8U,
                                                               0x7e16e27aU,
                                                               0xa5babefbU,
                                                               0xab1bfc6eU,
                                                               0x984def37U,
                                                               0x8840b1bcU,
                                                               0x8776a7c2U,
                                                               0xf0cccfa5U,
                                                               0x0a1858b5U,
                                                               0x3b65599dU,
                                                               0x59fe4e51U,
                                                               0xb769aed3U,
                                                               0xc4f5daaaU,
                                                               0xf07e62a2U
                                                           };
                                                           
                                                           static const uint32_t T0_3[256] = {
                                                               0x444e9e3eU,
                                                               0x82c6497fU,
                                                               0x1e4094e9U,
                                                               0xd7116fdeU,
                                                               0x637a2da4U,
                                                               0x59f6b580U,
                                                               0xa0dcdfd6U,
                                                               0xf4cd47f1U,
                                                               0x27f59fd2U,
                                                               0xeb01ebbcU,
                                                               0x59d1818bU,
                                                               0x21cf2c4eU,
                                                               0x472e405eU,
                                                               0xaf52b922U,
                                                               0xba211362U,
                                                               0x328063c3U,
                                                               0x52e60aa9U,
                                                               0xffc5c1e5U,
                                                               0x8adc1e7cU,
                                                               0x0d70f13aU,
                                                               0x96058ae8U,
                                                               0x24569d9bU,
                                                               0xac334cb7U,
                                                               0x17584aaeU,
                                                               0x866f196fU,
                                                               0x544d483bU,
                                                               0x5d189891U,
                                                               0xf8746b8dU,
                                                               0xb4a48e53U,
                                                               0xdeb14ab5U,
                                                               0x8707c420U,
                                                               0xdca90c9cU,
                                                               0xdb566997U,
                                                               0x0e5dc320U,
                                                               0x17bb6303U,
                                                               0x2df0d0d4U,
                                                               0x867b8b74U,
                                                               0xad6a8aecU,
                                                               0x9c1a8945U,
                                                               0x83c1ded3U,
                                                               0xc54298bfU,
                                                               0xcedf6a85U,
                                                               0x9ecdb7eaU,
                                                               0x1854a623U,
                                                               0x9539a266U,
                                                               0xfae1fe4fU,
                                                               0xdcbf0993U,
                                                               0xa6943e0cU,
                                                               0x22fd5f25U,
                                                               0x16f83dbdU,
                                                               0x5ad113abU,
                                                               0xaf0493e3U,
                                                               0x71a694c1U,
                                                               0xbb608438U,
                                                               0x3e7a11c0U,
                                                               0x75315eb4U,
                                                               0xcbb11e6cU,
                                                               0xccca0ad3U,
                                                               0x33a70c02U,
                                                               0xb560607bU,
                                                               0x11e4ca1aU,
                                                               0xbffd45c0U,
                                                               0x80c373c6U,
                                                               0x5d0c136dU,
                                                               0x34c50a58U,
                                                               0x9c813158U,
                                                               0x2d396124U,
                                                               0x89c71a5dU,
                                                               0xfccb7c7bU,
                                                               0x34781815U,
                                                               0xfc46c76cU,
                                                               0xee633618U,
                                                               0x4921bbf0U,
                                                               0x1c992669U,
                                                               0xe867b899U,
                                                               0x52798f1aU,
                                                               0x39ca8ca5U,
                                                               0xeb326bcdU,
                                                               0x5276beabU,
                                                               0x32ccec0eU,
                                                               0xe4502c95U,
                                                               0x9a2a43f3U,
                                                               0x90e6d77dU,
                                                               0x568038e3U,
                                                               0xba4cf646U,
                                                               0x577c064cU,
                                                               0xbe0c7b94U,
                                                               0xd8e4666aU,
                                                               0x72b760fcU,
                                                               0x0cd76230U,
                                                               0x6001d0d4U,
                                                               0x0e199cbdU,
                                                               0x3f693bbbU,
                                                               0x370f07fcU,
                                                               0xe4b762feU,
                                                               0xd3af9fceU,
                                                               0x392435baU,
                                                               0xb0fa964bU,
                                                               0xd070b603U,
                                                               0x90c2b60fU,
                                                               0x48972427U,
                                                               0xef09e7faU,
                                                               0x6aeb3f49U,
                                                               0xc1d86891U,
                                                               0x26400604U,
                                                               0xb2836327U,
                                                               0xd3b1a817U,
                                                               0x21655be8U,
                                                               0x431bd12fU,
                                                               0xa6d23745U,
                                                               0x27111686U,
                                                               0x1cfb2a98U,
                                                               0x488b1b56U,
                                                               0x1abe369aU,
                                                               0xca8f3c5cU,
                                                               0x90731e5aU,
                                                               0x505110d4U,
                                                               0x47741af8U,
                                                               0x601dc946U,
                                                               0xbbb97a04U,
                                                               0xffc3f767U,
                                                               0x94d37251U,
                                                               0x0dd2d8deU,
                                                               0x766a0a51U,
                                                               0x2d619892U,
                                                               0x0d26dc40U,
                                                               0x67177597U,
                                                               0x1ad8627eU,
                                                               0x447d67d0U,
                                                               0xa359c5d2U,
                                                               0xeb32bfc8U,
                                                               0xfac270cfU,
                                                               0x9914f6f3U,
                                                               0x4ef037c6U,
                                                               0x5c1e9abaU,
                                                               0xc30d5624U,
                                                               0xf794b26fU,
                                                               0x874a8bf7U,
                                                               0x1cd57b22U,
                                                               0xbce854a5U,
                                                               0x0894a366U,
                                                               0x9c996703U,
                                                               0x913359e3U,
                                                               0x6abef000U,
                                                               0xd00f935dU,
                                                               0x824c648dU,
                                                               0xd29f3d7eU,
                                                               0xfa282fedU,
                                                               0x894edf43U,
                                                               0xef65722eU,
                                                               0x14259f7cU,
                                                               0x0c36a94cU,
                                                               0x7499fff1U,
                                                               0xe3e85edcU,
                                                               0xf7fc609aU,
                                                               0xf77e0004U,
                                                               0x0e7c537cU,
                                                               0x33a7837eU,
                                                               0x3e9b8dbeU,
                                                               0x276fe231U,
                                                               0xa7f294ddU,
                                                               0xd02a6ea6U,
                                                               0x8a1792acU,
                                                               0x8666ed13U,
                                                               0x96fcc8a9U,
                                                               0x9e484fc5U,
                                                               0x65a855e8U,
                                                               0xc643f18fU,
                                                               0x24ad93bbU,
                                                               0x83eb9f16U,
                                                               0x4389c9e5U,
                                                               0x6ad1071bU,
                                                               0x37090731U,
                                                               0x9e0ca1b8U,
                                                               0x51961c37U,
                                                               0xb607a18fU,
                                                               0x91f90dbdU,
                                                               0x4281622eU,
                                                               0xdfbd83fbU,
                                                               0xbc74deadU,
                                                               0xc00a4f89U,
                                                               0x24937c32U,
                                                               0x0fe41076U,
                                                               0xd310b96dU,
                                                               0x359ffed9U,
                                                               0x1512e322U,
                                                               0x3f997cafU,
                                                               0x82657fc7U,
                                                               0x00a809bcU,
                                                               0x8071ca9fU,
                                                               0x53a48bc9U,
                                                               0x0d2782d9U,
                                                               0x83612921U,
                                                               0x0684b07bU,
                                                               0xd7596469U,
                                                               0x899bc49eU,
                                                               0x7692bf91U,
                                                               0x347ddb03U,
                                                               0x49d299b1U,
                                                               0xcf5ee9fdU,
                                                               0xc958420eU,
                                                               0x9d43f75fU,
                                                               0x40a42c7dU,
                                                               0x4c14e743U,
                                                               0xbf82f069U,
                                                               0x79d47ac7U,
                                                               0x68723460U,
                                                               0x1dfb4b2aU,
                                                               0x6687913aU,
                                                               0x10ccd1cbU,
                                                               0x5a852f12U,
                                                               0x7650f582U,
                                                               0xff32fc0cU,
                                                               0x27ab337cU,
                                                               0x4d64f859U,
                                                               0x28dbac3aU,
                                                               0xdd8ed75cU,
                                                               0x8ed5fea3U,
                                                               0x0a160125U,
                                                               0x41eebbd6U,
                                                               0x3fcfd311U,
                                                               0xf3e1a509U,
                                                               0x300c4e9aU,
                                                               0x829bc95dU,
                                                               0x9d0f06d3U,
                                                               0xe604fdaeU,
                                                               0xe0f5c473U,
                                                               0x582dd6cdU,
                                                               0xfdec5e33U,
                                                               0x58a9d1feU,
                                                               0x99e34fdaU,
                                                               0x2132b7e0U,
                                                               0x9c4fbe80U,
                                                               0xd20d3d31U,
                                                               0x480e1408U,
                                                               0x92a65f88U,
                                                               0x6233b50cU,
                                                               0xb25cf06aU,
                                                               0xde5082caU,
                                                               0x64991a32U,
                                                               0x6ebc49c5U,
                                                               0x69d1e2e8U,
                                                               0x031d55a3U,
                                                               0x9571c140U,
                                                               0x0e898434U,
                                                               0x6587acb4U,
                                                               0x8c3e5052U,
                                                               0x5e93dd49U,
                                                               0x49f879aeU,
                                                               0x8604b9d0U,
                                                               0x00c3579eU,
                                                               0xdaa2a15bU,
                                                               0x07ace1a6U,
                                                               0xa610aad8U,
                                                               0x29145c73U,
                                                               0x21bca41cU
                                                           };
                                                           
                                                           static const uint32_t T1_0[256] = {
                                                               0x5562ca88U,
                                                               0x0618bffcU,
                                                               0x55559df0U,
                                                               0xb3459360U,
                                                               0xf2165fc1U,
                                                               0xa2091caeU,
                                                               0xbcbb19cbU,
                                                               0x23e8fd93U,
                                                               0x8432b597U,
                                                               0x13d76083U,
                                                               0x6d5cd3d6U,
                                                               0xf1e08648U,
                                                               0x0e3ed2a5U,
                                                               0x705776f1U,
                                                               0x973ebfe0U,
                                                               0xd06f6229U,
                                                               0xb0aa89e4U,
                                                               0x781cfddeU,
                                                               0x54457aeaU,
                                                               0x4ec97c76U,
                                                               0x9966687eU,
                                                               0xee21a359U,
                                                               0xcd6fa2f0U,
                                                               0x359feabaU,
                                                               0xc672596aU,
                                                               0xfc8008c3U,
                                                               0x49cb9f33U,
                                                               0x3613a81eU,
                                                               0xcc8752bdU,
                                                               0xfe4ff775U,
                                                               0x4d63d169U,
                                                               0x90aa643aU,
                                                               0x93dc4875U,
                                                               0xc1c759a8U,
                                                               0x1a68bf7bU,
                                                               0xb3a0eba5U,
                                                               0x39734c42U,
                                                               0xd8529dfcU,
                                                               0xa4f4d573U,
                                                               0xc8a1f429U,
                                                               0xec0cd2ddU,
                                                               0xea2d5771U,
                                                               0xd9898fb1U,
                                                               0xa2b0fe7bU,
                                                               0x97ecd887U,
                                                               0x98b84bf6U,
                                                               0xc1f4e5d4U,
                                                               0x7ad64e3fU,
                                                               0x8dc98f93U,
                                                               0x9ebbe4a0U,
                                                               0x45991700U,
                                                               0x1e536913U,
                                                               0x9c9ce373U,
                                                               0xdc2aea53U,
                                                               0x8001939dU,
                                                               0x7139ada6U,
                                                               0x44e93f7dU,
                                                               0x3da2fa1aU,
                                                               0x48bdb5aaU,
                                                               0xf4d6ac3eU,
                                                               0x21434121U,
                                                               0xca3e018cU,
                                                               0x65d796dcU,
                                                               0x340eb759U,
                                                               0xa6fd8f71U,
                                                               0xf29e7ad9U,
                                                               0x0d2cd34fU,
                                                               0xaba0f6c0U,
                                                               0x32b9dde9U,
                                                               0x585234efU,
                                                               0x7c142387U,
                                                               0xcf348958U,
                                                               0xdeeeff1dU,
                                                               0xf689eee0U,
                                                               0x3fef79cdU,
                                                               0x53d8731bU,
                                                               0xe0d34640U,
                                                               0x85afefd0U,
                                                               0x5b67267aU,
                                                               0xd877c668U,
                                                               0x5ec0da56U,
                                                               0x41572797U,
                                                               0x52f4749dU,
                                                               0xa99eeacaU,
                                                               0xab5a8781U,
                                                               0xf56a5c3bU,
                                                               0xcb5363dcU,
                                                               0x0f777e37U,
                                                               0x2bcb5617U,
                                                               0x23cb0dafU,
                                                               0xb63c880fU,
                                                               0x1cfc7f29U,
                                                               0x8d111b1dU,
                                                               0x41ba2233U,
                                                               0x992b495aU,
                                                               0x8263b854U,
                                                               0x097fbe28U,
                                                               0x43e81622U,
                                                               0xce47cddaU,
                                                               0xd04c525fU,
                                                               0xc530a6e1U,
                                                               0xe343fab5U,
                                                               0x3257304dU,
                                                               0x1c4b2055U,
                                                               0x8544bd69U,
                                                               0xb0ead575U,
                                                               0xaec6c71bU,
                                                               0xbe1809aaU,
                                                               0x1ff685d0U,
                                                               0xde7176e5U,
                                                               0x93f2007aU,
                                                               0xb352574fU,
                                                               0x4814fbcdU,
                                                               0xccee2dbfU,
                                                               0xf876cff6U,
                                                               0xe2c89e19U,
                                                               0x5c670536U,
                                                               0xec625443U,
                                                               0xb50a8845U,
                                                               0x9fd716ddU,
                                                               0x85564037U,
                                                               0xfe1d450bU,
                                                               0x65764d4dU,
                                                               0x5629984bU,
                                                               0x8e5fb351U,
                                                               0x561a3401U,
                                                               0x845fb339U,
                                                               0x966232bfU,
                                                               0x6fa29475U,
                                                               0x94b533baU,
                                                               0xbd8609ceU,
                                                               0xf8c45f87U,
                                                               0xab0fc3f9U,
                                                               0x67cf314fU,
                                                               0x3883d0a0U,
                                                               0xb77eb1daU,
                                                               0x97d811abU,
                                                               0x6650a0adU,
                                                               0x6aaf9ec9U,
                                                               0x04306911U,
                                                               0xf9ca96f0U,
                                                               0x2f2392b6U,
                                                               0x7ab297a3U,
                                                               0x1307c29dU,
                                                               0x43ef8cd2U,
                                                               0x16fd921aU,
                                                               0x86cbc101U,
                                                               0x4f1f70a3U,
                                                               0x9944b3f5U,
                                                               0x09e24e60U,
                                                               0xa04f2b4aU,
                                                               0xff2d30ffU,
                                                               0x20111451U,
                                                               0x93cd026eU,
                                                               0xe2f35d1bU,
                                                               0x0aa948d4U,
                                                               0x12ddf10dU,
                                                               0x04aacb99U,
                                                               0xcaedc344U,
                                                               0x68aa796eU,
                                                               0x8bc8ae7eU,
                                                               0x2a8021e9U,
                                                               0xb5a4ee18U,
                                                               0xc6d75cc0U,
                                                               0x61dfd6f0U,
                                                               0x56832fb7U,
                                                               0x654933ebU,
                                                               0xd68c15c8U,
                                                               0xe378204fU,
                                                               0x40f6887fU,
                                                               0xe53fdcffU,
                                                               0x4401b152U,
                                                               0xc6730cfaU,
                                                               0xb2d67ad5U,
                                                               0x71b53fc2U,
                                                               0x8afa8e12U,
                                                               0x6b022672U,
                                                               0xc02f7f82U,
                                                               0xcd3701a7U,
                                                               0x1fc89607U,
                                                               0xe0999b48U,
                                                               0x546a45b9U,
                                                               0x0265855cU,
                                                               0x1ceb20abU,
                                                               0xa3e87aafU,
                                                               0x4a9e0d8eU,
                                                               0x87d49e9dU,
                                                               0xe59dc443U,
                                                               0x032a8546U,
                                                               0x07bcf497U,
                                                               0x23b56a40U,
                                                               0x629b72bdU,
                                                               0xa660da68U,
                                                               0x49a57aabU,
                                                               0xbdcf4357U,
                                                               0x60bcc45fU,
                                                               0x4bcbd93dU,
                                                               0x4716fecaU,
                                                               0x69804050U,
                                                               0x182ec5d1U,
                                                               0x1618b357U,
                                                               0x7bbe7ed8U,
                                                               0xcf2db57fU,
                                                               0x429a9ccfU,
                                                               0xbfd1fe81U,
                                                               0xe300c50cU,
                                                               0x70466311U,
                                                               0x76f2ad90U,
                                                               0xebc55f0fU,
                                                               0xca9ba678U,
                                                               0x5456aac9U,
                                                               0xd7edb74bU,
                                                               0xa589662eU,
                                                               0x08849c2fU,
                                                               0x247e523aU,
                                                               0xdaa022ebU,
                                                               0x0aa873c4U,
                                                               0xccf426c7U,
                                                               0x07cd12baU,
                                                               0x77a7db2eU,
                                                               0x76a2b6c7U,
                                                               0x49d02474U,
                                                               0x02df23f5U,
                                                               0xed837a40U,
                                                               0x7bc98073U,
                                                               0xb7bf453dU,
                                                               0x7cf36a3eU,
                                                               0xc6ca56b2U,
                                                               0xb38d7277U,
                                                               0xeced22e9U,
                                                               0xce4e1c40U,
                                                               0x5d0ea268U,
                                                               0x171dfb52U,
                                                               0x34f7bb9cU,
                                                               0x62ce3ee4U,
                                                               0x0b58cd86U,
                                                               0x206bebc0U,
                                                               0xfceb6e68U,
                                                               0xd65d3e4dU,
                                                               0x7ec0d8d8U,
                                                               0xf6bffe1bU,
                                                               0x7cb9d25cU,
                                                               0xfe2bc58aU,
                                                               0x800aceadU,
                                                               0xd55d56c8U,
                                                               0x1094ef42U,
                                                               0x12e654b8U,
                                                               0xa32ad1daU,
                                                               0x15d6257bU,
                                                               0x5d630620U,
                                                               0x314774cdU,
                                                               0xe252d6b0U,
                                                               0x30bc5613U,
                                                               0x4dcf54d5U,
                                                               0xf9bc6ee0U,
                                                               0x21857e96U
                                                           };
                                                           
                                                           static const uint32_t T1_1[256] = {
                                                               0x3fdcb1ceU,
                                                               0xa56a4f48U,
                                                               0x8829066aU,
                                                               0xe8b680c8U,
                                                               0x06c8bcdaU,
                                                               0x6bbc7b25U,
                                                               0x3b249c0cU,
                                                               0x057d7a93U,
                                                               0x1d18c271U,
                                                               0x47017becU,
                                                               0x14fef61eU,
                                                               0xbfc291bbU,
                                                               0x2a594069U,
                                                               0x36fee75dU,
                                                               0x9488a37dU,
                                                               0x5d1bcbb7U,
                                                               0x0a8f02efU,
                                                               0x0e92cf71U,
                                                               0x3a624fccU,
                                                               0x1cb02005U,
                                                               0x8dcb2625U,
                                                               0xbff7443eU,
                                                               0xd53c79bdU,
                                                               0xdd7bca6aU,
                                                               0x7e08d398U,
                                                               0xf2a6323dU,
                                                               0x85f8d3afU,
                                                               0x9a8cc5b4U,
                                                               0xf3838586U,
                                                               0xd6fed6e3U,
                                                               0xe43d04deU,
                                                               0x762b14a7U,
                                                               0x0c65f62eU,
                                                               0x8aab8522U,
                                                               0x89743059U,
                                                               0x30731414U,
                                                               0xf996afa4U,
                                                               0xc4200264U,
                                                               0xb4ee7e82U,
                                                               0xef41a62cU,
                                                               0x0ef6973aU,
                                                               0x7cddb948U,
                                                               0x56e5b4b0U,
                                                               0xe5eaaf38U,
                                                               0xf54a364cU,
                                                               0x8259f23bU,
                                                               0xe660c880U,
                                                               0x335dfc0dU,
                                                               0x54211afcU,
                                                               0x131007e7U,
                                                               0x87f5d308U,
                                                               0x1fd496f9U,
                                                               0x0fda119fU,
                                                               0x832a1cc0U,
                                                               0xa0067d5cU,
                                                               0x58cc65e5U,
                                                               0x41355d88U,
                                                               0x9672add7U,
                                                               0x82698cb7U,
                                                               0xeddcd4b1U,
                                                               0x9a5758adU,
                                                               0x62990259U,
                                                               0x611a29d3U,
                                                               0x9385b28aU,
                                                               0x235f99aeU,
                                                               0xc8738b95U,
                                                               0xb1922aacU,
                                                               0x838ca838U,
                                                               0x5351c8f1U,
                                                               0xd51ad73fU,
                                                               0x6f01e1bdU,
                                                               0x471abb8fU,
                                                               0xabd59114U,
                                                               0xfaee97d9U,
                                                               0x23ddfe52U,
                                                               0x2581d1feU,
                                                               0xbdfc756dU,
                                                               0xe718978bU,
                                                               0x1ab2c19eU,
                                                               0x5661b918U,
                                                               0x3b0643c1U,
                                                               0x4fa4ee19U,
                                                               0xdb514cc4U,
                                                               0x3a601d75U,
                                                               0xacde488eU,
                                                               0x4f32aafaU,
                                                               0x578fbc67U,
                                                               0x0329bfb1U,
                                                               0x4ecbcffbU,
                                                               0x319f735bU,
                                                               0x2b030d44U,
                                                               0xad5d90aeU,
                                                               0x2b9500fdU,
                                                               0xcd4da8f1U,
                                                               0x091569e1U,
                                                               0x0a1b59d1U,
                                                               0x16ec6893U,
                                                               0x3f21e49fU,
                                                               0x169fd644U,
                                                               0xa42868ffU,
                                                               0x6384615aU,
                                                               0x87ebaea8U,
                                                               0xc2155ff9U,
                                                               0x1f46e3f5U,
                                                               0xf21e22b5U,
                                                               0x2abffc2eU,
                                                               0x73a11b53U,
                                                               0x3ce0e0b6U,
                                                               0xf9a807caU,
                                                               0x8d733637U,
                                                               0x8a4068f4U,
                                                               0xc4e744b8U,
                                                               0x2a625719U,
                                                               0xeb3054abU,
                                                               0x62d371d0U,
                                                               0xf9e365b5U,
                                                               0xb4ac2691U,
                                                               0x1d3d3101U,
                                                               0x0eedb5acU,
                                                               0xbb8377faU,
                                                               0x65762abdU,
                                                               0x65a87ef1U,
                                                               0x29d9c63bU,
                                                               0x87b54373U,
                                                               0xe63b5b79U,
                                                               0x579257afU,
                                                               0xe9c7bbbaU,
                                                               0x5fa35b87U,
                                                               0x5ea139c1U,
                                                               0xa6b1fee8U,
                                                               0x8989619cU,
                                                               0xf3702d33U,
                                                               0x8b8c5fd8U,
                                                               0xdaa05461U,
                                                               0xb4dda16fU,
                                                               0xe02cdb1cU,
                                                               0x2ae69c26U,
                                                               0x043ac8c0U,
                                                               0x25fd7be2U,
                                                               0x4b2d16d5U,
                                                               0x62b9779dU,
                                                               0x2d0d1d01U,
                                                               0xc4aeb4bfU,
                                                               0x02afe6c6U,
                                                               0xb29a9ac6U,
                                                               0xecf309aeU,
                                                               0xbf001bebU,
                                                               0x960ed508U,
                                                               0xab084faeU,
                                                               0x8a6998f1U,
                                                               0x02244a62U,
                                                               0xe23ff170U,
                                                               0x251628eaU,
                                                               0x1d98168cU,
                                                               0x77748871U,
                                                               0xb3350755U,
                                                               0xbdb9f0c1U,
                                                               0xfce4b36bU,
                                                               0x3f38407eU,
                                                               0x85155bd1U,
                                                               0xf9ccc748U,
                                                               0x0820bce5U,
                                                               0x370015c4U,
                                                               0x832c9101U,
                                                               0x18310479U,
                                                               0xc8abba19U,
                                                               0x86a088ddU,
                                                               0x9134b620U,
                                                               0xcddf70e5U,
                                                               0x74f65a9eU,
                                                               0x98e21fbbU,
                                                               0x58cd4431U,
                                                               0xa63eb20aU,
                                                               0xb7251a0dU,
                                                               0x63a82562U,
                                                               0x9bb8b545U,
                                                               0x25b5ae11U,
                                                               0xa2e75f0dU,
                                                               0x47fcb19dU,
                                                               0x1f42fe7aU,
                                                               0x4a8738eaU,
                                                               0x6a6887c0U,
                                                               0xd21f56e9U,
                                                               0xed4761d9U,
                                                               0x02095926U,
                                                               0xc444b5b8U,
                                                               0x306bdc8cU,
                                                               0x42f0aebeU,
                                                               0x9450d432U,
                                                               0xe09b2f29U,
                                                               0x9980f432U,
                                                               0x886659b9U,
                                                               0x61a446dbU,
                                                               0xa2f74111U,
                                                               0x500723c7U,
                                                               0x36f03d25U,
                                                               0xb1fe644eU,
                                                               0x9bff02edU,
                                                               0x13ee5523U,
                                                               0xd32b1ea8U,
                                                               0x8eb3e100U,
                                                               0xbf0caf09U,
                                                               0xa099ab6dU,
                                                               0x8f6dcb49U,
                                                               0x49c17c0aU,
                                                               0x1b1307e6U,
                                                               0xbfbf0398U,
                                                               0x43b76187U,
                                                               0xb5b9dadfU,
                                                               0xcc2452e1U,
                                                               0x3e231d9cU,
                                                               0x200dfc4fU,
                                                               0x8569a06bU,
                                                               0x12175eb5U,
                                                               0x5d2aaa4dU,
                                                               0x338271d9U,
                                                               0x76887d05U,
                                                               0xd93c9074U,
                                                               0x8910da1aU,
                                                               0xc26c2576U,
                                                               0xcef6dc2bU,
                                                               0x1c223841U,
                                                               0x70711033U,
                                                               0x5578d083U,
                                                               0x0389b418U,
                                                               0x4f85fc3bU,
                                                               0x51f983ccU,
                                                               0x03364869U,
                                                               0xa1e7bab0U,
                                                               0x459912deU,
                                                               0x86f8752bU,
                                                               0x77d34847U,
                                                               0x365cc398U,
                                                               0x153fb9bfU,
                                                               0x6ddd6f94U,
                                                               0x40c1ef61U,
                                                               0x54549d9fU,
                                                               0x4c153180U,
                                                               0x58320e60U,
                                                               0x77c83ab5U,
                                                               0x59573198U,
                                                               0xf33c1595U,
                                                               0x907e19e0U,
                                                               0xbb3813b2U,
                                                               0x44f2d835U,
                                                               0x47b06dbcU,
                                                               0xebb9907aU,
                                                               0x395a1f1aU,
                                                               0x54213dbbU,
                                                               0x037c90b2U,
                                                               0x3dda5ce7U,
                                                               0x8e280066U,
                                                               0x860c1c88U,
                                                               0x3f620a6dU,
                                                               0xf0153eb2U,
                                                               0x15cfe3a3U
                                                           };
                                                           
                                                           static const uint32_t T1_2[256] = {
                                                               0x1be80d26U,
                                                               0x89e29be4U,
                                                               0x4f1f5104U,
                                                               0x52a778c3U,
                                                               0x1210b62cU,
                                                               0x5e20720dU,
                                                               0xbf1a64a2U,
                                                               0xfd6d02faU,
                                                               0xbe60b448U,
                                                               0xcb4a4e57U,
                                                               0x98c33efcU,
                                                               0x93eeab14U,
                                                               0xec1a34eeU,
                                                               0x151e557aU,
                                                               0xc84e8fc4U,
                                                               0x296f9679U,
                                                               0xcc0ed10aU,
                                                               0x63ad6c16U,
                                                               0xaa0359dfU,
                                                               0x93780084U,
                                                               0xeb854e9dU,
                                                               0x027c33dbU,
                                                               0x8a52d0cfU,
                                                               0x38af61d4U,
                                                               0x55445f42U,
                                                               0x2bf2426fU,
                                                               0x1ab6775dU,
                                                               0xaf3c4ba9U,
                                                               0xcb33eec3U,
                                                               0xc24dabbdU,
                                                               0xfaec5c70U,
                                                               0xec3ec08aU,
                                                               0x34da229bU,
                                                               0xa812595bU,
                                                               0x73aa9a84U,
                                                               0xb371ba03U,
                                                               0x87927aa7U,
                                                               0x014fa820U,
                                                               0x069c6792U,
                                                               0x35375382U,
                                                               0xa2b71380U,
                                                               0xd8b015b2U,
                                                               0x99722a07U,
                                                               0x855e1176U,
                                                               0x8eee17f2U,
                                                               0x1e508713U,
                                                               0xc89826d1U,
                                                               0x3df6c455U,
                                                               0x4c06d59dU,
                                                               0xb5db07ecU,
                                                               0xbb6744f5U,
                                                               0x0798ee48U,
                                                               0x610dac33U,
                                                               0x947f0851U,
                                                               0x4ae3c3d7U,
                                                               0xdc240875U,
                                                               0x8e704dffU,
                                                               0xb9dbc812U,
                                                               0x1e7adc11U,
                                                               0x574f1183U,
                                                               0xf66f8c40U,
                                                               0x140435b6U,
                                                               0xd29b9f59U,
                                                               0xb2325a9bU,
                                                               0x49921a91U,
                                                               0x4b6f8353U,
                                                               0x90e36dabU,
                                                               0x916a7e66U,
                                                               0xc1fe699dU,
                                                               0x8443280aU,
                                                               0x24f23b07U,
                                                               0xad26335dU,
                                                               0xa45fcc06U,
                                                               0x2966cd5eU,
                                                               0x2f37abb8U,
                                                               0xa5203332U,
                                                               0xd4982e03U,
                                                               0xfd5116f0U,
                                                               0xf0e08120U,
                                                               0x5d2564c0U,
                                                               0xe6961d8cU,
                                                               0x4786d128U,
                                                               0x52168f38U,
                                                               0xcb28b3f3U,
                                                               0x6fb34903U,
                                                               0x5d69a5dbU,
                                                               0xb6b53141U,
                                                               0x5f7def81U,
                                                               0x829f23c9U,
                                                               0xdc69e32eU,
                                                               0xc7f594dfU,
                                                               0x9d88b313U,
                                                               0xc90bfbeeU,
                                                               0xd999ee1bU,
                                                               0x23af7548U,
                                                               0xc1abda03U,
                                                               0x18697767U,
                                                               0xd4626177U,
                                                               0xea3e0700U,
                                                               0x23025befU,
                                                               0xace47beaU,
                                                               0x617448acU,
                                                               0xc8ac3479U,
                                                               0x10426de8U,
                                                               0x4474e9dbU,
                                                               0x9ebf3910U,
                                                               0xab8c8350U,
                                                               0x5de700f7U,
                                                               0x01edf70eU,
                                                               0xae36556dU,
                                                               0x6ebd484fU,
                                                               0x836215feU,
                                                               0x4963cc11U,
                                                               0xc2d54e7aU,
                                                               0x61bd1f12U,
                                                               0xf276d17cU,
                                                               0xb9a0f0aaU,
                                                               0xdbe0cf86U,
                                                               0xe3f2c690U,
                                                               0xab3a6a9aU,
                                                               0x20b79027U,
                                                               0x07bf455dU,
                                                               0xd10ae8d6U,
                                                               0xd9aa06e0U,
                                                               0xb0743964U,
                                                               0x6387dbb6U,
                                                               0x4e8464f7U,
                                                               0x52c8455bU,
                                                               0xce5283abU,
                                                               0xda824191U,
                                                               0xdeb47125U,
                                                               0x426f9d13U,
                                                               0x6dce1efcU,
                                                               0x59413665U,
                                                               0x9cf94649U,
                                                               0xb8e0c993U,
                                                               0x7239ca07U,
                                                               0xa9931ad4U,
                                                               0x0b2eb0eeU,
                                                               0x968c8ec4U,
                                                               0xaf529184U,
                                                               0x3484c267U,
                                                               0x199e18c1U,
                                                               0xdbf5fb87U,
                                                               0x39aaea7aU,
                                                               0xdfe662afU,
                                                               0xc924c10cU,
                                                               0xca74386dU,
                                                               0xbc7872a3U,
                                                               0x78cc4455U,
                                                               0x65918119U,
                                                               0x6b68d3c1U,
                                                               0x11b1b0adU,
                                                               0x00367535U,
                                                               0x91772320U,
                                                               0x6904e102U,
                                                               0x8345254bU,
                                                               0x1dcd4111U,
                                                               0x7457bc2bU,
                                                               0xa9d8f209U,
                                                               0x8d0e6608U,
                                                               0x23ae7820U,
                                                               0x087fbcf1U,
                                                               0x4a2c176bU,
                                                               0xe95747a7U,
                                                               0x32f3be75U,
                                                               0x829d311aU,
                                                               0xf1ba5ac9U,
                                                               0x2e416cebU,
                                                               0x0c1ba8a4U,
                                                               0x89a63cacU,
                                                               0x1efce9d5U,
                                                               0xb8cd318dU,
                                                               0x7019262dU,
                                                               0xdd3adeb9U,
                                                               0x8b4b2f03U,
                                                               0xfb3ade11U,
                                                               0xdf953da9U,
                                                               0x04aa11d8U,
                                                               0x9c008491U,
                                                               0xec1e03e7U,
                                                               0xa86103dcU,
                                                               0x1e258401U,
                                                               0xd93b2db9U,
                                                               0xd25ac0fcU,
                                                               0x9d2b5b61U,
                                                               0xcfc8c2aaU,
                                                               0x21ac9cefU,
                                                               0xba2ea843U,
                                                               0x79df819cU,
                                                               0x6cedc424U,
                                                               0xd31d79b2U,
                                                               0xac1af89cU,
                                                               0x99a798ceU,
                                                               0x2b3f1babU,
                                                               0x87ebb681U,
                                                               0xc6a216deU,
                                                               0x29f935bdU,
                                                               0x1ca88f95U,
                                                               0xc1707501U,
                                                               0xb2ad3bffU,
                                                               0x6ba4ba13U,
                                                               0x0bf81d25U,
                                                               0xc00d1f3eU,
                                                               0x4a865e43U,
                                                               0xa786184dU,
                                                               0xae41dae3U,
                                                               0x08543f98U,
                                                               0xd7b5a129U,
                                                               0x5bae0144U,
                                                               0x15d11ef2U,
                                                               0x1d5319a1U,
                                                               0xe4dc6ca1U,
                                                               0xa86ea989U,
                                                               0x3f4cd4c4U,
                                                               0x42edb680U,
                                                               0x3962e92aU,
                                                               0x8d86c933U,
                                                               0xd1203fa6U,
                                                               0xd8fd1c81U,
                                                               0x05112f11U,
                                                               0x9ce51820U,
                                                               0xbdc070bbU,
                                                               0x85ef5b6aU,
                                                               0x44bec930U,
                                                               0x47b0d749U,
                                                               0x45e14c49U,
                                                               0x64049ed8U,
                                                               0xfd061072U,
                                                               0xc2b73439U,
                                                               0x288c3bf2U,
                                                               0x274b9916U,
                                                               0x9644a9b9U,
                                                               0x46fe9995U,
                                                               0x233b6a6bU,
                                                               0x3248d23eU,
                                                               0x2fc70033U,
                                                               0x275b680dU,
                                                               0x76d4808fU,
                                                               0x799fc4beU,
                                                               0x79f37a5eU,
                                                               0xb3227d13U,
                                                               0x2262a6b8U,
                                                               0x5e78d88fU,
                                                               0x93681076U,
                                                               0x9ea673acU,
                                                               0x8b501da7U,
                                                               0x82e70c6eU,
                                                               0x81111b0cU,
                                                               0xa42d5bd6U,
                                                               0x9a25175dU,
                                                               0x63bc7133U,
                                                               0xc79951eaU,
                                                               0x18773f12U,
                                                               0x90089940U,
                                                               0xe48432e4U
                                                           };
                                                           
                                                           static const uint32_t T1_3[256] = {
                                                               0xee6d611eU,
                                                               0xc8956e82U,
                                                               0x4b611b1dU,
                                                               0xe94ab508U,
                                                               0xb615d063U,
                                                               0x55fe9570U,
                                                               0x163b454cU,
                                                               0x6bce4c4eU,
                                                               0x0bbd81ebU,
                                                               0xa980bdf4U,
                                                               0xb8223167U,
                                                               0x9e7fad7cU,
                                                               0x44023e55U,
                                                               0xe0744af7U,
                                                               0xf5f7d0b3U,
                                                               0xc1b032b2U,
                                                               0x0012f6eeU,
                                                               0xf46ff432U,
                                                               0xc151215bU,
                                                               0x26f63a10U,
                                                               0x5a3d149aU,
                                                               0xb5eb0490U,
                                                               0x311e176aU,
                                                               0x3ab9e8aeU,
                                                               0x3125c9ecU,
                                                               0x76306d79U,
                                                               0x57aafb7aU,
                                                               0x38b803a8U,
                                                               0x9cc2e66fU,
                                                               0x32fca0d6U,
                                                               0xb58869ffU,
                                                               0xd24894fdU,
                                                               0xe4769859U,
                                                               0xe64493cdU,
                                                               0xd283c647U,
                                                               0xf0b7318aU,
                                                               0xa9d9833cU,
                                                               0x635de732U,
                                                               0xe82b4d34U,
                                                               0x9075ac76U,
                                                               0xbc7050abU,
                                                               0x78cd1a08U,
                                                               0x6504e912U,
                                                               0x8946c7a1U,
                                                               0x96b89930U,
                                                               0x54b8171aU,
                                                               0x9a0486a3U,
                                                               0x8282f035U,
                                                               0x82f41882U,
                                                               0xdd513ab5U,
                                                               0x27295b2dU,
                                                               0xa8c98831U,
                                                               0x6c82e513U,
                                                               0x675c2401U,
                                                               0xe54dee7fU,
                                                               0xd03c347fU,
                                                               0xb988cbf5U,
                                                               0x5f56710dU,
                                                               0x6ad2129eU,
                                                               0xf060b355U,
                                                               0x9e2e652bU,
                                                               0x7c7d123fU,
                                                               0x01cdf3b8U,
                                                               0x44fb4b14U,
                                                               0xe71402b5U,
                                                               0x9eed285fU,
                                                               0x5fa23368U,
                                                               0xc05f36b5U,
                                                               0xb0ffeaf5U,
                                                               0xceaeb300U,
                                                               0xb9e4fb7fU,
                                                               0xfac7b13bU,
                                                               0x6ab3671bU,
                                                               0x6bdedbe8U,
                                                               0xf7cbfc76U,
                                                               0x3ed819d1U,
                                                               0x95446942U,
                                                               0x354d3bdfU,
                                                               0xf369450bU,
                                                               0xa806a7b4U,
                                                               0x997f9954U,
                                                               0xe797ff7cU,
                                                               0x655adbaaU,
                                                               0x9133454bU,
                                                               0x0bf4b7e9U,
                                                               0xd6138f68U,
                                                               0x0ffce462U,
                                                               0x9e3cfc7fU,
                                                               0xc6136c14U,
                                                               0xd099ad36U,
                                                               0x3b26bc32U,
                                                               0x9e55e59cU,
                                                               0xfe2fb1c1U,
                                                               0xab63b54eU,
                                                               0x9e60a898U,
                                                               0xb8a0023eU,
                                                               0xbfd281c0U,
                                                               0x25f8d2f4U,
                                                               0x4cc8edd8U,
                                                               0x4ac379b7U,
                                                               0x651521caU,
                                                               0x36c85812U,
                                                               0x1a54ebdeU,
                                                               0x98a1ae3dU,
                                                               0x145abf54U,
                                                               0xac2ac31dU,
                                                               0x6b5a5576U,
                                                               0x01e1fe54U,
                                                               0xfbc21eb7U,
                                                               0xc05c72acU,
                                                               0x177f9796U,
                                                               0xbc4a00baU,
                                                               0x434e867bU,
                                                               0x30328ac4U,
                                                               0x3ec1a3b3U,
                                                               0x304b2a91U,
                                                               0x81b0d748U,
                                                               0x35af1d59U,
                                                               0xb5fba3e3U,
                                                               0x3f6d7f41U,
                                                               0x6927d29cU,
                                                               0xa733a27fU,
                                                               0xed49389bU,
                                                               0x65e8e36fU,
                                                               0x88c6200bU,
                                                               0x1e8942f6U,
                                                               0x6063d6b6U,
                                                               0x8a11ec88U,
                                                               0xa7b7ff87U,
                                                               0x40484d82U,
                                                               0x7554e496U,
                                                               0x966513e3U,
                                                               0x848b7fc6U,
                                                               0x4fd7d3deU,
                                                               0x9ba8b126U,
                                                               0x9b7e9d73U,
                                                               0x55821d50U,
                                                               0xd24a62ecU,
                                                               0x29e3610dU,
                                                               0x6bb1d03cU,
                                                               0x0ce64e77U,
                                                               0x0bd4f9c9U,
                                                               0xb8e9393aU,
                                                               0x14531b98U,
                                                               0xa144f516U,
                                                               0x41dd0278U,
                                                               0xb39d53bcU,
                                                               0x90c9b2f5U,
                                                               0x290c1fe6U,
                                                               0x73d39b42U,
                                                               0x1f9c35eeU,
                                                               0x7628a061U,
                                                               0x46ab455aU,
                                                               0x7f073252U,
                                                               0x9a4107d6U,
                                                               0xf0c29b47U,
                                                               0xfaec50fbU,
                                                               0x27fabb6eU,
                                                               0xe927ac1aU,
                                                               0xbbb94d19U,
                                                               0x673660e0U,
                                                               0x0cfd0890U,
                                                               0x900effc2U,
                                                               0xa4772280U,
                                                               0x630a0d08U,
                                                               0x1173a6d3U,
                                                               0x1cd8ccefU,
                                                               0x883ad9e2U,
                                                               0x571ee88eU,
                                                               0x35f3ab23U,
                                                               0xf0d93eadU,
                                                               0xf5e9adc8U,
                                                               0x76ccc4b1U,
                                                               0xe7350505U,
                                                               0x338cb46fU,
                                                               0x85c25788U,
                                                               0xd25415e2U,
                                                               0x77996d7fU,
                                                               0x74efc903U,
                                                               0x5b947654U,
                                                               0xe5dde524U,
                                                               0x1bcf8514U,
                                                               0xcde1f305U,
                                                               0x4ab8e3e6U,
                                                               0x91fa850eU,
                                                               0xd2983b73U,
                                                               0x7b851eedU,
                                                               0xaee2a798U,
                                                               0x97742b81U,
                                                               0x9bac16feU,
                                                               0x352a00b0U,
                                                               0x81f5d214U,
                                                               0x2e458426U,
                                                               0x011ac70aU,
                                                               0xab420efbU,
                                                               0xaf076046U,
                                                               0x8fa2e58fU,
                                                               0x32f73e3bU,
                                                               0xdc3c3ec1U,
                                                               0x19a43de1U,
                                                               0xd7399e60U,
                                                               0xccfbdd1eU,
                                                               0xb9ebedffU,
                                                               0x5d38aebeU,
                                                               0x951e86b3U,
                                                               0x581c018cU,
                                                               0x334cde8bU,
                                                               0x4f3d9d36U,
                                                               0x3899cf0fU,
                                                               0x383ee190U,
                                                               0xe495750bU,
                                                               0xc2a7d8cfU,
                                                               0x9d3ff799U,
                                                               0x034dd97dU,
                                                               0x08e3065eU,
                                                               0x61f888a1U,
                                                               0xa6aaa52fU,
                                                               0x8d76e070U,
                                                               0x8d48a8cdU,
                                                               0x74d19738U,
                                                               0xc832d54dU,
                                                               0xb79dd94cU,
                                                               0xbe8b3d41U,
                                                               0x7f8c4390U,
                                                               0xbd8eb353U,
                                                               0x5b2d6e23U,
                                                               0xbe6a9215U,
                                                               0xbe52a389U,
                                                               0xf9ae042eU,
                                                               0x20866ce1U,
                                                               0xc0504523U,
                                                               0x2e61f1c0U,
                                                               0x2c62f9caU,
                                                               0xc0c64e6eU,
                                                               0xa43cc1dcU,
                                                               0x1b20ce71U,
                                                               0x7ee72ffbU,
                                                               0x3ef8af17U,
                                                               0xdb721732U,
                                                               0x008ac30eU,
                                                               0x019a0e48U,
                                                               0x47c08cd1U,
                                                               0xa12c6b15U,
                                                               0xf32f2ca0U,
                                                               0x7eb2c391U,
                                                               0x966810b1U,
                                                               0xb065d882U,
                                                               0x64ef6d66U,
                                                               0xf75c9d68U,
                                                               0x9763a4b9U,
                                                               0x9c1045ceU,
                                                               0xdfad155cU,
                                                               0x7b4e57c3U,
                                                               0xc37e702eU,
                                                               0xb2914e78U,
                                                               0xd9615101U
                                                           };
                                                           
                                                           static __attribute__((always_inline)) inline uint32_t rotl32(uint32_t x, uint32_t n) noexcept {
                                                           
                                                               return ((x << n) | (x >> (0x00000020U - n)));
                                                           }
                                                           
                                                           static __attribute__((always_inline)) inline uint32_t derive_seed() noexcept {
                                                           
                                                               const uint32_t s0 = 0xab4cb3cdU;
                                                               uint32_t x0 = T0_0[(s0 & 0x000000ffU)];
                                                               uint32_t x1 = T0_1[((s0 >> 0x00000008U) & 0x000000ffU)];
                                                               uint32_t x2 = T0_2[((s0 >> 0x00000010U) & 0x000000ffU)];
                                                               uint32_t x3 = T0_3[((s0 >> 0x00000018U) & 0x000000ffU)];
                                                               uint32_t y0 = (rotl32(x0, 0x00000007U) ^ x1);
                                                               uint32_t y1 = (rotl32(x1, 0x0000000bU) ^ x2);
                                                               uint32_t y2 = (rotl32(x2, 0x00000013U) ^ x3);
                                                               uint32_t y3 = (rotl32(x3, 0x00000017U) ^ x0);
                                                               uint32_t z0 = T1_0[(y0 & 0x000000ffU)];
                                                               uint32_t z1 = T1_1[(y1 & 0x000000ffU)];
                                                               uint32_t z2 = T1_2[(y2 & 0x000000ffU)];
                                                               uint32_t z3 = T1_3[(y3 & 0x000000ffU)];
                                                               return (((z0 ^ z1) ^ z2) ^ z3);
                                                           }
                                
                                } // namespace asgard_whitebox
                                
                                static __attribute__((always_inline)) inline uint32_t asgard_wbox_derive_seed() noexcept {
                                
                                    return asgard_whitebox::derive_seed();
                                }
                                
                                // Randomized Architectural Register Map (π ∈ S_32)
                                
                                enum RegMap : uint8_t {
                                                           REG_RAX = 1,
                                                           REG_RCX = 11,
                                                           REG_RDX = 6,
                                                           REG_RBX = 18,
                                                           REG_RSP = 22,
                                                           REG_RBP = 13,
                                                           REG_RSI = 23,
                                                           REG_RDI = 27,
                                                           REG_R8 = 12,
                                                           REG_R9 = 5,
                                                           REG_R10 = 2,
                                                           REG_R11 = 26,
                                                           REG_R12 = 16,
                                                           REG_R13 = 24,
                                                           REG_R14 = 31,
                                                           REG_R15 = 10,
                                                           REG_VTMP0 = 17,
                                                           REG_VTMP1 = 7,
                                                           REG_VTMP2 = 30,
                                                           REG_VTMP3 = 25,
                                                           REG_VIP = 3,
                                                           REG_VSP = 15,
                                                           REG_VKEY = 0,
                                                           REG_VX18 = 14,
                                                           REG_VX19 = 4,
                                                           REG_VX20 = 20,
                                                           REG_VX21 = 9,
                                                           REG_VX22 = 8,
                                                           REG_VX23 = 29,
                                                           REG_VX24 = 28,
                                                           REG_VX25 = 21,
                                                           REG_VX26 = 19,
                                                           
                                };
                                
                                // 64-bit Cryptographic Key Derivation for Bytecode Offset (SplitMix64)
                                
                                __attribute__((always_inline)) inline static uint64_t key64_for_offset(uint32_t seed, size_t offset) noexcept {
                                
                                    uint64_t s64 = static_cast<uint64_t>(seed);
                                    uint64_t x0 = (((s64 << 0x0000000000000020ULL) | (s64 ^ 0x000000009e3779b9ULL)) ^ (static_cast<uint64_t>(offset) * 0x517cc1b727220a95ULL));
                                    uint64_t x1 = ((x0 ^ (x0 >> 0x000000000000001eULL)) * 0xbf58476d1ce4e5b9ULL);
                                    uint64_t x2 = ((x1 ^ (x1 >> 0x000000000000001bULL)) * 0x94d049bb133111ebULL);
                                    return (x2 ^ (x2 >> 0x000000000000001fULL));
                                }
                                
                                // Handlers Table Integrity Hash
                                
                                __attribute__((always_inline)) inline static uint64_t compute_handlers_hash(const uintptr_t* all_domains, size_t num_domains) noexcept {
                                
                                    uint64_t h = 0x5877cafebabe1337ULL;
                                    for (size_t d = 0x0000000000000000ULL; d < num_domains; ++d) {
                                    
                                        for (size_t op = 0x0000000000000000ULL; op < 0x0000000000000100ULL; ++op) {
                                        
                                            uint64_t ptr_val = static_cast<uint64_t>(all_domains[((d * 0x0000000000000100ULL) + op)]);
                                            h ^= (ptr_val * 0x9e3779b97f4a7c15ULL);
                                            h = ((h >> 0x000000000000001bULL) | (h << 0x0000000000000025ULL));
                                            h *= 0xbf58476d1ce4e5b9ULL;
                                        }
                                    }
                                    h ^= asgard_mem_integrity::compute_section_integrity_hash();
                                    return (h ^ (h >> 0x000000000000001fULL));
                                }
                                
                                // Blinded VMContext with Canary Guard Zones & Per-Slot Masking (P1-04b)
                                
                                struct VMContext {
                                                      static inline constexpr uint64_t CANARY_VAL = 0xcafebabe13375877ULL;
                                                      uint64_t canary_head = CANARY_VAL;
                                                      uint64_t mid_canaries[32];
                                                      uint64_t gprs[32];
                                                      uint64_t slot_masks[32];
                                                      uint64_t vregs[32][8];
                                                      uint64_t stack[512];
                                                      size_t sp;
                                                      uint64_t reg_mask;
                                                      uint32_t init_seed;
                                                      uint64_t poison_penalty;
                                                      uint64_t running_key;
                                                      bool cf;
                                                      bool zf;
                                                      bool sf;
                                                      bool of;
                                                      bool trapped;
                                                      size_t executed_instructions;
                                                      uint64_t canary_tail = CANARY_VAL;
                                                      static inline constexpr size_t REG_AFFINE_A = 27;
                                                      static inline constexpr size_t REG_AFFINE_B = 15;
                                                      static __attribute__((always_inline)) inline uint8_t reg_phys_idx(uint8_t i) noexcept {
                                                      
                                                          return static_cast<uint8_t>((((static_cast<size_t>((i & 31)) * REG_AFFINE_A) + REG_AFFINE_B) & 31));
                                                      }
                                                      __attribute__((always_inline)) inline void init(uint32_t seed = asgard_wbox_derive_seed()) noexcept {
                                                      
                                                          init_seed = seed;
                                                          poison_penalty = ((key64_for_offset(seed, 0x0000000000005877ULL) ^ 0xcaa7e1d8718bf877ULL) | 0x0000000000000001ULL);
                                                          running_key = (key64_for_offset(seed, 0x0000000013375877ULL) ^ 0xcafebabe13375877ULL);
                                                          reg_mask = (0x5a5a5a5a13375877ULL ^ (static_cast<uint64_t>(seed) * 0x9e3779b97f4a7c15ULL));
                                                          for (size_t i = 0x0000000000000000ULL; i < 0x0000000000000020ULL; ++i) {
                                                          
                                                              slot_masks[i] = (key64_for_offset(seed, (0x0000000000001000ULL + i)) ^ 0xa5a5a5a51337beefULL);
                                                              gprs[i] = (slot_masks[i] ^ reg_mask);
                                                              mid_canaries[i] = (CANARY_VAL ^ ((static_cast<uint64_t>(i) * 0x517cc1b727220a95ULL) ^ static_cast<uint64_t>(seed)));
                                                              vregs[i][0] = 0x0000000000000000ULL;
                                                              for (size_t v = 0x0000000000000001ULL; v < 0x0000000000000008ULL; ++v) {
                                                              
                                                                  vregs[i][v] = 0x0000000000000000ULL;
                                                              }
                                                          }
                                                          sp = 0x0000000000000000ULL;
                                                          cf = false;
                                                          zf = false;
                                                          sf = false;
                                                          of = false;
                                                          trapped = false;
                                                          executed_instructions = 0x0000000000000000ULL;
                                                          canary_head = CANARY_VAL;
                                                          canary_tail = CANARY_VAL;
                                                      }
                                                      static __attribute__((always_inline)) inline uint64_t advance_key_step(uint64_t k, uint8_t op, uint8_t dst, int64_t imm) noexcept {
                                                      
                                                          uint64_t x = (k ^ (((static_cast<uint64_t>(op) * 0x9e3779b97f4a7c15ULL) + (static_cast<uint64_t>(dst) << 0x0000000000000018ULL)) + static_cast<uint64_t>(imm)));
                                                          uint64_t rot = ((x >> 0x0000000000000017ULL) | (x << 0x0000000000000029ULL));
                                                          return ((rot * 0xbf58476d1ce4e5b9ULL) ^ 0x5877cafe1337beefULL);
                                                      }
                                                      __attribute__((always_inline)) inline void advance_running_key(uint8_t op, uint8_t dst, int64_t imm) noexcept {
                                                      
                                                          running_key = advance_key_step(running_key, op, dst, imm);
                                                      }
                                                      static __attribute__((always_inline)) inline uint64_t anchor_key(uint32_t seed, uint64_t off, uint64_t addr_hash = 0) noexcept {
                                                      
                                                          return (key64_for_offset((seed ^ 0x5bd1e995U), static_cast<size_t>((off ^ 0x0000000013375877ULL))) ^ addr_hash);
                                                      }
                                                      __attribute__((always_inline)) inline void reanchor_running_key(uint64_t off, uint64_t addr_hash = 0) noexcept {
                                                      
                                                          running_key = anchor_key(init_seed, off, addr_hash);
                                                      }
                                                      static __attribute__((always_inline)) inline uint64_t poly_hash64(uint64_t x) noexcept {
                                                      
                                                          uint64_t x1 = ((x ^ (x >> 0x000000000000001eULL)) * 0xbf58476d1ce4e5b9ULL);
                                                          uint64_t x2 = ((x1 ^ (x1 >> 0x000000000000001bULL)) * 0x94d049bb133111ebULL);
                                                          return (x2 ^ (x2 >> 0x000000000000001fULL));
                                                      }
                                                      static __attribute__((always_inline)) inline uint64_t branch_invariant_poly_update(uint64_t key, uint64_t delta, uint64_t poly_const) noexcept {
                                                      
                                                          uint64_t c = (poly_const | 0x0000000000000001ULL);
                                                          return poly_hash64((key ^ (c * delta)));
                                                      }
                                                      __attribute__((always_inline)) inline void apply_poly_merge_update(uint64_t delta, uint64_t poly_const) noexcept {
                                                      
                                                          running_key = branch_invariant_poly_update(running_key, delta, poly_const);
                                                      }
                                                      __attribute__((always_inline)) inline uint64_t get_vkey() const noexcept {
                                                      
                                                          return running_key;
                                                      }
                                                      __attribute__((always_inline)) inline bool verify_canaries() const noexcept {
                                                      
                                                          if ((canary_head != CANARY_VAL) || (canary_tail != CANARY_VAL)) {
                                                          
                                                              return false;
                                                          }
                                                          size_t frame = ((sp >> 0x0000000000000004ULL) & 0x000000000000001fULL);
                                                          uint64_t expected = ((CANARY_VAL ^ (static_cast<uint64_t>(frame) * 0x517cc1b727220a95ULL)) ^ static_cast<uint64_t>(init_seed));
                                                          return (mid_canaries[frame] == expected);
                                                      }
                                                      __attribute__((always_inline)) inline uint64_t get_reg(uint8_t i) const noexcept {
                                                      
                                                          size_t idx = static_cast<size_t>(reg_phys_idx(i));
                                                          return ((gprs[idx] ^ slot_masks[idx]) ^ reg_mask);
                                                      }
                                                      __attribute__((always_inline)) inline void set_reg(uint8_t i, uint64_t v) noexcept {
                                                      
                                                          size_t idx = static_cast<size_t>(reg_phys_idx(i));
                                                          uint64_t new_m = ((slot_masks[idx] ^ running_key) * 0x9e3779b97f4a7c15ULL);
                                                          slot_masks[idx] = new_m;
                                                          gprs[idx] = (v ^ (new_m ^ reg_mask));
                                                      }
                                                      __attribute__((always_inline)) inline void evolve_slot_mask(uint8_t i, uint32_t k) noexcept {
                                                      
                                                          size_t idx = static_cast<size_t>(reg_phys_idx(i));
                                                          uint64_t cur_val = (gprs[idx] ^ (slot_masks[idx] ^ reg_mask));
                                                          uint64_t delta = ((static_cast<uint64_t>(k) * 0x6a09e667f3bcc908ULL) ^ (static_cast<uint64_t>(idx) * 0x517cc1b727220a95ULL));
                                                          slot_masks[idx] = ((slot_masks[idx] ^ delta) * 0xbf58476d1ce4e5b9ULL);
                                                          gprs[idx] = (cur_val ^ (slot_masks[idx] ^ reg_mask));
                                                      }
                                                      __attribute__((always_inline)) inline uint64_t get_vreg_lane(uint8_t i, size_t lane) const noexcept {
                                                      
                                                          return vregs[(i & 31)][(lane & 7)];
                                                      }
                                                      __attribute__((always_inline)) inline void set_vreg_lane(uint8_t i, size_t lane, uint64_t value) noexcept {
                                                      
                                                          vregs[(i & 31)][(lane & 7)] = value;
                                                      }
                                                      __attribute__((always_inline)) inline void set_vreg(uint8_t i, uint64_t lo, uint64_t hi) noexcept {
                                                      
                                                          vregs[(i & 31)][0] = lo;
                                                          vregs[(i & 31)][1] = hi;
                                                          for (size_t v = 0x0000000000000002ULL; v < 0x0000000000000008ULL; ++v) {
                                                          
                                                              vregs[(i & 31)][v] = 0x0000000000000000ULL;
                                                          }
                                                      }
                                                      __attribute__((always_inline)) inline uint64_t get_rax() const noexcept {
                                                      
                                                          return get_reg(REG_RAX);
                                                      }
                                                      __attribute__((always_inline)) inline void set_rax(uint64_t v) noexcept {
                                                      
                                                          set_reg(REG_RAX, v);
                                                      }
                                                      __attribute__((always_inline)) inline uint64_t get_rdi() const noexcept {
                                                      
                                                          return get_reg(REG_RDI);
                                                      }
                                                      __attribute__((always_inline)) inline void set_rdi(uint64_t v) noexcept {
                                                      
                                                          set_reg(REG_RDI, v);
                                                      }
                                                      __attribute__((always_inline)) inline uint64_t get_rsi() const noexcept {
                                                      
                                                          return get_reg(REG_RSI);
                                                      }
                                                      __attribute__((always_inline)) inline void set_rsi(uint64_t v) noexcept {
                                                      
                                                          set_reg(REG_RSI, v);
                                                      }
                                                      __attribute__((always_inline)) inline uint64_t get_fs_base() const noexcept {
                                                      
                                                          return get_reg(REG_VX25);
                                                      }
                                                      __attribute__((always_inline)) inline void set_fs_base(uint64_t v) noexcept {
                                                      
                                                          set_reg(REG_VX25, v);
                                                      }
                                                      __attribute__((always_inline)) inline uint64_t get_gs_base() const noexcept {
                                                      
                                                          return get_reg(REG_VX26);
                                                      }
                                                      __attribute__((always_inline)) inline void set_gs_base(uint64_t v) noexcept {
                                                      
                                                          set_reg(REG_VX26, v);
                                                      }
                                                      __attribute__((always_inline)) inline uint64_t rns_add(uint64_t a, uint64_t b) const noexcept {
                                                      
                                                          return asgard_rns::decode(asgard_rns::add(asgard_rns::encode(a), asgard_rns::encode(b)));
                                                      }
                                                      __attribute__((always_inline)) inline uint64_t rns_sub(uint64_t a, uint64_t b) const noexcept {
                                                      
                                                          return asgard_rns::decode(asgard_rns::sub(asgard_rns::encode(a), asgard_rns::encode(b)));
                                                      }
                                                      __attribute__((always_inline)) inline uint64_t rns_mul(uint64_t a, uint64_t b) const noexcept {
                                                      
                                                          return asgard_rns::decode(asgard_rns::mul(asgard_rns::encode(a), asgard_rns::encode(b)));
                                                      }
                                                      __attribute__((always_inline)) inline void evolve_mask(uint32_t k) noexcept {
                                                      
                                                          uint64_t delta = ((static_cast<uint64_t>(k) * 0x6a09e667f3bcc908ULL) ^ 0x0000000000001337ULL);
                                                          uint64_t old_mask = reg_mask;
                                                          uint64_t new_mask = ((reg_mask ^ delta) + 0x0000000000005877ULL);
                                                          for (size_t i = 0x0000000000000000ULL; i < 0x0000000000000020ULL; ++i) {
                                                          
                                                              gprs[i] = ((gprs[i] ^ old_mask) ^ new_mask);
                                                          }
                                                          reg_mask = new_mask;
                                                      }
                                                      __attribute__((always_inline)) inline void rotate_registers_epoch(uint32_t from_ep, uint32_t to_ep) noexcept {
                                                      
                                                          uint32_t tr = (((from_ep & 3) << 2) | (to_ep & 3));
                                                          switch (tr) {
                                                          
                                                            case 1: {
                                                            
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(11)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(11)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(13)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(13)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(8)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(8)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(2)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(2)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(3)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(3)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(10)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(10)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(15)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(15)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(5)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(5)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(7)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(7)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(1)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(1)]);
                                                                std::swap(gprs[reg_phys_idx(6)], gprs[reg_phys_idx(14)]);
                                                                std::swap(slot_masks[reg_phys_idx(6)], slot_masks[reg_phys_idx(14)]);
                                                                std::swap(gprs[reg_phys_idx(9)], gprs[reg_phys_idx(12)]);
                                                                std::swap(slot_masks[reg_phys_idx(9)], slot_masks[reg_phys_idx(12)]);
                                                                break;
                                                            }
                                                            case 2: {
                                                            
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(2)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(2)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(12)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(12)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(1)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(1)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(9)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(9)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(8)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(8)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(4)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(4)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(11)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(11)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(13)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(13)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(14)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(14)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(6)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(6)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(10)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(10)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(15)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(15)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(7)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(7)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(5)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(5)]);
                                                                break;
                                                            }
                                                            case 3: {
                                                            
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(13)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(13)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(12)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(12)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(2)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(2)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(14)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(14)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(11)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(11)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(7)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(7)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(1)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(1)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(6)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(6)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(10)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(10)]);
                                                                std::swap(gprs[reg_phys_idx(3)], gprs[reg_phys_idx(4)]);
                                                                std::swap(slot_masks[reg_phys_idx(3)], slot_masks[reg_phys_idx(4)]);
                                                                std::swap(gprs[reg_phys_idx(3)], gprs[reg_phys_idx(9)]);
                                                                std::swap(slot_masks[reg_phys_idx(3)], slot_masks[reg_phys_idx(9)]);
                                                                std::swap(gprs[reg_phys_idx(5)], gprs[reg_phys_idx(8)]);
                                                                std::swap(slot_masks[reg_phys_idx(5)], slot_masks[reg_phys_idx(8)]);
                                                                std::swap(gprs[reg_phys_idx(5)], gprs[reg_phys_idx(15)]);
                                                                std::swap(slot_masks[reg_phys_idx(5)], slot_masks[reg_phys_idx(15)]);
                                                                break;
                                                            }
                                                            case 4: {
                                                            
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(1)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(1)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(7)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(7)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(5)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(5)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(15)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(15)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(10)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(10)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(3)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(3)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(2)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(2)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(8)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(8)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(13)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(13)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(11)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(11)]);
                                                                std::swap(gprs[reg_phys_idx(6)], gprs[reg_phys_idx(14)]);
                                                                std::swap(slot_masks[reg_phys_idx(6)], slot_masks[reg_phys_idx(14)]);
                                                                std::swap(gprs[reg_phys_idx(9)], gprs[reg_phys_idx(12)]);
                                                                std::swap(slot_masks[reg_phys_idx(9)], slot_masks[reg_phys_idx(12)]);
                                                                break;
                                                            }
                                                            case 6: {
                                                            
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(9)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(9)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(1)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(1)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(5)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(5)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(7)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(7)]);
                                                                std::swap(gprs[reg_phys_idx(2)], gprs[reg_phys_idx(4)]);
                                                                std::swap(slot_masks[reg_phys_idx(2)], slot_masks[reg_phys_idx(4)]);
                                                                std::swap(gprs[reg_phys_idx(2)], gprs[reg_phys_idx(11)]);
                                                                std::swap(slot_masks[reg_phys_idx(2)], slot_masks[reg_phys_idx(11)]);
                                                                std::swap(gprs[reg_phys_idx(3)], gprs[reg_phys_idx(12)]);
                                                                std::swap(slot_masks[reg_phys_idx(3)], slot_masks[reg_phys_idx(12)]);
                                                                std::swap(gprs[reg_phys_idx(3)], gprs[reg_phys_idx(8)]);
                                                                std::swap(slot_masks[reg_phys_idx(3)], slot_masks[reg_phys_idx(8)]);
                                                                std::swap(gprs[reg_phys_idx(3)], gprs[reg_phys_idx(14)]);
                                                                std::swap(slot_masks[reg_phys_idx(3)], slot_masks[reg_phys_idx(14)]);
                                                                std::swap(gprs[reg_phys_idx(3)], gprs[reg_phys_idx(10)]);
                                                                std::swap(slot_masks[reg_phys_idx(3)], slot_masks[reg_phys_idx(10)]);
                                                                break;
                                                            }
                                                            case 7: {
                                                            
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(6)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(6)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(11)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(11)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(13)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(13)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(7)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(7)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(8)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(8)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(12)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(12)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(3)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(3)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(14)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(14)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(10)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(10)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(4)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(4)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(9)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(9)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(2)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(2)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(15)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(15)]);
                                                                break;
                                                            }
                                                            case 8: {
                                                            
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(5)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(5)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(7)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(7)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(15)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(15)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(10)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(10)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(6)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(6)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(14)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(14)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(13)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(13)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(11)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(11)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(4)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(4)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(8)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(8)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(9)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(9)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(1)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(1)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(12)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(12)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(2)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(2)]);
                                                                break;
                                                            }
                                                            case 9: {
                                                            
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(7)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(7)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(5)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(5)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(1)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(1)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(9)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(9)]);
                                                                std::swap(gprs[reg_phys_idx(2)], gprs[reg_phys_idx(11)]);
                                                                std::swap(slot_masks[reg_phys_idx(2)], slot_masks[reg_phys_idx(11)]);
                                                                std::swap(gprs[reg_phys_idx(2)], gprs[reg_phys_idx(4)]);
                                                                std::swap(slot_masks[reg_phys_idx(2)], slot_masks[reg_phys_idx(4)]);
                                                                std::swap(gprs[reg_phys_idx(3)], gprs[reg_phys_idx(10)]);
                                                                std::swap(slot_masks[reg_phys_idx(3)], slot_masks[reg_phys_idx(10)]);
                                                                std::swap(gprs[reg_phys_idx(3)], gprs[reg_phys_idx(14)]);
                                                                std::swap(slot_masks[reg_phys_idx(3)], slot_masks[reg_phys_idx(14)]);
                                                                std::swap(gprs[reg_phys_idx(3)], gprs[reg_phys_idx(8)]);
                                                                std::swap(slot_masks[reg_phys_idx(3)], slot_masks[reg_phys_idx(8)]);
                                                                std::swap(gprs[reg_phys_idx(3)], gprs[reg_phys_idx(12)]);
                                                                std::swap(slot_masks[reg_phys_idx(3)], slot_masks[reg_phys_idx(12)]);
                                                                break;
                                                            }
                                                            case 11: {
                                                            
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(8)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(8)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(3)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(3)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(4)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(4)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(15)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(15)]);
                                                                std::swap(gprs[reg_phys_idx(1)], gprs[reg_phys_idx(2)]);
                                                                std::swap(slot_masks[reg_phys_idx(1)], slot_masks[reg_phys_idx(2)]);
                                                                std::swap(gprs[reg_phys_idx(1)], gprs[reg_phys_idx(13)]);
                                                                std::swap(slot_masks[reg_phys_idx(1)], slot_masks[reg_phys_idx(13)]);
                                                                std::swap(gprs[reg_phys_idx(1)], gprs[reg_phys_idx(7)]);
                                                                std::swap(slot_masks[reg_phys_idx(1)], slot_masks[reg_phys_idx(7)]);
                                                                std::swap(gprs[reg_phys_idx(1)], gprs[reg_phys_idx(5)]);
                                                                std::swap(slot_masks[reg_phys_idx(1)], slot_masks[reg_phys_idx(5)]);
                                                                std::swap(gprs[reg_phys_idx(6)], gprs[reg_phys_idx(11)]);
                                                                std::swap(slot_masks[reg_phys_idx(6)], slot_masks[reg_phys_idx(11)]);
                                                                std::swap(gprs[reg_phys_idx(6)], gprs[reg_phys_idx(9)]);
                                                                std::swap(slot_masks[reg_phys_idx(6)], slot_masks[reg_phys_idx(9)]);
                                                                std::swap(gprs[reg_phys_idx(12)], gprs[reg_phys_idx(14)]);
                                                                std::swap(slot_masks[reg_phys_idx(12)], slot_masks[reg_phys_idx(14)]);
                                                                break;
                                                            }
                                                            case 12: {
                                                            
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(10)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(10)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(6)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(6)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(1)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(1)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(7)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(7)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(11)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(11)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(14)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(14)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(2)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(2)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(12)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(12)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(13)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(13)]);
                                                                std::swap(gprs[reg_phys_idx(3)], gprs[reg_phys_idx(9)]);
                                                                std::swap(slot_masks[reg_phys_idx(3)], slot_masks[reg_phys_idx(9)]);
                                                                std::swap(gprs[reg_phys_idx(3)], gprs[reg_phys_idx(4)]);
                                                                std::swap(slot_masks[reg_phys_idx(3)], slot_masks[reg_phys_idx(4)]);
                                                                std::swap(gprs[reg_phys_idx(5)], gprs[reg_phys_idx(15)]);
                                                                std::swap(slot_masks[reg_phys_idx(5)], slot_masks[reg_phys_idx(15)]);
                                                                std::swap(gprs[reg_phys_idx(5)], gprs[reg_phys_idx(8)]);
                                                                std::swap(slot_masks[reg_phys_idx(5)], slot_masks[reg_phys_idx(8)]);
                                                                break;
                                                            }
                                                            case 13: {
                                                            
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(15)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(15)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(2)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(2)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(9)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(9)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(4)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(4)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(10)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(10)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(14)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(14)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(3)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(3)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(12)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(12)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(8)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(8)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(7)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(7)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(13)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(13)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(11)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(11)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(6)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(6)]);
                                                                break;
                                                            }
                                                            case 14: {
                                                            
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(15)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(15)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(4)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(4)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(3)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(3)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(8)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(8)]);
                                                                std::swap(gprs[reg_phys_idx(1)], gprs[reg_phys_idx(5)]);
                                                                std::swap(slot_masks[reg_phys_idx(1)], slot_masks[reg_phys_idx(5)]);
                                                                std::swap(gprs[reg_phys_idx(1)], gprs[reg_phys_idx(7)]);
                                                                std::swap(slot_masks[reg_phys_idx(1)], slot_masks[reg_phys_idx(7)]);
                                                                std::swap(gprs[reg_phys_idx(1)], gprs[reg_phys_idx(13)]);
                                                                std::swap(slot_masks[reg_phys_idx(1)], slot_masks[reg_phys_idx(13)]);
                                                                std::swap(gprs[reg_phys_idx(1)], gprs[reg_phys_idx(2)]);
                                                                std::swap(slot_masks[reg_phys_idx(1)], slot_masks[reg_phys_idx(2)]);
                                                                std::swap(gprs[reg_phys_idx(6)], gprs[reg_phys_idx(9)]);
                                                                std::swap(slot_masks[reg_phys_idx(6)], slot_masks[reg_phys_idx(9)]);
                                                                std::swap(gprs[reg_phys_idx(6)], gprs[reg_phys_idx(11)]);
                                                                std::swap(slot_masks[reg_phys_idx(6)], slot_masks[reg_phys_idx(11)]);
                                                                std::swap(gprs[reg_phys_idx(12)], gprs[reg_phys_idx(14)]);
                                                                std::swap(slot_masks[reg_phys_idx(12)], slot_masks[reg_phys_idx(14)]);
                                                                break;
                                                            }
                                                            default: {
                                                            
                                                                break;
                                                            }
                                                          }
                                                      }
                                                      static inline constexpr size_t STACK_SIZE = 512;
                                                      static inline constexpr size_t STACK_STRIDE = 125;
                                                      static inline constexpr size_t STACK_OFFSET = 7;
                                                      __attribute__((always_inline)) inline size_t scramble_stack_idx(size_t index) const noexcept {
                                                      
                                                          return static_cast<size_t>((((index * STACK_STRIDE) + STACK_OFFSET) & (STACK_SIZE - 1)));
                                                      }
                                                      __attribute__((always_inline)) inline void push(uint64_t v) noexcept {
                                                      
                                                          if (!verify_canaries()) {
                                                          
                                                              reg_mask ^= poison_penalty;
                                                              trapped = true;
                                                          }
                                                          if (sp < STACK_SIZE) {
                                                          
                                                              size_t phys_idx = scramble_stack_idx(sp);
                                                              uint64_t enc_mask = ((static_cast<uint64_t>(sp) * 0x9e3779b97f4a7c15ULL) ^ 0xa5a5a5a55a5a5a5aULL);
                                                              stack[phys_idx] = (v ^ enc_mask);
                                                              sp += 1;
                                                          }
                                                      }
                                                      __attribute__((always_inline)) inline uint64_t pop() noexcept {
                                                      
                                                          if (!verify_canaries()) {
                                                          
                                                              reg_mask ^= poison_penalty;
                                                              trapped = true;
                                                          }
                                                          if (sp > 0) {
                                                          
                                                              sp -= 1;
                                                              size_t phys_idx = scramble_stack_idx(sp);
                                                              uint64_t enc_mask = ((static_cast<uint64_t>(sp) * 0x9e3779b97f4a7c15ULL) ^ 0xa5a5a5a55a5a5a5aULL);
                                                              uint64_t val = (stack[phys_idx] ^ enc_mask);
                                                              stack[phys_idx] = (0xdeadbeefcafe1337ULL ^ enc_mask);
                                                              return val;
                                                          }
                                                          return 0x0000000000000000ULL;
                                                      }
                                                      uint64_t trace_digest = 0x53b7d9f7a1b4283eULL;
                                                      uint64_t bridge_state[16];
                                                          inline void morph_math_to_flow(uint64_t target_digest = 0) noexcept {
#if defined(ASGARD_MULTI_VM_ENABLED)
        uint64_t dig = target_digest ? target_digest : trace_digest;
        uint64_t regs[16];
        for (int i = 0; i < 16; ++i) regs[i] = get_reg(i);
        in_place_morph_math_to_flow(regs, bridge_state, dig);
        trace_digest = bridge_rol64(dig, 13) ^ 0x5877CAFEULL;
#else
        (void)target_digest;
#endif
    }
                                                          inline void morph_flow_to_math(uint64_t target_digest = 0) noexcept {
#if defined(ASGARD_MULTI_VM_ENABLED)
        uint64_t dig = target_digest ? target_digest : (bridge_rol64(trace_digest, 51) ^ 0x5877CAFEULL);
        uint64_t regs[16];
        for (int i = 0; i < 16; ++i) regs[i] = get_reg(i);
        in_place_morph_flow_to_math(bridge_state, regs, dig);
        trace_digest = dig;
#else
        (void)target_digest;
#endif
    }
                                                      
                                };
                                
                                // Flag Evaluation and Condition Check Helpers
                                
                                __attribute__((always_inline)) inline static bool eval_condition(const VMContext& ctx, uint8_t cond) noexcept {
                                
                                    switch (cond) {
                                                     case 0: {
                                                                  return ctx.zf;
                                                     }
                                                     case 1: {
                                                                  return (!ctx.zf);
                                                     }
                                                     case 2: {
                                                                  return ctx.cf;
                                                     }
                                                     case 3: {
                                                                  return (!ctx.cf);
                                                     }
                                                     case 4: {
                                                                  return (ctx.cf || ctx.zf);
                                                     }
                                                     case 5: {
                                                                  return ((!ctx.cf) && (!ctx.zf));
                                                     }
                                                     case 6: {
                                                                  return ctx.sf;
                                                     }
                                                     case 7: {
                                                                  return (!ctx.sf);
                                                     }
                                                     case 8: {
                                                                  return (ctx.sf != ctx.of);
                                                     }
                                                     case 9: {
                                                                  return (ctx.sf == ctx.of);
                                                     }
                                                     case 10: {
                                                                   return (ctx.zf || (ctx.sf != ctx.of));
                                                     }
                                                     case 11: {
                                                                   return ((!ctx.zf) && (ctx.sf == ctx.of));
                                                     }
                                                     case 12: {
                                                                   return ctx.of;
                                                     }
                                                     case 13: {
                                                                   return (!ctx.of);
                                                     }
                                                     case 14: {
                                                                   return true;
                                                     }
                                                     default: {
                                                                   return true;
                                                     }
                                    }
                                }
                                
                                __attribute__((always_inline)) inline static void compute_sub_flags(VMContext& ctx, uint64_t a, uint64_t b, uint32_t bits) noexcept {
                                
                                    if ((bits == 0) || (bits >= 64)) {
                                    
                                        uint64_t res = (a - b);
                                        ctx.zf = (res == 0x0000000000000000ULL);
                                        ctx.sf = (static_cast<int64_t>(res) < 0LL);
                                        ctx.cf = (a < b);
                                        ctx.of = ((((a ^ b) & (a ^ res)) >> 0x000000000000003fULL) != 0x0000000000000000ULL);
                                    } else {
                                                uint64_t mask = ((0x0000000000000001ULL << bits) - 0x0000000000000001ULL);
                                                uint64_t sign_bit = (0x0000000000000001ULL << (bits - 1));
                                                uint64_t a_val = (a & mask);
                                                uint64_t b_val = (b & mask);
                                                uint64_t res = ((a_val - b_val) & mask);
                                                ctx.zf = (res == 0x0000000000000000ULL);
                                                ctx.sf = ((res & sign_bit) != 0x0000000000000000ULL);
                                                ctx.cf = (a_val < b_val);
                                                ctx.of = ((((a_val ^ b_val) & (a_val ^ res)) & sign_bit) != 0x0000000000000000ULL);
                                    }
                                }
                                
                                __attribute__((always_inline)) inline static void compute_add_flags(VMContext& ctx, uint64_t a, uint64_t b, uint32_t bits) noexcept {
                                
                                    if ((bits == 0) || (bits >= 64)) {
                                    
                                        uint64_t res = (a + b);
                                        ctx.zf = (res == 0x0000000000000000ULL);
                                        ctx.sf = (static_cast<int64_t>(res) < 0LL);
                                        ctx.cf = (res < a);
                                        ctx.of = ((((~((a ^ b))) & (a ^ res)) >> 0x000000000000003fULL) != 0x0000000000000000ULL);
                                    } else {
                                                uint64_t mask = ((0x0000000000000001ULL << bits) - 0x0000000000000001ULL);
                                                uint64_t sign_bit = (0x0000000000000001ULL << (bits - 1));
                                                uint64_t a_val = (a & mask);
                                                uint64_t b_val = (b & mask);
                                                uint64_t res = ((a_val + b_val) & mask);
                                                ctx.zf = (res == 0x0000000000000000ULL);
                                                ctx.sf = ((res & sign_bit) != 0x0000000000000000ULL);
                                                ctx.cf = (res < a_val);
                                                ctx.of = ((((~((a_val ^ b_val))) & (a_val ^ res)) & sign_bit) != 0x0000000000000000ULL);
                                    }
                                }
                                
                                static inline bool execute_threaded(VMContext& ctx, const uint64_t* bytecode, size_t count, uint32_t seed = asgard_wbox_derive_seed() /* seed = 0x723A9E2FU */, bool scrub_source = false) {
                                
                                    if (ctx.reg_mask == 0x0000000000000000ULL) {
                                    
                                        ctx.init(seed);
                                    }
                                    asgard_nanomites::install_nanomite_handlers(seed);
                                    uint64_t full_hash = 0xf9194a7a07dfecc2ULL;
                                    for (size_t i = 0x0000000000000000ULL; i < count; ++i) {
                                    
                                        full_hash = (((full_hash ^ bytecode[i]) * 0x6862a033f189e6e9ULL) + ((uint64_t)(i)));
                                    }
                                    uint64_t hash_diff = (full_hash ^ 0x46e6589e9c7b33f7ULL);
                                    ctx.running_key ^= hash_diff;
                                    ctx.reg_mask ^= (hash_diff * 0x00005877cafebeefULL);
                                    if (hash_diff != 0x0000000000000000ULL) {
                                    
                                        ctx.trapped = true;
                                        return false;
                                    }
                                    if (asgard_syscalls::sys_check_debugger_present()) {
                                    
                                        ctx.reg_mask ^= 0xcafebabe13375877ULL;
                                        ctx.trapped = true;
                                        return false;
                                    }
                                    uint64_t emu_penalty = asgard_anti_emulation::evaluate_emulation_differential();
                                    if (emu_penalty != 0x0000000000000000ULL) {
                                    
                                        ctx.reg_mask ^= emu_penalty;
                                    }
                                    uint64_t smc_penalty = asgard_smc::execute_introspective_smc_probe(((uint64_t)(seed)));
                                    if (smc_penalty != 0x0000000000000000ULL) {
                                    
                                        ctx.reg_mask ^= smc_penalty;
                                    }
                                    uint64_t mem_penalty = asgard_mem_integrity::evaluate_memory_integrity();
                                    if (mem_penalty != 0x0000000000000000ULL) {
                                    
                                        ctx.reg_mask ^= mem_penalty;
                                    }
                                    uint64_t stack_buf[256];
                                    uint64_t* heap_work_bc = ((count <= 0x0000000000000100ULL) ? nullptr : ((uint64_t*)(malloc((count * sizeof(uint64_t))))));
                                    uint64_t* work_bc = ((count <= 0x0000000000000100ULL) ? stack_buf : heap_work_bc);
                                    if (__builtin_expect((!work_bc), 0)) {
                                    
                                        ctx.trapped = true;
                                        return false;
                                    }
                                    for (size_t i = 0x0000000000000000ULL; i < count; ++i) {
                                    
                                        work_bc[i] = (0x5877cafe1337beefULL ^ (((uint64_t)(seed)) + ((uint64_t)(i))));
                                    }
                                    size_t vIP_idx = 0x0000000000000000ULL;
                                    static const uint8_t domain_salt[4] = { 0x00, 0xA0, 0x9E, 0x77 };
                                    static uintptr_t all_dispatch_domains[4][256];
    static bool dispatch_domains_ready = false;
    if (__builtin_expect(!dispatch_domains_ready, 0)) {
#if !defined(_MSC_VER) || defined(__clang__)
                                    static void* raw_domain0[256] = {
                                        &&H_DECOY_8,
                                        &&H_DECOY_5,
                                        &&H_DECOY_0,
                                        &&H_VEC_ZERO_UPPER,
                                        &&H_DECOY_15,
                                        &&H_DECOY_2,
                                        &&H_DECOY_15,
                                        &&H_DECOY_1,
                                        &&H_NEG_RR,
                                        &&H_ATOMIC_LOAD,
                                        &&H_DECOY_0,
                                        &&H_AND_RR,
                                        &&H_DECOY_15,
                                        &&H_EXIT,
                                        &&H_DECOY_5,
                                        &&H_PMOVMSKB,
                                        &&H_DECOY_7,
                                        &&H_DECOY_7,
                                        &&H_DECOY_4,
                                        &&H_DECOY_12,
                                        &&H_FCVTZS,
                                        &&H_SETCC,
                                        &&H_DECOY_12,
                                        &&H_DECOY_12,
                                        &&H_VEC_BINOP,
                                        &&H_DECOY_10,
                                        &&H_ROR_RR,
                                        &&H_DECOY_0,
                                        &&H_CLZ_RR,
                                        &&H_FUSED_SUB_XOR_RRI,
                                        &&H_DECOY_5,
                                        &&H_AND_RI,
                                        &&H_DECOY_6,
                                        &&H_DECOY_12,
                                        &&H_ADC_RR,
                                        &&H_MOV_VR,
                                        &&H_LOAD_8,
                                        &&H_XOR_RR,
                                        &&H_DECOY_5,
                                        &&H_DECOY_14,
                                        &&H_VEC_MOV,
                                        &&H_DECOY_12,
                                        &&H_LOAD_S32,
                                        &&H_DECOY_6,
                                        &&H_DECOY_9,
                                        &&H_DECOY_4,
                                        &&H_DECOY_15,
                                        &&H_STORE_16,
                                        &&H_CCMN_RR,
                                        &&H_VEC_IMM,
                                        &&H_DECOY_3,
                                        &&H_SUB_RR,
                                        &&H_MOV_RI,
                                        &&H_VMUL_VV,
                                        &&H_DECOY_0,
                                        &&H_VEC_STORE,
                                        &&H_DECOY_3,
                                        &&H_FUSED_SHL_ADD_RRI,
                                        &&H_LOAD_S8,
                                        &&H_POPCNT_RR,
                                        &&H_ROL_RR,
                                        &&H_SHR_RR,
                                        &&H_DIV_RR,
                                        &&H_DECOY_15,
                                        &&H_DECOY_0,
                                        &&H_DECOY_5,
                                        &&H_DECOY_5,
                                        &&H_FDIV_DD,
                                        &&H_DECOY_4,
                                        &&H_DECOY_7,
                                        &&H_IJMP_R,
                                        &&H_DECOY_14,
                                        &&H_ATOMIC_ADD,
                                        &&H_STORE_8,
                                        &&H_DECOY_10,
                                        &&H_DECOY_0,
                                        &&H_DECOY_7,
                                        &&H_DECOY_4,
                                        &&H_LOAD_16,
                                        &&H_DECOY_4,
                                        &&H_DECOY_11,
                                        &&H_VSUB_VV,
                                        &&H_IMUL_RI,
                                        &&H_CALL_EXTERN,
                                        &&H_DECOY_13,
                                        &&H_DECOY_6,
                                        &&H_FMUL_DD,
                                        &&H_ATOMIC_STORE,
                                        &&H_DECOY_9,
                                        &&H_CTZ_RR,
                                        &&H_ADD_RI,
                                        &&H_RBIT_RR,
                                        &&H_DECOY_12,
                                        &&H_FUSED_XOR_ADD_RRI,
                                        &&H_DECOY_3,
                                        &&H_LOAD_32,
                                        &&H_DECOY_12,
                                        &&H_DECOY_5,
                                        &&H_DECOY_10,
                                        &&H_CALL,
                                        &&H_GET_FLAGS_R,
                                        &&H_FADD_DD,
                                        &&H_DECOY_0,
                                        &&H_DECOY_12,
                                        &&H_DECOY_0,
                                        &&H_DECOY_9,
                                        &&H_DECOY_13,
                                        &&H_CCMP_RI,
                                        &&H_STORE_32,
                                        &&H_DECOY_15,
                                        &&H_DECOY_0,
                                        &&H_DECOY_6,
                                        &&H_FCSEL_VV,
                                        &&H_CCMN_RI,
                                        &&H_OR_RI,
                                        &&H_DECOY_11,
                                        &&H_DECOY_11,
                                        &&H_SCVTF,
                                        &&H_DECOY_9,
                                        &&H_JMP,
                                        &&H_MULH_RR,
                                        &&H_SHL_RR,
                                        &&H_DECOY_12,
                                        &&H_DECOY_14,
                                        &&H_FSUB_DD,
                                        &&H_STORE_64,
                                        &&H_SHR_RI,
                                        &&H_DECOY_7,
                                        &&H_DECOY_6,
                                        &&H_DECOY_8,
                                        &&H_DECOY_12,
                                        &&H_VEC_EXT,
                                        &&H_DECOY_2,
                                        &&H_FSQRT_D,
                                        &&H_MOV_HIGH,
                                        &&H_DECOY_2,
                                        &&H_POP_R,
                                        &&H_DECOY_12,
                                        &&H_ROL_RI,
                                        &&H_FUSED_MOV_ADD_RRI,
                                        &&H_LOAD_64,
                                        &&H_ROR_RI,
                                        &&H_RET,
                                        &&H_DECOY_15,
                                        &&H_DECOY_5,
                                        &&H_IMUL_RR,
                                        &&H_DECOY_2,
                                        &&H_DECOY_9,
                                        &&H_DECOY_0,
                                        &&H_DECOY_6,
                                        &&H_FCMP_DD,
                                        &&H_DECOY_11,
                                        &&H_DECOY_8,
                                        &&H_JCC,
                                        &&H_DECOY_2,
                                        &&H_DECOY_11,
                                        &&H_DECOY_14,
                                        &&H_UCVTF,
                                        &&H_BRIDGE_TO_FLOW,
                                        &&H_DECOY_7,
                                        &&H_FUSED_ADD_IMUL_RRI,
                                        &&H_FCVT,
                                        &&H_DECOY_2,
                                        &&H_DECOY_8,
                                        &&H_DECOY_9,
                                        &&H_DECOY_3,
                                        &&H_DECOY_1,
                                        &&H_DECOY_10,
                                        &&H_VEC_SPLAT,
                                        &&H_ATOMIC_SWP,
                                        &&H_DECOY_8,
                                        &&H_ICALL_R,
                                        &&H_DECOY_0,
                                        &&H_BRIDGE_TO_MATH,
                                        &&H_DECOY_14,
                                        &&H_DECOY_6,
                                        &&H_DECOY_9,
                                        &&H_DECOY_3,
                                        &&H_DECOY_9,
                                        &&H_FCVTZU,
                                        &&H_DECOY_12,
                                        &&H_CMOV,
                                        &&H_NOT_RR,
                                        &&H_FUSED_CMP_CMOV,
                                        &&H_DECOY_3,
                                        &&H_DECOY_0,
                                        &&H_DECOY_12,
                                        &&H_DECOY_15,
                                        &&H_DECOY_0,
                                        &&H_DECOY_12,
                                        &&H_DECOY_0,
                                        &&H_DECOY_1,
                                        &&H_DECOY_0,
                                        &&H_NOP,
                                        &&H_DECOY_13,
                                        &&H_DECOY_12,
                                        &&H_DECOY_0,
                                        &&H_ATOMIC_CAS,
                                        &&H_DECOY_14,
                                        &&H_DECOY_6,
                                        &&H_VADD_VV,
                                        &&H_SET_FLAGS_R,
                                        &&H_ADD_RR,
                                        &&H_DECOY_8,
                                        &&H_DECOY_15,
                                        &&H_XOR_RI,
                                        &&H_FENCE,
                                        &&H_RESOLVE_SYM,
                                        &&H_DECOY_6,
                                        &&H_DECOY_4,
                                        &&H_IMULH_RR,
                                        &&H_DECOY_8,
                                        &&H_SBB_RR,
                                        &&H_DECOY_12,
                                        &&H_SBB_RI,
                                        &&H_BSWAP_RR,
                                        &&H_MOV_RV,
                                        &&H_DECOY_5,
                                        &&H_OR_RR,
                                        &&H_DECOY_10,
                                        &&H_LOAD_S16,
                                        &&H_DECOY_15,
                                        &&H_DECOY_5,
                                        &&H_CCMP_RR,
                                        &&H_DECOY_13,
                                        &&H_DECOY_11,
                                        &&H_DECOY_8,
                                        &&H_SUB_RI,
                                        &&H_VXOR_VV,
                                        &&H_DECOY_9,
                                        &&H_MOV_RR,
                                        &&H_FUSED_ADD_XOR_RRI,
                                        &&H_CMP_RR,
                                        &&H_FUSED_AND_OR_RRI,
                                        &&H_CMP_RI,
                                        &&H_IDIV_RR,
                                        &&H_DECOY_9,
                                        &&H_VEC_CLEAR_UPPER,
                                        &&H_DECOY_13,
                                        &&H_DECOY_11,
                                        &&H_VEC_LOAD,
                                        &&H_SAR_RI,
                                        &&H_SHL_RI,
                                        &&H_SAR_RR,
                                        &&H_PUSH_R,
                                        &&H_DECOY_15,
                                        &&H_DECOY_3,
                                        &&H_DECOY_5,
                                        &&H_DECOY_0,
                                        &&H_DECOY_9,
                                        &&H_DECOY_4,
                                        &&H_DECOY_10,
                                        &&H_DECOY_0,
                                        &&H_ADC_RI,
                                        &&H_DECOY_11,
                                        &&H_DECOY_8
                                    };
                                    static void* raw_domain1[256] = {
                                        &&H_FUSED_ADD_IMUL_RRI_D1,
                                        &&H_FCVT_D1,
                                        &&H_DECOY_9,
                                        &&H_DECOY_15,
                                        &&H_DECOY_0,
                                        &&H_DECOY_10,
                                        &&H_DECOY_8,
                                        &&H_DECOY_1,
                                        &&H_VEC_SPLAT_D1,
                                        &&H_ATOMIC_SWP_D1,
                                        &&H_DECOY_15,
                                        &&H_ICALL_R_D1,
                                        &&H_DECOY_7,
                                        &&H_BRIDGE_TO_MATH_D1,
                                        &&H_DECOY_5,
                                        &&H_DECOY_13,
                                        &&H_DECOY_0,
                                        &&H_DECOY_10,
                                        &&H_DECOY_0,
                                        &&H_FCVTZU_D1,
                                        &&H_DECOY_3,
                                        &&H_CMOV_D1,
                                        &&H_NOT_RR_D1,
                                        &&H_FUSED_CMP_CMOV_D1,
                                        &&H_DECOY_10,
                                        &&H_DECOY_7,
                                        &&H_DECOY_3,
                                        &&H_DECOY_6,
                                        &&H_DECOY_7,
                                        &&H_DECOY_3,
                                        &&H_DECOY_7,
                                        &&H_DECOY_8,
                                        &&H_DECOY_13,
                                        &&H_DECOY_15,
                                        &&H_DECOY_3,
                                        &&H_VEC_EXT_D1,
                                        &&H_DECOY_9,
                                        &&H_FSQRT_D_D1,
                                        &&H_MOV_HIGH_D1,
                                        &&H_DECOY_9,
                                        &&H_POP_R_D1,
                                        &&H_DECOY_3,
                                        &&H_ROL_RI_D1,
                                        &&H_FUSED_MOV_ADD_RRI_D1,
                                        &&H_LOAD_64_D1,
                                        &&H_ROR_RI_D1,
                                        &&H_RET_D1,
                                        &&H_DECOY_6,
                                        &&H_DECOY_12,
                                        &&H_IMUL_RR_D1,
                                        &&H_DECOY_9,
                                        &&H_DECOY_0,
                                        &&H_DECOY_7,
                                        &&H_DECOY_13,
                                        &&H_FCMP_DD_D1,
                                        &&H_DECOY_2,
                                        &&H_DECOY_15,
                                        &&H_JCC_D1,
                                        &&H_DECOY_9,
                                        &&H_DECOY_2,
                                        &&H_DECOY_5,
                                        &&H_UCVTF_D1,
                                        &&H_BRIDGE_TO_FLOW_D1,
                                        &&H_DECOY_14,
                                        &&H_DECOY_4,
                                        &&H_DECOY_2,
                                        &&H_DECOY_15,
                                        &&H_SUB_RI_D1,
                                        &&H_VXOR_VV_D1,
                                        &&H_DECOY_0,
                                        &&H_MOV_RR_D1,
                                        &&H_FUSED_ADD_XOR_RRI_D1,
                                        &&H_CMP_RR_D1,
                                        &&H_FUSED_AND_OR_RRI_D1,
                                        &&H_CMP_RI_D1,
                                        &&H_IDIV_RR_D1,
                                        &&H_DECOY_0,
                                        &&H_VEC_CLEAR_UPPER_D1,
                                        &&H_DECOY_4,
                                        &&H_DECOY_2,
                                        &&H_VEC_LOAD_D1,
                                        &&H_SAR_RI_D1,
                                        &&H_SHL_RI_D1,
                                        &&H_SAR_RR_D1,
                                        &&H_PUSH_R_D1,
                                        &&H_DECOY_6,
                                        &&H_DECOY_10,
                                        &&H_DECOY_12,
                                        &&H_DECOY_7,
                                        &&H_DECOY_0,
                                        &&H_DECOY_11,
                                        &&H_DECOY_1,
                                        &&H_DECOY_7,
                                        &&H_ADC_RI_D1,
                                        &&H_DECOY_2,
                                        &&H_DECOY_15,
                                        &&H_DECOY_7,
                                        &&H_NOP_D1,
                                        &&H_DECOY_4,
                                        &&H_DECOY_3,
                                        &&H_DECOY_7,
                                        &&H_ATOMIC_CAS_D1,
                                        &&H_DECOY_5,
                                        &&H_DECOY_13,
                                        &&H_VADD_VV_D1,
                                        &&H_SET_FLAGS_R_D1,
                                        &&H_ADD_RR_D1,
                                        &&H_DECOY_15,
                                        &&H_DECOY_6,
                                        &&H_XOR_RI_D1,
                                        &&H_FENCE_D1,
                                        &&H_RESOLVE_SYM_D1,
                                        &&H_DECOY_13,
                                        &&H_DECOY_11,
                                        &&H_IMULH_RR_D1,
                                        &&H_DECOY_15,
                                        &&H_SBB_RR_D1,
                                        &&H_DECOY_3,
                                        &&H_SBB_RI_D1,
                                        &&H_BSWAP_RR_D1,
                                        &&H_MOV_RV_D1,
                                        &&H_DECOY_12,
                                        &&H_OR_RR_D1,
                                        &&H_DECOY_1,
                                        &&H_LOAD_S16_D1,
                                        &&H_DECOY_6,
                                        &&H_DECOY_12,
                                        &&H_CCMP_RR_D1,
                                        &&H_DECOY_13,
                                        &&H_DECOY_3,
                                        &&H_ADC_RR_D1,
                                        &&H_MOV_VR_D1,
                                        &&H_LOAD_8_D1,
                                        &&H_XOR_RR_D1,
                                        &&H_DECOY_12,
                                        &&H_DECOY_5,
                                        &&H_VEC_MOV_D1,
                                        &&H_DECOY_3,
                                        &&H_LOAD_S32_D1,
                                        &&H_DECOY_13,
                                        &&H_DECOY_0,
                                        &&H_DECOY_11,
                                        &&H_DECOY_6,
                                        &&H_STORE_16_D1,
                                        &&H_CCMN_RR_D1,
                                        &&H_VEC_IMM_D1,
                                        &&H_DECOY_10,
                                        &&H_SUB_RR_D1,
                                        &&H_MOV_RI_D1,
                                        &&H_VMUL_VV_D1,
                                        &&H_DECOY_7,
                                        &&H_VEC_STORE_D1,
                                        &&H_DECOY_10,
                                        &&H_FUSED_SHL_ADD_RRI_D1,
                                        &&H_LOAD_S8_D1,
                                        &&H_POPCNT_RR_D1,
                                        &&H_ROL_RR_D1,
                                        &&H_SHR_RR_D1,
                                        &&H_DIV_RR_D1,
                                        &&H_DECOY_6,
                                        &&H_DECOY_15,
                                        &&H_DECOY_12,
                                        &&H_DECOY_7,
                                        &&H_VEC_ZERO_UPPER_D1,
                                        &&H_DECOY_6,
                                        &&H_DECOY_9,
                                        &&H_DECOY_6,
                                        &&H_DECOY_8,
                                        &&H_NEG_RR_D1,
                                        &&H_ATOMIC_LOAD_D1,
                                        &&H_DECOY_7,
                                        &&H_AND_RR_D1,
                                        &&H_DECOY_6,
                                        &&H_EXIT_D1,
                                        &&H_DECOY_12,
                                        &&H_PMOVMSKB_D1,
                                        &&H_DECOY_14,
                                        &&H_DECOY_14,
                                        &&H_DECOY_11,
                                        &&H_DECOY_3,
                                        &&H_FCVTZS_D1,
                                        &&H_SETCC_D1,
                                        &&H_DECOY_3,
                                        &&H_DECOY_3,
                                        &&H_VEC_BINOP_D1,
                                        &&H_DECOY_1,
                                        &&H_ROR_RR_D1,
                                        &&H_DECOY_7,
                                        &&H_CLZ_RR_D1,
                                        &&H_FUSED_SUB_XOR_RRI_D1,
                                        &&H_DECOY_12,
                                        &&H_AND_RI_D1,
                                        &&H_DECOY_3,
                                        &&H_DECOY_12,
                                        &&H_DECOY_1,
                                        &&H_CALL_D1,
                                        &&H_GET_FLAGS_R_D1,
                                        &&H_FADD_DD_D1,
                                        &&H_DECOY_7,
                                        &&H_DECOY_3,
                                        &&H_DECOY_7,
                                        &&H_DECOY_0,
                                        &&H_DECOY_4,
                                        &&H_CCMP_RI_D1,
                                        &&H_STORE_32_D1,
                                        &&H_DECOY_6,
                                        &&H_DECOY_7,
                                        &&H_DECOY_13,
                                        &&H_FCSEL_VV_D1,
                                        &&H_CCMN_RI_D1,
                                        &&H_OR_RI_D1,
                                        &&H_DECOY_2,
                                        &&H_DECOY_2,
                                        &&H_SCVTF_D1,
                                        &&H_DECOY_0,
                                        &&H_JMP_D1,
                                        &&H_MULH_RR_D1,
                                        &&H_SHL_RR_D1,
                                        &&H_DECOY_3,
                                        &&H_DECOY_5,
                                        &&H_FSUB_DD_D1,
                                        &&H_STORE_64_D1,
                                        &&H_SHR_RI_D1,
                                        &&H_DECOY_14,
                                        &&H_DECOY_7,
                                        &&H_DECOY_12,
                                        &&H_DECOY_12,
                                        &&H_FDIV_DD_D1,
                                        &&H_DECOY_11,
                                        &&H_DECOY_14,
                                        &&H_IJMP_R_D1,
                                        &&H_DECOY_5,
                                        &&H_ATOMIC_ADD_D1,
                                        &&H_STORE_8_D1,
                                        &&H_DECOY_1,
                                        &&H_DECOY_7,
                                        &&H_DECOY_14,
                                        &&H_DECOY_11,
                                        &&H_LOAD_16_D1,
                                        &&H_DECOY_11,
                                        &&H_DECOY_2,
                                        &&H_VSUB_VV_D1,
                                        &&H_IMUL_RI_D1,
                                        &&H_CALL_EXTERN_D1,
                                        &&H_DECOY_4,
                                        &&H_DECOY_13,
                                        &&H_FMUL_DD_D1,
                                        &&H_ATOMIC_STORE_D1,
                                        &&H_DECOY_0,
                                        &&H_CTZ_RR_D1,
                                        &&H_ADD_RI_D1,
                                        &&H_RBIT_RR_D1,
                                        &&H_DECOY_3,
                                        &&H_FUSED_XOR_ADD_RRI_D1,
                                        &&H_DECOY_10,
                                        &&H_LOAD_32_D1
                                    };
                                    static void* raw_domain2[256] = {
                                        &&H_BRIDGE_TO_FLOW_D2,
                                        &&H_DECOY_11,
                                        &&H_DECOY_14,
                                        &&H_UCVTF_D2,
                                        &&H_DECOY_14,
                                        &&H_DECOY_7,
                                        &&H_DECOY_0,
                                        &&H_JCC_D2,
                                        &&H_FCMP_DD_D2,
                                        &&H_DECOY_15,
                                        &&H_DECOY_0,
                                        &&H_DECOY_6,
                                        &&H_DECOY_14,
                                        &&H_DECOY_5,
                                        &&H_DECOY_13,
                                        &&H_IMUL_RR_D2,
                                        &&H_RET_D2,
                                        &&H_DECOY_3,
                                        &&H_LOAD_64_D2,
                                        &&H_ROR_RI_D2,
                                        &&H_ROL_RI_D2,
                                        &&H_FUSED_MOV_ADD_RRI_D2,
                                        &&H_POP_R_D2,
                                        &&H_DECOY_4,
                                        &&H_MOV_HIGH_D2,
                                        &&H_DECOY_6,
                                        &&H_DECOY_2,
                                        &&H_FSQRT_D_D2,
                                        &&H_DECOY_8,
                                        &&H_VEC_EXT_D2,
                                        &&H_DECOY_14,
                                        &&H_DECOY_0,
                                        &&H_DECOY_4,
                                        &&H_DECOY_5,
                                        &&H_DECOY_0,
                                        &&H_DECOY_12,
                                        &&H_DECOY_8,
                                        &&H_DECOY_11,
                                        &&H_DECOY_11,
                                        &&H_DECOY_8,
                                        &&H_NOT_RR_D2,
                                        &&H_FUSED_CMP_CMOV_D2,
                                        &&H_DECOY_12,
                                        &&H_CMOV_D2,
                                        &&H_DECOY_5,
                                        &&H_FCVTZU_D2,
                                        &&H_DECOY_1,
                                        &&H_DECOY_11,
                                        &&H_DECOY_2,
                                        &&H_DECOY_10,
                                        &&H_DECOY_0,
                                        &&H_BRIDGE_TO_MATH_D2,
                                        &&H_DECOY_4,
                                        &&H_ICALL_R_D2,
                                        &&H_VEC_SPLAT_D2,
                                        &&H_ATOMIC_SWP_D2,
                                        &&H_DECOY_5,
                                        &&H_DECOY_14,
                                        &&H_DECOY_9,
                                        &&H_DECOY_3,
                                        &&H_DECOY_14,
                                        &&H_DECOY_4,
                                        &&H_FUSED_ADD_IMUL_RRI_D2,
                                        &&H_FCVT_D2,
                                        &&H_DECOY_9,
                                        &&H_CCMP_RR_D2,
                                        &&H_LOAD_S16_D2,
                                        &&H_DECOY_15,
                                        &&H_OR_RR_D2,
                                        &&H_DECOY_6,
                                        &&H_MOV_RV_D2,
                                        &&H_DECOY_13,
                                        &&H_SBB_RI_D2,
                                        &&H_BSWAP_RR_D2,
                                        &&H_SBB_RR_D2,
                                        &&H_DECOY_12,
                                        &&H_IMULH_RR_D2,
                                        &&H_DECOY_4,
                                        &&H_DECOY_14,
                                        &&H_DECOY_12,
                                        &&H_FENCE_D2,
                                        &&H_RESOLVE_SYM_D2,
                                        &&H_DECOY_15,
                                        &&H_XOR_RI_D2,
                                        &&H_ADD_RR_D2,
                                        &&H_DECOY_4,
                                        &&H_VADD_VV_D2,
                                        &&H_SET_FLAGS_R_D2,
                                        &&H_DECOY_2,
                                        &&H_DECOY_10,
                                        &&H_DECOY_0,
                                        &&H_ATOMIC_CAS_D2,
                                        &&H_DECOY_9,
                                        &&H_DECOY_8,
                                        &&H_DECOY_8,
                                        &&H_NOP_D2,
                                        &&H_DECOY_15,
                                        &&H_DECOY_12,
                                        &&H_DECOY_0,
                                        &&H_ADC_RI_D2,
                                        &&H_DECOY_0,
                                        &&H_DECOY_6,
                                        &&H_DECOY_8,
                                        &&H_DECOY_1,
                                        &&H_DECOY_7,
                                        &&H_DECOY_9,
                                        &&H_PUSH_R_D2,
                                        &&H_DECOY_15,
                                        &&H_SHL_RI_D2,
                                        &&H_SAR_RR_D2,
                                        &&H_VEC_LOAD_D2,
                                        &&H_SAR_RI_D2,
                                        &&H_DECOY_1,
                                        &&H_DECOY_15,
                                        &&H_DECOY_9,
                                        &&H_VEC_CLEAR_UPPER_D2,
                                        &&H_CMP_RI_D2,
                                        &&H_IDIV_RR_D2,
                                        &&H_CMP_RR_D2,
                                        &&H_FUSED_AND_OR_RRI_D2,
                                        &&H_MOV_RR_D2,
                                        &&H_FUSED_ADD_XOR_RRI_D2,
                                        &&H_VXOR_VV_D2,
                                        &&H_DECOY_9,
                                        &&H_DECOY_4,
                                        &&H_SUB_RI_D2,
                                        &&H_DECOY_5,
                                        &&H_DECOY_3,
                                        &&H_DECOY_9,
                                        &&H_AND_RI_D2,
                                        &&H_CLZ_RR_D2,
                                        &&H_FUSED_SUB_XOR_RRI_D2,
                                        &&H_ROR_RR_D2,
                                        &&H_DECOY_12,
                                        &&H_VEC_BINOP_D2,
                                        &&H_DECOY_2,
                                        &&H_DECOY_0,
                                        &&H_DECOY_0,
                                        &&H_FCVTZS_D2,
                                        &&H_SETCC_D2,
                                        &&H_DECOY_0,
                                        &&H_DECOY_8,
                                        &&H_DECOY_15,
                                        &&H_DECOY_15,
                                        &&H_DECOY_9,
                                        &&H_PMOVMSKB_D2,
                                        &&H_DECOY_15,
                                        &&H_EXIT_D2,
                                        &&H_DECOY_12,
                                        &&H_AND_RR_D2,
                                        &&H_NEG_RR_D2,
                                        &&H_ATOMIC_LOAD_D2,
                                        &&H_DECOY_3,
                                        &&H_DECOY_5,
                                        &&H_DECOY_15,
                                        &&H_DECOY_2,
                                        &&H_DECOY_12,
                                        &&H_VEC_ZERO_UPPER_D2,
                                        &&H_DECOY_0,
                                        &&H_DECOY_13,
                                        &&H_DIV_RR_D2,
                                        &&H_DECOY_3,
                                        &&H_ROL_RR_D2,
                                        &&H_SHR_RR_D2,
                                        &&H_LOAD_S8_D2,
                                        &&H_POPCNT_RR_D2,
                                        &&H_DECOY_11,
                                        &&H_FUSED_SHL_ADD_RRI_D2,
                                        &&H_DECOY_4,
                                        &&H_VEC_STORE_D2,
                                        &&H_MOV_RI_D2,
                                        &&H_VMUL_VV_D2,
                                        &&H_DECOY_15,
                                        &&H_SUB_RR_D2,
                                        &&H_CCMN_RR_D2,
                                        &&H_VEC_IMM_D2,
                                        &&H_DECOY_3,
                                        &&H_STORE_16_D2,
                                        &&H_DECOY_9,
                                        &&H_DECOY_4,
                                        &&H_LOAD_S32_D2,
                                        &&H_DECOY_2,
                                        &&H_VEC_MOV_D2,
                                        &&H_DECOY_4,
                                        &&H_DECOY_9,
                                        &&H_DECOY_2,
                                        &&H_LOAD_8_D2,
                                        &&H_XOR_RR_D2,
                                        &&H_ADC_RR_D2,
                                        &&H_MOV_VR_D2,
                                        &&H_DECOY_14,
                                        &&H_DECOY_4,
                                        &&H_DECOY_7,
                                        &&H_LOAD_32_D2,
                                        &&H_DECOY_12,
                                        &&H_FUSED_XOR_ADD_RRI_D2,
                                        &&H_ADD_RI_D2,
                                        &&H_RBIT_RR_D2,
                                        &&H_DECOY_1,
                                        &&H_CTZ_RR_D2,
                                        &&H_FMUL_DD_D2,
                                        &&H_ATOMIC_STORE_D2,
                                        &&H_DECOY_13,
                                        &&H_DECOY_6,
                                        &&H_IMUL_RI_D2,
                                        &&H_CALL_EXTERN_D2,
                                        &&H_DECOY_3,
                                        &&H_VSUB_VV_D2,
                                        &&H_LOAD_16_D2,
                                        &&H_DECOY_8,
                                        &&H_DECOY_7,
                                        &&H_DECOY_4,
                                        &&H_DECOY_6,
                                        &&H_DECOY_12,
                                        &&H_ATOMIC_ADD_D2,
                                        &&H_STORE_8_D2,
                                        &&H_IJMP_R_D2,
                                        &&H_DECOY_2,
                                        &&H_DECOY_4,
                                        &&H_DECOY_7,
                                        &&H_DECOY_1,
                                        &&H_FDIV_DD_D2,
                                        &&H_DECOY_8,
                                        &&H_DECOY_13,
                                        &&H_SHR_RI_D2,
                                        &&H_DECOY_11,
                                        &&H_FSUB_DD_D2,
                                        &&H_STORE_64_D2,
                                        &&H_DECOY_8,
                                        &&H_DECOY_10,
                                        &&H_MULH_RR_D2,
                                        &&H_SHL_RR_D2,
                                        &&H_DECOY_13,
                                        &&H_JMP_D2,
                                        &&H_DECOY_11,
                                        &&H_SCVTF_D2,
                                        &&H_OR_RI_D2,
                                        &&H_DECOY_7,
                                        &&H_FCSEL_VV_D2,
                                        &&H_CCMN_RI_D2,
                                        &&H_DECOY_4,
                                        &&H_DECOY_10,
                                        &&H_STORE_32_D2,
                                        &&H_DECOY_15,
                                        &&H_DECOY_9,
                                        &&H_CCMP_RI_D2,
                                        &&H_DECOY_8,
                                        &&H_DECOY_1,
                                        &&H_DECOY_4,
                                        &&H_DECOY_0,
                                        &&H_GET_FLAGS_R_D2,
                                        &&H_FADD_DD_D2,
                                        &&H_DECOY_6,
                                        &&H_CALL_D2,
                                        &&H_DECOY_4,
                                        &&H_DECOY_13
                                    };
                                    static void* raw_domain3[256] = {
                                        &&H_JMP_D1,
                                        &&H_DECOY_15,
                                        &&H_SCVTF_D1,
                                        &&H_DECOY_13,
                                        &&H_DECOY_3,
                                        &&H_OR_RI_D1,
                                        &&H_CCMN_RI_D1,
                                        &&H_FCSEL_VV_D1,
                                        &&H_DECOY_7,
                                        &&H_SHR_RI_D1,
                                        &&H_STORE_64_D1,
                                        &&H_FSUB_DD_D1,
                                        &&H_DECOY_6,
                                        &&H_DECOY_10,
                                        &&H_SHL_RR_D1,
                                        &&H_MULH_RR_D1,
                                        &&H_DECOY_12,
                                        &&H_DECOY_6,
                                        &&H_FADD_DD_D1,
                                        &&H_GET_FLAGS_R_D1,
                                        &&H_CALL_D1,
                                        &&H_DECOY_8,
                                        &&H_DECOY_9,
                                        &&H_DECOY_6,
                                        &&H_DECOY_6,
                                        &&H_DECOY_6,
                                        &&H_DECOY_11,
                                        &&H_STORE_32_D1,
                                        &&H_CCMP_RI_D1,
                                        &&H_DECOY_11,
                                        &&H_DECOY_13,
                                        &&H_DECOY_10,
                                        &&H_ATOMIC_STORE_D1,
                                        &&H_FMUL_DD_D1,
                                        &&H_DECOY_2,
                                        &&H_DECOY_15,
                                        &&H_CALL_EXTERN_D1,
                                        &&H_IMUL_RI_D1,
                                        &&H_VSUB_VV_D1,
                                        &&H_DECOY_5,
                                        &&H_LOAD_32_D1,
                                        &&H_DECOY_9,
                                        &&H_FUSED_XOR_ADD_RRI_D1,
                                        &&H_DECOY_14,
                                        &&H_RBIT_RR_D1,
                                        &&H_ADD_RI_D1,
                                        &&H_CTZ_RR_D1,
                                        &&H_DECOY_3,
                                        &&H_DECOY_14,
                                        &&H_IJMP_R_D1,
                                        &&H_DECOY_3,
                                        &&H_DECOY_6,
                                        &&H_FDIV_DD_D1,
                                        &&H_DECOY_3,
                                        &&H_DECOY_9,
                                        &&H_DECOY_10,
                                        &&H_DECOY_4,
                                        &&H_LOAD_16_D1,
                                        &&H_DECOY_0,
                                        &&H_DECOY_9,
                                        &&H_DECOY_8,
                                        &&H_DECOY_8,
                                        &&H_STORE_8_D1,
                                        &&H_ATOMIC_ADD_D1,
                                        &&H_VEC_STORE_D1,
                                        &&H_DECOY_6,
                                        &&H_VMUL_VV_D1,
                                        &&H_MOV_RI_D1,
                                        &&H_SUB_RR_D1,
                                        &&H_DECOY_1,
                                        &&H_VEC_IMM_D1,
                                        &&H_CCMN_RR_D1,
                                        &&H_DECOY_15,
                                        &&H_DIV_RR_D1,
                                        &&H_SHR_RR_D1,
                                        &&H_ROL_RR_D1,
                                        &&H_POPCNT_RR_D1,
                                        &&H_LOAD_S8_D1,
                                        &&H_FUSED_SHL_ADD_RRI_D1,
                                        &&H_DECOY_13,
                                        &&H_DECOY_14,
                                        &&H_DECOY_11,
                                        &&H_XOR_RR_D1,
                                        &&H_LOAD_8_D1,
                                        &&H_MOV_VR_D1,
                                        &&H_ADC_RR_D1,
                                        &&H_DECOY_0,
                                        &&H_DECOY_0,
                                        &&H_STORE_16_D1,
                                        &&H_DECOY_5,
                                        &&H_DECOY_0,
                                        &&H_DECOY_11,
                                        &&H_DECOY_14,
                                        &&H_LOAD_S32_D1,
                                        &&H_DECOY_0,
                                        &&H_VEC_MOV_D1,
                                        &&H_DECOY_12,
                                        &&H_DECOY_2,
                                        &&H_SETCC_D1,
                                        &&H_FCVTZS_D1,
                                        &&H_DECOY_4,
                                        &&H_DECOY_2,
                                        &&H_DECOY_11,
                                        &&H_DECOY_1,
                                        &&H_AND_RI_D1,
                                        &&H_DECOY_11,
                                        &&H_FUSED_SUB_XOR_RRI_D1,
                                        &&H_CLZ_RR_D1,
                                        &&H_DECOY_8,
                                        &&H_ROR_RR_D1,
                                        &&H_DECOY_14,
                                        &&H_VEC_BINOP_D1,
                                        &&H_DECOY_1,
                                        &&H_DECOY_5,
                                        &&H_DECOY_14,
                                        &&H_DECOY_1,
                                        &&H_VEC_ZERO_UPPER_D1,
                                        &&H_DECOY_14,
                                        &&H_DECOY_9,
                                        &&H_DECOY_2,
                                        &&H_PMOVMSKB_D1,
                                        &&H_DECOY_11,
                                        &&H_EXIT_D1,
                                        &&H_DECOY_1,
                                        &&H_AND_RR_D1,
                                        &&H_DECOY_14,
                                        &&H_ATOMIC_LOAD_D1,
                                        &&H_NEG_RR_D1,
                                        &&H_DECOY_5,
                                        &&H_DECOY_9,
                                        &&H_DECOY_11,
                                        &&H_PUSH_R_D1,
                                        &&H_SAR_RR_D1,
                                        &&H_SHL_RI_D1,
                                        &&H_SAR_RI_D1,
                                        &&H_VEC_LOAD_D1,
                                        &&H_DECOY_8,
                                        &&H_DECOY_1,
                                        &&H_ADC_RI_D1,
                                        &&H_DECOY_2,
                                        &&H_DECOY_2,
                                        &&H_DECOY_2,
                                        &&H_DECOY_13,
                                        &&H_DECOY_10,
                                        &&H_FUSED_ADD_XOR_RRI_D1,
                                        &&H_MOV_RR_D1,
                                        &&H_DECOY_5,
                                        &&H_VXOR_VV_D1,
                                        &&H_SUB_RI_D1,
                                        &&H_DECOY_6,
                                        &&H_DECOY_15,
                                        &&H_DECOY_7,
                                        &&H_DECOY_11,
                                        &&H_DECOY_3,
                                        &&H_VEC_CLEAR_UPPER_D1,
                                        &&H_DECOY_11,
                                        &&H_IDIV_RR_D1,
                                        &&H_CMP_RI_D1,
                                        &&H_FUSED_AND_OR_RRI_D1,
                                        &&H_CMP_RR_D1,
                                        &&H_BSWAP_RR_D1,
                                        &&H_SBB_RI_D1,
                                        &&H_DECOY_8,
                                        &&H_SBB_RR_D1,
                                        &&H_DECOY_0,
                                        &&H_IMULH_RR_D1,
                                        &&H_DECOY_8,
                                        &&H_DECOY_0,
                                        &&H_CCMP_RR_D1,
                                        &&H_DECOY_11,
                                        &&H_DECOY_11,
                                        &&H_LOAD_S16_D1,
                                        &&H_DECOY_2,
                                        &&H_OR_RR_D1,
                                        &&H_DECOY_9,
                                        &&H_MOV_RV_D1,
                                        &&H_DECOY_6,
                                        &&H_DECOY_4,
                                        &&H_ATOMIC_CAS_D1,
                                        &&H_DECOY_2,
                                        &&H_DECOY_4,
                                        &&H_DECOY_11,
                                        &&H_NOP_D1,
                                        &&H_DECOY_10,
                                        &&H_RESOLVE_SYM_D1,
                                        &&H_FENCE_D1,
                                        &&H_XOR_RI_D1,
                                        &&H_DECOY_1,
                                        &&H_DECOY_0,
                                        &&H_ADD_RR_D1,
                                        &&H_SET_FLAGS_R_D1,
                                        &&H_VADD_VV_D1,
                                        &&H_FUSED_CMP_CMOV_D1,
                                        &&H_NOT_RR_D1,
                                        &&H_CMOV_D1,
                                        &&H_DECOY_14,
                                        &&H_FCVTZU_D1,
                                        &&H_DECOY_7,
                                        &&H_DECOY_7,
                                        &&H_DECOY_3,
                                        &&H_DECOY_1,
                                        &&H_DECOY_6,
                                        &&H_DECOY_8,
                                        &&H_DECOY_2,
                                        &&H_DECOY_7,
                                        &&H_DECOY_10,
                                        &&H_DECOY_4,
                                        &&H_DECOY_13,
                                        &&H_DECOY_10,
                                        &&H_DECOY_7,
                                        &&H_DECOY_15,
                                        &&H_DECOY_11,
                                        &&H_DECOY_0,
                                        &&H_DECOY_0,
                                        &&H_FCVT_D1,
                                        &&H_FUSED_ADD_IMUL_RRI_D1,
                                        &&H_DECOY_6,
                                        &&H_DECOY_4,
                                        &&H_BRIDGE_TO_MATH_D1,
                                        &&H_DECOY_2,
                                        &&H_ICALL_R_D1,
                                        &&H_DECOY_6,
                                        &&H_ATOMIC_SWP_D1,
                                        &&H_VEC_SPLAT_D1,
                                        &&H_DECOY_11,
                                        &&H_FCMP_DD_D1,
                                        &&H_DECOY_2,
                                        &&H_DECOY_2,
                                        &&H_DECOY_1,
                                        &&H_DECOY_0,
                                        &&H_IMUL_RR_D1,
                                        &&H_DECOY_15,
                                        &&H_DECOY_7,
                                        &&H_BRIDGE_TO_FLOW_D1,
                                        &&H_UCVTF_D1,
                                        &&H_DECOY_0,
                                        &&H_DECOY_3,
                                        &&H_DECOY_0,
                                        &&H_JCC_D1,
                                        &&H_DECOY_2,
                                        &&H_DECOY_2,
                                        &&H_MOV_HIGH_D1,
                                        &&H_FSQRT_D_D1,
                                        &&H_DECOY_4,
                                        &&H_VEC_EXT_D1,
                                        &&H_DECOY_10,
                                        &&H_DECOY_12,
                                        &&H_DECOY_0,
                                        &&H_DECOY_15,
                                        &&H_RET_D1,
                                        &&H_ROR_RI_D1,
                                        &&H_LOAD_64_D1,
                                        &&H_FUSED_MOV_ADD_RRI_D1,
                                        &&H_ROL_RI_D1,
                                        &&H_DECOY_0,
                                        &&H_POP_R_D1
                                    };
                                    static void** raw_all_domains[4] = { raw_domain0, raw_domain1, raw_domain2, raw_domain3 };
                                            for (size_t d = 0; d < 4; ++d) {
            for (size_t o = 0; o < 256; ++o) {
                uintptr_t k_slot = ((uintptr_t)seed * 0x517CC1B727220A95ULL) ^ (((uintptr_t)d * 256ULL + (uintptr_t)o) * 0x6A09E667F3BCC908ULL);
                all_dispatch_domains[d][o] = (uintptr_t)raw_all_domains[d][o] ^ k_slot;
                *(reinterpret_cast<volatile uintptr_t*>(&raw_all_domains[d][o])) = k_slot ^ 0xDEADBEEF5A5A5A5AULL;
            }
        }
#else
        for (size_t d = 0; d < 4; ++d) {
            for (size_t o = 0; o < 256; ++o) {
                uintptr_t k_slot = ((uintptr_t)seed * 0x517CC1B727220A95ULL) ^ (((uintptr_t)d * 256ULL + (uintptr_t)o) * 0x6A09E667F3BCC908ULL);
                all_dispatch_domains[d][o] = ((uintptr_t)(d * 256 + o) + 0x1337) ^ k_slot;
            }
        }
#endif
        dispatch_domains_ready = true;
    }
                                    uint64_t g_handlers_hash = compute_handlers_hash(((const uintptr_t*)(all_dispatch_domains)), 4);
                                        uint64_t word = 0;
    uint64_t k_dyn = 0;
    uint8_t op = 0;
    uint8_t dst = 0;
    uint8_t src = 0;
    int64_t imm = 0;
    size_t next_canary_step = 47 + ((uint64_t)seed & 0x3FULL);

#if defined(_MSC_VER) && !defined(__clang__)
    #define DISPATCH_OPCODE() do { \
        goto DISPATCH_MSVC; \
    } while(0)
#else
    #define DISPATCH_OPCODE() do { \
        uint8_t domain_idx = (uint8_t)((k_dyn >> 32) % 4); \
        uint8_t permuted_slot = (uint8_t)(op ^ domain_salt[domain_idx]); \
        uintptr_t k_slot = ((uintptr_t)seed * 0x517CC1B727220A95ULL) ^ (((uintptr_t)domain_idx * 256ULL + (uintptr_t)permuted_slot) * 0x6A09E667F3BCC908ULL); \
        void* target = (void*)(all_dispatch_domains[domain_idx][permuted_slot] ^ k_slot); \
        goto *target; \
    } while(0)
#endif

    #define FETCH_NEXT() do { \
        if (__builtin_expect(vIP_idx >= count, 0)) goto EXIT_VM; \
        if (__builtin_expect(ctx.executed_instructions > (count * 10000ULL + 1000000ULL), 0)) { \
            ctx.trapped = true; \
            goto EXIT_VM; \
        } \
        uint64_t k_pos = key64_for_offset(seed, vIP_idx); \
        k_dyn = k_pos ^ ctx.running_key; \
        if (__builtin_expect(ctx.executed_instructions >= next_canary_step, 0)) { \
            if (__builtin_expect(!ctx.verify_canaries(), 0)) { \
                ctx.reg_mask ^= (0xCAFEBABE13375877ULL ^ (k_dyn * 0x9E3779B97F4A7C15ULL)) | 1ULL; \
            } \
            next_canary_step = ctx.executed_instructions + 47 + ((k_dyn >> 21) & 0x7FULL); \
        } \
        work_bc[vIP_idx] = bytecode[vIP_idx]; \
        word = work_bc[vIP_idx] ^ k_dyn; \
        SCRUB_WORD(&work_bc[vIP_idx], (k_dyn * 0x6A09E667F3BCC908ULL) ^ 0x5877CAFE1337BEEFULL); \
        vIP_idx++; \
        op = (uint8_t)(((word + 0xFFULL) - (word | 0xFFULL))); \
        dst = (uint8_t)((((word >> 8) + 0x1FULL) - ((word >> 8) | 0x1FULL))); \
        src = (uint8_t)((((word >> 13) + 0x1FULL) - ((word >> 13) | 0x1FULL))); \
        imm = (int64_t)((int32_t)((((word >> 18) + 0xFFFFFFFFULL) - ((word >> 18) | 0xFFFFFFFFULL)))); \
        ctx.evolve_mask((uint32_t)k_dyn); \
        ctx.evolve_slot_mask(dst, (uint32_t)k_dyn); \
        ctx.advance_running_key(op, dst, imm); \
        DISPATCH_OPCODE(); \
    } while(0)
                                    ctx.reanchor_running_key(0x0000000000000000ULL);
                                    #if defined(_MSC_VER) && !defined(__clang__)
    goto START_VM_MSVC;
    DISPATCH_MSVC: {
        uint8_t d_idx = (uint8_t)((k_dyn >> 32) % 4);
        uint8_t permuted_slot = (uint8_t)(op ^ domain_salt[d_idx]);
        switch ((uint32_t)d_idx * 256U + (uint32_t)permuted_slot) {
        case (0 * 256 + 0): goto H_DECOY_8;
        case (0 * 256 + 1): goto H_DECOY_5;
        case (0 * 256 + 2): goto H_DECOY_0;
        case (0 * 256 + 3): goto H_VEC_ZERO_UPPER;
        case (0 * 256 + 4): goto H_DECOY_15;
        case (0 * 256 + 5): goto H_DECOY_2;
        case (0 * 256 + 6): goto H_DECOY_15;
        case (0 * 256 + 7): goto H_DECOY_1;
        case (0 * 256 + 8): goto H_NEG_RR;
        case (0 * 256 + 9): goto H_ATOMIC_LOAD;
        case (0 * 256 + 10): goto H_DECOY_0;
        case (0 * 256 + 11): goto H_AND_RR;
        case (0 * 256 + 12): goto H_DECOY_15;
        case (0 * 256 + 13): goto H_EXIT;
        case (0 * 256 + 14): goto H_DECOY_5;
        case (0 * 256 + 15): goto H_PMOVMSKB;
        case (0 * 256 + 16): goto H_DECOY_7;
        case (0 * 256 + 17): goto H_DECOY_7;
        case (0 * 256 + 18): goto H_DECOY_4;
        case (0 * 256 + 19): goto H_DECOY_12;
        case (0 * 256 + 20): goto H_FCVTZS;
        case (0 * 256 + 21): goto H_SETCC;
        case (0 * 256 + 22): goto H_DECOY_12;
        case (0 * 256 + 23): goto H_DECOY_12;
        case (0 * 256 + 24): goto H_VEC_BINOP;
        case (0 * 256 + 25): goto H_DECOY_10;
        case (0 * 256 + 26): goto H_ROR_RR;
        case (0 * 256 + 27): goto H_DECOY_0;
        case (0 * 256 + 28): goto H_CLZ_RR;
        case (0 * 256 + 29): goto H_FUSED_SUB_XOR_RRI;
        case (0 * 256 + 30): goto H_DECOY_5;
        case (0 * 256 + 31): goto H_AND_RI;
        case (0 * 256 + 32): goto H_DECOY_6;
        case (0 * 256 + 33): goto H_DECOY_12;
        case (0 * 256 + 34): goto H_ADC_RR;
        case (0 * 256 + 35): goto H_MOV_VR;
        case (0 * 256 + 36): goto H_LOAD_8;
        case (0 * 256 + 37): goto H_XOR_RR;
        case (0 * 256 + 38): goto H_DECOY_5;
        case (0 * 256 + 39): goto H_DECOY_14;
        case (0 * 256 + 40): goto H_VEC_MOV;
        case (0 * 256 + 41): goto H_DECOY_12;
        case (0 * 256 + 42): goto H_LOAD_S32;
        case (0 * 256 + 43): goto H_DECOY_6;
        case (0 * 256 + 44): goto H_DECOY_9;
        case (0 * 256 + 45): goto H_DECOY_4;
        case (0 * 256 + 46): goto H_DECOY_15;
        case (0 * 256 + 47): goto H_STORE_16;
        case (0 * 256 + 48): goto H_CCMN_RR;
        case (0 * 256 + 49): goto H_VEC_IMM;
        case (0 * 256 + 50): goto H_DECOY_3;
        case (0 * 256 + 51): goto H_SUB_RR;
        case (0 * 256 + 52): goto H_MOV_RI;
        case (0 * 256 + 53): goto H_VMUL_VV;
        case (0 * 256 + 54): goto H_DECOY_0;
        case (0 * 256 + 55): goto H_VEC_STORE;
        case (0 * 256 + 56): goto H_DECOY_3;
        case (0 * 256 + 57): goto H_FUSED_SHL_ADD_RRI;
        case (0 * 256 + 58): goto H_LOAD_S8;
        case (0 * 256 + 59): goto H_POPCNT_RR;
        case (0 * 256 + 60): goto H_ROL_RR;
        case (0 * 256 + 61): goto H_SHR_RR;
        case (0 * 256 + 62): goto H_DIV_RR;
        case (0 * 256 + 63): goto H_DECOY_15;
        case (0 * 256 + 64): goto H_DECOY_0;
        case (0 * 256 + 65): goto H_DECOY_5;
        case (0 * 256 + 66): goto H_DECOY_5;
        case (0 * 256 + 67): goto H_FDIV_DD;
        case (0 * 256 + 68): goto H_DECOY_4;
        case (0 * 256 + 69): goto H_DECOY_7;
        case (0 * 256 + 70): goto H_IJMP_R;
        case (0 * 256 + 71): goto H_DECOY_14;
        case (0 * 256 + 72): goto H_ATOMIC_ADD;
        case (0 * 256 + 73): goto H_STORE_8;
        case (0 * 256 + 74): goto H_DECOY_10;
        case (0 * 256 + 75): goto H_DECOY_0;
        case (0 * 256 + 76): goto H_DECOY_7;
        case (0 * 256 + 77): goto H_DECOY_4;
        case (0 * 256 + 78): goto H_LOAD_16;
        case (0 * 256 + 79): goto H_DECOY_4;
        case (0 * 256 + 80): goto H_DECOY_11;
        case (0 * 256 + 81): goto H_VSUB_VV;
        case (0 * 256 + 82): goto H_IMUL_RI;
        case (0 * 256 + 83): goto H_CALL_EXTERN;
        case (0 * 256 + 84): goto H_DECOY_13;
        case (0 * 256 + 85): goto H_DECOY_6;
        case (0 * 256 + 86): goto H_FMUL_DD;
        case (0 * 256 + 87): goto H_ATOMIC_STORE;
        case (0 * 256 + 88): goto H_DECOY_9;
        case (0 * 256 + 89): goto H_CTZ_RR;
        case (0 * 256 + 90): goto H_ADD_RI;
        case (0 * 256 + 91): goto H_RBIT_RR;
        case (0 * 256 + 92): goto H_DECOY_12;
        case (0 * 256 + 93): goto H_FUSED_XOR_ADD_RRI;
        case (0 * 256 + 94): goto H_DECOY_3;
        case (0 * 256 + 95): goto H_LOAD_32;
        case (0 * 256 + 96): goto H_DECOY_12;
        case (0 * 256 + 97): goto H_DECOY_5;
        case (0 * 256 + 98): goto H_DECOY_10;
        case (0 * 256 + 99): goto H_CALL;
        case (0 * 256 + 100): goto H_GET_FLAGS_R;
        case (0 * 256 + 101): goto H_FADD_DD;
        case (0 * 256 + 102): goto H_DECOY_0;
        case (0 * 256 + 103): goto H_DECOY_12;
        case (0 * 256 + 104): goto H_DECOY_0;
        case (0 * 256 + 105): goto H_DECOY_9;
        case (0 * 256 + 106): goto H_DECOY_13;
        case (0 * 256 + 107): goto H_CCMP_RI;
        case (0 * 256 + 108): goto H_STORE_32;
        case (0 * 256 + 109): goto H_DECOY_15;
        case (0 * 256 + 110): goto H_DECOY_0;
        case (0 * 256 + 111): goto H_DECOY_6;
        case (0 * 256 + 112): goto H_FCSEL_VV;
        case (0 * 256 + 113): goto H_CCMN_RI;
        case (0 * 256 + 114): goto H_OR_RI;
        case (0 * 256 + 115): goto H_DECOY_11;
        case (0 * 256 + 116): goto H_DECOY_11;
        case (0 * 256 + 117): goto H_SCVTF;
        case (0 * 256 + 118): goto H_DECOY_9;
        case (0 * 256 + 119): goto H_JMP;
        case (0 * 256 + 120): goto H_MULH_RR;
        case (0 * 256 + 121): goto H_SHL_RR;
        case (0 * 256 + 122): goto H_DECOY_12;
        case (0 * 256 + 123): goto H_DECOY_14;
        case (0 * 256 + 124): goto H_FSUB_DD;
        case (0 * 256 + 125): goto H_STORE_64;
        case (0 * 256 + 126): goto H_SHR_RI;
        case (0 * 256 + 127): goto H_DECOY_7;
        case (0 * 256 + 128): goto H_DECOY_6;
        case (0 * 256 + 129): goto H_DECOY_8;
        case (0 * 256 + 130): goto H_DECOY_12;
        case (0 * 256 + 131): goto H_VEC_EXT;
        case (0 * 256 + 132): goto H_DECOY_2;
        case (0 * 256 + 133): goto H_FSQRT_D;
        case (0 * 256 + 134): goto H_MOV_HIGH;
        case (0 * 256 + 135): goto H_DECOY_2;
        case (0 * 256 + 136): goto H_POP_R;
        case (0 * 256 + 137): goto H_DECOY_12;
        case (0 * 256 + 138): goto H_ROL_RI;
        case (0 * 256 + 139): goto H_FUSED_MOV_ADD_RRI;
        case (0 * 256 + 140): goto H_LOAD_64;
        case (0 * 256 + 141): goto H_ROR_RI;
        case (0 * 256 + 142): goto H_RET;
        case (0 * 256 + 143): goto H_DECOY_15;
        case (0 * 256 + 144): goto H_DECOY_5;
        case (0 * 256 + 145): goto H_IMUL_RR;
        case (0 * 256 + 146): goto H_DECOY_2;
        case (0 * 256 + 147): goto H_DECOY_9;
        case (0 * 256 + 148): goto H_DECOY_0;
        case (0 * 256 + 149): goto H_DECOY_6;
        case (0 * 256 + 150): goto H_FCMP_DD;
        case (0 * 256 + 151): goto H_DECOY_11;
        case (0 * 256 + 152): goto H_DECOY_8;
        case (0 * 256 + 153): goto H_JCC;
        case (0 * 256 + 154): goto H_DECOY_2;
        case (0 * 256 + 155): goto H_DECOY_11;
        case (0 * 256 + 156): goto H_DECOY_14;
        case (0 * 256 + 157): goto H_UCVTF;
        case (0 * 256 + 158): goto H_BRIDGE_TO_FLOW;
        case (0 * 256 + 159): goto H_DECOY_7;
        case (0 * 256 + 160): goto H_FUSED_ADD_IMUL_RRI;
        case (0 * 256 + 161): goto H_FCVT;
        case (0 * 256 + 162): goto H_DECOY_2;
        case (0 * 256 + 163): goto H_DECOY_8;
        case (0 * 256 + 164): goto H_DECOY_9;
        case (0 * 256 + 165): goto H_DECOY_3;
        case (0 * 256 + 166): goto H_DECOY_1;
        case (0 * 256 + 167): goto H_DECOY_10;
        case (0 * 256 + 168): goto H_VEC_SPLAT;
        case (0 * 256 + 169): goto H_ATOMIC_SWP;
        case (0 * 256 + 170): goto H_DECOY_8;
        case (0 * 256 + 171): goto H_ICALL_R;
        case (0 * 256 + 172): goto H_DECOY_0;
        case (0 * 256 + 173): goto H_BRIDGE_TO_MATH;
        case (0 * 256 + 174): goto H_DECOY_14;
        case (0 * 256 + 175): goto H_DECOY_6;
        case (0 * 256 + 176): goto H_DECOY_9;
        case (0 * 256 + 177): goto H_DECOY_3;
        case (0 * 256 + 178): goto H_DECOY_9;
        case (0 * 256 + 179): goto H_FCVTZU;
        case (0 * 256 + 180): goto H_DECOY_12;
        case (0 * 256 + 181): goto H_CMOV;
        case (0 * 256 + 182): goto H_NOT_RR;
        case (0 * 256 + 183): goto H_FUSED_CMP_CMOV;
        case (0 * 256 + 184): goto H_DECOY_3;
        case (0 * 256 + 185): goto H_DECOY_0;
        case (0 * 256 + 186): goto H_DECOY_12;
        case (0 * 256 + 187): goto H_DECOY_15;
        case (0 * 256 + 188): goto H_DECOY_0;
        case (0 * 256 + 189): goto H_DECOY_12;
        case (0 * 256 + 190): goto H_DECOY_0;
        case (0 * 256 + 191): goto H_DECOY_1;
        case (0 * 256 + 192): goto H_DECOY_0;
        case (0 * 256 + 193): goto H_NOP;
        case (0 * 256 + 194): goto H_DECOY_13;
        case (0 * 256 + 195): goto H_DECOY_12;
        case (0 * 256 + 196): goto H_DECOY_0;
        case (0 * 256 + 197): goto H_ATOMIC_CAS;
        case (0 * 256 + 198): goto H_DECOY_14;
        case (0 * 256 + 199): goto H_DECOY_6;
        case (0 * 256 + 200): goto H_VADD_VV;
        case (0 * 256 + 201): goto H_SET_FLAGS_R;
        case (0 * 256 + 202): goto H_ADD_RR;
        case (0 * 256 + 203): goto H_DECOY_8;
        case (0 * 256 + 204): goto H_DECOY_15;
        case (0 * 256 + 205): goto H_XOR_RI;
        case (0 * 256 + 206): goto H_FENCE;
        case (0 * 256 + 207): goto H_RESOLVE_SYM;
        case (0 * 256 + 208): goto H_DECOY_6;
        case (0 * 256 + 209): goto H_DECOY_4;
        case (0 * 256 + 210): goto H_IMULH_RR;
        case (0 * 256 + 211): goto H_DECOY_8;
        case (0 * 256 + 212): goto H_SBB_RR;
        case (0 * 256 + 213): goto H_DECOY_12;
        case (0 * 256 + 214): goto H_SBB_RI;
        case (0 * 256 + 215): goto H_BSWAP_RR;
        case (0 * 256 + 216): goto H_MOV_RV;
        case (0 * 256 + 217): goto H_DECOY_5;
        case (0 * 256 + 218): goto H_OR_RR;
        case (0 * 256 + 219): goto H_DECOY_10;
        case (0 * 256 + 220): goto H_LOAD_S16;
        case (0 * 256 + 221): goto H_DECOY_15;
        case (0 * 256 + 222): goto H_DECOY_5;
        case (0 * 256 + 223): goto H_CCMP_RR;
        case (0 * 256 + 224): goto H_DECOY_13;
        case (0 * 256 + 225): goto H_DECOY_11;
        case (0 * 256 + 226): goto H_DECOY_8;
        case (0 * 256 + 227): goto H_SUB_RI;
        case (0 * 256 + 228): goto H_VXOR_VV;
        case (0 * 256 + 229): goto H_DECOY_9;
        case (0 * 256 + 230): goto H_MOV_RR;
        case (0 * 256 + 231): goto H_FUSED_ADD_XOR_RRI;
        case (0 * 256 + 232): goto H_CMP_RR;
        case (0 * 256 + 233): goto H_FUSED_AND_OR_RRI;
        case (0 * 256 + 234): goto H_CMP_RI;
        case (0 * 256 + 235): goto H_IDIV_RR;
        case (0 * 256 + 236): goto H_DECOY_9;
        case (0 * 256 + 237): goto H_VEC_CLEAR_UPPER;
        case (0 * 256 + 238): goto H_DECOY_13;
        case (0 * 256 + 239): goto H_DECOY_11;
        case (0 * 256 + 240): goto H_VEC_LOAD;
        case (0 * 256 + 241): goto H_SAR_RI;
        case (0 * 256 + 242): goto H_SHL_RI;
        case (0 * 256 + 243): goto H_SAR_RR;
        case (0 * 256 + 244): goto H_PUSH_R;
        case (0 * 256 + 245): goto H_DECOY_15;
        case (0 * 256 + 246): goto H_DECOY_3;
        case (0 * 256 + 247): goto H_DECOY_5;
        case (0 * 256 + 248): goto H_DECOY_0;
        case (0 * 256 + 249): goto H_DECOY_9;
        case (0 * 256 + 250): goto H_DECOY_4;
        case (0 * 256 + 251): goto H_DECOY_10;
        case (0 * 256 + 252): goto H_DECOY_0;
        case (0 * 256 + 253): goto H_ADC_RI;
        case (0 * 256 + 254): goto H_DECOY_11;
        case (0 * 256 + 255): goto H_DECOY_8;
        case (1 * 256 + 0): goto H_FUSED_ADD_IMUL_RRI_D1;
        case (1 * 256 + 1): goto H_FCVT_D1;
        case (1 * 256 + 2): goto H_DECOY_9;
        case (1 * 256 + 3): goto H_DECOY_15;
        case (1 * 256 + 4): goto H_DECOY_0;
        case (1 * 256 + 5): goto H_DECOY_10;
        case (1 * 256 + 6): goto H_DECOY_8;
        case (1 * 256 + 7): goto H_DECOY_1;
        case (1 * 256 + 8): goto H_VEC_SPLAT_D1;
        case (1 * 256 + 9): goto H_ATOMIC_SWP_D1;
        case (1 * 256 + 10): goto H_DECOY_15;
        case (1 * 256 + 11): goto H_ICALL_R_D1;
        case (1 * 256 + 12): goto H_DECOY_7;
        case (1 * 256 + 13): goto H_BRIDGE_TO_MATH_D1;
        case (1 * 256 + 14): goto H_DECOY_5;
        case (1 * 256 + 15): goto H_DECOY_13;
        case (1 * 256 + 16): goto H_DECOY_0;
        case (1 * 256 + 17): goto H_DECOY_10;
        case (1 * 256 + 18): goto H_DECOY_0;
        case (1 * 256 + 19): goto H_FCVTZU_D1;
        case (1 * 256 + 20): goto H_DECOY_3;
        case (1 * 256 + 21): goto H_CMOV_D1;
        case (1 * 256 + 22): goto H_NOT_RR_D1;
        case (1 * 256 + 23): goto H_FUSED_CMP_CMOV_D1;
        case (1 * 256 + 24): goto H_DECOY_10;
        case (1 * 256 + 25): goto H_DECOY_7;
        case (1 * 256 + 26): goto H_DECOY_3;
        case (1 * 256 + 27): goto H_DECOY_6;
        case (1 * 256 + 28): goto H_DECOY_7;
        case (1 * 256 + 29): goto H_DECOY_3;
        case (1 * 256 + 30): goto H_DECOY_7;
        case (1 * 256 + 31): goto H_DECOY_8;
        case (1 * 256 + 32): goto H_DECOY_13;
        case (1 * 256 + 33): goto H_DECOY_15;
        case (1 * 256 + 34): goto H_DECOY_3;
        case (1 * 256 + 35): goto H_VEC_EXT_D1;
        case (1 * 256 + 36): goto H_DECOY_9;
        case (1 * 256 + 37): goto H_FSQRT_D_D1;
        case (1 * 256 + 38): goto H_MOV_HIGH_D1;
        case (1 * 256 + 39): goto H_DECOY_9;
        case (1 * 256 + 40): goto H_POP_R_D1;
        case (1 * 256 + 41): goto H_DECOY_3;
        case (1 * 256 + 42): goto H_ROL_RI_D1;
        case (1 * 256 + 43): goto H_FUSED_MOV_ADD_RRI_D1;
        case (1 * 256 + 44): goto H_LOAD_64_D1;
        case (1 * 256 + 45): goto H_ROR_RI_D1;
        case (1 * 256 + 46): goto H_RET_D1;
        case (1 * 256 + 47): goto H_DECOY_6;
        case (1 * 256 + 48): goto H_DECOY_12;
        case (1 * 256 + 49): goto H_IMUL_RR_D1;
        case (1 * 256 + 50): goto H_DECOY_9;
        case (1 * 256 + 51): goto H_DECOY_0;
        case (1 * 256 + 52): goto H_DECOY_7;
        case (1 * 256 + 53): goto H_DECOY_13;
        case (1 * 256 + 54): goto H_FCMP_DD_D1;
        case (1 * 256 + 55): goto H_DECOY_2;
        case (1 * 256 + 56): goto H_DECOY_15;
        case (1 * 256 + 57): goto H_JCC_D1;
        case (1 * 256 + 58): goto H_DECOY_9;
        case (1 * 256 + 59): goto H_DECOY_2;
        case (1 * 256 + 60): goto H_DECOY_5;
        case (1 * 256 + 61): goto H_UCVTF_D1;
        case (1 * 256 + 62): goto H_BRIDGE_TO_FLOW_D1;
        case (1 * 256 + 63): goto H_DECOY_14;
        case (1 * 256 + 64): goto H_DECOY_4;
        case (1 * 256 + 65): goto H_DECOY_2;
        case (1 * 256 + 66): goto H_DECOY_15;
        case (1 * 256 + 67): goto H_SUB_RI_D1;
        case (1 * 256 + 68): goto H_VXOR_VV_D1;
        case (1 * 256 + 69): goto H_DECOY_0;
        case (1 * 256 + 70): goto H_MOV_RR_D1;
        case (1 * 256 + 71): goto H_FUSED_ADD_XOR_RRI_D1;
        case (1 * 256 + 72): goto H_CMP_RR_D1;
        case (1 * 256 + 73): goto H_FUSED_AND_OR_RRI_D1;
        case (1 * 256 + 74): goto H_CMP_RI_D1;
        case (1 * 256 + 75): goto H_IDIV_RR_D1;
        case (1 * 256 + 76): goto H_DECOY_0;
        case (1 * 256 + 77): goto H_VEC_CLEAR_UPPER_D1;
        case (1 * 256 + 78): goto H_DECOY_4;
        case (1 * 256 + 79): goto H_DECOY_2;
        case (1 * 256 + 80): goto H_VEC_LOAD_D1;
        case (1 * 256 + 81): goto H_SAR_RI_D1;
        case (1 * 256 + 82): goto H_SHL_RI_D1;
        case (1 * 256 + 83): goto H_SAR_RR_D1;
        case (1 * 256 + 84): goto H_PUSH_R_D1;
        case (1 * 256 + 85): goto H_DECOY_6;
        case (1 * 256 + 86): goto H_DECOY_10;
        case (1 * 256 + 87): goto H_DECOY_12;
        case (1 * 256 + 88): goto H_DECOY_7;
        case (1 * 256 + 89): goto H_DECOY_0;
        case (1 * 256 + 90): goto H_DECOY_11;
        case (1 * 256 + 91): goto H_DECOY_1;
        case (1 * 256 + 92): goto H_DECOY_7;
        case (1 * 256 + 93): goto H_ADC_RI_D1;
        case (1 * 256 + 94): goto H_DECOY_2;
        case (1 * 256 + 95): goto H_DECOY_15;
        case (1 * 256 + 96): goto H_DECOY_7;
        case (1 * 256 + 97): goto H_NOP_D1;
        case (1 * 256 + 98): goto H_DECOY_4;
        case (1 * 256 + 99): goto H_DECOY_3;
        case (1 * 256 + 100): goto H_DECOY_7;
        case (1 * 256 + 101): goto H_ATOMIC_CAS_D1;
        case (1 * 256 + 102): goto H_DECOY_5;
        case (1 * 256 + 103): goto H_DECOY_13;
        case (1 * 256 + 104): goto H_VADD_VV_D1;
        case (1 * 256 + 105): goto H_SET_FLAGS_R_D1;
        case (1 * 256 + 106): goto H_ADD_RR_D1;
        case (1 * 256 + 107): goto H_DECOY_15;
        case (1 * 256 + 108): goto H_DECOY_6;
        case (1 * 256 + 109): goto H_XOR_RI_D1;
        case (1 * 256 + 110): goto H_FENCE_D1;
        case (1 * 256 + 111): goto H_RESOLVE_SYM_D1;
        case (1 * 256 + 112): goto H_DECOY_13;
        case (1 * 256 + 113): goto H_DECOY_11;
        case (1 * 256 + 114): goto H_IMULH_RR_D1;
        case (1 * 256 + 115): goto H_DECOY_15;
        case (1 * 256 + 116): goto H_SBB_RR_D1;
        case (1 * 256 + 117): goto H_DECOY_3;
        case (1 * 256 + 118): goto H_SBB_RI_D1;
        case (1 * 256 + 119): goto H_BSWAP_RR_D1;
        case (1 * 256 + 120): goto H_MOV_RV_D1;
        case (1 * 256 + 121): goto H_DECOY_12;
        case (1 * 256 + 122): goto H_OR_RR_D1;
        case (1 * 256 + 123): goto H_DECOY_1;
        case (1 * 256 + 124): goto H_LOAD_S16_D1;
        case (1 * 256 + 125): goto H_DECOY_6;
        case (1 * 256 + 126): goto H_DECOY_12;
        case (1 * 256 + 127): goto H_CCMP_RR_D1;
        case (1 * 256 + 128): goto H_DECOY_13;
        case (1 * 256 + 129): goto H_DECOY_3;
        case (1 * 256 + 130): goto H_ADC_RR_D1;
        case (1 * 256 + 131): goto H_MOV_VR_D1;
        case (1 * 256 + 132): goto H_LOAD_8_D1;
        case (1 * 256 + 133): goto H_XOR_RR_D1;
        case (1 * 256 + 134): goto H_DECOY_12;
        case (1 * 256 + 135): goto H_DECOY_5;
        case (1 * 256 + 136): goto H_VEC_MOV_D1;
        case (1 * 256 + 137): goto H_DECOY_3;
        case (1 * 256 + 138): goto H_LOAD_S32_D1;
        case (1 * 256 + 139): goto H_DECOY_13;
        case (1 * 256 + 140): goto H_DECOY_0;
        case (1 * 256 + 141): goto H_DECOY_11;
        case (1 * 256 + 142): goto H_DECOY_6;
        case (1 * 256 + 143): goto H_STORE_16_D1;
        case (1 * 256 + 144): goto H_CCMN_RR_D1;
        case (1 * 256 + 145): goto H_VEC_IMM_D1;
        case (1 * 256 + 146): goto H_DECOY_10;
        case (1 * 256 + 147): goto H_SUB_RR_D1;
        case (1 * 256 + 148): goto H_MOV_RI_D1;
        case (1 * 256 + 149): goto H_VMUL_VV_D1;
        case (1 * 256 + 150): goto H_DECOY_7;
        case (1 * 256 + 151): goto H_VEC_STORE_D1;
        case (1 * 256 + 152): goto H_DECOY_10;
        case (1 * 256 + 153): goto H_FUSED_SHL_ADD_RRI_D1;
        case (1 * 256 + 154): goto H_LOAD_S8_D1;
        case (1 * 256 + 155): goto H_POPCNT_RR_D1;
        case (1 * 256 + 156): goto H_ROL_RR_D1;
        case (1 * 256 + 157): goto H_SHR_RR_D1;
        case (1 * 256 + 158): goto H_DIV_RR_D1;
        case (1 * 256 + 159): goto H_DECOY_6;
        case (1 * 256 + 160): goto H_DECOY_15;
        case (1 * 256 + 161): goto H_DECOY_12;
        case (1 * 256 + 162): goto H_DECOY_7;
        case (1 * 256 + 163): goto H_VEC_ZERO_UPPER_D1;
        case (1 * 256 + 164): goto H_DECOY_6;
        case (1 * 256 + 165): goto H_DECOY_9;
        case (1 * 256 + 166): goto H_DECOY_6;
        case (1 * 256 + 167): goto H_DECOY_8;
        case (1 * 256 + 168): goto H_NEG_RR_D1;
        case (1 * 256 + 169): goto H_ATOMIC_LOAD_D1;
        case (1 * 256 + 170): goto H_DECOY_7;
        case (1 * 256 + 171): goto H_AND_RR_D1;
        case (1 * 256 + 172): goto H_DECOY_6;
        case (1 * 256 + 173): goto H_EXIT_D1;
        case (1 * 256 + 174): goto H_DECOY_12;
        case (1 * 256 + 175): goto H_PMOVMSKB_D1;
        case (1 * 256 + 176): goto H_DECOY_14;
        case (1 * 256 + 177): goto H_DECOY_14;
        case (1 * 256 + 178): goto H_DECOY_11;
        case (1 * 256 + 179): goto H_DECOY_3;
        case (1 * 256 + 180): goto H_FCVTZS_D1;
        case (1 * 256 + 181): goto H_SETCC_D1;
        case (1 * 256 + 182): goto H_DECOY_3;
        case (1 * 256 + 183): goto H_DECOY_3;
        case (1 * 256 + 184): goto H_VEC_BINOP_D1;
        case (1 * 256 + 185): goto H_DECOY_1;
        case (1 * 256 + 186): goto H_ROR_RR_D1;
        case (1 * 256 + 187): goto H_DECOY_7;
        case (1 * 256 + 188): goto H_CLZ_RR_D1;
        case (1 * 256 + 189): goto H_FUSED_SUB_XOR_RRI_D1;
        case (1 * 256 + 190): goto H_DECOY_12;
        case (1 * 256 + 191): goto H_AND_RI_D1;
        case (1 * 256 + 192): goto H_DECOY_3;
        case (1 * 256 + 193): goto H_DECOY_12;
        case (1 * 256 + 194): goto H_DECOY_1;
        case (1 * 256 + 195): goto H_CALL_D1;
        case (1 * 256 + 196): goto H_GET_FLAGS_R_D1;
        case (1 * 256 + 197): goto H_FADD_DD_D1;
        case (1 * 256 + 198): goto H_DECOY_7;
        case (1 * 256 + 199): goto H_DECOY_3;
        case (1 * 256 + 200): goto H_DECOY_7;
        case (1 * 256 + 201): goto H_DECOY_0;
        case (1 * 256 + 202): goto H_DECOY_4;
        case (1 * 256 + 203): goto H_CCMP_RI_D1;
        case (1 * 256 + 204): goto H_STORE_32_D1;
        case (1 * 256 + 205): goto H_DECOY_6;
        case (1 * 256 + 206): goto H_DECOY_7;
        case (1 * 256 + 207): goto H_DECOY_13;
        case (1 * 256 + 208): goto H_FCSEL_VV_D1;
        case (1 * 256 + 209): goto H_CCMN_RI_D1;
        case (1 * 256 + 210): goto H_OR_RI_D1;
        case (1 * 256 + 211): goto H_DECOY_2;
        case (1 * 256 + 212): goto H_DECOY_2;
        case (1 * 256 + 213): goto H_SCVTF_D1;
        case (1 * 256 + 214): goto H_DECOY_0;
        case (1 * 256 + 215): goto H_JMP_D1;
        case (1 * 256 + 216): goto H_MULH_RR_D1;
        case (1 * 256 + 217): goto H_SHL_RR_D1;
        case (1 * 256 + 218): goto H_DECOY_3;
        case (1 * 256 + 219): goto H_DECOY_5;
        case (1 * 256 + 220): goto H_FSUB_DD_D1;
        case (1 * 256 + 221): goto H_STORE_64_D1;
        case (1 * 256 + 222): goto H_SHR_RI_D1;
        case (1 * 256 + 223): goto H_DECOY_14;
        case (1 * 256 + 224): goto H_DECOY_7;
        case (1 * 256 + 225): goto H_DECOY_12;
        case (1 * 256 + 226): goto H_DECOY_12;
        case (1 * 256 + 227): goto H_FDIV_DD_D1;
        case (1 * 256 + 228): goto H_DECOY_11;
        case (1 * 256 + 229): goto H_DECOY_14;
        case (1 * 256 + 230): goto H_IJMP_R_D1;
        case (1 * 256 + 231): goto H_DECOY_5;
        case (1 * 256 + 232): goto H_ATOMIC_ADD_D1;
        case (1 * 256 + 233): goto H_STORE_8_D1;
        case (1 * 256 + 234): goto H_DECOY_1;
        case (1 * 256 + 235): goto H_DECOY_7;
        case (1 * 256 + 236): goto H_DECOY_14;
        case (1 * 256 + 237): goto H_DECOY_11;
        case (1 * 256 + 238): goto H_LOAD_16_D1;
        case (1 * 256 + 239): goto H_DECOY_11;
        case (1 * 256 + 240): goto H_DECOY_2;
        case (1 * 256 + 241): goto H_VSUB_VV_D1;
        case (1 * 256 + 242): goto H_IMUL_RI_D1;
        case (1 * 256 + 243): goto H_CALL_EXTERN_D1;
        case (1 * 256 + 244): goto H_DECOY_4;
        case (1 * 256 + 245): goto H_DECOY_13;
        case (1 * 256 + 246): goto H_FMUL_DD_D1;
        case (1 * 256 + 247): goto H_ATOMIC_STORE_D1;
        case (1 * 256 + 248): goto H_DECOY_0;
        case (1 * 256 + 249): goto H_CTZ_RR_D1;
        case (1 * 256 + 250): goto H_ADD_RI_D1;
        case (1 * 256 + 251): goto H_RBIT_RR_D1;
        case (1 * 256 + 252): goto H_DECOY_3;
        case (1 * 256 + 253): goto H_FUSED_XOR_ADD_RRI_D1;
        case (1 * 256 + 254): goto H_DECOY_10;
        case (1 * 256 + 255): goto H_LOAD_32_D1;
        case (2 * 256 + 0): goto H_BRIDGE_TO_FLOW_D2;
        case (2 * 256 + 1): goto H_DECOY_11;
        case (2 * 256 + 2): goto H_DECOY_14;
        case (2 * 256 + 3): goto H_UCVTF_D2;
        case (2 * 256 + 4): goto H_DECOY_14;
        case (2 * 256 + 5): goto H_DECOY_7;
        case (2 * 256 + 6): goto H_DECOY_0;
        case (2 * 256 + 7): goto H_JCC_D2;
        case (2 * 256 + 8): goto H_FCMP_DD_D2;
        case (2 * 256 + 9): goto H_DECOY_15;
        case (2 * 256 + 10): goto H_DECOY_0;
        case (2 * 256 + 11): goto H_DECOY_6;
        case (2 * 256 + 12): goto H_DECOY_14;
        case (2 * 256 + 13): goto H_DECOY_5;
        case (2 * 256 + 14): goto H_DECOY_13;
        case (2 * 256 + 15): goto H_IMUL_RR_D2;
        case (2 * 256 + 16): goto H_RET_D2;
        case (2 * 256 + 17): goto H_DECOY_3;
        case (2 * 256 + 18): goto H_LOAD_64_D2;
        case (2 * 256 + 19): goto H_ROR_RI_D2;
        case (2 * 256 + 20): goto H_ROL_RI_D2;
        case (2 * 256 + 21): goto H_FUSED_MOV_ADD_RRI_D2;
        case (2 * 256 + 22): goto H_POP_R_D2;
        case (2 * 256 + 23): goto H_DECOY_4;
        case (2 * 256 + 24): goto H_MOV_HIGH_D2;
        case (2 * 256 + 25): goto H_DECOY_6;
        case (2 * 256 + 26): goto H_DECOY_2;
        case (2 * 256 + 27): goto H_FSQRT_D_D2;
        case (2 * 256 + 28): goto H_DECOY_8;
        case (2 * 256 + 29): goto H_VEC_EXT_D2;
        case (2 * 256 + 30): goto H_DECOY_14;
        case (2 * 256 + 31): goto H_DECOY_0;
        case (2 * 256 + 32): goto H_DECOY_4;
        case (2 * 256 + 33): goto H_DECOY_5;
        case (2 * 256 + 34): goto H_DECOY_0;
        case (2 * 256 + 35): goto H_DECOY_12;
        case (2 * 256 + 36): goto H_DECOY_8;
        case (2 * 256 + 37): goto H_DECOY_11;
        case (2 * 256 + 38): goto H_DECOY_11;
        case (2 * 256 + 39): goto H_DECOY_8;
        case (2 * 256 + 40): goto H_NOT_RR_D2;
        case (2 * 256 + 41): goto H_FUSED_CMP_CMOV_D2;
        case (2 * 256 + 42): goto H_DECOY_12;
        case (2 * 256 + 43): goto H_CMOV_D2;
        case (2 * 256 + 44): goto H_DECOY_5;
        case (2 * 256 + 45): goto H_FCVTZU_D2;
        case (2 * 256 + 46): goto H_DECOY_1;
        case (2 * 256 + 47): goto H_DECOY_11;
        case (2 * 256 + 48): goto H_DECOY_2;
        case (2 * 256 + 49): goto H_DECOY_10;
        case (2 * 256 + 50): goto H_DECOY_0;
        case (2 * 256 + 51): goto H_BRIDGE_TO_MATH_D2;
        case (2 * 256 + 52): goto H_DECOY_4;
        case (2 * 256 + 53): goto H_ICALL_R_D2;
        case (2 * 256 + 54): goto H_VEC_SPLAT_D2;
        case (2 * 256 + 55): goto H_ATOMIC_SWP_D2;
        case (2 * 256 + 56): goto H_DECOY_5;
        case (2 * 256 + 57): goto H_DECOY_14;
        case (2 * 256 + 58): goto H_DECOY_9;
        case (2 * 256 + 59): goto H_DECOY_3;
        case (2 * 256 + 60): goto H_DECOY_14;
        case (2 * 256 + 61): goto H_DECOY_4;
        case (2 * 256 + 62): goto H_FUSED_ADD_IMUL_RRI_D2;
        case (2 * 256 + 63): goto H_FCVT_D2;
        case (2 * 256 + 64): goto H_DECOY_9;
        case (2 * 256 + 65): goto H_CCMP_RR_D2;
        case (2 * 256 + 66): goto H_LOAD_S16_D2;
        case (2 * 256 + 67): goto H_DECOY_15;
        case (2 * 256 + 68): goto H_OR_RR_D2;
        case (2 * 256 + 69): goto H_DECOY_6;
        case (2 * 256 + 70): goto H_MOV_RV_D2;
        case (2 * 256 + 71): goto H_DECOY_13;
        case (2 * 256 + 72): goto H_SBB_RI_D2;
        case (2 * 256 + 73): goto H_BSWAP_RR_D2;
        case (2 * 256 + 74): goto H_SBB_RR_D2;
        case (2 * 256 + 75): goto H_DECOY_12;
        case (2 * 256 + 76): goto H_IMULH_RR_D2;
        case (2 * 256 + 77): goto H_DECOY_4;
        case (2 * 256 + 78): goto H_DECOY_14;
        case (2 * 256 + 79): goto H_DECOY_12;
        case (2 * 256 + 80): goto H_FENCE_D2;
        case (2 * 256 + 81): goto H_RESOLVE_SYM_D2;
        case (2 * 256 + 82): goto H_DECOY_15;
        case (2 * 256 + 83): goto H_XOR_RI_D2;
        case (2 * 256 + 84): goto H_ADD_RR_D2;
        case (2 * 256 + 85): goto H_DECOY_4;
        case (2 * 256 + 86): goto H_VADD_VV_D2;
        case (2 * 256 + 87): goto H_SET_FLAGS_R_D2;
        case (2 * 256 + 88): goto H_DECOY_2;
        case (2 * 256 + 89): goto H_DECOY_10;
        case (2 * 256 + 90): goto H_DECOY_0;
        case (2 * 256 + 91): goto H_ATOMIC_CAS_D2;
        case (2 * 256 + 92): goto H_DECOY_9;
        case (2 * 256 + 93): goto H_DECOY_8;
        case (2 * 256 + 94): goto H_DECOY_8;
        case (2 * 256 + 95): goto H_NOP_D2;
        case (2 * 256 + 96): goto H_DECOY_15;
        case (2 * 256 + 97): goto H_DECOY_12;
        case (2 * 256 + 98): goto H_DECOY_0;
        case (2 * 256 + 99): goto H_ADC_RI_D2;
        case (2 * 256 + 100): goto H_DECOY_0;
        case (2 * 256 + 101): goto H_DECOY_6;
        case (2 * 256 + 102): goto H_DECOY_8;
        case (2 * 256 + 103): goto H_DECOY_1;
        case (2 * 256 + 104): goto H_DECOY_7;
        case (2 * 256 + 105): goto H_DECOY_9;
        case (2 * 256 + 106): goto H_PUSH_R_D2;
        case (2 * 256 + 107): goto H_DECOY_15;
        case (2 * 256 + 108): goto H_SHL_RI_D2;
        case (2 * 256 + 109): goto H_SAR_RR_D2;
        case (2 * 256 + 110): goto H_VEC_LOAD_D2;
        case (2 * 256 + 111): goto H_SAR_RI_D2;
        case (2 * 256 + 112): goto H_DECOY_1;
        case (2 * 256 + 113): goto H_DECOY_15;
        case (2 * 256 + 114): goto H_DECOY_9;
        case (2 * 256 + 115): goto H_VEC_CLEAR_UPPER_D2;
        case (2 * 256 + 116): goto H_CMP_RI_D2;
        case (2 * 256 + 117): goto H_IDIV_RR_D2;
        case (2 * 256 + 118): goto H_CMP_RR_D2;
        case (2 * 256 + 119): goto H_FUSED_AND_OR_RRI_D2;
        case (2 * 256 + 120): goto H_MOV_RR_D2;
        case (2 * 256 + 121): goto H_FUSED_ADD_XOR_RRI_D2;
        case (2 * 256 + 122): goto H_VXOR_VV_D2;
        case (2 * 256 + 123): goto H_DECOY_9;
        case (2 * 256 + 124): goto H_DECOY_4;
        case (2 * 256 + 125): goto H_SUB_RI_D2;
        case (2 * 256 + 126): goto H_DECOY_5;
        case (2 * 256 + 127): goto H_DECOY_3;
        case (2 * 256 + 128): goto H_DECOY_9;
        case (2 * 256 + 129): goto H_AND_RI_D2;
        case (2 * 256 + 130): goto H_CLZ_RR_D2;
        case (2 * 256 + 131): goto H_FUSED_SUB_XOR_RRI_D2;
        case (2 * 256 + 132): goto H_ROR_RR_D2;
        case (2 * 256 + 133): goto H_DECOY_12;
        case (2 * 256 + 134): goto H_VEC_BINOP_D2;
        case (2 * 256 + 135): goto H_DECOY_2;
        case (2 * 256 + 136): goto H_DECOY_0;
        case (2 * 256 + 137): goto H_DECOY_0;
        case (2 * 256 + 138): goto H_FCVTZS_D2;
        case (2 * 256 + 139): goto H_SETCC_D2;
        case (2 * 256 + 140): goto H_DECOY_0;
        case (2 * 256 + 141): goto H_DECOY_8;
        case (2 * 256 + 142): goto H_DECOY_15;
        case (2 * 256 + 143): goto H_DECOY_15;
        case (2 * 256 + 144): goto H_DECOY_9;
        case (2 * 256 + 145): goto H_PMOVMSKB_D2;
        case (2 * 256 + 146): goto H_DECOY_15;
        case (2 * 256 + 147): goto H_EXIT_D2;
        case (2 * 256 + 148): goto H_DECOY_12;
        case (2 * 256 + 149): goto H_AND_RR_D2;
        case (2 * 256 + 150): goto H_NEG_RR_D2;
        case (2 * 256 + 151): goto H_ATOMIC_LOAD_D2;
        case (2 * 256 + 152): goto H_DECOY_3;
        case (2 * 256 + 153): goto H_DECOY_5;
        case (2 * 256 + 154): goto H_DECOY_15;
        case (2 * 256 + 155): goto H_DECOY_2;
        case (2 * 256 + 156): goto H_DECOY_12;
        case (2 * 256 + 157): goto H_VEC_ZERO_UPPER_D2;
        case (2 * 256 + 158): goto H_DECOY_0;
        case (2 * 256 + 159): goto H_DECOY_13;
        case (2 * 256 + 160): goto H_DIV_RR_D2;
        case (2 * 256 + 161): goto H_DECOY_3;
        case (2 * 256 + 162): goto H_ROL_RR_D2;
        case (2 * 256 + 163): goto H_SHR_RR_D2;
        case (2 * 256 + 164): goto H_LOAD_S8_D2;
        case (2 * 256 + 165): goto H_POPCNT_RR_D2;
        case (2 * 256 + 166): goto H_DECOY_11;
        case (2 * 256 + 167): goto H_FUSED_SHL_ADD_RRI_D2;
        case (2 * 256 + 168): goto H_DECOY_4;
        case (2 * 256 + 169): goto H_VEC_STORE_D2;
        case (2 * 256 + 170): goto H_MOV_RI_D2;
        case (2 * 256 + 171): goto H_VMUL_VV_D2;
        case (2 * 256 + 172): goto H_DECOY_15;
        case (2 * 256 + 173): goto H_SUB_RR_D2;
        case (2 * 256 + 174): goto H_CCMN_RR_D2;
        case (2 * 256 + 175): goto H_VEC_IMM_D2;
        case (2 * 256 + 176): goto H_DECOY_3;
        case (2 * 256 + 177): goto H_STORE_16_D2;
        case (2 * 256 + 178): goto H_DECOY_9;
        case (2 * 256 + 179): goto H_DECOY_4;
        case (2 * 256 + 180): goto H_LOAD_S32_D2;
        case (2 * 256 + 181): goto H_DECOY_2;
        case (2 * 256 + 182): goto H_VEC_MOV_D2;
        case (2 * 256 + 183): goto H_DECOY_4;
        case (2 * 256 + 184): goto H_DECOY_9;
        case (2 * 256 + 185): goto H_DECOY_2;
        case (2 * 256 + 186): goto H_LOAD_8_D2;
        case (2 * 256 + 187): goto H_XOR_RR_D2;
        case (2 * 256 + 188): goto H_ADC_RR_D2;
        case (2 * 256 + 189): goto H_MOV_VR_D2;
        case (2 * 256 + 190): goto H_DECOY_14;
        case (2 * 256 + 191): goto H_DECOY_4;
        case (2 * 256 + 192): goto H_DECOY_7;
        case (2 * 256 + 193): goto H_LOAD_32_D2;
        case (2 * 256 + 194): goto H_DECOY_12;
        case (2 * 256 + 195): goto H_FUSED_XOR_ADD_RRI_D2;
        case (2 * 256 + 196): goto H_ADD_RI_D2;
        case (2 * 256 + 197): goto H_RBIT_RR_D2;
        case (2 * 256 + 198): goto H_DECOY_1;
        case (2 * 256 + 199): goto H_CTZ_RR_D2;
        case (2 * 256 + 200): goto H_FMUL_DD_D2;
        case (2 * 256 + 201): goto H_ATOMIC_STORE_D2;
        case (2 * 256 + 202): goto H_DECOY_13;
        case (2 * 256 + 203): goto H_DECOY_6;
        case (2 * 256 + 204): goto H_IMUL_RI_D2;
        case (2 * 256 + 205): goto H_CALL_EXTERN_D2;
        case (2 * 256 + 206): goto H_DECOY_3;
        case (2 * 256 + 207): goto H_VSUB_VV_D2;
        case (2 * 256 + 208): goto H_LOAD_16_D2;
        case (2 * 256 + 209): goto H_DECOY_8;
        case (2 * 256 + 210): goto H_DECOY_7;
        case (2 * 256 + 211): goto H_DECOY_4;
        case (2 * 256 + 212): goto H_DECOY_6;
        case (2 * 256 + 213): goto H_DECOY_12;
        case (2 * 256 + 214): goto H_ATOMIC_ADD_D2;
        case (2 * 256 + 215): goto H_STORE_8_D2;
        case (2 * 256 + 216): goto H_IJMP_R_D2;
        case (2 * 256 + 217): goto H_DECOY_2;
        case (2 * 256 + 218): goto H_DECOY_4;
        case (2 * 256 + 219): goto H_DECOY_7;
        case (2 * 256 + 220): goto H_DECOY_1;
        case (2 * 256 + 221): goto H_FDIV_DD_D2;
        case (2 * 256 + 222): goto H_DECOY_8;
        case (2 * 256 + 223): goto H_DECOY_13;
        case (2 * 256 + 224): goto H_SHR_RI_D2;
        case (2 * 256 + 225): goto H_DECOY_11;
        case (2 * 256 + 226): goto H_FSUB_DD_D2;
        case (2 * 256 + 227): goto H_STORE_64_D2;
        case (2 * 256 + 228): goto H_DECOY_8;
        case (2 * 256 + 229): goto H_DECOY_10;
        case (2 * 256 + 230): goto H_MULH_RR_D2;
        case (2 * 256 + 231): goto H_SHL_RR_D2;
        case (2 * 256 + 232): goto H_DECOY_13;
        case (2 * 256 + 233): goto H_JMP_D2;
        case (2 * 256 + 234): goto H_DECOY_11;
        case (2 * 256 + 235): goto H_SCVTF_D2;
        case (2 * 256 + 236): goto H_OR_RI_D2;
        case (2 * 256 + 237): goto H_DECOY_7;
        case (2 * 256 + 238): goto H_FCSEL_VV_D2;
        case (2 * 256 + 239): goto H_CCMN_RI_D2;
        case (2 * 256 + 240): goto H_DECOY_4;
        case (2 * 256 + 241): goto H_DECOY_10;
        case (2 * 256 + 242): goto H_STORE_32_D2;
        case (2 * 256 + 243): goto H_DECOY_15;
        case (2 * 256 + 244): goto H_DECOY_9;
        case (2 * 256 + 245): goto H_CCMP_RI_D2;
        case (2 * 256 + 246): goto H_DECOY_8;
        case (2 * 256 + 247): goto H_DECOY_1;
        case (2 * 256 + 248): goto H_DECOY_4;
        case (2 * 256 + 249): goto H_DECOY_0;
        case (2 * 256 + 250): goto H_GET_FLAGS_R_D2;
        case (2 * 256 + 251): goto H_FADD_DD_D2;
        case (2 * 256 + 252): goto H_DECOY_6;
        case (2 * 256 + 253): goto H_CALL_D2;
        case (2 * 256 + 254): goto H_DECOY_4;
        case (2 * 256 + 255): goto H_DECOY_13;
        case (3 * 256 + 0): goto H_JMP_D1;
        case (3 * 256 + 1): goto H_DECOY_15;
        case (3 * 256 + 2): goto H_SCVTF_D1;
        case (3 * 256 + 3): goto H_DECOY_13;
        case (3 * 256 + 4): goto H_DECOY_3;
        case (3 * 256 + 5): goto H_OR_RI_D1;
        case (3 * 256 + 6): goto H_CCMN_RI_D1;
        case (3 * 256 + 7): goto H_FCSEL_VV_D1;
        case (3 * 256 + 8): goto H_DECOY_7;
        case (3 * 256 + 9): goto H_SHR_RI_D1;
        case (3 * 256 + 10): goto H_STORE_64_D1;
        case (3 * 256 + 11): goto H_FSUB_DD_D1;
        case (3 * 256 + 12): goto H_DECOY_6;
        case (3 * 256 + 13): goto H_DECOY_10;
        case (3 * 256 + 14): goto H_SHL_RR_D1;
        case (3 * 256 + 15): goto H_MULH_RR_D1;
        case (3 * 256 + 16): goto H_DECOY_12;
        case (3 * 256 + 17): goto H_DECOY_6;
        case (3 * 256 + 18): goto H_FADD_DD_D1;
        case (3 * 256 + 19): goto H_GET_FLAGS_R_D1;
        case (3 * 256 + 20): goto H_CALL_D1;
        case (3 * 256 + 21): goto H_DECOY_8;
        case (3 * 256 + 22): goto H_DECOY_9;
        case (3 * 256 + 23): goto H_DECOY_6;
        case (3 * 256 + 24): goto H_DECOY_6;
        case (3 * 256 + 25): goto H_DECOY_6;
        case (3 * 256 + 26): goto H_DECOY_11;
        case (3 * 256 + 27): goto H_STORE_32_D1;
        case (3 * 256 + 28): goto H_CCMP_RI_D1;
        case (3 * 256 + 29): goto H_DECOY_11;
        case (3 * 256 + 30): goto H_DECOY_13;
        case (3 * 256 + 31): goto H_DECOY_10;
        case (3 * 256 + 32): goto H_ATOMIC_STORE_D1;
        case (3 * 256 + 33): goto H_FMUL_DD_D1;
        case (3 * 256 + 34): goto H_DECOY_2;
        case (3 * 256 + 35): goto H_DECOY_15;
        case (3 * 256 + 36): goto H_CALL_EXTERN_D1;
        case (3 * 256 + 37): goto H_IMUL_RI_D1;
        case (3 * 256 + 38): goto H_VSUB_VV_D1;
        case (3 * 256 + 39): goto H_DECOY_5;
        case (3 * 256 + 40): goto H_LOAD_32_D1;
        case (3 * 256 + 41): goto H_DECOY_9;
        case (3 * 256 + 42): goto H_FUSED_XOR_ADD_RRI_D1;
        case (3 * 256 + 43): goto H_DECOY_14;
        case (3 * 256 + 44): goto H_RBIT_RR_D1;
        case (3 * 256 + 45): goto H_ADD_RI_D1;
        case (3 * 256 + 46): goto H_CTZ_RR_D1;
        case (3 * 256 + 47): goto H_DECOY_3;
        case (3 * 256 + 48): goto H_DECOY_14;
        case (3 * 256 + 49): goto H_IJMP_R_D1;
        case (3 * 256 + 50): goto H_DECOY_3;
        case (3 * 256 + 51): goto H_DECOY_6;
        case (3 * 256 + 52): goto H_FDIV_DD_D1;
        case (3 * 256 + 53): goto H_DECOY_3;
        case (3 * 256 + 54): goto H_DECOY_9;
        case (3 * 256 + 55): goto H_DECOY_10;
        case (3 * 256 + 56): goto H_DECOY_4;
        case (3 * 256 + 57): goto H_LOAD_16_D1;
        case (3 * 256 + 58): goto H_DECOY_0;
        case (3 * 256 + 59): goto H_DECOY_9;
        case (3 * 256 + 60): goto H_DECOY_8;
        case (3 * 256 + 61): goto H_DECOY_8;
        case (3 * 256 + 62): goto H_STORE_8_D1;
        case (3 * 256 + 63): goto H_ATOMIC_ADD_D1;
        case (3 * 256 + 64): goto H_VEC_STORE_D1;
        case (3 * 256 + 65): goto H_DECOY_6;
        case (3 * 256 + 66): goto H_VMUL_VV_D1;
        case (3 * 256 + 67): goto H_MOV_RI_D1;
        case (3 * 256 + 68): goto H_SUB_RR_D1;
        case (3 * 256 + 69): goto H_DECOY_1;
        case (3 * 256 + 70): goto H_VEC_IMM_D1;
        case (3 * 256 + 71): goto H_CCMN_RR_D1;
        case (3 * 256 + 72): goto H_DECOY_15;
        case (3 * 256 + 73): goto H_DIV_RR_D1;
        case (3 * 256 + 74): goto H_SHR_RR_D1;
        case (3 * 256 + 75): goto H_ROL_RR_D1;
        case (3 * 256 + 76): goto H_POPCNT_RR_D1;
        case (3 * 256 + 77): goto H_LOAD_S8_D1;
        case (3 * 256 + 78): goto H_FUSED_SHL_ADD_RRI_D1;
        case (3 * 256 + 79): goto H_DECOY_13;
        case (3 * 256 + 80): goto H_DECOY_14;
        case (3 * 256 + 81): goto H_DECOY_11;
        case (3 * 256 + 82): goto H_XOR_RR_D1;
        case (3 * 256 + 83): goto H_LOAD_8_D1;
        case (3 * 256 + 84): goto H_MOV_VR_D1;
        case (3 * 256 + 85): goto H_ADC_RR_D1;
        case (3 * 256 + 86): goto H_DECOY_0;
        case (3 * 256 + 87): goto H_DECOY_0;
        case (3 * 256 + 88): goto H_STORE_16_D1;
        case (3 * 256 + 89): goto H_DECOY_5;
        case (3 * 256 + 90): goto H_DECOY_0;
        case (3 * 256 + 91): goto H_DECOY_11;
        case (3 * 256 + 92): goto H_DECOY_14;
        case (3 * 256 + 93): goto H_LOAD_S32_D1;
        case (3 * 256 + 94): goto H_DECOY_0;
        case (3 * 256 + 95): goto H_VEC_MOV_D1;
        case (3 * 256 + 96): goto H_DECOY_12;
        case (3 * 256 + 97): goto H_DECOY_2;
        case (3 * 256 + 98): goto H_SETCC_D1;
        case (3 * 256 + 99): goto H_FCVTZS_D1;
        case (3 * 256 + 100): goto H_DECOY_4;
        case (3 * 256 + 101): goto H_DECOY_2;
        case (3 * 256 + 102): goto H_DECOY_11;
        case (3 * 256 + 103): goto H_DECOY_1;
        case (3 * 256 + 104): goto H_AND_RI_D1;
        case (3 * 256 + 105): goto H_DECOY_11;
        case (3 * 256 + 106): goto H_FUSED_SUB_XOR_RRI_D1;
        case (3 * 256 + 107): goto H_CLZ_RR_D1;
        case (3 * 256 + 108): goto H_DECOY_8;
        case (3 * 256 + 109): goto H_ROR_RR_D1;
        case (3 * 256 + 110): goto H_DECOY_14;
        case (3 * 256 + 111): goto H_VEC_BINOP_D1;
        case (3 * 256 + 112): goto H_DECOY_1;
        case (3 * 256 + 113): goto H_DECOY_5;
        case (3 * 256 + 114): goto H_DECOY_14;
        case (3 * 256 + 115): goto H_DECOY_1;
        case (3 * 256 + 116): goto H_VEC_ZERO_UPPER_D1;
        case (3 * 256 + 117): goto H_DECOY_14;
        case (3 * 256 + 118): goto H_DECOY_9;
        case (3 * 256 + 119): goto H_DECOY_2;
        case (3 * 256 + 120): goto H_PMOVMSKB_D1;
        case (3 * 256 + 121): goto H_DECOY_11;
        case (3 * 256 + 122): goto H_EXIT_D1;
        case (3 * 256 + 123): goto H_DECOY_1;
        case (3 * 256 + 124): goto H_AND_RR_D1;
        case (3 * 256 + 125): goto H_DECOY_14;
        case (3 * 256 + 126): goto H_ATOMIC_LOAD_D1;
        case (3 * 256 + 127): goto H_NEG_RR_D1;
        case (3 * 256 + 128): goto H_DECOY_5;
        case (3 * 256 + 129): goto H_DECOY_9;
        case (3 * 256 + 130): goto H_DECOY_11;
        case (3 * 256 + 131): goto H_PUSH_R_D1;
        case (3 * 256 + 132): goto H_SAR_RR_D1;
        case (3 * 256 + 133): goto H_SHL_RI_D1;
        case (3 * 256 + 134): goto H_SAR_RI_D1;
        case (3 * 256 + 135): goto H_VEC_LOAD_D1;
        case (3 * 256 + 136): goto H_DECOY_8;
        case (3 * 256 + 137): goto H_DECOY_1;
        case (3 * 256 + 138): goto H_ADC_RI_D1;
        case (3 * 256 + 139): goto H_DECOY_2;
        case (3 * 256 + 140): goto H_DECOY_2;
        case (3 * 256 + 141): goto H_DECOY_2;
        case (3 * 256 + 142): goto H_DECOY_13;
        case (3 * 256 + 143): goto H_DECOY_10;
        case (3 * 256 + 144): goto H_FUSED_ADD_XOR_RRI_D1;
        case (3 * 256 + 145): goto H_MOV_RR_D1;
        case (3 * 256 + 146): goto H_DECOY_5;
        case (3 * 256 + 147): goto H_VXOR_VV_D1;
        case (3 * 256 + 148): goto H_SUB_RI_D1;
        case (3 * 256 + 149): goto H_DECOY_6;
        case (3 * 256 + 150): goto H_DECOY_15;
        case (3 * 256 + 151): goto H_DECOY_7;
        case (3 * 256 + 152): goto H_DECOY_11;
        case (3 * 256 + 153): goto H_DECOY_3;
        case (3 * 256 + 154): goto H_VEC_CLEAR_UPPER_D1;
        case (3 * 256 + 155): goto H_DECOY_11;
        case (3 * 256 + 156): goto H_IDIV_RR_D1;
        case (3 * 256 + 157): goto H_CMP_RI_D1;
        case (3 * 256 + 158): goto H_FUSED_AND_OR_RRI_D1;
        case (3 * 256 + 159): goto H_CMP_RR_D1;
        case (3 * 256 + 160): goto H_BSWAP_RR_D1;
        case (3 * 256 + 161): goto H_SBB_RI_D1;
        case (3 * 256 + 162): goto H_DECOY_8;
        case (3 * 256 + 163): goto H_SBB_RR_D1;
        case (3 * 256 + 164): goto H_DECOY_0;
        case (3 * 256 + 165): goto H_IMULH_RR_D1;
        case (3 * 256 + 166): goto H_DECOY_8;
        case (3 * 256 + 167): goto H_DECOY_0;
        case (3 * 256 + 168): goto H_CCMP_RR_D1;
        case (3 * 256 + 169): goto H_DECOY_11;
        case (3 * 256 + 170): goto H_DECOY_11;
        case (3 * 256 + 171): goto H_LOAD_S16_D1;
        case (3 * 256 + 172): goto H_DECOY_2;
        case (3 * 256 + 173): goto H_OR_RR_D1;
        case (3 * 256 + 174): goto H_DECOY_9;
        case (3 * 256 + 175): goto H_MOV_RV_D1;
        case (3 * 256 + 176): goto H_DECOY_6;
        case (3 * 256 + 177): goto H_DECOY_4;
        case (3 * 256 + 178): goto H_ATOMIC_CAS_D1;
        case (3 * 256 + 179): goto H_DECOY_2;
        case (3 * 256 + 180): goto H_DECOY_4;
        case (3 * 256 + 181): goto H_DECOY_11;
        case (3 * 256 + 182): goto H_NOP_D1;
        case (3 * 256 + 183): goto H_DECOY_10;
        case (3 * 256 + 184): goto H_RESOLVE_SYM_D1;
        case (3 * 256 + 185): goto H_FENCE_D1;
        case (3 * 256 + 186): goto H_XOR_RI_D1;
        case (3 * 256 + 187): goto H_DECOY_1;
        case (3 * 256 + 188): goto H_DECOY_0;
        case (3 * 256 + 189): goto H_ADD_RR_D1;
        case (3 * 256 + 190): goto H_SET_FLAGS_R_D1;
        case (3 * 256 + 191): goto H_VADD_VV_D1;
        case (3 * 256 + 192): goto H_FUSED_CMP_CMOV_D1;
        case (3 * 256 + 193): goto H_NOT_RR_D1;
        case (3 * 256 + 194): goto H_CMOV_D1;
        case (3 * 256 + 195): goto H_DECOY_14;
        case (3 * 256 + 196): goto H_FCVTZU_D1;
        case (3 * 256 + 197): goto H_DECOY_7;
        case (3 * 256 + 198): goto H_DECOY_7;
        case (3 * 256 + 199): goto H_DECOY_3;
        case (3 * 256 + 200): goto H_DECOY_1;
        case (3 * 256 + 201): goto H_DECOY_6;
        case (3 * 256 + 202): goto H_DECOY_8;
        case (3 * 256 + 203): goto H_DECOY_2;
        case (3 * 256 + 204): goto H_DECOY_7;
        case (3 * 256 + 205): goto H_DECOY_10;
        case (3 * 256 + 206): goto H_DECOY_4;
        case (3 * 256 + 207): goto H_DECOY_13;
        case (3 * 256 + 208): goto H_DECOY_10;
        case (3 * 256 + 209): goto H_DECOY_7;
        case (3 * 256 + 210): goto H_DECOY_15;
        case (3 * 256 + 211): goto H_DECOY_11;
        case (3 * 256 + 212): goto H_DECOY_0;
        case (3 * 256 + 213): goto H_DECOY_0;
        case (3 * 256 + 214): goto H_FCVT_D1;
        case (3 * 256 + 215): goto H_FUSED_ADD_IMUL_RRI_D1;
        case (3 * 256 + 216): goto H_DECOY_6;
        case (3 * 256 + 217): goto H_DECOY_4;
        case (3 * 256 + 218): goto H_BRIDGE_TO_MATH_D1;
        case (3 * 256 + 219): goto H_DECOY_2;
        case (3 * 256 + 220): goto H_ICALL_R_D1;
        case (3 * 256 + 221): goto H_DECOY_6;
        case (3 * 256 + 222): goto H_ATOMIC_SWP_D1;
        case (3 * 256 + 223): goto H_VEC_SPLAT_D1;
        case (3 * 256 + 224): goto H_DECOY_11;
        case (3 * 256 + 225): goto H_FCMP_DD_D1;
        case (3 * 256 + 226): goto H_DECOY_2;
        case (3 * 256 + 227): goto H_DECOY_2;
        case (3 * 256 + 228): goto H_DECOY_1;
        case (3 * 256 + 229): goto H_DECOY_0;
        case (3 * 256 + 230): goto H_IMUL_RR_D1;
        case (3 * 256 + 231): goto H_DECOY_15;
        case (3 * 256 + 232): goto H_DECOY_7;
        case (3 * 256 + 233): goto H_BRIDGE_TO_FLOW_D1;
        case (3 * 256 + 234): goto H_UCVTF_D1;
        case (3 * 256 + 235): goto H_DECOY_0;
        case (3 * 256 + 236): goto H_DECOY_3;
        case (3 * 256 + 237): goto H_DECOY_0;
        case (3 * 256 + 238): goto H_JCC_D1;
        case (3 * 256 + 239): goto H_DECOY_2;
        case (3 * 256 + 240): goto H_DECOY_2;
        case (3 * 256 + 241): goto H_MOV_HIGH_D1;
        case (3 * 256 + 242): goto H_FSQRT_D_D1;
        case (3 * 256 + 243): goto H_DECOY_4;
        case (3 * 256 + 244): goto H_VEC_EXT_D1;
        case (3 * 256 + 245): goto H_DECOY_10;
        case (3 * 256 + 246): goto H_DECOY_12;
        case (3 * 256 + 247): goto H_DECOY_0;
        case (3 * 256 + 248): goto H_DECOY_15;
        case (3 * 256 + 249): goto H_RET_D1;
        case (3 * 256 + 250): goto H_ROR_RI_D1;
        case (3 * 256 + 251): goto H_LOAD_64_D1;
        case (3 * 256 + 252): goto H_FUSED_MOV_ADD_RRI_D1;
        case (3 * 256 + 253): goto H_ROL_RI_D1;
        case (3 * 256 + 254): goto H_DECOY_0;
        case (3 * 256 + 255): goto H_POP_R_D1;

        default: goto EXIT_VM;
        }
    }
    START_VM_MSVC:
#endif
                                    FETCH_NEXT();
                                        #if defined(__x86_64__)
    #define PROBE_START() uint64_t _t0 = __builtin_ia32_rdtsc()
    #define PROBE_CHECK() do { uint64_t _t1 = __builtin_ia32_rdtsc(); if ((_t1 - _t0) > 50000000ULL) { ctx.reg_mask ^= 0x1337BEEF5877A5A5ULL; } } while(0)
    #elif defined(__aarch64__)
    #define PROBE_START() uint64_t _t0; __asm__ volatile("mrs %0, cntvct_el0" : "=r"(_t0))
    #define PROBE_CHECK() do { uint64_t _t1; __asm__ volatile("mrs %0, cntvct_el0" : "=r"(_t1)); if ((_t1 - _t0) > 50000000ULL) { ctx.reg_mask ^= 0x1337BEEF5877A5A5ULL; } } while(0)
    #elif defined(__riscv) || defined(__riscv__)
    #define PROBE_START() uint64_t _t0; __asm__ volatile("rdtime %0" : "=r"(_t0))
    #define PROBE_CHECK() do { uint64_t _t1; __asm__ volatile("rdtime %0" : "=r"(_t1)); if ((_t1 - _t0) > 50000000ULL) { ctx.reg_mask ^= 0x1337BEEF5877A5A5ULL; } } while(0)
    #else
    #define PROBE_START() uint64_t _t0 = 0
    #define PROBE_CHECK() do {} while(0)
    #endif

    H_NOP: { ctx.executed_instructions += 1; FETCH_NEXT(); }
    H_MOV_RR: { if (dst != src) ctx.set_reg(dst, ctx.get_reg(src)); ctx.executed_instructions++; FETCH_NEXT(); }
    H_MOV_RI: ctx.set_reg(dst, (uint64_t)(uint32_t)imm); ctx.executed_instructions++; FETCH_NEXT();
    H_MOV_HIGH: {
        uint64_t _d = ctx.get_reg(dst);
        uint64_t _hi = static_cast<uint64_t>(static_cast<uint32_t>(imm)) << 32;
        ctx.set_reg(dst, (_d & 0xFFFFFFFFULL) ^ _hi);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_NEG_RR: { PROBE_START(); ctx.set_reg(dst, 0ULL - ctx.get_reg(dst)); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_NOT_RR: { PROBE_START(); uint64_t _v = ctx.get_reg(dst); ctx.set_reg(dst, _v ^ ~0ULL); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_BSWAP_RR: {
        uint64_t _val = ctx.get_reg(src);
        uint32_t _b = static_cast<uint32_t>(imm);
        uint64_t _r = (_b == 16) ? static_cast<uint64_t>(__builtin_bswap16(static_cast<uint16_t>(_val)))
                     : ((_b == 32) ? static_cast<uint64_t>(__builtin_bswap32(static_cast<uint32_t>(_val)))
                                   : __builtin_bswap64(_val));
        ctx.set_reg(dst, _r);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_CLZ_RR: {
        uint64_t val = ctx.get_reg(src);
        uint32_t bits = (uint32_t)imm;
        uint64_t mask = (bits >= 64) ? ~0ULL : ((1ULL << bits) - 1ULL);
        uint64_t mval = val & mask;
        uint64_t res;
        if (bits <= 32) {
            uint32_t v32 = (uint32_t)mval;
            res = (v32 == 0) ? (uint64_t)bits : (uint64_t)(__builtin_clz(v32) - (32 - bits));
        } else {
            res = (mval == 0) ? 64ULL : (uint64_t)__builtin_clzll(mval);
        }
        ctx.set_reg(dst, res);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_CTZ_RR: {
        uint64_t val = ctx.get_reg(src);
        uint32_t bits = (uint32_t)imm;
        uint64_t mask = (bits >= 64) ? ~0ULL : ((1ULL << bits) - 1ULL);
        uint64_t mval = val & mask;
        uint64_t res;
        if (bits <= 32) {
            uint32_t v32 = (uint32_t)mval;
            res = (v32 == 0) ? (uint64_t)bits : (uint64_t)__builtin_ctz(v32);
        } else {
            res = (mval == 0) ? 64ULL : (uint64_t)__builtin_ctzll(mval);
        }
        ctx.set_reg(dst, res);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_POPCNT_RR: {
        uint64_t val = ctx.get_reg(src);
        uint32_t bits = (uint32_t)imm;
        uint64_t mask = (bits >= 64) ? ~0ULL : ((1ULL << bits) - 1ULL);
        uint64_t mval = val & mask;
        uint64_t res = (bits <= 32) ? (uint64_t)__builtin_popcount((uint32_t)mval) : (uint64_t)__builtin_popcountll(mval);
        ctx.set_reg(dst, res);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_RBIT_RR: {
        uint64_t val = ctx.get_reg(src);
        uint32_t bits = (uint32_t)imm;
        uint64_t res = 0;
        for (uint32_t i = 0; i < bits; ++i) {
            if ((val >> i) & 1ULL) { res |= (1ULL << (bits - 1 - i)); }
        }
        ctx.set_reg(dst, res);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_ADD_RR: { PROBE_START(); ctx.set_reg(dst, ((((((((((0x0000000000000002ULL & (ctx.get_reg(dst) | ctx.get_reg(src))) * (0x0000000000000002ULL + (ctx.get_reg(dst) | ctx.get_reg(src)))) + ((0x0000000000000002ULL & (~((ctx.get_reg(dst) | ctx.get_reg(src))))) * ((~0x0000000000000002ULL) & (ctx.get_reg(dst) | ctx.get_reg(src))))) - ((0x0000000000000002ULL & (ctx.get_reg(dst) | ctx.get_reg(src))) * (0x0000000000000002ULL & (ctx.get_reg(dst) | ctx.get_reg(src))))) - ((((ctx.get_reg(dst) + ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))) + (((ctx.get_reg(dst) & ctx.get_reg(src)) + (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - ctx.get_reg(dst))) - (((ctx.get_reg(dst) & ctx.get_reg(src)) & 0x5555555555555555ULL) + ((ctx.get_reg(dst) & ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL)))) ^ ((((ctx.get_reg(dst) + ctx.get_reg(src)) & 0x5555555555555555ULL) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) + ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL)))) + (0x0000000000000002ULL * ((((((0x0000000000000002ULL & (ctx.get_reg(dst) | ctx.get_reg(src))) * (0x0000000000000002ULL + (ctx.get_reg(dst) | ctx.get_reg(src)))) + ((0x0000000000000002ULL & (~((ctx.get_reg(dst) | ctx.get_reg(src))))) * ((~0x0000000000000002ULL) & (ctx.get_reg(dst) | ctx.get_reg(src))))) - ((0x0000000000000002ULL & (ctx.get_reg(dst) | ctx.get_reg(src))) * (0x0000000000000002ULL & (ctx.get_reg(dst) | ctx.get_reg(src))))) - ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))) & ((((ctx.get_reg(dst) + ctx.get_reg(src)) & 0x5555555555555555ULL) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) + ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL)))))) + ((((((((0x0000000000000002ULL & (ctx.get_reg(dst) | ctx.get_reg(src))) * (0x0000000000000002ULL + (ctx.get_reg(dst) | ctx.get_reg(src)))) + ((0x0000000000000002ULL & (~((ctx.get_reg(dst) | ctx.get_reg(src))))) * ((~0x0000000000000002ULL) & (ctx.get_reg(dst) | ctx.get_reg(src))))) - ((0x0000000000000002ULL & (ctx.get_reg(dst) | ctx.get_reg(src))) * (0x0000000000000002ULL & (ctx.get_reg(dst) | ctx.get_reg(src))))) - ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))) ^ ((((ctx.get_reg(dst) + ctx.get_reg(src)) & 0x5555555555555555ULL) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) + ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL)))) + (0x0000000000000002ULL * (((((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) & 0x5555555555555555ULL) - ((ctx.get_reg(dst) ^ ctx.get_reg(src)) & 0x5555555555555555ULL)) + (((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) & 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) ^ ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL))) & ((((ctx.get_reg(dst) + ctx.get_reg(src)) & 0x5555555555555555ULL) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) + ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL)))))) - (ctx.get_reg(dst) + ctx.get_reg(src)))) ^ (((((((((((0x0000000000000002ULL & (ctx.get_reg(dst) | ctx.get_reg(src))) * (0x0000000000000002ULL + (ctx.get_reg(dst) | ctx.get_reg(src)))) + ((0x0000000000000002ULL & (~((ctx.get_reg(dst) | ctx.get_reg(src))))) * ((~0x0000000000000002ULL) & (ctx.get_reg(dst) | ctx.get_reg(src))))) - ((0x0000000000000002ULL & (ctx.get_reg(dst) | ctx.get_reg(src))) * (0x0000000000000002ULL & (ctx.get_reg(dst) | ctx.get_reg(src))))) - ((((ctx.get_reg(dst) + ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))) + (((ctx.get_reg(dst) & ctx.get_reg(src)) + (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - ctx.get_reg(dst))) - (((ctx.get_reg(dst) & ctx.get_reg(src)) & 0x5555555555555555ULL) + ((ctx.get_reg(dst) & ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL)))) ^ ((((ctx.get_reg(dst) + ctx.get_reg(src)) & 0x5555555555555555ULL) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) + ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL)))) + (0x0000000000000002ULL * ((((((0x0000000000000002ULL & (ctx.get_reg(dst) | ctx.get_reg(src))) * (0x0000000000000002ULL + (ctx.get_reg(dst) | ctx.get_reg(src)))) + ((0x0000000000000002ULL & (~((ctx.get_reg(dst) | ctx.get_reg(src))))) * ((~0x0000000000000002ULL) & (ctx.get_reg(dst) | ctx.get_reg(src))))) - ((0x0000000000000002ULL & (ctx.get_reg(dst) | ctx.get_reg(src))) * (0x0000000000000002ULL & (ctx.get_reg(dst) | ctx.get_reg(src))))) - ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))) & ((((ctx.get_reg(dst) + ctx.get_reg(src)) & 0x5555555555555555ULL) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) + ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL)))))) + ((((((((0x0000000000000002ULL & (ctx.get_reg(dst) | ctx.get_reg(src))) * (0x0000000000000002ULL + (ctx.get_reg(dst) | ctx.get_reg(src)))) + ((0x0000000000000002ULL & (~((ctx.get_reg(dst) | ctx.get_reg(src))))) * ((~0x0000000000000002ULL) & (ctx.get_reg(dst) | ctx.get_reg(src))))) - ((0x0000000000000002ULL & (ctx.get_reg(dst) | ctx.get_reg(src))) * (0x0000000000000002ULL & (ctx.get_reg(dst) | ctx.get_reg(src))))) - ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))) ^ ((((ctx.get_reg(dst) + ctx.get_reg(src)) & 0x5555555555555555ULL) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) + ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL)))) + (0x0000000000000002ULL * (((((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) & 0x5555555555555555ULL) - ((ctx.get_reg(dst) ^ ctx.get_reg(src)) & 0x5555555555555555ULL)) + (((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) & 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) ^ ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL))) & ((((ctx.get_reg(dst) + ctx.get_reg(src)) & 0x5555555555555555ULL) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) + ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL)))))) - (ctx.get_reg(dst) + ctx.get_reg(src)))) & 0x000000007fffffffULL) * 0x60f4a0017ebc4577ULL) << 0x0000000000000021ULL)) ^ ((((((((((((0x0000000000000002ULL & (ctx.get_reg(dst) | ctx.get_reg(src))) * (0x0000000000000002ULL + (ctx.get_reg(dst) | ctx.get_reg(src)))) + ((0x0000000000000002ULL & (~((ctx.get_reg(dst) | ctx.get_reg(src))))) * ((~0x0000000000000002ULL) & (ctx.get_reg(dst) | ctx.get_reg(src))))) - ((0x0000000000000002ULL & (ctx.get_reg(dst) | ctx.get_reg(src))) * (0x0000000000000002ULL & (ctx.get_reg(dst) | ctx.get_reg(src))))) - ((((ctx.get_reg(dst) + ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))) + (((ctx.get_reg(dst) & ctx.get_reg(src)) + (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - ctx.get_reg(dst))) - (((ctx.get_reg(dst) & ctx.get_reg(src)) & 0x5555555555555555ULL) + ((ctx.get_reg(dst) & ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL)))) ^ ((((ctx.get_reg(dst) + ctx.get_reg(src)) & 0x5555555555555555ULL) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) + ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL)))) + (0x0000000000000002ULL * ((((((0x0000000000000002ULL & (ctx.get_reg(dst) | ctx.get_reg(src))) * (0x0000000000000002ULL + (ctx.get_reg(dst) | ctx.get_reg(src)))) + ((0x0000000000000002ULL & (~((ctx.get_reg(dst) | ctx.get_reg(src))))) * ((~0x0000000000000002ULL) & (ctx.get_reg(dst) | ctx.get_reg(src))))) - ((0x0000000000000002ULL & (ctx.get_reg(dst) | ctx.get_reg(src))) * (0x0000000000000002ULL & (ctx.get_reg(dst) | ctx.get_reg(src))))) - ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))) & ((((ctx.get_reg(dst) + ctx.get_reg(src)) & 0x5555555555555555ULL) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) + ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL)))))) + ((((((((0x0000000000000002ULL & (ctx.get_reg(dst) | ctx.get_reg(src))) * (0x0000000000000002ULL + (ctx.get_reg(dst) | ctx.get_reg(src)))) + ((0x0000000000000002ULL & (~((ctx.get_reg(dst) | ctx.get_reg(src))))) * ((~0x0000000000000002ULL) & (ctx.get_reg(dst) | ctx.get_reg(src))))) - ((0x0000000000000002ULL & (ctx.get_reg(dst) | ctx.get_reg(src))) * (0x0000000000000002ULL & (ctx.get_reg(dst) | ctx.get_reg(src))))) - ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))) ^ ((((ctx.get_reg(dst) + ctx.get_reg(src)) & 0x5555555555555555ULL) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) + ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL)))) + (0x0000000000000002ULL * (((((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) & 0x5555555555555555ULL) - ((ctx.get_reg(dst) ^ ctx.get_reg(src)) & 0x5555555555555555ULL)) + (((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) & 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) ^ ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL))) & ((((ctx.get_reg(dst) + ctx.get_reg(src)) & 0x5555555555555555ULL) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) + ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL)))))) - (ctx.get_reg(dst) + ctx.get_reg(src)))) ^ (((((((((((0x0000000000000002ULL & (ctx.get_reg(dst) | ctx.get_reg(src))) * (0x0000000000000002ULL + (ctx.get_reg(dst) | ctx.get_reg(src)))) + ((0x0000000000000002ULL & (~((ctx.get_reg(dst) | ctx.get_reg(src))))) * ((~0x0000000000000002ULL) & (ctx.get_reg(dst) | ctx.get_reg(src))))) - ((0x0000000000000002ULL & (ctx.get_reg(dst) | ctx.get_reg(src))) * (0x0000000000000002ULL & (ctx.get_reg(dst) | ctx.get_reg(src))))) - ((((ctx.get_reg(dst) + ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))) + (((ctx.get_reg(dst) & ctx.get_reg(src)) + (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - ctx.get_reg(dst))) - (((ctx.get_reg(dst) & ctx.get_reg(src)) & 0x5555555555555555ULL) + ((ctx.get_reg(dst) & ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL)))) ^ ((((ctx.get_reg(dst) + ctx.get_reg(src)) & 0x5555555555555555ULL) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) + ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL)))) + (0x0000000000000002ULL * ((((((0x0000000000000002ULL & (ctx.get_reg(dst) | ctx.get_reg(src))) * (0x0000000000000002ULL + (ctx.get_reg(dst) | ctx.get_reg(src)))) + ((0x0000000000000002ULL & (~((ctx.get_reg(dst) | ctx.get_reg(src))))) * ((~0x0000000000000002ULL) & (ctx.get_reg(dst) | ctx.get_reg(src))))) - ((0x0000000000000002ULL & (ctx.get_reg(dst) | ctx.get_reg(src))) * (0x0000000000000002ULL & (ctx.get_reg(dst) | ctx.get_reg(src))))) - ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))) & ((((ctx.get_reg(dst) + ctx.get_reg(src)) & 0x5555555555555555ULL) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) + ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL)))))) + ((((((((0x0000000000000002ULL & (ctx.get_reg(dst) | ctx.get_reg(src))) * (0x0000000000000002ULL + (ctx.get_reg(dst) | ctx.get_reg(src)))) + ((0x0000000000000002ULL & (~((ctx.get_reg(dst) | ctx.get_reg(src))))) * ((~0x0000000000000002ULL) & (ctx.get_reg(dst) | ctx.get_reg(src))))) - ((0x0000000000000002ULL & (ctx.get_reg(dst) | ctx.get_reg(src))) * (0x0000000000000002ULL & (ctx.get_reg(dst) | ctx.get_reg(src))))) - ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))) ^ ((((ctx.get_reg(dst) + ctx.get_reg(src)) & 0x5555555555555555ULL) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) + ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL)))) + (0x0000000000000002ULL * (((((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) & 0x5555555555555555ULL) - ((ctx.get_reg(dst) ^ ctx.get_reg(src)) & 0x5555555555555555ULL)) + (((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) & 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) ^ ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL))) & ((((ctx.get_reg(dst) + ctx.get_reg(src)) & 0x5555555555555555ULL) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) + ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL)))))) - (ctx.get_reg(dst) + ctx.get_reg(src)))) & 0x000000007fffffffULL) * 0x60f4a0017ebc4577ULL) << 0x0000000000000021ULL)) & 0x000000007fffffffULL) * 0x60f4a0017ebc4577ULL) << 0x0000000000000021ULL))); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_ADD_RI: { PROBE_START(); ctx.set_reg(dst, ((ctx.get_reg(dst) ^ static_cast<uint64_t>(imm)) + (0x0000000000000002ULL * (ctx.get_reg(dst) & static_cast<uint64_t>(imm))))); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_SUB_RR: { PROBE_START(); ctx.set_reg(dst, (((0x0000000000000002ULL * (((ctx.get_reg(dst) & (~ctx.get_reg(src))) - (((~ctx.get_reg(dst)) + ctx.get_reg(src)) - ((~ctx.get_reg(dst)) | ctx.get_reg(src)))) | ((0x0000000000000002ULL * ((ctx.get_reg(dst) ^ ctx.get_reg(src)) & (~(((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))))))) - ((ctx.get_reg(dst) ^ ctx.get_reg(src)) ^ ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))))))) - ((((ctx.get_reg(dst) & (~ctx.get_reg(src))) ^ (((~ctx.get_reg(dst)) + ctx.get_reg(src)) - ((~ctx.get_reg(dst)) | ctx.get_reg(src)))) - (0x0000000000000002ULL * ((~((ctx.get_reg(dst) & (~ctx.get_reg(src))))) & ((~ctx.get_reg(dst)) & ctx.get_reg(src))))) ^ ((0x0000000000000002ULL * ((ctx.get_reg(dst) ^ ctx.get_reg(src)) & (~(((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))))))) - ((ctx.get_reg(dst) ^ ctx.get_reg(src)) ^ ((0x0000000000000002ULL * ((ctx.get_reg(dst) | ctx.get_reg(src)) & (~((ctx.get_reg(dst) & ctx.get_reg(src)))))) - ((ctx.get_reg(dst) | ctx.get_reg(src)) ^ (ctx.get_reg(dst) & ctx.get_reg(src)))))))) + (((((ctx.get_reg(dst) & (~ctx.get_reg(src))) - (((~ctx.get_reg(dst)) + ctx.get_reg(src)) - ((~ctx.get_reg(dst)) | ctx.get_reg(src)))) | ((0x0000000000000002ULL * ((ctx.get_reg(dst) ^ ctx.get_reg(src)) & (~(((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))))))) - ((ctx.get_reg(dst) ^ ctx.get_reg(src)) ^ ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))))) + (((ctx.get_reg(dst) & (~ctx.get_reg(src))) - (((~ctx.get_reg(dst)) + ctx.get_reg(src)) - ((~ctx.get_reg(dst)) | ctx.get_reg(src)))) & ((0x0000000000000002ULL * ((ctx.get_reg(dst) ^ ctx.get_reg(src)) & (~(((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))))))) - ((ctx.get_reg(dst) ^ ctx.get_reg(src)) ^ ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))))))) - (ctx.get_reg(dst) - ctx.get_reg(src))))); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_SUB_RI: { PROBE_START(); uint64_t _d = ctx.get_reg(dst); ctx.set_reg(dst, (_d - static_cast<uint64_t>(imm))); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_IMUL_RR: {
        PROBE_START();
        ctx.set_reg(dst, static_cast<uint64_t>(static_cast<int64_t>(ctx.get_reg(dst)) * static_cast<int64_t>(ctx.get_reg(src))));
        PROBE_CHECK();
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_IMUL_RI: {
        PROBE_START();
        ctx.set_reg(dst, static_cast<uint64_t>(static_cast<int64_t>(ctx.get_reg(dst)) * imm));
        PROBE_CHECK();
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_XOR_RR: { PROBE_START(); ctx.set_reg(dst, ((((((ctx.get_reg(dst) ^ ctx.get_reg(src)) ^ (((((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) & (~((ctx.get_reg(dst) + ctx.get_reg(src))))) - ((~(((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))))) & (ctx.get_reg(dst) + ctx.get_reg(src)))) + ((((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) ^ (ctx.get_reg(dst) + ctx.get_reg(src))) - ((((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) | (ctx.get_reg(dst) + ctx.get_reg(src))) - (((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) & (ctx.get_reg(dst) + ctx.get_reg(src))))))) + (0x0000000000000002ULL * ((ctx.get_reg(dst) ^ ctx.get_reg(src)) & (((((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) & (~((ctx.get_reg(dst) + ctx.get_reg(src))))) - ((~(((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))))) & (ctx.get_reg(dst) + ctx.get_reg(src)))) + ((((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) ^ (ctx.get_reg(dst) + ctx.get_reg(src))) - ((((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) | (ctx.get_reg(dst) + ctx.get_reg(src))) - (((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) & (ctx.get_reg(dst) + ctx.get_reg(src))))))))) + ((((ctx.get_reg(dst) ^ ctx.get_reg(src)) ^ (((((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) & (~((ctx.get_reg(dst) + ctx.get_reg(src))))) - ((~(((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))))) & (ctx.get_reg(dst) + ctx.get_reg(src)))) + ((((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) ^ (ctx.get_reg(dst) + ctx.get_reg(src))) - ((((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) | (ctx.get_reg(dst) + ctx.get_reg(src))) - (((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) & (ctx.get_reg(dst) + ctx.get_reg(src))))))) + (0x0000000000000002ULL * ((ctx.get_reg(dst) ^ ctx.get_reg(src)) & (((((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) & (~((ctx.get_reg(dst) + ctx.get_reg(src))))) - ((~(((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))))) & (ctx.get_reg(dst) + ctx.get_reg(src)))) + ((((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) ^ (ctx.get_reg(dst) + ctx.get_reg(src))) - ((((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) | (ctx.get_reg(dst) + ctx.get_reg(src))) - (((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) & (ctx.get_reg(dst) + ctx.get_reg(src))))))))) - (ctx.get_reg(dst) ^ ctx.get_reg(src)))) ^ (((((((ctx.get_reg(dst) ^ ctx.get_reg(src)) ^ (((((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) & (~((ctx.get_reg(dst) + ctx.get_reg(src))))) - ((~(((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))))) & (ctx.get_reg(dst) + ctx.get_reg(src)))) + ((((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) ^ (ctx.get_reg(dst) + ctx.get_reg(src))) - ((((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) | (ctx.get_reg(dst) + ctx.get_reg(src))) - (((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) & (ctx.get_reg(dst) + ctx.get_reg(src))))))) + (0x0000000000000002ULL * ((ctx.get_reg(dst) ^ ctx.get_reg(src)) & (((((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) & (~((ctx.get_reg(dst) + ctx.get_reg(src))))) - ((~(((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))))) & (ctx.get_reg(dst) + ctx.get_reg(src)))) + ((((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) ^ (ctx.get_reg(dst) + ctx.get_reg(src))) - ((((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) | (ctx.get_reg(dst) + ctx.get_reg(src))) - (((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) & (ctx.get_reg(dst) + ctx.get_reg(src))))))))) + ((((ctx.get_reg(dst) ^ ctx.get_reg(src)) ^ (((((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) & (~((ctx.get_reg(dst) + ctx.get_reg(src))))) - ((~(((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))))) & (ctx.get_reg(dst) + ctx.get_reg(src)))) + ((((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) ^ (ctx.get_reg(dst) + ctx.get_reg(src))) - ((((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) | (ctx.get_reg(dst) + ctx.get_reg(src))) - (((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) & (ctx.get_reg(dst) + ctx.get_reg(src))))))) + (0x0000000000000002ULL * ((ctx.get_reg(dst) ^ ctx.get_reg(src)) & (((((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) & (~((ctx.get_reg(dst) + ctx.get_reg(src))))) - ((~(((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))))) & (ctx.get_reg(dst) + ctx.get_reg(src)))) + ((((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) ^ (ctx.get_reg(dst) + ctx.get_reg(src))) - ((((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) | (ctx.get_reg(dst) + ctx.get_reg(src))) - (((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) & (ctx.get_reg(dst) + ctx.get_reg(src))))))))) - (ctx.get_reg(dst) ^ ctx.get_reg(src)))) & 0x000000007fffffffULL) * 0x7f464604990176e3ULL) << 0x0000000000000021ULL)) ^ ((((((((ctx.get_reg(dst) ^ ctx.get_reg(src)) ^ (((((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) & (~((ctx.get_reg(dst) + ctx.get_reg(src))))) - ((~(((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))))) & (ctx.get_reg(dst) + ctx.get_reg(src)))) + ((((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) ^ (ctx.get_reg(dst) + ctx.get_reg(src))) - ((((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) | (ctx.get_reg(dst) + ctx.get_reg(src))) - (((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) & (ctx.get_reg(dst) + ctx.get_reg(src))))))) + (0x0000000000000002ULL * ((ctx.get_reg(dst) ^ ctx.get_reg(src)) & (((((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) & (~((ctx.get_reg(dst) + ctx.get_reg(src))))) - ((~(((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))))) & (ctx.get_reg(dst) + ctx.get_reg(src)))) + ((((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) ^ (ctx.get_reg(dst) + ctx.get_reg(src))) - ((((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) | (ctx.get_reg(dst) + ctx.get_reg(src))) - (((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) & (ctx.get_reg(dst) + ctx.get_reg(src))))))))) + ((((ctx.get_reg(dst) ^ ctx.get_reg(src)) ^ (((((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) & (~((ctx.get_reg(dst) + ctx.get_reg(src))))) - ((~(((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))))) & (ctx.get_reg(dst) + ctx.get_reg(src)))) + ((((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) ^ (ctx.get_reg(dst) + ctx.get_reg(src))) - ((((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) | (ctx.get_reg(dst) + ctx.get_reg(src))) - (((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) & (ctx.get_reg(dst) + ctx.get_reg(src))))))) + (0x0000000000000002ULL * ((ctx.get_reg(dst) ^ ctx.get_reg(src)) & (((((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) & (~((ctx.get_reg(dst) + ctx.get_reg(src))))) - ((~(((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))))) & (ctx.get_reg(dst) + ctx.get_reg(src)))) + ((((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) ^ (ctx.get_reg(dst) + ctx.get_reg(src))) - ((((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) | (ctx.get_reg(dst) + ctx.get_reg(src))) - (((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) & (ctx.get_reg(dst) + ctx.get_reg(src))))))))) - (ctx.get_reg(dst) ^ ctx.get_reg(src)))) ^ (((((((ctx.get_reg(dst) ^ ctx.get_reg(src)) ^ (((((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) & (~((ctx.get_reg(dst) + ctx.get_reg(src))))) - ((~(((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))))) & (ctx.get_reg(dst) + ctx.get_reg(src)))) + ((((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) ^ (ctx.get_reg(dst) + ctx.get_reg(src))) - ((((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) | (ctx.get_reg(dst) + ctx.get_reg(src))) - (((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) & (ctx.get_reg(dst) + ctx.get_reg(src))))))) + (0x0000000000000002ULL * ((ctx.get_reg(dst) ^ ctx.get_reg(src)) & (((((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) & (~((ctx.get_reg(dst) + ctx.get_reg(src))))) - ((~(((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))))) & (ctx.get_reg(dst) + ctx.get_reg(src)))) + ((((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) ^ (ctx.get_reg(dst) + ctx.get_reg(src))) - ((((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) | (ctx.get_reg(dst) + ctx.get_reg(src))) - (((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) & (ctx.get_reg(dst) + ctx.get_reg(src))))))))) + ((((ctx.get_reg(dst) ^ ctx.get_reg(src)) ^ (((((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) & (~((ctx.get_reg(dst) + ctx.get_reg(src))))) - ((~(((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))))) & (ctx.get_reg(dst) + ctx.get_reg(src)))) + ((((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) ^ (ctx.get_reg(dst) + ctx.get_reg(src))) - ((((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) | (ctx.get_reg(dst) + ctx.get_reg(src))) - (((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) & (ctx.get_reg(dst) + ctx.get_reg(src))))))) + (0x0000000000000002ULL * ((ctx.get_reg(dst) ^ ctx.get_reg(src)) & (((((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) & (~((ctx.get_reg(dst) + ctx.get_reg(src))))) - ((~(((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))))) & (ctx.get_reg(dst) + ctx.get_reg(src)))) + ((((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) ^ (ctx.get_reg(dst) + ctx.get_reg(src))) - ((((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) | (ctx.get_reg(dst) + ctx.get_reg(src))) - (((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) & (ctx.get_reg(dst) + ctx.get_reg(src))))))))) - (ctx.get_reg(dst) ^ ctx.get_reg(src)))) & 0x000000007fffffffULL) * 0x7f464604990176e3ULL) << 0x0000000000000021ULL)) & 0x000000007fffffffULL) * 0x7f464604990176e3ULL) << 0x0000000000000021ULL))); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_XOR_RI: { PROBE_START(); ctx.set_reg(dst, ((ctx.get_reg(dst) | static_cast<uint64_t>(imm)) - (ctx.get_reg(dst) & static_cast<uint64_t>(imm)))); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_AND_RR: { PROBE_START(); ctx.set_reg(dst, ((((((0x0000000000000002ULL * (ctx.get_reg(dst) & (~((ctx.get_reg(dst) & (~ctx.get_reg(src))))))) - (ctx.get_reg(dst) ^ ((ctx.get_reg(dst) - (ctx.get_reg(dst) & (~((~ctx.get_reg(src)))))) + ((ctx.get_reg(dst) ^ (~ctx.get_reg(src))) - ((ctx.get_reg(dst) | (~ctx.get_reg(src))) - (ctx.get_reg(dst) & (~ctx.get_reg(src)))))))) ^ (((((0x0000000000000002ULL * ((ctx.get_reg(dst) | ctx.get_reg(src)) & (~((ctx.get_reg(dst) & ctx.get_reg(src)))))) - ((ctx.get_reg(dst) | ctx.get_reg(src)) ^ (ctx.get_reg(dst) & ctx.get_reg(src)))) & 0x5555555555555555ULL) - (((0x0000000000000002ULL * ((ctx.get_reg(dst) | ctx.get_reg(src)) & (~((ctx.get_reg(dst) & ctx.get_reg(src)))))) - ((ctx.get_reg(dst) | ctx.get_reg(src)) ^ (ctx.get_reg(dst) & ctx.get_reg(src)))) & 0x5555555555555555ULL)) + ((((0x0000000000000002ULL * ((ctx.get_reg(dst) | ctx.get_reg(src)) & (~((ctx.get_reg(dst) & ctx.get_reg(src)))))) - ((ctx.get_reg(dst) | ctx.get_reg(src)) ^ (ctx.get_reg(dst) & ctx.get_reg(src)))) & 0xaaaaaaaaaaaaaaaaULL) - (((0x0000000000000002ULL * ((ctx.get_reg(dst) | ctx.get_reg(src)) & (~((ctx.get_reg(dst) & ctx.get_reg(src)))))) - ((ctx.get_reg(dst) | ctx.get_reg(src)) ^ (ctx.get_reg(dst) & ctx.get_reg(src)))) & 0xaaaaaaaaaaaaaaaaULL)))) + (0x0000000000000002ULL * (((0x0000000000000002ULL * (ctx.get_reg(dst) & (~((ctx.get_reg(dst) & (~ctx.get_reg(src))))))) - (ctx.get_reg(dst) ^ ((ctx.get_reg(dst) - (ctx.get_reg(dst) & (~((~ctx.get_reg(src)))))) + ((ctx.get_reg(dst) ^ (~ctx.get_reg(src))) - ((ctx.get_reg(dst) | (~ctx.get_reg(src))) - (ctx.get_reg(dst) & (~ctx.get_reg(src)))))))) & ((0x0000000000000002ULL * ((ctx.get_reg(dst) ^ ctx.get_reg(src)) & (~((ctx.get_reg(dst) ^ ctx.get_reg(src)))))) - (((0x0000000000000002ULL * ((ctx.get_reg(dst) | ctx.get_reg(src)) & (~((ctx.get_reg(dst) & ctx.get_reg(src)))))) - ((ctx.get_reg(dst) | ctx.get_reg(src)) ^ (ctx.get_reg(dst) & ctx.get_reg(src)))) ^ ((0x0000000000000002ULL * ((ctx.get_reg(dst) | ctx.get_reg(src)) & (~((ctx.get_reg(dst) & ctx.get_reg(src)))))) - ((ctx.get_reg(dst) | ctx.get_reg(src)) ^ (ctx.get_reg(dst) & ctx.get_reg(src))))))))) ^ (((((((0x0000000000000002ULL * (ctx.get_reg(dst) & (~((ctx.get_reg(dst) & (~ctx.get_reg(src))))))) - (ctx.get_reg(dst) ^ ((ctx.get_reg(dst) - (ctx.get_reg(dst) & (~((~ctx.get_reg(src)))))) + ((ctx.get_reg(dst) ^ (~ctx.get_reg(src))) - ((ctx.get_reg(dst) | (~ctx.get_reg(src))) - (ctx.get_reg(dst) & (~ctx.get_reg(src)))))))) ^ (((((0x0000000000000002ULL * ((ctx.get_reg(dst) | ctx.get_reg(src)) & (~((ctx.get_reg(dst) & ctx.get_reg(src)))))) - ((ctx.get_reg(dst) | ctx.get_reg(src)) ^ (ctx.get_reg(dst) & ctx.get_reg(src)))) & 0x5555555555555555ULL) - (((0x0000000000000002ULL * ((ctx.get_reg(dst) | ctx.get_reg(src)) & (~((ctx.get_reg(dst) & ctx.get_reg(src)))))) - ((ctx.get_reg(dst) | ctx.get_reg(src)) ^ (ctx.get_reg(dst) & ctx.get_reg(src)))) & 0x5555555555555555ULL)) + ((((0x0000000000000002ULL * ((ctx.get_reg(dst) | ctx.get_reg(src)) & (~((ctx.get_reg(dst) & ctx.get_reg(src)))))) - ((ctx.get_reg(dst) | ctx.get_reg(src)) ^ (ctx.get_reg(dst) & ctx.get_reg(src)))) & 0xaaaaaaaaaaaaaaaaULL) - (((0x0000000000000002ULL * ((ctx.get_reg(dst) | ctx.get_reg(src)) & (~((ctx.get_reg(dst) & ctx.get_reg(src)))))) - ((ctx.get_reg(dst) | ctx.get_reg(src)) ^ (ctx.get_reg(dst) & ctx.get_reg(src)))) & 0xaaaaaaaaaaaaaaaaULL)))) + (0x0000000000000002ULL * (((0x0000000000000002ULL * (ctx.get_reg(dst) & (~((ctx.get_reg(dst) & (~ctx.get_reg(src))))))) - (ctx.get_reg(dst) ^ ((ctx.get_reg(dst) - (ctx.get_reg(dst) & (~((~ctx.get_reg(src)))))) + ((ctx.get_reg(dst) ^ (~ctx.get_reg(src))) - ((ctx.get_reg(dst) | (~ctx.get_reg(src))) - (ctx.get_reg(dst) & (~ctx.get_reg(src)))))))) & ((0x0000000000000002ULL * ((ctx.get_reg(dst) ^ ctx.get_reg(src)) & (~((ctx.get_reg(dst) ^ ctx.get_reg(src)))))) - (((0x0000000000000002ULL * ((ctx.get_reg(dst) | ctx.get_reg(src)) & (~((ctx.get_reg(dst) & ctx.get_reg(src)))))) - ((ctx.get_reg(dst) | ctx.get_reg(src)) ^ (ctx.get_reg(dst) & ctx.get_reg(src)))) ^ ((0x0000000000000002ULL * ((ctx.get_reg(dst) | ctx.get_reg(src)) & (~((ctx.get_reg(dst) & ctx.get_reg(src)))))) - ((ctx.get_reg(dst) | ctx.get_reg(src)) ^ (ctx.get_reg(dst) & ctx.get_reg(src))))))))) & 0x000000007fffffffULL) * 0x4ecbc959e9d94971ULL) << 0x0000000000000021ULL)) ^ ((((((((0x0000000000000002ULL * (ctx.get_reg(dst) & (~((ctx.get_reg(dst) & (~ctx.get_reg(src))))))) - (ctx.get_reg(dst) ^ ((ctx.get_reg(dst) - (ctx.get_reg(dst) & (~((~ctx.get_reg(src)))))) + ((ctx.get_reg(dst) ^ (~ctx.get_reg(src))) - ((ctx.get_reg(dst) | (~ctx.get_reg(src))) - (ctx.get_reg(dst) & (~ctx.get_reg(src)))))))) ^ (((((0x0000000000000002ULL * ((ctx.get_reg(dst) | ctx.get_reg(src)) & (~((ctx.get_reg(dst) & ctx.get_reg(src)))))) - ((ctx.get_reg(dst) | ctx.get_reg(src)) ^ (ctx.get_reg(dst) & ctx.get_reg(src)))) & 0x5555555555555555ULL) - (((0x0000000000000002ULL * ((ctx.get_reg(dst) | ctx.get_reg(src)) & (~((ctx.get_reg(dst) & ctx.get_reg(src)))))) - ((ctx.get_reg(dst) | ctx.get_reg(src)) ^ (ctx.get_reg(dst) & ctx.get_reg(src)))) & 0x5555555555555555ULL)) + ((((0x0000000000000002ULL * ((ctx.get_reg(dst) | ctx.get_reg(src)) & (~((ctx.get_reg(dst) & ctx.get_reg(src)))))) - ((ctx.get_reg(dst) | ctx.get_reg(src)) ^ (ctx.get_reg(dst) & ctx.get_reg(src)))) & 0xaaaaaaaaaaaaaaaaULL) - (((0x0000000000000002ULL * ((ctx.get_reg(dst) | ctx.get_reg(src)) & (~((ctx.get_reg(dst) & ctx.get_reg(src)))))) - ((ctx.get_reg(dst) | ctx.get_reg(src)) ^ (ctx.get_reg(dst) & ctx.get_reg(src)))) & 0xaaaaaaaaaaaaaaaaULL)))) + (0x0000000000000002ULL * (((0x0000000000000002ULL * (ctx.get_reg(dst) & (~((ctx.get_reg(dst) & (~ctx.get_reg(src))))))) - (ctx.get_reg(dst) ^ ((ctx.get_reg(dst) - (ctx.get_reg(dst) & (~((~ctx.get_reg(src)))))) + ((ctx.get_reg(dst) ^ (~ctx.get_reg(src))) - ((ctx.get_reg(dst) | (~ctx.get_reg(src))) - (ctx.get_reg(dst) & (~ctx.get_reg(src)))))))) & ((0x0000000000000002ULL * ((ctx.get_reg(dst) ^ ctx.get_reg(src)) & (~((ctx.get_reg(dst) ^ ctx.get_reg(src)))))) - (((0x0000000000000002ULL * ((ctx.get_reg(dst) | ctx.get_reg(src)) & (~((ctx.get_reg(dst) & ctx.get_reg(src)))))) - ((ctx.get_reg(dst) | ctx.get_reg(src)) ^ (ctx.get_reg(dst) & ctx.get_reg(src)))) ^ ((0x0000000000000002ULL * ((ctx.get_reg(dst) | ctx.get_reg(src)) & (~((ctx.get_reg(dst) & ctx.get_reg(src)))))) - ((ctx.get_reg(dst) | ctx.get_reg(src)) ^ (ctx.get_reg(dst) & ctx.get_reg(src))))))))) ^ (((((((0x0000000000000002ULL * (ctx.get_reg(dst) & (~((ctx.get_reg(dst) & (~ctx.get_reg(src))))))) - (ctx.get_reg(dst) ^ ((ctx.get_reg(dst) - (ctx.get_reg(dst) & (~((~ctx.get_reg(src)))))) + ((ctx.get_reg(dst) ^ (~ctx.get_reg(src))) - ((ctx.get_reg(dst) | (~ctx.get_reg(src))) - (ctx.get_reg(dst) & (~ctx.get_reg(src)))))))) ^ (((((0x0000000000000002ULL * ((ctx.get_reg(dst) | ctx.get_reg(src)) & (~((ctx.get_reg(dst) & ctx.get_reg(src)))))) - ((ctx.get_reg(dst) | ctx.get_reg(src)) ^ (ctx.get_reg(dst) & ctx.get_reg(src)))) & 0x5555555555555555ULL) - (((0x0000000000000002ULL * ((ctx.get_reg(dst) | ctx.get_reg(src)) & (~((ctx.get_reg(dst) & ctx.get_reg(src)))))) - ((ctx.get_reg(dst) | ctx.get_reg(src)) ^ (ctx.get_reg(dst) & ctx.get_reg(src)))) & 0x5555555555555555ULL)) + ((((0x0000000000000002ULL * ((ctx.get_reg(dst) | ctx.get_reg(src)) & (~((ctx.get_reg(dst) & ctx.get_reg(src)))))) - ((ctx.get_reg(dst) | ctx.get_reg(src)) ^ (ctx.get_reg(dst) & ctx.get_reg(src)))) & 0xaaaaaaaaaaaaaaaaULL) - (((0x0000000000000002ULL * ((ctx.get_reg(dst) | ctx.get_reg(src)) & (~((ctx.get_reg(dst) & ctx.get_reg(src)))))) - ((ctx.get_reg(dst) | ctx.get_reg(src)) ^ (ctx.get_reg(dst) & ctx.get_reg(src)))) & 0xaaaaaaaaaaaaaaaaULL)))) + (0x0000000000000002ULL * (((0x0000000000000002ULL * (ctx.get_reg(dst) & (~((ctx.get_reg(dst) & (~ctx.get_reg(src))))))) - (ctx.get_reg(dst) ^ ((ctx.get_reg(dst) - (ctx.get_reg(dst) & (~((~ctx.get_reg(src)))))) + ((ctx.get_reg(dst) ^ (~ctx.get_reg(src))) - ((ctx.get_reg(dst) | (~ctx.get_reg(src))) - (ctx.get_reg(dst) & (~ctx.get_reg(src)))))))) & ((0x0000000000000002ULL * ((ctx.get_reg(dst) ^ ctx.get_reg(src)) & (~((ctx.get_reg(dst) ^ ctx.get_reg(src)))))) - (((0x0000000000000002ULL * ((ctx.get_reg(dst) | ctx.get_reg(src)) & (~((ctx.get_reg(dst) & ctx.get_reg(src)))))) - ((ctx.get_reg(dst) | ctx.get_reg(src)) ^ (ctx.get_reg(dst) & ctx.get_reg(src)))) ^ ((0x0000000000000002ULL * ((ctx.get_reg(dst) | ctx.get_reg(src)) & (~((ctx.get_reg(dst) & ctx.get_reg(src)))))) - ((ctx.get_reg(dst) | ctx.get_reg(src)) ^ (ctx.get_reg(dst) & ctx.get_reg(src))))))))) & 0x000000007fffffffULL) * 0x4ecbc959e9d94971ULL) << 0x0000000000000021ULL)) & 0x000000007fffffffULL) * 0x4ecbc959e9d94971ULL) << 0x0000000000000021ULL))); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_AND_RI: { PROBE_START(); ctx.set_reg(dst, (((0x3009a0de16c2ab5cULL * (ctx.get_reg(dst) ^ static_cast<uint64_t>(imm))) + (0x3009a0de16c2ab5dULL * (ctx.get_reg(dst) & static_cast<uint64_t>(imm)))) + (0xcff65f21e93d54a4ULL * (ctx.get_reg(dst) | static_cast<uint64_t>(imm))))); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_OR_RR: { PROBE_START(); ctx.set_reg(dst, (((((((ctx.get_reg(dst) + 0x5555555555555555ULL) - (ctx.get_reg(dst) | 0x5555555555555555ULL)) + ((ctx.get_reg(src) + 0x5555555555555555ULL) - (ctx.get_reg(src) | 0x5555555555555555ULL))) - (((ctx.get_reg(dst) + 0x5555555555555555ULL) - (ctx.get_reg(dst) | 0x5555555555555555ULL)) & ((ctx.get_reg(src) + 0x5555555555555555ULL) - (ctx.get_reg(src) | 0x5555555555555555ULL)))) & 0x5555555555555555ULL) + (((((ctx.get_reg(dst) - (ctx.get_reg(dst) & (~0xaaaaaaaaaaaaaaaaULL))) + ((ctx.get_reg(dst) ^ 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) | 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL)))) ^ (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL)) + (((ctx.get_reg(dst) - (ctx.get_reg(dst) & (~0xaaaaaaaaaaaaaaaaULL))) + ((ctx.get_reg(dst) ^ 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) | 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL)))) & (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))) & 0x5555555555555555ULL)) + ((((((ctx.get_reg(dst) + 0x5555555555555555ULL) - (ctx.get_reg(dst) | 0x5555555555555555ULL)) + ((ctx.get_reg(src) + 0x5555555555555555ULL) - (ctx.get_reg(src) | 0x5555555555555555ULL))) - (((ctx.get_reg(dst) + 0x5555555555555555ULL) - (ctx.get_reg(dst) | 0x5555555555555555ULL)) & ((ctx.get_reg(src) + 0x5555555555555555ULL) - (ctx.get_reg(src) | 0x5555555555555555ULL)))) & 0xaaaaaaaaaaaaaaaaULL) + (((((ctx.get_reg(dst) - (ctx.get_reg(dst) & (~0xaaaaaaaaaaaaaaaaULL))) + ((ctx.get_reg(dst) ^ 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) | 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL)))) ^ (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL)) + (((ctx.get_reg(dst) - (ctx.get_reg(dst) & (~0xaaaaaaaaaaaaaaaaULL))) + ((ctx.get_reg(dst) ^ 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) | 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL)))) & (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))) & 0xaaaaaaaaaaaaaaaaULL)))); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_OR_RI: { PROBE_START(); ctx.set_reg(dst, (((((0x5b1bd05b7a8f5924ULL * (ctx.get_reg(dst) ^ static_cast<uint64_t>(imm))) + (0x5b1bd05b7a8f5924ULL * (ctx.get_reg(dst) & static_cast<uint64_t>(imm)))) + (0xa4e42fa48570a6ddULL * (ctx.get_reg(dst) | static_cast<uint64_t>(imm)))) + 0xe5ae13c386cbb5c2ULL) - 0xe5ae13c386cbb5c2ULL)); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_ROL_RI: {
        uint64_t val = ctx.get_reg(dst); uint32_t shift = (uint32_t)(imm & 63);
        ctx.set_reg(dst, (val << shift) | (val >> ((64 - shift) & 63)));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_ROR_RI: {
        uint64_t val = ctx.get_reg(dst); uint32_t shift = (uint32_t)(imm & 63);
        uint64_t _res = (val >> shift) | (val << ((64 - shift) & 63));
        ctx.set_reg(dst, _res);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_SHL_RI: {
        uint64_t v = ctx.get_reg(dst); uint32_t s = static_cast<uint32_t>(imm & 63);
        ctx.set_reg(dst, v << s);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_SHR_RI: {
        uint64_t v = ctx.get_reg(dst); uint32_t s = static_cast<uint32_t>(imm & 63);
        ctx.set_reg(dst, v >> s);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_SAR_RI: {
        uint64_t val = ctx.get_reg(dst); uint32_t shift = (uint32_t)(imm & 63);
        ctx.set_reg(dst, (uint64_t)((int64_t)val >> shift));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_ROL_RR: {
        uint64_t v = ctx.get_reg(dst); uint32_t s = (uint32_t)(ctx.get_reg(src) & 63);
        ctx.set_reg(dst, (v << s) | (v >> ((64 - s) & 63)));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_ROR_RR: {
        uint64_t val = ctx.get_reg(dst); uint32_t shift = (uint32_t)(ctx.get_reg(src) & 63);
        ctx.set_reg(dst, (val >> shift) | (val << ((64 - shift) & 63)));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_SHL_RR: {
        uint64_t val = ctx.get_reg(dst); uint32_t shift = (uint32_t)(ctx.get_reg(src) & 63);
        ctx.set_reg(dst, val << shift);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_SHR_RR: {
        uint64_t v = ctx.get_reg(dst); uint32_t s = static_cast<uint32_t>(ctx.get_reg(src) & 63);
        ctx.set_reg(dst, v >> s);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_SAR_RR: {
        uint64_t val = ctx.get_reg(dst); uint32_t shift = (uint32_t)(ctx.get_reg(src) & 63);
        ctx.set_reg(dst, (uint64_t)((int64_t)val >> shift));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_DIV_RR: {
        uint64_t a = ctx.get_reg(dst); uint64_t b = ctx.get_reg(src);
        if (b == 0) { ctx.trapped = true; goto EXIT_VM; }
        ctx.set_reg(dst, a / b);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_IDIV_RR: {
        int64_t _d = static_cast<int64_t>(ctx.get_reg(dst)), _s = static_cast<int64_t>(ctx.get_reg(src));
        if (_s == 0 || (_s == -1 && _d == INT64_MIN)) { ctx.trapped = true; goto EXIT_VM; }
        int64_t _quot = (_s == -1) ? (-_d) : (_d / _s);
        ctx.set_reg(dst, static_cast<uint64_t>(_quot));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_MULH_RR: {
        #if defined(__SIZEOF_INT128__)
        uint64_t res = (uint64_t)(((unsigned __int128)ctx.get_reg(dst) * (unsigned __int128)ctx.get_reg(src)) >> 64);
        #else
        uint64_t a = ctx.get_reg(dst); uint64_t b = ctx.get_reg(src);
        uint64_t a_lo = (uint32_t)a, a_hi = a >> 32;
        uint64_t b_lo = (uint32_t)b, b_hi = b >> 32;
        uint64_t cy = (((a_lo * b_lo) >> 32) + (uint32_t)(a_lo * b_hi) + (uint32_t)(a_hi * b_lo)) >> 32;
        uint64_t res = (a_hi * b_hi) + ((a_lo * b_hi) >> 32) + ((a_hi * b_lo) >> 32) + cy;
        #endif
        ctx.set_reg(dst, res);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_IMULH_RR: {
        int64_t a = (int64_t)ctx.get_reg(dst); int64_t b = (int64_t)ctx.get_reg(src);
        #if defined(__SIZEOF_INT128__)
        signed __int128 _prod = (signed __int128)a * (signed __int128)b;
        uint64_t res = static_cast<uint64_t>(_prod >> 64);
        #else
        uint64_t ua = (uint64_t)a, ub = (uint64_t)b;
        uint64_t a_lo = (uint32_t)ua, a_hi = ua >> 32;
        uint64_t b_lo = (uint32_t)ub, b_hi = ub >> 32;
        uint64_t p0 = a_lo * b_lo, p1 = a_lo * b_hi, p2 = a_hi * b_lo, p3 = a_hi * b_hi;
        uint64_t cy = ((p0 >> 32) + (uint32_t)p1 + (uint32_t)p2) >> 32;
        uint64_t res = p3 + (p1 >> 32) + (p2 >> 32) + cy;
        if (a < 0) res -= ub;
        if (b < 0) res -= ua;
        #endif
        ctx.set_reg(dst, res);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_CMP_RI: {
        PROBE_START();
        uint64_t a = ctx.get_reg(dst); uint64_t b = (uint64_t)imm;
        uint32_t bits = (uint32_t)((word >> 50) & 0x7F);
        compute_sub_flags(ctx, a, b, bits);
        PROBE_CHECK();
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_CMP_RR: {
        PROBE_START();
        uint64_t a = ctx.get_reg(dst); uint64_t b = ctx.get_reg(src);
        uint32_t bits = (uint32_t)((word >> 50) & 0x7F);
        compute_sub_flags(ctx, a, b, bits);
        PROBE_CHECK();
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_PUSH_R: {
        uint64_t val = ctx.get_reg(dst);
        ctx.push(val);
        uint64_t cur_sp = ctx.get_reg(REG_RSP);
        if (cur_sp >= 0x10008ULL && cur_sp <= 0x7FFFFFFFFFFFULL) {
            uint64_t* sp_ptr = reinterpret_cast<uint64_t*>(cur_sp - 8ULL);
            ctx.set_reg(REG_RSP, reinterpret_cast<uint64_t>(sp_ptr));
            *sp_ptr = val;
        }
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_POP_R: {
        uint64_t cur_sp = ctx.get_reg(REG_RSP);
        uint64_t val = 0;
        if (cur_sp >= 0x10000ULL && cur_sp <= 0x7FFFFFFFFFFFULL) {
            const uint64_t* sp_ptr = reinterpret_cast<const uint64_t*>(cur_sp);
            val = *sp_ptr;
            ctx.set_reg(REG_RSP, cur_sp + sizeof(uint64_t));
            ctx.pop();
        } else {
            val = ctx.pop();
        }
        ctx.set_reg(dst, val);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_ADC_RR: {
        uint64_t a = ctx.get_reg(dst); uint64_t b = ctx.get_reg(src);
        uint64_t c = static_cast<uint64_t>(ctx.cf);
        uint64_t res = (a + b) + c;
        ctx.cf = (res < a) || (c && res == a);
        ctx.zf = (res == 0);
        ctx.sf = (res >> 63) != 0;
        ctx.of = (((a ^ res) & (b ^ res)) >> 63) != 0;
        ctx.set_reg(dst, res);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_ADC_RI: {
        uint64_t a = ctx.get_reg(dst); uint64_t b = (uint64_t)imm;
        uint64_t c = ctx.cf ? 1ULL : 0ULL;
        uint64_t res = a + b + c;
        ctx.cf = (res < a) || (c && res == a);
        ctx.of = ((((a ^ res) & (b ^ res)) >> 63) != 0);
        ctx.zf = (res == 0);
        ctx.sf = ((int64_t)res < 0);
        ctx.set_reg(dst, res);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_SBB_RR: {
        uint64_t a = ctx.get_reg(dst); uint64_t b = ctx.get_reg(src);
        uint64_t borrow = ctx.cf ? 1ULL : 0ULL;
        uint64_t res = a - (b + borrow);
        ctx.cf = (a < b) || (borrow && a == b);
        ctx.of = ((((a ^ b) & (a ^ res)) >> 63) != 0);
        ctx.zf = (res == 0);
        ctx.sf = ((int64_t)res < 0);
        ctx.set_reg(dst, res);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_SBB_RI: {
        uint64_t a = ctx.get_reg(dst); uint64_t b = (uint64_t)imm;
        uint64_t borrow = ctx.cf ? 1ULL : 0ULL;
        uint64_t res = a - (b + borrow);
        ctx.cf = (a < b) || (borrow && a == b);
        ctx.of = ((((a ^ b) & (a ^ res)) >> 63) != 0);
        ctx.zf = (res == 0);
        ctx.sf = ((int64_t)res < 0);
        ctx.set_reg(dst, res);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_CCMP_RR: {
        uint8_t cond = (uint8_t)((((word >> 18) + 0x0FULL) - ((word >> 18) | 0x0FULL)));
        uint8_t nzcv = (uint8_t)((((word >> 22) + 0x0FULL) - ((word >> 22) | 0x0FULL)));
        uint32_t bits = (uint32_t)((((word >> 50) + 0x7FULL) - ((word >> 50) | 0x7FULL)));
        if (eval_condition(ctx, cond)) {
            uint64_t a = ctx.get_reg(dst); uint64_t b = ctx.get_reg(src);
            compute_sub_flags(ctx, a, b, bits);
        } else {
            ctx.sf = (nzcv & 8) != 0;
            ctx.zf = (nzcv & 4) != 0;
            ctx.cf = (nzcv & 2) != 0;
            ctx.of = (nzcv & 1) != 0;
        }
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_CCMP_RI: {
        uint8_t cond = (uint8_t)((((word >> 18) + 0x0FULL) - ((word >> 18) | 0x0FULL)));
        uint8_t nzcv = (uint8_t)((((word >> 22) + 0x0FULL) - ((word >> 22) | 0x0FULL)));
        uint64_t b = (uint64_t)((((word >> 26) + 0x1FULL) - ((word >> 26) | 0x1FULL)));
        uint32_t bits = (uint32_t)((((word >> 50) + 0x7FULL) - ((word >> 50) | 0x7FULL)));
        if (eval_condition(ctx, cond)) {
            uint64_t a = ctx.get_reg(dst);
            compute_sub_flags(ctx, a, b, bits);
        } else {
            ctx.sf = (nzcv & 8) != 0;
            ctx.zf = (nzcv & 4) != 0;
            ctx.cf = (nzcv & 2) != 0;
            ctx.of = (nzcv & 1) != 0;
        }
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_CCMN_RR: {
        uint8_t cond = (uint8_t)((((word >> 18) + 0x0FULL) - ((word >> 18) | 0x0FULL)));
        uint8_t nzcv = (uint8_t)((((word >> 22) + 0x0FULL) - ((word >> 22) | 0x0FULL)));
        uint32_t bits = (uint32_t)((((word >> 50) + 0x7FULL) - ((word >> 50) | 0x7FULL)));
        if (!eval_condition(ctx, cond)) {
            ctx.sf = (nzcv & 8) != 0;
            ctx.zf = (nzcv & 4) != 0;
            ctx.cf = (nzcv & 2) != 0;
            ctx.of = (nzcv & 1) != 0;
        } else {
            uint64_t a = ctx.get_reg(dst); uint64_t b = ctx.get_reg(src);
            compute_add_flags(ctx, a, b, bits);
        }
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_CCMN_RI: {
        uint8_t cond = (uint8_t)((((word >> 18) + 0x0FULL) - ((word >> 18) | 0x0FULL)));
        uint8_t nzcv = (uint8_t)((((word >> 22) + 0x0FULL) - ((word >> 22) | 0x0FULL)));
        uint64_t b = (uint64_t)((((word >> 26) + 0x1FULL) - ((word >> 26) | 0x1FULL)));
        uint32_t bits = (uint32_t)((((word >> 50) + 0x7FULL) - ((word >> 50) | 0x7FULL)));
        if (!eval_condition(ctx, cond)) {
            ctx.sf = (nzcv & 8) != 0;
            ctx.zf = (nzcv & 4) != 0;
            ctx.cf = (nzcv & 2) != 0;
            ctx.of = (nzcv & 1) != 0;
        } else {
            uint64_t a = ctx.get_reg(dst);
            compute_add_flags(ctx, a, b, bits);
        }
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_GET_FLAGS_R: {
        uint64_t f = 2ULL;
        f |= (uint64_t)ctx.cf;
        f |= ((uint64_t)ctx.zf << 6);
        f |= ((uint64_t)ctx.sf << 7);
        f |= ((uint64_t)ctx.of << 11);
        ctx.set_reg(dst, f);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_SET_FLAGS_R: {
        uint64_t f = ctx.get_reg(src);
        ctx.cf = (f & 1ULL) != 0;
        ctx.zf = (f & 0x40ULL) != 0;
        ctx.sf = (f & 0x80ULL) != 0;
        ctx.of = (f & 0x800ULL) != 0;
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_JMP: {
        #if defined(__APPLE__)
        vIP_idx = static_cast<size_t>(imm);
        #elif defined(_WIN32)
        asgard_nanomites::g_nanomite_dispatcher.current_trap_id = static_cast<uint32_t>(vIP_idx);
        asgard_nanomites::g_nanomite_dispatcher.current_condition = 1;
        asgard_nanomites::g_nanomite_dispatcher.register_nanomite(static_cast<uint32_t>(vIP_idx), static_cast<uint64_t>(imm), static_cast<uint64_t>(imm), static_cast<uint64_t>((seed ^ static_cast<uint32_t>(vIP_idx))));
        __debugbreak();
        vIP_idx = ((asgard_nanomites::g_nanomite_dispatcher.resolved_target != 0) ? static_cast<size_t>(asgard_nanomites::g_nanomite_dispatcher.resolved_target) : static_cast<size_t>(imm));
        #elif defined(__linux__) && !defined(_MSC_VER)
        asgard_nanomites::g_nanomite_dispatcher.current_trap_id = static_cast<uint32_t>(vIP_idx);
        asgard_nanomites::g_nanomite_dispatcher.current_condition = 1;
        asgard_nanomites::g_nanomite_dispatcher.register_nanomite(static_cast<uint32_t>(vIP_idx), static_cast<uint64_t>(imm), static_cast<uint64_t>(imm), static_cast<uint64_t>((seed ^ static_cast<uint32_t>(vIP_idx))));
        raise(SIGTRAP);
        vIP_idx = ((asgard_nanomites::g_nanomite_dispatcher.resolved_target != 0) ? static_cast<size_t>(asgard_nanomites::g_nanomite_dispatcher.resolved_target) : static_cast<size_t>(imm));
        #else
        vIP_idx = static_cast<size_t>(imm);
        #endif
        ctx.reanchor_running_key(static_cast<uint64_t>(vIP_idx));
        ctx.executed_instructions++;
        FETCH_NEXT();
    }
    H_JCC: {
        PROBE_START();
        uint8_t cond = static_cast<uint8_t>((((word >> 0x0000000000000012ULL) + 0x000000000000000fULL) - ((word >> 0x0000000000000012ULL) | 0x000000000000000fULL)));
        uint64_t base_vip = static_cast<uint64_t>(((word >> 0x0000000000000016ULL) & 0x00000000001fffffULL));
        uint64_t enc_delta = static_cast<uint64_t>(((word >> 0x000000000000002bULL) & 0x00000000001fffffULL));
        uint64_t salt = (((static_cast<uint64_t>(cond) * 0x0000000000005877ULL) ^ 0x000000001337beefULL) & 0x00000000001fffffULL);
        uint64_t delta = (enc_delta ^ salt);
        uint64_t t_true = (base_vip ^ delta);
        uint64_t t_false = base_vip;
        uint64_t c = (eval_condition(ctx, cond) ? 0x0000000000000001ULL : 0x0000000000000000ULL);
        #if defined(__APPLE__)
        vIP_idx = static_cast<size_t>(((c * t_true) + ((0x0000000000000001ULL - c) * t_false)));
        #elif defined(_WIN32)
        asgard_nanomites::g_nanomite_dispatcher.current_trap_id = static_cast<uint32_t>(vIP_idx);
        asgard_nanomites::g_nanomite_dispatcher.current_condition = static_cast<uint32_t>(c);
        asgard_nanomites::g_nanomite_dispatcher.register_nanomite(static_cast<uint32_t>(vIP_idx), t_true, t_false, static_cast<uint64_t>((seed ^ static_cast<uint32_t>(vIP_idx))));
        __debugbreak();
        vIP_idx = ((asgard_nanomites::g_nanomite_dispatcher.resolved_target != 0) ? static_cast<size_t>(asgard_nanomites::g_nanomite_dispatcher.resolved_target) : static_cast<size_t>(((c * t_true) + ((0x0000000000000001ULL - c) * t_false))));
        #elif defined(__linux__) && !defined(_MSC_VER)
        asgard_nanomites::g_nanomite_dispatcher.current_trap_id = static_cast<uint32_t>(vIP_idx);
        asgard_nanomites::g_nanomite_dispatcher.current_condition = static_cast<uint32_t>(c);
        asgard_nanomites::g_nanomite_dispatcher.register_nanomite(static_cast<uint32_t>(vIP_idx), t_true, t_false, static_cast<uint64_t>((seed ^ static_cast<uint32_t>(vIP_idx))));
        raise(SIGTRAP);
        vIP_idx = ((asgard_nanomites::g_nanomite_dispatcher.resolved_target != 0) ? static_cast<size_t>(asgard_nanomites::g_nanomite_dispatcher.resolved_target) : static_cast<size_t>(((c * t_true) + ((0x0000000000000001ULL - c) * t_false))));
        #else
        vIP_idx = static_cast<size_t>(((c * t_true) + ((0x0000000000000001ULL - c) * t_false)));
        #endif
        ctx.reanchor_running_key(static_cast<uint64_t>(vIP_idx));
        PROBE_CHECK();
        ctx.executed_instructions++;
        FETCH_NEXT();
    }
    H_CMOV: {
        PROBE_START();
        uint8_t cond = static_cast<uint8_t>((((word >> 0x0000000000000012ULL) + 0x000000000000000fULL) - ((word >> 0x0000000000000012ULL) | 0x000000000000000fULL)));
        uint64_t _s = ctx.get_reg(src);
        uint64_t _d = ctx.get_reg(dst);
        ctx.set_reg(dst, (eval_condition(ctx, cond) ? _s : _d));
        PROBE_CHECK();
        ctx.executed_instructions++;
        FETCH_NEXT();
    }
    H_SETCC: {
        PROBE_START();
        uint8_t cond = static_cast<uint8_t>((((word >> 0x0000000000000012ULL) + 0x000000000000000fULL) - ((word >> 0x0000000000000012ULL) | 0x000000000000000fULL)));
        ctx.set_reg(dst, static_cast<uint64_t>((eval_condition(ctx, cond) ? 1 : 0)));
        PROBE_CHECK();
        ctx.executed_instructions++;
        FETCH_NEXT();
    }
    H_CALL: {
        ctx.push(static_cast<uint64_t>(vIP_idx));
        #if defined(__APPLE__)
        vIP_idx = static_cast<size_t>(imm);
        #elif defined(_WIN32)
        asgard_nanomites::g_nanomite_dispatcher.current_trap_id = static_cast<uint32_t>(vIP_idx);
        asgard_nanomites::g_nanomite_dispatcher.current_condition = 1;
        asgard_nanomites::g_nanomite_dispatcher.register_nanomite(static_cast<uint32_t>(vIP_idx), static_cast<uint64_t>(imm), static_cast<uint64_t>(imm), static_cast<uint64_t>((seed ^ static_cast<uint32_t>(vIP_idx))));
        __debugbreak();
        vIP_idx = ((asgard_nanomites::g_nanomite_dispatcher.resolved_target != 0) ? static_cast<size_t>(asgard_nanomites::g_nanomite_dispatcher.resolved_target) : static_cast<size_t>(imm));
        #elif defined(__linux__) && !defined(_MSC_VER)
        asgard_nanomites::g_nanomite_dispatcher.current_trap_id = static_cast<uint32_t>(vIP_idx);
        asgard_nanomites::g_nanomite_dispatcher.current_condition = 1;
        asgard_nanomites::g_nanomite_dispatcher.register_nanomite(static_cast<uint32_t>(vIP_idx), static_cast<uint64_t>(imm), static_cast<uint64_t>(imm), static_cast<uint64_t>((seed ^ static_cast<uint32_t>(vIP_idx))));
        raise(SIGTRAP);
        vIP_idx = ((asgard_nanomites::g_nanomite_dispatcher.resolved_target != 0) ? static_cast<size_t>(asgard_nanomites::g_nanomite_dispatcher.resolved_target) : static_cast<size_t>(imm));
        #else
        vIP_idx = static_cast<size_t>(imm);
        #endif
        ctx.reanchor_running_key(static_cast<uint64_t>(vIP_idx));
        ctx.executed_instructions++;
        FETCH_NEXT();
    }
    H_IJMP_R: {
        uint64_t target = ctx.get_reg(dst);
        if (__builtin_expect((target < count), 1)) {
                                                vIP_idx = static_cast<size_t>(target);
} else {
            if (target != 0) {
                                  #if defined(__x86_64__) || defined(_M_X64)
                                  uint64_t a0 = ctx.get_reg(REG_RDI);
                                  uint64_t a1 = ctx.get_reg(REG_RSI);
                                  uint64_t a2 = ctx.get_reg(REG_RDX);
                                  uint64_t a3 = ctx.get_reg(REG_RCX);
                                  uint64_t a4 = ctx.get_reg(REG_R8);
                                  uint64_t a5 = ctx.get_reg(REG_R9);
                                  #else
                                  uint64_t a0 = ctx.get_reg(REG_RAX);
                                  uint64_t a1 = ctx.get_reg(REG_RCX);
                                  uint64_t a2 = ctx.get_reg(REG_RDX);
                                  uint64_t a3 = ctx.get_reg(REG_RBX);
                                  uint64_t a4 = ctx.get_reg(REG_RSI);
                                  uint64_t a5 = ctx.get_reg(REG_RDI);
                                  #endif
                                  typedef uint64_t (*indirect_fn_t)(uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t);
                                  indirect_fn_t fn = reinterpret_cast<indirect_fn_t>(target);
                                  uint64_t ret_val = fn(a0, a1, a2, a3, a4, a5);
                                  ctx.set_reg(REG_RAX, ret_val);
                                  goto EXIT_VM;
            }
}
        ctx.reanchor_running_key(static_cast<uint64_t>(vIP_idx));
        ctx.executed_instructions++;
        FETCH_NEXT();
    }
    H_ICALL_R: {
        uint64_t target_ptr = ctx.get_reg(dst);
        if (target_ptr < count) {
                             ctx.push(static_cast<uint64_t>(vIP_idx));
                             vIP_idx = static_cast<size_t>(target_ptr);
} else {
            if (target_ptr != 0x0000000000000000ULL) {
                                                          #if defined(__x86_64__) || defined(_M_X64)
                                                          uint64_t a0 = ctx.get_reg(REG_RDI);
                                                          uint64_t a1 = ctx.get_reg(REG_RSI);
                                                          uint64_t a2 = ctx.get_reg(REG_RDX);
                                                          uint64_t a3 = ctx.get_reg(REG_RCX);
                                                          uint64_t a4 = ctx.get_reg(REG_R8);
                                                          uint64_t a5 = ctx.get_reg(REG_R9);
                                                          #else
                                                          uint64_t a0 = ctx.get_reg(REG_RAX);
                                                          uint64_t a1 = ctx.get_reg(REG_RCX);
                                                          uint64_t a2 = ctx.get_reg(REG_RDX);
                                                          uint64_t a3 = ctx.get_reg(REG_RBX);
                                                          uint64_t a4 = ctx.get_reg(REG_RSI);
                                                          uint64_t a5 = ctx.get_reg(REG_RDI);
                                                          #endif
                                                          typedef uint64_t (*indirect_fn_t)(uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t);
                                                          indirect_fn_t fn = reinterpret_cast<indirect_fn_t>(target_ptr);
                                                          uint64_t ret_val = fn(a0, a1, a2, a3, a4, a5);
                                                          ctx.set_reg(REG_RAX, ret_val);
            }
}
        ctx.reanchor_running_key(static_cast<uint64_t>(vIP_idx));
        ctx.executed_instructions++;
        FETCH_NEXT();
    }
    H_RET: case_ret: { if (ctx.sp > 512) {
                       ctx.trapped = true;
} ctx.executed_instructions += 1; goto EXIT_VM; }
    H_EXIT: { if (ctx.sp > 512) {
                       ctx.trapped = true;
} ctx.executed_instructions += 1; goto EXIT_VM; }

    H_BRIDGE_TO_FLOW: {
        ctx.morph_math_to_flow(static_cast<uint64_t>((imm & 0xffffffffffffffffULL)));
        ctx.executed_instructions++;
        FETCH_NEXT();
    }
    H_BRIDGE_TO_MATH: {
        ctx.morph_flow_to_math(static_cast<uint64_t>(imm));
        ctx.executed_instructions++;
        FETCH_NEXT();
    }
    H_FUSED_MOV_ADD_RRI: {
        uint64_t _s = ctx.get_reg(src);
        uint64_t _i = static_cast<uint64_t>(imm);
        ctx.set_reg(dst, ((_s ^ _i) + (0x0000000000000002ULL * (_s & _i))));
        ctx.executed_instructions += 2;
        FETCH_NEXT();
    }
    H_FUSED_ADD_IMUL_RRI: {
        ctx.set_reg(dst, ((ctx.get_reg(dst) + ctx.get_reg(src)) * static_cast<uint64_t>(imm)));
        ctx.executed_instructions += 2;
        FETCH_NEXT();
    }
    H_FUSED_ADD_XOR_RRI: {
        uint64_t _sum = (ctx.get_reg(dst) + ctx.get_reg(src));
        uint64_t _imm = static_cast<uint64_t>(imm);
        ctx.set_reg(dst, ((_sum + _imm) - (0x0000000000000002ULL * (_sum & _imm))));
        ctx.executed_instructions += 2;
        FETCH_NEXT();
    }
    H_FUSED_SUB_XOR_RRI: {
        uint64_t _imm = static_cast<uint64_t>(imm);
        uint64_t _diff = (ctx.get_reg(dst) - ctx.get_reg(src));
        ctx.set_reg(dst, ((_diff | _imm) - (_diff & _imm)));
        ctx.executed_instructions += 2;
        FETCH_NEXT();
    }
    H_FUSED_XOR_ADD_RRI: {
        uint64_t _a = ctx.get_reg(dst);
        uint64_t _b = ctx.get_reg(src);
        uint64_t _x = ((_a | _b) - (_a & _b));
        uint64_t _i = static_cast<uint64_t>(imm);
        ctx.set_reg(dst, ((_x | _i) + (_x & _i)));
        ctx.executed_instructions += 2;
        FETCH_NEXT();
    }
    H_FUSED_CMP_CMOV: {
        uint64_t a = ctx.get_reg(dst);
        uint64_t b = static_cast<uint64_t>(imm);
        uint8_t cond = static_cast<uint8_t>(((word >> 0x0000000000000032ULL) & 0x000000000000000fULL));
        uint32_t bits = static_cast<uint32_t>(((word >> 0x0000000000000036ULL) & 0x000000000000007fULL));
        compute_sub_flags(ctx, a, b, bits);
        if (eval_condition(ctx, cond)) {
                                    ctx.set_reg(dst, ctx.get_reg(src));
}
        ctx.executed_instructions += 2;
        FETCH_NEXT();
    }
    H_FUSED_AND_OR_RRI: {
        ctx.set_reg(dst, ((ctx.get_reg(dst) & ctx.get_reg(src)) | static_cast<uint64_t>(imm)));
        ctx.executed_instructions += 2;
        FETCH_NEXT();
    }
    H_FUSED_SHL_ADD_RRI: {
        uint64_t _shl = (ctx.get_reg(dst) << (static_cast<uint64_t>(imm) & 0x000000000000003fULL));
        ctx.set_reg(dst, (_shl + ctx.get_reg(src)));
        ctx.executed_instructions += 2;
        FETCH_NEXT();
    }
    H_VADD_VV: {
        uint64_t d0 = ctx.get_vreg_lane(dst, 0), d1 = ctx.get_vreg_lane(dst, 1);
        uint64_t s0 = ctx.get_vreg_lane(src, 0), s1 = ctx.get_vreg_lane(src, 1);
#if defined(ASGARD_VECTOR_ISA) && defined(__aarch64__)
        uint64x2_t vd = vcombine_u64(vcreate_u64(d0), vcreate_u64(d1));
        uint64x2_t vs = vcombine_u64(vcreate_u64(s0), vcreate_u64(s1));
        uint64x2_t vr = vaddq_u64(vd, vs);
        ctx.set_vreg(dst, vgetq_lane_u64(vr, 0), vgetq_lane_u64(vr, 1));
#elif defined(ASGARD_VECTOR_ISA) && defined(__x86_64__)
        __m128i vd = _mm_set_epi64x((int64_t)d1, (int64_t)d0);
        __m128i vs = _mm_set_epi64x((int64_t)s1, (int64_t)s0);
        __m128i vr = _mm_add_epi64(vd, vs);
        ctx.set_vreg(dst, (uint64_t)_mm_extract_epi64(vr, 0), (uint64_t)_mm_extract_epi64(vr, 1));
#else
        ctx.set_vreg(dst, d0 + s0, d1 + s1);
#endif
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_VSUB_VV: {
        uint64_t d0 = ctx.get_vreg_lane(dst, 0), d1 = ctx.get_vreg_lane(dst, 1);
        uint64_t s0 = ctx.get_vreg_lane(src, 0), s1 = ctx.get_vreg_lane(src, 1);
#if defined(ASGARD_VECTOR_ISA) && defined(__aarch64__)
        uint64x2_t vr = vsubq_u64(vcombine_u64(vcreate_u64(d0), vcreate_u64(d1)), vcombine_u64(vcreate_u64(s0), vcreate_u64(s1)));
        ctx.set_vreg(dst, vgetq_lane_u64(vr, 0), vgetq_lane_u64(vr, 1));
#elif defined(ASGARD_VECTOR_ISA) && defined(__x86_64__)
        __m128i vr = _mm_sub_epi64(_mm_set_epi64x((int64_t)d1, (int64_t)d0), _mm_set_epi64x((int64_t)s1, (int64_t)s0));
        ctx.set_vreg(dst, static_cast<uint64_t>(_mm_extract_epi64(vr, 0)), static_cast<uint64_t>(_mm_extract_epi64(vr, 1)));
#else
        uint64_t _r0 = d0 - s0, _r1 = d1 - s1; ctx.set_vreg(dst, _r0, _r1);
#endif
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_VMUL_VV: {
        uint64_t d0 = ctx.get_vreg_lane(dst, 0), d1 = ctx.get_vreg_lane(dst, 1);
        uint64_t s0 = ctx.get_vreg_lane(src, 0), s1 = ctx.get_vreg_lane(src, 1);
        ctx.set_vreg(dst, d0 * s0, d1 * s1);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_VXOR_VV: {
        uint64_t d0 = ctx.get_vreg_lane(dst, 0), d1 = ctx.get_vreg_lane(dst, 1);
        uint64_t s0 = ctx.get_vreg_lane(src, 0), s1 = ctx.get_vreg_lane(src, 1);
#if defined(ASGARD_VECTOR_ISA) && defined(__aarch64__)
        uint64x2_t vr = veorq_u64(vcombine_u64(vcreate_u64(d0), vcreate_u64(d1)), vcombine_u64(vcreate_u64(s0), vcreate_u64(s1)));
        ctx.set_vreg(dst, vgetq_lane_u64(vr, 0), vgetq_lane_u64(vr, 1));
#elif defined(ASGARD_VECTOR_ISA) && defined(__x86_64__)
        __m128i vr = _mm_xor_si128(_mm_set_epi64x((int64_t)d1, (int64_t)d0), _mm_set_epi64x((int64_t)s1, (int64_t)s0));
        ctx.set_vreg(dst, static_cast<uint64_t>(_mm_extract_epi64(vr, 0)), static_cast<uint64_t>(_mm_extract_epi64(vr, 1)));
#else
        uint64_t _r0 = d0 ^ s0, _r1 = d1 ^ s1; ctx.set_vreg(dst, _r0, _r1);
#endif
        ctx.executed_instructions++; FETCH_NEXT();
    }

    H_VEC_MOV: {
        uint32_t bits = (uint32_t)(imm & 0x3ff);
        for (size_t i = 0; i < (bits + 63) / 64; ++i) ctx.set_vreg_lane(dst, i, ctx.get_vreg_lane(src, i));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_VEC_BINOP: {
        uint32_t src2 = (uint32_t)(imm & 31);
        uint32_t bits = (uint32_t)((imm >> 5) & 0x3ff);
        uint32_t lane_bits = (uint32_t)((imm >> 15) & 0xff);
        if (lane_bits == 0) lane_bits = 64;
        uint32_t vop = (uint32_t)((imm >> 23) & 0x1f);
        uint32_t elem = (uint32_t)((imm >> 28) & 0x3);
        uint64_t mask = lane_bits == 8 ? 0xffULL : (lane_bits == 16 ? 0xffffULL : (lane_bits == 32 ? 0xffffffffULL : ~0ULL));
        for (size_t bit = 0; bit < bits; bit += lane_bits) {
            size_t chunk = bit / 64; unsigned shift = (unsigned)(bit % 64);
            uint64_t a = (ctx.get_vreg_lane(src, chunk) >> shift) & mask;
            uint64_t b = (ctx.get_vreg_lane(src2, chunk) >> shift) & mask;
            uint64_t value = 0;
            if (elem == 1 && vop <= 2) {
                float fa = std::bit_cast<float>(static_cast<uint32_t>(a));
                float fb = std::bit_cast<float>(static_cast<uint32_t>(b));
                float fr = vop == 0 ? fa + fb : (vop == 1 ? fa - fb : fa * fb);
                value = std::bit_cast<uint32_t>(fr);
            } else if (elem == 1 && vop == 11) {
                float fa = std::bit_cast<float>(static_cast<uint32_t>(a));
                float fb = std::bit_cast<float>(static_cast<uint32_t>(b));
                value = std::bit_cast<uint32_t>(std::fmin(fa, fb));
            } else if (elem == 1 && vop == 12) {
                float fa = std::bit_cast<float>(static_cast<uint32_t>(a));
                float fb = std::bit_cast<float>(static_cast<uint32_t>(b));
                value = std::bit_cast<uint32_t>(std::fmax(fa, fb));
            } else if (elem == 2 && vop <= 2) {
                double fa = std::bit_cast<double>(a);
                double fb = std::bit_cast<double>(b);
                double fr = vop == 0 ? fa + fb : (vop == 1 ? fa - fb : fa * fb);
                value = std::bit_cast<uint64_t>(fr);
            } else if (elem == 2 && vop == 11) {
                double fa = std::bit_cast<double>(a);
                double fb = std::bit_cast<double>(b);
                value = std::bit_cast<uint64_t>(std::fmin(fa, fb));
            } else if (elem == 2 && vop == 12) {
                double fa = std::bit_cast<double>(a);
                double fb = std::bit_cast<double>(b);
                value = std::bit_cast<uint64_t>(std::fmax(fa, fb));
            } else {
                int64_t sa = lane_bits == 8 ? (int64_t)(int8_t)a : (lane_bits == 16 ? (int64_t)(int16_t)a : (lane_bits == 32 ? (int64_t)(int32_t)a : (int64_t)a));
                int64_t sb = lane_bits == 8 ? (int64_t)(int8_t)b : (lane_bits == 16 ? (int64_t)(int16_t)b : (lane_bits == 32 ? (int64_t)(int32_t)b : (int64_t)b));
                switch (vop) {
                    case 0: value = a + b; break;
                    case 1: value = a - b; break;
                    case 2: value = a * b; break;
                    case 3: value = a & b; break;
                    case 4: value = a | b; break;
                    case 5: value = a ^ b; break;
                    case 6: { uint32_t cnt = (uint32_t)(ctx.get_vreg_lane(src2, 0) & 0xff); value = (cnt >= lane_bits) ? 0 : (a << cnt); break; }
                    case 7: { uint32_t cnt = (uint32_t)(ctx.get_vreg_lane(src2, 0) & 0xff); value = (cnt >= lane_bits) ? 0 : (a >> cnt); break; }
                    case 8: { uint32_t cnt = (uint32_t)(ctx.get_vreg_lane(src2, 0) & 0xff); value = (cnt >= lane_bits) ? (sa < 0 ? mask : 0) : ((uint64_t)(sa >> cnt) & mask); break; }
                    case 9: value = (a == b) ? mask : 0; break;
                    case 10: value = (sa > sb) ? mask : 0; break;
                    case 11: value = (sa < sb) ? a : b; break;
                    case 12: value = (sa > sb) ? a : b; break;
                    case 13: value = (a < b) ? a : b; break;
                    case 14: value = (a > b) ? a : b; break;
                    case 15: value = (uint64_t)(sa < 0 ? -sa : sa) & mask; break;
                    case 16: value = (~a) & b; break;
                    case 17: {
                        size_t block_lane = (bit / lane_bits) % (128 / lane_bits);
                        size_t half_idx = block_lane / 2;
                        size_t src_reg = (block_lane % 2 == 0) ? src : src2;
                        size_t src_bit = ((bit / 128) * 128) + (half_idx * lane_bits);
                        value = (ctx.get_vreg_lane(src_reg, src_bit / 64) >> (src_bit % 64)) & mask;
                        break;
                    }
                    case 18: {
                        size_t num_lanes = 128 / lane_bits;
                        size_t block_lane = (bit / lane_bits) % num_lanes;
                        size_t half_idx = (num_lanes / 2) + (block_lane / 2);
                        size_t src_reg = (block_lane % 2 == 0) ? src : src2;
                        size_t src_bit = ((bit / 128) * 128) + (half_idx * lane_bits);
                        value = (ctx.get_vreg_lane(src_reg, src_bit / 64) >> (src_bit % 64)) & mask;
                        break;
                    }
                    case 21: {
                        uint8_t ctrl = (uint8_t)(b & 0xff);
                        if (ctrl & 0x80) value = 0;
                        else {
                            size_t src_bit = ((bit / 128) * 128) + ((ctrl & 0xf) * 8);
                            value = (ctx.get_vreg_lane(src, src_bit / 64) >> (src_bit % 64)) & 0xff;
                        }
                        break;
                    }
                    case 23: {
                        size_t num_lanes = 128 / lane_bits;
                        size_t block_lane = (bit / lane_bits) % num_lanes;
                        size_t half_len = num_lanes / 2;
                        size_t src_reg = (block_lane < half_len) ? src : src2;
                        size_t sel_elem = (block_lane < half_len) ? (block_lane * 2) : ((block_lane - half_len) * 2);
                        size_t src_bit = ((bit / 128) * 128) + (sel_elem * lane_bits);
                        value = (ctx.get_vreg_lane(src_reg, src_bit / 64) >> (src_bit % 64)) & mask;
                        break;
                    }
                    case 24: {
                        size_t num_lanes = 128 / lane_bits;
                        size_t block_lane = (bit / lane_bits) % num_lanes;
                        size_t half_len = num_lanes / 2;
                        size_t src_reg = (block_lane < half_len) ? src : src2;
                        size_t sel_elem = (block_lane < half_len) ? (block_lane * 2 + 1) : ((block_lane - half_len) * 2 + 1);
                        size_t src_bit = ((bit / 128) * 128) + (sel_elem * lane_bits);
                        value = (ctx.get_vreg_lane(src_reg, src_bit / 64) >> (src_bit % 64)) & mask;
                        break;
                    }
                    case 25: {
                        size_t num_lanes = 128 / lane_bits;
                        size_t block_lane = (bit / lane_bits) % num_lanes;
                        size_t k = block_lane / 2;
                        size_t src_reg = (block_lane % 2 == 0) ? src : src2;
                        size_t sel_elem = k * 2;
                        size_t src_bit = ((bit / 128) * 128) + (sel_elem * lane_bits);
                        value = (ctx.get_vreg_lane(src_reg, src_bit / 64) >> (src_bit % 64)) & mask;
                        break;
                    }
                    case 26: {
                        size_t num_lanes = 128 / lane_bits;
                        size_t block_lane = (bit / lane_bits) % num_lanes;
                        size_t k = block_lane / 2;
                        size_t src_reg = (block_lane % 2 == 0) ? src : src2;
                        size_t sel_elem = k * 2 + 1;
                        size_t src_bit = ((bit / 128) * 128) + (sel_elem * lane_bits);
                        value = (ctx.get_vreg_lane(src_reg, src_bit / 64) >> (src_bit % 64)) & mask;
                        break;
                    }
                    case 28: {
                        uint8_t idx = (uint8_t)(b & 0xff);
                        if (idx < 16) {
                            size_t src_bit = ((bit / 128) * 128) + (idx * 8);
                            value = (ctx.get_vreg_lane(src, src_bit / 64) >> (src_bit % 64)) & 0xff;
                        } else {
                            value = 0;
                        }
                        break;
                    }
                    case 29: {
                        uint8_t idx = (uint8_t)(b & 0xff);
                        if (idx < 16) {
                            size_t src_bit = ((bit / 128) * 128) + (idx * 8);
                            value = (ctx.get_vreg_lane(src, src_bit / 64) >> (src_bit % 64)) & 0xff;
                        } else {
                            value = (ctx.get_vreg_lane(dst, chunk) >> shift) & 0xff;
                        }
                        break;
                    }
                    case 30: {
                        int64_t min_val = (lane_bits == 64) ? (int64_t)0x8000000000000000ULL : (lane_bits == 32) ? (int64_t)(int32_t)0x80000000 : (lane_bits == 16) ? (int64_t)(int16_t)0x8000 : (int64_t)(int8_t)0x80;
                        if (sb == 0) value = ~0ULL;
                        else if (sb == -1 && sa == min_val) value = (uint64_t)sa;
                        else value = (uint64_t)(sa / sb);
                        break;
                    }
                    case 31: {
                        value = (b != 0) ? (a / b) : mask;
                        break;
                    }
                    case 32: {
                        int64_t min_val = (lane_bits == 64) ? (int64_t)0x8000000000000000ULL : (lane_bits == 32) ? (int64_t)(int32_t)0x80000000 : (lane_bits == 16) ? (int64_t)(int16_t)0x8000 : (int64_t)(int8_t)0x80;
                        if (sb == 0) value = a;
                        else if (sb == -1 && sa == min_val) value = 0;
                        else value = (uint64_t)(sa % sb);
                        break;
                    }
                    case 33: {
                        value = (b != 0) ? (a % b) : a;
                        break;
                    }
                    case 34: value = (a != b) ? mask : 0; break;
                    case 35: value = (sa <= sb) ? mask : 0; break;
                    case 36: value = (a < b) ? mask : 0; break;
                    case 37: value = (a <= b) ? mask : 0; break;
                    default: value = a ^ b; break;
                }
            }
            uint64_t old_value = ctx.get_vreg_lane(dst, chunk);
            uint64_t packed_mask = mask << shift;
            ctx.set_vreg_lane(dst, chunk, (old_value & ~packed_mask) | ((value & mask) << shift));
        }
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_VEC_IMM: {
        uint64_t imm_val = imm & 0xffULL;
        uint32_t bits = (uint32_t)((imm >> 8) & 0x3ff);
        uint32_t lane_bits = (uint32_t)((imm >> 18) & 0xff);
        if (lane_bits == 0) lane_bits = 64;
        uint32_t vop = (uint32_t)((imm >> 26) & 0x1f);
        uint64_t mask = lane_bits == 8 ? 0xffULL : (lane_bits == 16 ? 0xffffULL : (lane_bits == 32 ? 0xffffffffULL : ~0ULL));
        for (size_t bit = 0; bit < bits; bit += lane_bits) {
            size_t chunk = bit / 64; unsigned shift = (unsigned)(bit % 64);
            uint64_t a = (ctx.get_vreg_lane(src, chunk) >> shift) & mask;
            int64_t sa = lane_bits == 8 ? (int64_t)(int8_t)a : (lane_bits == 16 ? (int64_t)(int16_t)a : (lane_bits == 32 ? (int64_t)(int32_t)a : (int64_t)a));
            uint64_t value = 0;
            switch (vop) {
                case 6: { uint32_t cnt = (uint32_t)imm_val; value = (cnt >= lane_bits) ? 0 : (a << cnt); break; }
                case 7: { uint32_t cnt = (uint32_t)imm_val; value = (cnt >= lane_bits) ? 0 : (a >> cnt); break; }
                case 8: { uint32_t cnt = (uint32_t)imm_val; value = (cnt >= lane_bits) ? (sa < 0 ? mask : 0) : ((uint64_t)(sa >> cnt) & mask); break; }
                case 21: {
                    size_t lane_in_128 = (bit / 32) % 4;
                    size_t sel = (imm_val >> (lane_in_128 * 2)) & 3;
                    size_t src_bit = ((bit / 128) * 128) + (sel * 32);
                    value = (ctx.get_vreg_lane(src, src_bit / 64) >> (src_bit % 64)) & 0xffffffffULL;
                    break;
                }
                case 22: {
                    size_t lane_idx = bit / lane_bits;
                    size_t sel = (imm_val >> (lane_idx % 8)) & 1;
                    value = (sel == 0) ? a : ((ctx.get_vreg_lane(dst, chunk) >> shift) & mask);
                    break;
                }
                default: value = a; break;
            }
            uint64_t old_value = ctx.get_vreg_lane(dst, chunk);
            uint64_t packed_mask = mask << shift;
            ctx.set_vreg_lane(dst, chunk, (old_value & ~packed_mask) | ((value & mask) << shift));
        }
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_VEC_CLEAR_UPPER: {
        ctx.set_vreg_lane(dst, 2, 0ULL);
        ctx.set_vreg_lane(dst, 3, 0ULL);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_VEC_ZERO_UPPER: {
        for (size_t i = 0; i < 16; ++i) {
            ctx.set_vreg_lane(i, 2, 0ULL);
            ctx.set_vreg_lane(i, 3, 0ULL);
        }
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_PMOVMSKB: {
        uint32_t bits = (uint32_t)(imm & 0x3ff);
        uint32_t num_bytes = bits / 8;
        uint64_t mask = 0;
        for (uint32_t b = 0; b < num_bytes; ++b) {
            uint64_t byte_val = (ctx.get_vreg_lane(src, b / 8) >> ((b % 8) * 8)) & 0xff;
            if (byte_val & 0x80) mask |= (1ULL << b);
        }
        ctx.set_reg(dst, mask);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_VEC_LOAD: {
        uint32_t bits = (uint32_t)((word >> 50) & 0x3ff);
        uint64_t address = ctx.get_reg(src) + (uint64_t)imm;
        for (size_t i = 0; i < (bits + 63) / 64; ++i) { uint64_t value = 0; std::memcpy(&value, reinterpret_cast<const void*>(address + i * 8), sizeof(value)); ctx.set_vreg_lane(dst, i, value); }
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_VEC_STORE: {
        uint32_t bits = (uint32_t)((word >> 50) & 0x3ff);
        uint64_t address = ctx.get_reg(dst) + (uint64_t)imm;
        for (size_t i = 0; i < (bits + 63) / 64; ++i) std::memcpy(reinterpret_cast<void*>(address + i * 8), &ctx.vregs[src & 31][i & 7], sizeof(uint64_t));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_VEC_SPLAT: {
        uint32_t bits = (uint32_t)(imm & 0xffff);
        uint32_t lane_bits = (uint32_t)((imm >> 16) & 0xffff);
        uint64_t val = ctx.get_reg(src);
        uint64_t mask = (lane_bits >= 64) ? ~0ULL : ((1ULL << lane_bits) - 1ULL);
        uint64_t val_masked = val & mask;
        uint32_t num_lanes = (lane_bits > 0) ? (bits / lane_bits) : 0;
        for (uint32_t l = 0; l < num_lanes; ++l) {
            uint32_t pos = l * lane_bits;
            uint32_t chunk = pos / 64;
            uint32_t shift = pos % 64;
            uint64_t packed_mask = (lane_bits >= 64) ? ~0ULL : (mask << shift);
            uint64_t cur = ctx.get_vreg_lane(dst, chunk);
            cur = (cur & ~packed_mask) | (val_masked << shift);
            ctx.set_vreg_lane(dst, chunk, cur);
        }
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_VEC_EXT: {
        uint32_t src2 = (uint32_t)(imm & 31);
        uint32_t shift_bytes = (uint32_t)((imm >> 5) & 15);
        uint32_t bits = (uint32_t)((imm >> 9) & 0x3ff);
        if (bits == 0) bits = 128;
        for (size_t byte_idx = 0; byte_idx < (bits / 8); ++byte_idx) {
            size_t total_idx = (byte_idx % 16) + shift_bytes;
            uint64_t val = 0;
            if (total_idx < 16) {
                size_t bit_pos = ((byte_idx / 16) * 128) + (total_idx * 8);
                val = (ctx.get_vreg_lane(src, bit_pos / 64) >> (bit_pos % 64)) & 0xff;
            } else {
                size_t m_idx = total_idx - 16;
                size_t bit_pos = ((byte_idx / 16) * 128) + (m_idx * 8);
                val = (ctx.get_vreg_lane(src2, bit_pos / 64) >> (bit_pos % 64)) & 0xff;
            }
            size_t chunk = (byte_idx * 8) / 64; unsigned shift = (unsigned)((byte_idx * 8) % 64);
            uint64_t old_v = ctx.get_vreg_lane(dst, chunk);
            uint64_t clr = old_v & ~(0xffULL << shift);
            ctx.set_vreg_lane(dst, chunk, clr | (val << shift));
        }
        ctx.executed_instructions++; FETCH_NEXT();
    }

    H_CALL_EXTERN: {
        size_t sym_idx = (size_t)imm;
        void* sym_ptr = asgard_resolve_sym_idx((int32_t)sym_idx);
        if (sym_ptr) {
            uint32_t sym_h = g_external_symbols[sym_idx].hash;
            uint32_t sym_ah = g_external_symbols[sym_idx].alt_hash;
            uint64_t a0 = ctx.get_reg(REG_RAX);
            uint64_t a1 = ctx.get_reg(REG_RCX);
            uint64_t a2 = ctx.get_reg(REG_RDX);
            uint64_t a3 = ctx.get_reg(REG_RBX);
            uint64_t a4 = ctx.get_reg(REG_RSI);
            uint64_t a5 = ctx.get_reg(REG_RDI);
            uint64_t a6 = ctx.get_reg(REG_R8);
            uint64_t a7 = ctx.get_reg(REG_R9);
            const uint64_t* stk = reinterpret_cast<const uint64_t*>(ctx.get_reg(REG_RSP));
            uint64_t ret_val = 0;
            if (sym_h == 0x42FCF5CFU || sym_ah == 0x42FCF5CFU || sym_h == 0x07554ACDU || sym_ah == 0x07554ACDU || sym_h == 0xE76FB4AAU || sym_ah == 0xE76FB4AAU) {
                typedef int (*printf_fn_t)(const char*, ...);
                printf_fn_t pfn = reinterpret_cast<printf_fn_t>(sym_ptr);
#if defined(__APPLE__) && defined(__aarch64__)
                ret_val = (uint64_t)pfn((const char*)a0, stk[0], stk[1], stk[2], stk[3], stk[4], stk[5], stk[6], stk[7]);
#else
                ret_val = (uint64_t)pfn((const char*)a0, a1, a2, a3, a4, a5, a6, a7);
#endif
            } else if (sym_h == 0xFCB512E2U || sym_ah == 0xFCB512E2U || sym_h == 0x4B3C5330U || sym_ah == 0x4B3C5330U || sym_h == 0x937D1EF6U || sym_ah == 0x937D1EF6U || sym_h == 0xCB76D42BU || sym_ah == 0xCB76D42BU || sym_h == 0xD54CE817U || sym_ah == 0xD54CE817U || sym_h == 0xBBED3905U || sym_ah == 0xBBED3905U || sym_h == 0x42C07C7CU || sym_ah == 0x42C07C7CU || sym_h == 0x24559DBDU || sym_ah == 0x24559DBDU) {
                typedef int (*fprintf_fn_t)(void*, const char*, ...);
                fprintf_fn_t fpfn = reinterpret_cast<fprintf_fn_t>(sym_ptr);
#if defined(__APPLE__) && defined(__aarch64__)
                ret_val = (uint64_t)fpfn((void*)a0, (const char*)a1, stk[0], stk[1], stk[2], stk[3], stk[4], stk[5], stk[6], stk[7]);
#else
                ret_val = (uint64_t)fpfn((void*)a0, (const char*)a1, a2, a3, a4, a5, a6, a7);
#endif
            } else if (sym_h == 0x7FE32B00U || sym_ah == 0x7FE32B00U || sym_h == 0xBCBF60EEU || sym_ah == 0xBCBF60EEU || sym_h == 0x70E2D349U || sym_ah == 0x70E2D349U || sym_h == 0x44FA3468U || sym_ah == 0x44FA3468U) {
                typedef int (*sprintf_fn_t)(char*, const char*, ...);
                sprintf_fn_t spfn = reinterpret_cast<sprintf_fn_t>(sym_ptr);
#if defined(__APPLE__) && defined(__aarch64__)
                ret_val = (uint64_t)spfn((char*)a0, (const char*)a1, stk[0], stk[1], stk[2], stk[3], stk[4], stk[5], stk[6], stk[7]);
#else
                ret_val = (uint64_t)spfn((char*)a0, (const char*)a1, a2, a3, a4, a5, a6, a7);
#endif
            } else if (sym_h == 0x54EE11FAU || sym_ah == 0x54EE11FAU || sym_h == 0x933075F4U || sym_ah == 0x933075F4U || sym_h == 0x3FD5EB6FU || sym_ah == 0x3FD5EB6FU || sym_h == 0x5B3553B4U || sym_ah == 0x5B3553B4U) {
                typedef int (*snprintf_fn_t)(char*, size_t, const char*, ...);
                snprintf_fn_t snpfn = reinterpret_cast<snprintf_fn_t>(sym_ptr);
#if defined(__APPLE__) && defined(__aarch64__)
                ret_val = (uint64_t)snpfn((char*)a0, (size_t)a1, (const char*)a2, stk[0], stk[1], stk[2], stk[3], stk[4], stk[5], stk[6], stk[7]);
#else
                ret_val = (uint64_t)snpfn((char*)a0, (size_t)a1, (const char*)a2, a3, a4, a5, a6, a7);
#endif
            } else {
                typedef uint64_t (*extern_fn_t)(uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t);
                extern_fn_t fn = reinterpret_cast<extern_fn_t>(sym_ptr);
                ret_val = fn(a0, a1, a2, a3, a4, a5, a6, a7);
            }
            ctx.set_reg(REG_RAX, ret_val);
        }
        ctx.executed_instructions++; FETCH_NEXT();
    }

    H_LOAD_64: {
        uintptr_t _ptr = static_cast<uintptr_t>(ctx.get_reg(src)) + static_cast<uintptr_t>(imm);
        uint64_t _v = 0;
        std::memcpy(&_v, reinterpret_cast<const void*>(_ptr), sizeof(uint64_t));
        ctx.set_reg(dst, _v);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_LOAD_32: {
        const char* _base = reinterpret_cast<const char*>(ctx.get_reg(src));
        ctx.set_reg(dst, (uint64_t)(*reinterpret_cast<const uint32_t*>(_base + imm)));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_LOAD_16: {
        uint64_t addr = ctx.get_reg(src) + (uint64_t)imm;
        ctx.set_reg(dst, (uint64_t)(*reinterpret_cast<const uint16_t*>(addr)));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_LOAD_8: {
        const char* _base = reinterpret_cast<const char*>(ctx.get_reg(src));
        ctx.set_reg(dst, (uint64_t)(*reinterpret_cast<const uint8_t*>(_base + imm)));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_LOAD_S32: {
        uint64_t addr = ctx.get_reg(src) + (uint64_t)imm;
        ctx.set_reg(dst, (uint64_t)(int64_t)(*reinterpret_cast<const int32_t*>(addr)));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_LOAD_S16: {
        uint64_t addr = ctx.get_reg(src) + (uint64_t)imm;
        ctx.set_reg(dst, (uint64_t)(int64_t)(*reinterpret_cast<const int16_t*>(addr)));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_LOAD_S8: {
        uintptr_t _ptr = static_cast<uintptr_t>(ctx.get_reg(src)) + static_cast<uintptr_t>(imm);
        int8_t _s8 = 0;
        std::memcpy(&_s8, reinterpret_cast<const void*>(_ptr), sizeof(int8_t));
        ctx.set_reg(dst, (uint64_t)(int64_t)_s8);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_STORE_64: {
        char* _target = reinterpret_cast<char*>(ctx.get_reg(dst)) + imm;
        *reinterpret_cast<uint64_t*>(_target) = ctx.get_reg(src);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_STORE_32: {
        char* _target = reinterpret_cast<char*>(ctx.get_reg(dst)) + imm;
        *reinterpret_cast<uint32_t*>(_target) = (uint32_t)ctx.get_reg(src);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_STORE_16: {
        uintptr_t _ptr = static_cast<uintptr_t>(ctx.get_reg(dst)) + static_cast<uintptr_t>(imm);
        uint16_t _v16 = (uint16_t)ctx.get_reg(src);
        std::memcpy(reinterpret_cast<void*>(_ptr), &_v16, sizeof(uint16_t));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_STORE_8: {
        uint64_t addr = ctx.get_reg(dst) + (uint64_t)imm;
        *reinterpret_cast<uint8_t*>(addr) = (uint8_t)ctx.get_reg(src);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_RESOLVE_SYM: {
        size_t sym_idx = (size_t)imm;
        void* sym_ptr = asgard_resolve_sym_idx((int32_t)sym_idx);
        ctx.set_reg(dst, (uint64_t)sym_ptr);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_FADD_DD: {
        double _a = std::bit_cast<double>(ctx.get_vreg_lane(src, 0));
        double _b = std::bit_cast<double>(ctx.get_vreg_lane(static_cast<uint8_t>(imm), 0));
        ctx.set_vreg(dst, std::bit_cast<uint64_t>(_a + _b), 0);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_FSUB_DD: {
        uint64_t a_raw = ctx.get_vreg_lane(src, 0), b_raw = ctx.get_vreg_lane((uint8_t)imm, 0);
        double a = std::bit_cast<double>(a_raw), b = std::bit_cast<double>(b_raw);
        ctx.set_vreg(dst, std::bit_cast<uint64_t>(a - b), 0);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_FMUL_DD: {
        uint64_t a_raw = ctx.get_vreg_lane(src, 0), b_raw = ctx.get_vreg_lane((uint8_t)imm, 0);
        double a = std::bit_cast<double>(a_raw), b = std::bit_cast<double>(b_raw);
        ctx.set_vreg(dst, std::bit_cast<uint64_t>(a * b), 0);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_FDIV_DD: {
        uint64_t a_raw = ctx.get_vreg_lane(src, 0), b_raw = ctx.get_vreg_lane((uint8_t)imm, 0);
        double a = std::bit_cast<double>(a_raw), b = std::bit_cast<double>(b_raw);
        double r = a / b;
        ctx.set_vreg(dst, std::bit_cast<uint64_t>(r), 0);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_FSQRT_D: {
        uint64_t a_raw = ctx.get_vreg_lane(src, 0);
        double a = std::bit_cast<double>(a_raw);
        double r = std::sqrt(a);
        ctx.set_vreg(dst, std::bit_cast<uint64_t>(r), 0);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_FCMP_DD: {
        double _a = std::bit_cast<double>(ctx.get_vreg_lane(src, 0));
        double _b = std::bit_cast<double>(ctx.get_vreg_lane(static_cast<uint8_t>(imm), 0));
        ctx.of = false;
        ctx.sf = (_a < _b);
        ctx.cf = (_a >= _b);
        ctx.zf = (_a == _b);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_FCVTZS: {
        uint64_t a_raw = ctx.get_vreg_lane(src, 0);
        double a = std::bit_cast<double>(a_raw);
        ctx.set_reg(dst, (uint64_t)((int64_t)a));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_SCVTF: {
        int64_t v = (int64_t)ctx.get_reg(src);
        ctx.set_vreg(dst, std::bit_cast<uint64_t>((double)v), 0);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_FCVTZU: {
        uint64_t a_raw = ctx.get_vreg_lane(src, 0);
        double a = std::bit_cast<double>(a_raw);
        ctx.set_reg(dst, (a < 0.0) ? 0ULL : (uint64_t)a);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_UCVTF: {
        uint64_t _v = ctx.get_reg(src);
        ctx.set_vreg(dst, std::bit_cast<uint64_t>((double)_v), 0);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_FCVT: {
        float f32 = std::bit_cast<float>((uint32_t)ctx.get_vreg_lane(src, 0));
        ctx.set_vreg(dst, std::bit_cast<uint64_t>((double)f32), 0);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_ATOMIC_LOAD: {
        uint64_t _addr = ctx.get_reg(src) + static_cast<uint64_t>(imm);
        uint64_t _val = __atomic_load_n(reinterpret_cast<uint64_t*>(_addr), __ATOMIC_SEQ_CST);
        ctx.set_reg(dst, _val);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_ATOMIC_STORE: {
        uint64_t _addr = ctx.get_reg(dst) + (uint64_t)imm;
        (void)__atomic_exchange_n(reinterpret_cast<uint64_t*>(_addr), ctx.get_reg(src), __ATOMIC_SEQ_CST);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_ATOMIC_CAS: {
        uint64_t _addr = ctx.get_reg(dst) + static_cast<uint64_t>(imm);
        uint64_t _exp = ctx.get_reg(src), _des = ctx.get_reg(REG_RAX);
        __atomic_compare_exchange_n(reinterpret_cast<uint64_t*>(_addr), &_exp, _des, false, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST);
        ctx.set_reg(src, _exp);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_ATOMIC_ADD: {
        uint64_t _addr = ctx.get_reg(dst) + static_cast<uint64_t>(imm);
        uint64_t _old = __atomic_fetch_add(reinterpret_cast<uint64_t*>(_addr), ctx.get_reg(src), __ATOMIC_SEQ_CST);
        ctx.set_reg(src, _old);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_ATOMIC_SWP: {
        uint64_t* ptr = reinterpret_cast<uint64_t*>(ctx.get_reg(dst) + (uint64_t)imm);
        uint64_t old = __atomic_load_n(ptr, __ATOMIC_RELAXED);
        uint64_t new_val = ctx.get_reg(src);
        while (!__atomic_compare_exchange_n(ptr, &old, new_val, false, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST)) {}
        ctx.set_reg(src, old);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_FENCE: { std::atomic_thread_fence(std::memory_order_seq_cst); ctx.executed_instructions++; FETCH_NEXT(); }
    H_MOV_VR: { ctx.set_vreg_lane(dst, 0, ctx.get_reg(src)); ctx.executed_instructions++; FETCH_NEXT(); }
    H_MOV_RV: {
        uint64_t _val = ctx.get_vreg_lane(src, 0);
        uint64_t _buf[1];
        std::memcpy(_buf, (&_val), sizeof(uint64_t));
        ctx.set_reg(dst, _buf[0]);
        ctx.executed_instructions++;
        FETCH_NEXT();
    }
    H_FCSEL_VV: {
        uint8_t _c = (uint8_t)((((word >> 18) + 0x0FULL) - ((word >> 18) | 0x0FULL)));
        uint64_t _s = ctx.get_vreg_lane(src, 0);
        if (eval_condition(ctx, _c)) ctx.set_vreg_lane(dst, 0, _s);
        ctx.executed_instructions++; FETCH_NEXT();
    }

    H_DECOY_0: { uint64_t _d = ctx.get_reg(dst); ctx.reg_mask ^= ((k_dyn ^ 0x0000000000005877ULL) | 0x0000000000000001ULL); ctx.set_reg(dst, ((_d ^ 0x0000000000005877ULL) + ctx.reg_mask)); ctx.executed_instructions++; FETCH_NEXT(); }
    H_DECOY_1: { uint64_t _d = ctx.get_reg(dst); ctx.reg_mask ^= ((static_cast<uint64_t>(op) * 0x0000000000005877ULL) | 0x0000000000000001ULL); ctx.set_reg(dst, (_d + static_cast<uint64_t>(imm))); ctx.executed_instructions++; FETCH_NEXT(); }
    H_DECOY_2: { ctx.reg_mask ^= ((k_dyn ^ 0x0000000000009e37ULL) | 0x0000000000000001ULL); ctx.set_reg(dst, (ctx.get_reg(dst) * 0x0000000000009e37ULL)); ctx.executed_instructions++; FETCH_NEXT(); }
    H_DECOY_3: { ctx.reg_mask ^= ((k_dyn >> 13) | 0x0000000000000001ULL); ctx.set_reg(dst, ((ctx.get_reg(dst) << 3) | (ctx.get_reg(dst) >> 61))); ctx.executed_instructions++; FETCH_NEXT(); }
    H_DECOY_4: { uint64_t _s = ctx.get_reg(src); ctx.reg_mask ^= ((static_cast<uint64_t>(op) * 0x000000000000cafeULL) | 0x0000000000000001ULL); ctx.set_reg(dst, (_s ^ static_cast<uint64_t>(imm))); ctx.executed_instructions++; FETCH_NEXT(); }
    H_DECOY_5: { uint64_t _d = ctx.get_reg(dst); uint64_t _s = ctx.get_reg(src); ctx.reg_mask ^= ((static_cast<uint64_t>(op) * 0x0000000000001337ULL) | 0x0000000000000001ULL); ctx.set_reg(dst, (_d & (~_s))); ctx.executed_instructions++; FETCH_NEXT(); }
    H_DECOY_6: { uint64_t _d = ctx.get_reg(dst); ctx.reg_mask ^= ((static_cast<uint64_t>(op) * 0x00000000cafebabeULL) | 0x0000000000000001ULL); ctx.set_reg(dst, (_d | 0x00000000cafebabeULL)); ctx.executed_instructions++; FETCH_NEXT(); }
    H_DECOY_7: { ctx.reg_mask ^= ((k_dyn * 0x94d049bb133111ebULL) | 0x0000000000000001ULL); ctx.set_reg(dst, (((ctx.get_reg(dst) >> 5) | static_cast<uint64_t>(imm)) - ((ctx.get_reg(dst) >> 5) & static_cast<uint64_t>(imm)))); ctx.executed_instructions++; FETCH_NEXT(); }
    H_DECOY_8: { ctx.reg_mask ^= ((k_dyn ^ 0x0000000000001337ULL) | 0x0000000000000001ULL); ctx.set_reg(dst, (ctx.get_reg(dst) - 0x0000000000001337ULL)); ctx.executed_instructions++; FETCH_NEXT(); }
    H_DECOY_9: { uint64_t _rhs = (ctx.get_reg(src) + 0x0000000000000001ULL); ctx.reg_mask ^= ((static_cast<uint64_t>(op) ^ _rhs) | 0x0000000000000001ULL); ctx.set_reg(dst, (ctx.get_reg(dst) ^ _rhs)); ctx.executed_instructions++; FETCH_NEXT(); }
    H_DECOY_10: { uint64_t _m = (ctx.get_reg(dst) * 0x5851f42d4c957f2dULL); ctx.reg_mask ^= ((static_cast<uint64_t>(op) * 0x0000000000006a09ULL) | 0x0000000000000001ULL); ctx.set_reg(dst, (_m + 0x0000000000000001ULL)); ctx.executed_instructions++; FETCH_NEXT(); }
    H_DECOY_11: { uint64_t _sh = (ctx.get_reg(dst) << 7); ctx.reg_mask ^= ((static_cast<uint64_t>(op) << 7) | 0x0000000000000001ULL); ctx.set_reg(dst, (_sh ^ static_cast<uint64_t>(imm))); ctx.executed_instructions++; FETCH_NEXT(); }
    H_DECOY_12: { ctx.reg_mask ^= ((k_dyn ^ 0x00000000deadbeefULL) | 0x0000000000000001ULL); ctx.set_reg(dst, (ctx.get_reg(dst) ^ 0x00000000deadbeefULL)); ctx.executed_instructions++; FETCH_NEXT(); }
    H_DECOY_13: { ctx.reg_mask ^= ((k_dyn + static_cast<uint64_t>(src)) | 0x0000000000000001ULL); ctx.set_reg(dst, (ctx.get_reg(dst) + ctx.get_reg(src))); ctx.executed_instructions++; FETCH_NEXT(); }
    H_DECOY_14: { ctx.reg_mask ^= ((k_dyn ^ (static_cast<uint64_t>(imm) * 0x0000000000000003ULL)) | 0x0000000000000001ULL); ctx.set_reg(dst, (ctx.get_reg(dst) ^ (static_cast<uint64_t>(imm) * 0x0000000000000003ULL))); ctx.executed_instructions++; FETCH_NEXT(); }
    H_DECOY_15: { ctx.reg_mask ^= ((k_dyn * 0xbf58476d1ce4e5b9ULL) | 0x0000000000000001ULL); ctx.set_reg(dst, (ctx.get_reg(dst) ^ (~0x0000000000000000ULL))); ctx.executed_instructions++; FETCH_NEXT(); }
    H_DECOY: { uint64_t _p = (((static_cast<uint64_t>(op) * 0xbf58476d1ce4e5b9ULL) ^ (k_dyn * 0x6a09e667f3bcc908ULL)) ^ 0xcafebabe13375877ULL); ctx.reg_mask ^= (_p | 0x0000000000000001ULL); ctx.set_reg(dst, ((ctx.get_reg(dst) ^ ctx.reg_mask) + static_cast<uint64_t>(imm))); ctx.executed_instructions++; FETCH_NEXT(); }
    H_NOP_D1: { ctx.executed_instructions += 1; FETCH_NEXT(); }
    H_MOV_RR_D1: ctx.set_reg(dst, ctx.get_reg(src)); ctx.executed_instructions++; FETCH_NEXT();
    H_MOV_RI_D1: { uint32_t _u32 = (uint32_t)imm; ctx.set_reg(dst, (uint64_t)_u32); ctx.executed_instructions++; FETCH_NEXT(); }
    H_MOV_HIGH_D1: {
        uint64_t _d = ctx.get_reg(dst);
        uint64_t _hi = static_cast<uint64_t>(static_cast<uint32_t>(imm)) << 32;
        ctx.set_reg(dst, (_d & 0xFFFFFFFFULL) ^ _hi);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_NEG_RR_D1: { PROBE_START(); ctx.set_reg(dst, static_cast<uint64_t>(-static_cast<int64_t>(ctx.get_reg(dst)))); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_NOT_RR_D1: { PROBE_START(); ctx.set_reg(dst, 0xFFFFFFFFFFFFFFFFULL - ctx.get_reg(dst)); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_BSWAP_RR_D1: {
        uint64_t _val = ctx.get_reg(src);
        uint32_t _b = static_cast<uint32_t>(imm);
        uint64_t _r = (_b == 16) ? static_cast<uint64_t>(__builtin_bswap16(static_cast<uint16_t>(_val)))
                     : ((_b == 32) ? static_cast<uint64_t>(__builtin_bswap32(static_cast<uint32_t>(_val)))
                                   : __builtin_bswap64(_val));
        ctx.set_reg(dst, _r);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_CLZ_RR_D1: {
        uint64_t val = ctx.get_reg(src); uint32_t bits = (uint32_t)imm;
        uint64_t mask = (bits >= 64) ? ~0ULL : ((1ULL << bits) - 1ULL);
        uint64_t mval = val & mask;
        uint64_t _clz = (bits <= 32) ? (((uint32_t)mval == 0) ? (uint64_t)bits : (uint64_t)(__builtin_clz((uint32_t)mval) - (32 - bits)))
                                     : ((mval == 0) ? 64ULL : (uint64_t)__builtin_clzll(mval));
        ctx.set_reg(dst, _clz);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_CTZ_RR_D1: {
        uint64_t _s = ctx.get_reg(src);
        uint32_t _bits = static_cast<uint32_t>(imm);
        uint64_t _mask = (_bits >= 64) ? ~0ULL : ((1ULL << _bits) - 1ULL);
        uint64_t _ms = _s & _mask;
        if (_bits <= 32) {
            uint32_t _v32 = static_cast<uint32_t>(_ms);
            ctx.set_reg(dst, (_v32 == 0) ? static_cast<uint64_t>(_bits) : static_cast<uint64_t>(__builtin_ctz(_v32)));
        } else {
            ctx.set_reg(dst, (_ms == 0) ? 64ULL : static_cast<uint64_t>(__builtin_ctzll(_ms)));
        }
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_POPCNT_RR_D1: {
        uint64_t _s = ctx.get_reg(src);
        uint32_t _b = static_cast<uint32_t>(imm);
        uint64_t _mask = (_b >= 64) ? ~0ULL : ((1ULL << _b) - 1ULL);
        uint64_t _ms = _s & _mask;
        uint64_t _res = (_b <= 32) ? static_cast<uint64_t>(__builtin_popcount(static_cast<uint32_t>(_ms))) : static_cast<uint64_t>(__builtin_popcountll(_ms));
        ctx.set_reg(dst, _res);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_RBIT_RR_D1: {
        uint64_t _val = ctx.get_reg(src); uint32_t _bits = static_cast<uint32_t>(imm);
        uint64_t _res = 0; uint32_t _i = 0;
        while (_i < _bits) {
            if ((_val >> _i) & 1ULL) _res |= (1ULL << (_bits - 1 - _i));
            _i++;
        }
        ctx.set_reg(dst, _res);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_ADD_RR_D1: { PROBE_START(); ctx.set_reg(dst, (((((((0x0000000000000002ULL * (((ctx.get_reg(dst) & 0x5555555555555555ULL) | (ctx.get_reg(src) & 0x5555555555555555ULL)) + ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) | (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL)))) - (ctx.get_reg(dst) ^ ctx.get_reg(src))) ^ ((((ctx.get_reg(dst) + ctx.get_reg(src)) & (~((ctx.get_reg(dst) + ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) + ctx.get_reg(src)))) & (ctx.get_reg(dst) + ctx.get_reg(src)))) + (((ctx.get_reg(dst) + ctx.get_reg(src)) ^ (ctx.get_reg(dst) + ctx.get_reg(src))) - (((ctx.get_reg(dst) + ctx.get_reg(src)) | (ctx.get_reg(dst) + ctx.get_reg(src))) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & (ctx.get_reg(dst) + ctx.get_reg(src))))))) + (0x0000000000000002ULL * (((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) - (ctx.get_reg(dst) ^ ctx.get_reg(src))) & ((((ctx.get_reg(dst) + ctx.get_reg(src)) & (~((ctx.get_reg(dst) + ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) + ctx.get_reg(src)))) & (ctx.get_reg(dst) + ctx.get_reg(src)))) + (((ctx.get_reg(dst) + ctx.get_reg(src)) ^ (ctx.get_reg(dst) + ctx.get_reg(src))) - (((ctx.get_reg(dst) + ctx.get_reg(src)) | (ctx.get_reg(dst) + ctx.get_reg(src))) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & (ctx.get_reg(dst) + ctx.get_reg(src))))))))) + (((((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) - (ctx.get_reg(dst) ^ ctx.get_reg(src))) ^ ((((ctx.get_reg(dst) + ctx.get_reg(src)) & (~((ctx.get_reg(dst) + ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) + ctx.get_reg(src)))) & (ctx.get_reg(dst) + ctx.get_reg(src)))) + (((ctx.get_reg(dst) + ctx.get_reg(src)) ^ (ctx.get_reg(dst) + ctx.get_reg(src))) - (((ctx.get_reg(dst) + ctx.get_reg(src)) | (ctx.get_reg(dst) + ctx.get_reg(src))) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & (ctx.get_reg(dst) + ctx.get_reg(src))))))) + (0x0000000000000002ULL * (((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) - (ctx.get_reg(dst) ^ ctx.get_reg(src))) & ((((ctx.get_reg(dst) + ctx.get_reg(src)) & (~((ctx.get_reg(dst) + ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) + ctx.get_reg(src)))) & (ctx.get_reg(dst) + ctx.get_reg(src)))) + (((ctx.get_reg(dst) + ctx.get_reg(src)) ^ (ctx.get_reg(dst) + ctx.get_reg(src))) - (((ctx.get_reg(dst) + ctx.get_reg(src)) | (ctx.get_reg(dst) + ctx.get_reg(src))) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & (ctx.get_reg(dst) + ctx.get_reg(src))))))))) - (ctx.get_reg(dst) + ctx.get_reg(src)))) ^ ((((((((0x0000000000000002ULL * (((ctx.get_reg(dst) & 0x5555555555555555ULL) | (ctx.get_reg(src) & 0x5555555555555555ULL)) + ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) | (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL)))) - (ctx.get_reg(dst) ^ ctx.get_reg(src))) ^ ((((ctx.get_reg(dst) + ctx.get_reg(src)) & (~((ctx.get_reg(dst) + ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) + ctx.get_reg(src)))) & (ctx.get_reg(dst) + ctx.get_reg(src)))) + (((ctx.get_reg(dst) + ctx.get_reg(src)) ^ (ctx.get_reg(dst) + ctx.get_reg(src))) - (((ctx.get_reg(dst) + ctx.get_reg(src)) | (ctx.get_reg(dst) + ctx.get_reg(src))) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & (ctx.get_reg(dst) + ctx.get_reg(src))))))) + (0x0000000000000002ULL * (((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) - (ctx.get_reg(dst) ^ ctx.get_reg(src))) & ((((ctx.get_reg(dst) + ctx.get_reg(src)) & (~((ctx.get_reg(dst) + ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) + ctx.get_reg(src)))) & (ctx.get_reg(dst) + ctx.get_reg(src)))) + (((ctx.get_reg(dst) + ctx.get_reg(src)) ^ (ctx.get_reg(dst) + ctx.get_reg(src))) - (((ctx.get_reg(dst) + ctx.get_reg(src)) | (ctx.get_reg(dst) + ctx.get_reg(src))) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & (ctx.get_reg(dst) + ctx.get_reg(src))))))))) + (((((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) - (ctx.get_reg(dst) ^ ctx.get_reg(src))) ^ ((((ctx.get_reg(dst) + ctx.get_reg(src)) & (~((ctx.get_reg(dst) + ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) + ctx.get_reg(src)))) & (ctx.get_reg(dst) + ctx.get_reg(src)))) + (((ctx.get_reg(dst) + ctx.get_reg(src)) ^ (ctx.get_reg(dst) + ctx.get_reg(src))) - (((ctx.get_reg(dst) + ctx.get_reg(src)) | (ctx.get_reg(dst) + ctx.get_reg(src))) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & (ctx.get_reg(dst) + ctx.get_reg(src))))))) + (0x0000000000000002ULL * (((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) - (ctx.get_reg(dst) ^ ctx.get_reg(src))) & ((((ctx.get_reg(dst) + ctx.get_reg(src)) & (~((ctx.get_reg(dst) + ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) + ctx.get_reg(src)))) & (ctx.get_reg(dst) + ctx.get_reg(src)))) + (((ctx.get_reg(dst) + ctx.get_reg(src)) ^ (ctx.get_reg(dst) + ctx.get_reg(src))) - (((ctx.get_reg(dst) + ctx.get_reg(src)) | (ctx.get_reg(dst) + ctx.get_reg(src))) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & (ctx.get_reg(dst) + ctx.get_reg(src))))))))) - (ctx.get_reg(dst) + ctx.get_reg(src)))) & 0x000000007fffffffULL) * 0x120d334d0e967bfdULL) << 0x0000000000000021ULL)) ^ (((((((((0x0000000000000002ULL * (((ctx.get_reg(dst) & 0x5555555555555555ULL) | (ctx.get_reg(src) & 0x5555555555555555ULL)) + ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) | (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL)))) - (ctx.get_reg(dst) ^ ctx.get_reg(src))) ^ ((((ctx.get_reg(dst) + ctx.get_reg(src)) & (~((ctx.get_reg(dst) + ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) + ctx.get_reg(src)))) & (ctx.get_reg(dst) + ctx.get_reg(src)))) + (((ctx.get_reg(dst) + ctx.get_reg(src)) ^ (ctx.get_reg(dst) + ctx.get_reg(src))) - (((ctx.get_reg(dst) + ctx.get_reg(src)) | (ctx.get_reg(dst) + ctx.get_reg(src))) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & (ctx.get_reg(dst) + ctx.get_reg(src))))))) + (0x0000000000000002ULL * (((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) - (ctx.get_reg(dst) ^ ctx.get_reg(src))) & ((((ctx.get_reg(dst) + ctx.get_reg(src)) & (~((ctx.get_reg(dst) + ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) + ctx.get_reg(src)))) & (ctx.get_reg(dst) + ctx.get_reg(src)))) + (((ctx.get_reg(dst) + ctx.get_reg(src)) ^ (ctx.get_reg(dst) + ctx.get_reg(src))) - (((ctx.get_reg(dst) + ctx.get_reg(src)) | (ctx.get_reg(dst) + ctx.get_reg(src))) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & (ctx.get_reg(dst) + ctx.get_reg(src))))))))) + (((((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) - (ctx.get_reg(dst) ^ ctx.get_reg(src))) ^ ((((ctx.get_reg(dst) + ctx.get_reg(src)) & (~((ctx.get_reg(dst) + ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) + ctx.get_reg(src)))) & (ctx.get_reg(dst) + ctx.get_reg(src)))) + (((ctx.get_reg(dst) + ctx.get_reg(src)) ^ (ctx.get_reg(dst) + ctx.get_reg(src))) - (((ctx.get_reg(dst) + ctx.get_reg(src)) | (ctx.get_reg(dst) + ctx.get_reg(src))) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & (ctx.get_reg(dst) + ctx.get_reg(src))))))) + (0x0000000000000002ULL * (((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) - (ctx.get_reg(dst) ^ ctx.get_reg(src))) & ((((ctx.get_reg(dst) + ctx.get_reg(src)) & (~((ctx.get_reg(dst) + ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) + ctx.get_reg(src)))) & (ctx.get_reg(dst) + ctx.get_reg(src)))) + (((ctx.get_reg(dst) + ctx.get_reg(src)) ^ (ctx.get_reg(dst) + ctx.get_reg(src))) - (((ctx.get_reg(dst) + ctx.get_reg(src)) | (ctx.get_reg(dst) + ctx.get_reg(src))) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & (ctx.get_reg(dst) + ctx.get_reg(src))))))))) - (ctx.get_reg(dst) + ctx.get_reg(src)))) ^ ((((((((0x0000000000000002ULL * (((ctx.get_reg(dst) & 0x5555555555555555ULL) | (ctx.get_reg(src) & 0x5555555555555555ULL)) + ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) | (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL)))) - (ctx.get_reg(dst) ^ ctx.get_reg(src))) ^ ((((ctx.get_reg(dst) + ctx.get_reg(src)) & (~((ctx.get_reg(dst) + ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) + ctx.get_reg(src)))) & (ctx.get_reg(dst) + ctx.get_reg(src)))) + (((ctx.get_reg(dst) + ctx.get_reg(src)) ^ (ctx.get_reg(dst) + ctx.get_reg(src))) - (((ctx.get_reg(dst) + ctx.get_reg(src)) | (ctx.get_reg(dst) + ctx.get_reg(src))) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & (ctx.get_reg(dst) + ctx.get_reg(src))))))) + (0x0000000000000002ULL * (((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) - (ctx.get_reg(dst) ^ ctx.get_reg(src))) & ((((ctx.get_reg(dst) + ctx.get_reg(src)) & (~((ctx.get_reg(dst) + ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) + ctx.get_reg(src)))) & (ctx.get_reg(dst) + ctx.get_reg(src)))) + (((ctx.get_reg(dst) + ctx.get_reg(src)) ^ (ctx.get_reg(dst) + ctx.get_reg(src))) - (((ctx.get_reg(dst) + ctx.get_reg(src)) | (ctx.get_reg(dst) + ctx.get_reg(src))) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & (ctx.get_reg(dst) + ctx.get_reg(src))))))))) + (((((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) - (ctx.get_reg(dst) ^ ctx.get_reg(src))) ^ ((((ctx.get_reg(dst) + ctx.get_reg(src)) & (~((ctx.get_reg(dst) + ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) + ctx.get_reg(src)))) & (ctx.get_reg(dst) + ctx.get_reg(src)))) + (((ctx.get_reg(dst) + ctx.get_reg(src)) ^ (ctx.get_reg(dst) + ctx.get_reg(src))) - (((ctx.get_reg(dst) + ctx.get_reg(src)) | (ctx.get_reg(dst) + ctx.get_reg(src))) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & (ctx.get_reg(dst) + ctx.get_reg(src))))))) + (0x0000000000000002ULL * (((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) - (ctx.get_reg(dst) ^ ctx.get_reg(src))) & ((((ctx.get_reg(dst) + ctx.get_reg(src)) & (~((ctx.get_reg(dst) + ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) + ctx.get_reg(src)))) & (ctx.get_reg(dst) + ctx.get_reg(src)))) + (((ctx.get_reg(dst) + ctx.get_reg(src)) ^ (ctx.get_reg(dst) + ctx.get_reg(src))) - (((ctx.get_reg(dst) + ctx.get_reg(src)) | (ctx.get_reg(dst) + ctx.get_reg(src))) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & (ctx.get_reg(dst) + ctx.get_reg(src))))))))) - (ctx.get_reg(dst) + ctx.get_reg(src)))) & 0x000000007fffffffULL) * 0x120d334d0e967bfdULL) << 0x0000000000000021ULL)) & 0x000000007fffffffULL) * 0x120d334d0e967bfdULL) << 0x0000000000000021ULL))); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_ADD_RI_D1: { PROBE_START(); uint64_t _d = ctx.get_reg(dst); ctx.set_reg(dst, (_d + static_cast<uint64_t>(imm))); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_SUB_RR_D1: { PROBE_START(); ctx.set_reg(dst, (((((((((ctx.get_reg(dst) & (~ctx.get_reg(src))) & 0x5555555555555555ULL) - (((~ctx.get_reg(dst)) & ctx.get_reg(src)) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) & (~ctx.get_reg(src))) & 0xaaaaaaaaaaaaaaaaULL) - (((~ctx.get_reg(dst)) & ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL))) & 0x5555555555555555ULL) + (((((~ctx.get_reg(dst)) ^ (~ctx.get_reg(src))) + ((~(((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))))) + 0x0000000000000001ULL)) + (((ctx.get_reg(dst) ^ ctx.get_reg(src)) - ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))) - ((ctx.get_reg(dst) ^ ctx.get_reg(src)) + ((~(((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))))) + 0x0000000000000001ULL)))) & 0x5555555555555555ULL)) + ((((((ctx.get_reg(dst) & (~ctx.get_reg(src))) & 0x5555555555555555ULL) - (((~ctx.get_reg(dst)) & ctx.get_reg(src)) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) & (~ctx.get_reg(src))) & 0xaaaaaaaaaaaaaaaaULL) - (((~ctx.get_reg(dst)) & ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL))) & 0xaaaaaaaaaaaaaaaaULL) + (((((~ctx.get_reg(dst)) ^ (~ctx.get_reg(src))) + ((~(((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))))) + 0x0000000000000001ULL)) + (((ctx.get_reg(dst) ^ ctx.get_reg(src)) - ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))) - ((ctx.get_reg(dst) ^ ctx.get_reg(src)) + ((~(((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))))) + 0x0000000000000001ULL)))) & 0xaaaaaaaaaaaaaaaaULL))) ^ ((((((((((ctx.get_reg(dst) & (~ctx.get_reg(src))) & 0x5555555555555555ULL) - (((~ctx.get_reg(dst)) & ctx.get_reg(src)) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) & (~ctx.get_reg(src))) & 0xaaaaaaaaaaaaaaaaULL) - (((~ctx.get_reg(dst)) & ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL))) & 0x5555555555555555ULL) + (((((~ctx.get_reg(dst)) ^ (~ctx.get_reg(src))) + ((~(((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))))) + 0x0000000000000001ULL)) + (((ctx.get_reg(dst) ^ ctx.get_reg(src)) - ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))) - ((ctx.get_reg(dst) ^ ctx.get_reg(src)) + ((~(((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))))) + 0x0000000000000001ULL)))) & 0x5555555555555555ULL)) + ((((((ctx.get_reg(dst) & (~ctx.get_reg(src))) & 0x5555555555555555ULL) - (((~ctx.get_reg(dst)) & ctx.get_reg(src)) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) & (~ctx.get_reg(src))) & 0xaaaaaaaaaaaaaaaaULL) - (((~ctx.get_reg(dst)) & ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL))) & 0xaaaaaaaaaaaaaaaaULL) + (((((~ctx.get_reg(dst)) ^ (~ctx.get_reg(src))) + ((~(((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))))) + 0x0000000000000001ULL)) + (((ctx.get_reg(dst) ^ ctx.get_reg(src)) - ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))) - ((ctx.get_reg(dst) ^ ctx.get_reg(src)) + ((~(((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))))) + 0x0000000000000001ULL)))) & 0xaaaaaaaaaaaaaaaaULL))) & 0x000000007fffffffULL) * 0x255e1221bed2b5c7ULL) << 0x0000000000000021ULL)) ^ (((((((((((ctx.get_reg(dst) & (~ctx.get_reg(src))) & 0x5555555555555555ULL) - (((~ctx.get_reg(dst)) & ctx.get_reg(src)) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) & (~ctx.get_reg(src))) & 0xaaaaaaaaaaaaaaaaULL) - (((~ctx.get_reg(dst)) & ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL))) & 0x5555555555555555ULL) + (((((~ctx.get_reg(dst)) ^ (~ctx.get_reg(src))) + ((~(((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))))) + 0x0000000000000001ULL)) + (((ctx.get_reg(dst) ^ ctx.get_reg(src)) - ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))) - ((ctx.get_reg(dst) ^ ctx.get_reg(src)) + ((~(((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))))) + 0x0000000000000001ULL)))) & 0x5555555555555555ULL)) + ((((((ctx.get_reg(dst) & (~ctx.get_reg(src))) & 0x5555555555555555ULL) - (((~ctx.get_reg(dst)) & ctx.get_reg(src)) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) & (~ctx.get_reg(src))) & 0xaaaaaaaaaaaaaaaaULL) - (((~ctx.get_reg(dst)) & ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL))) & 0xaaaaaaaaaaaaaaaaULL) + (((((~ctx.get_reg(dst)) ^ (~ctx.get_reg(src))) + ((~(((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))))) + 0x0000000000000001ULL)) + (((ctx.get_reg(dst) ^ ctx.get_reg(src)) - ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))) - ((ctx.get_reg(dst) ^ ctx.get_reg(src)) + ((~(((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))))) + 0x0000000000000001ULL)))) & 0xaaaaaaaaaaaaaaaaULL))) ^ ((((((((((ctx.get_reg(dst) & (~ctx.get_reg(src))) & 0x5555555555555555ULL) - (((~ctx.get_reg(dst)) & ctx.get_reg(src)) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) & (~ctx.get_reg(src))) & 0xaaaaaaaaaaaaaaaaULL) - (((~ctx.get_reg(dst)) & ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL))) & 0x5555555555555555ULL) + (((((~ctx.get_reg(dst)) ^ (~ctx.get_reg(src))) + ((~(((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))))) + 0x0000000000000001ULL)) + (((ctx.get_reg(dst) ^ ctx.get_reg(src)) - ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))) - ((ctx.get_reg(dst) ^ ctx.get_reg(src)) + ((~(((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))))) + 0x0000000000000001ULL)))) & 0x5555555555555555ULL)) + ((((((ctx.get_reg(dst) & (~ctx.get_reg(src))) & 0x5555555555555555ULL) - (((~ctx.get_reg(dst)) & ctx.get_reg(src)) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) & (~ctx.get_reg(src))) & 0xaaaaaaaaaaaaaaaaULL) - (((~ctx.get_reg(dst)) & ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL))) & 0xaaaaaaaaaaaaaaaaULL) + (((((~ctx.get_reg(dst)) ^ (~ctx.get_reg(src))) + ((~(((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))))) + 0x0000000000000001ULL)) + (((ctx.get_reg(dst) ^ ctx.get_reg(src)) - ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))) - ((ctx.get_reg(dst) ^ ctx.get_reg(src)) + ((~(((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))))) + 0x0000000000000001ULL)))) & 0xaaaaaaaaaaaaaaaaULL))) & 0x000000007fffffffULL) * 0x255e1221bed2b5c7ULL) << 0x0000000000000021ULL)) & 0x000000007fffffffULL) * 0x255e1221bed2b5c7ULL) << 0x0000000000000021ULL))); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_SUB_RI_D1: { PROBE_START(); uint64_t _d = ctx.get_reg(dst); ctx.set_reg(dst, (_d - static_cast<uint64_t>(imm))); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_IMUL_RR_D1: {
        PROBE_START();
        uint64_t a = ctx.get_reg(dst); uint64_t b = ctx.get_reg(src);
        ctx.set_reg(dst, ((a & b) * (a | b)) + ((a & (~b)) * ((~a) & b)));
        PROBE_CHECK();
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_IMUL_RI_D1: {
        PROBE_START();
        ctx.set_reg(dst, static_cast<uint64_t>(static_cast<int64_t>(ctx.get_reg(dst)) * imm));
        PROBE_CHECK();
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_XOR_RR_D1: { PROBE_START(); ctx.set_reg(dst, ((((((((((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0x5555555555555555ULL) + ((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0xaaaaaaaaaaaaaaaaULL)) | ((ctx.get_reg(src) - (ctx.get_reg(src) & (~0x5555555555555555ULL))) + ((ctx.get_reg(src) ^ 0x5555555555555555ULL) - ((ctx.get_reg(src) | 0x5555555555555555ULL) - (ctx.get_reg(src) & 0x5555555555555555ULL))))) + (((ctx.get_reg(dst) - (ctx.get_reg(dst) & (~0xaaaaaaaaaaaaaaaaULL))) + ((ctx.get_reg(dst) ^ 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) | 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL)))) | (((ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL) & 0x5555555555555555ULL) + ((ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL) & 0xaaaaaaaaaaaaaaaaULL)))) & (~(((ctx.get_reg(dst) + ctx.get_reg(src)) - (((ctx.get_reg(dst) + ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))) + (((ctx.get_reg(dst) & ctx.get_reg(src)) + (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - ctx.get_reg(dst))))))) - ((~((((ctx.get_reg(dst) + ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))) + (((ctx.get_reg(dst) & ctx.get_reg(src)) + (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - ctx.get_reg(dst))))) & ((ctx.get_reg(dst) + ctx.get_reg(src)) - (((ctx.get_reg(dst) + ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))) + (((ctx.get_reg(dst) & ctx.get_reg(src)) + (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - ctx.get_reg(dst)))))) + (((((((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0x5555555555555555ULL) + ((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0xaaaaaaaaaaaaaaaaULL)) | ((ctx.get_reg(src) - (ctx.get_reg(src) & (~0x5555555555555555ULL))) + ((ctx.get_reg(src) ^ 0x5555555555555555ULL) - ((ctx.get_reg(src) | 0x5555555555555555ULL) - (ctx.get_reg(src) & 0x5555555555555555ULL))))) + (((ctx.get_reg(dst) - (ctx.get_reg(dst) & (~0xaaaaaaaaaaaaaaaaULL))) + ((ctx.get_reg(dst) ^ 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) | 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL)))) | (((ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL) & 0x5555555555555555ULL) + ((ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL) & 0xaaaaaaaaaaaaaaaaULL)))) ^ ((ctx.get_reg(dst) + ctx.get_reg(src)) - (((ctx.get_reg(dst) + ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))) + (((ctx.get_reg(dst) & ctx.get_reg(src)) + (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - ctx.get_reg(dst))))) - (((((ctx.get_reg(dst) + ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))) + (((ctx.get_reg(dst) & ctx.get_reg(src)) + (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - ctx.get_reg(dst))) | ((ctx.get_reg(dst) + ctx.get_reg(src)) - (((ctx.get_reg(dst) + ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))) + (((ctx.get_reg(dst) & ctx.get_reg(src)) + (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - ctx.get_reg(dst))))) - ((((ctx.get_reg(dst) + ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))) + (((ctx.get_reg(dst) & ctx.get_reg(src)) + (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - ctx.get_reg(dst))) & ((ctx.get_reg(dst) + ctx.get_reg(src)) - (((ctx.get_reg(dst) + ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))) + (((ctx.get_reg(dst) & ctx.get_reg(src)) + (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - ctx.get_reg(dst)))))))) ^ (((((((((((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0x5555555555555555ULL) + ((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0xaaaaaaaaaaaaaaaaULL)) | ((ctx.get_reg(src) - (ctx.get_reg(src) & (~0x5555555555555555ULL))) + ((ctx.get_reg(src) ^ 0x5555555555555555ULL) - ((ctx.get_reg(src) | 0x5555555555555555ULL) - (ctx.get_reg(src) & 0x5555555555555555ULL))))) + (((ctx.get_reg(dst) - (ctx.get_reg(dst) & (~0xaaaaaaaaaaaaaaaaULL))) + ((ctx.get_reg(dst) ^ 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) | 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL)))) | (((ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL) & 0x5555555555555555ULL) + ((ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL) & 0xaaaaaaaaaaaaaaaaULL)))) & (~(((ctx.get_reg(dst) + ctx.get_reg(src)) - (((ctx.get_reg(dst) + ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))) + (((ctx.get_reg(dst) & ctx.get_reg(src)) + (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - ctx.get_reg(dst))))))) - ((~((((ctx.get_reg(dst) + ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))) + (((ctx.get_reg(dst) & ctx.get_reg(src)) + (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - ctx.get_reg(dst))))) & ((ctx.get_reg(dst) + ctx.get_reg(src)) - (((ctx.get_reg(dst) + ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))) + (((ctx.get_reg(dst) & ctx.get_reg(src)) + (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - ctx.get_reg(dst)))))) + (((((((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0x5555555555555555ULL) + ((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0xaaaaaaaaaaaaaaaaULL)) | ((ctx.get_reg(src) - (ctx.get_reg(src) & (~0x5555555555555555ULL))) + ((ctx.get_reg(src) ^ 0x5555555555555555ULL) - ((ctx.get_reg(src) | 0x5555555555555555ULL) - (ctx.get_reg(src) & 0x5555555555555555ULL))))) + (((ctx.get_reg(dst) - (ctx.get_reg(dst) & (~0xaaaaaaaaaaaaaaaaULL))) + ((ctx.get_reg(dst) ^ 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) | 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL)))) | (((ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL) & 0x5555555555555555ULL) + ((ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL) & 0xaaaaaaaaaaaaaaaaULL)))) ^ ((ctx.get_reg(dst) + ctx.get_reg(src)) - (((ctx.get_reg(dst) + ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))) + (((ctx.get_reg(dst) & ctx.get_reg(src)) + (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - ctx.get_reg(dst))))) - (((((ctx.get_reg(dst) + ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))) + (((ctx.get_reg(dst) & ctx.get_reg(src)) + (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - ctx.get_reg(dst))) | ((ctx.get_reg(dst) + ctx.get_reg(src)) - (((ctx.get_reg(dst) + ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))) + (((ctx.get_reg(dst) & ctx.get_reg(src)) + (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - ctx.get_reg(dst))))) - ((((ctx.get_reg(dst) + ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))) + (((ctx.get_reg(dst) & ctx.get_reg(src)) + (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - ctx.get_reg(dst))) & ((ctx.get_reg(dst) + ctx.get_reg(src)) - (((ctx.get_reg(dst) + ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))) + (((ctx.get_reg(dst) & ctx.get_reg(src)) + (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - ctx.get_reg(dst)))))))) & 0x000000007fffffffULL) * 0x2e7bbf635e3eb77bULL) << 0x0000000000000021ULL)) ^ ((((((((((((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0x5555555555555555ULL) + ((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0xaaaaaaaaaaaaaaaaULL)) | ((ctx.get_reg(src) - (ctx.get_reg(src) & (~0x5555555555555555ULL))) + ((ctx.get_reg(src) ^ 0x5555555555555555ULL) - ((ctx.get_reg(src) | 0x5555555555555555ULL) - (ctx.get_reg(src) & 0x5555555555555555ULL))))) + (((ctx.get_reg(dst) - (ctx.get_reg(dst) & (~0xaaaaaaaaaaaaaaaaULL))) + ((ctx.get_reg(dst) ^ 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) | 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL)))) | (((ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL) & 0x5555555555555555ULL) + ((ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL) & 0xaaaaaaaaaaaaaaaaULL)))) & (~(((ctx.get_reg(dst) + ctx.get_reg(src)) - (((ctx.get_reg(dst) + ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))) + (((ctx.get_reg(dst) & ctx.get_reg(src)) + (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - ctx.get_reg(dst))))))) - ((~((((ctx.get_reg(dst) + ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))) + (((ctx.get_reg(dst) & ctx.get_reg(src)) + (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - ctx.get_reg(dst))))) & ((ctx.get_reg(dst) + ctx.get_reg(src)) - (((ctx.get_reg(dst) + ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))) + (((ctx.get_reg(dst) & ctx.get_reg(src)) + (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - ctx.get_reg(dst)))))) + (((((((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0x5555555555555555ULL) + ((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0xaaaaaaaaaaaaaaaaULL)) | ((ctx.get_reg(src) - (ctx.get_reg(src) & (~0x5555555555555555ULL))) + ((ctx.get_reg(src) ^ 0x5555555555555555ULL) - ((ctx.get_reg(src) | 0x5555555555555555ULL) - (ctx.get_reg(src) & 0x5555555555555555ULL))))) + (((ctx.get_reg(dst) - (ctx.get_reg(dst) & (~0xaaaaaaaaaaaaaaaaULL))) + ((ctx.get_reg(dst) ^ 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) | 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL)))) | (((ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL) & 0x5555555555555555ULL) + ((ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL) & 0xaaaaaaaaaaaaaaaaULL)))) ^ ((ctx.get_reg(dst) + ctx.get_reg(src)) - (((ctx.get_reg(dst) + ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))) + (((ctx.get_reg(dst) & ctx.get_reg(src)) + (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - ctx.get_reg(dst))))) - (((((ctx.get_reg(dst) + ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))) + (((ctx.get_reg(dst) & ctx.get_reg(src)) + (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - ctx.get_reg(dst))) | ((ctx.get_reg(dst) + ctx.get_reg(src)) - (((ctx.get_reg(dst) + ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))) + (((ctx.get_reg(dst) & ctx.get_reg(src)) + (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - ctx.get_reg(dst))))) - ((((ctx.get_reg(dst) + ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))) + (((ctx.get_reg(dst) & ctx.get_reg(src)) + (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - ctx.get_reg(dst))) & ((ctx.get_reg(dst) + ctx.get_reg(src)) - (((ctx.get_reg(dst) + ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))) + (((ctx.get_reg(dst) & ctx.get_reg(src)) + (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - ctx.get_reg(dst)))))))) ^ (((((((((((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0x5555555555555555ULL) + ((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0xaaaaaaaaaaaaaaaaULL)) | ((ctx.get_reg(src) - (ctx.get_reg(src) & (~0x5555555555555555ULL))) + ((ctx.get_reg(src) ^ 0x5555555555555555ULL) - ((ctx.get_reg(src) | 0x5555555555555555ULL) - (ctx.get_reg(src) & 0x5555555555555555ULL))))) + (((ctx.get_reg(dst) - (ctx.get_reg(dst) & (~0xaaaaaaaaaaaaaaaaULL))) + ((ctx.get_reg(dst) ^ 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) | 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL)))) | (((ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL) & 0x5555555555555555ULL) + ((ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL) & 0xaaaaaaaaaaaaaaaaULL)))) & (~(((ctx.get_reg(dst) + ctx.get_reg(src)) - (((ctx.get_reg(dst) + ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))) + (((ctx.get_reg(dst) & ctx.get_reg(src)) + (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - ctx.get_reg(dst))))))) - ((~((((ctx.get_reg(dst) + ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))) + (((ctx.get_reg(dst) & ctx.get_reg(src)) + (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - ctx.get_reg(dst))))) & ((ctx.get_reg(dst) + ctx.get_reg(src)) - (((ctx.get_reg(dst) + ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))) + (((ctx.get_reg(dst) & ctx.get_reg(src)) + (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - ctx.get_reg(dst)))))) + (((((((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0x5555555555555555ULL) + ((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0xaaaaaaaaaaaaaaaaULL)) | ((ctx.get_reg(src) - (ctx.get_reg(src) & (~0x5555555555555555ULL))) + ((ctx.get_reg(src) ^ 0x5555555555555555ULL) - ((ctx.get_reg(src) | 0x5555555555555555ULL) - (ctx.get_reg(src) & 0x5555555555555555ULL))))) + (((ctx.get_reg(dst) - (ctx.get_reg(dst) & (~0xaaaaaaaaaaaaaaaaULL))) + ((ctx.get_reg(dst) ^ 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) | 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL)))) | (((ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL) & 0x5555555555555555ULL) + ((ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL) & 0xaaaaaaaaaaaaaaaaULL)))) ^ ((ctx.get_reg(dst) + ctx.get_reg(src)) - (((ctx.get_reg(dst) + ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))) + (((ctx.get_reg(dst) & ctx.get_reg(src)) + (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - ctx.get_reg(dst))))) - (((((ctx.get_reg(dst) + ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))) + (((ctx.get_reg(dst) & ctx.get_reg(src)) + (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - ctx.get_reg(dst))) | ((ctx.get_reg(dst) + ctx.get_reg(src)) - (((ctx.get_reg(dst) + ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))) + (((ctx.get_reg(dst) & ctx.get_reg(src)) + (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - ctx.get_reg(dst))))) - ((((ctx.get_reg(dst) + ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))) + (((ctx.get_reg(dst) & ctx.get_reg(src)) + (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - ctx.get_reg(dst))) & ((ctx.get_reg(dst) + ctx.get_reg(src)) - (((ctx.get_reg(dst) + ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))) + (((ctx.get_reg(dst) & ctx.get_reg(src)) + (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - ctx.get_reg(dst)))))))) & 0x000000007fffffffULL) * 0x2e7bbf635e3eb77bULL) << 0x0000000000000021ULL)) & 0x000000007fffffffULL) * 0x2e7bbf635e3eb77bULL) << 0x0000000000000021ULL))); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_XOR_RI_D1: { PROBE_START(); uint64_t _d = ctx.get_reg(dst); uint64_t _i = static_cast<uint64_t>(imm); ctx.set_reg(dst, ((_d + _i) - (0x0000000000000002ULL * (_d & _i)))); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_AND_RR_D1: { PROBE_START(); ctx.set_reg(dst, (((0x0000000000000002ULL * ((ctx.get_reg(dst) - ((ctx.get_reg(dst) - (ctx.get_reg(dst) & (~((~ctx.get_reg(src)))))) + ((ctx.get_reg(dst) ^ (~ctx.get_reg(src))) - ((ctx.get_reg(dst) | (~ctx.get_reg(src))) - (ctx.get_reg(dst) & (~ctx.get_reg(src))))))) | (((ctx.get_reg(dst) ^ ctx.get_reg(src)) + (((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) - (ctx.get_reg(dst) + ctx.get_reg(src)))) - ((ctx.get_reg(dst) ^ ctx.get_reg(src)) + (((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) - (ctx.get_reg(dst) + ctx.get_reg(src))))))) - (((0x0000000000000002ULL * (ctx.get_reg(dst) & (~((ctx.get_reg(dst) & (~ctx.get_reg(src))))))) - (ctx.get_reg(dst) ^ ((ctx.get_reg(dst) - (ctx.get_reg(dst) & (~((~ctx.get_reg(src)))))) + ((ctx.get_reg(dst) ^ (~ctx.get_reg(src))) - ((ctx.get_reg(dst) | (~ctx.get_reg(src))) - (ctx.get_reg(dst) & (~ctx.get_reg(src)))))))) ^ ((((ctx.get_reg(dst) | ctx.get_reg(src)) + (((ctx.get_reg(dst) & ctx.get_reg(src)) + (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - ctx.get_reg(dst))) - (ctx.get_reg(dst) & ctx.get_reg(src))) - (((ctx.get_reg(dst) | ctx.get_reg(src)) + (((ctx.get_reg(dst) & ctx.get_reg(src)) + (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - ctx.get_reg(dst))) - (ctx.get_reg(dst) & ctx.get_reg(src)))))) + ((((ctx.get_reg(dst) - ((ctx.get_reg(dst) - (ctx.get_reg(dst) & (~((~ctx.get_reg(src)))))) + ((ctx.get_reg(dst) ^ (~ctx.get_reg(src))) - ((ctx.get_reg(dst) | (~ctx.get_reg(src))) - (ctx.get_reg(dst) & (~ctx.get_reg(src))))))) | (((ctx.get_reg(dst) ^ ctx.get_reg(src)) + (((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) - (ctx.get_reg(dst) + ctx.get_reg(src)))) - ((ctx.get_reg(dst) ^ ctx.get_reg(src)) + (((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) - (ctx.get_reg(dst) + ctx.get_reg(src)))))) + ((ctx.get_reg(dst) - ((ctx.get_reg(dst) - (ctx.get_reg(dst) & (~((~ctx.get_reg(src)))))) + ((ctx.get_reg(dst) ^ (~ctx.get_reg(src))) - ((ctx.get_reg(dst) | (~ctx.get_reg(src))) - (ctx.get_reg(dst) & (~ctx.get_reg(src))))))) & (((ctx.get_reg(dst) ^ ctx.get_reg(src)) + (((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) - (ctx.get_reg(dst) + ctx.get_reg(src)))) - ((ctx.get_reg(dst) ^ ctx.get_reg(src)) + (((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) - (ctx.get_reg(dst) + ctx.get_reg(src))))))) - (ctx.get_reg(dst) & ctx.get_reg(src))))); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_AND_RI_D1: { PROBE_START(); ctx.set_reg(dst, ((ctx.get_reg(dst) + static_cast<uint64_t>(imm)) - (ctx.get_reg(dst) | static_cast<uint64_t>(imm)))); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_OR_RR_D1: { PROBE_START(); ctx.set_reg(dst, (((((0x0000000000000002ULL * (((((ctx.get_reg(dst) & 0x5555555555555555ULL) + (ctx.get_reg(src) & 0x5555555555555555ULL)) - ((ctx.get_reg(dst) & 0x5555555555555555ULL) & (ctx.get_reg(src) & 0x5555555555555555ULL))) + ((((ctx.get_reg(dst) & 0x5555555555555555ULL) & (ctx.get_reg(src) & 0x5555555555555555ULL)) + ((ctx.get_reg(dst) & 0x5555555555555555ULL) & (~((ctx.get_reg(src) & 0x5555555555555555ULL))))) - (ctx.get_reg(dst) & 0x5555555555555555ULL))) | ((((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & 0x5555555555555555ULL) + ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & 0xaaaaaaaaaaaaaaaaULL)) | (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL)))) - ((((~(((~ctx.get_reg(dst)) | (~0x5555555555555555ULL)))) ^ ((ctx.get_reg(src) - (ctx.get_reg(src) & (~0x5555555555555555ULL))) + ((ctx.get_reg(src) ^ 0x5555555555555555ULL) - ((ctx.get_reg(src) | 0x5555555555555555ULL) - (ctx.get_reg(src) & 0x5555555555555555ULL))))) + ((~(((~ctx.get_reg(dst)) | (~0x5555555555555555ULL)))) & ((ctx.get_reg(src) - (ctx.get_reg(src) & (~0x5555555555555555ULL))) + ((ctx.get_reg(src) ^ 0x5555555555555555ULL) - ((ctx.get_reg(src) | 0x5555555555555555ULL) - (ctx.get_reg(src) & 0x5555555555555555ULL)))))) ^ ((((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & 0x5555555555555555ULL) + ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & 0xaaaaaaaaaaaaaaaaULL)) | (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL)))) + (((((((ctx.get_reg(dst) & 0x5555555555555555ULL) + (ctx.get_reg(src) & 0x5555555555555555ULL)) - ((ctx.get_reg(dst) & 0x5555555555555555ULL) & (ctx.get_reg(src) & 0x5555555555555555ULL))) + ((((ctx.get_reg(dst) & 0x5555555555555555ULL) & (ctx.get_reg(src) & 0x5555555555555555ULL)) + ((ctx.get_reg(dst) & 0x5555555555555555ULL) & (~((ctx.get_reg(src) & 0x5555555555555555ULL))))) - (ctx.get_reg(dst) & 0x5555555555555555ULL))) | ((((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & 0x5555555555555555ULL) + ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & 0xaaaaaaaaaaaaaaaaULL)) | (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))) + (((((ctx.get_reg(dst) & 0x5555555555555555ULL) + (ctx.get_reg(src) & 0x5555555555555555ULL)) - ((ctx.get_reg(dst) & 0x5555555555555555ULL) & (ctx.get_reg(src) & 0x5555555555555555ULL))) + ((((ctx.get_reg(dst) & 0x5555555555555555ULL) & (ctx.get_reg(src) & 0x5555555555555555ULL)) + ((ctx.get_reg(dst) & 0x5555555555555555ULL) & (~((ctx.get_reg(src) & 0x5555555555555555ULL))))) - (ctx.get_reg(dst) & 0x5555555555555555ULL))) & ((((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & 0x5555555555555555ULL) + ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & 0xaaaaaaaaaaaaaaaaULL)) | (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL)))) - (ctx.get_reg(dst) | ctx.get_reg(src)))) ^ ((((((0x0000000000000002ULL * (((((ctx.get_reg(dst) & 0x5555555555555555ULL) + (ctx.get_reg(src) & 0x5555555555555555ULL)) - ((ctx.get_reg(dst) & 0x5555555555555555ULL) & (ctx.get_reg(src) & 0x5555555555555555ULL))) + ((((ctx.get_reg(dst) & 0x5555555555555555ULL) & (ctx.get_reg(src) & 0x5555555555555555ULL)) + ((ctx.get_reg(dst) & 0x5555555555555555ULL) & (~((ctx.get_reg(src) & 0x5555555555555555ULL))))) - (ctx.get_reg(dst) & 0x5555555555555555ULL))) | ((((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & 0x5555555555555555ULL) + ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & 0xaaaaaaaaaaaaaaaaULL)) | (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL)))) - ((((~(((~ctx.get_reg(dst)) | (~0x5555555555555555ULL)))) ^ ((ctx.get_reg(src) - (ctx.get_reg(src) & (~0x5555555555555555ULL))) + ((ctx.get_reg(src) ^ 0x5555555555555555ULL) - ((ctx.get_reg(src) | 0x5555555555555555ULL) - (ctx.get_reg(src) & 0x5555555555555555ULL))))) + ((~(((~ctx.get_reg(dst)) | (~0x5555555555555555ULL)))) & ((ctx.get_reg(src) - (ctx.get_reg(src) & (~0x5555555555555555ULL))) + ((ctx.get_reg(src) ^ 0x5555555555555555ULL) - ((ctx.get_reg(src) | 0x5555555555555555ULL) - (ctx.get_reg(src) & 0x5555555555555555ULL)))))) ^ ((((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & 0x5555555555555555ULL) + ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & 0xaaaaaaaaaaaaaaaaULL)) | (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL)))) + (((((((ctx.get_reg(dst) & 0x5555555555555555ULL) + (ctx.get_reg(src) & 0x5555555555555555ULL)) - ((ctx.get_reg(dst) & 0x5555555555555555ULL) & (ctx.get_reg(src) & 0x5555555555555555ULL))) + ((((ctx.get_reg(dst) & 0x5555555555555555ULL) & (ctx.get_reg(src) & 0x5555555555555555ULL)) + ((ctx.get_reg(dst) & 0x5555555555555555ULL) & (~((ctx.get_reg(src) & 0x5555555555555555ULL))))) - (ctx.get_reg(dst) & 0x5555555555555555ULL))) | ((((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & 0x5555555555555555ULL) + ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & 0xaaaaaaaaaaaaaaaaULL)) | (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))) + (((((ctx.get_reg(dst) & 0x5555555555555555ULL) + (ctx.get_reg(src) & 0x5555555555555555ULL)) - ((ctx.get_reg(dst) & 0x5555555555555555ULL) & (ctx.get_reg(src) & 0x5555555555555555ULL))) + ((((ctx.get_reg(dst) & 0x5555555555555555ULL) & (ctx.get_reg(src) & 0x5555555555555555ULL)) + ((ctx.get_reg(dst) & 0x5555555555555555ULL) & (~((ctx.get_reg(src) & 0x5555555555555555ULL))))) - (ctx.get_reg(dst) & 0x5555555555555555ULL))) & ((((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & 0x5555555555555555ULL) + ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & 0xaaaaaaaaaaaaaaaaULL)) | (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL)))) - (ctx.get_reg(dst) | ctx.get_reg(src)))) & 0x000000007fffffffULL) * 0x1db0caf2e7fdb945ULL) << 0x0000000000000021ULL)) ^ (((((((0x0000000000000002ULL * (((((ctx.get_reg(dst) & 0x5555555555555555ULL) + (ctx.get_reg(src) & 0x5555555555555555ULL)) - ((ctx.get_reg(dst) & 0x5555555555555555ULL) & (ctx.get_reg(src) & 0x5555555555555555ULL))) + ((((ctx.get_reg(dst) & 0x5555555555555555ULL) & (ctx.get_reg(src) & 0x5555555555555555ULL)) + ((ctx.get_reg(dst) & 0x5555555555555555ULL) & (~((ctx.get_reg(src) & 0x5555555555555555ULL))))) - (ctx.get_reg(dst) & 0x5555555555555555ULL))) | ((((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & 0x5555555555555555ULL) + ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & 0xaaaaaaaaaaaaaaaaULL)) | (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL)))) - ((((~(((~ctx.get_reg(dst)) | (~0x5555555555555555ULL)))) ^ ((ctx.get_reg(src) - (ctx.get_reg(src) & (~0x5555555555555555ULL))) + ((ctx.get_reg(src) ^ 0x5555555555555555ULL) - ((ctx.get_reg(src) | 0x5555555555555555ULL) - (ctx.get_reg(src) & 0x5555555555555555ULL))))) + ((~(((~ctx.get_reg(dst)) | (~0x5555555555555555ULL)))) & ((ctx.get_reg(src) - (ctx.get_reg(src) & (~0x5555555555555555ULL))) + ((ctx.get_reg(src) ^ 0x5555555555555555ULL) - ((ctx.get_reg(src) | 0x5555555555555555ULL) - (ctx.get_reg(src) & 0x5555555555555555ULL)))))) ^ ((((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & 0x5555555555555555ULL) + ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & 0xaaaaaaaaaaaaaaaaULL)) | (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL)))) + (((((((ctx.get_reg(dst) & 0x5555555555555555ULL) + (ctx.get_reg(src) & 0x5555555555555555ULL)) - ((ctx.get_reg(dst) & 0x5555555555555555ULL) & (ctx.get_reg(src) & 0x5555555555555555ULL))) + ((((ctx.get_reg(dst) & 0x5555555555555555ULL) & (ctx.get_reg(src) & 0x5555555555555555ULL)) + ((ctx.get_reg(dst) & 0x5555555555555555ULL) & (~((ctx.get_reg(src) & 0x5555555555555555ULL))))) - (ctx.get_reg(dst) & 0x5555555555555555ULL))) | ((((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & 0x5555555555555555ULL) + ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & 0xaaaaaaaaaaaaaaaaULL)) | (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))) + (((((ctx.get_reg(dst) & 0x5555555555555555ULL) + (ctx.get_reg(src) & 0x5555555555555555ULL)) - ((ctx.get_reg(dst) & 0x5555555555555555ULL) & (ctx.get_reg(src) & 0x5555555555555555ULL))) + ((((ctx.get_reg(dst) & 0x5555555555555555ULL) & (ctx.get_reg(src) & 0x5555555555555555ULL)) + ((ctx.get_reg(dst) & 0x5555555555555555ULL) & (~((ctx.get_reg(src) & 0x5555555555555555ULL))))) - (ctx.get_reg(dst) & 0x5555555555555555ULL))) & ((((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & 0x5555555555555555ULL) + ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & 0xaaaaaaaaaaaaaaaaULL)) | (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL)))) - (ctx.get_reg(dst) | ctx.get_reg(src)))) ^ ((((((0x0000000000000002ULL * (((((ctx.get_reg(dst) & 0x5555555555555555ULL) + (ctx.get_reg(src) & 0x5555555555555555ULL)) - ((ctx.get_reg(dst) & 0x5555555555555555ULL) & (ctx.get_reg(src) & 0x5555555555555555ULL))) + ((((ctx.get_reg(dst) & 0x5555555555555555ULL) & (ctx.get_reg(src) & 0x5555555555555555ULL)) + ((ctx.get_reg(dst) & 0x5555555555555555ULL) & (~((ctx.get_reg(src) & 0x5555555555555555ULL))))) - (ctx.get_reg(dst) & 0x5555555555555555ULL))) | ((((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & 0x5555555555555555ULL) + ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & 0xaaaaaaaaaaaaaaaaULL)) | (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL)))) - ((((~(((~ctx.get_reg(dst)) | (~0x5555555555555555ULL)))) ^ ((ctx.get_reg(src) - (ctx.get_reg(src) & (~0x5555555555555555ULL))) + ((ctx.get_reg(src) ^ 0x5555555555555555ULL) - ((ctx.get_reg(src) | 0x5555555555555555ULL) - (ctx.get_reg(src) & 0x5555555555555555ULL))))) + ((~(((~ctx.get_reg(dst)) | (~0x5555555555555555ULL)))) & ((ctx.get_reg(src) - (ctx.get_reg(src) & (~0x5555555555555555ULL))) + ((ctx.get_reg(src) ^ 0x5555555555555555ULL) - ((ctx.get_reg(src) | 0x5555555555555555ULL) - (ctx.get_reg(src) & 0x5555555555555555ULL)))))) ^ ((((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & 0x5555555555555555ULL) + ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & 0xaaaaaaaaaaaaaaaaULL)) | (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL)))) + (((((((ctx.get_reg(dst) & 0x5555555555555555ULL) + (ctx.get_reg(src) & 0x5555555555555555ULL)) - ((ctx.get_reg(dst) & 0x5555555555555555ULL) & (ctx.get_reg(src) & 0x5555555555555555ULL))) + ((((ctx.get_reg(dst) & 0x5555555555555555ULL) & (ctx.get_reg(src) & 0x5555555555555555ULL)) + ((ctx.get_reg(dst) & 0x5555555555555555ULL) & (~((ctx.get_reg(src) & 0x5555555555555555ULL))))) - (ctx.get_reg(dst) & 0x5555555555555555ULL))) | ((((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & 0x5555555555555555ULL) + ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & 0xaaaaaaaaaaaaaaaaULL)) | (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))) + (((((ctx.get_reg(dst) & 0x5555555555555555ULL) + (ctx.get_reg(src) & 0x5555555555555555ULL)) - ((ctx.get_reg(dst) & 0x5555555555555555ULL) & (ctx.get_reg(src) & 0x5555555555555555ULL))) + ((((ctx.get_reg(dst) & 0x5555555555555555ULL) & (ctx.get_reg(src) & 0x5555555555555555ULL)) + ((ctx.get_reg(dst) & 0x5555555555555555ULL) & (~((ctx.get_reg(src) & 0x5555555555555555ULL))))) - (ctx.get_reg(dst) & 0x5555555555555555ULL))) & ((((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & 0x5555555555555555ULL) + ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & 0xaaaaaaaaaaaaaaaaULL)) | (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL)))) - (ctx.get_reg(dst) | ctx.get_reg(src)))) & 0x000000007fffffffULL) * 0x1db0caf2e7fdb945ULL) << 0x0000000000000021ULL)) & 0x000000007fffffffULL) * 0x1db0caf2e7fdb945ULL) << 0x0000000000000021ULL))); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_OR_RI_D1: { PROBE_START(); ctx.set_reg(dst, (ctx.get_reg(dst) | static_cast<uint64_t>(imm))); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_ROL_RI_D1: {
        uint64_t val = ctx.get_reg(dst); uint32_t shift = (uint32_t)(imm & 63);
        ctx.set_reg(dst, (val << shift) | (val >> ((64 - shift) & 63)));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_ROR_RI_D1: {
        uint64_t v = ctx.get_reg(dst); uint32_t s = (uint32_t)(imm & 63);
        ctx.set_reg(dst, (v >> s) | (v << ((64 - s) & 63)));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_SHL_RI_D1: {
        uint64_t _res = ctx.get_reg(dst) << (uint32_t)(imm & 63);
        ctx.set_reg(dst, _res);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_SHR_RI_D1: {
        uint64_t v = ctx.get_reg(dst); uint32_t s = static_cast<uint32_t>(imm & 63);
        ctx.set_reg(dst, v >> s);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_SAR_RI_D1: {
        uint64_t val = ctx.get_reg(dst); uint32_t shift = (uint32_t)(imm & 63);
        ctx.set_reg(dst, (uint64_t)((int64_t)val >> shift));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_ROL_RR_D1: {
        uint64_t val = ctx.get_reg(dst); uint32_t shift = (uint32_t)(ctx.get_reg(src) & 63);
        ctx.set_reg(dst, (val << shift) | (val >> ((64 - shift) & 63)));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_ROR_RR_D1: {
        uint64_t val = ctx.get_reg(dst); uint32_t shift = (uint32_t)(ctx.get_reg(src) & 63);
        ctx.set_reg(dst, (val >> shift) | (val << ((64 - shift) & 63)));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_SHL_RR_D1: {
        uint64_t val = ctx.get_reg(dst); uint32_t shift = (uint32_t)(ctx.get_reg(src) & 63);
        ctx.set_reg(dst, val << shift);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_SHR_RR_D1: {
        uint64_t _res = ctx.get_reg(dst) >> (uint32_t)(ctx.get_reg(src) & 63);
        ctx.set_reg(dst, _res);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_SAR_RR_D1: {
        uint64_t _res = (uint64_t)((int64_t)ctx.get_reg(dst) >> (uint32_t)(ctx.get_reg(src) & 63));
        ctx.set_reg(dst, _res);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_DIV_RR_D1: {
        uint64_t _divisor = ctx.get_reg(src);
        if (_divisor == 0ULL) { ctx.trapped = true; goto EXIT_VM; }
        uint64_t _dividend = ctx.get_reg(dst);
        ctx.set_reg(dst, _dividend / _divisor);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_IDIV_RR_D1: {
        int64_t _d = static_cast<int64_t>(ctx.get_reg(dst)), _s = static_cast<int64_t>(ctx.get_reg(src));
        if (_s == 0 || (_s == -1 && _d == INT64_MIN)) { ctx.trapped = true; goto EXIT_VM; }
        int64_t _quot = (_s == -1) ? (-_d) : (_d / _s);
        ctx.set_reg(dst, static_cast<uint64_t>(_quot));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_MULH_RR_D1: {
        uint64_t a = ctx.get_reg(dst); uint64_t b = ctx.get_reg(src);
        #if defined(__SIZEOF_INT128__)
        uint64_t res = (uint64_t)(((unsigned __int128)a * (unsigned __int128)b) >> 64);
        #else
        uint64_t a_lo = (uint32_t)a, a_hi = a >> 32;
        uint64_t b_lo = (uint32_t)b, b_hi = b >> 32;
        uint64_t p0 = a_lo * b_lo;
        uint64_t p1 = a_lo * b_hi;
        uint64_t p2 = a_hi * b_lo;
        uint64_t p3 = a_hi * b_hi;
        uint64_t cy = ((p0 >> 32) + (uint32_t)p1 + (uint32_t)p2) >> 32;
        uint64_t res = p3 + (p1 >> 32) + (p2 >> 32) + cy;
        #endif
        ctx.set_reg(dst, res);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_IMULH_RR_D1: {
        #if defined(__SIZEOF_INT128__)
        uint64_t res = (uint64_t)(((signed __int128)(int64_t)ctx.get_reg(dst) * (signed __int128)(int64_t)ctx.get_reg(src)) >> 64);
        #else
        int64_t a = (int64_t)ctx.get_reg(dst); int64_t b = (int64_t)ctx.get_reg(src);
        uint64_t ua = (uint64_t)a, ub = (uint64_t)b;
        uint64_t a_lo = (uint32_t)ua, a_hi = ua >> 32;
        uint64_t b_lo = (uint32_t)ub, b_hi = ub >> 32;
        uint64_t cy = (((a_lo * b_lo) >> 32) + (uint32_t)(a_lo * b_hi) + (uint32_t)(a_hi * b_lo)) >> 32;
        uint64_t res = (a_hi * b_hi) + ((a_lo * b_hi) >> 32) + ((a_hi * b_lo) >> 32) + cy;
        if (a < 0) res -= ub;
        if (b < 0) res -= ua;
        #endif
        ctx.set_reg(dst, res);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_CMP_RI_D1: {
        PROBE_START();
        uint64_t _d = ctx.get_reg(dst);
        compute_sub_flags(ctx, _d, static_cast<uint64_t>(imm), static_cast<uint32_t>((word >> 50) & 0x7F));
        PROBE_CHECK();
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_CMP_RR_D1: {
        PROBE_START();
        uint32_t bits = static_cast<uint32_t>((word >> 50) & 0x7F);
        compute_sub_flags(ctx, ctx.get_reg(dst), ctx.get_reg(src), bits);
        PROBE_CHECK();
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_PUSH_R_D1: {
        uint64_t val = ctx.get_reg(dst);
        ctx.push(val);
        uint64_t cur_sp = ctx.get_reg(REG_RSP);
        if (cur_sp >= 0x10008ULL && cur_sp <= 0x7FFFFFFFFFFFULL) {
            uint64_t* sp_ptr = reinterpret_cast<uint64_t*>(cur_sp - 8ULL);
            ctx.set_reg(REG_RSP, reinterpret_cast<uint64_t>(sp_ptr));
            *sp_ptr = val;
        }
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_POP_R_D1: {
        uint64_t cur_sp = ctx.get_reg(REG_RSP);
        uint64_t val = 0;
        if (cur_sp >= 0x10000ULL && cur_sp <= 0x7FFFFFFFFFFFULL) {
            val = *reinterpret_cast<const uint64_t*>(cur_sp);
            ctx.set_reg(REG_RSP, cur_sp + 8ULL);
            ctx.pop();
        } else {
            val = ctx.pop();
        }
        ctx.set_reg(dst, val);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_ADC_RR_D1: {
        uint64_t a = ctx.get_reg(dst); uint64_t b = ctx.get_reg(src);
        uint64_t c = ctx.cf ? 1ULL : 0ULL;
        uint64_t res = a + b + c;
        ctx.cf = (res < a) || (c && res == a);
        ctx.of = ((((a ^ res) & (b ^ res)) >> 63) != 0);
        ctx.zf = (res == 0);
        ctx.sf = ((int64_t)res < 0);
        ctx.set_reg(dst, res);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_ADC_RI_D1: {
        uint64_t a = ctx.get_reg(dst); uint64_t b = (uint64_t)imm;
        uint64_t c = ctx.cf ? 1ULL : 0ULL;
        uint64_t ab = a + b;
        uint64_t res = ab + c;
        ctx.cf = (ab < a) || (res < ab);
        ctx.of = ((((a ^ res) & (b ^ res)) >> 63) != 0);
        ctx.zf = (res == 0);
        ctx.sf = ((int64_t)res < 0);
        ctx.set_reg(dst, res);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_SBB_RR_D1: {
        uint64_t a = ctx.get_reg(dst); uint64_t b = ctx.get_reg(src);
        uint64_t borrow = static_cast<uint64_t>(ctx.cf);
        uint64_t res = (a - b) - borrow;
        ctx.cf = (a < b) || (borrow && a == b);
        ctx.zf = (res == 0);
        ctx.sf = (res >> 63) != 0;
        ctx.of = (((a ^ b) & (a ^ res)) >> 63) != 0;
        ctx.set_reg(dst, res);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_SBB_RI_D1: {
        uint64_t a = ctx.get_reg(dst); uint64_t b = (uint64_t)imm;
        uint64_t borrow = static_cast<uint64_t>(ctx.cf);
        uint64_t res = (a - b) - borrow;
        ctx.cf = (a < b) || (borrow && a == b);
        ctx.zf = (res == 0);
        ctx.sf = (res >> 63) != 0;
        ctx.of = (((a ^ b) & (a ^ res)) >> 63) != 0;
        ctx.set_reg(dst, res);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_CCMP_RR_D1: {
        uint8_t cond = (uint8_t)((((word >> 18) + 0x0FULL) - ((word >> 18) | 0x0FULL)));
        uint8_t nzcv = (uint8_t)((((word >> 22) + 0x0FULL) - ((word >> 22) | 0x0FULL)));
        uint32_t bits = (uint32_t)((((word >> 50) + 0x7FULL) - ((word >> 50) | 0x7FULL)));
        if (!eval_condition(ctx, cond)) {
            ctx.sf = (nzcv & 8) != 0;
            ctx.zf = (nzcv & 4) != 0;
            ctx.cf = (nzcv & 2) != 0;
            ctx.of = (nzcv & 1) != 0;
        } else {
            uint64_t a = ctx.get_reg(dst); uint64_t b = ctx.get_reg(src);
            compute_sub_flags(ctx, a, b, bits);
        }
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_CCMP_RI_D1: {
        uint8_t cond = (uint8_t)((((word >> 18) + 0x0FULL) - ((word >> 18) | 0x0FULL)));
        uint8_t nzcv = (uint8_t)((((word >> 22) + 0x0FULL) - ((word >> 22) | 0x0FULL)));
        uint64_t b = (uint64_t)((((word >> 26) + 0x1FULL) - ((word >> 26) | 0x1FULL)));
        uint32_t bits = (uint32_t)((((word >> 50) + 0x7FULL) - ((word >> 50) | 0x7FULL)));
        if (eval_condition(ctx, cond)) {
            uint64_t a = ctx.get_reg(dst);
            compute_sub_flags(ctx, a, b, bits);
        } else {
            ctx.sf = (nzcv & 8) != 0;
            ctx.zf = (nzcv & 4) != 0;
            ctx.cf = (nzcv & 2) != 0;
            ctx.of = (nzcv & 1) != 0;
        }
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_CCMN_RR_D1: {
        uint8_t cond = (uint8_t)((((word >> 18) + 0x0FULL) - ((word >> 18) | 0x0FULL)));
        uint8_t nzcv = (uint8_t)((((word >> 22) + 0x0FULL) - ((word >> 22) | 0x0FULL)));
        uint32_t bits = (uint32_t)((((word >> 50) + 0x7FULL) - ((word >> 50) | 0x7FULL)));
        if (!eval_condition(ctx, cond)) {
            ctx.sf = (nzcv & 8) != 0;
            ctx.zf = (nzcv & 4) != 0;
            ctx.cf = (nzcv & 2) != 0;
            ctx.of = (nzcv & 1) != 0;
        } else {
            uint64_t a = ctx.get_reg(dst); uint64_t b = ctx.get_reg(src);
            compute_add_flags(ctx, a, b, bits);
        }
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_CCMN_RI_D1: {
        uint8_t cond = (uint8_t)((((word >> 18) + 0x0FULL) - ((word >> 18) | 0x0FULL)));
        uint8_t nzcv = (uint8_t)((((word >> 22) + 0x0FULL) - ((word >> 22) | 0x0FULL)));
        uint64_t b = (uint64_t)((((word >> 26) + 0x1FULL) - ((word >> 26) | 0x1FULL)));
        uint32_t bits = (uint32_t)((((word >> 50) + 0x7FULL) - ((word >> 50) | 0x7FULL)));
        if (!eval_condition(ctx, cond)) {
            ctx.sf = (nzcv & 8) != 0;
            ctx.zf = (nzcv & 4) != 0;
            ctx.cf = (nzcv & 2) != 0;
            ctx.of = (nzcv & 1) != 0;
        } else {
            uint64_t a = ctx.get_reg(dst);
            compute_add_flags(ctx, a, b, bits);
        }
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_GET_FLAGS_R_D1: {
        uint64_t f = 2ULL;
        f |= (uint64_t)ctx.cf;
        f |= ((uint64_t)ctx.zf << 6);
        f |= ((uint64_t)ctx.sf << 7);
        f |= ((uint64_t)ctx.of << 11);
        ctx.set_reg(dst, f);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_SET_FLAGS_R_D1: {
        uint64_t f = ctx.get_reg(src);
        ctx.cf = (f & 1ULL) != 0;
        ctx.zf = (f & 0x40ULL) != 0;
        ctx.sf = (f & 0x80ULL) != 0;
        ctx.of = (f & 0x800ULL) != 0;
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_JMP_D1: {
        #if defined(__APPLE__)
        vIP_idx = static_cast<size_t>(imm);
        #elif defined(_WIN32)
        asgard_nanomites::g_nanomite_dispatcher.current_trap_id = static_cast<uint32_t>(vIP_idx);
        asgard_nanomites::g_nanomite_dispatcher.current_condition = 1;
        asgard_nanomites::g_nanomite_dispatcher.register_nanomite(static_cast<uint32_t>(vIP_idx), static_cast<uint64_t>(imm), static_cast<uint64_t>(imm), static_cast<uint64_t>((seed ^ static_cast<uint32_t>(vIP_idx))));
        __debugbreak();
        vIP_idx = ((asgard_nanomites::g_nanomite_dispatcher.resolved_target != 0) ? static_cast<size_t>(asgard_nanomites::g_nanomite_dispatcher.resolved_target) : static_cast<size_t>(imm));
        #elif defined(__linux__) && !defined(_MSC_VER)
        asgard_nanomites::g_nanomite_dispatcher.current_trap_id = static_cast<uint32_t>(vIP_idx);
        asgard_nanomites::g_nanomite_dispatcher.current_condition = 1;
        asgard_nanomites::g_nanomite_dispatcher.register_nanomite(static_cast<uint32_t>(vIP_idx), static_cast<uint64_t>(imm), static_cast<uint64_t>(imm), static_cast<uint64_t>((seed ^ static_cast<uint32_t>(vIP_idx))));
        raise(SIGTRAP);
        vIP_idx = ((asgard_nanomites::g_nanomite_dispatcher.resolved_target != 0) ? static_cast<size_t>(asgard_nanomites::g_nanomite_dispatcher.resolved_target) : static_cast<size_t>(imm));
        #else
        vIP_idx = static_cast<size_t>(imm);
        #endif
        ctx.reanchor_running_key(static_cast<uint64_t>(vIP_idx));
        ctx.executed_instructions++;
        FETCH_NEXT();
    }
    H_JCC_D1: {
        PROBE_START();
        uint8_t cond = static_cast<uint8_t>((((word >> 0x0000000000000012ULL) + 0x000000000000000fULL) - ((word >> 0x0000000000000012ULL) | 0x000000000000000fULL)));
        uint64_t base_vip = static_cast<uint64_t>(((word >> 0x0000000000000016ULL) & 0x00000000001fffffULL));
        uint64_t enc_delta = static_cast<uint64_t>(((word >> 0x000000000000002bULL) & 0x00000000001fffffULL));
        uint64_t salt = (((static_cast<uint64_t>(cond) * 0x0000000000005877ULL) ^ 0x000000001337beefULL) & 0x00000000001fffffULL);
        uint64_t delta = (enc_delta ^ salt);
        uint64_t t_true = (base_vip ^ delta);
        uint64_t t_false = base_vip;
        uint64_t c = (eval_condition(ctx, cond) ? 0x0000000000000001ULL : 0x0000000000000000ULL);
        #if defined(__APPLE__)
        vIP_idx = static_cast<size_t>(((c * t_true) + ((0x0000000000000001ULL - c) * t_false)));
        #elif defined(_WIN32)
        asgard_nanomites::g_nanomite_dispatcher.current_trap_id = static_cast<uint32_t>(vIP_idx);
        asgard_nanomites::g_nanomite_dispatcher.current_condition = static_cast<uint32_t>(c);
        asgard_nanomites::g_nanomite_dispatcher.register_nanomite(static_cast<uint32_t>(vIP_idx), t_true, t_false, static_cast<uint64_t>((seed ^ static_cast<uint32_t>(vIP_idx))));
        __debugbreak();
        vIP_idx = ((asgard_nanomites::g_nanomite_dispatcher.resolved_target != 0) ? static_cast<size_t>(asgard_nanomites::g_nanomite_dispatcher.resolved_target) : static_cast<size_t>(((c * t_true) + ((0x0000000000000001ULL - c) * t_false))));
        #elif defined(__linux__) && !defined(_MSC_VER)
        asgard_nanomites::g_nanomite_dispatcher.current_trap_id = static_cast<uint32_t>(vIP_idx);
        asgard_nanomites::g_nanomite_dispatcher.current_condition = static_cast<uint32_t>(c);
        asgard_nanomites::g_nanomite_dispatcher.register_nanomite(static_cast<uint32_t>(vIP_idx), t_true, t_false, static_cast<uint64_t>((seed ^ static_cast<uint32_t>(vIP_idx))));
        raise(SIGTRAP);
        vIP_idx = ((asgard_nanomites::g_nanomite_dispatcher.resolved_target != 0) ? static_cast<size_t>(asgard_nanomites::g_nanomite_dispatcher.resolved_target) : static_cast<size_t>(((c * t_true) + ((0x0000000000000001ULL - c) * t_false))));
        #else
        vIP_idx = static_cast<size_t>(((c * t_true) + ((0x0000000000000001ULL - c) * t_false)));
        #endif
        ctx.reanchor_running_key(static_cast<uint64_t>(vIP_idx));
        PROBE_CHECK();
        ctx.executed_instructions++;
        FETCH_NEXT();
    }
    H_CMOV_D1: {
        PROBE_START();
        uint8_t cond = static_cast<uint8_t>((((word >> 0x0000000000000012ULL) + 0x000000000000000fULL) - ((word >> 0x0000000000000012ULL) | 0x000000000000000fULL)));
        if (eval_condition(ctx, cond)) {
                                    ctx.set_reg(dst, ctx.get_reg(src));
}
        PROBE_CHECK();
        ctx.executed_instructions++;
        FETCH_NEXT();
    }
    H_SETCC_D1: {
        PROBE_START();
        uint8_t cond = static_cast<uint8_t>((((word >> 0x0000000000000012ULL) + 0x000000000000000fULL) - ((word >> 0x0000000000000012ULL) | 0x000000000000000fULL)));
        uint64_t val = (eval_condition(ctx, cond) ? 0x0000000000000001ULL : 0x0000000000000000ULL);
        ctx.set_reg(dst, val);
        PROBE_CHECK();
        ctx.executed_instructions++;
        FETCH_NEXT();
    }
    H_CALL_D1: {
        ctx.push(static_cast<uint64_t>(vIP_idx));
        #if defined(__APPLE__)
        vIP_idx = static_cast<size_t>(imm);
        #elif defined(_WIN32)
        asgard_nanomites::g_nanomite_dispatcher.current_trap_id = static_cast<uint32_t>(vIP_idx);
        asgard_nanomites::g_nanomite_dispatcher.current_condition = 1;
        asgard_nanomites::g_nanomite_dispatcher.register_nanomite(static_cast<uint32_t>(vIP_idx), static_cast<uint64_t>(imm), static_cast<uint64_t>(imm), static_cast<uint64_t>((seed ^ static_cast<uint32_t>(vIP_idx))));
        __debugbreak();
        vIP_idx = ((asgard_nanomites::g_nanomite_dispatcher.resolved_target != 0) ? static_cast<size_t>(asgard_nanomites::g_nanomite_dispatcher.resolved_target) : static_cast<size_t>(imm));
        #elif defined(__linux__) && !defined(_MSC_VER)
        asgard_nanomites::g_nanomite_dispatcher.current_trap_id = static_cast<uint32_t>(vIP_idx);
        asgard_nanomites::g_nanomite_dispatcher.current_condition = 1;
        asgard_nanomites::g_nanomite_dispatcher.register_nanomite(static_cast<uint32_t>(vIP_idx), static_cast<uint64_t>(imm), static_cast<uint64_t>(imm), static_cast<uint64_t>((seed ^ static_cast<uint32_t>(vIP_idx))));
        raise(SIGTRAP);
        vIP_idx = ((asgard_nanomites::g_nanomite_dispatcher.resolved_target != 0) ? static_cast<size_t>(asgard_nanomites::g_nanomite_dispatcher.resolved_target) : static_cast<size_t>(imm));
        #else
        vIP_idx = static_cast<size_t>(imm);
        #endif
        ctx.reanchor_running_key(static_cast<uint64_t>(vIP_idx));
        ctx.executed_instructions++;
        FETCH_NEXT();
    }
    H_IJMP_R_D1: {
        uint64_t target = ctx.get_reg(dst);
        if (target < count) {
                         vIP_idx = static_cast<size_t>(target);
} else {
            if (target != 0x0000000000000000ULL) {
                                                      #if defined(__x86_64__) || defined(_M_X64)
                                                      uint64_t a0 = ctx.get_reg(REG_RDI);
                                                      uint64_t a1 = ctx.get_reg(REG_RSI);
                                                      uint64_t a2 = ctx.get_reg(REG_RDX);
                                                      uint64_t a3 = ctx.get_reg(REG_RCX);
                                                      uint64_t a4 = ctx.get_reg(REG_R8);
                                                      uint64_t a5 = ctx.get_reg(REG_R9);
                                                      #else
                                                      uint64_t a0 = ctx.get_reg(REG_RAX);
                                                      uint64_t a1 = ctx.get_reg(REG_RCX);
                                                      uint64_t a2 = ctx.get_reg(REG_RDX);
                                                      uint64_t a3 = ctx.get_reg(REG_RBX);
                                                      uint64_t a4 = ctx.get_reg(REG_RSI);
                                                      uint64_t a5 = ctx.get_reg(REG_RDI);
                                                      #endif
                                                      typedef uint64_t (*indirect_fn_t)(uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t);
                                                      indirect_fn_t fn = reinterpret_cast<indirect_fn_t>(target);
                                                      uint64_t ret_val = fn(a0, a1, a2, a3, a4, a5);
                                                      ctx.set_reg(REG_RAX, ret_val);
                                                      goto EXIT_VM;
            }
}
        ctx.reanchor_running_key(static_cast<uint64_t>(vIP_idx));
        ctx.executed_instructions++;
        FETCH_NEXT();
    }
    H_ICALL_R_D1: {
        uint64_t target_ptr = ctx.get_reg(dst);
        if (target_ptr < count) {
                             ctx.push(static_cast<uint64_t>(vIP_idx));
                             vIP_idx = static_cast<size_t>(target_ptr);
} else {
            if (target_ptr != 0x0000000000000000ULL) {
                                                          #if defined(__x86_64__) || defined(_M_X64)
                                                          uint64_t a0 = ctx.get_reg(REG_RDI);
                                                          uint64_t a1 = ctx.get_reg(REG_RSI);
                                                          uint64_t a2 = ctx.get_reg(REG_RDX);
                                                          uint64_t a3 = ctx.get_reg(REG_RCX);
                                                          uint64_t a4 = ctx.get_reg(REG_R8);
                                                          uint64_t a5 = ctx.get_reg(REG_R9);
                                                          #else
                                                          uint64_t a0 = ctx.get_reg(REG_RAX);
                                                          uint64_t a1 = ctx.get_reg(REG_RCX);
                                                          uint64_t a2 = ctx.get_reg(REG_RDX);
                                                          uint64_t a3 = ctx.get_reg(REG_RBX);
                                                          uint64_t a4 = ctx.get_reg(REG_RSI);
                                                          uint64_t a5 = ctx.get_reg(REG_RDI);
                                                          #endif
                                                          typedef uint64_t (*indirect_fn_t)(uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t);
                                                          indirect_fn_t fn = reinterpret_cast<indirect_fn_t>(target_ptr);
                                                          uint64_t ret_val = fn(a0, a1, a2, a3, a4, a5);
                                                          ctx.set_reg(REG_RAX, ret_val);
            }
}
        ctx.reanchor_running_key(static_cast<uint64_t>(vIP_idx));
        ctx.executed_instructions++;
        FETCH_NEXT();
    }
    H_RET_D1: { if (ctx.sp > 512) {
                       ctx.trapped = true;
} ctx.executed_instructions += 1; goto EXIT_VM; }
    H_EXIT_D1: { if (ctx.sp > 512) {
                       ctx.trapped = true;
} ctx.executed_instructions += 1; goto EXIT_VM; }

    H_BRIDGE_TO_FLOW_D1: {
        uint64_t _imm_flow = static_cast<uint64_t>(imm);
        ctx.morph_math_to_flow(_imm_flow);
        ctx.executed_instructions += 1;
        FETCH_NEXT();
    }
    H_BRIDGE_TO_MATH_D1: {
        ctx.morph_flow_to_math(static_cast<uint64_t>((imm & 0xffffffffffffffffULL)));
        ctx.executed_instructions++;
        FETCH_NEXT();
    }
    H_FUSED_MOV_ADD_RRI_D1: {
        ctx.set_reg(dst, (ctx.get_reg(src) + static_cast<uint64_t>(imm)));
        ctx.executed_instructions += 2;
        FETCH_NEXT();
    }
    H_FUSED_ADD_IMUL_RRI_D1: {
        uint64_t _imm = static_cast<uint64_t>(imm);
        uint64_t _res = ((ctx.get_reg(dst) * _imm) + (ctx.get_reg(src) * _imm));
        ctx.set_reg(dst, _res);
        ctx.executed_instructions += 2;
        FETCH_NEXT();
    }
    H_FUSED_ADD_XOR_RRI_D1: {
        uint64_t _sum = (ctx.get_reg(dst) + ctx.get_reg(src));
        uint64_t _imm = static_cast<uint64_t>(imm);
        ctx.set_reg(dst, ((_sum + _imm) - (0x0000000000000002ULL * (_sum & _imm))));
        ctx.executed_instructions += 2;
        FETCH_NEXT();
    }
    H_FUSED_SUB_XOR_RRI_D1: {
        ctx.set_reg(dst, ((ctx.get_reg(dst) - ctx.get_reg(src)) ^ static_cast<uint64_t>(imm)));
        ctx.executed_instructions += 2;
        FETCH_NEXT();
    }
    H_FUSED_XOR_ADD_RRI_D1: {
        uint64_t _a = ctx.get_reg(dst);
        uint64_t _b = ctx.get_reg(src);
        uint64_t _x = ((_a + _b) - (0x0000000000000002ULL * (_a & _b)));
        ctx.set_reg(dst, (_x + static_cast<uint64_t>(imm)));
        ctx.executed_instructions += 2;
        FETCH_NEXT();
    }
    H_FUSED_CMP_CMOV_D1: {
        uint64_t a = ctx.get_reg(dst);
        uint64_t b = static_cast<uint64_t>(imm);
        uint8_t cond = static_cast<uint8_t>(((word >> 0x0000000000000032ULL) & 0x000000000000000fULL));
        uint32_t bits = static_cast<uint32_t>(((word >> 0x0000000000000036ULL) & 0x000000000000007fULL));
        compute_sub_flags(ctx, a, b, bits);
        uint64_t _m = (eval_condition(ctx, cond) ? (~0x0000000000000000ULL) : 0x0000000000000000ULL);
        ctx.set_reg(dst, ((ctx.get_reg(src) & _m) | (a & (~_m))));
        ctx.executed_instructions += 2;
        FETCH_NEXT();
    }
    H_FUSED_AND_OR_RRI_D1: {
        uint64_t _and = (ctx.get_reg(dst) & ctx.get_reg(src));
        ctx.set_reg(dst, (_and | static_cast<uint64_t>(imm)));
        ctx.executed_instructions += 2;
        FETCH_NEXT();
    }
    H_FUSED_SHL_ADD_RRI_D1: {
        uint64_t _shl = (ctx.get_reg(dst) << (static_cast<uint64_t>(imm) & 0x000000000000003fULL));
        uint64_t _s = ctx.get_reg(src);
        ctx.set_reg(dst, ((_shl ^ _s) + (0x0000000000000002ULL * (_shl & _s))));
        ctx.executed_instructions += 2;
        FETCH_NEXT();
    }
    H_VADD_VV_D1: {
        uint64_t d0 = ctx.get_vreg_lane(dst, 0), d1 = ctx.get_vreg_lane(dst, 1);
        uint64_t s0 = ctx.get_vreg_lane(src, 0), s1 = ctx.get_vreg_lane(src, 1);
        uint64_t _res0 = d0 + s0; uint64_t _res1 = d1 + s1;
        ctx.set_vreg(dst, _res0, _res1);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_VSUB_VV_D1: {
        uint64_t d0 = ctx.get_vreg_lane(dst, 0), d1 = ctx.get_vreg_lane(dst, 1);
        uint64_t s0 = ctx.get_vreg_lane(src, 0), s1 = ctx.get_vreg_lane(src, 1);
        uint64_t _res0 = d0 - s0; uint64_t _res1 = d1 - s1;
        ctx.set_vreg(dst, _res0, _res1);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_VMUL_VV_D1: {
        uint64_t d0 = ctx.get_vreg_lane(dst, 0), d1 = ctx.get_vreg_lane(dst, 1);
        uint64_t s0 = ctx.get_vreg_lane(src, 0), s1 = ctx.get_vreg_lane(src, 1);
        ctx.set_vreg(dst, d0 * s0, d1 * s1);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_VXOR_VV_D1: {
        uint64_t d0 = ctx.get_vreg_lane(dst, 0), d1 = ctx.get_vreg_lane(dst, 1);
        uint64_t s0 = ctx.get_vreg_lane(src, 0), s1 = ctx.get_vreg_lane(src, 1);
        uint64_t _res0 = d0 ^ s0; uint64_t _res1 = d1 ^ s1;
        ctx.set_vreg(dst, _res0, _res1);
        ctx.executed_instructions++; FETCH_NEXT();
    }

    H_VEC_MOV_D1: {
        uint32_t bits = (uint32_t)(imm & 0x3ff);
        for (size_t i = 0; i < (bits + 63) / 64; ++i) ctx.set_vreg_lane(dst, i, ctx.get_vreg_lane(src, i));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_VEC_BINOP_D1: {
        uint32_t src2 = (uint32_t)(imm & 31);
        uint32_t bits = (uint32_t)((imm >> 5) & 0x3ff);
        uint32_t lane_bits = (uint32_t)((imm >> 15) & 0xff);
        if (lane_bits == 0) lane_bits = 64;
        uint32_t vop = (uint32_t)((imm >> 23) & 0x1f);
        uint32_t elem = (uint32_t)((imm >> 28) & 0x3);
        uint64_t mask = lane_bits == 8 ? 0xffULL : (lane_bits == 16 ? 0xffffULL : (lane_bits == 32 ? 0xffffffffULL : ~0ULL));
        for (size_t bit = 0; bit < bits; bit += lane_bits) {
            size_t chunk = bit / 64; unsigned shift = (unsigned)(bit % 64);
            uint64_t a = (ctx.get_vreg_lane(src, chunk) >> shift) & mask;
            uint64_t b = (ctx.get_vreg_lane(src2, chunk) >> shift) & mask;
            uint64_t value = 0;
            if (elem == 1 && vop <= 2) {
                float fa = std::bit_cast<float>(static_cast<uint32_t>(a));
                float fb = std::bit_cast<float>(static_cast<uint32_t>(b));
                float fr = vop == 0 ? fa + fb : (vop == 1 ? fa - fb : fa * fb);
                value = std::bit_cast<uint32_t>(fr);
            } else if (elem == 1 && vop == 11) {
                float fa = std::bit_cast<float>(static_cast<uint32_t>(a));
                float fb = std::bit_cast<float>(static_cast<uint32_t>(b));
                value = std::bit_cast<uint32_t>(std::fmin(fa, fb));
            } else if (elem == 1 && vop == 12) {
                float fa = std::bit_cast<float>(static_cast<uint32_t>(a));
                float fb = std::bit_cast<float>(static_cast<uint32_t>(b));
                value = std::bit_cast<uint32_t>(std::fmax(fa, fb));
            } else if (elem == 2 && vop <= 2) {
                double fa = std::bit_cast<double>(a);
                double fb = std::bit_cast<double>(b);
                double fr = vop == 0 ? fa + fb : (vop == 1 ? fa - fb : fa * fb);
                value = std::bit_cast<uint64_t>(fr);
            } else if (elem == 2 && vop == 11) {
                double fa = std::bit_cast<double>(a);
                double fb = std::bit_cast<double>(b);
                value = std::bit_cast<uint64_t>(std::fmin(fa, fb));
            } else if (elem == 2 && vop == 12) {
                double fa = std::bit_cast<double>(a);
                double fb = std::bit_cast<double>(b);
                value = std::bit_cast<uint64_t>(std::fmax(fa, fb));
            } else {
                int64_t sa = lane_bits == 8 ? (int64_t)(int8_t)a : (lane_bits == 16 ? (int64_t)(int16_t)a : (lane_bits == 32 ? (int64_t)(int32_t)a : (int64_t)a));
                int64_t sb = lane_bits == 8 ? (int64_t)(int8_t)b : (lane_bits == 16 ? (int64_t)(int16_t)b : (lane_bits == 32 ? (int64_t)(int32_t)b : (int64_t)b));
                switch (vop) {
                    case 0: value = a + b; break;
                    case 1: value = a - b; break;
                    case 2: value = a * b; break;
                    case 3: value = a & b; break;
                    case 4: value = a | b; break;
                    case 5: value = a ^ b; break;
                    case 6: { uint32_t cnt = (uint32_t)(ctx.get_vreg_lane(src2, 0) & 0xff); value = (cnt >= lane_bits) ? 0 : (a << cnt); break; }
                    case 7: { uint32_t cnt = (uint32_t)(ctx.get_vreg_lane(src2, 0) & 0xff); value = (cnt >= lane_bits) ? 0 : (a >> cnt); break; }
                    case 8: { uint32_t cnt = (uint32_t)(ctx.get_vreg_lane(src2, 0) & 0xff); value = (cnt >= lane_bits) ? (sa < 0 ? mask : 0) : ((uint64_t)(sa >> cnt) & mask); break; }
                    case 9: value = (a == b) ? mask : 0; break;
                    case 10: value = (sa > sb) ? mask : 0; break;
                    case 11: value = (sa < sb) ? a : b; break;
                    case 12: value = (sa > sb) ? a : b; break;
                    case 13: value = (a < b) ? a : b; break;
                    case 14: value = (a > b) ? a : b; break;
                    case 15: value = (uint64_t)(sa < 0 ? -sa : sa) & mask; break;
                    case 16: value = (~a) & b; break;
                    case 17: {
                        size_t block_lane = (bit / lane_bits) % (128 / lane_bits);
                        size_t half_idx = block_lane / 2;
                        size_t src_reg = (block_lane % 2 == 0) ? src : src2;
                        size_t src_bit = ((bit / 128) * 128) + (half_idx * lane_bits);
                        value = (ctx.get_vreg_lane(src_reg, src_bit / 64) >> (src_bit % 64)) & mask;
                        break;
                    }
                    case 18: {
                        size_t num_lanes = 128 / lane_bits;
                        size_t block_lane = (bit / lane_bits) % num_lanes;
                        size_t half_idx = (num_lanes / 2) + (block_lane / 2);
                        size_t src_reg = (block_lane % 2 == 0) ? src : src2;
                        size_t src_bit = ((bit / 128) * 128) + (half_idx * lane_bits);
                        value = (ctx.get_vreg_lane(src_reg, src_bit / 64) >> (src_bit % 64)) & mask;
                        break;
                    }
                    case 21: {
                        uint8_t ctrl = (uint8_t)(b & 0xff);
                        if (ctrl & 0x80) value = 0;
                        else {
                            size_t src_bit = ((bit / 128) * 128) + ((ctrl & 0xf) * 8);
                            value = (ctx.get_vreg_lane(src, src_bit / 64) >> (src_bit % 64)) & 0xff;
                        }
                        break;
                    }
                    case 23: {
                        size_t num_lanes = 128 / lane_bits;
                        size_t block_lane = (bit / lane_bits) % num_lanes;
                        size_t half_len = num_lanes / 2;
                        size_t src_reg = (block_lane < half_len) ? src : src2;
                        size_t sel_elem = (block_lane < half_len) ? (block_lane * 2) : ((block_lane - half_len) * 2);
                        size_t src_bit = ((bit / 128) * 128) + (sel_elem * lane_bits);
                        value = (ctx.get_vreg_lane(src_reg, src_bit / 64) >> (src_bit % 64)) & mask;
                        break;
                    }
                    case 24: {
                        size_t num_lanes = 128 / lane_bits;
                        size_t block_lane = (bit / lane_bits) % num_lanes;
                        size_t half_len = num_lanes / 2;
                        size_t src_reg = (block_lane < half_len) ? src : src2;
                        size_t sel_elem = (block_lane < half_len) ? (block_lane * 2 + 1) : ((block_lane - half_len) * 2 + 1);
                        size_t src_bit = ((bit / 128) * 128) + (sel_elem * lane_bits);
                        value = (ctx.get_vreg_lane(src_reg, src_bit / 64) >> (src_bit % 64)) & mask;
                        break;
                    }
                    case 25: {
                        size_t num_lanes = 128 / lane_bits;
                        size_t block_lane = (bit / lane_bits) % num_lanes;
                        size_t k = block_lane / 2;
                        size_t src_reg = (block_lane % 2 == 0) ? src : src2;
                        size_t sel_elem = k * 2;
                        size_t src_bit = ((bit / 128) * 128) + (sel_elem * lane_bits);
                        value = (ctx.get_vreg_lane(src_reg, src_bit / 64) >> (src_bit % 64)) & mask;
                        break;
                    }
                    case 26: {
                        size_t num_lanes = 128 / lane_bits;
                        size_t block_lane = (bit / lane_bits) % num_lanes;
                        size_t k = block_lane / 2;
                        size_t src_reg = (block_lane % 2 == 0) ? src : src2;
                        size_t sel_elem = k * 2 + 1;
                        size_t src_bit = ((bit / 128) * 128) + (sel_elem * lane_bits);
                        value = (ctx.get_vreg_lane(src_reg, src_bit / 64) >> (src_bit % 64)) & mask;
                        break;
                    }
                    case 28: {
                        uint8_t idx = (uint8_t)(b & 0xff);
                        if (idx < 16) {
                            size_t src_bit = ((bit / 128) * 128) + (idx * 8);
                            value = (ctx.get_vreg_lane(src, src_bit / 64) >> (src_bit % 64)) & 0xff;
                        } else {
                            value = 0;
                        }
                        break;
                    }
                    case 29: {
                        uint8_t idx = (uint8_t)(b & 0xff);
                        if (idx < 16) {
                            size_t src_bit = ((bit / 128) * 128) + (idx * 8);
                            value = (ctx.get_vreg_lane(src, src_bit / 64) >> (src_bit % 64)) & 0xff;
                        } else {
                            value = (ctx.get_vreg_lane(dst, chunk) >> shift) & 0xff;
                        }
                        break;
                    }
                    case 30: {
                        int64_t min_val = (lane_bits == 64) ? (int64_t)0x8000000000000000ULL : (lane_bits == 32) ? (int64_t)(int32_t)0x80000000 : (lane_bits == 16) ? (int64_t)(int16_t)0x8000 : (int64_t)(int8_t)0x80;
                        if (sb == 0) value = ~0ULL;
                        else if (sb == -1 && sa == min_val) value = (uint64_t)sa;
                        else value = (uint64_t)(sa / sb);
                        break;
                    }
                    case 31: {
                        value = (b != 0) ? (a / b) : mask;
                        break;
                    }
                    case 32: {
                        int64_t min_val = (lane_bits == 64) ? (int64_t)0x8000000000000000ULL : (lane_bits == 32) ? (int64_t)(int32_t)0x80000000 : (lane_bits == 16) ? (int64_t)(int16_t)0x8000 : (int64_t)(int8_t)0x80;
                        if (sb == 0) value = a;
                        else if (sb == -1 && sa == min_val) value = 0;
                        else value = (uint64_t)(sa % sb);
                        break;
                    }
                    case 33: {
                        value = (b != 0) ? (a % b) : a;
                        break;
                    }
                    case 34: value = (a != b) ? mask : 0; break;
                    case 35: value = (sa <= sb) ? mask : 0; break;
                    case 36: value = (a < b) ? mask : 0; break;
                    case 37: value = (a <= b) ? mask : 0; break;
                    default: value = a ^ b; break;
                }
            }
            uint64_t old_value = ctx.get_vreg_lane(dst, chunk);
            uint64_t packed_mask = mask << shift;
            ctx.set_vreg_lane(dst, chunk, (old_value & ~packed_mask) | ((value & mask) << shift));
        }
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_VEC_IMM_D1: {
        uint64_t imm_val = imm & 0xffULL;
        uint32_t bits = (uint32_t)((imm >> 8) & 0x3ff);
        uint32_t lane_bits = (uint32_t)((imm >> 18) & 0xff);
        if (lane_bits == 0) lane_bits = 64;
        uint32_t vop = (uint32_t)((imm >> 26) & 0x1f);
        uint64_t mask = lane_bits == 8 ? 0xffULL : (lane_bits == 16 ? 0xffffULL : (lane_bits == 32 ? 0xffffffffULL : ~0ULL));
        for (size_t bit = 0; bit < bits; bit += lane_bits) {
            size_t chunk = bit / 64; unsigned shift = (unsigned)(bit % 64);
            uint64_t a = (ctx.get_vreg_lane(src, chunk) >> shift) & mask;
            int64_t sa = lane_bits == 8 ? (int64_t)(int8_t)a : (lane_bits == 16 ? (int64_t)(int16_t)a : (lane_bits == 32 ? (int64_t)(int32_t)a : (int64_t)a));
            uint64_t value = 0;
            switch (vop) {
                case 6: { uint32_t cnt = (uint32_t)imm_val; value = (cnt >= lane_bits) ? 0 : (a << cnt); break; }
                case 7: { uint32_t cnt = (uint32_t)imm_val; value = (cnt >= lane_bits) ? 0 : (a >> cnt); break; }
                case 8: { uint32_t cnt = (uint32_t)imm_val; value = (cnt >= lane_bits) ? (sa < 0 ? mask : 0) : ((uint64_t)(sa >> cnt) & mask); break; }
                case 21: {
                    size_t lane_in_128 = (bit / 32) % 4;
                    size_t sel = (imm_val >> (lane_in_128 * 2)) & 3;
                    size_t src_bit = ((bit / 128) * 128) + (sel * 32);
                    value = (ctx.get_vreg_lane(src, src_bit / 64) >> (src_bit % 64)) & 0xffffffffULL;
                    break;
                }
                case 22: {
                    size_t lane_idx = bit / lane_bits;
                    size_t sel = (imm_val >> (lane_idx % 8)) & 1;
                    value = (sel == 0) ? a : ((ctx.get_vreg_lane(dst, chunk) >> shift) & mask);
                    break;
                }
                default: value = a; break;
            }
            uint64_t old_value = ctx.get_vreg_lane(dst, chunk);
            uint64_t packed_mask = mask << shift;
            ctx.set_vreg_lane(dst, chunk, (old_value & ~packed_mask) | ((value & mask) << shift));
        }
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_VEC_CLEAR_UPPER_D1: {
        ctx.set_vreg_lane(dst, 2, 0ULL);
        ctx.set_vreg_lane(dst, 3, 0ULL);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_VEC_ZERO_UPPER_D1: {
        for (size_t i = 0; i < 16; ++i) {
            ctx.set_vreg_lane(i, 2, 0ULL);
            ctx.set_vreg_lane(i, 3, 0ULL);
        }
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_PMOVMSKB_D1: {
        uint32_t bits = (uint32_t)(imm & 0x3ff);
        uint32_t num_bytes = bits / 8;
        uint64_t mask = 0;
        for (uint32_t b = 0; b < num_bytes; ++b) {
            uint64_t byte_val = (ctx.get_vreg_lane(src, b / 8) >> ((b % 8) * 8)) & 0xff;
            if (byte_val & 0x80) mask |= (1ULL << b);
        }
        ctx.set_reg(dst, mask);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_VEC_LOAD_D1: {
        uint32_t bits = (uint32_t)((word >> 50) & 0x3ff);
        uint64_t address = ctx.get_reg(src) + (uint64_t)imm;
        for (size_t i = 0; i < (bits + 63) / 64; ++i) { uint64_t value = 0; std::memcpy(&value, reinterpret_cast<const void*>(address + i * 8), sizeof(value)); ctx.set_vreg_lane(dst, i, value); }
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_VEC_STORE_D1: {
        uint32_t bits = (uint32_t)((word >> 50) & 0x3ff);
        uint64_t address = ctx.get_reg(dst) + (uint64_t)imm;
        for (size_t i = 0; i < (bits + 63) / 64; ++i) std::memcpy(reinterpret_cast<void*>(address + i * 8), &ctx.vregs[src & 31][i & 7], sizeof(uint64_t));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_VEC_SPLAT_D1: {
        uint32_t bits = (uint32_t)(imm & 0xffff);
        uint32_t lane_bits = (uint32_t)((imm >> 16) & 0xffff);
        uint64_t val = ctx.get_reg(src);
        uint64_t mask = (lane_bits >= 64) ? ~0ULL : ((1ULL << lane_bits) - 1ULL);
        uint64_t val_masked = val & mask;
        uint32_t num_lanes = (lane_bits > 0) ? (bits / lane_bits) : 0;
        for (uint32_t l = 0; l < num_lanes; ++l) {
            uint32_t pos = l * lane_bits;
            uint32_t chunk = pos / 64;
            uint32_t shift = pos % 64;
            uint64_t packed_mask = (lane_bits >= 64) ? ~0ULL : (mask << shift);
            uint64_t cur = ctx.get_vreg_lane(dst, chunk);
            cur = (cur & ~packed_mask) | (val_masked << shift);
            ctx.set_vreg_lane(dst, chunk, cur);
        }
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_VEC_EXT_D1: {
        uint32_t src2 = (uint32_t)(imm & 31);
        uint32_t shift_bytes = (uint32_t)((imm >> 5) & 15);
        uint32_t bits = (uint32_t)((imm >> 9) & 0x3ff);
        if (bits == 0) bits = 128;
        for (size_t byte_idx = 0; byte_idx < (bits / 8); ++byte_idx) {
            size_t total_idx = (byte_idx % 16) + shift_bytes;
            uint64_t val = 0;
            if (total_idx < 16) {
                size_t bit_pos = ((byte_idx / 16) * 128) + (total_idx * 8);
                val = (ctx.get_vreg_lane(src, bit_pos / 64) >> (bit_pos % 64)) & 0xff;
            } else {
                size_t m_idx = total_idx - 16;
                size_t bit_pos = ((byte_idx / 16) * 128) + (m_idx * 8);
                val = (ctx.get_vreg_lane(src2, bit_pos / 64) >> (bit_pos % 64)) & 0xff;
            }
            size_t chunk = (byte_idx * 8) / 64; unsigned shift = (unsigned)((byte_idx * 8) % 64);
            uint64_t old_v = ctx.get_vreg_lane(dst, chunk);
            uint64_t clr = old_v & ~(0xffULL << shift);
            ctx.set_vreg_lane(dst, chunk, clr | (val << shift));
        }
        ctx.executed_instructions++; FETCH_NEXT();
    }

    H_CALL_EXTERN_D1: {
        size_t sym_idx = (size_t)imm;
        void* sym_ptr = asgard_resolve_sym_idx((int32_t)sym_idx);
        if (sym_ptr) {
            uint32_t sym_h = g_external_symbols[sym_idx].hash;
            uint32_t sym_ah = g_external_symbols[sym_idx].alt_hash;
            uint64_t a0 = ctx.get_reg(REG_RAX);
            uint64_t a1 = ctx.get_reg(REG_RCX);
            uint64_t a2 = ctx.get_reg(REG_RDX);
            uint64_t a3 = ctx.get_reg(REG_RBX);
            uint64_t a4 = ctx.get_reg(REG_RSI);
            uint64_t a5 = ctx.get_reg(REG_RDI);
            uint64_t a6 = ctx.get_reg(REG_R8);
            uint64_t a7 = ctx.get_reg(REG_R9);
            const uint64_t* stk = reinterpret_cast<const uint64_t*>(ctx.get_reg(REG_RSP));
            uint64_t ret_val = 0;
            if (sym_h == 0x42FCF5CFU || sym_ah == 0x42FCF5CFU || sym_h == 0x07554ACDU || sym_ah == 0x07554ACDU || sym_h == 0xE76FB4AAU || sym_ah == 0xE76FB4AAU) {
                typedef int (*printf_fn_t)(const char*, ...);
                printf_fn_t pfn = reinterpret_cast<printf_fn_t>(sym_ptr);
#if defined(__APPLE__) && defined(__aarch64__)
                ret_val = (uint64_t)pfn((const char*)a0, stk[0], stk[1], stk[2], stk[3], stk[4], stk[5], stk[6], stk[7]);
#else
                ret_val = (uint64_t)pfn((const char*)a0, a1, a2, a3, a4, a5, a6, a7);
#endif
            } else if (sym_h == 0xFCB512E2U || sym_ah == 0xFCB512E2U || sym_h == 0x4B3C5330U || sym_ah == 0x4B3C5330U || sym_h == 0x937D1EF6U || sym_ah == 0x937D1EF6U || sym_h == 0xCB76D42BU || sym_ah == 0xCB76D42BU || sym_h == 0xD54CE817U || sym_ah == 0xD54CE817U || sym_h == 0xBBED3905U || sym_ah == 0xBBED3905U || sym_h == 0x42C07C7CU || sym_ah == 0x42C07C7CU || sym_h == 0x24559DBDU || sym_ah == 0x24559DBDU) {
                typedef int (*fprintf_fn_t)(void*, const char*, ...);
                fprintf_fn_t fpfn = reinterpret_cast<fprintf_fn_t>(sym_ptr);
#if defined(__APPLE__) && defined(__aarch64__)
                ret_val = (uint64_t)fpfn((void*)a0, (const char*)a1, stk[0], stk[1], stk[2], stk[3], stk[4], stk[5], stk[6], stk[7]);
#else
                ret_val = (uint64_t)fpfn((void*)a0, (const char*)a1, a2, a3, a4, a5, a6, a7);
#endif
            } else if (sym_h == 0x7FE32B00U || sym_ah == 0x7FE32B00U || sym_h == 0xBCBF60EEU || sym_ah == 0xBCBF60EEU || sym_h == 0x70E2D349U || sym_ah == 0x70E2D349U || sym_h == 0x44FA3468U || sym_ah == 0x44FA3468U) {
                typedef int (*sprintf_fn_t)(char*, const char*, ...);
                sprintf_fn_t spfn = reinterpret_cast<sprintf_fn_t>(sym_ptr);
#if defined(__APPLE__) && defined(__aarch64__)
                ret_val = (uint64_t)spfn((char*)a0, (const char*)a1, stk[0], stk[1], stk[2], stk[3], stk[4], stk[5], stk[6], stk[7]);
#else
                ret_val = (uint64_t)spfn((char*)a0, (const char*)a1, a2, a3, a4, a5, a6, a7);
#endif
            } else if (sym_h == 0x54EE11FAU || sym_ah == 0x54EE11FAU || sym_h == 0x933075F4U || sym_ah == 0x933075F4U || sym_h == 0x3FD5EB6FU || sym_ah == 0x3FD5EB6FU || sym_h == 0x5B3553B4U || sym_ah == 0x5B3553B4U) {
                typedef int (*snprintf_fn_t)(char*, size_t, const char*, ...);
                snprintf_fn_t snpfn = reinterpret_cast<snprintf_fn_t>(sym_ptr);
#if defined(__APPLE__) && defined(__aarch64__)
                ret_val = (uint64_t)snpfn((char*)a0, (size_t)a1, (const char*)a2, stk[0], stk[1], stk[2], stk[3], stk[4], stk[5], stk[6], stk[7]);
#else
                ret_val = (uint64_t)snpfn((char*)a0, (size_t)a1, (const char*)a2, a3, a4, a5, a6, a7);
#endif
            } else {
                typedef uint64_t (*extern_fn_t)(uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t);
                extern_fn_t fn = reinterpret_cast<extern_fn_t>(sym_ptr);
                ret_val = fn(a0, a1, a2, a3, a4, a5, a6, a7);
            }
            ctx.set_reg(REG_RAX, ret_val);
        }
        ctx.executed_instructions++; FETCH_NEXT();
    }

    H_LOAD_64_D1: {
        uint64_t addr = ctx.get_reg(src) + (uint64_t)imm;
        ctx.set_reg(dst, *reinterpret_cast<const uint64_t*>(addr));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_LOAD_32_D1: {
        const char* _base = reinterpret_cast<const char*>(ctx.get_reg(src));
        ctx.set_reg(dst, (uint64_t)(*reinterpret_cast<const uint32_t*>(_base + imm)));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_LOAD_16_D1: {
        const char* _base = reinterpret_cast<const char*>(ctx.get_reg(src));
        ctx.set_reg(dst, (uint64_t)(*reinterpret_cast<const uint16_t*>(_base + imm)));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_LOAD_8_D1: {
        uintptr_t _ptr = static_cast<uintptr_t>(ctx.get_reg(src)) + static_cast<uintptr_t>(imm);
        uint8_t _v8 = 0;
        std::memcpy(&_v8, reinterpret_cast<const void*>(_ptr), sizeof(uint8_t));
        ctx.set_reg(dst, (uint64_t)_v8);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_LOAD_S32_D1: {
        uintptr_t _ptr = static_cast<uintptr_t>(ctx.get_reg(src)) + static_cast<uintptr_t>(imm);
        int32_t _s32 = 0;
        std::memcpy(&_s32, reinterpret_cast<const void*>(_ptr), sizeof(int32_t));
        ctx.set_reg(dst, (uint64_t)(int64_t)_s32);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_LOAD_S16_D1: {
        uintptr_t _ptr = static_cast<uintptr_t>(ctx.get_reg(src)) + static_cast<uintptr_t>(imm);
        int16_t _s16 = 0;
        std::memcpy(&_s16, reinterpret_cast<const void*>(_ptr), sizeof(int16_t));
        ctx.set_reg(dst, (uint64_t)(int64_t)_s16);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_LOAD_S8_D1: {
        uintptr_t _ptr = static_cast<uintptr_t>(ctx.get_reg(src)) + static_cast<uintptr_t>(imm);
        int8_t _s8 = 0;
        std::memcpy(&_s8, reinterpret_cast<const void*>(_ptr), sizeof(int8_t));
        ctx.set_reg(dst, (uint64_t)(int64_t)_s8);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_STORE_64_D1: {
        uint64_t addr = ctx.get_reg(dst) + (uint64_t)imm;
        *reinterpret_cast<uint64_t*>(addr) = ctx.get_reg(src);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_STORE_32_D1: {
        uint64_t addr = ctx.get_reg(dst) + (uint64_t)imm;
        *reinterpret_cast<uint32_t*>(addr) = (uint32_t)ctx.get_reg(src);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_STORE_16_D1: {
        uint64_t addr = ctx.get_reg(dst) + (uint64_t)imm;
        *reinterpret_cast<uint16_t*>(addr) = (uint16_t)ctx.get_reg(src);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_STORE_8_D1: {
        uintptr_t _ptr = static_cast<uintptr_t>(ctx.get_reg(dst)) + static_cast<uintptr_t>(imm);
        uint8_t _v8 = (uint8_t)ctx.get_reg(src);
        std::memcpy(reinterpret_cast<void*>(_ptr), &_v8, sizeof(uint8_t));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_RESOLVE_SYM_D1: {
        size_t _idx = static_cast<size_t>(imm);
        void* _p = asgard_resolve_sym_idx((int32_t)_idx);
        ctx.set_reg(dst, static_cast<uint64_t>(reinterpret_cast<uintptr_t>(_p)));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_FADD_DD_D1: {
        double _a = std::bit_cast<double>(ctx.get_vreg_lane(src, 0));
        double _b = std::bit_cast<double>(ctx.get_vreg_lane(static_cast<uint8_t>(imm), 0));
        ctx.set_vreg(dst, std::bit_cast<uint64_t>(_a + _b), 0);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_FSUB_DD_D1: {
        uint64_t _s = ctx.get_vreg_lane(src, 0), _i = ctx.get_vreg_lane((uint8_t)imm, 0);
        ctx.set_vreg(dst, std::bit_cast<uint64_t>(std::bit_cast<double>(_s) - std::bit_cast<double>(_i)), 0);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_FMUL_DD_D1: {
        uint64_t a_raw = ctx.get_vreg_lane(src, 0), b_raw = ctx.get_vreg_lane((uint8_t)imm, 0);
        double a = std::bit_cast<double>(a_raw), b = std::bit_cast<double>(b_raw);
        ctx.set_vreg(dst, std::bit_cast<uint64_t>(a * b), 0);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_FDIV_DD_D1: {
        uint64_t _s = ctx.get_vreg_lane(src, 0), _i = ctx.get_vreg_lane((uint8_t)imm, 0);
        double a = std::bit_cast<double>(_s), b = std::bit_cast<double>(_i);
        ctx.set_vreg(dst, std::bit_cast<uint64_t>((b != 0.0) ? (a / b) : 0.0), 0);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_FSQRT_D_D1: {
        uint64_t _s = ctx.get_vreg_lane(src, 0);
        double a = std::bit_cast<double>(_s);
        ctx.set_vreg(dst, std::bit_cast<uint64_t>((a >= 0.0) ? std::sqrt(a) : 0.0), 0);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_FCMP_DD_D1: {
        double _a = std::bit_cast<double>(ctx.get_vreg_lane(src, 0));
        double _b = std::bit_cast<double>(ctx.get_vreg_lane(static_cast<uint8_t>(imm), 0));
        ctx.of = false;
        ctx.sf = (_a < _b);
        ctx.cf = (_a >= _b);
        ctx.zf = (_a == _b);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_FCVTZS_D1: {
        uint64_t a_raw = ctx.get_vreg_lane(src, 0);
        double a = std::bit_cast<double>(a_raw);
        ctx.set_reg(dst, (uint64_t)((int64_t)a));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_SCVTF_D1: {
        ctx.set_vreg(dst, std::bit_cast<uint64_t>((double)(int64_t)ctx.get_reg(src)), 0);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_FCVTZU_D1: {
        double _a = std::bit_cast<double>(ctx.get_vreg_lane(src, 0));
        uint64_t _u64 = (_a < 0.0) ? 0ULL : static_cast<uint64_t>(_a);
        ctx.set_reg(dst, _u64);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_UCVTF_D1: {
        uint64_t _v = ctx.get_reg(src);
        ctx.set_vreg(dst, std::bit_cast<uint64_t>((double)_v), 0);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_FCVT_D1: {
        float f32 = std::bit_cast<float>((uint32_t)ctx.get_vreg_lane(src, 0));
        ctx.set_vreg(dst, std::bit_cast<uint64_t>((double)f32), 0);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_ATOMIC_LOAD_D1: {
        uint64_t addr = ctx.get_reg(src) + (uint64_t)imm;
        auto* ptr = reinterpret_cast<std::atomic<uint64_t>*>(addr);
        ctx.set_reg(dst, ptr->load(std::memory_order_seq_cst));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_ATOMIC_STORE_D1: {
        uint64_t _addr = ctx.get_reg(dst) + (uint64_t)imm;
        (void)__atomic_exchange_n(reinterpret_cast<uint64_t*>(_addr), ctx.get_reg(src), __ATOMIC_SEQ_CST);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_ATOMIC_CAS_D1: {
        auto* ptr = reinterpret_cast<std::atomic<uint64_t>*>(ctx.get_reg(dst) + (uint64_t)imm);
        uint64_t expected = ctx.get_reg(src);
        while (!ptr->compare_exchange_weak(expected, ctx.get_reg(REG_RAX), std::memory_order_seq_cst, std::memory_order_seq_cst)) {
            if (expected != ctx.get_reg(src)) break;
        }
        ctx.set_reg(src, expected);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_ATOMIC_ADD_D1: {
        uint64_t addr = ctx.get_reg(dst) + (uint64_t)imm;
        auto* ptr = reinterpret_cast<std::atomic<uint64_t>*>(addr);
        uint64_t old = ptr->fetch_add(ctx.get_reg(src), std::memory_order_seq_cst);
        ctx.set_reg(src, old);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_ATOMIC_SWP_D1: {
        uint64_t* ptr = reinterpret_cast<uint64_t*>(ctx.get_reg(dst) + (uint64_t)imm);
        uint64_t old = __atomic_load_n(ptr, __ATOMIC_RELAXED);
        uint64_t new_val = ctx.get_reg(src);
        while (!__atomic_compare_exchange_n(ptr, &old, new_val, false, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST)) {}
        ctx.set_reg(src, old);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_FENCE_D1: { std::atomic_thread_fence(std::memory_order_seq_cst); ctx.executed_instructions++; FETCH_NEXT(); }
    H_MOV_VR_D1: {
        uint64_t _val = (ctx.get_reg(src) ^ 0xa5a5a5a55a5a5a5aULL);
        ctx.set_vreg_lane(dst, 0, (_val ^ 0xa5a5a5a55a5a5a5aULL));
        ctx.executed_instructions++;
        FETCH_NEXT();
    }
    H_MOV_RV_D1: {
        uint64_t _val = ctx.get_vreg_lane(src, 0);
        uint64_t _buf[1];
        std::memcpy(_buf, (&_val), sizeof(uint64_t));
        ctx.set_reg(dst, _buf[0]);
        ctx.executed_instructions++;
        FETCH_NEXT();
    }
    H_FCSEL_VV_D1: {
        uint8_t cond = (uint8_t)((((word >> 18) + 0x0FULL) - ((word >> 18) | 0x0FULL)));
        if (eval_condition(ctx, cond)) ctx.set_vreg_lane(dst, 0, ctx.get_vreg_lane(src, 0));
        ctx.executed_instructions++; FETCH_NEXT();
    }


    H_NOP_D2: { (void)dst; ctx.executed_instructions++; FETCH_NEXT(); }
    H_MOV_RR_D2: { uint64_t _v = ctx.get_reg(src); ctx.set_reg(dst, _v); ctx.executed_instructions++; FETCH_NEXT(); }
    H_MOV_RI_D2: { uint64_t _imm_u64 = static_cast<uint64_t>(static_cast<uint32_t>(imm)); ctx.set_reg(dst, _imm_u64); ctx.executed_instructions++; FETCH_NEXT(); }
    H_MOV_HIGH_D2: {
        uint32_t _low32 = static_cast<uint32_t>(ctx.get_reg(dst));
        ctx.set_reg(dst, (static_cast<uint64_t>(static_cast<uint32_t>(imm)) << 32) | static_cast<uint64_t>(_low32));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_NEG_RR_D2: { PROBE_START(); ctx.set_reg(dst, 0ULL - ctx.get_reg(dst)); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_NOT_RR_D2: { PROBE_START(); ctx.set_reg(dst, 0xFFFFFFFFFFFFFFFFULL - ctx.get_reg(dst)); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_BSWAP_RR_D2: {
        uint64_t _val = ctx.get_reg(src);
        uint32_t _b = static_cast<uint32_t>(imm);
        uint64_t _r = (_b == 16) ? static_cast<uint64_t>(__builtin_bswap16(static_cast<uint16_t>(_val)))
                     : ((_b == 32) ? static_cast<uint64_t>(__builtin_bswap32(static_cast<uint32_t>(_val)))
                                   : __builtin_bswap64(_val));
        ctx.set_reg(dst, _r);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_CLZ_RR_D2: {
        uint64_t val = ctx.get_reg(src);
        uint32_t bits = (uint32_t)imm;
        uint64_t mask = (bits >= 64) ? ~0ULL : ((1ULL << bits) - 1ULL);
        uint64_t mval = val & mask;
        uint64_t res;
        if (bits <= 32) {
            uint32_t v32 = (uint32_t)mval;
            res = (v32 == 0) ? (uint64_t)bits : (uint64_t)(__builtin_clz(v32) - (32 - bits));
        } else {
            res = (mval == 0) ? 64ULL : (uint64_t)__builtin_clzll(mval);
        }
        ctx.set_reg(dst, res);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_CTZ_RR_D2: {
        uint64_t val = ctx.get_reg(src);
        uint32_t bits = (uint32_t)imm;
        uint64_t mask = (bits >= 64) ? ~0ULL : ((1ULL << bits) - 1ULL);
        uint64_t mval = val & mask;
        uint64_t res;
        if (bits <= 32) {
            uint32_t v32 = (uint32_t)mval;
            res = (v32 == 0) ? (uint64_t)bits : (uint64_t)__builtin_ctz(v32);
        } else {
            res = (mval == 0) ? 64ULL : (uint64_t)__builtin_ctzll(mval);
        }
        ctx.set_reg(dst, res);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_POPCNT_RR_D2: {
        uint64_t val = ctx.get_reg(src);
        uint32_t bits = (uint32_t)imm;
        uint64_t mask = (bits >= 64) ? ~0ULL : ((1ULL << bits) - 1ULL);
        uint64_t mval = val & mask;
        uint64_t res = (bits <= 32) ? (uint64_t)__builtin_popcount((uint32_t)mval) : (uint64_t)__builtin_popcountll(mval);
        ctx.set_reg(dst, res);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_RBIT_RR_D2: {
        uint64_t val = ctx.get_reg(src);
        uint32_t bits = (uint32_t)imm;
        uint64_t res = 0;
        for (uint32_t i = 0; i < bits; ++i) {
            if ((val >> i) & 1ULL) { res |= (1ULL << (bits - 1 - i)); }
        }
        ctx.set_reg(dst, res);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_ADD_RR_D2: { PROBE_START(); ctx.set_reg(dst, (((((0x0000000000000002ULL * (((ctx.get_reg(dst) & 0x5555555555555555ULL) | (ctx.get_reg(src) & 0x5555555555555555ULL)) + ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) | (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL)))) - ((ctx.get_reg(dst) ^ ctx.get_reg(src)) + ((((ctx.get_reg(dst) + ctx.get_reg(src)) & (~((ctx.get_reg(dst) + ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) + ctx.get_reg(src)))) & (ctx.get_reg(dst) + ctx.get_reg(src)))) + (((ctx.get_reg(dst) + ctx.get_reg(src)) ^ (ctx.get_reg(dst) + ctx.get_reg(src))) - (((ctx.get_reg(dst) + ctx.get_reg(src)) | (ctx.get_reg(dst) + ctx.get_reg(src))) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & (ctx.get_reg(dst) + ctx.get_reg(src)))))))) ^ ((((ctx.get_reg(dst) + ctx.get_reg(src)) & (~((ctx.get_reg(dst) + ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) + ctx.get_reg(src)))) & (ctx.get_reg(dst) + ctx.get_reg(src)))) + (((ctx.get_reg(dst) + ctx.get_reg(src)) ^ (ctx.get_reg(dst) + ctx.get_reg(src))) - (((ctx.get_reg(dst) + ctx.get_reg(src)) | (ctx.get_reg(dst) + ctx.get_reg(src))) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & (ctx.get_reg(dst) + ctx.get_reg(src))))))) + (0x0000000000000002ULL * (((0x0000000000000002ULL * ((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) & (~((ctx.get_reg(dst) ^ ctx.get_reg(src)))))) - ((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) ^ (ctx.get_reg(dst) ^ ctx.get_reg(src)))) & ((((ctx.get_reg(dst) + ctx.get_reg(src)) & (~((ctx.get_reg(dst) + ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) + ctx.get_reg(src)))) & (ctx.get_reg(dst) + ctx.get_reg(src)))) + (((ctx.get_reg(dst) + ctx.get_reg(src)) ^ (ctx.get_reg(dst) + ctx.get_reg(src))) - (((ctx.get_reg(dst) + ctx.get_reg(src)) | (ctx.get_reg(dst) + ctx.get_reg(src))) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & (ctx.get_reg(dst) + ctx.get_reg(src))))))))) + (((((0x0000000000000002ULL * ((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) & (~((ctx.get_reg(dst) ^ ctx.get_reg(src)))))) - ((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) ^ (ctx.get_reg(dst) ^ ctx.get_reg(src)))) ^ ((((ctx.get_reg(dst) + ctx.get_reg(src)) & (~((ctx.get_reg(dst) + ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) + ctx.get_reg(src)))) & (ctx.get_reg(dst) + ctx.get_reg(src)))) + (((ctx.get_reg(dst) + ctx.get_reg(src)) ^ (ctx.get_reg(dst) + ctx.get_reg(src))) - (((ctx.get_reg(dst) + ctx.get_reg(src)) | (ctx.get_reg(dst) + ctx.get_reg(src))) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & (ctx.get_reg(dst) + ctx.get_reg(src))))))) + (0x0000000000000002ULL * (((0x0000000000000002ULL * ((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) & (~((ctx.get_reg(dst) ^ ctx.get_reg(src)))))) - ((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) ^ (ctx.get_reg(dst) ^ ctx.get_reg(src)))) & ((((ctx.get_reg(dst) + ctx.get_reg(src)) & (~((ctx.get_reg(dst) + ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) + ctx.get_reg(src)))) & (ctx.get_reg(dst) + ctx.get_reg(src)))) + (((ctx.get_reg(dst) + ctx.get_reg(src)) ^ (ctx.get_reg(dst) + ctx.get_reg(src))) - (((ctx.get_reg(dst) + ctx.get_reg(src)) | (ctx.get_reg(dst) + ctx.get_reg(src))) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & (ctx.get_reg(dst) + ctx.get_reg(src))))))))) - (ctx.get_reg(dst) + ctx.get_reg(src))))); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_ADD_RI_D2: { PROBE_START(); uint64_t _d = ctx.get_reg(dst); ctx.set_reg(dst, (_d + static_cast<uint64_t>(imm))); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_SUB_RR_D2: { PROBE_START(); ctx.set_reg(dst, (((((((ctx.get_reg(dst) & (~ctx.get_reg(src))) - (((~ctx.get_reg(dst)) - ((~ctx.get_reg(dst)) & (~ctx.get_reg(src)))) + (((~ctx.get_reg(dst)) ^ ctx.get_reg(src)) - (((~ctx.get_reg(dst)) | ctx.get_reg(src)) - ((~ctx.get_reg(dst)) & ctx.get_reg(src)))))) ^ ((((ctx.get_reg(dst) & 0x5555555555555555ULL) ^ (ctx.get_reg(src) & 0x5555555555555555ULL)) + ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) ^ (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))) - ((((ctx.get_reg(dst) | ctx.get_reg(src)) & 0x5555555555555555ULL) - ((ctx.get_reg(dst) & ctx.get_reg(src)) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) | ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) & ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL))))) + (0x0000000000000002ULL * (((ctx.get_reg(dst) & (~ctx.get_reg(src))) - (((~ctx.get_reg(dst)) - ((~ctx.get_reg(dst)) & (~ctx.get_reg(src)))) + (((~ctx.get_reg(dst)) ^ ctx.get_reg(src)) - (((~ctx.get_reg(dst)) | ctx.get_reg(src)) - ((~ctx.get_reg(dst)) & ctx.get_reg(src)))))) & ((((ctx.get_reg(dst) & 0x5555555555555555ULL) ^ (ctx.get_reg(src) & 0x5555555555555555ULL)) + ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) ^ (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))) - ((((ctx.get_reg(dst) | ctx.get_reg(src)) & 0x5555555555555555ULL) - ((ctx.get_reg(dst) & ctx.get_reg(src)) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) | ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) & ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL))))))) + (((((ctx.get_reg(dst) & (~ctx.get_reg(src))) - (((~ctx.get_reg(dst)) - ((~ctx.get_reg(dst)) & (~ctx.get_reg(src)))) + (((~ctx.get_reg(dst)) ^ ctx.get_reg(src)) - (((~ctx.get_reg(dst)) | ctx.get_reg(src)) - ((~ctx.get_reg(dst)) & ctx.get_reg(src)))))) ^ ((((ctx.get_reg(dst) & 0x5555555555555555ULL) ^ (ctx.get_reg(src) & 0x5555555555555555ULL)) + ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) ^ (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))) - ((((ctx.get_reg(dst) | ctx.get_reg(src)) & 0x5555555555555555ULL) - ((ctx.get_reg(dst) & ctx.get_reg(src)) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) | ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) & ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL))))) + (0x0000000000000002ULL * (((ctx.get_reg(dst) & (~ctx.get_reg(src))) - ((~ctx.get_reg(dst)) & ctx.get_reg(src))) & ((ctx.get_reg(dst) ^ ctx.get_reg(src)) - ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))))))) - (ctx.get_reg(dst) - ctx.get_reg(src)))) ^ ((((((((ctx.get_reg(dst) & (~ctx.get_reg(src))) - (((~ctx.get_reg(dst)) - ((~ctx.get_reg(dst)) & (~ctx.get_reg(src)))) + (((~ctx.get_reg(dst)) ^ ctx.get_reg(src)) - (((~ctx.get_reg(dst)) | ctx.get_reg(src)) - ((~ctx.get_reg(dst)) & ctx.get_reg(src)))))) ^ ((((ctx.get_reg(dst) & 0x5555555555555555ULL) ^ (ctx.get_reg(src) & 0x5555555555555555ULL)) + ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) ^ (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))) - ((((ctx.get_reg(dst) | ctx.get_reg(src)) & 0x5555555555555555ULL) - ((ctx.get_reg(dst) & ctx.get_reg(src)) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) | ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) & ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL))))) + (0x0000000000000002ULL * (((ctx.get_reg(dst) & (~ctx.get_reg(src))) - (((~ctx.get_reg(dst)) - ((~ctx.get_reg(dst)) & (~ctx.get_reg(src)))) + (((~ctx.get_reg(dst)) ^ ctx.get_reg(src)) - (((~ctx.get_reg(dst)) | ctx.get_reg(src)) - ((~ctx.get_reg(dst)) & ctx.get_reg(src)))))) & ((((ctx.get_reg(dst) & 0x5555555555555555ULL) ^ (ctx.get_reg(src) & 0x5555555555555555ULL)) + ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) ^ (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))) - ((((ctx.get_reg(dst) | ctx.get_reg(src)) & 0x5555555555555555ULL) - ((ctx.get_reg(dst) & ctx.get_reg(src)) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) | ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) & ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL))))))) + (((((ctx.get_reg(dst) & (~ctx.get_reg(src))) - (((~ctx.get_reg(dst)) - ((~ctx.get_reg(dst)) & (~ctx.get_reg(src)))) + (((~ctx.get_reg(dst)) ^ ctx.get_reg(src)) - (((~ctx.get_reg(dst)) | ctx.get_reg(src)) - ((~ctx.get_reg(dst)) & ctx.get_reg(src)))))) ^ ((((ctx.get_reg(dst) & 0x5555555555555555ULL) ^ (ctx.get_reg(src) & 0x5555555555555555ULL)) + ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) ^ (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))) - ((((ctx.get_reg(dst) | ctx.get_reg(src)) & 0x5555555555555555ULL) - ((ctx.get_reg(dst) & ctx.get_reg(src)) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) | ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) & ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL))))) + (0x0000000000000002ULL * (((ctx.get_reg(dst) & (~ctx.get_reg(src))) - ((~ctx.get_reg(dst)) & ctx.get_reg(src))) & ((ctx.get_reg(dst) ^ ctx.get_reg(src)) - ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))))))) - (ctx.get_reg(dst) - ctx.get_reg(src)))) & 0x000000007fffffffULL) * 0x033e2dd89416710bULL) << 0x0000000000000021ULL)) ^ (((((((((ctx.get_reg(dst) & (~ctx.get_reg(src))) - (((~ctx.get_reg(dst)) - ((~ctx.get_reg(dst)) & (~ctx.get_reg(src)))) + (((~ctx.get_reg(dst)) ^ ctx.get_reg(src)) - (((~ctx.get_reg(dst)) | ctx.get_reg(src)) - ((~ctx.get_reg(dst)) & ctx.get_reg(src)))))) ^ ((((ctx.get_reg(dst) & 0x5555555555555555ULL) ^ (ctx.get_reg(src) & 0x5555555555555555ULL)) + ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) ^ (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))) - ((((ctx.get_reg(dst) | ctx.get_reg(src)) & 0x5555555555555555ULL) - ((ctx.get_reg(dst) & ctx.get_reg(src)) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) | ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) & ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL))))) + (0x0000000000000002ULL * (((ctx.get_reg(dst) & (~ctx.get_reg(src))) - (((~ctx.get_reg(dst)) - ((~ctx.get_reg(dst)) & (~ctx.get_reg(src)))) + (((~ctx.get_reg(dst)) ^ ctx.get_reg(src)) - (((~ctx.get_reg(dst)) | ctx.get_reg(src)) - ((~ctx.get_reg(dst)) & ctx.get_reg(src)))))) & ((((ctx.get_reg(dst) & 0x5555555555555555ULL) ^ (ctx.get_reg(src) & 0x5555555555555555ULL)) + ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) ^ (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))) - ((((ctx.get_reg(dst) | ctx.get_reg(src)) & 0x5555555555555555ULL) - ((ctx.get_reg(dst) & ctx.get_reg(src)) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) | ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) & ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL))))))) + (((((ctx.get_reg(dst) & (~ctx.get_reg(src))) - (((~ctx.get_reg(dst)) - ((~ctx.get_reg(dst)) & (~ctx.get_reg(src)))) + (((~ctx.get_reg(dst)) ^ ctx.get_reg(src)) - (((~ctx.get_reg(dst)) | ctx.get_reg(src)) - ((~ctx.get_reg(dst)) & ctx.get_reg(src)))))) ^ ((((ctx.get_reg(dst) & 0x5555555555555555ULL) ^ (ctx.get_reg(src) & 0x5555555555555555ULL)) + ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) ^ (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))) - ((((ctx.get_reg(dst) | ctx.get_reg(src)) & 0x5555555555555555ULL) - ((ctx.get_reg(dst) & ctx.get_reg(src)) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) | ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) & ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL))))) + (0x0000000000000002ULL * (((ctx.get_reg(dst) & (~ctx.get_reg(src))) - ((~ctx.get_reg(dst)) & ctx.get_reg(src))) & ((ctx.get_reg(dst) ^ ctx.get_reg(src)) - ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))))))) - (ctx.get_reg(dst) - ctx.get_reg(src)))) ^ ((((((((ctx.get_reg(dst) & (~ctx.get_reg(src))) - (((~ctx.get_reg(dst)) - ((~ctx.get_reg(dst)) & (~ctx.get_reg(src)))) + (((~ctx.get_reg(dst)) ^ ctx.get_reg(src)) - (((~ctx.get_reg(dst)) | ctx.get_reg(src)) - ((~ctx.get_reg(dst)) & ctx.get_reg(src)))))) ^ ((((ctx.get_reg(dst) & 0x5555555555555555ULL) ^ (ctx.get_reg(src) & 0x5555555555555555ULL)) + ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) ^ (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))) - ((((ctx.get_reg(dst) | ctx.get_reg(src)) & 0x5555555555555555ULL) - ((ctx.get_reg(dst) & ctx.get_reg(src)) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) | ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) & ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL))))) + (0x0000000000000002ULL * (((ctx.get_reg(dst) & (~ctx.get_reg(src))) - (((~ctx.get_reg(dst)) - ((~ctx.get_reg(dst)) & (~ctx.get_reg(src)))) + (((~ctx.get_reg(dst)) ^ ctx.get_reg(src)) - (((~ctx.get_reg(dst)) | ctx.get_reg(src)) - ((~ctx.get_reg(dst)) & ctx.get_reg(src)))))) & ((((ctx.get_reg(dst) & 0x5555555555555555ULL) ^ (ctx.get_reg(src) & 0x5555555555555555ULL)) + ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) ^ (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))) - ((((ctx.get_reg(dst) | ctx.get_reg(src)) & 0x5555555555555555ULL) - ((ctx.get_reg(dst) & ctx.get_reg(src)) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) | ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) & ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL))))))) + (((((ctx.get_reg(dst) & (~ctx.get_reg(src))) - (((~ctx.get_reg(dst)) - ((~ctx.get_reg(dst)) & (~ctx.get_reg(src)))) + (((~ctx.get_reg(dst)) ^ ctx.get_reg(src)) - (((~ctx.get_reg(dst)) | ctx.get_reg(src)) - ((~ctx.get_reg(dst)) & ctx.get_reg(src)))))) ^ ((((ctx.get_reg(dst) & 0x5555555555555555ULL) ^ (ctx.get_reg(src) & 0x5555555555555555ULL)) + ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) ^ (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))) - ((((ctx.get_reg(dst) | ctx.get_reg(src)) & 0x5555555555555555ULL) - ((ctx.get_reg(dst) & ctx.get_reg(src)) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) | ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) & ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL))))) + (0x0000000000000002ULL * (((ctx.get_reg(dst) & (~ctx.get_reg(src))) - ((~ctx.get_reg(dst)) & ctx.get_reg(src))) & ((ctx.get_reg(dst) ^ ctx.get_reg(src)) - ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))))))) - (ctx.get_reg(dst) - ctx.get_reg(src)))) & 0x000000007fffffffULL) * 0x033e2dd89416710bULL) << 0x0000000000000021ULL)) & 0x000000007fffffffULL) * 0x033e2dd89416710bULL) << 0x0000000000000021ULL))); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_SUB_RI_D2: { PROBE_START(); uint64_t _d = ctx.get_reg(dst); uint64_t _i = static_cast<uint64_t>(imm); ctx.set_reg(dst, (_d + ((~_i) + 0x0000000000000001ULL))); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_IMUL_RR_D2: {
        PROBE_START();
        uint64_t a = ctx.get_reg(dst); uint64_t b = ctx.get_reg(src);
        ctx.set_reg(dst, ((a & b) * (a | b)) + ((a & (~b)) * ((~a) & b)));
        PROBE_CHECK();
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_IMUL_RI_D2: {
        PROBE_START();
        ctx.set_reg(dst, static_cast<uint64_t>(static_cast<int64_t>(ctx.get_reg(dst)) * imm));
        PROBE_CHECK();
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_XOR_RR_D2: { PROBE_START(); ctx.set_reg(dst, (((((((((ctx.get_reg(dst) + 0x5555555555555555ULL) - (ctx.get_reg(dst) | 0x5555555555555555ULL)) | (ctx.get_reg(src) & 0x5555555555555555ULL)) - (((ctx.get_reg(dst) + 0x5555555555555555ULL) - (ctx.get_reg(dst) | 0x5555555555555555ULL)) & (ctx.get_reg(src) & 0x5555555555555555ULL))) ^ ((((ctx.get_reg(dst) + 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(dst) | 0xaaaaaaaaaaaaaaaaULL)) | ((ctx.get_reg(src) - (ctx.get_reg(src) & (~0xaaaaaaaaaaaaaaaaULL))) + ((ctx.get_reg(src) ^ 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(src) | 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))))) - (((ctx.get_reg(dst) + 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(dst) | 0xaaaaaaaaaaaaaaaaULL)) & ((ctx.get_reg(src) - (ctx.get_reg(src) & (~0xaaaaaaaaaaaaaaaaULL))) + ((ctx.get_reg(src) ^ 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(src) | 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))))))) + (0x0000000000000002ULL * ((((ctx.get_reg(dst) & 0x5555555555555555ULL) | (ctx.get_reg(src) & 0x5555555555555555ULL)) - ((ctx.get_reg(dst) & 0x5555555555555555ULL) & (ctx.get_reg(src) & 0x5555555555555555ULL))) & (((ctx.get_reg(dst) + 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(dst) | 0xaaaaaaaaaaaaaaaaULL)) ^ ((ctx.get_reg(src) - (ctx.get_reg(src) & (~0xaaaaaaaaaaaaaaaaULL))) + ((ctx.get_reg(src) ^ 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(src) | 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL)))))))) + ((((((ctx.get_reg(dst) & 0x5555555555555555ULL) | (ctx.get_reg(src) & 0x5555555555555555ULL)) - ((ctx.get_reg(dst) & 0x5555555555555555ULL) & (ctx.get_reg(src) & 0x5555555555555555ULL))) ^ (((ctx.get_reg(dst) + 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(dst) | 0xaaaaaaaaaaaaaaaaULL)) ^ ((ctx.get_reg(src) - (ctx.get_reg(src) & (~0xaaaaaaaaaaaaaaaaULL))) + ((ctx.get_reg(src) ^ 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(src) | 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL)))))) + (0x0000000000000002ULL * ((((ctx.get_reg(dst) & 0x5555555555555555ULL) | (ctx.get_reg(src) & 0x5555555555555555ULL)) - ((ctx.get_reg(dst) & 0x5555555555555555ULL) & (ctx.get_reg(src) & 0x5555555555555555ULL))) & (((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) + (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL)) - (0x0000000000000002ULL * ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))))))) - (ctx.get_reg(dst) ^ ctx.get_reg(src)))) ^ ((((((((((ctx.get_reg(dst) + 0x5555555555555555ULL) - (ctx.get_reg(dst) | 0x5555555555555555ULL)) | (ctx.get_reg(src) & 0x5555555555555555ULL)) - (((ctx.get_reg(dst) + 0x5555555555555555ULL) - (ctx.get_reg(dst) | 0x5555555555555555ULL)) & (ctx.get_reg(src) & 0x5555555555555555ULL))) ^ ((((ctx.get_reg(dst) + 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(dst) | 0xaaaaaaaaaaaaaaaaULL)) | ((ctx.get_reg(src) - (ctx.get_reg(src) & (~0xaaaaaaaaaaaaaaaaULL))) + ((ctx.get_reg(src) ^ 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(src) | 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))))) - (((ctx.get_reg(dst) + 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(dst) | 0xaaaaaaaaaaaaaaaaULL)) & ((ctx.get_reg(src) - (ctx.get_reg(src) & (~0xaaaaaaaaaaaaaaaaULL))) + ((ctx.get_reg(src) ^ 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(src) | 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))))))) + (0x0000000000000002ULL * ((((ctx.get_reg(dst) & 0x5555555555555555ULL) | (ctx.get_reg(src) & 0x5555555555555555ULL)) - ((ctx.get_reg(dst) & 0x5555555555555555ULL) & (ctx.get_reg(src) & 0x5555555555555555ULL))) & (((ctx.get_reg(dst) + 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(dst) | 0xaaaaaaaaaaaaaaaaULL)) ^ ((ctx.get_reg(src) - (ctx.get_reg(src) & (~0xaaaaaaaaaaaaaaaaULL))) + ((ctx.get_reg(src) ^ 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(src) | 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL)))))))) + ((((((ctx.get_reg(dst) & 0x5555555555555555ULL) | (ctx.get_reg(src) & 0x5555555555555555ULL)) - ((ctx.get_reg(dst) & 0x5555555555555555ULL) & (ctx.get_reg(src) & 0x5555555555555555ULL))) ^ (((ctx.get_reg(dst) + 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(dst) | 0xaaaaaaaaaaaaaaaaULL)) ^ ((ctx.get_reg(src) - (ctx.get_reg(src) & (~0xaaaaaaaaaaaaaaaaULL))) + ((ctx.get_reg(src) ^ 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(src) | 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL)))))) + (0x0000000000000002ULL * ((((ctx.get_reg(dst) & 0x5555555555555555ULL) | (ctx.get_reg(src) & 0x5555555555555555ULL)) - ((ctx.get_reg(dst) & 0x5555555555555555ULL) & (ctx.get_reg(src) & 0x5555555555555555ULL))) & (((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) + (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL)) - (0x0000000000000002ULL * ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))))))) - (ctx.get_reg(dst) ^ ctx.get_reg(src)))) & 0x000000007fffffffULL) * 0x08c373af497d6b05ULL) << 0x0000000000000021ULL)) ^ (((((((((((ctx.get_reg(dst) + 0x5555555555555555ULL) - (ctx.get_reg(dst) | 0x5555555555555555ULL)) | (ctx.get_reg(src) & 0x5555555555555555ULL)) - (((ctx.get_reg(dst) + 0x5555555555555555ULL) - (ctx.get_reg(dst) | 0x5555555555555555ULL)) & (ctx.get_reg(src) & 0x5555555555555555ULL))) ^ ((((ctx.get_reg(dst) + 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(dst) | 0xaaaaaaaaaaaaaaaaULL)) | ((ctx.get_reg(src) - (ctx.get_reg(src) & (~0xaaaaaaaaaaaaaaaaULL))) + ((ctx.get_reg(src) ^ 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(src) | 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))))) - (((ctx.get_reg(dst) + 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(dst) | 0xaaaaaaaaaaaaaaaaULL)) & ((ctx.get_reg(src) - (ctx.get_reg(src) & (~0xaaaaaaaaaaaaaaaaULL))) + ((ctx.get_reg(src) ^ 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(src) | 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))))))) + (0x0000000000000002ULL * ((((ctx.get_reg(dst) & 0x5555555555555555ULL) | (ctx.get_reg(src) & 0x5555555555555555ULL)) - ((ctx.get_reg(dst) & 0x5555555555555555ULL) & (ctx.get_reg(src) & 0x5555555555555555ULL))) & (((ctx.get_reg(dst) + 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(dst) | 0xaaaaaaaaaaaaaaaaULL)) ^ ((ctx.get_reg(src) - (ctx.get_reg(src) & (~0xaaaaaaaaaaaaaaaaULL))) + ((ctx.get_reg(src) ^ 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(src) | 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL)))))))) + ((((((ctx.get_reg(dst) & 0x5555555555555555ULL) | (ctx.get_reg(src) & 0x5555555555555555ULL)) - ((ctx.get_reg(dst) & 0x5555555555555555ULL) & (ctx.get_reg(src) & 0x5555555555555555ULL))) ^ (((ctx.get_reg(dst) + 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(dst) | 0xaaaaaaaaaaaaaaaaULL)) ^ ((ctx.get_reg(src) - (ctx.get_reg(src) & (~0xaaaaaaaaaaaaaaaaULL))) + ((ctx.get_reg(src) ^ 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(src) | 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL)))))) + (0x0000000000000002ULL * ((((ctx.get_reg(dst) & 0x5555555555555555ULL) | (ctx.get_reg(src) & 0x5555555555555555ULL)) - ((ctx.get_reg(dst) & 0x5555555555555555ULL) & (ctx.get_reg(src) & 0x5555555555555555ULL))) & (((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) + (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL)) - (0x0000000000000002ULL * ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))))))) - (ctx.get_reg(dst) ^ ctx.get_reg(src)))) ^ ((((((((((ctx.get_reg(dst) + 0x5555555555555555ULL) - (ctx.get_reg(dst) | 0x5555555555555555ULL)) | (ctx.get_reg(src) & 0x5555555555555555ULL)) - (((ctx.get_reg(dst) + 0x5555555555555555ULL) - (ctx.get_reg(dst) | 0x5555555555555555ULL)) & (ctx.get_reg(src) & 0x5555555555555555ULL))) ^ ((((ctx.get_reg(dst) + 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(dst) | 0xaaaaaaaaaaaaaaaaULL)) | ((ctx.get_reg(src) - (ctx.get_reg(src) & (~0xaaaaaaaaaaaaaaaaULL))) + ((ctx.get_reg(src) ^ 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(src) | 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))))) - (((ctx.get_reg(dst) + 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(dst) | 0xaaaaaaaaaaaaaaaaULL)) & ((ctx.get_reg(src) - (ctx.get_reg(src) & (~0xaaaaaaaaaaaaaaaaULL))) + ((ctx.get_reg(src) ^ 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(src) | 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))))))) + (0x0000000000000002ULL * ((((ctx.get_reg(dst) & 0x5555555555555555ULL) | (ctx.get_reg(src) & 0x5555555555555555ULL)) - ((ctx.get_reg(dst) & 0x5555555555555555ULL) & (ctx.get_reg(src) & 0x5555555555555555ULL))) & (((ctx.get_reg(dst) + 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(dst) | 0xaaaaaaaaaaaaaaaaULL)) ^ ((ctx.get_reg(src) - (ctx.get_reg(src) & (~0xaaaaaaaaaaaaaaaaULL))) + ((ctx.get_reg(src) ^ 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(src) | 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL)))))))) + ((((((ctx.get_reg(dst) & 0x5555555555555555ULL) | (ctx.get_reg(src) & 0x5555555555555555ULL)) - ((ctx.get_reg(dst) & 0x5555555555555555ULL) & (ctx.get_reg(src) & 0x5555555555555555ULL))) ^ (((ctx.get_reg(dst) + 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(dst) | 0xaaaaaaaaaaaaaaaaULL)) ^ ((ctx.get_reg(src) - (ctx.get_reg(src) & (~0xaaaaaaaaaaaaaaaaULL))) + ((ctx.get_reg(src) ^ 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(src) | 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL)))))) + (0x0000000000000002ULL * ((((ctx.get_reg(dst) & 0x5555555555555555ULL) | (ctx.get_reg(src) & 0x5555555555555555ULL)) - ((ctx.get_reg(dst) & 0x5555555555555555ULL) & (ctx.get_reg(src) & 0x5555555555555555ULL))) & (((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) + (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL)) - (0x0000000000000002ULL * ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))))))) - (ctx.get_reg(dst) ^ ctx.get_reg(src)))) & 0x000000007fffffffULL) * 0x08c373af497d6b05ULL) << 0x0000000000000021ULL)) & 0x000000007fffffffULL) * 0x08c373af497d6b05ULL) << 0x0000000000000021ULL))); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_XOR_RI_D2: { PROBE_START(); ctx.set_reg(dst, (((((0x8bbb8896230c638dULL * (ctx.get_reg(dst) ^ static_cast<uint64_t>(imm))) + (0x8bbb8896230c638cULL * (ctx.get_reg(dst) & static_cast<uint64_t>(imm)))) + (0x74447769dcf39c74ULL * (ctx.get_reg(dst) | static_cast<uint64_t>(imm)))) + 0x634101e554ca7b12ULL) - 0x634101e554ca7b12ULL)); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_AND_RR_D2: { PROBE_START(); ctx.set_reg(dst, ((((((((ctx.get_reg(dst) & (~((ctx.get_reg(dst) & (~ctx.get_reg(src)))))) - ((~ctx.get_reg(dst)) & (ctx.get_reg(dst) & (~ctx.get_reg(src))))) + ((ctx.get_reg(dst) ^ (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - ((ctx.get_reg(dst) | (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - (ctx.get_reg(dst) & (ctx.get_reg(dst) & (~ctx.get_reg(src))))))) ^ (((ctx.get_reg(dst) ^ ctx.get_reg(src)) + ((~(((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))))) + 0x0000000000000001ULL)) + (((ctx.get_reg(dst) ^ ctx.get_reg(src)) - ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))) - ((ctx.get_reg(dst) ^ ctx.get_reg(src)) + ((~(((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))))) + 0x0000000000000001ULL))))) + (0x0000000000000002ULL * ((((ctx.get_reg(dst) & (~((ctx.get_reg(dst) & (~ctx.get_reg(src)))))) - ((~ctx.get_reg(dst)) & (ctx.get_reg(dst) & (~ctx.get_reg(src))))) + ((ctx.get_reg(dst) ^ (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - ((ctx.get_reg(dst) | (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - (ctx.get_reg(dst) & (ctx.get_reg(dst) & (~ctx.get_reg(src))))))) & (((ctx.get_reg(dst) ^ ctx.get_reg(src)) + ((~(((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))))) + 0x0000000000000001ULL)) + (((ctx.get_reg(dst) ^ ctx.get_reg(src)) - ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))) - ((ctx.get_reg(dst) ^ ctx.get_reg(src)) + ((~(((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))))) + 0x0000000000000001ULL))))))) + ((((((ctx.get_reg(dst) & (~((ctx.get_reg(dst) & (~ctx.get_reg(src)))))) - ((~ctx.get_reg(dst)) & (ctx.get_reg(dst) & (~ctx.get_reg(src))))) + ((ctx.get_reg(dst) ^ (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - ((ctx.get_reg(dst) | (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - (ctx.get_reg(dst) & (ctx.get_reg(dst) & (~ctx.get_reg(src))))))) ^ (((ctx.get_reg(dst) ^ ctx.get_reg(src)) + ((~(((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))))) + 0x0000000000000001ULL)) + (((ctx.get_reg(dst) ^ ctx.get_reg(src)) - ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))) - ((ctx.get_reg(dst) ^ ctx.get_reg(src)) + ((~(((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))))) + 0x0000000000000001ULL))))) + (0x0000000000000002ULL * ((((ctx.get_reg(dst) & (~((ctx.get_reg(dst) & (~ctx.get_reg(src)))))) - ((~ctx.get_reg(dst)) & (ctx.get_reg(dst) & (~ctx.get_reg(src))))) + ((ctx.get_reg(dst) ^ (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - ((ctx.get_reg(dst) | (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - (ctx.get_reg(dst) & (ctx.get_reg(dst) & (~ctx.get_reg(src))))))) & (((ctx.get_reg(dst) ^ ctx.get_reg(src)) + ((~(((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))))) + 0x0000000000000001ULL)) + (((ctx.get_reg(dst) ^ ctx.get_reg(src)) - ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))) - ((ctx.get_reg(dst) ^ ctx.get_reg(src)) + ((~(((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))))) + 0x0000000000000001ULL))))))) - (ctx.get_reg(dst) & ctx.get_reg(src)))) ^ (((((((((ctx.get_reg(dst) & (~((ctx.get_reg(dst) & (~ctx.get_reg(src)))))) - ((~ctx.get_reg(dst)) & (ctx.get_reg(dst) & (~ctx.get_reg(src))))) + ((ctx.get_reg(dst) ^ (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - ((ctx.get_reg(dst) | (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - (ctx.get_reg(dst) & (ctx.get_reg(dst) & (~ctx.get_reg(src))))))) ^ (((ctx.get_reg(dst) ^ ctx.get_reg(src)) + ((~(((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))))) + 0x0000000000000001ULL)) + (((ctx.get_reg(dst) ^ ctx.get_reg(src)) - ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))) - ((ctx.get_reg(dst) ^ ctx.get_reg(src)) + ((~(((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))))) + 0x0000000000000001ULL))))) + (0x0000000000000002ULL * ((((ctx.get_reg(dst) & (~((ctx.get_reg(dst) & (~ctx.get_reg(src)))))) - ((~ctx.get_reg(dst)) & (ctx.get_reg(dst) & (~ctx.get_reg(src))))) + ((ctx.get_reg(dst) ^ (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - ((ctx.get_reg(dst) | (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - (ctx.get_reg(dst) & (ctx.get_reg(dst) & (~ctx.get_reg(src))))))) & (((ctx.get_reg(dst) ^ ctx.get_reg(src)) + ((~(((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))))) + 0x0000000000000001ULL)) + (((ctx.get_reg(dst) ^ ctx.get_reg(src)) - ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))) - ((ctx.get_reg(dst) ^ ctx.get_reg(src)) + ((~(((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))))) + 0x0000000000000001ULL))))))) + ((((((ctx.get_reg(dst) & (~((ctx.get_reg(dst) & (~ctx.get_reg(src)))))) - ((~ctx.get_reg(dst)) & (ctx.get_reg(dst) & (~ctx.get_reg(src))))) + ((ctx.get_reg(dst) ^ (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - ((ctx.get_reg(dst) | (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - (ctx.get_reg(dst) & (ctx.get_reg(dst) & (~ctx.get_reg(src))))))) ^ (((ctx.get_reg(dst) ^ ctx.get_reg(src)) + ((~(((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))))) + 0x0000000000000001ULL)) + (((ctx.get_reg(dst) ^ ctx.get_reg(src)) - ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))) - ((ctx.get_reg(dst) ^ ctx.get_reg(src)) + ((~(((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))))) + 0x0000000000000001ULL))))) + (0x0000000000000002ULL * ((((ctx.get_reg(dst) & (~((ctx.get_reg(dst) & (~ctx.get_reg(src)))))) - ((~ctx.get_reg(dst)) & (ctx.get_reg(dst) & (~ctx.get_reg(src))))) + ((ctx.get_reg(dst) ^ (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - ((ctx.get_reg(dst) | (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - (ctx.get_reg(dst) & (ctx.get_reg(dst) & (~ctx.get_reg(src))))))) & (((ctx.get_reg(dst) ^ ctx.get_reg(src)) + ((~(((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))))) + 0x0000000000000001ULL)) + (((ctx.get_reg(dst) ^ ctx.get_reg(src)) - ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))) - ((ctx.get_reg(dst) ^ ctx.get_reg(src)) + ((~(((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))))) + 0x0000000000000001ULL))))))) - (ctx.get_reg(dst) & ctx.get_reg(src)))) & 0x000000007fffffffULL) * 0x30d717922b646cabULL) << 0x0000000000000021ULL)) ^ ((((((((((ctx.get_reg(dst) & (~((ctx.get_reg(dst) & (~ctx.get_reg(src)))))) - ((~ctx.get_reg(dst)) & (ctx.get_reg(dst) & (~ctx.get_reg(src))))) + ((ctx.get_reg(dst) ^ (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - ((ctx.get_reg(dst) | (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - (ctx.get_reg(dst) & (ctx.get_reg(dst) & (~ctx.get_reg(src))))))) ^ (((ctx.get_reg(dst) ^ ctx.get_reg(src)) + ((~(((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))))) + 0x0000000000000001ULL)) + (((ctx.get_reg(dst) ^ ctx.get_reg(src)) - ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))) - ((ctx.get_reg(dst) ^ ctx.get_reg(src)) + ((~(((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))))) + 0x0000000000000001ULL))))) + (0x0000000000000002ULL * ((((ctx.get_reg(dst) & (~((ctx.get_reg(dst) & (~ctx.get_reg(src)))))) - ((~ctx.get_reg(dst)) & (ctx.get_reg(dst) & (~ctx.get_reg(src))))) + ((ctx.get_reg(dst) ^ (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - ((ctx.get_reg(dst) | (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - (ctx.get_reg(dst) & (ctx.get_reg(dst) & (~ctx.get_reg(src))))))) & (((ctx.get_reg(dst) ^ ctx.get_reg(src)) + ((~(((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))))) + 0x0000000000000001ULL)) + (((ctx.get_reg(dst) ^ ctx.get_reg(src)) - ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))) - ((ctx.get_reg(dst) ^ ctx.get_reg(src)) + ((~(((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))))) + 0x0000000000000001ULL))))))) + ((((((ctx.get_reg(dst) & (~((ctx.get_reg(dst) & (~ctx.get_reg(src)))))) - ((~ctx.get_reg(dst)) & (ctx.get_reg(dst) & (~ctx.get_reg(src))))) + ((ctx.get_reg(dst) ^ (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - ((ctx.get_reg(dst) | (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - (ctx.get_reg(dst) & (ctx.get_reg(dst) & (~ctx.get_reg(src))))))) ^ (((ctx.get_reg(dst) ^ ctx.get_reg(src)) + ((~(((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))))) + 0x0000000000000001ULL)) + (((ctx.get_reg(dst) ^ ctx.get_reg(src)) - ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))) - ((ctx.get_reg(dst) ^ ctx.get_reg(src)) + ((~(((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))))) + 0x0000000000000001ULL))))) + (0x0000000000000002ULL * ((((ctx.get_reg(dst) & (~((ctx.get_reg(dst) & (~ctx.get_reg(src)))))) - ((~ctx.get_reg(dst)) & (ctx.get_reg(dst) & (~ctx.get_reg(src))))) + ((ctx.get_reg(dst) ^ (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - ((ctx.get_reg(dst) | (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - (ctx.get_reg(dst) & (ctx.get_reg(dst) & (~ctx.get_reg(src))))))) & (((ctx.get_reg(dst) ^ ctx.get_reg(src)) + ((~(((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))))) + 0x0000000000000001ULL)) + (((ctx.get_reg(dst) ^ ctx.get_reg(src)) - ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))) - ((ctx.get_reg(dst) ^ ctx.get_reg(src)) + ((~(((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))))) + 0x0000000000000001ULL))))))) - (ctx.get_reg(dst) & ctx.get_reg(src)))) ^ (((((((((ctx.get_reg(dst) & (~((ctx.get_reg(dst) & (~ctx.get_reg(src)))))) - ((~ctx.get_reg(dst)) & (ctx.get_reg(dst) & (~ctx.get_reg(src))))) + ((ctx.get_reg(dst) ^ (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - ((ctx.get_reg(dst) | (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - (ctx.get_reg(dst) & (ctx.get_reg(dst) & (~ctx.get_reg(src))))))) ^ (((ctx.get_reg(dst) ^ ctx.get_reg(src)) + ((~(((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))))) + 0x0000000000000001ULL)) + (((ctx.get_reg(dst) ^ ctx.get_reg(src)) - ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))) - ((ctx.get_reg(dst) ^ ctx.get_reg(src)) + ((~(((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))))) + 0x0000000000000001ULL))))) + (0x0000000000000002ULL * ((((ctx.get_reg(dst) & (~((ctx.get_reg(dst) & (~ctx.get_reg(src)))))) - ((~ctx.get_reg(dst)) & (ctx.get_reg(dst) & (~ctx.get_reg(src))))) + ((ctx.get_reg(dst) ^ (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - ((ctx.get_reg(dst) | (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - (ctx.get_reg(dst) & (ctx.get_reg(dst) & (~ctx.get_reg(src))))))) & (((ctx.get_reg(dst) ^ ctx.get_reg(src)) + ((~(((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))))) + 0x0000000000000001ULL)) + (((ctx.get_reg(dst) ^ ctx.get_reg(src)) - ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))) - ((ctx.get_reg(dst) ^ ctx.get_reg(src)) + ((~(((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))))) + 0x0000000000000001ULL))))))) + ((((((ctx.get_reg(dst) & (~((ctx.get_reg(dst) & (~ctx.get_reg(src)))))) - ((~ctx.get_reg(dst)) & (ctx.get_reg(dst) & (~ctx.get_reg(src))))) + ((ctx.get_reg(dst) ^ (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - ((ctx.get_reg(dst) | (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - (ctx.get_reg(dst) & (ctx.get_reg(dst) & (~ctx.get_reg(src))))))) ^ (((ctx.get_reg(dst) ^ ctx.get_reg(src)) + ((~(((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))))) + 0x0000000000000001ULL)) + (((ctx.get_reg(dst) ^ ctx.get_reg(src)) - ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))) - ((ctx.get_reg(dst) ^ ctx.get_reg(src)) + ((~(((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))))) + 0x0000000000000001ULL))))) + (0x0000000000000002ULL * ((((ctx.get_reg(dst) & (~((ctx.get_reg(dst) & (~ctx.get_reg(src)))))) - ((~ctx.get_reg(dst)) & (ctx.get_reg(dst) & (~ctx.get_reg(src))))) + ((ctx.get_reg(dst) ^ (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - ((ctx.get_reg(dst) | (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - (ctx.get_reg(dst) & (ctx.get_reg(dst) & (~ctx.get_reg(src))))))) & (((ctx.get_reg(dst) ^ ctx.get_reg(src)) + ((~(((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))))) + 0x0000000000000001ULL)) + (((ctx.get_reg(dst) ^ ctx.get_reg(src)) - ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))) - ((ctx.get_reg(dst) ^ ctx.get_reg(src)) + ((~(((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))))) + 0x0000000000000001ULL))))))) - (ctx.get_reg(dst) & ctx.get_reg(src)))) & 0x000000007fffffffULL) * 0x30d717922b646cabULL) << 0x0000000000000021ULL)) & 0x000000007fffffffULL) * 0x30d717922b646cabULL) << 0x0000000000000021ULL))); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_AND_RI_D2: { PROBE_START(); ctx.set_reg(dst, (ctx.get_reg(dst) & static_cast<uint64_t>(imm))); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_OR_RR_D2: { PROBE_START(); ctx.set_reg(dst, ((((ctx.get_reg(dst) | ctx.get_reg(src)) ^ (((((ctx.get_reg(dst) & ctx.get_reg(src)) + (ctx.get_reg(dst) & (~ctx.get_reg(src)))) & 0x5555555555555555ULL) - (((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0x5555555555555555ULL) + ((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0xaaaaaaaaaaaaaaaaULL))) + ((((ctx.get_reg(dst) & ctx.get_reg(src)) + (ctx.get_reg(dst) & (~ctx.get_reg(src)))) & 0xaaaaaaaaaaaaaaaaULL) - (~(((~ctx.get_reg(dst)) | (~0xaaaaaaaaaaaaaaaaULL))))))) + (0x0000000000000002ULL * ((ctx.get_reg(dst) | ctx.get_reg(src)) & (((((ctx.get_reg(dst) & ctx.get_reg(src)) + (ctx.get_reg(dst) & (~ctx.get_reg(src)))) & 0x5555555555555555ULL) - (ctx.get_reg(dst) & 0x5555555555555555ULL)) + ((((ctx.get_reg(dst) & ctx.get_reg(src)) + (ctx.get_reg(dst) & (~ctx.get_reg(src)))) & 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL)))))) + ((((ctx.get_reg(dst) | ctx.get_reg(src)) ^ (((((ctx.get_reg(dst) & ctx.get_reg(src)) + (ctx.get_reg(dst) & (~ctx.get_reg(src)))) & 0x5555555555555555ULL) - (ctx.get_reg(dst) & 0x5555555555555555ULL)) + ((((ctx.get_reg(dst) & ctx.get_reg(src)) + (ctx.get_reg(dst) & (~ctx.get_reg(src)))) & 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL)))) + (0x0000000000000002ULL * ((ctx.get_reg(dst) | ctx.get_reg(src)) & (((((ctx.get_reg(dst) & ctx.get_reg(src)) + (ctx.get_reg(dst) & (~ctx.get_reg(src)))) & 0x5555555555555555ULL) - (ctx.get_reg(dst) & 0x5555555555555555ULL)) + ((((ctx.get_reg(dst) & ctx.get_reg(src)) + (ctx.get_reg(dst) & (~ctx.get_reg(src)))) & 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL)))))) - (ctx.get_reg(dst) | ctx.get_reg(src))))); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_OR_RI_D2: { PROBE_START(); uint64_t _d = ctx.get_reg(dst); uint64_t _i = static_cast<uint64_t>(imm); ctx.set_reg(dst, ((_d + _i) - (_d & _i))); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_ROL_RI_D2: {
        uint64_t v = ctx.get_reg(dst); uint32_t s = (uint32_t)(imm & 63);
        ctx.set_reg(dst, (v << s) | (v >> ((64 - s) & 63)));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_ROR_RI_D2: {
        uint64_t val = ctx.get_reg(dst); uint32_t shift = (uint32_t)(imm & 63);
        uint64_t _res = (val >> shift) | (val << ((64 - shift) & 63));
        ctx.set_reg(dst, _res);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_SHL_RI_D2: {
        uint64_t v = ctx.get_reg(dst); uint32_t s = static_cast<uint32_t>(imm & 63);
        ctx.set_reg(dst, v << s);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_SHR_RI_D2: {
        uint64_t val = ctx.get_reg(dst); uint32_t shift = (uint32_t)(imm & 63);
        ctx.set_reg(dst, val >> shift);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_SAR_RI_D2: {
        uint64_t val = ctx.get_reg(dst); uint32_t shift = (uint32_t)(imm & 63);
        ctx.set_reg(dst, (uint64_t)((int64_t)val >> shift));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_ROL_RR_D2: {
        uint64_t val = ctx.get_reg(dst); uint32_t shift = (uint32_t)(ctx.get_reg(src) & 63);
        ctx.set_reg(dst, (val << shift) | (val >> ((64 - shift) & 63)));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_ROR_RR_D2: {
        uint64_t v = ctx.get_reg(dst); uint32_t s = (uint32_t)(ctx.get_reg(src) & 63);
        ctx.set_reg(dst, (v >> s) | (v << ((64 - s) & 63)));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_SHL_RR_D2: {
        uint64_t _res = ctx.get_reg(dst) << (uint32_t)(ctx.get_reg(src) & 63);
        ctx.set_reg(dst, _res);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_SHR_RR_D2: {
        uint64_t v = ctx.get_reg(dst); uint32_t s = static_cast<uint32_t>(ctx.get_reg(src) & 63);
        ctx.set_reg(dst, v >> s);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_SAR_RR_D2: {
        uint64_t val = ctx.get_reg(dst); uint32_t shift = (uint32_t)(ctx.get_reg(src) & 63);
        ctx.set_reg(dst, (uint64_t)((int64_t)val >> shift));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_DIV_RR_D2: {
        uint64_t _divisor = ctx.get_reg(src);
        if (_divisor == 0ULL) { ctx.trapped = true; goto EXIT_VM; }
        uint64_t _dividend = ctx.get_reg(dst);
        ctx.set_reg(dst, _dividend / _divisor);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_IDIV_RR_D2: {
        int64_t a = (int64_t)ctx.get_reg(dst); int64_t b = (int64_t)ctx.get_reg(src);
        if (b == 0 || (b == -1 && a == INT64_MIN)) { ctx.trapped = true; goto EXIT_VM; }
        int64_t q = (b == -1) ? (int64_t)(0 - (uint64_t)a) : (a / b);
        ctx.set_reg(dst, (uint64_t)q);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_MULH_RR_D2: {
        uint64_t a = ctx.get_reg(dst); uint64_t b = ctx.get_reg(src);
        #if defined(__SIZEOF_INT128__)
        uint64_t res = (uint64_t)(((unsigned __int128)a * (unsigned __int128)b) >> 64);
        #else
        uint64_t a_lo = (uint32_t)a, a_hi = a >> 32;
        uint64_t b_lo = (uint32_t)b, b_hi = b >> 32;
        uint64_t p0 = a_lo * b_lo;
        uint64_t p1 = a_lo * b_hi;
        uint64_t p2 = a_hi * b_lo;
        uint64_t p3 = a_hi * b_hi;
        uint64_t cy = ((p0 >> 32) + (uint32_t)p1 + (uint32_t)p2) >> 32;
        uint64_t res = p3 + (p1 >> 32) + (p2 >> 32) + cy;
        #endif
        ctx.set_reg(dst, res);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_IMULH_RR_D2: {
        int64_t a = (int64_t)ctx.get_reg(dst); int64_t b = (int64_t)ctx.get_reg(src);
        #if defined(__SIZEOF_INT128__)
        signed __int128 _prod = (signed __int128)a * (signed __int128)b;
        uint64_t res = static_cast<uint64_t>(_prod >> 64);
        #else
        uint64_t ua = (uint64_t)a, ub = (uint64_t)b;
        uint64_t a_lo = (uint32_t)ua, a_hi = ua >> 32;
        uint64_t b_lo = (uint32_t)ub, b_hi = ub >> 32;
        uint64_t p0 = a_lo * b_lo, p1 = a_lo * b_hi, p2 = a_hi * b_lo, p3 = a_hi * b_hi;
        uint64_t cy = ((p0 >> 32) + (uint32_t)p1 + (uint32_t)p2) >> 32;
        uint64_t res = p3 + (p1 >> 32) + (p2 >> 32) + cy;
        if (a < 0) res -= ub;
        if (b < 0) res -= ua;
        #endif
        ctx.set_reg(dst, res);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_CMP_RI_D2: {
        PROBE_START();
        uint64_t _d = ctx.get_reg(dst);
        compute_sub_flags(ctx, _d, static_cast<uint64_t>(imm), static_cast<uint32_t>((word >> 50) & 0x7F));
        PROBE_CHECK();
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_CMP_RR_D2: {
        PROBE_START();
        uint32_t bits = static_cast<uint32_t>((word >> 50) & 0x7F);
        compute_sub_flags(ctx, ctx.get_reg(dst), ctx.get_reg(src), bits);
        PROBE_CHECK();
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_PUSH_R_D2: {
        uint64_t val = ctx.get_reg(dst);
        ctx.push(val);
        uint64_t cur_sp = ctx.get_reg(REG_RSP);
        if (cur_sp >= 0x10008ULL && cur_sp <= 0x7FFFFFFFFFFFULL) {
            uint64_t* sp_ptr = reinterpret_cast<uint64_t*>(cur_sp - 8ULL);
            ctx.set_reg(REG_RSP, reinterpret_cast<uint64_t>(sp_ptr));
            *sp_ptr = val;
        }
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_POP_R_D2: {
        uint64_t cur_sp = ctx.get_reg(REG_RSP);
        uint64_t val = 0;
        if (cur_sp >= 0x10000ULL && cur_sp <= 0x7FFFFFFFFFFFULL) {
            std::memcpy(&val, reinterpret_cast<const void*>(cur_sp), sizeof(uint64_t));
            ctx.set_reg(REG_RSP, cur_sp + 8ULL);
            ctx.pop();
        } else {
            val = ctx.pop();
        }
        ctx.set_reg(dst, val);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_ADC_RR_D2: {
        uint64_t a = ctx.get_reg(dst); uint64_t b = ctx.get_reg(src);
        uint64_t c = static_cast<uint64_t>(ctx.cf);
        uint64_t res = (a + b) + c;
        ctx.cf = (res < a) || (c && res == a);
        ctx.zf = (res == 0);
        ctx.sf = (res >> 63) != 0;
        ctx.of = (((a ^ res) & (b ^ res)) >> 63) != 0;
        ctx.set_reg(dst, res);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_ADC_RI_D2: {
        uint64_t a = ctx.get_reg(dst); uint64_t b = (uint64_t)imm;
        uint64_t c = static_cast<uint64_t>(ctx.cf);
        uint64_t res = (a + b) + c;
        ctx.cf = (res < a) || (c && res == a);
        ctx.zf = (res == 0);
        ctx.sf = (res >> 63) != 0;
        ctx.of = (((a ^ res) & (b ^ res)) >> 63) != 0;
        ctx.set_reg(dst, res);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_SBB_RR_D2: {
        uint64_t a = ctx.get_reg(dst); uint64_t b = ctx.get_reg(src);
        uint64_t borrow = static_cast<uint64_t>(ctx.cf);
        uint64_t res = (a - b) - borrow;
        ctx.cf = (a < b) || (borrow && a == b);
        ctx.zf = (res == 0);
        ctx.sf = (res >> 63) != 0;
        ctx.of = (((a ^ b) & (a ^ res)) >> 63) != 0;
        ctx.set_reg(dst, res);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_SBB_RI_D2: {
        uint64_t a = ctx.get_reg(dst); uint64_t b = (uint64_t)imm;
        uint64_t borrow = ctx.cf ? 1ULL : 0ULL;
        uint64_t res = a - (b + borrow);
        ctx.cf = (a < b) || (borrow && a == b);
        ctx.of = ((((a ^ b) & (a ^ res)) >> 63) != 0);
        ctx.zf = (res == 0);
        ctx.sf = ((int64_t)res < 0);
        ctx.set_reg(dst, res);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_CCMP_RR_D2: {
        uint8_t cond = (uint8_t)((((word >> 18) + 0x0FULL) - ((word >> 18) | 0x0FULL)));
        uint8_t nzcv = (uint8_t)((((word >> 22) + 0x0FULL) - ((word >> 22) | 0x0FULL)));
        uint32_t bits = (uint32_t)((((word >> 50) + 0x7FULL) - ((word >> 50) | 0x7FULL)));
        if (eval_condition(ctx, cond)) {
            uint64_t a = ctx.get_reg(dst); uint64_t b = ctx.get_reg(src);
            compute_sub_flags(ctx, a, b, bits);
        } else {
            ctx.sf = (nzcv & 8) != 0;
            ctx.zf = (nzcv & 4) != 0;
            ctx.cf = (nzcv & 2) != 0;
            ctx.of = (nzcv & 1) != 0;
        }
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_CCMP_RI_D2: {
        uint8_t cond = (uint8_t)((((word >> 18) + 0x0FULL) - ((word >> 18) | 0x0FULL)));
        uint8_t nzcv = (uint8_t)((((word >> 22) + 0x0FULL) - ((word >> 22) | 0x0FULL)));
        uint64_t b = (uint64_t)((((word >> 26) + 0x1FULL) - ((word >> 26) | 0x1FULL)));
        uint32_t bits = (uint32_t)((((word >> 50) + 0x7FULL) - ((word >> 50) | 0x7FULL)));
        if (eval_condition(ctx, cond)) {
            uint64_t a = ctx.get_reg(dst);
            compute_sub_flags(ctx, a, b, bits);
        } else {
            ctx.sf = (nzcv & 8) != 0;
            ctx.zf = (nzcv & 4) != 0;
            ctx.cf = (nzcv & 2) != 0;
            ctx.of = (nzcv & 1) != 0;
        }
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_CCMN_RR_D2: {
        uint8_t cond = (uint8_t)((((word >> 18) + 0x0FULL) - ((word >> 18) | 0x0FULL)));
        uint8_t nzcv = (uint8_t)((((word >> 22) + 0x0FULL) - ((word >> 22) | 0x0FULL)));
        uint32_t bits = (uint32_t)((((word >> 50) + 0x7FULL) - ((word >> 50) | 0x7FULL)));
        if (!eval_condition(ctx, cond)) {
            ctx.sf = (nzcv & 8) != 0;
            ctx.zf = (nzcv & 4) != 0;
            ctx.cf = (nzcv & 2) != 0;
            ctx.of = (nzcv & 1) != 0;
        } else {
            uint64_t a = ctx.get_reg(dst); uint64_t b = ctx.get_reg(src);
            compute_add_flags(ctx, a, b, bits);
        }
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_CCMN_RI_D2: {
        uint8_t cond = (uint8_t)((((word >> 18) + 0x0FULL) - ((word >> 18) | 0x0FULL)));
        uint8_t nzcv = (uint8_t)((((word >> 22) + 0x0FULL) - ((word >> 22) | 0x0FULL)));
        uint64_t b = (uint64_t)((((word >> 26) + 0x1FULL) - ((word >> 26) | 0x1FULL)));
        uint32_t bits = (uint32_t)((((word >> 50) + 0x7FULL) - ((word >> 50) | 0x7FULL)));
        if (eval_condition(ctx, cond)) {
            uint64_t a = ctx.get_reg(dst);
            compute_add_flags(ctx, a, b, bits);
        } else {
            ctx.sf = (nzcv & 8) != 0;
            ctx.zf = (nzcv & 4) != 0;
            ctx.cf = (nzcv & 2) != 0;
            ctx.of = (nzcv & 1) != 0;
        }
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_GET_FLAGS_R_D2: {
        uint64_t f = 2ULL;
        f |= (uint64_t)ctx.cf;
        f |= ((uint64_t)ctx.zf << 6);
        f |= ((uint64_t)ctx.sf << 7);
        f |= ((uint64_t)ctx.of << 11);
        ctx.set_reg(dst, f);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_SET_FLAGS_R_D2: {
        uint64_t f = ctx.get_reg(src);
        ctx.cf = static_cast<bool>(f & 1ULL);
        ctx.zf = static_cast<bool>(f & 0x40ULL);
        ctx.sf = static_cast<bool>(f & 0x80ULL);
        ctx.of = static_cast<bool>(f & 0x800ULL);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_JMP_D2: {
        #if defined(__APPLE__)
        vIP_idx = static_cast<size_t>(imm);
        #elif defined(_WIN32)
        asgard_nanomites::g_nanomite_dispatcher.current_trap_id = static_cast<uint32_t>(vIP_idx);
        asgard_nanomites::g_nanomite_dispatcher.current_condition = 1;
        asgard_nanomites::g_nanomite_dispatcher.register_nanomite(static_cast<uint32_t>(vIP_idx), static_cast<uint64_t>(imm), static_cast<uint64_t>(imm), static_cast<uint64_t>((seed ^ static_cast<uint32_t>(vIP_idx))));
        __debugbreak();
        vIP_idx = ((asgard_nanomites::g_nanomite_dispatcher.resolved_target != 0) ? static_cast<size_t>(asgard_nanomites::g_nanomite_dispatcher.resolved_target) : static_cast<size_t>(imm));
        #elif defined(__linux__) && !defined(_MSC_VER)
        asgard_nanomites::g_nanomite_dispatcher.current_trap_id = static_cast<uint32_t>(vIP_idx);
        asgard_nanomites::g_nanomite_dispatcher.current_condition = 1;
        asgard_nanomites::g_nanomite_dispatcher.register_nanomite(static_cast<uint32_t>(vIP_idx), static_cast<uint64_t>(imm), static_cast<uint64_t>(imm), static_cast<uint64_t>((seed ^ static_cast<uint32_t>(vIP_idx))));
        raise(SIGTRAP);
        vIP_idx = ((asgard_nanomites::g_nanomite_dispatcher.resolved_target != 0) ? static_cast<size_t>(asgard_nanomites::g_nanomite_dispatcher.resolved_target) : static_cast<size_t>(imm));
        #else
        vIP_idx = static_cast<size_t>(imm);
        #endif
        ctx.reanchor_running_key(static_cast<uint64_t>(vIP_idx));
        ctx.executed_instructions++;
        FETCH_NEXT();
    }
    H_JCC_D2: {
        PROBE_START();
        uint8_t cond = static_cast<uint8_t>((((word >> 0x0000000000000012ULL) + 0x000000000000000fULL) - ((word >> 0x0000000000000012ULL) | 0x000000000000000fULL)));
        uint64_t base_vip = static_cast<uint64_t>(((word >> 0x0000000000000016ULL) & 0x00000000001fffffULL));
        uint64_t enc_delta = static_cast<uint64_t>(((word >> 0x000000000000002bULL) & 0x00000000001fffffULL));
        uint64_t salt = (((static_cast<uint64_t>(cond) * 0x0000000000005877ULL) ^ 0x000000001337beefULL) & 0x00000000001fffffULL);
        uint64_t delta = (enc_delta ^ salt);
        uint64_t t_true = (base_vip ^ delta);
        uint64_t t_false = base_vip;
        uint64_t c = (eval_condition(ctx, cond) ? 0x0000000000000001ULL : 0x0000000000000000ULL);
        #if defined(__APPLE__)
        vIP_idx = static_cast<size_t>(((c * t_true) + ((0x0000000000000001ULL - c) * t_false)));
        #elif defined(_WIN32)
        asgard_nanomites::g_nanomite_dispatcher.current_trap_id = static_cast<uint32_t>(vIP_idx);
        asgard_nanomites::g_nanomite_dispatcher.current_condition = static_cast<uint32_t>(c);
        asgard_nanomites::g_nanomite_dispatcher.register_nanomite(static_cast<uint32_t>(vIP_idx), t_true, t_false, static_cast<uint64_t>((seed ^ static_cast<uint32_t>(vIP_idx))));
        __debugbreak();
        vIP_idx = ((asgard_nanomites::g_nanomite_dispatcher.resolved_target != 0) ? static_cast<size_t>(asgard_nanomites::g_nanomite_dispatcher.resolved_target) : static_cast<size_t>(((c * t_true) + ((0x0000000000000001ULL - c) * t_false))));
        #elif defined(__linux__) && !defined(_MSC_VER)
        asgard_nanomites::g_nanomite_dispatcher.current_trap_id = static_cast<uint32_t>(vIP_idx);
        asgard_nanomites::g_nanomite_dispatcher.current_condition = static_cast<uint32_t>(c);
        asgard_nanomites::g_nanomite_dispatcher.register_nanomite(static_cast<uint32_t>(vIP_idx), t_true, t_false, static_cast<uint64_t>((seed ^ static_cast<uint32_t>(vIP_idx))));
        raise(SIGTRAP);
        vIP_idx = ((asgard_nanomites::g_nanomite_dispatcher.resolved_target != 0) ? static_cast<size_t>(asgard_nanomites::g_nanomite_dispatcher.resolved_target) : static_cast<size_t>(((c * t_true) + ((0x0000000000000001ULL - c) * t_false))));
        #else
        vIP_idx = static_cast<size_t>(((c * t_true) + ((0x0000000000000001ULL - c) * t_false)));
        #endif
        ctx.reanchor_running_key(static_cast<uint64_t>(vIP_idx));
        PROBE_CHECK();
        ctx.executed_instructions++;
        FETCH_NEXT();
    }
    H_CMOV_D2: {
        PROBE_START();
        uint8_t cond = static_cast<uint8_t>((((word >> 0x0000000000000012ULL) + 0x000000000000000fULL) - ((word >> 0x0000000000000012ULL) | 0x000000000000000fULL)));
        uint64_t _m = (eval_condition(ctx, cond) ? (~0x0000000000000000ULL) : 0x0000000000000000ULL);
        ctx.set_reg(dst, ((ctx.get_reg(src) & _m) | (ctx.get_reg(dst) & (~_m))));
        PROBE_CHECK();
        ctx.executed_instructions++;
        FETCH_NEXT();
    }
    H_SETCC_D2: {
        PROBE_START();
        uint8_t cond = static_cast<uint8_t>((((word >> 0x0000000000000012ULL) + 0x000000000000000fULL) - ((word >> 0x0000000000000012ULL) | 0x000000000000000fULL)));
        uint64_t _val = 0x0000000000000000ULL;
        if (eval_condition(ctx, cond)) {
                                    _val = 0x0000000000000001ULL;
}
        ctx.set_reg(dst, _val);
        PROBE_CHECK();
        ctx.executed_instructions++;
        FETCH_NEXT();
    }
    H_CALL_D2: {
        ctx.push(static_cast<uint64_t>(vIP_idx));
        #if defined(__APPLE__)
        vIP_idx = static_cast<size_t>(imm);
        #elif defined(_WIN32)
        asgard_nanomites::g_nanomite_dispatcher.current_trap_id = static_cast<uint32_t>(vIP_idx);
        asgard_nanomites::g_nanomite_dispatcher.current_condition = 1;
        asgard_nanomites::g_nanomite_dispatcher.register_nanomite(static_cast<uint32_t>(vIP_idx), static_cast<uint64_t>(imm), static_cast<uint64_t>(imm), static_cast<uint64_t>((seed ^ static_cast<uint32_t>(vIP_idx))));
        __debugbreak();
        vIP_idx = ((asgard_nanomites::g_nanomite_dispatcher.resolved_target != 0) ? static_cast<size_t>(asgard_nanomites::g_nanomite_dispatcher.resolved_target) : static_cast<size_t>(imm));
        #elif defined(__linux__) && !defined(_MSC_VER)
        asgard_nanomites::g_nanomite_dispatcher.current_trap_id = static_cast<uint32_t>(vIP_idx);
        asgard_nanomites::g_nanomite_dispatcher.current_condition = 1;
        asgard_nanomites::g_nanomite_dispatcher.register_nanomite(static_cast<uint32_t>(vIP_idx), static_cast<uint64_t>(imm), static_cast<uint64_t>(imm), static_cast<uint64_t>((seed ^ static_cast<uint32_t>(vIP_idx))));
        raise(SIGTRAP);
        vIP_idx = ((asgard_nanomites::g_nanomite_dispatcher.resolved_target != 0) ? static_cast<size_t>(asgard_nanomites::g_nanomite_dispatcher.resolved_target) : static_cast<size_t>(imm));
        #else
        vIP_idx = static_cast<size_t>(imm);
        #endif
        ctx.reanchor_running_key(static_cast<uint64_t>(vIP_idx));
        ctx.executed_instructions++;
        FETCH_NEXT();
    }
    H_IJMP_R_D2: {
        uint64_t target = ctx.get_reg(dst);
        if (__builtin_expect((target < count), 1)) {
                                                vIP_idx = static_cast<size_t>(target);
} else {
            if (target != 0) {
                                  #if defined(__x86_64__) || defined(_M_X64)
                                  uint64_t a0 = ctx.get_reg(REG_RDI);
                                  uint64_t a1 = ctx.get_reg(REG_RSI);
                                  uint64_t a2 = ctx.get_reg(REG_RDX);
                                  uint64_t a3 = ctx.get_reg(REG_RCX);
                                  uint64_t a4 = ctx.get_reg(REG_R8);
                                  uint64_t a5 = ctx.get_reg(REG_R9);
                                  #else
                                  uint64_t a0 = ctx.get_reg(REG_RAX);
                                  uint64_t a1 = ctx.get_reg(REG_RCX);
                                  uint64_t a2 = ctx.get_reg(REG_RDX);
                                  uint64_t a3 = ctx.get_reg(REG_RBX);
                                  uint64_t a4 = ctx.get_reg(REG_RSI);
                                  uint64_t a5 = ctx.get_reg(REG_RDI);
                                  #endif
                                  typedef uint64_t (*indirect_fn_t)(uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t);
                                  indirect_fn_t fn = reinterpret_cast<indirect_fn_t>(target);
                                  uint64_t ret_val = fn(a0, a1, a2, a3, a4, a5);
                                  ctx.set_reg(REG_RAX, ret_val);
                                  goto EXIT_VM;
            }
}
        ctx.reanchor_running_key(static_cast<uint64_t>(vIP_idx));
        ctx.executed_instructions++;
        FETCH_NEXT();
    }
    H_ICALL_R_D2: {
        uint64_t target_ptr = ctx.get_reg(dst);
        if (target_ptr < count) {
                             ctx.push(static_cast<uint64_t>(vIP_idx));
                             vIP_idx = static_cast<size_t>(target_ptr);
} else {
            if (target_ptr != 0x0000000000000000ULL) {
                                                          #if defined(__x86_64__) || defined(_M_X64)
                                                          uint64_t a0 = ctx.get_reg(REG_RDI);
                                                          uint64_t a1 = ctx.get_reg(REG_RSI);
                                                          uint64_t a2 = ctx.get_reg(REG_RDX);
                                                          uint64_t a3 = ctx.get_reg(REG_RCX);
                                                          uint64_t a4 = ctx.get_reg(REG_R8);
                                                          uint64_t a5 = ctx.get_reg(REG_R9);
                                                          #else
                                                          uint64_t a0 = ctx.get_reg(REG_RAX);
                                                          uint64_t a1 = ctx.get_reg(REG_RCX);
                                                          uint64_t a2 = ctx.get_reg(REG_RDX);
                                                          uint64_t a3 = ctx.get_reg(REG_RBX);
                                                          uint64_t a4 = ctx.get_reg(REG_RSI);
                                                          uint64_t a5 = ctx.get_reg(REG_RDI);
                                                          #endif
                                                          typedef uint64_t (*indirect_fn_t)(uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t);
                                                          indirect_fn_t fn = reinterpret_cast<indirect_fn_t>(target_ptr);
                                                          uint64_t ret_val = fn(a0, a1, a2, a3, a4, a5);
                                                          ctx.set_reg(REG_RAX, ret_val);
            }
}
        ctx.reanchor_running_key(static_cast<uint64_t>(vIP_idx));
        ctx.executed_instructions++;
        FETCH_NEXT();
    }
    H_RET_D2: { if (!ctx.verify_canaries()) {
                                 ctx.trapped = true;
} ctx.executed_instructions++; goto EXIT_VM; }
    H_EXIT_D2: { if (!ctx.verify_canaries()) {
                                 ctx.trapped = true;
} ctx.executed_instructions++; goto EXIT_VM; }

    H_BRIDGE_TO_FLOW_D2: {
        uint64_t _imm_flow = static_cast<uint64_t>(imm);
        ctx.morph_math_to_flow(_imm_flow);
        ctx.executed_instructions += 1;
        FETCH_NEXT();
    }
    H_BRIDGE_TO_MATH_D2: {
        ctx.morph_flow_to_math(static_cast<uint64_t>(imm));
        ctx.executed_instructions++;
        FETCH_NEXT();
    }
    H_FUSED_MOV_ADD_RRI_D2: {
        ctx.set_reg(dst, (ctx.get_reg(src) + static_cast<uint64_t>(imm)));
        ctx.executed_instructions += 2;
        FETCH_NEXT();
    }
    H_FUSED_ADD_IMUL_RRI_D2: {
        uint64_t _imm = static_cast<uint64_t>(imm);
        uint64_t _res = ((ctx.get_reg(dst) * _imm) + (ctx.get_reg(src) * _imm));
        ctx.set_reg(dst, _res);
        ctx.executed_instructions += 2;
        FETCH_NEXT();
    }
    H_FUSED_ADD_XOR_RRI_D2: {
        uint64_t _sum = (ctx.get_reg(dst) + ctx.get_reg(src));
        uint64_t _imm = static_cast<uint64_t>(imm);
        ctx.set_reg(dst, ((_sum + _imm) - (0x0000000000000002ULL * (_sum & _imm))));
        ctx.executed_instructions += 2;
        FETCH_NEXT();
    }
    H_FUSED_SUB_XOR_RRI_D2: {
        uint64_t _diff = (ctx.get_reg(dst) - ctx.get_reg(src));
        uint64_t _imm = static_cast<uint64_t>(imm);
        ctx.set_reg(dst, ((_diff + _imm) - (0x0000000000000002ULL * (_diff & _imm))));
        ctx.executed_instructions += 2;
        FETCH_NEXT();
    }
    H_FUSED_XOR_ADD_RRI_D2: {
        uint64_t _a = ctx.get_reg(dst);
        uint64_t _b = ctx.get_reg(src);
        uint64_t _x = ((_a + _b) - (0x0000000000000002ULL * (_a & _b)));
        ctx.set_reg(dst, (_x + static_cast<uint64_t>(imm)));
        ctx.executed_instructions += 2;
        FETCH_NEXT();
    }
    H_FUSED_CMP_CMOV_D2: {
        uint64_t a = ctx.get_reg(dst);
        uint64_t b = static_cast<uint64_t>(imm);
        uint8_t cond = static_cast<uint8_t>(((word >> 0x0000000000000032ULL) & 0x000000000000000fULL));
        uint32_t bits = static_cast<uint32_t>(((word >> 0x0000000000000036ULL) & 0x000000000000007fULL));
        compute_sub_flags(ctx, a, b, bits);
        uint64_t _m = (eval_condition(ctx, cond) ? (~0x0000000000000000ULL) : 0x0000000000000000ULL);
        ctx.set_reg(dst, ((ctx.get_reg(src) & _m) | (a & (~_m))));
        ctx.executed_instructions += 2;
        FETCH_NEXT();
    }
    H_FUSED_AND_OR_RRI_D2: {
        ctx.set_reg(dst, ((ctx.get_reg(dst) & ctx.get_reg(src)) | static_cast<uint64_t>(imm)));
        ctx.executed_instructions += 2;
        FETCH_NEXT();
    }
    H_FUSED_SHL_ADD_RRI_D2: {
        uint64_t _shl = (ctx.get_reg(dst) << (static_cast<uint64_t>(imm) & 0x000000000000003fULL));
        uint64_t _s = ctx.get_reg(src);
        ctx.set_reg(dst, ((_shl ^ _s) + (0x0000000000000002ULL * (_shl & _s))));
        ctx.executed_instructions += 2;
        FETCH_NEXT();
    }
    H_VADD_VV_D2: {
        uint64_t d0 = ctx.get_vreg_lane(dst, 0), d1 = ctx.get_vreg_lane(dst, 1);
        uint64_t s0 = ctx.get_vreg_lane(src, 0), s1 = ctx.get_vreg_lane(src, 1);
        uint64_t _res0 = d0 + s0; uint64_t _res1 = d1 + s1;
        ctx.set_vreg(dst, _res0, _res1);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_VSUB_VV_D2: {
        uint64_t d0 = ctx.get_vreg_lane(dst, 0), d1 = ctx.get_vreg_lane(dst, 1);
        uint64_t s0 = ctx.get_vreg_lane(src, 0), s1 = ctx.get_vreg_lane(src, 1);
#if defined(ASGARD_VECTOR_ISA) && defined(__aarch64__)
        uint64x2_t vr = vsubq_u64(vcombine_u64(vcreate_u64(d0), vcreate_u64(d1)), vcombine_u64(vcreate_u64(s0), vcreate_u64(s1)));
        ctx.set_vreg(dst, vgetq_lane_u64(vr, 0), vgetq_lane_u64(vr, 1));
#elif defined(ASGARD_VECTOR_ISA) && defined(__x86_64__)
        __m128i vr = _mm_sub_epi64(_mm_set_epi64x((int64_t)d1, (int64_t)d0), _mm_set_epi64x((int64_t)s1, (int64_t)s0));
        ctx.set_vreg(dst, static_cast<uint64_t>(_mm_extract_epi64(vr, 0)), static_cast<uint64_t>(_mm_extract_epi64(vr, 1)));
#else
        uint64_t _r0 = d0 - s0, _r1 = d1 - s1; ctx.set_vreg(dst, _r0, _r1);
#endif
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_VMUL_VV_D2: {
        uint64_t d0 = ctx.get_vreg_lane(dst, 0), d1 = ctx.get_vreg_lane(dst, 1);
        uint64_t s0 = ctx.get_vreg_lane(src, 0), s1 = ctx.get_vreg_lane(src, 1);
        uint64_t _m0 = d0 * s0, _m1 = d1 * s1; ctx.set_vreg(dst, _m0, _m1);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_VXOR_VV_D2: {
        uint64_t d0 = ctx.get_vreg_lane(dst, 0), d1 = ctx.get_vreg_lane(dst, 1);
        uint64_t s0 = ctx.get_vreg_lane(src, 0), s1 = ctx.get_vreg_lane(src, 1);
        uint64_t _res0 = d0 ^ s0; uint64_t _res1 = d1 ^ s1;
        ctx.set_vreg(dst, _res0, _res1);
        ctx.executed_instructions++; FETCH_NEXT();
    }

    H_VEC_MOV_D2: {
        uint32_t bits = (uint32_t)(imm & 0x3ff); size_t i = 0;
        while (i < (bits + 63) / 64) { ctx.set_vreg_lane(dst, i, ctx.get_vreg_lane(src, i)); ++i; }
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_VEC_BINOP_D2: {
        uint32_t src2 = (uint32_t)(imm & 31);
        uint32_t bits = (uint32_t)((imm >> 5) & 0x3ff);
        uint32_t lane_bits = (uint32_t)((imm >> 15) & 0xff);
        if (lane_bits == 0) lane_bits = 64;
        uint32_t vop = (uint32_t)((imm >> 23) & 0x1f);
        uint32_t elem = (uint32_t)((imm >> 28) & 0x3);
        uint64_t mask = lane_bits == 8 ? 0xffULL : (lane_bits == 16 ? 0xffffULL : (lane_bits == 32 ? 0xffffffffULL : ~0ULL));
        for (size_t bit = 0; bit < bits; bit += lane_bits) {
            size_t chunk = bit / 64; unsigned shift = (unsigned)(bit % 64);
            uint64_t a = (ctx.get_vreg_lane(src, chunk) >> shift) & mask;
            uint64_t b = (ctx.get_vreg_lane(src2, chunk) >> shift) & mask;
            uint64_t value = 0;
            if (elem == 1 && vop <= 2) {
                float fa = std::bit_cast<float>(static_cast<uint32_t>(a));
                float fb = std::bit_cast<float>(static_cast<uint32_t>(b));
                float fr = vop == 0 ? fa + fb : (vop == 1 ? fa - fb : fa * fb);
                value = std::bit_cast<uint32_t>(fr);
            } else if (elem == 1 && vop == 11) {
                float fa = std::bit_cast<float>(static_cast<uint32_t>(a));
                float fb = std::bit_cast<float>(static_cast<uint32_t>(b));
                value = std::bit_cast<uint32_t>(std::fmin(fa, fb));
            } else if (elem == 1 && vop == 12) {
                float fa = std::bit_cast<float>(static_cast<uint32_t>(a));
                float fb = std::bit_cast<float>(static_cast<uint32_t>(b));
                value = std::bit_cast<uint32_t>(std::fmax(fa, fb));
            } else if (elem == 2 && vop <= 2) {
                double fa = std::bit_cast<double>(a);
                double fb = std::bit_cast<double>(b);
                double fr = vop == 0 ? fa + fb : (vop == 1 ? fa - fb : fa * fb);
                value = std::bit_cast<uint64_t>(fr);
            } else if (elem == 2 && vop == 11) {
                double fa = std::bit_cast<double>(a);
                double fb = std::bit_cast<double>(b);
                value = std::bit_cast<uint64_t>(std::fmin(fa, fb));
            } else if (elem == 2 && vop == 12) {
                double fa = std::bit_cast<double>(a);
                double fb = std::bit_cast<double>(b);
                value = std::bit_cast<uint64_t>(std::fmax(fa, fb));
            } else {
                int64_t sa = lane_bits == 8 ? (int64_t)(int8_t)a : (lane_bits == 16 ? (int64_t)(int16_t)a : (lane_bits == 32 ? (int64_t)(int32_t)a : (int64_t)a));
                int64_t sb = lane_bits == 8 ? (int64_t)(int8_t)b : (lane_bits == 16 ? (int64_t)(int16_t)b : (lane_bits == 32 ? (int64_t)(int32_t)b : (int64_t)b));
                switch (vop) {
                    case 0: value = a + b; break;
                    case 1: value = a - b; break;
                    case 2: value = a * b; break;
                    case 3: value = a & b; break;
                    case 4: value = a | b; break;
                    case 5: value = a ^ b; break;
                    case 6: { uint32_t cnt = (uint32_t)(ctx.get_vreg_lane(src2, 0) & 0xff); value = (cnt >= lane_bits) ? 0 : (a << cnt); break; }
                    case 7: { uint32_t cnt = (uint32_t)(ctx.get_vreg_lane(src2, 0) & 0xff); value = (cnt >= lane_bits) ? 0 : (a >> cnt); break; }
                    case 8: { uint32_t cnt = (uint32_t)(ctx.get_vreg_lane(src2, 0) & 0xff); value = (cnt >= lane_bits) ? (sa < 0 ? mask : 0) : ((uint64_t)(sa >> cnt) & mask); break; }
                    case 9: value = (a == b) ? mask : 0; break;
                    case 10: value = (sa > sb) ? mask : 0; break;
                    case 11: value = (sa < sb) ? a : b; break;
                    case 12: value = (sa > sb) ? a : b; break;
                    case 13: value = (a < b) ? a : b; break;
                    case 14: value = (a > b) ? a : b; break;
                    case 15: value = (uint64_t)(sa < 0 ? -sa : sa) & mask; break;
                    case 16: value = (~a) & b; break;
                    case 17: {
                        size_t block_lane = (bit / lane_bits) % (128 / lane_bits);
                        size_t half_idx = block_lane / 2;
                        size_t src_reg = (block_lane % 2 == 0) ? src : src2;
                        size_t src_bit = ((bit / 128) * 128) + (half_idx * lane_bits);
                        value = (ctx.get_vreg_lane(src_reg, src_bit / 64) >> (src_bit % 64)) & mask;
                        break;
                    }
                    case 18: {
                        size_t num_lanes = 128 / lane_bits;
                        size_t block_lane = (bit / lane_bits) % num_lanes;
                        size_t half_idx = (num_lanes / 2) + (block_lane / 2);
                        size_t src_reg = (block_lane % 2 == 0) ? src : src2;
                        size_t src_bit = ((bit / 128) * 128) + (half_idx * lane_bits);
                        value = (ctx.get_vreg_lane(src_reg, src_bit / 64) >> (src_bit % 64)) & mask;
                        break;
                    }
                    case 21: {
                        uint8_t ctrl = (uint8_t)(b & 0xff);
                        if (ctrl & 0x80) value = 0;
                        else {
                            size_t src_bit = ((bit / 128) * 128) + ((ctrl & 0xf) * 8);
                            value = (ctx.get_vreg_lane(src, src_bit / 64) >> (src_bit % 64)) & 0xff;
                        }
                        break;
                    }
                    case 23: {
                        size_t num_lanes = 128 / lane_bits;
                        size_t block_lane = (bit / lane_bits) % num_lanes;
                        size_t half_len = num_lanes / 2;
                        size_t src_reg = (block_lane < half_len) ? src : src2;
                        size_t sel_elem = (block_lane < half_len) ? (block_lane * 2) : ((block_lane - half_len) * 2);
                        size_t src_bit = ((bit / 128) * 128) + (sel_elem * lane_bits);
                        value = (ctx.get_vreg_lane(src_reg, src_bit / 64) >> (src_bit % 64)) & mask;
                        break;
                    }
                    case 24: {
                        size_t num_lanes = 128 / lane_bits;
                        size_t block_lane = (bit / lane_bits) % num_lanes;
                        size_t half_len = num_lanes / 2;
                        size_t src_reg = (block_lane < half_len) ? src : src2;
                        size_t sel_elem = (block_lane < half_len) ? (block_lane * 2 + 1) : ((block_lane - half_len) * 2 + 1);
                        size_t src_bit = ((bit / 128) * 128) + (sel_elem * lane_bits);
                        value = (ctx.get_vreg_lane(src_reg, src_bit / 64) >> (src_bit % 64)) & mask;
                        break;
                    }
                    case 25: {
                        size_t num_lanes = 128 / lane_bits;
                        size_t block_lane = (bit / lane_bits) % num_lanes;
                        size_t k = block_lane / 2;
                        size_t src_reg = (block_lane % 2 == 0) ? src : src2;
                        size_t sel_elem = k * 2;
                        size_t src_bit = ((bit / 128) * 128) + (sel_elem * lane_bits);
                        value = (ctx.get_vreg_lane(src_reg, src_bit / 64) >> (src_bit % 64)) & mask;
                        break;
                    }
                    case 26: {
                        size_t num_lanes = 128 / lane_bits;
                        size_t block_lane = (bit / lane_bits) % num_lanes;
                        size_t k = block_lane / 2;
                        size_t src_reg = (block_lane % 2 == 0) ? src : src2;
                        size_t sel_elem = k * 2 + 1;
                        size_t src_bit = ((bit / 128) * 128) + (sel_elem * lane_bits);
                        value = (ctx.get_vreg_lane(src_reg, src_bit / 64) >> (src_bit % 64)) & mask;
                        break;
                    }
                    case 28: {
                        uint8_t idx = (uint8_t)(b & 0xff);
                        if (idx < 16) {
                            size_t src_bit = ((bit / 128) * 128) + (idx * 8);
                            value = (ctx.get_vreg_lane(src, src_bit / 64) >> (src_bit % 64)) & 0xff;
                        } else {
                            value = 0;
                        }
                        break;
                    }
                    case 29: {
                        uint8_t idx = (uint8_t)(b & 0xff);
                        if (idx < 16) {
                            size_t src_bit = ((bit / 128) * 128) + (idx * 8);
                            value = (ctx.get_vreg_lane(src, src_bit / 64) >> (src_bit % 64)) & 0xff;
                        } else {
                            value = (ctx.get_vreg_lane(dst, chunk) >> shift) & 0xff;
                        }
                        break;
                    }
                    case 30: {
                        int64_t min_val = (lane_bits == 64) ? (int64_t)0x8000000000000000ULL : (lane_bits == 32) ? (int64_t)(int32_t)0x80000000 : (lane_bits == 16) ? (int64_t)(int16_t)0x8000 : (int64_t)(int8_t)0x80;
                        if (sb == 0) value = ~0ULL;
                        else if (sb == -1 && sa == min_val) value = (uint64_t)sa;
                        else value = (uint64_t)(sa / sb);
                        break;
                    }
                    case 31: {
                        value = (b != 0) ? (a / b) : mask;
                        break;
                    }
                    case 32: {
                        int64_t min_val = (lane_bits == 64) ? (int64_t)0x8000000000000000ULL : (lane_bits == 32) ? (int64_t)(int32_t)0x80000000 : (lane_bits == 16) ? (int64_t)(int16_t)0x8000 : (int64_t)(int8_t)0x80;
                        if (sb == 0) value = a;
                        else if (sb == -1 && sa == min_val) value = 0;
                        else value = (uint64_t)(sa % sb);
                        break;
                    }
                    case 33: {
                        value = (b != 0) ? (a % b) : a;
                        break;
                    }
                    case 34: value = (a != b) ? mask : 0; break;
                    case 35: value = (sa <= sb) ? mask : 0; break;
                    case 36: value = (a < b) ? mask : 0; break;
                    case 37: value = (a <= b) ? mask : 0; break;
                    default: value = a ^ b; break;
                }
            }
            uint64_t old_value = ctx.get_vreg_lane(dst, chunk);
            uint64_t packed_mask = mask << shift;
            ctx.set_vreg_lane(dst, chunk, (old_value & ~packed_mask) | ((value & mask) << shift));
        }
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_VEC_IMM_D2: {
        uint64_t imm_val = imm & 0xffULL;
        uint32_t bits = (uint32_t)((imm >> 8) & 0x3ff);
        uint32_t lane_bits = (uint32_t)((imm >> 18) & 0xff);
        if (lane_bits == 0) lane_bits = 64;
        uint32_t vop = (uint32_t)((imm >> 26) & 0x1f);
        uint64_t mask = lane_bits == 8 ? 0xffULL : (lane_bits == 16 ? 0xffffULL : (lane_bits == 32 ? 0xffffffffULL : ~0ULL));
        for (size_t bit = 0; bit < bits; bit += lane_bits) {
            size_t chunk = bit / 64; unsigned shift = (unsigned)(bit % 64);
            uint64_t a = (ctx.get_vreg_lane(src, chunk) >> shift) & mask;
            int64_t sa = lane_bits == 8 ? (int64_t)(int8_t)a : (lane_bits == 16 ? (int64_t)(int16_t)a : (lane_bits == 32 ? (int64_t)(int32_t)a : (int64_t)a));
            uint64_t value = 0;
            switch (vop) {
                case 6: { uint32_t cnt = (uint32_t)imm_val; value = (cnt >= lane_bits) ? 0 : (a << cnt); break; }
                case 7: { uint32_t cnt = (uint32_t)imm_val; value = (cnt >= lane_bits) ? 0 : (a >> cnt); break; }
                case 8: { uint32_t cnt = (uint32_t)imm_val; value = (cnt >= lane_bits) ? (sa < 0 ? mask : 0) : ((uint64_t)(sa >> cnt) & mask); break; }
                case 21: {
                    size_t lane_in_128 = (bit / 32) % 4;
                    size_t sel = (imm_val >> (lane_in_128 * 2)) & 3;
                    size_t src_bit = ((bit / 128) * 128) + (sel * 32);
                    value = (ctx.get_vreg_lane(src, src_bit / 64) >> (src_bit % 64)) & 0xffffffffULL;
                    break;
                }
                case 22: {
                    size_t lane_idx = bit / lane_bits;
                    size_t sel = (imm_val >> (lane_idx % 8)) & 1;
                    value = (sel == 0) ? a : ((ctx.get_vreg_lane(dst, chunk) >> shift) & mask);
                    break;
                }
                default: value = a; break;
            }
            uint64_t old_value = ctx.get_vreg_lane(dst, chunk);
            uint64_t packed_mask = mask << shift;
            ctx.set_vreg_lane(dst, chunk, (old_value & ~packed_mask) | ((value & mask) << shift));
        }
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_VEC_CLEAR_UPPER_D2: {
        ctx.set_vreg_lane(dst, 2, 0ULL);
        ctx.set_vreg_lane(dst, 3, 0ULL);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_VEC_ZERO_UPPER_D2: {
        for (size_t i = 0; i < 16; ++i) {
            ctx.set_vreg_lane(i, 2, 0ULL);
            ctx.set_vreg_lane(i, 3, 0ULL);
        }
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_PMOVMSKB_D2: {
        uint32_t bits = (uint32_t)(imm & 0x3ff);
        uint32_t num_bytes = bits / 8;
        uint64_t mask = 0;
        for (uint32_t b = 0; b < num_bytes; ++b) {
            uint64_t byte_val = (ctx.get_vreg_lane(src, b / 8) >> ((b % 8) * 8)) & 0xff;
            if (byte_val & 0x80) mask |= (1ULL << b);
        }
        ctx.set_reg(dst, mask);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_VEC_LOAD_D2: {
        uint32_t bits = (uint32_t)((word >> 50) & 0x3ff);
        uint64_t address = ctx.get_reg(src) + (uint64_t)imm;
        for (size_t i = 0; i < (bits + 63) / 64; ++i) { uint64_t value = 0; std::memcpy(&value, reinterpret_cast<const void*>(address + i * 8), sizeof(value)); ctx.set_vreg_lane(dst, i, value); }
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_VEC_STORE_D2: {
        uint32_t bits = (uint32_t)((word >> 50) & 0x3ff);
        uint64_t address = ctx.get_reg(dst) + (uint64_t)imm;
        for (size_t i = 0; i < (bits + 63) / 64; ++i) std::memcpy(reinterpret_cast<void*>(address + i * 8), &ctx.vregs[src & 31][i & 7], sizeof(uint64_t));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_VEC_SPLAT_D2: {
        uint32_t bits = (uint32_t)(imm & 0xffff);
        uint32_t lane_bits = (uint32_t)((imm >> 16) & 0xffff);
        uint64_t val = ctx.get_reg(src);
        uint64_t mask = (lane_bits >= 64) ? ~0ULL : ((1ULL << lane_bits) - 1ULL);
        uint64_t val_masked = val & mask;
        uint32_t num_lanes = (lane_bits > 0) ? (bits / lane_bits) : 0;
        for (uint32_t l = 0; l < num_lanes; ++l) {
            uint32_t pos = l * lane_bits;
            uint32_t chunk = pos / 64;
            uint32_t shift = pos % 64;
            uint64_t packed_mask = (lane_bits >= 64) ? ~0ULL : (mask << shift);
            uint64_t cur = ctx.get_vreg_lane(dst, chunk);
            cur = (cur & ~packed_mask) | (val_masked << shift);
            ctx.set_vreg_lane(dst, chunk, cur);
        }
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_VEC_EXT_D2: {
        uint32_t src2 = (uint32_t)(imm & 31);
        uint32_t shift_bytes = (uint32_t)((imm >> 5) & 15);
        uint32_t bits = (uint32_t)((imm >> 9) & 0x3ff);
        if (bits == 0) bits = 128;
        for (size_t byte_idx = 0; byte_idx < (bits / 8); ++byte_idx) {
            size_t total_idx = (byte_idx % 16) + shift_bytes;
            uint64_t val = 0;
            if (total_idx < 16) {
                size_t bit_pos = ((byte_idx / 16) * 128) + (total_idx * 8);
                val = (ctx.get_vreg_lane(src, bit_pos / 64) >> (bit_pos % 64)) & 0xff;
            } else {
                size_t m_idx = total_idx - 16;
                size_t bit_pos = ((byte_idx / 16) * 128) + (m_idx * 8);
                val = (ctx.get_vreg_lane(src2, bit_pos / 64) >> (bit_pos % 64)) & 0xff;
            }
            size_t chunk = (byte_idx * 8) / 64; unsigned shift = (unsigned)((byte_idx * 8) % 64);
            uint64_t old_v = ctx.get_vreg_lane(dst, chunk);
            uint64_t clr = old_v & ~(0xffULL << shift);
            ctx.set_vreg_lane(dst, chunk, clr | (val << shift));
        }
        ctx.executed_instructions++; FETCH_NEXT();
    }

    H_CALL_EXTERN_D2: {
        size_t sym_idx = (size_t)imm;
        void* sym_ptr = asgard_resolve_sym_idx((int32_t)sym_idx);
        if (sym_ptr) {
            uint32_t sym_h = g_external_symbols[sym_idx].hash;
            uint32_t sym_ah = g_external_symbols[sym_idx].alt_hash;
            uint64_t a0 = ctx.get_reg(REG_RAX);
            uint64_t a1 = ctx.get_reg(REG_RCX);
            uint64_t a2 = ctx.get_reg(REG_RDX);
            uint64_t a3 = ctx.get_reg(REG_RBX);
            uint64_t a4 = ctx.get_reg(REG_RSI);
            uint64_t a5 = ctx.get_reg(REG_RDI);
            uint64_t a6 = ctx.get_reg(REG_R8);
            uint64_t a7 = ctx.get_reg(REG_R9);
            const uint64_t* stk = reinterpret_cast<const uint64_t*>(ctx.get_reg(REG_RSP));
            uint64_t ret_val = 0;
            if (sym_h == 0x42FCF5CFU || sym_ah == 0x42FCF5CFU || sym_h == 0x07554ACDU || sym_ah == 0x07554ACDU || sym_h == 0xE76FB4AAU || sym_ah == 0xE76FB4AAU) {
                typedef int (*printf_fn_t)(const char*, ...);
                printf_fn_t pfn = reinterpret_cast<printf_fn_t>(sym_ptr);
#if defined(__APPLE__) && defined(__aarch64__)
                ret_val = (uint64_t)pfn((const char*)a0, stk[0], stk[1], stk[2], stk[3], stk[4], stk[5], stk[6], stk[7]);
#else
                ret_val = (uint64_t)pfn((const char*)a0, a1, a2, a3, a4, a5, a6, a7);
#endif
            } else if (sym_h == 0xFCB512E2U || sym_ah == 0xFCB512E2U || sym_h == 0x4B3C5330U || sym_ah == 0x4B3C5330U || sym_h == 0x937D1EF6U || sym_ah == 0x937D1EF6U || sym_h == 0xCB76D42BU || sym_ah == 0xCB76D42BU || sym_h == 0xD54CE817U || sym_ah == 0xD54CE817U || sym_h == 0xBBED3905U || sym_ah == 0xBBED3905U || sym_h == 0x42C07C7CU || sym_ah == 0x42C07C7CU || sym_h == 0x24559DBDU || sym_ah == 0x24559DBDU) {
                typedef int (*fprintf_fn_t)(void*, const char*, ...);
                fprintf_fn_t fpfn = reinterpret_cast<fprintf_fn_t>(sym_ptr);
#if defined(__APPLE__) && defined(__aarch64__)
                ret_val = (uint64_t)fpfn((void*)a0, (const char*)a1, stk[0], stk[1], stk[2], stk[3], stk[4], stk[5], stk[6], stk[7]);
#else
                ret_val = (uint64_t)fpfn((void*)a0, (const char*)a1, a2, a3, a4, a5, a6, a7);
#endif
            } else if (sym_h == 0x7FE32B00U || sym_ah == 0x7FE32B00U || sym_h == 0xBCBF60EEU || sym_ah == 0xBCBF60EEU || sym_h == 0x70E2D349U || sym_ah == 0x70E2D349U || sym_h == 0x44FA3468U || sym_ah == 0x44FA3468U) {
                typedef int (*sprintf_fn_t)(char*, const char*, ...);
                sprintf_fn_t spfn = reinterpret_cast<sprintf_fn_t>(sym_ptr);
#if defined(__APPLE__) && defined(__aarch64__)
                ret_val = (uint64_t)spfn((char*)a0, (const char*)a1, stk[0], stk[1], stk[2], stk[3], stk[4], stk[5], stk[6], stk[7]);
#else
                ret_val = (uint64_t)spfn((char*)a0, (const char*)a1, a2, a3, a4, a5, a6, a7);
#endif
            } else if (sym_h == 0x54EE11FAU || sym_ah == 0x54EE11FAU || sym_h == 0x933075F4U || sym_ah == 0x933075F4U || sym_h == 0x3FD5EB6FU || sym_ah == 0x3FD5EB6FU || sym_h == 0x5B3553B4U || sym_ah == 0x5B3553B4U) {
                typedef int (*snprintf_fn_t)(char*, size_t, const char*, ...);
                snprintf_fn_t snpfn = reinterpret_cast<snprintf_fn_t>(sym_ptr);
#if defined(__APPLE__) && defined(__aarch64__)
                ret_val = (uint64_t)snpfn((char*)a0, (size_t)a1, (const char*)a2, stk[0], stk[1], stk[2], stk[3], stk[4], stk[5], stk[6], stk[7]);
#else
                ret_val = (uint64_t)snpfn((char*)a0, (size_t)a1, (const char*)a2, a3, a4, a5, a6, a7);
#endif
            } else {
                typedef uint64_t (*extern_fn_t)(uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t);
                extern_fn_t fn = reinterpret_cast<extern_fn_t>(sym_ptr);
                ret_val = fn(a0, a1, a2, a3, a4, a5, a6, a7);
            }
            ctx.set_reg(REG_RAX, ret_val);
        }
        ctx.executed_instructions++; FETCH_NEXT();
    }

    H_LOAD_64_D2: {
        uintptr_t _ptr = static_cast<uintptr_t>(ctx.get_reg(src)) + static_cast<uintptr_t>(imm);
        uint64_t _v = 0;
        std::memcpy(&_v, reinterpret_cast<const void*>(_ptr), sizeof(uint64_t));
        ctx.set_reg(dst, _v);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_LOAD_32_D2: {
        uintptr_t _ptr = static_cast<uintptr_t>(ctx.get_reg(src)) + static_cast<uintptr_t>(imm);
        uint32_t _v32 = 0;
        std::memcpy(&_v32, reinterpret_cast<const void*>(_ptr), sizeof(uint32_t));
        ctx.set_reg(dst, (uint64_t)_v32);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_LOAD_16_D2: {
        const char* _base = reinterpret_cast<const char*>(ctx.get_reg(src));
        ctx.set_reg(dst, (uint64_t)(*reinterpret_cast<const uint16_t*>(_base + imm)));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_LOAD_8_D2: {
        uint64_t addr = ctx.get_reg(src) + (uint64_t)imm;
        ctx.set_reg(dst, (uint64_t)(*reinterpret_cast<const uint8_t*>(addr)));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_LOAD_S32_D2: {
        uintptr_t _ptr = static_cast<uintptr_t>(ctx.get_reg(src)) + static_cast<uintptr_t>(imm);
        int32_t _s32 = 0;
        std::memcpy(&_s32, reinterpret_cast<const void*>(_ptr), sizeof(int32_t));
        ctx.set_reg(dst, (uint64_t)(int64_t)_s32);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_LOAD_S16_D2: {
        const char* _base = reinterpret_cast<const char*>(ctx.get_reg(src));
        ctx.set_reg(dst, (uint64_t)(int64_t)(*reinterpret_cast<const int16_t*>(_base + imm)));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_LOAD_S8_D2: {
        const char* _base = reinterpret_cast<const char*>(ctx.get_reg(src));
        ctx.set_reg(dst, (uint64_t)(int64_t)(*reinterpret_cast<const int8_t*>(_base + imm)));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_STORE_64_D2: {
        uint64_t addr = ctx.get_reg(dst) + (uint64_t)imm;
        *reinterpret_cast<uint64_t*>(addr) = ctx.get_reg(src);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_STORE_32_D2: {
        uintptr_t _ptr = static_cast<uintptr_t>(ctx.get_reg(dst)) + static_cast<uintptr_t>(imm);
        uint32_t _v32 = (uint32_t)ctx.get_reg(src);
        std::memcpy(reinterpret_cast<void*>(_ptr), &_v32, sizeof(uint32_t));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_STORE_16_D2: {
        uint64_t addr = ctx.get_reg(dst) + (uint64_t)imm;
        *reinterpret_cast<uint16_t*>(addr) = (uint16_t)ctx.get_reg(src);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_STORE_8_D2: {
        uint64_t addr = ctx.get_reg(dst) + (uint64_t)imm;
        *reinterpret_cast<uint8_t*>(addr) = (uint8_t)ctx.get_reg(src);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_RESOLVE_SYM_D2: {
        size_t _idx = static_cast<size_t>(imm);
        void* _p = asgard_resolve_sym_idx((int32_t)_idx);
        ctx.set_reg(dst, static_cast<uint64_t>(reinterpret_cast<uintptr_t>(_p)));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_FADD_DD_D2: {
        uint64_t _s = ctx.get_vreg_lane(src, 0), _i = ctx.get_vreg_lane((uint8_t)imm, 0);
        ctx.set_vreg(dst, std::bit_cast<uint64_t>(std::bit_cast<double>(_s) + std::bit_cast<double>(_i)), 0);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_FSUB_DD_D2: {
        uint64_t _s = ctx.get_vreg_lane(src, 0), _i = ctx.get_vreg_lane((uint8_t)imm, 0);
        ctx.set_vreg(dst, std::bit_cast<uint64_t>(std::bit_cast<double>(_s) - std::bit_cast<double>(_i)), 0);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_FMUL_DD_D2: {
        double _a = std::bit_cast<double>(ctx.get_vreg_lane(src, 0));
        double _b = std::bit_cast<double>(ctx.get_vreg_lane(static_cast<uint8_t>(imm), 0));
        ctx.set_vreg(dst, std::bit_cast<uint64_t>(_a * _b), 0);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_FDIV_DD_D2: {
        uint64_t _s = ctx.get_vreg_lane(src, 0), _i = ctx.get_vreg_lane((uint8_t)imm, 0);
        double a = std::bit_cast<double>(_s), b = std::bit_cast<double>(_i);
        ctx.set_vreg(dst, std::bit_cast<uint64_t>((b != 0.0) ? (a / b) : 0.0), 0);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_FSQRT_D_D2: {
        uint64_t a_raw = ctx.get_vreg_lane(src, 0);
        double a = std::bit_cast<double>(a_raw);
        double r = std::sqrt(a);
        ctx.set_vreg(dst, std::bit_cast<uint64_t>(r), 0);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_FCMP_DD_D2: {
        double _a = std::bit_cast<double>(ctx.get_vreg_lane(src, 0));
        double _b = std::bit_cast<double>(ctx.get_vreg_lane(static_cast<uint8_t>(imm), 0));
        ctx.of = false;
        ctx.sf = (_a < _b);
        ctx.cf = (_a >= _b);
        ctx.zf = (_a == _b);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_FCVTZS_D2: {
        uint64_t a_raw = ctx.get_vreg_lane(src, 0);
        double a = std::bit_cast<double>(a_raw);
        ctx.set_reg(dst, (uint64_t)((int64_t)a));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_SCVTF_D2: {
        int64_t v = (int64_t)ctx.get_reg(src);
        ctx.set_vreg(dst, std::bit_cast<uint64_t>((double)v), 0);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_FCVTZU_D2: {
        double a = std::bit_cast<double>(ctx.get_vreg_lane(src, 0));
        if (a < 0.0) ctx.set_reg(dst, 0ULL); else ctx.set_reg(dst, (uint64_t)a);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_UCVTF_D2: {
        uint64_t _v = ctx.get_reg(src);
        ctx.set_vreg(dst, std::bit_cast<uint64_t>((double)_v), 0);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_FCVT_D2: {
        uint32_t _raw32 = static_cast<uint32_t>(ctx.get_vreg_lane(src, 0));
        float _f = std::bit_cast<float>(_raw32);
        double _d = static_cast<double>(_f);
        ctx.set_vreg(dst, std::bit_cast<uint64_t>(_d), 0);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_ATOMIC_LOAD_D2: {
        uint64_t _addr = ctx.get_reg(src) + (uint64_t)imm;
        std::atomic_thread_fence(std::memory_order_seq_cst);
        uint64_t _loaded = *reinterpret_cast<volatile uint64_t*>(_addr);
        std::atomic_thread_fence(std::memory_order_seq_cst);
        ctx.set_reg(dst, _loaded);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_ATOMIC_STORE_D2: {
        uint64_t _addr = ctx.get_reg(dst) + static_cast<uint64_t>(imm);
        __atomic_store_n(reinterpret_cast<uint64_t*>(_addr), ctx.get_reg(src), __ATOMIC_SEQ_CST);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_ATOMIC_CAS_D2: {
        uint64_t _addr = ctx.get_reg(dst) + static_cast<uint64_t>(imm);
        uint64_t _exp = ctx.get_reg(src), _des = ctx.get_reg(REG_RAX);
        __atomic_compare_exchange_n(reinterpret_cast<uint64_t*>(_addr), &_exp, _des, false, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST);
        ctx.set_reg(src, _exp);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_ATOMIC_ADD_D2: {
        uint64_t _addr = ctx.get_reg(dst) + static_cast<uint64_t>(imm);
        uint64_t _old = __atomic_fetch_add(reinterpret_cast<uint64_t*>(_addr), ctx.get_reg(src), __ATOMIC_SEQ_CST);
        ctx.set_reg(src, _old);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_ATOMIC_SWP_D2: {
        uint64_t addr = ctx.get_reg(dst) + (uint64_t)imm;
        auto* ptr = reinterpret_cast<std::atomic<uint64_t>*>(addr);
        uint64_t old = ptr->exchange(ctx.get_reg(src), std::memory_order_seq_cst);
        ctx.set_reg(src, old);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_FENCE_D2: { std::atomic_thread_fence(std::memory_order_seq_cst); ctx.executed_instructions++; FETCH_NEXT(); }
    H_MOV_VR_D2: {
        uint64_t _val = ctx.get_reg(src);
        uint64_t _buf[1];
        std::memcpy(_buf, (&_val), sizeof(uint64_t));
        ctx.set_vreg_lane(dst, 0, _buf[0]);
        ctx.executed_instructions++;
        FETCH_NEXT();
    }
    H_MOV_RV_D2: {
        uint64_t _val = (ctx.get_vreg_lane(src, 0) ^ 0x5a5a5a5aa5a5a5a5ULL);
        ctx.set_reg(dst, (_val ^ 0x5a5a5a5aa5a5a5a5ULL));
        ctx.executed_instructions++;
        FETCH_NEXT();
    }
    H_FCSEL_VV_D2: {
        uint8_t cond = (uint8_t)((((word >> 18) + 0x0FULL) - ((word >> 18) | 0x0FULL)));
        if (eval_condition(ctx, cond)) ctx.set_vreg_lane(dst, 0, ctx.get_vreg_lane(src, 0));
        ctx.executed_instructions++; FETCH_NEXT();
    }



                                    EXIT_VM:
                                        for (size_t i = 0; i < count; ++i) {
        SCRUB_WORD(&work_bc[i], 0x5A5A5A5A13375877ULL ^ ((uint64_t)seed + (uint64_t)i));
    }
                                        if (scrub_source && bytecode) {
        for (size_t i = 0; i < count; ++i) {
            SCRUB_WORD(&const_cast<uint64_t*>(bytecode)[i], 0xDEADBEEFCAFEBABEULL ^ ((uint64_t)seed + (uint64_t)i));
        }
    }
                                    if (heap_work_bc != nullptr) {
                                                                    free(heap_work_bc);
                                    }
                                    
                                    #undef DISPATCH_OPCODE
                                    
                                    
                                    #undef FETCH_NEXT
                                    
                                    return (!ctx.trapped);
                                }
                                
                                static inline bool execute_threaded(VMContext& ctx, const uint64_t* bytecode, size_t count, bool scrub_source) {
                                
                                    return execute_threaded(ctx, bytecode, count, asgard_wbox_derive_seed(), scrub_source);
                                }
                                
                                static inline __attribute__((noinline)) uint64_t asgard_vm_call(const uint64_t* bc, size_t len, uint64_t a0 = 0, uint64_t a1 = 0, uint64_t a2 = 0, uint64_t a3 = 0, uint64_t a4 = 0, uint64_t a5 = 0, uint64_t a6 = 0, uint64_t a7 = 0) {
                                
                                    vanguard_threaded_vm::VMContext ctx = {};
                                    ctx.init(asgard_wbox_derive_seed());
                                    alignas(16) static thread_local uint8_t host_stack[1048576];
                                    ctx.set_reg(vanguard_threaded_vm::REG_RSP, ((uint64_t)(((host_stack + sizeof(host_stack)) - 0x0000000000002000ULL))));
                                    ctx.set_reg(vanguard_threaded_vm::REG_RBP, ((uint64_t)(((host_stack + sizeof(host_stack)) - 0x0000000000002000ULL))));
                                    #if defined(__x86_64__) || defined(_M_X64)
    // System V / Windows x64 ABI argument registers
    ctx.set_reg(vanguard_threaded_vm::REG_RDI, a0);
    ctx.set_reg(vanguard_threaded_vm::REG_RSI, a1);
    ctx.set_reg(vanguard_threaded_vm::REG_RDX, a2);
    ctx.set_reg(vanguard_threaded_vm::REG_RCX, a3);
    ctx.set_reg(vanguard_threaded_vm::REG_R8,  a4);
    ctx.set_reg(vanguard_threaded_vm::REG_R9,  a5);
    ctx.set_reg(vanguard_threaded_vm::REG_RAX, a0);
#elif defined(__riscv) || defined(__riscv__)
    // RISC-V LP64 ABI argument mapping (a0->RAX, a1->RDX, a2->RCX, a3->RSI, a4->RDI, a5->R8, a6->R9, a7->R12)
    ctx.set_reg(vanguard_threaded_vm::REG_RAX, a0);
    ctx.set_reg(vanguard_threaded_vm::REG_RDX, a1);
    ctx.set_reg(vanguard_threaded_vm::REG_RCX, a2);
    ctx.set_reg(vanguard_threaded_vm::REG_RSI, a3);
    ctx.set_reg(vanguard_threaded_vm::REG_RDI, a4);
    ctx.set_reg(vanguard_threaded_vm::REG_R8,  a5);
    ctx.set_reg(vanguard_threaded_vm::REG_R9,  a6);
    ctx.set_reg(vanguard_threaded_vm::REG_R12, a7);
#else
    // ARM64 calling convention mapping (x0->RAX, x1->RCX, x2->RDX, x3->RBX, x4->RSI, x5->RDI, x6->R8, x7->R9)
    ctx.set_reg(vanguard_threaded_vm::REG_RAX, a0);
    ctx.set_reg(vanguard_threaded_vm::REG_RCX, a1);
    ctx.set_reg(vanguard_threaded_vm::REG_RDX, a2);
    ctx.set_reg(vanguard_threaded_vm::REG_RBX, a3);
    ctx.set_reg(vanguard_threaded_vm::REG_RSI, a4);
    ctx.set_reg(vanguard_threaded_vm::REG_RDI, a5);
    ctx.set_reg(vanguard_threaded_vm::REG_R8,  a6);
    ctx.set_reg(vanguard_threaded_vm::REG_R9,  a7);
#endif
                                    vanguard_threaded_vm::execute_threaded(ctx, bc, len, false);
                                    uint64_t ret_val = ctx.get_rax();
                                    if (__builtin_expect(ctx.trapped || ctx.canary_head != vanguard_threaded_vm::VMContext::CANARY_VAL || ctx.canary_tail != vanguard_threaded_vm::VMContext::CANARY_VAL, 0)) {
        ret_val ^= 0xDEADBEEF5A5A5A5AULL ^ ctx.reg_mask;
    }
                                    return (((ret_val ^ 0x5877cafe1337beefULL) + (0x0000000000000002ULL * (ret_val & 0x5877cafe1337beefULL))) - 0x5877cafe1337beefULL);
                                }

} // namespace vanguard_threaded_vm


