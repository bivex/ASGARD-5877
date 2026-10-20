# ASGARD-5877 nn_metamorph — Neural Network Emulation of Metamorphic Kernels

Apple Silicon MLX neural networks trained to approximate ASGARD metamorphic kernels: `asgard_fuzz_compute` (ULTRA) and `asgard_fuzz_mix` (VIRTUALIZE) from `examples/diff_fuzz`. An architectural ladder script (`--sweep`) benchmarks model capacities to evaluate what neural networks can and cannot learn, providing empirical insight into where metamorphism effectively obfuscates program semantics.

```
              TestPayload (40B) / (seed, blob)            Metamorphic output u64
                        │                                          ▲
        ┌───────────────┴───────────────┐            ┌─────────────┴─────────────┐
        │ Bit-exact NumPy reference     │            │ vm_out/protected_proj     │
        │ (kernel_ref.py, 14M vect/s)   ╞══ validation (Actual ASGARD VM binary) │
        └───────────────┬───────────────┘   (30k vect)└───────────────────────────┘
                        │ Bit features (296/646) + byte tokens (37/73)
        ┌───────────────┴────────────────────────────────┐
        │ MLX: MLP (256x2 ... 1024x6)                    │
        │      BitTokenTransformer (d128/L2 ... d256/L4) ├──► 64 output bit logits
        └────────────────────────────────────────────────┘    (BCE per bit)
```

## Quick Start

```bash
./examples/nn_metamorph/run.sh                                      # Validation + full architectural sweep (~7 min)
python3 examples/nn_metamorph/train.py --sweep --rung 'mlp-s|xf-s'  # Specific ladder subset
python3 examples/nn_metamorph/train.py --arch mlp --width 512 --depth 4 --epochs 12
```

Requirements: `mlx >= 0.31`, `numpy`, and the compiled binaries in `examples/diff_fuzz/vm_out/` (built via `run_diff_project.py`). Experiment logs are persisted to `results/results.jsonl` to aggregate model comparisons across sessions.

## Ground Truth

`kernel_ref.py` is a vectorized, bit-exact NumPy implementation of both computation kernels (masked 19-step loop, ARM saturating `fcvtzs` cast, RNE double-to-float conversion, uint64 wraparound arithmetic). `validate_ref.py` evaluates 30,000 boundary-weighted vectors (matching the differential fuzzer distribution) against the **actual protected binary** and the native golden executable, requiring 100% bitwise parity. Because differential fuzzing guarantees absolute functional equivalence, the reference matches the output of the metamorphic VM.

## Metrics

| Metric | Definition |
|---|---|
| `bit_acc` | Average prediction accuracy across all 64 output bits (0.5 = random coin toss) |
| `lo32/hi32` | Prediction accuracy on the lower and upper 32-bit halves of the output word |
| `hamming` | Mean Hamming distance to the ground truth (32 = uniform random distribution) |
| `exact` | Proportion of exact 64-bit integer matches |
| `p_early/p_full` | Accuracy on the early-exit path versus the complete loop path (compute kernel) |

## Empirical Findings

- **Learnable Features**: The early-exit path in compute `(a ^ 0x5877) + b mod 2^64` — bit $j$ of the sum depends strictly on input bits $\le j$ (carry chain), yielding $p_{\text{early}}$ noticeably higher than 0.5. An unexpected empirical observation from the initial run: the high half of the word is learned more readily than the lower half (hi32 $\approx 0.71$ vs lo32 $\approx 0.58$ in `mlp-s`), as coarse high-bit arithmetic structures present smoother gradient landscapes than precise lower-order XOR and carry bits. Floating-point branches (`q2 > 1e12`, `q2 == 0`, cast saturation) manifest as localized bitwise predicates on sign and exponent fields, which MLPs resolve easily.
- **Unlearnable Features**: The full compute execution path (SplitMix avalanche + mul/xorshift + unrolled loop) and the entire `mix` kernel (FNV-style rolling hash) — every output bit depends nonlinearly on nearly all input bits via feedback: $p_{\text{full}} \approx 0.50$ and Hamming distance $\approx 32$ across all architectures. This demonstrates the cryptographic avalanche effect of metamorphic transformation from a black-box adversarial perspective.
- **Transformer Scaling**: Self-attention over fixed bit fields does not outperform an MLP on a per-FLOP basis, as shown by the sweep ladder; a possible exception is `mix` (byte sequences), which remains inherently resistant to learning.

## Architectural Ladder

Configured via the `LADDER` definition in `train.py`:

| Rung | Architecture | Epochs | Learning Rate | Batch Size |
|---|---|---|---|---|
| `mlp-s` | MLP 256x2 (baseline) | 12 | 1e-3 | 4096 |
| `mlp-w` | MLP 1024x2 (width scaling at optimal depth) | 12 | 1e-3 | 4096 |
| `mlp-d` | MLP 256x4 (depth stress test) | 12 | 1e-3 | 4096 |
| `xf-s` | Transformer d128 L2 h4 | 8 | 3e-4 | 1024 |
| `xf-m` | Transformer d192 L3 h6 | 6 | 3e-4 | 1024 |
| `xf-l` | Transformer d256 L4 h8 | 4 | 3e-4 | 512 |

Training epochs for larger transformer models are scaled down (~56 s/epoch on 200k samples). Pass `--loss mse` for loss ablation (defaults to binary cross-entropy per bit).

## Initial Campaign Baseline (Apple Silicon M-Series, 200k train / 20k val)

| Rung | Parameters | Runtime | `bit_acc` | `exact` | `p_early` | `p_full` |
|---|---|---|---|---|---|---|
| **mlp-s** | 158k | **1.6s** | **0.6477** | 12.0% | **0.831** | 0.505 |
| `mlp-m` | 972k | 7.2s | 0.5897 | 4.1% | 0.698 | 0.505 |
| `mlp-l` | 5.6M | 23.0s | 0.5730 | 0.9% | 0.661 | 0.504 |
| `xf-s` | 319k | 116s | 0.6444 | 11.7% | 0.824 | 0.505 |
| `xf-m` | 972k | 202s | 0.6450 | 11.3% | 0.824 | 0.506 |
| `xf-l` | 2.2M | 276s | 0.6448 | **12.9%** | 0.826 | 0.504 |
| `mix: mlp` | — | <1s | 0.5006 | 0% | — | — |

Key observations:
1. `mlp-s` is the Pareto-optimal model (transformer `xf-l` is 172x more computationally expensive for comparable accuracy).
2. Transformers plateau at 0.644–0.645 despite a 7x capacity increase: attention layers extract no additional structure beyond local bit patterns.
3. Avalanche hash paths are unlearnable (loss converges exactly to $\ln 2 \approx 0.693$).

Fine-tuning MLP configurations (depth vs. width vs. learning rate):

| Configuration | `bit_acc` | Assessment |
|---|---|---|
| 256x2 | **0.6477** | Optimal trade-off |
| 1024x2 | 0.6466 | Width at depth 2 incurs minimal penalty |
| 2048x2 | 0.6200 | Excessive width (>1M parameters) degrades generalization |
| 512x3 | 0.6177 | Depth performance drop emerges at 3 layers |
| 256x4 | 0.5909 | Depth is the primary degradation factor |
| 512x4 @ lr 1e-4, 16ep | 0.6138 | Learning rate tuning does not resolve depth drop |

The learnable component behaves as a shallow two-layer function (XOR + carry chain): gradient signals attenuate with depth, a known pathology in parity-like bitwise problems. In `LADDER`, `mlp-w` tests width scaling at optimal depth, while `mlp-d` serves as a depth diagnostic probe.

## Repository Layout

```text
kernel_ref.py       Bit-exact NumPy reference implementation (ground truth)
validate_ref.py     Differential validation harness against live binaries (--fuzz protocol)
dataset.py          Sampling, bit features, and tokenizers (LSB-first order)
models.py           MLP and BitTokenTransformer models implemented in mlx.nn
train.py            CLI driver, training loops, metrics, LADDER sweep, results.jsonl logging
collect_traces.py   Build matrix runner (config x seed) for VM trace capture
train_trace.py      VM trace benchmark: next-handler prediction and cross-seed transfer
run.sh              Automated pipeline: validation -> compute sweep -> mix sweep
results/            results.jsonl persistent metric logs
traces/             Generated build binaries and execution traces (gitignored)
```

## Trace Benchmark: VM Execution Predictability (White-Box Adversary)

While the I/O benchmark measures the black-box function, the trace benchmark directly evaluates **the virtual machine execution engine**. When compiled with `ASG_VM_TRACE=1`, the native VM runner (`vm_runtime_emitter.ml`) logs the semantic opcode class at each step (tokens are canonical across builds, neutralizing opcode permutation). `collect_traces.py` generates a matrix of builds (configuration $\times$ seed), and `train_trace.py` trains a sequence model to predict subsequent handlers and measures cross-seed transfer:

```bash
python3 collect_traces.py -n 300                  # full/plain x 1001/2002 seeds
python3 train_trace.py                            # Learnability evaluation
```

Initial benchmark campaign (compute kernel, 300 test vectors, random baseline chance = 1/256):

| Build | Steps/Trace | Unigram Baseline | `nn_within` | `nn_cross` | Cross-Seed Transfer Ratio |
|---|---|---|---|---|---|
| full (CFF+MBA) 1001 | 3353 | 0.175 | 0.977 | 0.551 | 0.56 |
| full (CFF+MBA) 2002 | 3279 | 0.175 | 0.978 | 0.510 | 0.52 |
| plain 1001 | 1720 | 0.199 | 0.999 | 0.485 | 0.49 |
| plain 2002 | 1150 | 0.188 | 0.999 | 0.510 | 0.51 |

Interpretation:

- **Intra-Seed Determinism (`nn_within` $\approx 0.98–1.00$)**: A single build's trace is nearly deterministic for a sequence model. A dynamic attacker leveraging instrumentation can reconstruct the handler flow with high precision. CFF + MBA reduces predictability by only ~2 percentage points (0.999 to 0.977) while inflating trace length by 2–3x.
- **Metamorphic Seed Diversity**: Transferring a model trained on one seed to evaluate another drops accuracy from 0.98 to ~0.51. However, with the unigram baseline at 0.18, approximately 40–47% of the structural handler flow persists across rebuilds. This defines an upper bound for seed randomization improvements (e.g. dynamic handler scheduling and dispatcher whitening).
- **Targeted Hardening Vectors**: Quantifiable metrics to optimize: input-tainted CFF transitions (introducing data dependency into handler sequences), data-driven decoy insertion, and dynamic runtime dispatch diversity.

## Relevance to ASGARD Resilience

I/O learnability serves as a proxy for resilience against black-box behavioral modeling: minimizing learnable signal prevents adversaries from training surrogate models of protected logic. Trace learnability acts as a quantitative metric against dynamic and symbolic reverse engineering.
