#!/usr/bin/env python3
"""
ASGARD-5877 Neural Obfuscation Assessment Suite (NOAS)
=====================================================
Unified neural benchmarking suite evaluating the machine-learning resilience
of ASGARD code obfuscation and virtual machine hardening.

Combines:
  1. Graph Attention Network (GAT) for CFG / CFF / Dispatcher Deobfuscation
  2. Sequence-to-Sequence AST Transformer for MBA Algebraic Incompressibility
  3. Rolling-Key Markov Trace Predictability Estimator
"""
import os
import sys
import math
import subprocess
import warnings
warnings.filterwarnings("ignore")

from gnn_cff_eval import parse_cfg_json, audit_cfg_phase
from mba_deobf_eval import audit_mba_depth
from trace_lstm_eval import audit_trace_lstm
from predicate_realism_eval import audit_opaque_predicates
from amplifier_dce_eval import audit_amplifier_dce
from ghost_padding_eval import audit_ghost_padding
from spaghetti_reassembly_eval import audit_spaghetti_reassembly
from branchless_vip_eval import audit_branchless_vip

def run_pipeline_dump(out_dir="/tmp/pipeline_dump"):
    """Builds and runs dump_pipeline.exe to generate fresh JSON phase dumps."""
    bin_path = "_build/default/examples/pipeline_dump/dump_pipeline.exe"
    if not os.path.exists(bin_path):
        subprocess.run(["dune", "build", "examples/pipeline_dump/dump_pipeline.exe"], check=True)
    subprocess.run([bin_path, out_dir], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
    return out_dir


def evaluate_trace_entropy(seed=0x3CD4810B2EEB0926, bytecode_path=None, steps=50000):
    """Measures next-handler predictability and Shannon entropy of the rolling key or bytecode."""
    if bytecode_path and os.path.exists(bytecode_path):
        with open(bytecode_path, "rb") as f:
            data = f.read()
        history = list(data)
    else:
        history = []
        k = seed
        for i in range(steps):
            k = ((k * 0x9E3779B97F4A7C15) ^ (k >> 29)) & 0xFFFFFFFFFFFFFFFF
            handler_slot = (k ^ (i * 0x5D + 0x33)) & 0xFF
            history.append(handler_slot)

    # Bigram conditional entropy: H(S_t | S_{t-1})
    counts = {}
    transitions = {}
    for i in range(len(history) - 1):
        u, v = history[i], history[i + 1]
        counts[u] = counts.get(u, 0) + 1
        if u not in transitions:
            transitions[u] = {}
        transitions[u][v] = transitions[u].get(v, 0) + 1

    cond_entropy = 0.0
    for u, trans in transitions.items():
        p_u = counts[u] / (len(history) - 1)
        h_u = 0.0
        for v, cnt in trans.items():
            p_v_given_u = cnt / counts[u]
            h_u -= p_v_given_u * math.log2(p_v_given_u)
        cond_entropy += p_u * h_u

    max_entropy = 8.0 # log2(256)
    entropy_ratio = cond_entropy / max_entropy
    drs_trace = min(100.0, max(0.0, entropy_ratio * 100.0))
    return {
        "cond_entropy": cond_entropy,
        "max_entropy": max_entropy,
        "drs_trace": drs_trace,
        "samples": len(history)
    }

def main():
    import math
    print("=" * 76)
    print("        ASGARD-5877 NEURAL OBFUSCATION ASSESSMENT SUITE (NOAS)")
    print("=" * 76)

    # 1. Pipeline CFG Evaluation with GAT
    print("\n[Phase 1] Auditing CFG & CFF Flattening with Graph Attention Network (GAT)...")
    if len(sys.argv) > 1 and os.path.isdir(sys.argv[1]):
        dump_dir = sys.argv[1]
    else:
        dump_dir = run_pipeline_dump()

    bytecode_path = sys.argv[2] if len(sys.argv) > 2 else None
    if not bytecode_path:
        candidate = os.path.join(os.path.dirname(dump_dir), "real_license_out", "protected.vanguard")
        if os.path.exists(candidate):
            bytecode_path = candidate

    cfg_phases = ["1-lowered", "3-cff", "4-spaghetti", "5-ghost", "7-balance", "7-balance_(final)"]
    cfg_results = []
    print(f"  {'Phase':<16} {'Blocks':<8} {'Edges':<8} {'Hub-F1':<10} {'Edge-AUC':<10} {'DRS (0-100)':<12}")
    print("  " + "-" * 66)
    for p in cfg_phases:
        fpath = os.path.join(dump_dir, f"phase_{p}.json")
        if os.path.exists(fpath):
            cfg = parse_cfg_json(fpath)
            res = audit_cfg_phase(cfg, epochs=30)
            if res:
                cfg_results.append(res)
                print(f"  {res['phase']:<16} {res['blocks']:<8} {res['edges']:<8} {res['hub_f1']:<10.3f} {res['edge_auc']:<10.3f} {res['drs_cff']:<12.1f}")

    final_cfg_drs = cfg_results[-1]["drs_cff"] if cfg_results else 50.0

    # 2. MBA Evaluation with Transformer
    print("\n[Phase 2] Auditing MBA Incompressibility with AST-Level Transformer...")
    print(f"  {'Depth':<8} {'Avg Tokens':<12} {'Simplification Rate':<22} {'Loss':<10} {'DRS (0-100)':<12}")
    print("  " + "-" * 66)
    mba_results = []
    for d in [1, 2, 4]:
        res = audit_mba_depth(depth=d, epochs=25)
        mba_results.append(res)
        print(f"  {res['depth']:<8} {res['avg_tokens']:<12.1f} {res['exact_rate']*100:<20.1f}% {res['val_loss']:<10.3f} {res['drs_mba']:<12.1f}")

    final_mba_drs = mba_results[-1]["drs_mba"] if mba_results else 50.0

    # 3. Dynamic Trace Entropy & Long-Range LSTM Predictor
    print("\n[Phase 3] Auditing Dynamic Execution Trace & Rolling-Key Entropy...")
    trace_res = evaluate_trace_entropy(bytecode_path=bytecode_path)
    lstm_res = audit_trace_lstm(bytecode_path=bytecode_path, epochs=10)
    combined_trace_drs = 0.5 * trace_res["drs_trace"] + 0.5 * lstm_res["drs_trace_lstm"]

    print(f"  Conditional Transition Entropy: {trace_res['cond_entropy']:.3f} / {trace_res['max_entropy']:.1f} bits (Uniform Noise = 8.0)")
    print(f"  LSTM Top-1 Next-Byte Accuracy:  {lstm_res['top1_acc']*100:.3f}%  (Baseline = 0.391%, 95% Bound = {lstm_res['top1_upper_95']*100:.3f}%)")
    print(f"  Dynamic Trace & LSTM DRS:       {combined_trace_drs:.1f} / 100.0")

    # 4. Bytecode Amplifier & Dead-Code Elimination (DCE)
    print("\n[Phase 4] Auditing Bytecode Amplifier & Opcode-Level Dead-Code Recovery (Seq2Seq / Transformer)...")
    amp_res = audit_amplifier_dce(dump_dir=dump_dir, epochs=15)
    print(f"  Total Instructions:             Before={amp_res['ops_before']} -> After={amp_res['ops_after']} ({amp_res['redundancy_ratio']*100:.1f}% amplified)")
    print(f"  Opcode-Transformer DCE F1:      {amp_res['tf']['f1']:.3f}  (Recall/Recovery: {amp_res['tf']['recovery_rate']*100:.1f}%)")
    print(f"  BiLSTM Tagger DCE F1:           {amp_res['lstm']['f1']:.3f}  (Recall/Recovery: {amp_res['lstm']['recovery_rate']*100:.1f}%)")
    print(f"  5-gram Tabular Baseline F1:     {amp_res['tab']['f1']:.3f}")
    print(f"  Amplifier DCE Resilience (DRS): {amp_res['drs_amp']:.1f} / 100.0")

    # 5. Opaque Predicate Realism & AST Classifier
    print("\n[Phase 5] Auditing Opaque Predicate Realism (BiLSTM + Transformer vs Real Conditions)...")
    op_res = audit_opaque_predicates(n_samples=400, epochs=25)
    print(f"  BiLSTM ROC-AUC:                 {op_res['bilstm_auc']:.3f}  (Accuracy: {op_res['bilstm_acc']*100:.1f}%)")
    print(f"  Transformer ROC-AUC:            {op_res['tf_auc']:.3f}  (Accuracy: {op_res['tf_acc']*100:.1f}%)")
    print(f"  Tabular Baseline ROC-AUC:       {op_res['tab_auc']:.3f}")
    print(f"  Opaque Predicate DRS:           {op_res['drs_opaque']:.1f} / 100.0")
    # 6. Ghost Stack Padding Sequence Tagger Audit
    print("\n[Phase 6] Auditing Ghost Stack Padding (Sequence Tagger vs Spatial Dispersion)...")
    ghost_res = audit_ghost_padding(dump_dir=dump_dir, epochs=15)
    print(f"  Ghost Ops Injected:             +{ghost_res['ghost_ratio']*100:.1f}% ({ghost_res['ghost_ops']} ghost ops)")
    print(f"  Positional Entropy:             H={ghost_res['positional_entropy']:.3f} / {ghost_res['max_positional_entropy']:.3f} bits (Normalized: {ghost_res['normalized_entropy']:.3f})")
    print(f"  Transformer Ghost Recall:       {ghost_res['tf']['recall']*100:.1f}%  (F1: {ghost_res['tf']['f1']:.3f})")
    print(f"  BiLSTM Tagger Ghost Recall:     {ghost_res['lstm']['recall']*100:.1f}%  (F1: {ghost_res['lstm']['f1']:.3f})")
    print(f"  5-gram Context Baseline Recall: {ghost_res['tab']['recall']*100:.1f}%")
    print(f"  Ghost Padding DRS:              {ghost_res['drs_ghost']:.1f} / 100.0")

    # 7. Spaghetti Reassembly & Fragment Boundary Audit
    print("\n[Phase 7] Auditing Spaghetti Splitting & Fragment Reassembly (Siamese Network)...")
    spagh_res = audit_spaghetti_reassembly(dump_dir=dump_dir, epochs=20)
    print(f"  Fragments Synthesized:          {spagh_res['total_cff_blocks']} -> {spagh_res['total_spaghetti_blocks']} (+{spagh_res['split_count']} fragments)")
    print(f"  Length-Matched Pairs:           {spagh_res['split_count']} positive (adjacent) vs {spagh_res['split_count']} negative (inter-block)")
    print(f"  Red Herring Correlation:        r(is_split, position)={spagh_res['r_pos']:+.3f}, r(is_split, length)={spagh_res['r_len']:+.3f}")
    print(f"  Siamese Reassembly Pairwise-AUC:{spagh_res['auc']:>6.3f}  (Accuracy: {spagh_res['acc']*100:.1f}%)")
    print(f"  Spaghetti Reassembly DRS:       {spagh_res['drs_spaghetti']:.1f} / 100.0")
    # 8. Branchless VIP Idiom Collision & Metamorphism Audit
    print("\n[Phase 8] Auditing Constant-Time Branchless VIP Idioms against Pattern Matchers...")
    vip_res = audit_branchless_vip(target_path=dump_dir)
    print(f"  Branchless VIP Sites:           {vip_res['total_sites']}")
    print(f"  Signature Entropy:              H={vip_res['entropy']:.3f} / {vip_res['max_entropy']:.3f} bits (Normalized: {vip_res['norm_entropy']:.3f})")
    print(f"  Max Idiom Collision Rate:       {vip_res['collision_rate']*100:.1f}%")
    print(f"  Branchless VIP DRS:             {vip_res['drs_branchless']:.1f} / 100.0")

    # 9. Composite Assessment Score
    composite_drs = (
        (0.20 * final_cfg_drs)
        + (0.15 * final_mba_drs)
        + (0.15 * combined_trace_drs)
        + (0.15 * amp_res["drs_amp"])
        + (0.10 * op_res["drs_opaque"])
        + (0.10 * ghost_res["drs_ghost"])
        + (0.10 * spagh_res["drs_spaghetti"])
        + (0.05 * vip_res["drs_branchless"])
    )

    print("\n" + "=" * 80)
    print("                         NEURAL BENCHMARK SUMMARY")
    print("=" * 80)
    print(f"  [1] CFG & CFF Multi-Model Ensemble:         {final_cfg_drs:>5.1f} / 100.0")
    print(f"  [2] Algebraic Incompressibility (Seq2Seq):  {final_mba_drs:>5.1f} / 100.0")
    print(f"  [3] Dynamic Trace & Rolling-Key LSTM:       {combined_trace_drs:>5.1f} / 100.0")
    print(f"  [4] Bytecode Amplifier DCE Resilience:      {amp_res['drs_amp']:>5.1f} / 100.0")
    print(f"  [5] Opaque Predicate Realism:               {op_res['drs_opaque']:>5.1f} / 100.0")
    print(f"  [6] Ghost Stack Padding Resilience:         {ghost_res['drs_ghost']:>5.1f} / 100.0")
    print(f"  [7] Spaghetti Fragment Reassembly:          {spagh_res['drs_spaghetti']:>5.1f} / 100.0")
    print(f"  [8] Branchless VIP Metamorphism:            {vip_res['drs_branchless']:>5.1f} / 100.0")
    print("  " + "-" * 76)
    def tier_label(drs):
        if drs >= 90.0: return "TIER 3+"
        elif drs >= 70.0: return "TIER 2"
        else: return "TIER 1"
    print(f"  ===> COMPOSITE NEURAL DRS SCORE:            {composite_drs:>5.1f} / 100.0  [ {tier_label(composite_drs)} ]")
    print("=" * 80 + "\n")
if __name__ == "__main__":
    main()
