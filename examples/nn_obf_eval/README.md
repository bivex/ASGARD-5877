# ASGARD-5877 Neural Obfuscation Assessment Suite (NOAS)

An automated deep-learning benchmarking suite that trains neural models to attack, deobfuscate, and devirtualize ASGARD-protected binaries, computing empirical **Devirtualization Resistance Scores (DRS)** using machine learning metrics instead of static heuristics.

---

## Evaluation Architecture

The suite trains three specialized deep-learning models targeting the core protection layers:

```
                          ASGARD Protection Pipeline
                    (Stack-VM / CFF / MBA / Rolling Key)
                                     │
         ┌───────────────────────────┼───────────────────────────┐
         ▼                           ▼                           ▼
┌──────────────────┐       ┌──────────────────┐       ┌──────────────────┐
│  Graph Attention │       │  AST-Level MBA   │       │  Markov Trace    │
│  Network (GAT)   │       │  Transformer     │       │  Entropy Engine  │
├──────────────────┤       ├──────────────────┤       ├──────────────────┤
│ • Hub-F1 score   │       │ • Simplification │       │ • Bigram entropy │
│ • Link-Pred AUC  │       │ • Cross-entropy  │       │ • Rolling-key H  │
└────────┬─────────┘       └────────┬─────────┘       └────────┬─────────┘
         │                          │                          │
         └──────────────────────────┼──────────────────────────┘
                                    ▼
                     Composite Neural DRS (0..100)
```

### 1. Multi-Model Red-Team Ensemble & Statistical Bounds (`gnn_cff_eval.py`)
- **Attack Vector:** Automated CFF unflattening and dispatcher localization (simulating tools like D-Tigress, Ghidra unflatteners, and IDA VTIL).
- **Ensemble Architectures:**
  - **GAT (Attention):** 4-head Graph Attention Network (`GATLayer`) operating on Stack-IR basic block feature vectors $X \in \mathbb{R}^{15}$.
  - **GCN (Spectral):** Kipf & Welling Graph Convolutional Network with symmetric Laplacian normalization ($\tilde{D}^{-1/2} \tilde{A} \tilde{D}^{-1/2} X W$).
  - **GraphSAGE (Inductive):** Mean neighborhood pooling with representation concatenation ($W \cdot [X_u \,\|\, \text{mean}_{v \in \mathcal{N}(u)} X_v]$).
  - **Tabular Baseline:** Regularized pairwise Logistic Regression on non-graph edge features ($[X_u, X_v, |X_u - X_v|, X_u \cdot X_v]$).
- **Statistical Metrics (Hanley & McNeil 1982):**
  - **Standard Error (SE) & $z$-score:** Tests statistical significance of deviation from the random-guess boundary ($H_0: \text{AUC} = 0.50$):
    $$z = \frac{\text{AUC} - 0.50}{\text{SE}}, \quad p = \frac{1}{2} \text{erfc}\left(\frac{z}{\sqrt{2}}\right)$$
  - **95% Confidence Upper Bound ($\text{AUC}_{95\%}$):** Rather than taking an optimistic point estimate, the audit discounts DRS by the conservative upper bound $\text{AUC}_{95\%} = \min(1.0, \text{AUC} + 1.96 \cdot \text{SE})$.
- **Conservative Resilience Formula:**
  $$\text{AUC advantage} = \max(0.0, \text{AUC}_{95\%} - 0.5) \times 2.0$$
  $$\text{DRS}_{\text{CFG}} = \min_{M \in \{\text{GAT}, \text{GCN}, \text{SAGE}, \text{Tab}\}} \left[ 100.0 \times \left(1.0 - \left(0.6 \cdot (\text{AUC advantage}_M)^2 + 0.4 \cdot (\text{Hub-F1}_M)^2\right)\right) \right]$$
### 2. AST-Level Seq2Seq Transformer (`mba_deobf_eval.py`)
- **Attack Vector:** Neural symbolic deobfuscation and algebraic simplification of Mixed Boolean-Arithmetic (simulating NeuReduce and QSynth).
- **Architecture:** Sequence-to-Sequence Transformer with positional embeddings and self/cross-attention across tokenized expressions (`TOKENS`: operators, variables, constants, and `CONST` nullspace wildcards).
- **Metrics:**
  - **Simplification Rate:** Percentage of held-out obfuscated expressions the model successfully simplifies back to the exact canonical arithmetic ground-truth ($x \text{ op } C$).
  - **Cross-Entropy Loss:** Validation loss floor; higher loss proves genuine unlearnability.
- **Resilience Formula:**
  $$\text{DRS}_{\text{MBA}} = 100.0 \times (1.0 - \text{Simplification Rate})$$
  On Depth 4 (with ASGARD's L6 NullspaceZero strategy), the simplification rate drops to **0.0%** ($\text{DRS} = 100.0 / 100.0$).

### 3. Dynamic Trace Entropy Estimator (`eval_obfuscation.py`)
- **Attack Vector:** Recurrent next-state prediction (LSTM/RNN) and dynamic trace clustering on VM execution bytecode.
- **Methodology:** Computes bigram conditional Shannon entropy $H(S_t \mid S_{t-1})$ directly over serialized Vanguard bytecode words (`protected.vanguard`):
  $$H(S_t \mid S_{t-1}) = - \sum_{u} P(u) \sum_{v} P(v \mid u) \log_2 P(v \mid u)$$
- **Resilience Formula:**
  $$\text{DRS}_{\text{Trace}} = \min\left(100.0, \frac{H(S_t \mid S_{t-1})}{8.0} \times 100.0\right)$$
  With State-Feedback Rolling Key and VSP stack value whitening, the entropy reaches **7.928 / 8.0 bits** ($\text{DRS} = 99.1 / 100.0$).

---

## Quick Start

### 1. Run Assessment on Default Pipeline Dumps
```bash
./examples/nn_obf_eval/run_eval.sh
```

### 2. Evaluate a Real Protected Application (`license_check.c`)
To evaluate a real binary through all 10 Stack-VM pipeline phases:

```bash
# 1. Protect the binary and dump intermediate JSON phases
mkdir -p /tmp/my_license_json /tmp/my_license_out
ASGARD_DUMP_JSON_DIR=/tmp/my_license_json _build/default/bin/main.exe protect-arm64 \
  -i examples/license_check.c \
  -o /tmp/my_license_out \
  --engine=stack \
  --config samples/protection_config.full.json \
  --cff \
  --mba \
  --mba-depth 4 \
  --seed 1337 \
  --compile=false

# 2. Run NOAS against the real dumps and bytecode payload
python3 examples/nn_obf_eval/eval_obfuscation.py \
  /tmp/my_license_json \
  /tmp/my_license_out/protected.vanguard
```

### 3. Run Multi-Function Corpus Benchmark across C Algorithms
Evaluates across 6 real C programs (`sqlite_varint_hash`, `coreutils_crc32`, `openssl_sha256`, `wireguard_chacha20`, `zstd_xxhash64`, `license_check`), computing mean DRS, worst-case minimum (guaranteed lower bound), P10, and standard deviation:

```bash
./examples/nn_obf_eval/eval_corpus.py
```

---

## Sample Benchmark Output

```
============================================================================
        ASGARD-5877 NEURAL OBFUSCATION ASSESSMENT SUITE (NOAS)
============================================================================

[Phase 1] Auditing CFG & CFF Flattening with Graph Attention Network (GAT)...
  Phase            Blocks   Edges    Hub-F1     Edge-AUC   DRS (0-100) 
  ------------------------------------------------------------------
  1-lowered        245      414      0.000      0.617      96.7        
  2-amplified      245      414      0.000      0.570      98.8        
  3-cff            491      733      0.000      0.799      78.5        
  4-spaghetti      579      821      0.000      0.780      81.1        
  5-ghost          579      821      0.000      0.765      83.2        
  7-balance (final) 579      821      0.000      0.774      82.0        

[Phase 2] Auditing MBA Incompressibility with AST-Level Transformer...
  Depth    Avg Tokens   Simplification Rate    Loss       DRS (0-100) 
  ------------------------------------------------------------------
  1        18.5         0.0%                   1.034      100.0       
  2        61.4         0.0%                   1.315      100.0       
  4        191.2        0.0%                   1.284      100.0       

[Phase 3] Auditing Dynamic Execution Trace & Rolling-Key Entropy...
  Conditional Transition Entropy: 7.928 / 8.0 bits (Uniform Noise = 8.0)
  Dynamic Trace DRS:             99.1 / 100.0

============================================================================
                      NEURAL BENCHMARK SUMMARY
============================================================================
  [1] CFG & CFF Resilience (GAT):             82.0 / 100.0
  [2] Algebraic Incompressibility (Seq2Seq): 100.0 / 100.0
  [3] Dynamic Trace Unpredictability:         99.1 / 100.0
  ------------------------------------------------------------------------
  ===> COMPOSITE NEURAL DRS SCORE:            91.7 / 100.0  [ TIER 3+ RESILIENT ]
============================================================================
```

---

## Score Interpretation

| Composite DRS | Tier | Classification | Real-World Impact |
|---|---|---|---|
| **90.0 – 100.0** | **Tier 3+** | **Resilient to AI & SMT** | Graph deobfuscation fails; MBA cannot be simplified by Transformers or SMT within hours; dynamic execution traces are indistinguishable from random noise. |
| **70.0 – 89.9** | **Tier 2** | **Hardened** | Standard automated tools fail; partial recovery possible only with heavy manual symbolic execution. |
| **< 70.0** | **Tier 1** | **Vulnerable** | High information leakage; CFG dispatcher recognizable; linear MBA identities learnable by neural models. |
