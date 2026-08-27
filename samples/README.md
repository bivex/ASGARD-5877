# ASGARD-5877 Samples & Reverse Engineering Challenges

This directory contains standalone reference samples and reverse-engineering challenges protected with ASGARD-5877 Code Virtualization & Anti-Analysis Pipeline:

## Files:
1. `crackme_vm.cpp` — Source code for the standalone ARM64 CrackMe challenge hosting the Vanguard Direct-Threaded Virtual Machine (VBO) execution engine.
2. `sample_auth.c` — C implementation of an authentication algorithm with polymorphic constant blinding and dynamic keystream generation.

## Pre-compiled Binaries:
* Hardened Virtualized CrackMe: `binaries/crackme_arm64/crackme`
* Crackme Archive for CTF upload: `binaries/crackme_arm64/crackme.zip`
* Protected Bytecode payload: `binaries/crackme_arm64/protected.vanguard`
* Direct-Threaded C++ VM header: `binaries/crackme_arm64/threaded_vm.hpp`

## Validating CrackMe:
```bash
# Valid Solution Key:
./binaries/crackme_arm64/crackme FLAG-7A3F-9B1C-4D8E-2E6A

# Invalid Key Rejection:
./binaries/crackme_arm64/crackme FLAG-0000-0000-0000-0000
```
