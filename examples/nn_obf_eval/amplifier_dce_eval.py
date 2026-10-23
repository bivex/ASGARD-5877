#!/usr/bin/env python3
"""
ASGARD-5877 Bytecode Amplifier & Dead-Code Elimination (DCE) Evaluator
=====================================================================
Audits intra-block opcode sequence redundancy and resilience against
neural Dead-Code Elimination (DCE).

Unlike topological CFF flattening (which alters the control-flow graph),
the Bytecode Amplifier inflates instructions *within* basic blocks via:
 - Horner scheme polynomial constant synthesis
 - Invertible modular ring twists (k_odd * k_inv == 1 mod 2^64)
 - Carry cascades and expander chord work vectors

Attack:
 - Opcode Sequence Transformer (Seq2Seq / Sequence Tagging)
 - BiLSTM Sequence Tagger
 - Local 5-gram Tabular Baseline
Task:
 - Predict for each instruction in an amplified block whether it is
   redundant / removable by DCE (label 1) or core semantic (label 0).
Metric:
 - DCE Recovery Rate = Recall of identifying amplified dead-code instructions
 - DRS_amp = 100.0 * (1.0 - DCE_recovery_rate)
"""

import os
import sys
import json
import math
import random
import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F

OPCODES = [
    "<PAD>", "PushImm", "PushReg", "PopReg", "ReadMem", "WriteMem",
    "Add", "Sub", "Mul", "Nor", "Nand", "Shl", "Shr", "Sar", "Div", "Idiv",
    "AddImm", "SubImm", "AddImmImm", "SubImmImm", "SetRegImm", "AddRegImm",
    "Cmp", "Test", "Setcc", "Cmov", "PushFlags", "PopFlags", "JmpRel", "JccRel",
    "Exit", "CallExtern", "ResolveSym", "KeyAdjust", "KeyFeedback", "Dup", "Dup2", "Rot", "Swap",
    "<UNK>"
]
OP2ID = {op: i for i, op in enumerate(OPCODES)}
ID2OP = {i: op for i, op in enumerate(OPCODES)}
PAD_ID = OP2ID["<PAD>"]
VOCAB_SIZE = len(OPCODES)


class OpcodeDCETransformer(nn.Module):
    """Transformer Encoder for intra-block instruction-level sequence tagging."""
    def __init__(self, vocab_size=VOCAB_SIZE, d_model=48, nhead=4, num_layers=2, max_len=512):
        super().__init__()
        self.emb = nn.Embedding(vocab_size, d_model)
        self.pos_emb = nn.Embedding(max_len, d_model)
        layer = nn.TransformerEncoderLayer(d_model=d_model, nhead=nhead, dim_feedforward=96, batch_first=True)
        self.encoder = nn.TransformerEncoder(layer, num_layers=num_layers)
        self.fc = nn.Sequential(
            nn.Linear(d_model, 24),
            nn.ReLU(),
            nn.Linear(24, 1)
        )

    def forward(self, x):
        B, L = x.size()
        pos = torch.arange(L, device=x.device).unsqueeze(0).expand(B, -1)
        src = self.emb(x) + self.pos_emb(pos)
        padding_mask = (x == PAD_ID)
        out = self.encoder(src, src_key_padding_mask=padding_mask)
        return self.fc(out).squeeze(-1)


class OpcodeDCELSTM(nn.Module):
    """Bidirectional LSTM sequence tagger for instruction-level dead-code classification."""
    def __init__(self, vocab_size=VOCAB_SIZE, embed_dim=32, hidden_dim=48, num_layers=2):
        super().__init__()
        self.emb = nn.Embedding(vocab_size, embed_dim)
        self.lstm = nn.LSTM(embed_dim, hidden_dim, num_layers=num_layers, batch_first=True, bidirectional=True)
        self.fc = nn.Linear(hidden_dim * 2, 1)

    def forward(self, x):
        e = self.emb(x)
        out, _ = self.lstm(e)
        return self.fc(out).squeeze(-1)


def lcs_align_block(ops_before, ops_after):
    """Windowed alignment marking core ops (0) vs amplified dead code (1).

    Uses a bounded lookahead window to prevent non-matching transformations
    (e.g. Horner polynomial expansions of PushImm) from permanently freezing
    subsequent alignment across the block.
    """
    m, n = len(ops_before), len(ops_after)
    labels = [1] * n  # default: 1 = amplified/dead code
    j_last = 0
    matched = 0
    for i in range(m):
        found_j = -1
        for j in range(j_last, min(n, j_last + 50)):
            if ops_before[i] == ops_after[j]:
                found_j = j
                break
        if found_j != -1:
            labels[found_j] = 0
            j_last = found_j + 1
            matched += 1
    return labels, matched


def extract_dataset_from_dumps(dump_dir):
    """Ingests input phase dump and phase_2-amplified.json to extract block instruction pairs.

    Prefers phase_2a-pre-superop.json as the direct input to the amplifier pass,
    falling back to phase_1-lowered.json.
    """
    f1_pref = os.path.join(dump_dir, "phase_2a-pre-superop.json")
    f1_fallback = os.path.join(dump_dir, "phase_1-lowered.json")
    f1 = f1_pref if os.path.exists(f1_pref) else f1_fallback
    f2 = os.path.join(dump_dir, "phase_2-amplified.json")

    if not (os.path.exists(f1) and os.path.exists(f2)):
        return None

    with open(f1) as p1, open(f2) as p2:
        d1 = json.load(p1)
        d2 = json.load(p2)

    def op_key(o):
        args = o.get("args", [])
        return (o["op"], tuple(str(a) for a in args))
    b1_map = {b["id"]: [op_key(o) for o in b.get("ops", [])] for b in d1.get("blocks", [])}
    b2_list = d2.get("blocks", [])

    dataset = []
    total_ops_before = 0
    total_ops_after = 0
    total_matched = 0

    for b2 in b2_list:
        bid = b2["id"]
        ops_after = [op_key(o) for o in b2.get("ops", [])]
        ops_before = b1_map.get(bid, [])

        if len(ops_after) == 0:
            continue

        labels, matched = lcs_align_block(ops_before, ops_after)
        dataset.append((ops_after, labels))

        total_ops_before += len(ops_before)
        total_ops_after += len(ops_after)
        total_matched += matched

    label_balance = (total_ops_after - total_matched) / max(1, total_ops_after)
    return {
        "dataset": dataset,
        "ops_before": total_ops_before,
        "ops_after": total_ops_after,
        "matched_core": total_matched,
        "redundant_ops": total_ops_after - total_matched,
        "redundancy_ratio": label_balance,
        "label_balance": label_balance,
    }


def synthesize_amplified_dataset(n_blocks=150, seed=1337):
    """Synthetic dataset fallback modeling Horner polynomial and ring twist expansions."""
    random.seed(seed)
    dataset = []
    core_ops_pool = ["PushReg", "PopReg", "Add", "Sub", "Cmp", "JmpRel", "JccRel", "ReadMem", "WriteMem"]

    for _ in range(n_blocks):
        core_len = random.randint(8, 25)
        core_ops = [(random.choice(core_ops_pool), ()) for _ in range(core_len)]

        # Expand with Horner polynomials and ring twists
        ops_after = []
        labels = []

        for op_key_item in core_ops:
            op = op_key_item[0]
            # 70% chance to expand around this instruction
            if random.random() < 0.70:
                expansion_type = random.choice([0, 1, 2])
                if expansion_type == 0:
                    # Horner polynomial constant expansion
                    junk = [("PushImm", ("0",)), ("PushImm", ("1",)), ("Add", ()), ("PushImm", ("2",)), ("Sub", ()), ("Mul", ()), ("PushImm", ("3",)), ("Add", ())]
                elif expansion_type == 1:
                    # Modular ring twist: k_odd * k_inv == 1
                    junk = [("PushImm", ("k",)), ("Mul", ()), ("PushImm", ("k_inv",)), ("Mul", ())]
                else:
                    # Carry cascade
                    junk = [("PushReg", ("r0",)), ("PushReg", ("r1",)), ("Nor", ()), ("Nand", ()), ("Sub", ())]

                # Interleave
                ops_after.extend(junk)
                labels.extend([1] * len(junk))

            ops_after.append(op_key_item)
            labels.append(0)

        dataset.append((ops_after, labels))

    return {
        "dataset": dataset,
        "ops_before": sum(sum(1 for y in l if y == 0) for _, l in dataset),
        "ops_after": sum(len(o) for o, _ in dataset),
        "matched_core": sum(sum(1 for y in l if y == 0) for _, l in dataset),
        "redundant_ops": sum(sum(1 for y in l if y == 1) for _, l in dataset),
        "redundancy_ratio": sum(sum(1 for y in l if y == 1) for _, l in dataset) / sum(len(o) for o, _ in dataset)
    }


def pad_blocks(batch, max_len=256):
    """Pads opcode sequences and label masks."""
    x_list, y_list, mask_list = [], [], []
    for ops, labels in batch:
        ids = [OP2ID.get(op[0] if isinstance(op, tuple) else op, OP2ID["<UNK>"]) for op in ops][:max_len]
        labs = labels[:max_len]
        pad_len = max_len - len(ids)

        x_list.append(ids + [PAD_ID] * pad_len)
        y_list.append(labs + [0] * pad_len)
        mask_list.append([1] * len(ids) + [0] * pad_len)

    return (
        torch.tensor(x_list, dtype=torch.long),
        torch.tensor(y_list, dtype=torch.float32),
        torch.tensor(mask_list, dtype=torch.float32)
    )


def compute_dce_metrics(y_true, y_pred):
    """Computes Precision, Recall (Recovery Rate), F1, and AUC."""
    y_pred_bin = (y_pred >= 0.5).astype(np.float32)

    tp = float(np.sum((y_pred_bin == 1.0) & (y_true == 1.0)))
    fp = float(np.sum((y_pred_bin == 1.0) & (y_true == 0.0)))
    fn = float(np.sum((y_pred_bin == 0.0) & (y_true == 1.0)))
    tn = float(np.sum((y_pred_bin == 0.0) & (y_true == 0.0)))

    prec = tp / max(1.0, tp + fp)
    recall = tp / max(1.0, tp + fn)
    f1 = (2.0 * prec * recall) / max(1e-9, prec + recall)
    acc = (tp + tn) / max(1.0, len(y_true))

    # Hanley-McNeil AUC
    order = np.argsort(y_pred)[::-1]
    y_true_sorted = y_true[order]
    n_pos = int(np.sum(y_true == 1.0))
    n_neg = int(np.sum(y_true == 0.0))
    tps = np.cumsum(y_true_sorted)
    fps = np.cumsum(1.0 - y_true_sorted)
    tpr = tps / max(1, n_pos)
    fpr = fps / max(1, n_neg)

    if hasattr(np, "trapezoid"):
        auc = float(np.trapezoid(tpr, fpr))
    elif hasattr(np, "trapz"):
        auc = float(np.trapz(tpr, fpr))
    else:
        auc = float(np.sum((fpr[1:] - fpr[:-1]) * (tpr[1:] + tpr[:-1]) / 2.0))

    theta = max(0.001, min(0.999, auc))
    q1 = theta / (2.0 - theta)
    q2 = 2.0 * theta * theta / (1.0 + theta)
    num = theta * (1.0 - theta) + (n_pos - 1) * (q1 - theta * theta) + (n_neg - 1) * (q2 - theta * theta)
    se = math.sqrt(max(1e-9, num / (max(1, n_pos) * max(1, n_neg))))
    z = (theta - 0.5) / se
    p_val = 0.5 * math.erfc(z / math.sqrt(2.0))
    auc_95_upper = min(1.0, theta + 1.96 * se)

    return {
        "precision": prec,
        "recovery_rate": recall,
        "f1": f1,
        "accuracy": acc,
        "auc": auc,
        "auc_95_upper": auc_95_upper,
        "z": z,
        "p_value": p_val
    }


def audit_amplifier_dce(dump_dir=None, epochs=25, batch_size=16):
    """Trains Opcode-level Transformer and BiLSTM to detect amplified redundant instructions."""
    raw_info = extract_dataset_from_dumps(dump_dir) if dump_dir else None
    if not raw_info:
        raw_info = synthesize_amplified_dataset()

    dataset = raw_info["dataset"]
    split = int(len(dataset) * 0.75)
    train_data = dataset[:split]
    val_data = dataset[split:]

    X_tr, y_tr, mask_tr = pad_blocks(train_data)
    X_va, y_val, mask_va = pad_blocks(val_data)

    # 1. Model A: Opcode Sequence Transformer
    torch.manual_seed(1337)
    tf_model = OpcodeDCETransformer()
    opt_tf = torch.optim.Adam(tf_model.parameters(), lr=2e-3, weight_decay=1e-5)
    loss_fn = nn.BCEWithLogitsLoss(reduction='none')

    n_tr = len(X_tr)
    for _ in range(epochs):
        tf_model.train()
        perm = torch.randperm(n_tr)
        for i in range(0, n_tr, batch_size):
            idx = perm[i:i + batch_size]
            bx, by, bmask = X_tr[idx], y_tr[idx], mask_tr[idx]

            opt_tf.zero_grad()
            logits = tf_model(bx)
            loss = (loss_fn(logits, by) * bmask).sum() / bmask.sum().clamp(min=1.0)
            loss.backward()
            opt_tf.step()

    tf_model.eval()
    with torch.no_grad():
        tf_logits = tf_model(X_va)
        tf_probs = torch.sigmoid(tf_logits).numpy()

    # Flatten validation tokens
    valid_mask = (mask_va.numpy() == 1.0)
    flat_y_true = y_val.numpy()[valid_mask]
    flat_tf_pred = tf_probs[valid_mask]
    metrics_tf = compute_dce_metrics(flat_y_true, flat_tf_pred)

    # 2. Model B: BiLSTM Tagger
    torch.manual_seed(1337)
    lstm_model = OpcodeDCELSTM()
    opt_lstm = torch.optim.Adam(lstm_model.parameters(), lr=3e-3, weight_decay=1e-5)

    for _ in range(epochs):
        lstm_model.train()
        perm = torch.randperm(n_tr)
        for i in range(0, n_tr, batch_size):
            idx = perm[i:i + batch_size]
            bx, by, bmask = X_tr[idx], y_tr[idx], mask_tr[idx]

            opt_lstm.zero_grad()
            logits = lstm_model(bx)
            loss = (loss_fn(logits, by) * bmask).sum() / bmask.sum().clamp(min=1.0)
            loss.backward()
            opt_lstm.step()

    lstm_model.eval()
    with torch.no_grad():
        lstm_logits = lstm_model(X_va)
        lstm_probs = torch.sigmoid(lstm_logits).numpy()

    flat_lstm_pred = lstm_probs[valid_mask]
    metrics_lstm = compute_dce_metrics(flat_y_true, flat_lstm_pred)

    # 3. Model C: Local 5-gram Tabular Baseline
    # Builds 5-gram opcode context to predict redundancy
    def extract_ngrams(data):
        feats = []
        labels = []
        for ops, labs in data:
            ids = [OP2ID.get(o, OP2ID["<UNK>"]) for o in ops]
            n = len(ids)
            for j in range(n):
                c_prev2 = ids[j - 2] if j >= 2 else 0
                c_prev1 = ids[j - 1] if j >= 1 else 0
                c_curr = ids[j]
                c_next1 = ids[j + 1] if j + 1 < n else 0
                c_next2 = ids[j + 2] if j + 2 < n else 0
                feats.append([c_prev2, c_prev1, c_curr, c_next1, c_next2])
                labels.append(labs[j])
        return np.array(feats), np.array(labels)

    X_ng_tr, y_ng_tr = extract_ngrams(train_data)
    X_ng_va, y_ng_va = extract_ngrams(val_data)

    # One-hot linear model for 5-gram context
    lin_dce = nn.Embedding(VOCAB_SIZE, 8)
    lin_head = nn.Linear(8 * 5, 1)
    opt_tab = torch.optim.Adam(list(lin_dce.parameters()) + list(lin_head.parameters()), lr=5e-3)
    X_ng_tr_t = torch.tensor(X_ng_tr, dtype=torch.long)
    y_ng_tr_t = torch.tensor(y_ng_tr, dtype=torch.float32)

    for _ in range(15):
        opt_tab.zero_grad()
        e = lin_dce(X_ng_tr_t).reshape(len(X_ng_tr_t), -1)
        pred = lin_head(e).squeeze(-1)
        loss = F.binary_cross_entropy_with_logits(pred, y_ng_tr_t)
        loss.backward()
        opt_tab.step()

    with torch.no_grad():
        e_va = lin_dce(torch.tensor(X_ng_va, dtype=torch.long)).reshape(len(X_ng_va), -1)
        tab_preds = torch.sigmoid(lin_head(e_va)).squeeze(-1).numpy()
    metrics_tab = compute_dce_metrics(y_ng_va, tab_preds)

    # Resilience: DRS = 100 * (1 - max_recovery_rate)
    worst_recovery = max(metrics_tf["recovery_rate"], metrics_lstm["recovery_rate"], metrics_tab["recovery_rate"])
    drs_amp = max(0.0, 100.0 * (1.0 - worst_recovery))

    return {
        "ops_before": raw_info["ops_before"],
        "ops_after": raw_info["ops_after"],
        "redundancy_ratio": raw_info["redundancy_ratio"],
        "tf": metrics_tf,
        "lstm": metrics_lstm,
        "tab": metrics_tab,
        "worst_recovery_rate": worst_recovery,
        "drs_amp": drs_amp
    }


def main():
    dump_dir = sys.argv[1] if len(sys.argv) > 1 else "/tmp/real_license_json"
    print("=" * 86)
    print("      ASGARD-5877 BYTECODE AMPLIFIER & DEAD-CODE ELIMINATION (DCE) AUDITOR")
    print("=" * 86)
    print(f"[*] Auditing Opcode-Level Dead-Code Recovery across Basic Blocks...")
    print(f"    Source: '{dump_dir}'\n")

    res = audit_amplifier_dce(dump_dir=dump_dir, epochs=20)
    print(f"  Total Instructions: Before={res['ops_before']} -> After={res['ops_after']} ({res['redundancy_ratio']*100:.1f}% amplified)")
    print(f"  Label Balance (Dead=1): {res['redundancy_ratio']*100:.1f}% (Core=0: {(1.0 - res['redundancy_ratio'])*100:.1f}%)\n")

    header = f"{'Model':<22} {'Precision':<12} {'Recall (DCE)':<14} {'F1-Score':<10} {'ROC-AUC':<10} {'Worst-AUC95':<12}"
    print(header)
    print("-" * len(header))
    for name, m in [("Opcode-Transformer", res["tf"]), ("BiLSTM-Tagger", res["lstm"]), ("5-gram Tabular", res["tab"])]:
        print(f"{name:<22} {m['precision']*100:>10.1f}% {m['recovery_rate']*100:>12.1f}% {m['f1']:>9.3f} {m['auc']:>9.3f} {m['auc_95_upper']:>11.3f}")

    def tier_label(drs):
        if drs >= 90.0: return "TIER 3+ RESILIENT"
        elif drs >= 70.0: return "TIER 2 HARDENED"
        else: return "TIER 1 VULNERABLE"

    print("  " + "-" * 82)
    print(f"  ===> AMPLIFIER DCE RESILIENCE (DRS_amp):  {res['drs_amp']:>5.1f} / 100.0  [ {tier_label(res['drs_amp'])} ]")
    print("=" * 86 + "\n")


if __name__ == "__main__":
    main()
