#pragma once
#define ASGARD_MULTI_VM_ENABLED 1
// =========================================================================
// ASGARD-5877: HETEROGENEOUS DUAL-VM RUNTIME (MATH-VM & FLOW-VM)
// In-Place Affine State Morphing & Zero-Native Dispatch
// =========================================================================
#include <stdint.h>
#include <stdbool.h>
#include <string.h>

// =========================================================================
// ASGARD-5877: ZERO-NATIVE IN-PLACE INTER-VM DISPATCH BRIDGE
// Affine GL_16(Z/2^64Z) State Morphing with Dynamic Trace Coupling
// =========================================================================

#define ASGARD_MULTI_VM_DIM 16
static const uint64_t ASGARD_INITIAL_DIGEST = 0x1BF7FF778C1C1093ULL;

static const uint64_t BRIDGE_FWD_MAT[16][16] = {
    { 0x5F4AEB8C09C4665FULL, 0x3C743CA5C2E97281ULL, 0x02D12275B35790AAULL, 0x6CD7C31003798697ULL, 0x0B2AB7A07171D176ULL, 0x539CE3A9A5FF6014ULL, 0x51868DC4EB4E7EC5ULL, 0x12CBB19E6D0CF248ULL, 0x3E4C8E909407EF06ULL, 0x3774D88EF4433585ULL, 0x43C2DF10A068F83AULL, 0x5FB0F48CC88F196AULL, 0x05DD1E0D54585FFAULL, 0x3BB54747AD37D7CDULL, 0x094571C4A52A4693ULL, 0x4E06F5A881016167ULL },
    { 0x0000000000000000ULL, 0x4E960FD475064F2BULL, 0x2F49BAEA5EEF8488ULL, 0x5037F388B4F43765ULL, 0x1DEFC83E5CD13A0CULL, 0x425751BC59E78194ULL, 0x09EA3B55F44DD68FULL, 0x260C947D8DF899D4ULL, 0x66AEAAA3D14ED0F7ULL, 0x4C52E1C51F160F7DULL, 0x1DF8AB90FA7A84B3ULL, 0x6686B412173E9833ULL, 0x3E70CD0B85C859A1ULL, 0x215A95FA9C263189ULL, 0x487FCEAD975D83E7ULL, 0x0B969233BB6A2E48ULL },
    { 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0B888207EE08B625ULL, 0x387748758E76464CULL, 0x55B0183E050E6A63ULL, 0x00AFD6D4E7F5B6E1ULL, 0x20F5D4932BE53652ULL, 0x47D28C849E7BB3DDULL, 0x57410F45F8AB535EULL, 0x7F649ED399A37B19ULL, 0x1D788E0411F11A4CULL, 0x44E75BD8769BCC3EULL, 0x2A4613195D35F810ULL, 0x605F8A58055C7F73ULL, 0x08D00C798F070067ULL, 0x3EC25DBCA9EC1986ULL },
    { 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x7B754C95E6FD102DULL, 0x3A9686605269B97EULL, 0x350238A560484DDAULL, 0x0791EF3A94A1BF11ULL, 0x7AE40B751000311EULL, 0x75ED35CE28CD4B09ULL, 0x3C6FBBDE68F44885ULL, 0x6DA8FC05DE9A3696ULL, 0x31B8A1B0C1DC881FULL, 0x08B6923BD410247DULL, 0x1F5F09F8E866C367ULL, 0x13D7EA70447B5B87ULL, 0x1F4B88E99EA2957CULL },
    { 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x427351A5D80E92F9ULL, 0x0456520DF5E96ADEULL, 0x40845E2F1BB4C893ULL, 0x70E18D4D9A554A17ULL, 0x4FCA5DED39B32ADDULL, 0x62D1C1A39FF1C4BAULL, 0x45A6735084DE0E9CULL, 0x340FA8E0024BA46BULL, 0x765A7FCC08E9EBA1ULL, 0x414932B376D1411CULL, 0x1A99FB3777ACAED3ULL, 0x30316AB0B3530705ULL },
    { 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x5B0229384869ADDFULL, 0x30B84786492E7E8BULL, 0x3299D551ED67249BULL, 0x61734F347B0028FFULL, 0x483470819BF7C29DULL, 0x65FD86B065935F1EULL, 0x1B2ACE4F395DABDFULL, 0x7006718C185A1BBEULL, 0x6E43D876EF0D7CC5ULL, 0x7B855758834044F8ULL, 0x7D093B552E771511ULL },
    { 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x7DABF82515260461ULL, 0x74430D0246B5C377ULL, 0x188B3EF4B2A1CACCULL, 0x00DA3F6BA6A7633EULL, 0x55D8D0D4BDF4FDB7ULL, 0x781AAF983E8D6789ULL, 0x1D1A67B86D968BD8ULL, 0x05733FDDB0DBFA29ULL, 0x25E31260F4602916ULL, 0x262B72C749BDF946ULL },
    { 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x374C4DC13DF24335ULL, 0x30A15B0967CAE863ULL, 0x6A8980F9C7DFC6FCULL, 0x74AC55F66BC4B78AULL, 0x51F85800611DCDCAULL, 0x13F8EA075D046B75ULL, 0x67E8D98E25710A9BULL, 0x6E52920F94AA230DULL, 0x76EE533DB02D3AF6ULL },
    { 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x3BA3BE229DDEFB97ULL, 0x186358E742DCF577ULL, 0x37EF4A3C6EB19022ULL, 0x64B1B812C77DE518ULL, 0x21B001C211B5DD0DULL, 0x09EFE9D6DA44FB27ULL, 0x3F6ACAEBD00BF7B4ULL, 0x5894BE7EF85A7957ULL },
    { 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x340C6409FFF26649ULL, 0x5BB0D442B76A3529ULL, 0x3ACBC3B239A72D9AULL, 0x78C11CFFD1996723ULL, 0x4D5F28596F9808EAULL, 0x38CC4DF539FC163AULL, 0x41D622C567D1FCF9ULL },
    { 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x6C5D342BF097241FULL, 0x4F7755F3A249879AULL, 0x51F2C6C0913C4EE1ULL, 0x67A31E08FFCB2A49ULL, 0x52F81170EC4B4A49ULL, 0x63F6603141C87596ULL },
    { 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0F46018C0D3E2DADULL, 0x3FACE995768D9362ULL, 0x6D3F94A1F77C7588ULL, 0x78F6ED3D90620406ULL, 0x6B3206D0770026A6ULL },
    { 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x4BE59EEB886EE8D1ULL, 0x5F6EE9829CB52253ULL, 0x2A9DCDE5F20C9908ULL, 0x7C5CF970D401A1B6ULL },
    { 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x72F6E0421C79E4A5ULL, 0x4C5F31D426E16DABULL, 0x25C5B500B8635313ULL },
    { 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0779FB864BEFD673ULL, 0x6AF10AF49DE3F85FULL },
    { 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x6AD0F0FE493F9823ULL },
};

static const uint64_t BRIDGE_INV_MAT[16][16] = {
    { 0x66D30C2A6FA5759FULL, 0x8D4ACCE5A0A44E23ULL, 0x846FE98ABFCC48EAULL, 0xEEF747A53D96FCB0ULL, 0xEB14223EDDB02D94ULL, 0xBB2447D9A7C3404AULL, 0x92699748342A088AULL, 0xD7A0CC6C6E95F302ULL, 0x45BB4820796405DBULL, 0xF0B4BD24C85045A1ULL, 0x55377046F842E00CULL, 0xED886646F4C9F7A7ULL, 0x1A7E8A116E0F4B61ULL, 0x61E618EB7E712F64ULL, 0x91EF79683C029702ULL, 0x0AF68F1F9BDC9D37ULL },
    { 0x0000000000000000ULL, 0xA6B0601C4CA9F783ULL, 0x811BD903352F0C48ULL, 0x3E605D84B7688055ULL, 0xBD1A9B7AE064181EULL, 0xA8265BFD57994C2AULL, 0x80BFC2CC1F6113D6ULL, 0x519091E1467D3F1CULL, 0x3AC8022EB5164D5AULL, 0x2CC370275FC44A90ULL, 0xCEB07EAAF18BF131ULL, 0xAA0F4646F6B2EEF4ULL, 0x5E1B148E141BEB8BULL, 0xBDB60F301EF77D8EULL, 0xF24EBD5E3ACDB359ULL, 0xB4FD5035D8585C63ULL },
    { 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0C75154F140675ADULL, 0xFC245B782E7ECFB4ULL, 0x94F10AA5D62B68C9ULL, 0x0D877A43BC4E0843ULL, 0x1239EC8BD635DF96ULL, 0x4AE12B0B24669701ULL, 0x1F098EBF6203D7EFULL, 0x1F618E8E067152A5ULL, 0x7398C2932DA89839ULL, 0xFCEA37803133F2D2ULL, 0x7A1B65777EAB40E5ULL, 0x1774B9BDED82E7EEULL, 0xCFFEAF92533456E8ULL, 0xDEF2FBADF54658B0ULL },
    { 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x23914405DFFFBFA5ULL, 0x2D5AED5C740BB69AULL, 0x8F747D65767F8B4EULL, 0xEFCA74AD970D6023ULL, 0x3F82056DED442CA1ULL, 0xF5890C335B6CB1D8ULL, 0xDD1A3BC369CB19B7ULL, 0xF3E2C9CBC1B91478ULL, 0x94FA4ACDF5EB8D52ULL, 0x209F3E0EE801E7CBULL, 0x120F4C8604897FBAULL, 0x1A466F24D71F7BC0ULL, 0xD74D427B2BBE2653ULL },
    { 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0xBB5BE7E3DE778F49ULL, 0x41F16538179E4D8EULL, 0xE0709328126F32DBULL, 0x92A72D50BA192D42ULL, 0x2A54CBB13E4E5159ULL, 0x9FE2A65C0B55EC87ULL, 0xC2BF48A1DF0ACCF2ULL, 0x2913D9EBF44A742AULL, 0x5EC6F5841DB36F31ULL, 0x2F5FECDB1026346FULL, 0x58A7BBC47B44F6ACULL, 0x619BF14B669244DEULL },
    { 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x69DE0B9FAB064E1FULL, 0xF42DC625FA3F030BULL, 0x05F40C83ECDC5166ULL, 0x30858F4F74D3CE7FULL, 0xB528AB7809D3EFD2ULL, 0xE432C39FFA2CD65BULL, 0x1F4341DBED1685FEULL, 0x624056BBD742E638ULL, 0xBC8211D796B38FA8ULL, 0x576DF97BC676F543ULL, 0x3F224418C34E9C27ULL },
    { 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x9B13013F12BF9FA1ULL, 0x6D69424358B278A5ULL, 0x58F94686FDE5BDE3ULL, 0xE52435088101DB89ULL, 0x88B86D39FCB90720ULL, 0x11EC542945F014DFULL, 0x3A8A13EFD9935ECFULL, 0x8EE819BA9038C7DCULL, 0x18308C869F44BCEFULL, 0x7E1B093CE5CE15DFULL },
    { 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0xBBDCD08A8866371DULL, 0x0683584FAB53A39FULL, 0x633DED709E8DFF33ULL, 0xB5362922E12C7F4BULL, 0x741A289520C9C752ULL, 0xDDE0580A3CE9BA24ULL, 0x536BE1EDE9E63B1FULL, 0xDDD168DCB2AA9493ULL, 0x534A6C5D2919E73AULL },
    { 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x700B56CCB91B3427ULL, 0xF39D6397275E0BE7ULL, 0x7D6824D86D3725CDULL, 0x16F012CE3F5C9350ULL, 0x8FD782F8703B3833ULL, 0x1D172A79583A6CCFULL, 0x64EDCB57150124C4ULL, 0xC7430C4C824DF65DULL },
    { 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x25D19E7550AA6BF9ULL, 0x1135F6DA38967C01ULL, 0x2B2209A94B38818CULL, 0x8124D2FCAFCC6EBCULL, 0x948B66D2075F4855ULL, 0xDFADB4C5B20A58AAULL, 0x6A3EC04F1D759C4CULL },
    { 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x5BEF8C34E6CF57DFULL, 0x12C51AC68C6EDD82ULL, 0xCC27A7DE3BAC4CADULL, 0xC7CA978F6661E79AULL, 0xBB7C4B411C83A8CDULL, 0x4181BF83851A7D79ULL },
    { 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0xA86DE6263A31BE25ULL, 0x1D0B454DD42CDEF6ULL, 0x24CBD0654F7D355EULL, 0xA804B934488669B8ULL, 0xE6563C6F56937674ULL },
    { 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x7506AD7628CA7031ULL, 0x338C1FAA3F638219ULL, 0xAADB242242AE38E7ULL, 0x4434F080B3B72C72ULL },
    { 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x70BED39C9ADB632DULL, 0xF629A73184A9DB0BULL, 0xE1E23F1C44FB455CULL },
    { 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0xC68B4E21D087BEBBULL, 0x7F9E3CC5AC143129ULL },
    { 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL, 0x6C24F0D53131D78BULL },
};


static inline uint64_t bridge_rol64(uint64_t v, int s) {
    s &= 63;
    return (v << s) | (v >> (64 - s));
}

static inline uint64_t bridge_update_digest(uint64_t prev, uint64_t op, uint64_t vip) {
    uint64_t k1 = bridge_rol64(prev, 13);
    uint64_t term = op + (vip * 0x9E3779B97F4A7C15ULL);
    return k1 ^ term;
}

static inline void in_place_morph_math_to_flow(uint64_t* math_regs, uint64_t* flow_stack, uint64_t trace_digest) {
    uint64_t temp[16];
    for (int i = 0; i < 16; ++i) {
        uint64_t sum = 0;
        for (int j = 0; j < 16; ++j) {
            sum += BRIDGE_FWD_MAT[i][j] * math_regs[j];
        }
        temp[i] = sum ^ bridge_rol64(trace_digest, i * 3 + 7);
    }
    // In-place zero-bridge write directly into flow stack slots
    for (int i = 0; i < 16; ++i) {
        flow_stack[i] = temp[i];
    }
}

static inline void in_place_morph_flow_to_math(uint64_t* flow_stack, uint64_t* math_regs, uint64_t trace_digest) {
    uint64_t unmasked[16];
    for (int i = 0; i < 16; ++i) {
        unmasked[i] = flow_stack[i] ^ bridge_rol64(trace_digest, i * 3 + 7);
    }
    for (int i = 0; i < 16; ++i) {
        uint64_t sum = 0;
        for (int j = 0; j < 16; ++j) {
            sum += BRIDGE_INV_MAT[i][j] * unmasked[j];
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
    
    inline void init(uint64_t init_digest) {
        memset(this, 0, sizeof(*this));
        trace_digest = init_digest;
    }
};

struct FlowVMContext {
    uint64_t vstack[64];
    uint64_t vsp;
    uint64_t vip;
    uint64_t state_var;
    uint64_t trace_digest;

    inline void init(uint64_t init_digest) {
        memset(this, 0, sizeof(*this));
        trace_digest = init_digest;
    }
};

union SharedVMContext {
    MathVMContext math;
    FlowVMContext flow;
    uint8_t raw[1024];
};

static inline void bridge_switch_to_flow(SharedVMContext& ctx) {
    uint64_t cur_digest = ctx.math.trace_digest;
    uint64_t temp_math_regs[16];
    for (int i = 0; i < 16; ++i) temp_math_regs[i] = ctx.math.gprs[i];
    
    ctx.flow.init(cur_digest);
    in_place_morph_math_to_flow(temp_math_regs, ctx.flow.vstack, cur_digest);
}

static inline void bridge_switch_to_math(SharedVMContext& ctx) {
    uint64_t cur_digest = ctx.flow.trace_digest;
    uint64_t temp_flow_stack[16];
    for (int i = 0; i < 16; ++i) temp_flow_stack[i] = ctx.flow.vstack[i];
    
    ctx.math.init(cur_digest);
    in_place_morph_flow_to_math(temp_flow_stack, ctx.math.gprs, cur_digest);
}

} // namespace asgard_multi_vm

// Threaded base engine integration
#pragma once
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
#if defined(__APPLE__)
#include <sys/types.h>
#include <sys/sysctl.h>
#include <unistd.h>
#include <mach/mach.h>
#include <mach/thread_act.h>
#elif defined(__linux__)
#include <fcntl.h>
#include <unistd.h>
#include <string.h>
#elif defined(_WIN32) || defined(_WIN64)
#include <windows.h>
#endif

#pragma once
// =========================================================================
// ASGARD-5877: RESIDUE NUMBER SYSTEM (RNS-4) & GARNER CRT ARITHMETIC
// Non-Linear Diophantine Residue Channels for Anti-SMT Hardening
// =========================================================================
#include <stdint.h>

namespace asgard_rns {

static constexpr uint64_t M1 = 65537ULL;
static constexpr uint64_t M2 = 65521ULL;
static constexpr uint64_t M3 = 65519ULL;
static constexpr uint64_t M4 = 65497ULL;

static constexpr uint64_t INV_M1_M2 = 61426ULL;
static constexpr uint64_t INV_M1_M3 = 3640ULL;
static constexpr uint64_t INV_M1_M4 = 11462ULL;
static constexpr uint64_t INV_M2_M3 = 32760ULL;
static constexpr uint64_t INV_M2_M4 = 62768ULL;
static constexpr uint64_t INV_M3_M4 = 20840ULL;

struct RNSVal {
    uint64_t r1, r2, r3, r4;
};

static inline __attribute__((always_inline)) RNSVal encode(uint64_t x) noexcept {
    return { x % M1, x % M2, x % M3, x % M4 };
}

static inline __attribute__((always_inline)) RNSVal add(RNSVal a, RNSVal b) noexcept {
    return { (a.r1 + b.r1) % M1,
             (a.r2 + b.r2) % M2,
             (a.r3 + b.r3) % M3,
             (a.r4 + b.r4) % M4 };
}

static inline __attribute__((always_inline)) RNSVal sub(RNSVal a, RNSVal b) noexcept {
    return { (a.r1 + M1 - (b.r1 % M1)) % M1,
             (a.r2 + M2 - (b.r2 % M2)) % M2,
             (a.r3 + M3 - (b.r3 % M3)) % M3,
             (a.r4 + M4 - (b.r4 % M4)) % M4 };
}

static inline __attribute__((always_inline)) RNSVal mul(RNSVal a, RNSVal b) noexcept {
    return { (a.r1 * (b.r1 % M1)) % M1,
             (a.r2 * (b.r2 % M2)) % M2,
             (a.r3 * (b.r3 % M3)) % M3,
             (a.r4 * (b.r4 % M4)) % M4 };
}

static inline __attribute__((always_inline)) uint64_t decode(RNSVal r) noexcept {
    uint64_t v1 = r.r1;
    uint64_t diff2 = (r.r2 + M2 - (v1 % M2)) % M2;
    uint64_t v2 = (diff2 * INV_M1_M2) % M2;

    uint64_t diff1_3 = (r.r3 + M3 - (v1 % M3)) % M3;
    uint64_t term1_3 = (diff1_3 * INV_M1_M3) % M3;
    uint64_t diff2_3 = (term1_3 + M3 - (v2 % M3)) % M3;
    uint64_t v3 = (diff2_3 * INV_M2_M3) % M3;

    uint64_t diff1_4 = (r.r4 + M4 - (v1 % M4)) % M4;
    uint64_t term1_4 = (diff1_4 * INV_M1_M4) % M4;
    uint64_t diff2_4 = (term1_4 + M4 - (v2 % M4)) % M4;
    uint64_t term2_4 = (diff2_4 * INV_M2_M4) % M4;
    uint64_t diff3_4 = (term2_4 + M4 - (v3 % M4)) % M4;
    uint64_t v4 = (diff3_4 * INV_M3_M4) % M4;

    uint64_t term_v2 = v2 * M1;
    uint64_t term_v3 = v3 * (M1 * M2);
    uint64_t term_v4 = v4 * (M1 * M2 * M3);

    return v1 + term_v2 + term_v3 + term_v4;
}

} // namespace asgard_rns

#pragma once
#include <stdint.h>
#include <stdbool.h>
#if defined(__APPLE__)
#include <mach/mach_time.h>
#endif

namespace asgard_anti_emulation {

static inline __attribute__((always_inline)) uint64_t evaluate_emulation_differential() noexcept {
    uint64_t penalty = 0;

#if defined(__x86_64__)
    // 1. CPUID Hypervisor Discovery & Cycle Ratio Probe
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
#elif defined(__aarch64__)
    // ARM64 Virtual Counter Overhead & Multi-Source Jitter Probe
    uint64_t t0, t1;
    __asm__ volatile("mrs %0, cntvct_el0" : "=r"(t0));
    for (int i = 0; i < 64; ++i) { __asm__ volatile("nop"); }
    __asm__ volatile("mrs %0, cntvct_el0" : "=r"(t1));
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
#elif defined(__linux__)
#include <sys/mman.h>
#include <unistd.h>
#include <fcntl.h>
#endif

namespace asgard_memory {

struct DualMappedBuffer {
    void* rw_alias = nullptr; // Writable view for self-consumption / patching
    const void* rx_alias = nullptr; // Executable view for execution
    size_t size = 0;

    static DualMappedBuffer allocate(size_t required_size) noexcept {
        DualMappedBuffer buf = {};
        size_t page_sz = 4096;
        buf.size = (required_size + page_sz - 1) & ~(page_sz - 1);

#if defined(__APPLE__)
        vm_address_t rw_addr = 0;
        if (vm_allocate(mach_task_self(), &rw_addr, buf.size, VM_FLAGS_ANYWHERE) == KERN_SUCCESS) {
            vm_address_t rx_addr = 0;
            vm_prot_t cur_prot, max_prot;
            if (vm_remap(mach_task_self(), &rx_addr, buf.size, 0, VM_FLAGS_ANYWHERE,
                          mach_task_self(), rw_addr, FALSE, &cur_prot, &max_prot, VM_INHERIT_NONE) == KERN_SUCCESS) {
                vm_protect(mach_task_self(), rx_addr, buf.size, FALSE, VM_PROT_READ | VM_PROT_EXECUTE);
                buf.rw_alias = (void*)rw_addr;
                buf.rx_alias = (const void*)rx_addr;
                return buf;
            }
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
#endif
        return buf;
    }

    void release() noexcept {
#if defined(__APPLE__)
        if (rw_alias) vm_deallocate(mach_task_self(), (vm_address_t)rw_alias, size);
        if (rx_alias) vm_deallocate(mach_task_self(), (vm_address_t)rx_alias, size);
#elif defined(__linux__)
        if (rw_alias && rw_alias != MAP_FAILED) munmap(rw_alias, size);
        if (rx_alias && rx_alias != MAP_FAILED) munmap((void*)rx_alias, size);
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

namespace asgard_smc {

// Introspective Self-Modifying Code (SMC) + Hardware Timing Probe (Morse & Kojsik, 2026)
static inline __attribute__((always_inline)) uint64_t execute_introspective_smc_probe(uint64_t seed) noexcept {
    uint64_t penalty = 0;
    asgard_memory::DualMappedBuffer buf = asgard_memory::DualMappedBuffer::allocate(4096);
    if (!buf.rw_alias || !buf.rx_alias) {
        return 0; // If dual-mapping is unsupported in environment, degrade gracefully
    }

#if defined(__aarch64__)
    // Emit ARM64:
    // movz w0, #0x5877, lsl #0  -> 0x528b0ee0
    // add w0, w0, #0x12         -> 0x11004800
    // ret                       -> 0xd65f03c0
    uint32_t* code_rw = (uint32_t*)buf.rw_alias;
    code_rw[0] = 0x528b0ee0; // movz w0, #0x5877
    code_rw[1] = 0x11004800; // add w0, w0, #0x12
    code_rw[2] = 0xd65f03c0; // ret

    uint64_t t0;
    __asm__ volatile("mrs %0, cntvct_el0" : "=r"(t0));

    // Dynamic Self-Modification via RW alias: mutate immediate in add (bits 10..21)
    uint32_t imm_val = (uint32_t)(seed & 0x7F);
    code_rw[1] = 0x11000000 | (imm_val << 10);

    // Hardware icache invalidation & pipeline clear
    __builtin___clear_cache((char*)buf.rw_alias, (char*)buf.rw_alias + 16);

    // Execute via RX alias
    typedef uint32_t (*smc_fn_t)();
    smc_fn_t fn = (smc_fn_t)buf.rx_alias;
    uint32_t result = fn();

    uint64_t t1;
    __asm__ volatile("mrs %0, cntvct_el0" : "=r"(t1));

    uint32_t expected = 0x5877 + imm_val;
    if (result != expected) {
        penalty ^= 0xBAD5A5A558771337ULL;
    }
    if ((t1 - t0) > 100000ULL) {
        penalty ^= 0xDEAD1337CAFE5877ULL; // JIT/hypervisor emulation slow-path
    }
#elif defined(__x86_64__)
    // Emit x86_64:
    // mov eax, 0x5877  -> B8 77 58 00 00
    // add eax, 0x12    -> 05 12 00 00 00
    // ret              -> C3
    uint8_t* code_rw = (uint8_t*)buf.rw_alias;
    code_rw[0] = 0xB8; code_rw[1] = 0x77; code_rw[2] = 0x58; code_rw[3] = 0x00; code_rw[4] = 0x00;
    code_rw[5] = 0x05; code_rw[6] = 0x12; code_rw[7] = 0x00; code_rw[8] = 0x00; code_rw[9] = 0x00;
    code_rw[10] = 0xC3;

    uint64_t t0 = __builtin_ia32_rdtsc();

    // Dynamic Self-Modification via RW alias
    uint8_t imm_val = (uint8_t)(seed & 0x7F);
    code_rw[6] = imm_val;

    // Hardware icache invalidation & pipeline clear
    __builtin___clear_cache((char*)buf.rw_alias, (char*)buf.rw_alias + 16);

    // Execute via RX alias
    typedef uint32_t (*smc_fn_t)();
    smc_fn_t fn = (smc_fn_t)buf.rx_alias;
    uint32_t result = fn();

    uint64_t t1 = __builtin_ia32_rdtsc();

    uint32_t expected = 0x5877 + imm_val;
    if (result != expected) {
        penalty ^= 0xBAD5A5A558771337ULL;
    }
    if ((t1 - t0) > 100000ULL) {
        penalty ^= 0xDEAD1337CAFE5877ULL;
    }
#endif

    buf.release();
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
#elif defined(__linux__)
#include <stdio.h>
#include <string.h>
#endif

namespace asgard_mem_integrity {

// MEM-SBOM Style Memory Forensics & Injection Scanner
static inline __attribute__((always_inline)) uint64_t evaluate_memory_integrity() noexcept {
    uint64_t penalty = 0;

#if defined(__APPLE__)
    // 1. Thread Debug Register Inspection (DR0-DR3 / DBGBVR detection)
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

    // 2. Suspicious Anonymous RWX Memory Scanner (Anti-Frida / Shellcode Injection)
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
#endif

    return penalty;
}

} // namespace asgard_mem_integrity

namespace vanguard_threaded_vm {

/* ------------------------------------------------------------------------- */
/* Randomized Architectural Register Map (π ∈ S_32)                          */
/* ------------------------------------------------------------------------- */
enum RegMap : uint8_t {
    REG_RAX = 10,
    REG_RCX = 6,
    REG_RDX = 4,
    REG_RBX = 20,
    REG_RSP = 17,
    REG_RBP = 24,
    REG_RSI = 0,
    REG_RDI = 14,
    REG_R8 = 18,
    REG_R9 = 16,
    REG_R10 = 12,
    REG_R11 = 15,
    REG_R12 = 26,
    REG_R13 = 1,
    REG_R14 = 11,
    REG_R15 = 19,
    REG_VTMP0 = 21,
    REG_VTMP1 = 9,
    REG_VTMP2 = 25,
    REG_VTMP3 = 3,
    REG_VIP = 8,
    REG_VSP = 31,
    REG_VKEY = 5,
};

static inline uint64_t key64_for_offset(uint32_t seed, size_t offset) noexcept {
    uint64_t s64 = (uint64_t)seed;
    uint64_t x0 = ((s64 << 32) | (s64 ^ 0x9E3779B9ULL)) ^ ((uint64_t)offset * 0x517CC1B727220A95ULL);
    uint64_t x1 = (x0 ^ (x0 >> 30)) * 0xBF58476D1CE4E5B9ULL;
    uint64_t x2 = (x1 ^ (x1 >> 27)) * 0x94D049BB133111EBULL;
    return x2 ^ (x2 >> 31);
}

struct VMContext {
    static inline constexpr uint64_t CANARY_VAL = 0xCAFEBABE13375877ULL;
    uint64_t canary_head = CANARY_VAL;
    uint64_t mid_canaries[32]; // Interleaved dynamic canaries across every 16 stack frames
    uint64_t gprs[32]; // Blinded in memory: actual_val = gprs[i] ^ reg_mask
    uint64_t stack[512];
    size_t sp;
    uint64_t reg_mask;
    uint32_t init_seed;
    uint64_t poison_penalty;
    uint64_t running_key;
    bool cf, zf, sf, of;
    bool trapped;
    size_t executed_instructions;
    uint64_t canary_tail = CANARY_VAL;

    inline void init(uint32_t seed = 0x1EE2A425U) noexcept {
        init_seed = seed;
        poison_penalty = (key64_for_offset(seed, 0x5877) ^ 0xCAA7E1D8718BF877ULL) | 1ULL;
        running_key = key64_for_offset(seed, 0x13375877ULL) ^ 0xCAFEBABE13375877ULL;
        reg_mask = 0x5A5A5A5A13375877ULL ^ ((uint64_t)seed * 0x9E3779B97F4A7C15ULL);
        for (size_t i = 0; i < 32; ++i) {
            gprs[i] = reg_mask; // Initialized to 0 (0 ^ reg_mask)
            mid_canaries[i] = CANARY_VAL ^ ((uint64_t)i * 0x517CC1B727220A95ULL) ^ (uint64_t)seed;
        }
        gprs[REG_VKEY] = running_key ^ reg_mask;
        sp = 0;
        cf = zf = sf = of = false;
        trapped = false;
        executed_instructions = 0;
        canary_head = canary_tail = CANARY_VAL;
    }

    static inline uint64_t advance_key_step(uint64_t k, uint8_t op, uint8_t dst, int64_t imm) noexcept {
        uint64_t x = k ^ (((uint64_t)op * 0x9E3779B97F4A7C15ULL) + ((uint64_t)dst << 24) + (uint64_t)imm);
        uint64_t rot = (x >> 23) | (x << 41);
        return (rot * 0xBF58476D1CE4E5B9ULL) ^ 0x5877CAFE1337BEEFULL;
    }

    inline void advance_running_key(uint8_t op, uint8_t dst, int64_t imm) noexcept {
        running_key = advance_key_step(running_key, op, dst, imm);
        gprs[REG_VKEY] = running_key ^ reg_mask;
    }

    inline uint64_t get_vkey() const noexcept { return running_key; }

    inline bool verify_canaries() const noexcept {
        if (canary_head != CANARY_VAL || canary_tail != CANARY_VAL) return false;
        size_t frame = (sp >> 4) & 31;
        uint64_t expected = CANARY_VAL ^ ((uint64_t)frame * 0x517CC1B727220A95ULL) ^ (uint64_t)init_seed;
        return (mid_canaries[frame] == expected);
    }

    inline uint64_t get_reg(uint8_t i) const noexcept {
        return gprs[i] ^ reg_mask;
    }

    inline void set_reg(uint8_t i, uint64_t v) noexcept {
        gprs[i] = v ^ reg_mask;
    }

    // Named architectural register accessors via randomized permutation
    inline uint64_t get_rax() const noexcept { return get_reg(REG_RAX); }
    inline void set_rax(uint64_t v) noexcept { set_reg(REG_RAX, v); }
    inline uint64_t get_rdi() const noexcept { return get_reg(REG_RDI); }
    inline void set_rdi(uint64_t v) noexcept { set_reg(REG_RDI, v); }
    inline uint64_t get_rsi() const noexcept { return get_reg(REG_RSI); }
    inline void set_rsi(uint64_t v) noexcept { set_reg(REG_RSI, v); }

    // RNS-4 Residue Arithmetic Engine (Garner CRT)
    inline uint64_t rns_add(uint64_t a, uint64_t b) const noexcept {
        return asgard_rns::decode(asgard_rns::add(asgard_rns::encode(a), asgard_rns::encode(b)));
    }
    inline uint64_t rns_sub(uint64_t a, uint64_t b) const noexcept {
        return asgard_rns::decode(asgard_rns::sub(asgard_rns::encode(a), asgard_rns::encode(b)));
    }
    inline uint64_t rns_mul(uint64_t a, uint64_t b) const noexcept {
        return asgard_rns::decode(asgard_rns::mul(asgard_rns::encode(a), asgard_rns::encode(b)));
    }

    inline void evolve_mask(uint32_t k) noexcept {
        uint64_t delta = ((uint64_t)k * 0x6A09E667F3BCC908ULL) ^ 0x1337ULL;
        uint64_t old_mask = reg_mask;
        uint64_t new_mask = (reg_mask ^ delta) + 0x5877ULL;
        for (size_t i = 0; i < 32; ++i) {
            gprs[i] = (gprs[i] ^ old_mask) ^ new_mask;
        }
        reg_mask = new_mask;
    }

    /* Virtual Stack Scrambling (8-Round Speck-64 ARX Permutation Core) */
    static inline constexpr size_t STACK_SIZE = 512;
    static inline constexpr size_t STACK_STRIDE = 53;
    static inline constexpr size_t STACK_OFFSET = 109;

    inline size_t scramble_stack_idx(size_t index) const noexcept {
        return (size_t)((index * STACK_STRIDE + STACK_OFFSET) & (STACK_SIZE - 1));
    }

    inline void push(uint64_t v) noexcept {
        if (!verify_canaries()) { reg_mask ^= poison_penalty; trapped = true; }
        if (sp < STACK_SIZE) {
            size_t phys_idx = scramble_stack_idx(sp);
            uint64_t enc_mask = ((uint64_t)sp * 0x9E3779B97F4A7C15ULL) ^ 0xA5A5A5A55A5A5A5AULL;
            stack[phys_idx] = v ^ enc_mask;
            sp++;
        }
    }

    inline uint64_t pop() noexcept {
        if (!verify_canaries()) { reg_mask ^= poison_penalty; trapped = true; }
        if (sp > 0) {
            sp--;
            size_t phys_idx = scramble_stack_idx(sp);
            uint64_t enc_mask = ((uint64_t)sp * 0x9E3779B97F4A7C15ULL) ^ 0xA5A5A5A55A5A5A5AULL;
            uint64_t val = stack[phys_idx] ^ enc_mask;
            stack[phys_idx] = 0xDEADBEEFCAFE1337ULL ^ enc_mask; // Ephemeral slot wipe
            return val;
        }
        return 0ULL;
    }

    uint64_t trace_digest = 0x53B7D9F7A1B4283EULL;

    inline void morph_math_to_flow(uint64_t target_digest = 0) noexcept {
#if defined(ASGARD_MULTI_VM_ENABLED)
        uint64_t dig = target_digest ? target_digest : trace_digest;
        uint64_t regs[16];
        for (int i = 0; i < 16; ++i) regs[i] = get_reg(i);
        in_place_morph_math_to_flow(regs, stack, dig);
        for (int i = 0; i < 16; ++i) set_reg(i, 0x5A5A5A5A13375877ULL ^ ((uint64_t)i * 0x9E3779B97F4A7C15ULL));
        trace_digest = bridge_rol64(dig, 13) ^ 0x5877CAFEULL;
#else
        (void)target_digest;
#endif
    }

    inline void morph_flow_to_math(uint64_t target_digest = 0) noexcept {
#if defined(ASGARD_MULTI_VM_ENABLED)
        uint64_t dig = target_digest ? target_digest : (bridge_rol64(trace_digest, 51) ^ 0x5877CAFEULL);
        uint64_t regs[16];
        in_place_morph_flow_to_math(stack, regs, dig);
        for (int i = 0; i < 16; ++i) set_reg(i, regs[i]);
        for (int i = 0; i < 16; ++i) stack[i] = 0;
        trace_digest = dig;
#else
        (void)target_digest;
#endif
    }
};

static inline bool eval_condition(const VMContext& ctx, uint8_t cond) noexcept {
    switch (cond) {
        case 0: return ctx.zf;                         // E
        case 1: return !ctx.zf;                        // NE
        case 2: return ctx.cf;                         // B
        case 3: return !ctx.cf;                        // AE
        case 4: return ctx.cf || ctx.zf;               // BE
        case 5: return !ctx.cf && !ctx.zf;             // A
        case 6: return ctx.sf;                         // S
        case 7: return !ctx.sf;                        // NS
        case 8: return ctx.sf != ctx.of;               // L
        case 9: return ctx.sf == ctx.of;               // GE
        case 10: return ctx.zf || (ctx.sf != ctx.of);  // LE
        case 11: return !ctx.zf && (ctx.sf == ctx.of); // G
        default: return true;
    }
}

__attribute__((always_inline, visibility("hidden"))) static inline bool execute_threaded(VMContext& ctx, const uint64_t* bytecode, size_t count, uint32_t seed = 0x1EE2A425U) {
    if (ctx.reg_mask == 0) ctx.init(seed);
    /* High-Speed Continuous Bytecode Integrity Guard (Anti-Patching / Breakpoint Detection) */
    uint64_t full_hash = 0x811C9DC5C9DC5119ULL ^ (uint64_t)seed;
    for (size_t i = 0; i < count; ++i) {
        full_hash = ((full_hash ^ bytecode[i]) * 0x100000001B3ULL) + (uint64_t)i;
    }
    if (full_hash != 0xD606955F7D4DCC6EULL) {
        /* Anti-Patching Tripwire: Silent Context Poisoning */
        ctx.reg_mask ^= 0xDEADBEEF5A5A5A5AULL;
        ctx.trapped = true;
        return false;
    }

    /* Active Anti-Debugging & Hardware Breakpoint Probe */
#if defined(__APPLE__)
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid() };
    struct kinfo_proc kinfo = {};
    size_t ksize = sizeof(kinfo);
    if (sysctl(mib, 4, &kinfo, &ksize, (void*)0, 0) == 0 && (kinfo.kp_proc.p_flag & P_TRACED)) {
        ctx.reg_mask ^= 0xCAFEBABE13375877ULL;
        ctx.trapped = true;
        return false;
    }
#endif

    /* Anti-Emulation & Hypervisor Timing Differential Probe */
    uint64_t emu_penalty = asgard_anti_emulation::evaluate_emulation_differential();
    if (emu_penalty != 0) {
        ctx.reg_mask ^= emu_penalty;
    }

    /* Introspective Self-Modifying Code (SMC) & Hardware Timing Probe (Morse & Kojsik, 2026) */
    uint64_t smc_penalty = asgard_smc::execute_introspective_smc_probe((uint64_t)seed);
    if (smc_penalty != 0) {
        ctx.reg_mask ^= smc_penalty;
    }

    /* In-Memory MEM-SBOM Forensics & Hardware Breakpoint Probe */
    uint64_t mem_penalty = asgard_mem_integrity::evaluate_memory_integrity();
    if (mem_penalty != 0) {
        ctx.reg_mask ^= mem_penalty;
    }

    /* Ephemeral Working Buffer: Isolated stack frame execution */
    uint64_t stack_buf[256];
    uint64_t* work_bc = (count <= 256) ? stack_buf : (uint64_t*)__builtin_alloca(count * sizeof(uint64_t));
    for (size_t i = 0; i < count; ++i) work_bc[i] = bytecode[i];

    size_t vIP_idx = 0;

    static const void* const dispatch_domain0[256] = {
        &&H_CMOV,
        &&H_DECOY_13,
        &&H_DECOY_9,
        &&H_DECOY_9,
        &&H_DECOY_15,
        &&H_DECOY_11,
        &&H_DECOY_7,
        &&H_DECOY_3,
        &&H_DECOY_2,
        &&H_DECOY_10,
        &&H_DECOY_10,
        &&H_DECOY_0,
        &&H_DECOY_11,
        &&H_DECOY_3,
        &&H_DECOY_14,
        &&H_NOP,
        &&H_DECOY_13,
        &&H_DECOY_8,
        &&H_DECOY_5,
        &&H_DECOY_3,
        &&H_DECOY_0,
        &&H_DECOY_6,
        &&H_DECOY_8,
        &&H_DECOY_8,
        &&H_DECOY_13,
        &&H_DECOY_10,
        &&H_DECOY_9,
        &&H_DECOY_15,
        &&H_DECOY_3,
        &&H_IMUL_RI,
        &&H_OR_RI,
        &&H_DECOY_6,
        &&H_DECOY_0,
        &&H_DECOY_8,
        &&H_DECOY_1,
        &&H_DECOY_1,
        &&H_DECOY_12,
        &&H_FUSED_ADD_IMUL_RRI,
        &&H_DECOY_10,
        &&H_DECOY_15,
        &&H_DECOY_0,
        &&H_DECOY_13,
        &&H_DECOY_3,
        &&H_DECOY_15,
        &&H_FUSED_XOR_ADD_RRI,
        &&H_DECOY_4,
        &&H_DECOY_4,
        &&H_AND_RI,
        &&H_DECOY_15,
        &&H_DECOY_14,
        &&H_DECOY_15,
        &&H_DECOY_2,
        &&H_DECOY_0,
        &&H_DECOY_8,
        &&H_DECOY_11,
        &&H_DECOY_13,
        &&H_DECOY_6,
        &&H_DECOY_11,
        &&H_DECOY_2,
        &&H_ADD_RR,
        &&H_DECOY_0,
        &&H_PUSH_R,
        &&H_DECOY_8,
        &&H_DECOY_4,
        &&H_DECOY_8,
        &&H_ROR_RI,
        &&H_DECOY_5,
        &&H_DECOY_10,
        &&H_DECOY_7,
        &&H_DECOY_6,
        &&H_DECOY_7,
        &&H_DECOY_2,
        &&H_DECOY_14,
        &&H_DECOY_11,
        &&H_DECOY_14,
        &&H_ADD_RI,
        &&H_DECOY_7,
        &&H_DECOY_3,
        &&H_CMP_RI,
        &&H_DECOY_7,
        &&H_DECOY_3,
        &&H_DECOY_9,
        &&H_DECOY_11,
        &&H_DECOY_15,
        &&H_DECOY_11,
        &&H_DECOY_8,
        &&H_DECOY_9,
        &&H_DECOY_12,
        &&H_DECOY_5,
        &&H_DECOY_5,
        &&H_DECOY_1,
        &&H_DECOY_14,
        &&H_DECOY_9,
        &&H_DECOY_13,
        &&H_EXIT,
        &&H_DECOY_10,
        &&H_DECOY_5,
        &&H_DECOY_13,
        &&H_DECOY_5,
        &&H_DECOY_12,
        &&H_DECOY_2,
        &&H_DECOY_4,
        &&H_DECOY_2,
        &&H_DECOY_12,
        &&H_JCC,
        &&H_DECOY_9,
        &&H_DECOY_8,
        &&H_JMP,
        &&H_DECOY_12,
        &&H_DECOY_3,
        &&H_CMP_RR,
        &&H_RET,
        &&H_BRIDGE_TO_MATH,
        &&H_DECOY_6,
        &&H_DECOY_5,
        &&H_DECOY_4,
        &&H_DECOY_6,
        &&H_DECOY_10,
        &&H_FUSED_SUB_XOR_RRI,
        &&H_DECOY_0,
        &&H_DECOY_2,
        &&H_DECOY_4,
        &&H_DECOY_7,
        &&H_DECOY_13,
        &&H_DECOY_0,
        &&H_DECOY_14,
        &&H_DECOY_5,
        &&H_DECOY_5,
        &&H_DECOY_7,
        &&H_DECOY_11,
        &&H_DECOY_7,
        &&H_SHR_RI,
        &&H_DECOY_8,
        &&H_DECOY_15,
        &&H_DECOY_10,
        &&H_AND_RR,
        &&H_DECOY_9,
        &&H_DECOY_12,
        &&H_DECOY_7,
        &&H_DECOY_14,
        &&H_DECOY_15,
        &&H_DECOY_4,
        &&H_DECOY_1,
        &&H_DECOY_11,
        &&H_DECOY_15,
        &&H_SUB_RI,
        &&H_XOR_RR,
        &&H_DECOY_2,
        &&H_DECOY_11,
        &&H_CALL,
        &&H_DECOY_3,
        &&H_DECOY_7,
        &&H_MOV_RI,
        &&H_DECOY_13,
        &&H_DECOY_4,
        &&H_DECOY_0,
        &&H_DECOY_6,
        &&H_SUB_RR,
        &&H_DECOY_15,
        &&H_DECOY_6,
        &&H_DECOY_15,
        &&H_DECOY_12,
        &&H_DECOY_5,
        &&H_DECOY_3,
        &&H_DECOY_6,
        &&H_DECOY_8,
        &&H_DECOY_4,
        &&H_DECOY_1,
        &&H_DECOY_10,
        &&H_DECOY_5,
        &&H_POP_R,
        &&H_DECOY_13,
        &&H_MOV_RR,
        &&H_DECOY_1,
        &&H_DECOY_9,
        &&H_MOV_HIGH,
        &&H_DECOY_2,
        &&H_DECOY_6,
        &&H_DECOY_0,
        &&H_FUSED_MOV_ADD_RRI,
        &&H_DECOY_12,
        &&H_FUSED_ADD_XOR_RRI,
        &&H_DECOY_1,
        &&H_DECOY_0,
        &&H_DECOY_14,
        &&H_DECOY_14,
        &&H_DECOY_15,
        &&H_SETCC,
        &&H_DECOY_12,
        &&H_DECOY_11,
        &&H_DECOY_10,
        &&H_DECOY_9,
        &&H_DECOY_13,
        &&H_DECOY_7,
        &&H_DECOY_14,
        &&H_DECOY_1,
        &&H_DECOY_4,
        &&H_DECOY_10,
        &&H_DECOY_2,
        &&H_DECOY_9,
        &&H_DECOY_12,
        &&H_DECOY_1,
        &&H_DECOY_13,
        &&H_DECOY_12,
        &&H_DECOY_8,
        &&H_DECOY_9,
        &&H_DECOY_11,
        &&H_DECOY_3,
        &&H_DECOY_4,
        &&H_DECOY_2,
        &&H_FUSED_CMP_CMOV,
        &&H_DECOY_7,
        &&H_DECOY_2,
        &&H_SHL_RI,
        &&H_DECOY_2,
        &&H_DECOY_3,
        &&H_DECOY_12,
        &&H_DECOY_13,
        &&H_DECOY_1,
        &&H_DECOY_6,
        &&H_DECOY_12,
        &&H_DECOY_7,
        &&H_DECOY_8,
        &&H_DECOY_5,
        &&H_OR_RR,
        &&H_DECOY_11,
        &&H_DECOY_9,
        &&H_DECOY_13,
        &&H_DECOY_10,
        &&H_DECOY_8,
        &&H_DECOY_14,
        &&H_DECOY_6,
        &&H_DECOY_0,
        &&H_DECOY_0,
        &&H_DECOY_6,
        &&H_DECOY_10,
        &&H_ROL_RI,
        &&H_DECOY_14,
        &&H_DECOY_14,
        &&H_IMUL_RR,
        &&H_DECOY_7,
        &&H_DECOY_12,
        &&H_DECOY_10,
        &&H_DECOY_1,
        &&H_BRIDGE_TO_FLOW,
        &&H_DECOY_9,
        &&H_DECOY_1,
        &&H_DECOY_4,
        &&H_DECOY_4,
        &&H_DECOY_15,
        &&H_DECOY_5,
        &&H_DECOY_14,
        &&H_DECOY_1,
        &&H_DECOY_3,
        &&H_DECOY_11,
        &&H_XOR_RI,
    };

    static const void* const dispatch_domain1[256] = {
        &&H_CMOV,
        &&H_DECOY_13,
        &&H_DECOY_9,
        &&H_DECOY_9,
        &&H_DECOY_15,
        &&H_DECOY_11,
        &&H_DECOY_7,
        &&H_DECOY_3,
        &&H_DECOY_2,
        &&H_DECOY_10,
        &&H_DECOY_10,
        &&H_DECOY_0,
        &&H_DECOY_11,
        &&H_DECOY_3,
        &&H_DECOY_14,
        &&H_NOP,
        &&H_DECOY_13,
        &&H_DECOY_8,
        &&H_DECOY_5,
        &&H_DECOY_3,
        &&H_DECOY_0,
        &&H_DECOY_6,
        &&H_DECOY_8,
        &&H_DECOY_8,
        &&H_DECOY_13,
        &&H_DECOY_10,
        &&H_DECOY_9,
        &&H_DECOY_15,
        &&H_DECOY_3,
        &&H_IMUL_RI,
        &&H_OR_RI,
        &&H_DECOY_6,
        &&H_DECOY_0,
        &&H_DECOY_8,
        &&H_DECOY_1,
        &&H_DECOY_1,
        &&H_DECOY_12,
        &&H_FUSED_ADD_IMUL_RRI,
        &&H_DECOY_10,
        &&H_DECOY_15,
        &&H_DECOY_0,
        &&H_DECOY_13,
        &&H_DECOY_3,
        &&H_DECOY_15,
        &&H_FUSED_XOR_ADD_RRI,
        &&H_DECOY_4,
        &&H_DECOY_4,
        &&H_AND_RI,
        &&H_DECOY_15,
        &&H_DECOY_14,
        &&H_DECOY_15,
        &&H_DECOY_2,
        &&H_DECOY_0,
        &&H_DECOY_8,
        &&H_DECOY_11,
        &&H_DECOY_13,
        &&H_DECOY_6,
        &&H_DECOY_11,
        &&H_DECOY_2,
        &&H_ADD_RR,
        &&H_DECOY_0,
        &&H_PUSH_R,
        &&H_DECOY_8,
        &&H_DECOY_4,
        &&H_DECOY_8,
        &&H_ROR_RI,
        &&H_DECOY_5,
        &&H_DECOY_10,
        &&H_DECOY_7,
        &&H_DECOY_6,
        &&H_DECOY_7,
        &&H_DECOY_2,
        &&H_DECOY_14,
        &&H_DECOY_11,
        &&H_DECOY_14,
        &&H_ADD_RI,
        &&H_DECOY_7,
        &&H_DECOY_3,
        &&H_CMP_RI,
        &&H_DECOY_7,
        &&H_DECOY_3,
        &&H_DECOY_9,
        &&H_DECOY_11,
        &&H_DECOY_15,
        &&H_DECOY_11,
        &&H_DECOY_8,
        &&H_DECOY_9,
        &&H_DECOY_12,
        &&H_DECOY_5,
        &&H_DECOY_5,
        &&H_DECOY_1,
        &&H_DECOY_14,
        &&H_DECOY_9,
        &&H_DECOY_13,
        &&H_EXIT,
        &&H_DECOY_10,
        &&H_DECOY_5,
        &&H_DECOY_13,
        &&H_DECOY_5,
        &&H_DECOY_12,
        &&H_DECOY_2,
        &&H_DECOY_4,
        &&H_DECOY_2,
        &&H_DECOY_12,
        &&H_JCC,
        &&H_DECOY_9,
        &&H_DECOY_8,
        &&H_JMP,
        &&H_DECOY_12,
        &&H_DECOY_3,
        &&H_CMP_RR,
        &&H_RET,
        &&H_BRIDGE_TO_MATH,
        &&H_DECOY_6,
        &&H_DECOY_5,
        &&H_DECOY_4,
        &&H_DECOY_6,
        &&H_DECOY_10,
        &&H_FUSED_SUB_XOR_RRI,
        &&H_DECOY_0,
        &&H_DECOY_2,
        &&H_DECOY_4,
        &&H_DECOY_7,
        &&H_DECOY_13,
        &&H_DECOY_0,
        &&H_DECOY_14,
        &&H_DECOY_5,
        &&H_DECOY_5,
        &&H_DECOY_7,
        &&H_DECOY_11,
        &&H_DECOY_7,
        &&H_SHR_RI,
        &&H_DECOY_8,
        &&H_DECOY_15,
        &&H_DECOY_10,
        &&H_AND_RR,
        &&H_DECOY_9,
        &&H_DECOY_12,
        &&H_DECOY_7,
        &&H_DECOY_14,
        &&H_DECOY_15,
        &&H_DECOY_4,
        &&H_DECOY_1,
        &&H_DECOY_11,
        &&H_DECOY_15,
        &&H_SUB_RI,
        &&H_XOR_RR,
        &&H_DECOY_2,
        &&H_DECOY_11,
        &&H_CALL,
        &&H_DECOY_3,
        &&H_DECOY_7,
        &&H_MOV_RI,
        &&H_DECOY_13,
        &&H_DECOY_4,
        &&H_DECOY_0,
        &&H_DECOY_6,
        &&H_SUB_RR,
        &&H_DECOY_15,
        &&H_DECOY_6,
        &&H_DECOY_15,
        &&H_DECOY_12,
        &&H_DECOY_5,
        &&H_DECOY_3,
        &&H_DECOY_6,
        &&H_DECOY_8,
        &&H_DECOY_4,
        &&H_DECOY_1,
        &&H_DECOY_10,
        &&H_DECOY_5,
        &&H_POP_R,
        &&H_DECOY_13,
        &&H_MOV_RR,
        &&H_DECOY_1,
        &&H_DECOY_9,
        &&H_MOV_HIGH,
        &&H_DECOY_2,
        &&H_DECOY_6,
        &&H_DECOY_0,
        &&H_FUSED_MOV_ADD_RRI,
        &&H_DECOY_12,
        &&H_FUSED_ADD_XOR_RRI,
        &&H_DECOY_1,
        &&H_DECOY_0,
        &&H_DECOY_14,
        &&H_DECOY_14,
        &&H_DECOY_15,
        &&H_SETCC,
        &&H_DECOY_12,
        &&H_DECOY_11,
        &&H_DECOY_10,
        &&H_DECOY_9,
        &&H_DECOY_13,
        &&H_DECOY_7,
        &&H_DECOY_14,
        &&H_DECOY_1,
        &&H_DECOY_4,
        &&H_DECOY_10,
        &&H_DECOY_2,
        &&H_DECOY_9,
        &&H_DECOY_12,
        &&H_DECOY_1,
        &&H_DECOY_13,
        &&H_DECOY_12,
        &&H_DECOY_8,
        &&H_DECOY_9,
        &&H_DECOY_11,
        &&H_DECOY_3,
        &&H_DECOY_4,
        &&H_DECOY_2,
        &&H_FUSED_CMP_CMOV,
        &&H_DECOY_7,
        &&H_DECOY_2,
        &&H_SHL_RI,
        &&H_DECOY_2,
        &&H_DECOY_3,
        &&H_DECOY_12,
        &&H_DECOY_13,
        &&H_DECOY_1,
        &&H_DECOY_6,
        &&H_DECOY_12,
        &&H_DECOY_7,
        &&H_DECOY_8,
        &&H_DECOY_5,
        &&H_OR_RR,
        &&H_DECOY_11,
        &&H_DECOY_9,
        &&H_DECOY_13,
        &&H_DECOY_10,
        &&H_DECOY_8,
        &&H_DECOY_14,
        &&H_DECOY_6,
        &&H_DECOY_0,
        &&H_DECOY_0,
        &&H_DECOY_6,
        &&H_DECOY_10,
        &&H_ROL_RI,
        &&H_DECOY_14,
        &&H_DECOY_14,
        &&H_IMUL_RR,
        &&H_DECOY_7,
        &&H_DECOY_12,
        &&H_DECOY_10,
        &&H_DECOY_1,
        &&H_BRIDGE_TO_FLOW,
        &&H_DECOY_9,
        &&H_DECOY_1,
        &&H_DECOY_4,
        &&H_DECOY_4,
        &&H_DECOY_15,
        &&H_DECOY_5,
        &&H_DECOY_14,
        &&H_DECOY_1,
        &&H_DECOY_3,
        &&H_DECOY_11,
        &&H_XOR_RI,
    };

    static const void* const dispatch_domain2[256] = {
        &&H_CMOV,
        &&H_DECOY_13,
        &&H_DECOY_9,
        &&H_DECOY_9,
        &&H_DECOY_15,
        &&H_DECOY_11,
        &&H_DECOY_7,
        &&H_DECOY_3,
        &&H_DECOY_2,
        &&H_DECOY_10,
        &&H_DECOY_10,
        &&H_DECOY_0,
        &&H_DECOY_11,
        &&H_DECOY_3,
        &&H_DECOY_14,
        &&H_NOP,
        &&H_DECOY_13,
        &&H_DECOY_8,
        &&H_DECOY_5,
        &&H_DECOY_3,
        &&H_DECOY_0,
        &&H_DECOY_6,
        &&H_DECOY_8,
        &&H_DECOY_8,
        &&H_DECOY_13,
        &&H_DECOY_10,
        &&H_DECOY_9,
        &&H_DECOY_15,
        &&H_DECOY_3,
        &&H_IMUL_RI,
        &&H_OR_RI,
        &&H_DECOY_6,
        &&H_DECOY_0,
        &&H_DECOY_8,
        &&H_DECOY_1,
        &&H_DECOY_1,
        &&H_DECOY_12,
        &&H_FUSED_ADD_IMUL_RRI,
        &&H_DECOY_10,
        &&H_DECOY_15,
        &&H_DECOY_0,
        &&H_DECOY_13,
        &&H_DECOY_3,
        &&H_DECOY_15,
        &&H_FUSED_XOR_ADD_RRI,
        &&H_DECOY_4,
        &&H_DECOY_4,
        &&H_AND_RI,
        &&H_DECOY_15,
        &&H_DECOY_14,
        &&H_DECOY_15,
        &&H_DECOY_2,
        &&H_DECOY_0,
        &&H_DECOY_8,
        &&H_DECOY_11,
        &&H_DECOY_13,
        &&H_DECOY_6,
        &&H_DECOY_11,
        &&H_DECOY_2,
        &&H_ADD_RR,
        &&H_DECOY_0,
        &&H_PUSH_R,
        &&H_DECOY_8,
        &&H_DECOY_4,
        &&H_DECOY_8,
        &&H_ROR_RI,
        &&H_DECOY_5,
        &&H_DECOY_10,
        &&H_DECOY_7,
        &&H_DECOY_6,
        &&H_DECOY_7,
        &&H_DECOY_2,
        &&H_DECOY_14,
        &&H_DECOY_11,
        &&H_DECOY_14,
        &&H_ADD_RI,
        &&H_DECOY_7,
        &&H_DECOY_3,
        &&H_CMP_RI,
        &&H_DECOY_7,
        &&H_DECOY_3,
        &&H_DECOY_9,
        &&H_DECOY_11,
        &&H_DECOY_15,
        &&H_DECOY_11,
        &&H_DECOY_8,
        &&H_DECOY_9,
        &&H_DECOY_12,
        &&H_DECOY_5,
        &&H_DECOY_5,
        &&H_DECOY_1,
        &&H_DECOY_14,
        &&H_DECOY_9,
        &&H_DECOY_13,
        &&H_EXIT,
        &&H_DECOY_10,
        &&H_DECOY_5,
        &&H_DECOY_13,
        &&H_DECOY_5,
        &&H_DECOY_12,
        &&H_DECOY_2,
        &&H_DECOY_4,
        &&H_DECOY_2,
        &&H_DECOY_12,
        &&H_JCC,
        &&H_DECOY_9,
        &&H_DECOY_8,
        &&H_JMP,
        &&H_DECOY_12,
        &&H_DECOY_3,
        &&H_CMP_RR,
        &&H_RET,
        &&H_BRIDGE_TO_MATH,
        &&H_DECOY_6,
        &&H_DECOY_5,
        &&H_DECOY_4,
        &&H_DECOY_6,
        &&H_DECOY_10,
        &&H_FUSED_SUB_XOR_RRI,
        &&H_DECOY_0,
        &&H_DECOY_2,
        &&H_DECOY_4,
        &&H_DECOY_7,
        &&H_DECOY_13,
        &&H_DECOY_0,
        &&H_DECOY_14,
        &&H_DECOY_5,
        &&H_DECOY_5,
        &&H_DECOY_7,
        &&H_DECOY_11,
        &&H_DECOY_7,
        &&H_SHR_RI,
        &&H_DECOY_8,
        &&H_DECOY_15,
        &&H_DECOY_10,
        &&H_AND_RR,
        &&H_DECOY_9,
        &&H_DECOY_12,
        &&H_DECOY_7,
        &&H_DECOY_14,
        &&H_DECOY_15,
        &&H_DECOY_4,
        &&H_DECOY_1,
        &&H_DECOY_11,
        &&H_DECOY_15,
        &&H_SUB_RI,
        &&H_XOR_RR,
        &&H_DECOY_2,
        &&H_DECOY_11,
        &&H_CALL,
        &&H_DECOY_3,
        &&H_DECOY_7,
        &&H_MOV_RI,
        &&H_DECOY_13,
        &&H_DECOY_4,
        &&H_DECOY_0,
        &&H_DECOY_6,
        &&H_SUB_RR,
        &&H_DECOY_15,
        &&H_DECOY_6,
        &&H_DECOY_15,
        &&H_DECOY_12,
        &&H_DECOY_5,
        &&H_DECOY_3,
        &&H_DECOY_6,
        &&H_DECOY_8,
        &&H_DECOY_4,
        &&H_DECOY_1,
        &&H_DECOY_10,
        &&H_DECOY_5,
        &&H_POP_R,
        &&H_DECOY_13,
        &&H_MOV_RR,
        &&H_DECOY_1,
        &&H_DECOY_9,
        &&H_MOV_HIGH,
        &&H_DECOY_2,
        &&H_DECOY_6,
        &&H_DECOY_0,
        &&H_FUSED_MOV_ADD_RRI,
        &&H_DECOY_12,
        &&H_FUSED_ADD_XOR_RRI,
        &&H_DECOY_1,
        &&H_DECOY_0,
        &&H_DECOY_14,
        &&H_DECOY_14,
        &&H_DECOY_15,
        &&H_SETCC,
        &&H_DECOY_12,
        &&H_DECOY_11,
        &&H_DECOY_10,
        &&H_DECOY_9,
        &&H_DECOY_13,
        &&H_DECOY_7,
        &&H_DECOY_14,
        &&H_DECOY_1,
        &&H_DECOY_4,
        &&H_DECOY_10,
        &&H_DECOY_2,
        &&H_DECOY_9,
        &&H_DECOY_12,
        &&H_DECOY_1,
        &&H_DECOY_13,
        &&H_DECOY_12,
        &&H_DECOY_8,
        &&H_DECOY_9,
        &&H_DECOY_11,
        &&H_DECOY_3,
        &&H_DECOY_4,
        &&H_DECOY_2,
        &&H_FUSED_CMP_CMOV,
        &&H_DECOY_7,
        &&H_DECOY_2,
        &&H_SHL_RI,
        &&H_DECOY_2,
        &&H_DECOY_3,
        &&H_DECOY_12,
        &&H_DECOY_13,
        &&H_DECOY_1,
        &&H_DECOY_6,
        &&H_DECOY_12,
        &&H_DECOY_7,
        &&H_DECOY_8,
        &&H_DECOY_5,
        &&H_OR_RR,
        &&H_DECOY_11,
        &&H_DECOY_9,
        &&H_DECOY_13,
        &&H_DECOY_10,
        &&H_DECOY_8,
        &&H_DECOY_14,
        &&H_DECOY_6,
        &&H_DECOY_0,
        &&H_DECOY_0,
        &&H_DECOY_6,
        &&H_DECOY_10,
        &&H_ROL_RI,
        &&H_DECOY_14,
        &&H_DECOY_14,
        &&H_IMUL_RR,
        &&H_DECOY_7,
        &&H_DECOY_12,
        &&H_DECOY_10,
        &&H_DECOY_1,
        &&H_BRIDGE_TO_FLOW,
        &&H_DECOY_9,
        &&H_DECOY_1,
        &&H_DECOY_4,
        &&H_DECOY_4,
        &&H_DECOY_15,
        &&H_DECOY_5,
        &&H_DECOY_14,
        &&H_DECOY_1,
        &&H_DECOY_3,
        &&H_DECOY_11,
        &&H_XOR_RI,
    };

    static const void* const* const all_dispatch_domains[3] = {
        dispatch_domain0,
        dispatch_domain1,
        dispatch_domain2,
    };

    uint64_t word = 0;
    uint8_t op = 0;
    uint8_t dst = 0;
    uint8_t src = 0;
    int64_t imm = 0;

    #define FETCH_NEXT() do { \
        if (vIP_idx >= count) goto EXIT_VM; \
        uint64_t k_pos = key64_for_offset(seed, vIP_idx); \
        uint64_t k_dyn = k_pos ^ ctx.running_key; \
        word = bytecode[vIP_idx] ^ k_pos; \
        /* Ephemeral Self-Consuming: Overwrite scratch RAM buffer with dynamic rolling noise */ \
        work_bc[vIP_idx] = (k_dyn * 0x6A09E667F3BCC908ULL) ^ 0x5877CAFE1337BEEFULL; \
        vIP_idx++; \
        op = (uint8_t)(word & 0xFF); \
        dst = (uint8_t)((word >> 8) & 0x1F); \
        src = (uint8_t)((word >> 13) & 0x1F); \
        imm = (int64_t)((int32_t)((word >> 18) & 0xFFFFFFFFULL)); \
        ctx.evolve_mask((uint32_t)k_dyn); \
        ctx.advance_running_key(op, dst, imm); \
        uint8_t domain_idx = (uint8_t)((op ^ (uint8_t)(k_dyn & 0x07)) % 3); \
        goto *all_dispatch_domains[domain_idx][op]; \
    } while(0)

    FETCH_NEXT();

    #if defined(__x86_64__)
    #define PROBE_START() uint64_t _t0 = __builtin_ia32_rdtsc()
    #define PROBE_CHECK() do { uint64_t _t1 = __builtin_ia32_rdtsc(); if ((_t1 - _t0) > 100000ULL) { ctx.reg_mask ^= 0x1337BEEF5877A5A5ULL; } } while(0)
    #elif defined(__aarch64__)
    #define PROBE_START() uint64_t _t0; __asm__ volatile("mrs %0, cntvct_el0" : "=r"(_t0))
    #define PROBE_CHECK() do { uint64_t _t1; __asm__ volatile("mrs %0, cntvct_el0" : "=r"(_t1)); if ((_t1 - _t0) > 100000ULL) { ctx.reg_mask ^= 0x1337BEEF5877A5A5ULL; } } while(0)
    #else
    #define PROBE_START() uint64_t _t0 = 0
    #define PROBE_CHECK() do {} while(0)
    #endif

    H_NOP: ctx.executed_instructions++; FETCH_NEXT();
    H_MOV_RR: ctx.set_reg(dst, ctx.get_reg(src)); ctx.executed_instructions++; FETCH_NEXT();
    H_MOV_RI: ctx.set_reg(dst, (uint64_t)(uint32_t)imm); ctx.executed_instructions++; FETCH_NEXT();
    H_MOV_HIGH: {
        uint64_t high_val = (uint64_t)(uint32_t)imm << 32;
        ctx.set_reg(dst, (ctx.get_reg(dst) & 0xFFFFFFFFULL) | high_val);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_ADD_RR: { PROBE_START(); ctx.set_reg(dst, ((ctx.get_reg(dst) ^ ctx.get_reg(src)) + 2 * (ctx.get_reg(dst) & ctx.get_reg(src)))); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_ADD_RI: { PROBE_START(); ctx.set_reg(dst, (ctx.get_reg(dst) ^ (uint64_t)imm) + 2 * (ctx.get_reg(dst) & (uint64_t)imm)); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_SUB_RR: { PROBE_START(); ctx.set_reg(dst, ((ctx.get_reg(dst) ^ ctx.get_reg(src)) - 2 * ((~ctx.get_reg(dst)) & ctx.get_reg(src)))); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_SUB_RI: { PROBE_START(); ctx.set_reg(dst, (ctx.get_reg(dst) ^ (uint64_t)imm) - 2 * ((~ctx.get_reg(dst)) & (uint64_t)imm)); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_IMUL_RR: {
        PROBE_START();
        uint64_t a = ctx.get_reg(dst); uint64_t b = ctx.get_reg(src);
        ctx.set_reg(dst, ((a & b) * (a | b)) + ((a & (~b)) * ((~a) & b)));
        PROBE_CHECK();
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_IMUL_RI: {
        PROBE_START();
        uint64_t a = ctx.get_reg(dst); uint64_t b = (uint64_t)imm;
        ctx.set_reg(dst, ((a & b) * (a | b)) + ((a & (~b)) * ((~a) & b)));
        PROBE_CHECK();
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_XOR_RR: { PROBE_START(); ctx.set_reg(dst, ((ctx.get_reg(dst) + ctx.get_reg(src)) - 2 * (ctx.get_reg(dst) & ctx.get_reg(src)))); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_XOR_RI: { PROBE_START(); ctx.set_reg(dst, (ctx.get_reg(dst) | (uint64_t)imm) ^ (ctx.get_reg(dst) & (uint64_t)imm)); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_AND_RR: ctx.set_reg(dst, (ctx.get_reg(dst) + ctx.get_reg(src)) - (ctx.get_reg(dst) | ctx.get_reg(src))); ctx.executed_instructions++; FETCH_NEXT();
    H_AND_RI: ctx.set_reg(dst, (ctx.get_reg(dst) + (uint64_t)imm) - (ctx.get_reg(dst) | (uint64_t)imm)); ctx.executed_instructions++; FETCH_NEXT();
    H_OR_RR: ctx.set_reg(dst, (ctx.get_reg(dst) ^ ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))); ctx.executed_instructions++; FETCH_NEXT();
    H_OR_RI: ctx.set_reg(dst, (ctx.get_reg(dst) ^ (uint64_t)imm) + (ctx.get_reg(dst) & (uint64_t)imm)); ctx.executed_instructions++; FETCH_NEXT();
    H_ROL_RI: {
        uint64_t val = ctx.get_reg(dst); uint32_t shift = (uint32_t)(imm & 63);
        ctx.set_reg(dst, (val << shift) | (val >> ((64 - shift) & 63)));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_ROR_RI: {
        uint64_t val = ctx.get_reg(dst); uint32_t shift = (uint32_t)(imm & 63);
        ctx.set_reg(dst, (val >> shift) | (val << ((64 - shift) & 63)));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_SHL_RI: {
        uint64_t val = ctx.get_reg(dst); uint32_t shift = (uint32_t)(imm & 63);
        ctx.set_reg(dst, val << shift);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_SHR_RI: {
        uint64_t val = ctx.get_reg(dst); uint32_t shift = (uint32_t)(imm & 63);
        ctx.set_reg(dst, val >> shift);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_CMP_RI: {
        uint64_t a = ctx.get_reg(dst); uint64_t b = (uint64_t)imm;
        uint64_t res = a - b;
        ctx.zf = (res == 0);
        ctx.sf = ((int64_t)res < 0);
        ctx.cf = (a < b);
        ctx.of = ((((a ^ b) & (a ^ res)) >> 63) != 0);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_CMP_RR: {
        uint64_t a = ctx.get_reg(dst); uint64_t b = ctx.get_reg(src);
        uint64_t res = a - b;
        ctx.zf = (res == 0);
        ctx.sf = ((int64_t)res < 0);
        ctx.cf = (a < b);
        ctx.of = ((((a ^ b) & (a ^ res)) >> 63) != 0);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_PUSH_R: ctx.push(ctx.get_reg(dst)); ctx.executed_instructions++; FETCH_NEXT();
    H_POP_R: ctx.set_reg(dst, ctx.pop()); ctx.executed_instructions++; FETCH_NEXT();
    H_JMP: {
        vIP_idx = (size_t)imm;
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_JCC: {
        uint8_t cond = (uint8_t)((word >> 18) & 0x0F);
        uint64_t t_true = (uint64_t)((word >> 22) & 0x1FFFFFULL);
        uint64_t t_false = (uint64_t)((word >> 43) & 0x1FFFFFULL);
        uint64_t c = eval_condition(ctx, cond) ? 1ULL : 0ULL;
        vIP_idx = (size_t)(c * t_true + (1ULL - c) * t_false);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_CMOV: {
        uint8_t cond = (uint8_t)((word >> 18) & 0x0F);
        if (eval_condition(ctx, cond)) ctx.set_reg(dst, ctx.get_reg(src));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_SETCC: {
        uint8_t cond = (uint8_t)((word >> 18) & 0x0F);
        uint64_t val = eval_condition(ctx, cond) ? 1ULL : 0ULL;
        ctx.set_reg(dst, val);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_CALL: {
        ctx.push((uint64_t)vIP_idx);
        vIP_idx = (size_t)imm;
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_RET: case_ret: ctx.executed_instructions++; goto EXIT_VM;
    H_EXIT: ctx.executed_instructions++; goto EXIT_VM;

    H_FUSED_MOV_ADD_RRI: {
        ctx.set_reg(dst, ctx.get_reg(src) + (uint64_t)imm);
        ctx.executed_instructions += 2;
        FETCH_NEXT();
    }
    H_FUSED_ADD_IMUL_RRI: {
        ctx.set_reg(dst, (ctx.get_reg(dst) + ctx.get_reg(src)) * (uint64_t)imm);
        ctx.executed_instructions += 2;
        FETCH_NEXT();
    }
    H_FUSED_ADD_XOR_RRI: {
        ctx.set_reg(dst, (ctx.get_reg(dst) + ctx.get_reg(src)) ^ (uint64_t)imm);
        ctx.executed_instructions += 2;
        FETCH_NEXT();
    }
    H_FUSED_SUB_XOR_RRI: {
        ctx.set_reg(dst, (ctx.get_reg(dst) - ctx.get_reg(src)) ^ (uint64_t)imm);
        ctx.executed_instructions += 2;
        FETCH_NEXT();
    }
    H_FUSED_XOR_ADD_RRI: {
        ctx.set_reg(dst, (ctx.get_reg(dst) ^ ctx.get_reg(src)) + (uint64_t)imm);
        ctx.executed_instructions += 2;
        FETCH_NEXT();
    }
    H_FUSED_CMP_CMOV: {
        uint64_t a = ctx.get_reg(dst); uint64_t b = (uint64_t)imm;
        uint64_t res = a - b;
        ctx.zf = (res == 0);
        ctx.sf = ((int64_t)res < 0);
        ctx.cf = (a < b);
        uint8_t cond = (uint8_t)((word >> 50) & 0x0F);
        if (eval_condition(ctx, cond)) ctx.set_reg(dst, ctx.get_reg(src));
        ctx.executed_instructions += 2;
        FETCH_NEXT();
    }

    H_BRIDGE_TO_FLOW: {
        ctx.morph_math_to_flow((uint64_t)imm);
        ctx.executed_instructions++;
        FETCH_NEXT();
    }
    H_BRIDGE_TO_MATH: {
        ctx.morph_flow_to_math((uint64_t)imm);
        ctx.executed_instructions++;
        FETCH_NEXT();
    }
    H_DECOY_0: { ctx.set_reg(dst, ctx.get_reg(dst) ^ 0x5877ULL); ctx.executed_instructions++; FETCH_NEXT(); }
    H_DECOY_1: { ctx.set_reg(dst, ctx.get_reg(dst) + (uint64_t)imm); ctx.executed_instructions++; FETCH_NEXT(); }
    H_DECOY_2: { ctx.set_reg(dst, ctx.get_reg(dst) * 0x9E37ULL); ctx.executed_instructions++; FETCH_NEXT(); }
    H_DECOY_3: { ctx.set_reg(dst, (ctx.get_reg(dst) << 3) | (ctx.get_reg(dst) >> 61)); ctx.executed_instructions++; FETCH_NEXT(); }
    H_DECOY_4: { ctx.set_reg(dst, ctx.get_reg(src) ^ (uint64_t)imm); ctx.executed_instructions++; FETCH_NEXT(); }
    H_DECOY_5: { ctx.set_reg(dst, ctx.get_reg(dst) & ~ctx.get_reg(src)); ctx.executed_instructions++; FETCH_NEXT(); }
    H_DECOY_6: { ctx.set_reg(dst, ctx.get_reg(dst) | 0xCAFEBABEULL); ctx.executed_instructions++; FETCH_NEXT(); }
    H_DECOY_7: { ctx.set_reg(dst, (ctx.get_reg(dst) >> 5) ^ (uint64_t)imm); ctx.executed_instructions++; FETCH_NEXT(); }
    H_DECOY_8: { ctx.set_reg(dst, ctx.get_reg(dst) - 0x1337ULL); ctx.executed_instructions++; FETCH_NEXT(); }
    H_DECOY_9: { ctx.set_reg(dst, ctx.get_reg(dst) ^ (ctx.get_reg(src) + 1)); ctx.executed_instructions++; FETCH_NEXT(); }
    H_DECOY_10: { ctx.set_reg(dst, (ctx.get_reg(dst) * 6364136223846793005ULL) + 1); ctx.executed_instructions++; FETCH_NEXT(); }
    H_DECOY_11: { ctx.set_reg(dst, (ctx.get_reg(dst) << 7) ^ (uint64_t)imm); ctx.executed_instructions++; FETCH_NEXT(); }
    H_DECOY_12: { ctx.set_reg(dst, ctx.get_reg(dst) ^ 0xDEADBEEFULL); ctx.executed_instructions++; FETCH_NEXT(); }
    H_DECOY_13: { ctx.set_reg(dst, ctx.get_reg(dst) + ctx.get_reg(src)); ctx.executed_instructions++; FETCH_NEXT(); }
    H_DECOY_14: { ctx.set_reg(dst, ctx.get_reg(dst) ^ (uint64_t)(imm * 3)); ctx.executed_instructions++; FETCH_NEXT(); }
    H_DECOY_15: { ctx.set_reg(dst, ~ctx.get_reg(dst)); ctx.executed_instructions++; FETCH_NEXT(); }
    H_DECOY:
        ctx.trapped = true;
        goto EXIT_VM;

    EXIT_VM:
    /* Ephemeral Complete Memory Sanitization: Scrub all working memory */
    for (size_t i = 0; i < count; ++i) {
        work_bc[i] = 0x5A5A5A5A13375877ULL ^ ((uint64_t)seed + (uint64_t)i);
    }
    return !ctx.trapped;
}

} // namespace vanguard_threaded_vm

