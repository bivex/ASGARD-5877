/* ========================================================================= */
/*  ASGARD-5877 Differential Fuzzing - Shared Payload Layout                  */
/*                                                                           */
/*  Single source of truth for the memory layout consumed by BOTH sides of   */
/*  every differential comparison:                                           */
/*                                                                           */
/*    * the native golden build (plain clang++, markers compile to no-ops)   */
/*    * the ASGARD-protected VM build (macro-obf + CFF + MBA + VM bytecode)  */
/*    * the libFuzzer driver (memcpy's raw fuzz bytes over this struct)      */
/*                                                                           */
/*  Keep it POD and fixed-layout: no virtuals, no pointers, no padding-only  */
/*  field reads. The VM trampoline receives `&payload` as a raw address and  */
/*  the lifted x86-64 code reads members at their natural offsets.           */
/* ========================================================================= */
#ifndef ASGARD_DIFF_FUZZ_TYPES_H
#define ASGARD_DIFF_FUZZ_TYPES_H

#include <stdint.h>
#include <stddef.h>

struct TestPayload {
    uint64_t a;      /* wide integer mixer input                       */
    int32_t  b;      /* signed arithmetic input (incl. INT32_MIN)      */
    uint32_t c;      /* shift/div operand (0, 31, 32, 63 boundaries)   */
    double   d;      /* FP multiply/add + cvttsd2si parity            */
    double   e;      /* FP multiply/add + cvtsd2ss (double->float)    */
    uint8_t  flags;  /* branch / switch selector (bit 0 = main path)  */
};

/* Canonical packed size used by the libFuzzer driver: 40 bytes. */
#define ASG_TEST_PAYLOAD_SIZE ((size_t)40)

#endif /* ASGARD_DIFF_FUZZ_TYPES_H */
