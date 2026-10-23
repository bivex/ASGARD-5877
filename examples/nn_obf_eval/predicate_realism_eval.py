#!/usr/bin/env python3
"""
ASGARD-5877 Opaque Predicate Realism & Stack-VM CFF Classifier Evaluator
=========================================================================
Audits whether deep-learning sequence models (BiLSTM with attention,
Transformer Encoder) or tabular baselines can distinguish Stack-VM CFF
opaque branch sequences from real (non-CFF) branch sequences.

When a pipeline dump directory is supplied the evaluator loads
phase_3-cff.json and extracts:
  - Positive samples (opaque=1): windows of Stack-VM ops ending at each
    JccRel instruction found in CFF dispatcher blocks.
  - Negative samples (real condition=0): trailing op windows from blocks
    that end in JmpRel or Exit and contain no JccRel.

Without a dump directory the evaluator falls back to a synthetic dataset
of toy Brooks-MBA-style sequences (PushImm/Add/Sub/Cmp/JccRel) as positives
and random arithmetic sequences without Cmp+JccRel as negatives.
"""

import json
import math
import os
import random
import sys
import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F

TOKENS = [
    "<PAD>", "<CONST>",
    "PushImm", "PopReg", "PushReg",
    "Add", "Sub", "Mul", "Nor", "Nand",
    "Shl", "Shr", "And", "Or", "Xor",
    "Cmp", "JccRel", "JmpRel",
    "KeyFeedback", "AddImm", "SubImm",
    "AddImmImm", "SubImmImm", "SetRegImm",
    "AddRegImm", "Dup", "Dup2", "Rot",
    "Swap", "Exit",
]
TOKEN2ID = {t: i for i, t in enumerate(TOKENS)}
ID2TOKEN = {i: t for i, t in enumerate(TOKENS)}
PAD_ID = TOKEN2ID["<PAD>"]
VOCAB_SIZE = len(TOKENS)


class BiLSTMPredicateClassifier(nn.Module):
    """Bidirectional LSTM with attention pooling for predicate AST classification."""
    def __init__(self, vocab_size=VOCAB_SIZE, embed_dim=32, hidden_dim=64):
        super().__init__()
        self.emb = nn.Embedding(vocab_size, embed_dim)
        self.lstm = nn.LSTM(embed_dim, hidden_dim, batch_first=True, bidirectional=True)
        self.attn = nn.Linear(hidden_dim * 2, 1)
        self.fc = nn.Sequential(
            nn.Linear(hidden_dim * 2, 32),
            nn.ReLU(),
            nn.Linear(32, 1)
        )

    def forward(self, x):
        mask = (x != PAD_ID).float().unsqueeze(-1)
        e = self.emb(x)
        out, _ = self.lstm(e)
        attn_weights = self.attn(out).masked_fill(mask == 0, -1e9)
        alpha = F.softmax(attn_weights, dim=1)
        context = (out * alpha).sum(dim=1)
        return self.fc(context).squeeze(-1)


class TransformerPredicateClassifier(nn.Module):
    """Transformer Encoder with CLS token pooling."""
    def __init__(self, vocab_size=VOCAB_SIZE, d_model=48, nhead=4, num_layers=2, max_len=128):
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
        # Global mean pooling over non-pad tokens
        mask = (~padding_mask).float().unsqueeze(-1)
        pooled = (out * mask).sum(dim=1) / mask.sum(dim=1).clamp(min=1.0)
        return self.fc(pooled).squeeze(-1)


def extract_opaque_dataset_from_dump(dump_dir):
    """Loads phase_3-cff.json and phase_1-lowered.json to extract condition computation windows.

    Both positive and negative sequences represent the 3-10 instructions that compute
    branch flags immediately preceding a conditional jump (JccRel), truncated before
    the JccRel opcode itself. This ensures the classification task evaluates condition
    semantics (opaque algebraic identity vs genuine computation) rather than token presence.
    """
    cff_path = os.path.join(dump_dir, "phase_3-cff.json")
    lowered_path = os.path.join(dump_dir, "phase_1-lowered.json")
    if not os.path.isfile(cff_path):
        return None, False

    try:
        with open(cff_path, "r") as fh:
            cff_data = json.load(fh)
    except (json.JSONDecodeError, OSError):
        return None, False

    cff_blocks = cff_data.get("blocks", []) if isinstance(cff_data, dict) else (cff_data if isinstance(cff_data, list) else [])
    if not cff_blocks:
        return None, False

    # Positive samples: CFF blocks containing JccRel (condition windows preceding JccRel, truncated before JccRel)
    pos_samples = []
    for block in cff_blocks:
        ops = block.get("ops", [])
        if not isinstance(ops, list):
            continue
        op_names = [o.get("op", "<CONST>") if isinstance(o, dict) else str(o) for o in ops]
        jcc_positions = [i for i, name in enumerate(op_names) if name == "JccRel"]
        for jcc_pos in jcc_positions:
            start = max(0, jcc_pos - 10)
            window = op_names[start:jcc_pos]  # Truncated before JccRel
            if len(window) >= 2:
                pos_samples.append((window, 1))

    # Negative samples: Genuine program branch condition windows from phase_1-lowered.json
    neg_samples = []
    if os.path.isfile(lowered_path):
        try:
            with open(lowered_path, "r") as fh:
                low_data = json.load(fh)
            low_blocks = low_data.get("blocks", []) if isinstance(low_data, dict) else (low_data if isinstance(low_data, list) else [])
            for block in low_blocks:
                ops = block.get("ops", [])
                op_names = [o.get("op", "<CONST>") if isinstance(o, dict) else str(o) for o in ops]
                jcc_positions = [i for i, name in enumerate(op_names) if name == "JccRel"]
                for jcc_pos in jcc_positions:
                    start = max(0, jcc_pos - 10)
                    window = op_names[start:jcc_pos]  # Truncated before JccRel
                    if len(window) >= 2:
                        neg_samples.append((window, 0))
                if not jcc_positions:
                    jmp_positions = [i for i, name in enumerate(op_names) if name in ("JmpRel", "Exit")]
                    for jmp_pos in jmp_positions:
                        start = max(0, jmp_pos - 10)
                        window = op_names[start:jmp_pos]
                        if len(window) >= 2:
                            neg_samples.append((window, 0))
        except Exception:
            pass

    if not pos_samples or not neg_samples:
        return None, False

    # Balance classes
    n = min(len(pos_samples), len(neg_samples))
    pos = random.sample(pos_samples, n)
    neg = random.sample(neg_samples, n)
    balanced = pos + neg

    if len(balanced) < 60:
        multiplier = (60 // len(balanced)) + 1
        balanced = balanced * multiplier

    random.shuffle(balanced)
    return balanced, True


def generate_stack_vm_predicate_dataset(n_samples=400, seed=1337):
    """Generates a synthetic balanced Stack-VM dataset as fallback.

    Both classes represent condition calculations ending in Cmp.
    Positive: Brooks-MBA invariant identity calculation.
    Negative: Genuine variable arithmetic comparison.
    """
    random.seed(seed)
    samples = []

    arith_ops = ["Add", "Sub", "Mul", "And", "Or", "Xor", "Shl", "Shr"]

    for _ in range(n_samples // 2):
        prefix_len = random.randint(1, 4)
        prefix = [random.choice(["PushImm", "PushReg", "AddImm"]) for _ in range(prefix_len)]
        core = [
            "PushImm", "PushImm", "Add",
            "PushImm", "PushImm", "Add",
            "Sub", "PushImm", "Cmp"
        ]
        toks = prefix + core
        samples.append((toks, 1))

    for _ in range(n_samples // 2):
        prefix_len = random.randint(1, 4)
        prefix = [random.choice(["PushImm", "PushReg", "AddImm"]) for _ in range(prefix_len)]
        core = [
            random.choice(arith_ops), "PushReg", "PushImm",
            random.choice(arith_ops), "PushReg", "Cmp"
        ]
        toks = prefix + core
        samples.append((toks, 0))

    random.shuffle(samples)
    return samples


def extract_ast_features(toks):
    """Extracts non-graph structural features without tautological op flags."""
    length = float(len(toks))
    push_count = float(sum(1 for t in toks if "Push" in t or "Imm" in t))
    arith_count = float(sum(1 for t in toks if t in ("Add", "Sub", "Mul", "And", "Or", "Xor", "Shl", "Shr")))
    nor_count = float(sum(1 for t in toks if t in ("Nor", "Nand")))
    unique_ops = float(len(set(toks)))
    return np.array([length, push_count, arith_count, nor_count, unique_ops], dtype=np.float32)

def compute_stats(pos_scores, neg_scores):
    """Computes AUC, SE via Hanley-McNeil, z-score, p-value, and 95% upper bound."""
    n_pos = len(pos_scores)
    n_neg = len(neg_scores)
    if n_pos == 0 or n_neg == 0:
        return {
            "auc": 0.5,
            "acc": 0.5,
            "se": 0.1,
            "z": 0.0,
            "p_value": 0.5,
            "auc_95_upper": 0.5
        }
    y_true = np.concatenate([np.ones_like(pos_scores), np.zeros_like(neg_scores)])
    y_pred = np.concatenate([pos_scores, neg_scores])
    order = np.argsort(y_pred)[::-1]
    y_true_sorted = y_true[order]
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
    se = math.sqrt(max(1e-9, num / (n_pos * n_neg)))
    z = (theta - 0.5) / se
    p_val = 0.5 * math.erfc(z / math.sqrt(2.0))
    auc_95_upper = min(1.0, theta + 1.96 * se)

    # Accuracy at threshold 0.5
    acc = float(np.mean((y_pred >= 0.5) == (y_true == 1.0)))
    return {
        "auc": auc,
        "acc": acc,
        "se": se,
        "z": z,
        "p_value": p_val,
        "auc_95_upper": auc_95_upper
    }


def audit_opaque_predicates(dump_dir=None, n_samples=400, epochs=30):
    """Trains BiLSTM, Transformer, and Tabular baseline to distinguish opaque predicates.

    If dump_dir is provided and phase_3-cff.json is present, uses real pipeline
    Stack-VM CFF data. Falls back to synthetic Brooks-MBA-style sequences otherwise.
    """
    using_real = False
    if dump_dir is not None:
        dataset, using_real = extract_opaque_dataset_from_dump(dump_dir)

    if not using_real:
        dataset = generate_stack_vm_predicate_dataset(n_samples=n_samples)

    random.shuffle(dataset)
    split = int(len(dataset) * 0.75)
    train_data = dataset[:split]
    val_data = dataset[split:]

    def pad(samples, max_len=64):
        x_list, y_list = [], []
        for toks, label in samples:
            ids = [TOKEN2ID.get(t, TOKEN2ID["<CONST>"]) for t in toks][:max_len]
            x_list.append(ids + [PAD_ID] * (max_len - len(ids)))
            y_list.append(label)
        return torch.tensor(x_list, dtype=torch.long), torch.tensor(y_list, dtype=torch.float32)

    X_train, y_train = pad(train_data)
    X_val, y_val = pad(val_data)

    val_pos_idx = np.where(y_val.numpy() == 1.0)[0]
    val_neg_idx = np.where(y_val.numpy() == 0.0)[0]

    loss_fn = nn.BCEWithLogitsLoss()

    # Model A: BiLSTM
    torch.manual_seed(1337)
    bilstm = BiLSTMPredicateClassifier()
    opt_lstm = torch.optim.Adam(bilstm.parameters(), lr=3e-3, weight_decay=1e-4)

    for _ in range(epochs):
        bilstm.train()
        pred = bilstm(X_train)
        loss = loss_fn(pred, y_train)
        opt_lstm.zero_grad()
        loss.backward()
        opt_lstm.step()

    bilstm.eval()
    with torch.no_grad():
        lstm_preds = torch.sigmoid(bilstm(X_val)).numpy()
    stats_lstm = compute_stats(lstm_preds[val_pos_idx], lstm_preds[val_neg_idx])

    # Model B: Transformer
    torch.manual_seed(1337)
    tf = TransformerPredicateClassifier()
    opt_tf = torch.optim.Adam(tf.parameters(), lr=2e-3, weight_decay=1e-4)

    for _ in range(epochs):
        tf.train()
        pred = tf(X_train)
        loss = loss_fn(pred, y_train)
        opt_tf.zero_grad()
        loss.backward()
        opt_tf.step()

    tf.eval()
    with torch.no_grad():
        tf_preds = torch.sigmoid(tf(X_val)).numpy()
    stats_tf = compute_stats(tf_preds[val_pos_idx], tf_preds[val_neg_idx])

    # Model C: Tabular Logistic Baseline
    X_tab_tr = np.array([extract_ast_features(t) for t, _ in train_data])
    X_tab_va = np.array([extract_ast_features(t) for t, _ in val_data])
    lin = nn.Linear(X_tab_tr.shape[1], 1)
    opt_lin = torch.optim.Adam(lin.parameters(), lr=0.05, weight_decay=1e-3)
    X_tab_tr_t = torch.tensor(X_tab_tr, dtype=torch.float32)
    y_tr_t = y_train

    for _ in range(epochs):
        pred = lin(X_tab_tr_t).squeeze(-1)
        loss = loss_fn(pred, y_tr_t)
        opt_lin.zero_grad()
        loss.backward()
        opt_lin.step()

    lin.eval()
    with torch.no_grad():
        tab_preds = torch.sigmoid(lin(torch.tensor(X_tab_va, dtype=torch.float32))).squeeze(-1).numpy()
    stats_tab = compute_stats(tab_preds[val_pos_idx], tab_preds[val_neg_idx])

    # Conservative DRS: worst-case 95% upper bound
    def compute_drs(stats):
        adv = max(0.0, stats["auc_95_upper"] - 0.5) * 2.0
        return max(0.0, 100.0 * (1.0 - adv ** 2))

    drs_lstm = compute_drs(stats_lstm)
    drs_tf = compute_drs(stats_tf)
    drs_tab = compute_drs(stats_tab)

    conservative_drs = min([drs_lstm, drs_tf, drs_tab])
    worst_stats = max([stats_lstm, stats_tf, stats_tab], key=lambda s: s["auc_95_upper"])

    return {
        "bilstm_auc": stats_lstm["auc"],
        "bilstm_acc": stats_lstm["acc"],
        "tf_auc": stats_tf["auc"],
        "tf_acc": stats_tf["acc"],
        "tab_auc": stats_tab["auc"],
        "worst_auc_95": worst_stats["auc_95_upper"],
        "z_score": worst_stats["z"],
        "p_value": worst_stats["p_value"],
        "drs_opaque": conservative_drs,
        "using_real_dump": using_real,
    }


def main():
    dump_dir = sys.argv[1] if len(sys.argv) > 1 else None

    print("=" * 80)
    print("       ASGARD-5877 OPAQUE PREDICATE REALISM & AST AUDITOR")
    print("=" * 80)
    print("[*] Auditing Stack-VM CFF Opaque Branches vs Real Branch Sequences...")
    print("    Models: BiLSTM (Attention), AST-Transformer, Tabular Structural Baseline\n")

    res = audit_opaque_predicates(dump_dir=dump_dir, n_samples=400, epochs=30)
    source = "real pipeline dump" if res["using_real_dump"] else "synthetic fallback"
    print(f"    Data source: {source}")
    if dump_dir and not res["using_real_dump"]:
        print(f"    (phase_3-cff.json not found in {dump_dir!r}; using synthetic data)\n")
    else:
        print()
    print(f"  BiLSTM ROC-AUC:                      {res['bilstm_auc']:>6.3f}  (Accuracy: {res['bilstm_acc']*100:.1f}%)")
    print(f"  Transformer ROC-AUC:                 {res['tf_auc']:>6.3f}  (Accuracy: {res['tf_acc']*100:.1f}%)")
    print(f"  Tabular Baseline ROC-AUC:            {res['tab_auc']:>6.3f}")
    print(f"  Worst-Case 95% Upper Bound (AUC_95): {res['worst_auc_95']:>6.3f}")
    print(f"  Statistical z-score:                 {res['z_score']:>6.2f}  (p-value: {res['p_value']:.4f})")
    def tier_label(drs):
        if drs >= 90.0: return "TIER 3+ RESILIENT"
        elif drs >= 70.0: return "TIER 2 HARDENED"
        else: return "TIER 1 VULNERABLE"
    print("  " + "-" * 76)
    print(f"  ===> OPAQUE PREDICATE DRS SCORE:     {res['drs_opaque']:>6.1f} / 100.0  [ {tier_label(res['drs_opaque'])} ]")
    print("=" * 80 + "\n")


if __name__ == "__main__":
    main()
