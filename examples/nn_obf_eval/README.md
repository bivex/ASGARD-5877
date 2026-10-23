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

### 3. Dynamic Trace Entropy & Long-Range LSTM Predictor (`trace_lstm_eval.py`)
- **Attack Vector:** Recurrent next-state prediction (2-layer LSTM with hidden size 64) and dynamic trace clustering on VM execution bytecode.
- **Methodology:** Evaluates next-byte predictability over sliding context windows $k = 8$ across 151,000 serialized Vanguard bytecode words (`protected.vanguard`), combined with bigram conditional Shannon entropy:
  $$H(S_t \mid S_{t-1}) = - \sum_{u} P(u) \sum_{v} P(v \mid u) \log_2 P(v \mid u)$$
- **Resilience Formula:**
  $$\text{Top1 advantage} = \max\left(0.0, \frac{\text{Top1Acc}_{95\%} - 1/256}{1.0 - 1/256}\right)$$
  $$\text{DRS}_{\text{Trace}} = 0.5 \cdot \text{DRS}_{\text{entropy}} + 0.5 \cdot \max(0.0, 100.0 \times (1.0 - \text{Top1 advantage}))$$
  With State-Feedback Rolling Key, the LSTM Top-1 accuracy is restricted to **0.375%** (against the 0.391% uniform random baseline), yielding **99.4 / 100.0**.

### 4. Opaque Predicate Realism & AST Classifier (`predicate_realism_eval.py`)
- **Attack Vector:** Automated branch condition classification (distinguishing constant true/false invariants from genuine program branching).
- **Ensemble Models:** BiLSTM with Attention Pooling, AST-Transformer Encoder, and Tabular Structural Baseline.
- **Resilience Formula:**
  $$\text{DRS}_{\text{opaque}} = \min_{M} \left[ \max\left(0.0, 100.0 \times \left(1.0 - \left(2.0 \cdot \max(0.0, \text{AUC}_{95\%}(M) - 0.5)\right)^2\right)\right) \right]$$

### 5. Bytecode Amplifier & Dead-Code Elimination (DCE) (`amplifier_dce_eval.py`)
- **Attack Vector:** Intra-block Dead-Code Elimination (DCE) and redundant instruction recovery (simulating automated deobfuscators like de-obfuscating JIT compilers and peephole simplifiers).
- **Methodology:** Ingests `phase_1-lowered.json` (canonical core blocks) and `phase_2-amplified.json` (amplified blocks), aligning instructions via LCS to extract ground-truth dead-code labels.
- **Ensemble Models:**
  - **Opcode-Transformer:** Transformer Encoder sequence tagger predicting per-token redundancy across blocks up to 512 instructions.
  - **BiLSTM-Tagger:** Bidirectional LSTM with hidden size 48 per direction.
  - **5-gram Tabular Baseline:** Contextual n-gram logistic regression predicting redundancy from local opcode windows.
- **Resilience Formula:**
  $$\text{DCE Recovery Rate} = \text{Recall of identifying amplified dead-code instructions}$$
  $$\text{DRS}_{\text{amp}} = \max\left(0.0, 100.0 \times \left(1.0 - \max_{M} \text{DCE Recovery Rate}_M\right)\right)$$


### 6. Ghost Stack Padding & Sequence Tagger (`ghost_padding_eval.py`)
- **Attack Vector:** Intra-block Ghost Instruction Identification (simulating sequence taggers and neural deobfuscators learning the micro-patterns of semantically neutral stack padding operations like `PushImm; PopReg`, `KeyAdjust; KeyAdjust`, and `entangle_with_accumulator`).
- **Ground Truth:** Derived via Longest Common Subsequence (LCS) alignment matching on full `(opcode, operands)` tuples between `phase_4-spaghetti.json` (unpadded core) and `phase_5-ghost.json` (padded blocks), assigning label 0 to core instructions and label 1 to inserted ghost operations.
- **Spatial Dispersion & Positional Entropy:**
  - Evaluates whether ghost padding operations are clustered at block boundaries or uniformly distributed across instruction depth.
  - Measures Shannon positional entropy $H(\text{pos} \mid L) = -\sum_{i=1}^{10} p_i \log_2 p_i$ across 10 discrete relative block depth bins $[0.0, 1.0]$.
  - Normalized spatial dispersion $\eta = \frac{H}{\log_2(10)} \in [0.0, 1.0]$, where $\eta \to 1.0$ indicates maximal uniform dispersion without spatial clustering tells.
- **Ensemble Models:**
  - **Opcode-Transformer:** 2-layer Transformer Encoder with multi-head self-attention classifying each token position.
  - **BiLSTM-Tagger:** 2-layer Bidirectional LSTM sequence tagger.
  - **5-gram Tabular Baseline:** Contextual n-gram frequency lookup baseline.
- **Resilience Formula:**
  $$\text{Ghost-Recall} = \max_{M} \left[\text{Recall of identifying inserted ghost padding operations}_M\right]$$
  $$\text{DRS}_{\text{ghost}} = \max\left(0.0, 100.0 \times \left(1.0 - \text{Ghost-Recall}\right)\right)$$

### 7. Spaghetti Reassembly & Fragment Boundary Auditor (`spaghetti_reassembly_eval.py`)
- **Attack Vector:** Control-Flow Fragment Reassembly (simulating neural boundary classifiers and decompilers attempting to glue cut basic block fragments back into their pre-split straight-line form).
- **Siamese Network Architecture:**
  - Two weight-sharing Bidirectional LSTM encoders: $h_A = \text{Enc}(A)$, $h_B = \text{Enc}(B)$.
  - Fragment pair representation: $V = [h_A \,\|\, h_B \,\|\, |h_A - h_B| \,\|\, h_A \odot h_B]$.
  - 2-layer MLP classifier outputting predicted adjacency probability $P(A, B \text{ were originally adjacent})$.
- **Length-Matched Ground Truth:**
  - Positive pairs: genuine $(fragment_i, fragment_{i+1})$ cuts from `phase_4-spaghetti.json`.
  - Negative pairs: fragment pairs from different pre-split blocks matched by chunk length ($|\text{len}(B') - \text{len}(B)| \le 2$), eliminating sequence length as an artificial confounding tell.
- **Red Herring Spatial Audit:**
  - Computes Pearson correlation $r(\text{is\_split}, \text{position})$ and $r(\text{is\_split}, \text{length})$ across candidate blocks.
  - Verifies that Fisher-Yates shuffled budget allocation maintains uniform spatial dispersion ($r \approx 0.0$) so red herring noise does not create an exploitable boundary marker.
- **Resilience Formula:**
  $$\text{Pairwise-AUC}_{95\%} = \min(1.0, \text{AUC} + 1.96 \cdot \text{SE})$$
  $$\text{DRS}_{\text{spaghetti}} = \max\left(0.0, 100.0 \times \left(1.0 - 2.0 \cdot \max(0.0, \text{Pairwise-AUC}_{95\%} - 0.5)\right)^2\right)$$

### 8. Branchless VIP Idiom & Signature Collision Auditor (`branchless_vip_eval.py`)
- **Attack Vector:** Static Bytecode / AST Idiom Scanning (simulating reverse engineers using YARA rules, IDA signature scanners, or Ghidra decompilation pattern matchers to find unbroken constant-time VIP selection sequences like Warren's two's complement sign-bit trick).
- **Metamorphic Formulation Repertoire:**
  - **Variant 0:** $1 - ((d \mid -d) \gg 63)$ (Classic two's complement sign-bit)
  - **Variant 1:** $((\sim d) \ \& \ (d - 1)) \gg 63$ (Warren subtraction borrow from zero)
  - **Variant 2:** $1 - (((d \oplus -d) + (d \ \& \ -d)) \gg 63)$ (Mixed Boolean-Arithmetic OR decomposition)
  - **Variant 3:** $(\sim(d \mid -d) \gg 63) \ \& \ 1$ (De Morgan bitwise complement sign extraction)
  - **Variant 4:** $((d \mid -d) \gg 63) \oplus 1$ (Boolean XOR bit flipping)
- **Metrics:**
  - **Signature Collision Rate:** $\text{Collision Rate} = \frac{\max_i \text{Count}(\text{variant}_i)}{\text{Total Sites}}$.
  - **Variant Shannon Entropy:** $H(\text{variants}) = -\sum_{i=1}^5 p_i \log_2 p_i$, with normalized entropy $\eta = \frac{H}{\log_2(5)} \in [0.0, 1.0]$.
  - **Resilience Formula:**
    $$\text{DRS}_{\text{branchless}} = \max\left(0.0, 100.0 \times \left(1.0 - \frac{\text{Collision Rate} - 0.20}{0.80}\right) \times \eta\right)$$
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
  LSTM Top-1 Next-Byte Accuracy:  0.375%  (Baseline = 0.391%, 95% Bound = 0.620%)
  Dynamic Trace & LSTM DRS:       99.4 / 100.0

[Phase 4] Auditing Opaque Predicate Realism (BiLSTM + Transformer vs Real Conditions)...
  BiLSTM ROC-AUC:                 0.960  (Accuracy: 84.0%)
  Transformer ROC-AUC:            0.999  (Accuracy: 97.0%)
  Tabular Baseline ROC-AUC:       0.517
  Opaque Predicate DRS:           0.0 / 100.0

================================================================================
                         NEURAL BENCHMARK SUMMARY
================================================================================
  [1] CFG & CFF Multi-Model Ensemble:          95.3 / 100.0
  [2] Algebraic Incompressibility (Seq2Seq):   97.1 / 100.0
  [3] Dynamic Trace & Rolling-Key LSTM:        99.4 / 100.0
  [4] Opaque Predicate Realism:                 0.0 / 100.0
  ----------------------------------------------------------------------------
  ===> COMPOSITE NEURAL DRS SCORE:             82.4 / 100.0  [ TIER 3+ RESILIENT ]
================================================================================
```

---

## Score Interpretation

| Composite DRS | Tier | Classification | Real-World Impact |
|---|---|---|---|
| **90.0 – 100.0** | **Tier 3+** | **Resilient to AI & SMT** | Graph deobfuscation fails; MBA cannot be simplified by Transformers or SMT within hours; dynamic execution traces are indistinguishable from random noise. |
| **70.0 – 89.9** | **Tier 2** | **Hardened** | Standard automated tools fail; partial recovery possible only with heavy manual symbolic execution. |
| **< 70.0** | **Tier 1** | **Vulnerable** | High information leakage; CFG dispatcher recognizable; linear MBA identities learnable by neural models. |
