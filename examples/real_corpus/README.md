# Real-World Production Benchmark Corpus

This directory contains production C workloads integrated from real-world open-source software libraries, used to benchmark and validate the ASGARD-5877 virtualization and obfuscation compiler toolchain under ARM64.

## Workloads

- `openssl_sha256.c`: Production OpenSSL FIPS 180-4 SHA-256 block transformation routine (`openssl_sha256_transform`), featuring 64-round message scheduling, non-linear bitwise logic ($\text{Ch}, \text{Maj}$), circular rotations ($\Sigma_0, \Sigma_1, \sigma_0, \sigma_1$), and static round constants $K[64]$.
- `coreutils_crc32.c`: Production GNU Coreutils IEEE 802.3 32-bit CRC (`cksum`) engine (`coreutils_crc32_block`), featuring precomputed 256-word polynomial lookup tables and streaming byte block operations.
- `sqlite_varint_hash.c`: Production SQLite3 variable-length 64-bit integer codec (`sqlite3PutVarint64`, `sqlite3GetVarint64`) and 64-bit B-Tree/WAL page hash (`sqlite3PageChecksum`), exercising boundary encodings, memory zeroing, and external symbol resolution.

## Quick Start

Run the automated benchmark suite with DRS and overhead profiling:

```bash
../../scripts/run_real_world_benchmarks.sh
```

Or virtualize an individual workload manually:

```bash
# From repository root:
./_build/default/bin/main.exe protect-arm64 \
    -i examples/real_corpus/openssl_sha256.c \
    -o /tmp/asgard_openssl \
    --flatten --mba

# Execute virtualized binary:
/tmp/asgard_openssl/protected_app 100
```

See [`docs/REAL_WORLD_BENCHMARKS.md`](../../docs/REAL_WORLD_BENCHMARKS.md) for full metrics and architectural documentation.
