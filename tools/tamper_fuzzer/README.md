# tools/tamper_fuzzer — C++ Bytecode Fault-Injection & Anti-Tamper Fuzzer

In-process C++20 fault-injection and tamper fuzzer testing the cryptographic barriers, crash safety, and execution integrity invariants of the ASGARD-5877 Stack-VM.

---

## 1. Verified Invariants

* **Invariant 1 (Zero Privilege Escalation / Zero Bypass)**:
  Tampered bytecode must **never** return exit code `0` (`ACCESS GRANTED`) under any mutation.
* **Invariant 2 (SipHash-1-2 Bit Diffusion & Desynchronization)**:
  Any 1-bit or 1-byte mutation in a block desynchronizes the Murmur3 `fmix64` rolling key stream and the block's `SipHash-1-2` entry key, turning subsequent opcode decodes into invalid instruction traps.
* **Invariant 3 (Crash Safety & Signal Recovery)**:
  Catches `SIGSEGV`, `SIGBUS`, `SIGFPE`, `SIGILL` in-process via POSIX `sigsetjmp` / `siglongjmp` to verify that out-of-bounds reads/writes triggered by corrupted operands are caught cleanly without memory leaks or host process termination.
* **Invariant 4 (Authentication Trap)**:
  Confirms that payload corruption sets `asgard_stack_vm::g_last_auth_failed` and aborts execution before reaching critical logic.

---

## 2. Mutation Strategies

1. `MUT_BIT_FLIP`: Single-bit inversion at random ciphertext offsets.
2. `MUT_BYTE_REPLACE`: Replaces random byte with `0x00`, `0xFF`, or random value.
3. `MUT_WORD_CORRUPT`: Corrupts entire 64-bit aligned words.
4. `MUT_CHUNK_ZERO`: Zeroes out slices of 4..32 contiguous bytes.
5. `MUT_ENTRY_CORRUPT`: Mutates the initial entry block header and `KeyFeedback` tokens at offset `0..32`.
6. `MUT_DISPATCH_CORRUPT`: Targets CFF dispatcher shards and VPC routing blocks.

---

## 3. Build & Run

```bash
# Build the fuzzer binary:
bash tools/tamper_fuzzer/build.sh

# Run 1,000 iterations:
./tools/tamper_fuzzer/tamper_fuzzer --iters 1000

# Run 10,000 iterations on custom payload and seed:
./tools/tamper_fuzzer/tamper_fuzzer --iters 10000 --seed 0x1337 --payload protected_arm64_out/protected.vanguard
```
