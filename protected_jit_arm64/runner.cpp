#if __has_include("jit_vm_runtime.hpp")
#include "jit_vm_runtime.hpp"
#elif __has_include("rd_jit_runtime.hpp")
#include "rd_jit_runtime.hpp"
#else
#include "threaded_vm.hpp"
#endif
#include <iostream>
#include <chrono>

// JIT Block Descriptors
static const asgard_rd_jit::JITInstr jit_block_0_instrs[] = {
    { asgard_rd_jit::JIT_OP_MOV_RI, 3, 0, 0x000000002FF0AD38ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
};
static const asgard_rd_jit::JITInstr jit_block_1_instrs[] = {
    { asgard_rd_jit::JIT_OP_ADD_RI, 4, 0, 0xFFFFFFFFFFFFFFE0ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_MOV_RR, 5, 4, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_ADD_RI, 5, 0, 0x0000000000000010ULL },
    { asgard_rd_jit::JIT_OP_SUB_RI, 4, 0, 0x0000000000000020ULL },
    { asgard_rd_jit::JIT_OP_MOV_RI, 10, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_MOV_RI, 11, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_MOV_RI, 3, 0, 0x000000001289B876ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
};
static const asgard_rd_jit::JITInstr jit_block_2_instrs[] = {
    { asgard_rd_jit::JIT_OP_MOV_RI, 12, 0, 0x00000000000054AFULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_AND_RI, 12, 0, 0x000000000000FFFFULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_OR_RI, 12, 0, 0x0000000039880000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_MOV_RI, 3, 0, 0x000000003C31F8AAULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
};
static const asgard_rd_jit::JITInstr jit_block_3_instrs[] = {
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_MOV_RI, 3, 0, 0x00000000297CB426ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
};
static const asgard_rd_jit::JITInstr jit_block_4_instrs[] = {
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_MOV_RR, 13, 5, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_SUB_RI, 13, 0, 0x0000000000000028ULL },
    { asgard_rd_jit::JIT_OP_MOV_RI, 3, 0, 0x000000000D91C102ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
};
static const asgard_rd_jit::JITInstr jit_block_5_instrs[] = {
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_XOR_RR, 14, 10, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_MOV_RR, 0, 11, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_ADD_RR, 0, 12, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_XOR_RR, 14, 15, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_MOV_RR, 0, 11, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_ADD_RR, 0, 13, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_ADD_RI, 11, 0, 0x0000000000000001ULL },
    { asgard_rd_jit::JIT_OP_ADD_RI, 10, 0, 0x000000000000005DULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_MOV_RI, 0, 0, 0x000000000D91C102ULL },
    { asgard_rd_jit::JIT_OP_MOV_RI, 1, 0, 0x000000006E79E11EULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_MOV_RR, 3, 1, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
};
static const asgard_rd_jit::JITInstr jit_block_6_instrs[] = {
    { asgard_rd_jit::JIT_OP_MOV_RI, 10, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_MOV_RR, 11, 5, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_SUB_RI, 11, 0, 0x0000000000000028ULL },
    { asgard_rd_jit::JIT_OP_MOV_RI, 12, 0, 0x0000000000000001ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_MOV_RI, 3, 0, 0x0000000040623940ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
};
static const asgard_rd_jit::JITInstr jit_block_7_instrs[] = {
    { asgard_rd_jit::JIT_OP_MOV_RR, 0, 10, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_ADD_RR, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_MOV_RR, 0, 10, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_ADD_RR, 0, 11, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_MOV_RI, 1, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_ADD_RI, 10, 0, 0x0000000000000001ULL },
    { asgard_rd_jit::JIT_OP_MOV_RI, 0, 0, 0x0000000040623940ULL },
    { asgard_rd_jit::JIT_OP_MOV_RI, 1, 0, 0x000000005CBB04F2ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_MOV_RR, 3, 1, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
};
static const asgard_rd_jit::JITInstr jit_block_8_instrs[] = {
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_MOV_RI, 8, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_MOV_RR, 1, 12, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_MOV_RI, 0, 0, 0x00000000228A7E5AULL },
    { asgard_rd_jit::JIT_OP_MOV_RI, 1, 0, 0x000000001D154778ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_MOV_RR, 3, 1, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
};
static const asgard_rd_jit::JITInstr jit_block_9_instrs[] = {
    { asgard_rd_jit::JIT_OP_MOV_RR, 0, 4, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_SUB_RI, 0, 0, 0x0000000000000020ULL },
    { asgard_rd_jit::JIT_OP_MOV_RR, 4, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_MOV_RI, 10, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_MOV_RI, 11, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_MOV_RI, 12, 0, 0x0000000000003780ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_AND_RI, 12, 0, 0x000000000000FFFFULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_OR_RI, 12, 0, 0x0000000069920000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_MOV_RI, 3, 0, 0x000000004B7F7E5CULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
};
static const asgard_rd_jit::JITInstr jit_block_10_instrs[] = {
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_MOV_RI, 3, 0, 0x000000004120227CULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
};
static const asgard_rd_jit::JITInstr jit_block_11_instrs[] = {
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_MOV_RI, 3, 0, 0x0000000030B8803CULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
};
static const asgard_rd_jit::JITInstr jit_block_12_instrs[] = {
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_XOR_RR, 13, 10, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_MOV_RR, 0, 11, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_ADD_RR, 0, 12, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_XOR_RR, 13, 14, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_MOV_RR, 0, 11, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_ADD_RR, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_ADD_RI, 11, 0, 0x0000000000000001ULL },
    { asgard_rd_jit::JIT_OP_ADD_RI, 10, 0, 0x000000000000005DULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_MOV_RI, 0, 0, 0x0000000030B8803CULL },
    { asgard_rd_jit::JIT_OP_MOV_RI, 1, 0, 0x0000000075F66824ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_MOV_RR, 3, 1, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
};
static const asgard_rd_jit::JITInstr jit_block_13_instrs[] = {
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_MOV_RR, 0, 4, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_SUB_RI, 0, 0, 0x0000000000000020ULL },
    { asgard_rd_jit::JIT_OP_MOV_RR, 4, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_MOV_RI, 10, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_MOV_RI, 11, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_MOV_RI, 12, 0, 0x000000000000715DULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_AND_RI, 12, 0, 0x000000000000FFFFULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_OR_RI, 12, 0, 0x000000001CC20000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_MOV_RI, 3, 0, 0x000000005B0E539AULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
};
static const asgard_rd_jit::JITInstr jit_block_14_instrs[] = {
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_MOV_RI, 3, 0, 0x000000003236B652ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
};
static const asgard_rd_jit::JITInstr jit_block_15_instrs[] = {
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_MOV_RI, 3, 0, 0x00000000759EFFB8ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
};
static const asgard_rd_jit::JITInstr jit_block_16_instrs[] = {
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_XOR_RR, 13, 10, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_MOV_RR, 0, 11, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_ADD_RR, 0, 12, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_XOR_RR, 13, 14, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_MOV_RR, 0, 11, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_ADD_RR, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_ADD_RI, 11, 0, 0x0000000000000001ULL },
    { asgard_rd_jit::JIT_OP_ADD_RI, 10, 0, 0x000000000000005DULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_MOV_RI, 0, 0, 0x00000000759EFFB8ULL },
    { asgard_rd_jit::JIT_OP_MOV_RI, 1, 0, 0x000000001FE5CAC6ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_MOV_RR, 3, 1, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
};
static const asgard_rd_jit::JITInstr jit_block_17_instrs[] = {
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_MOV_RI, 10, 0, 0x0000000000005D9AULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_ADD_RI, 4, 0, 0xFFFFFFFFFFFFFFF0ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_ADD_RI, 4, 0, 0x0000000000000010ULL },
    { asgard_rd_jit::JIT_OP_MOV_RR, 0, 4, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_SUB_RI, 0, 0, 0x0000000000000030ULL },
    { asgard_rd_jit::JIT_OP_MOV_RR, 4, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_MOV_RI, 10, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_MOV_RI, 11, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_MOV_RI, 12, 0, 0x000000000000AEC9ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_AND_RI, 12, 0, 0x000000000000FFFFULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_OR_RI, 12, 0, 0x0000000021100000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_MOV_RI, 3, 0, 0x00000000038E30EAULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
};
static const asgard_rd_jit::JITInstr jit_block_18_instrs[] = {
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_MOV_RI, 3, 0, 0x0000000070423F6EULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
};
static const asgard_rd_jit::JITInstr jit_block_19_instrs[] = {
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_MOV_RI, 3, 0, 0x000000005581B420ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
};
static const asgard_rd_jit::JITInstr jit_block_20_instrs[] = {
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_XOR_RR, 13, 10, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_MOV_RR, 0, 11, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_ADD_RR, 0, 12, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_XOR_RR, 13, 14, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_MOV_RR, 0, 11, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_ADD_RR, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_ADD_RI, 11, 0, 0x0000000000000001ULL },
    { asgard_rd_jit::JIT_OP_ADD_RI, 10, 0, 0x000000000000005DULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_MOV_RI, 0, 0, 0x000000005581B420ULL },
    { asgard_rd_jit::JIT_OP_MOV_RI, 1, 0, 0x0000000057B8DB54ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_MOV_RR, 3, 1, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
};
static const asgard_rd_jit::JITInstr jit_block_21_instrs[] = {
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_MOV_RI, 10, 0, 0x0000000000005D9AULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_ADD_RI, 4, 0, 0xFFFFFFFFFFFFFFF0ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_ADD_RI, 4, 0, 0x0000000000000010ULL },
    { asgard_rd_jit::JIT_OP_MOV_RI, 3, 0, 0x0000000076BA5B86ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
};
static const asgard_rd_jit::JITInstr jit_block_22_instrs[] = {
    { asgard_rd_jit::JIT_OP_MOV_RR, 0, 4, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_SUB_RI, 0, 0, 0x0000000000000030ULL },
    { asgard_rd_jit::JIT_OP_MOV_RR, 4, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_MOV_RI, 10, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_MOV_RI, 11, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_MOV_RI, 12, 0, 0x0000000000006749ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_AND_RI, 12, 0, 0x000000000000FFFFULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_OR_RI, 12, 0, 0x0000000005BA0000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_MOV_RI, 3, 0, 0x0000000053BB2858ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
};
static const asgard_rd_jit::JITInstr jit_block_23_instrs[] = {
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_MOV_RI, 3, 0, 0x00000000692C17F4ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
};
static const asgard_rd_jit::JITInstr jit_block_24_instrs[] = {
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_MOV_RI, 3, 0, 0x00000000370E76E0ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
};
static const asgard_rd_jit::JITInstr jit_block_25_instrs[] = {
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_XOR_RR, 13, 10, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_MOV_RR, 0, 11, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_ADD_RR, 0, 12, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_XOR_RR, 13, 14, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_MOV_RR, 0, 11, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_ADD_RR, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_ADD_RI, 11, 0, 0x0000000000000001ULL },
    { asgard_rd_jit::JIT_OP_ADD_RI, 10, 0, 0x000000000000005DULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_MOV_RI, 0, 0, 0x00000000370E76E0ULL },
    { asgard_rd_jit::JIT_OP_MOV_RI, 1, 0, 0x000000001100E2E8ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_MOV_RR, 3, 1, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
};
static const asgard_rd_jit::JITInstr jit_block_26_instrs[] = {
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_MOV_RR, 0, 4, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_SUB_RI, 0, 0, 0x0000000000000020ULL },
    { asgard_rd_jit::JIT_OP_MOV_RR, 4, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_MOV_RI, 10, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_MOV_RI, 11, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_MOV_RI, 12, 0, 0x00000000000060B9ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_AND_RI, 12, 0, 0x000000000000FFFFULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_OR_RI, 12, 0, 0x000000001DC70000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_MOV_RI, 3, 0, 0x00000000107F93FCULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
};
static const asgard_rd_jit::JITInstr jit_block_27_instrs[] = {
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_MOV_RI, 3, 0, 0x000000007AF16AEEULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
};
static const asgard_rd_jit::JITInstr jit_block_28_instrs[] = {
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_MOV_RI, 3, 0, 0x00000000790B3EE8ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
};
static const asgard_rd_jit::JITInstr jit_block_29_instrs[] = {
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_XOR_RR, 13, 10, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_MOV_RR, 0, 11, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_ADD_RR, 0, 12, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_XOR_RR, 13, 14, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_MOV_RR, 0, 11, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_ADD_RR, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_ADD_RI, 11, 0, 0x0000000000000001ULL },
    { asgard_rd_jit::JIT_OP_ADD_RI, 10, 0, 0x000000000000005DULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_MOV_RI, 0, 0, 0x00000000790B3EE8ULL },
    { asgard_rd_jit::JIT_OP_MOV_RI, 1, 0, 0x000000000E39C31AULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_MOV_RR, 3, 1, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
};
static const asgard_rd_jit::JITInstr jit_block_30_instrs[] = {
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_MOV_RI, 3, 0, 0x0000000076BA5B86ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
};
static const asgard_rd_jit::JITInstr jit_block_31_instrs[] = {
    { asgard_rd_jit::JIT_OP_MOV_RR, 0, 8, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_MOV_RR, 4, 5, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_SUB_RI, 4, 0, 0x0000000000000010ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_ADD_RI, 4, 0, 0x0000000000000020ULL },
    { asgard_rd_jit::JIT_OP_RET, 0, 0, 0x0000000000000000ULL },
};
static const asgard_rd_jit::JITInstr jit_block_32_instrs[] = {
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
};
static const asgard_rd_jit::JITInstr jit_block_33_instrs[] = {
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
};
static const asgard_rd_jit::JITInstr jit_block_34_instrs[] = {
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
};
static const asgard_rd_jit::JITInstr jit_block_35_instrs[] = {
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
};
static const asgard_rd_jit::JITInstr jit_block_36_instrs[] = {
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
};
static const asgard_rd_jit::JITInstr jit_block_37_instrs[] = {
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
};
static const asgard_rd_jit::JITInstr jit_block_38_instrs[] = {
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
};
static const asgard_rd_jit::JITInstr jit_block_39_instrs[] = {
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
};
static const asgard_rd_jit::JITInstr jit_block_40_instrs[] = {
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
};
static const asgard_rd_jit::JITInstr jit_block_41_instrs[] = {
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
};
static const asgard_rd_jit::JITInstr jit_block_42_instrs[] = {
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
};
static const asgard_rd_jit::JITInstr jit_block_43_instrs[] = {
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
};
static const asgard_rd_jit::JITInstr jit_block_44_instrs[] = {
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
};
static const asgard_rd_jit::JITInstr jit_block_45_instrs[] = {
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
};
static const asgard_rd_jit::JITInstr jit_block_46_instrs[] = {
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
};
static const asgard_rd_jit::JITInstr jit_block_47_instrs[] = {
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
};
static const asgard_rd_jit::JITInstr jit_block_48_instrs[] = {
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
};
static const asgard_rd_jit::JITInstr jit_block_49_instrs[] = {
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
};
static const asgard_rd_jit::JITInstr jit_block_50_instrs[] = {
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
};
static const asgard_rd_jit::JITInstr jit_block_51_instrs[] = {
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
};
static const asgard_rd_jit::JITInstr jit_block_52_instrs[] = {
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
};
static const asgard_rd_jit::JITInstr jit_block_53_instrs[] = {
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
};
static const asgard_rd_jit::JITInstr jit_block_54_instrs[] = {
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
};
static const asgard_rd_jit::JITInstr jit_block_55_instrs[] = {
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
};
static const asgard_rd_jit::JITInstr jit_block_56_instrs[] = {
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
};
static const asgard_rd_jit::JITInstr jit_block_57_instrs[] = {
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
};
static const asgard_rd_jit::JITInstr jit_block_58_instrs[] = {
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
};
static const asgard_rd_jit::JITInstr jit_block_59_instrs[] = {
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
};
static const asgard_rd_jit::JITInstr jit_block_60_instrs[] = {
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
};
static const asgard_rd_jit::JITInstr jit_block_61_instrs[] = {
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
};
static const asgard_rd_jit::JITInstr jit_block_62_instrs[] = {
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
};
static const asgard_rd_jit::JITInstr jit_block_63_instrs[] = {
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
    { asgard_rd_jit::JIT_OP_NOP, 0, 0, 0x0000000000000000ULL },
};

static const asgard_rd_jit::JITBlock jit_blocks[] = {
    { 0, 2, jit_block_0_instrs },
    { 1, 14, jit_block_1_instrs },
    { 2, 12, jit_block_2_instrs },
    { 3, 3, jit_block_3_instrs },
    { 4, 5, jit_block_4_instrs },
    { 5, 27, jit_block_5_instrs },
    { 6, 9, jit_block_6_instrs },
    { 7, 22, jit_block_7_instrs },
    { 8, 13, jit_block_8_instrs },
    { 9, 19, jit_block_9_instrs },
    { 10, 3, jit_block_10_instrs },
    { 11, 3, jit_block_11_instrs },
    { 12, 27, jit_block_12_instrs },
    { 13, 21, jit_block_13_instrs },
    { 14, 3, jit_block_14_instrs },
    { 15, 3, jit_block_15_instrs },
    { 16, 27, jit_block_16_instrs },
    { 17, 27, jit_block_17_instrs },
    { 18, 3, jit_block_18_instrs },
    { 19, 3, jit_block_19_instrs },
    { 20, 27, jit_block_20_instrs },
    { 21, 10, jit_block_21_instrs },
    { 22, 19, jit_block_22_instrs },
    { 23, 3, jit_block_23_instrs },
    { 24, 3, jit_block_24_instrs },
    { 25, 27, jit_block_25_instrs },
    { 26, 21, jit_block_26_instrs },
    { 27, 3, jit_block_27_instrs },
    { 28, 3, jit_block_28_instrs },
    { 29, 27, jit_block_29_instrs },
    { 30, 4, jit_block_30_instrs },
    { 31, 9, jit_block_31_instrs },
    { 32, 1, jit_block_32_instrs },
    { 33, 2, jit_block_33_instrs },
    { 34, 2, jit_block_34_instrs },
    { 35, 2, jit_block_35_instrs },
    { 36, 2, jit_block_36_instrs },
    { 37, 2, jit_block_37_instrs },
    { 38, 2, jit_block_38_instrs },
    { 39, 2, jit_block_39_instrs },
    { 40, 2, jit_block_40_instrs },
    { 41, 2, jit_block_41_instrs },
    { 42, 2, jit_block_42_instrs },
    { 43, 2, jit_block_43_instrs },
    { 44, 2, jit_block_44_instrs },
    { 45, 2, jit_block_45_instrs },
    { 46, 2, jit_block_46_instrs },
    { 47, 2, jit_block_47_instrs },
    { 48, 2, jit_block_48_instrs },
    { 49, 2, jit_block_49_instrs },
    { 50, 2, jit_block_50_instrs },
    { 51, 2, jit_block_51_instrs },
    { 52, 2, jit_block_52_instrs },
    { 53, 2, jit_block_53_instrs },
    { 54, 2, jit_block_54_instrs },
    { 55, 2, jit_block_55_instrs },
    { 56, 2, jit_block_56_instrs },
    { 57, 2, jit_block_57_instrs },
    { 58, 2, jit_block_58_instrs },
    { 59, 2, jit_block_59_instrs },
    { 60, 2, jit_block_60_instrs },
    { 61, 2, jit_block_61_instrs },
    { 62, 2, jit_block_62_instrs },
    { 63, 2, jit_block_63_instrs },
};
static const size_t num_jit_blocks = sizeof(jit_blocks) / sizeof(jit_blocks[0]);

int main(int argc, char** argv) {
    std::cout << "[ASGARD-RD-JIT] Initializing Register-Driven JIT Virtual Machine...\n";
    std::cout << "  * Architecture: Register-Driven RISC (No Stack Emulation)\n";
    std::cout << "  * Arithmetic: RNS-4 Modular Residue Splitting (M > 2^64)\n";
    std::cout << "  * Memory Protection: Dual-Mapped W^X Ephemeral Buffer\n";
    std::cout << "  * Blocks: " << num_jit_blocks << " dynamic JIT synthesis block(s)\n";

    asgard_rd_jit::DualMappedJITBuffer jit_buf(4096);
    asgard_rd_jit::RD_JIT_Context ctx;
    ctx.init();

    uint64_t arg1 = (argc > 1) ? (uint64_t)atoll(argv[1]) : 42ULL;
    uint64_t arg2 = (argc > 2) ? (uint64_t)atoll(argv[2]) : 58ULL;
    ctx.set_reg(0, arg1);
    ctx.set_reg(1, arg2);

    auto t0 = std::chrono::high_resolution_clock::now();
    asgard_rd_jit::execute_jit_function(jit_buf, ctx, jit_blocks, num_jit_blocks);
    auto t1 = std::chrono::high_resolution_clock::now();

    double elapsed_us = std::chrono::duration<double, std::micro>(t1 - t0).count();
    uint64_t res = ctx.get_reg(0);

    std::cout << "[ASGARD-RD-JIT] Ephemeral Execution Successful!\n";
    std::cout << "  * Result (REG 0): " << res << " (0x" << std::hex << res << std::dec << ")\n";
    std::cout << "  * RNS Residues: (" << ctx.vregs[0].r1 << ", " << ctx.vregs[0].r2 << ", " << ctx.vregs[0].r3 << ", " << ctx.vregs[0].r4 << ")\n";
    std::cout << "  * JIT Cycle Time: " << elapsed_us << " us\n";
    return 0;
}
