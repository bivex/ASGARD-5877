# ASGARD-5877 Neural Obfuscation Assessment Suite (NOAS)

An automated deep-learning benchmarking suite that trains neural models to attack and deobfuscate ASGARD-protected binaries, measuring **Devirtualization Resistance Score (DRS)** using machine learning metrics instead of static heuristics.

## Architectures

1. **Graph Attention Network (GAT)** (`gnn_cff_eval.py`):
   - Multi-head attention message-passing over Stack-IR Control Flow Graphs (CFG).
   - Ingests phase dumps (`dump_pipeline.exe`).
   - Evaluates:
     - **Dispatcher Hub Detection (Hub-F1)**: Can a GNN locate the CFF dispatcher node among hundreds of blocks?
     - **Link Prediction (Edge-AUC)**: Can a GNN infer the true sequential control-flow transitions between basic blocks?

2. **AST-Level Seq2Seq Transformer** (`mba_deobf_eval.py`):
   - Encoder-Decoder Transformer with self-attention and cross-attention.
   - Evaluates whether neural networks can learn inverse polynomial / bitwise rewrites of Mixed Boolean-Arithmetic (MBA) across depths 1 to 4.

3. **Trace Entropy Predictor** (`eval_obfuscation.py`):
   - Bigram conditional Shannon entropy over rolling-key handler transitions.

## Quick Start

```bash
./examples/nn_obf_eval/run_eval.sh
```
