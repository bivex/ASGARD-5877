#!/usr/bin/env python3
"""
ASGARD-5877 Superop ISA-Diversification & Cross-Build Transfer Auditor (NOAS)
=============================================================================
Audits whether reverse-engineering signature libraries and neural handler
classifiers trained on one build of a protected binary (Build A) can transfer
zero-shot to deobfuscate instructions in another build (Build B) generated with
a different seed, testing the empirical resilience of per-build ISA permutation
and superoperator fusion.

Attack Model:
  1. Train Handler Semantics Classifier C_A on Build A:
     Given the raw byte encoding of a VM instruction (opcode byte + operand layout),
     predict its semantic opcode class (AddImm, SubImm, AddImmImm, SubImmImm,
     SetRegImm, AddRegImm, PushImm, PushReg, PopReg, Add, Sub, Mul, Nor, Nand,
     Cmp, JccRel).
  2. Zero-Shot Cross-Build Transfer Attack on Build B:
     Evaluate C_A without retraining on Build B (different seed -> randomized
     opcode byte permutation + randomized field layout order).

Metrics:
  - In-Build Accuracy: Accuracy of C_A on held-out instructions from Build A.
  - Transfer Accuracy: Zero-shot accuracy of C_A on instructions from Build B.
  - Transfer Ratio: Transfer_Acc / In_Build_Acc.
  - DRS_isa_diversity: 100 * (1 - Transfer_Accuracy).
"""

import os
import sys
import struct
import random
import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F

MASK64 = (1 << 64) - 1

CLASSES = [
    "AddImm", "SubImm", "AddImmImm", "SubImmImm", "SetRegImm", "AddRegImm",
    "PushImm", "PushReg", "PopReg", "Add", "Sub", "Mul", "Nor", "Nand", "Cmp", "JccRel"
]
CLASS2ID = {c: i for i, c in enumerate(CLASSES)}
ID2CLASS = {i: c for i, c in enumerate(CLASSES)}
NUM_CLASSES = len(CLASSES)


def splitmix64(state):
    """64-bit SplitMix64 PRNG matching lib/stack_vm/stack_encoder.ml."""
    state = (state + 0x9E3779B97F4A7C15) & MASK64
    z = state
    z = ((z ^ (z >> 30)) * 0xBF58476D1CE4E5B9) & MASK64
    z = ((z ^ (z >> 27)) * 0x94D049BB133111EB) & MASK64
    z = (z ^ (z >> 31)) & MASK64
    return state, z


def generate_opcode_map(seed):
    """Generates per-build polymorphic opcode permutation matching stack_encoder.ml."""
    state = 0x58771337CAFEBABE if seed == 0 else seed & MASK64
    pool = list(range(1, 255))
    for i in range(39):
        state, r = splitmix64(state)
        # OCaml abs(to_int z) mod (254 - i)
        signed_r = r if r < (1 << 63) else r - (1 << 64)
        j = i + (abs(signed_r) % (254 - i))
        pool[i], pool[j] = pool[j], pool[i]
    return pool[:39]


def generate_field_layout(seed):
    """Generates per-build operand field layout matching stack_encoder.ml."""
    s = (seed ^ 0xA5A55A5A0FF0F00F) & MASK64
    _, r = splitmix64(s)
    return {
        "jcc_target_first": (r & 1) != 0,
        "cmov_slot_first": (r & 2) != 0,
        "set_reg_imm_first": (r & 4) != 0,
        "add_reg_imm_first": (r & 8) != 0
    }


def encode_instruction(op_name, args, op_map, layout):
    """Encodes a single Stack-VM instruction into raw bytes."""
    idx_map = {
        "PushImm": 0, "PushReg": 1, "PopReg": 2, "Add": 5, "Sub": 6, "Mul": 7, "Nor": 8, "Nand": 9,
        "JccRel": 17, "Cmp": 24, "AddImm": 30, "SubImm": 31, "AddImmImm": 32, "SubImmImm": 33,
        "SetRegImm": 34, "AddRegImm": 35
    }
    op_byte = op_map[idx_map[op_name]]
    buf = bytearray([op_byte])

    if op_name in ("AddImm", "SubImm"):
        buf.extend(struct.pack("<q", args[0]))
    elif op_name in ("AddImmImm", "SubImmImm"):
        buf.extend(struct.pack("<q", args[0]))
        buf.extend(struct.pack("<q", args[1]))
    elif op_name == "SetRegImm":
        if layout["set_reg_imm_first"]:
            buf.extend(struct.pack("<q", args[1]))
            buf.extend(struct.pack("<h", args[0]))
        else:
            buf.extend(struct.pack("<h", args[0]))
            buf.extend(struct.pack("<q", args[1]))
    elif op_name == "AddRegImm":
        if layout["add_reg_imm_first"]:
            buf.extend(struct.pack("<q", args[1]))
            buf.extend(struct.pack("<h", args[0]))
        else:
            buf.extend(struct.pack("<h", args[0]))
            buf.extend(struct.pack("<q", args[1]))
    elif op_name == "PushImm":
        buf.extend(struct.pack("<q", args[0]))
    elif op_name in ("PushReg", "PopReg"):
        buf.extend(struct.pack("<h", args[0]))
    elif op_name == "JccRel":
        if layout["jcc_target_first"]:
            buf.extend(struct.pack("<i", args[0]))
            buf.append(args[1])
        else:
            buf.append(args[1])
            buf.extend(struct.pack("<i", args[0]))

    # Pad to fixed byte vector of length 18
    padded = list(buf)[:18] + [0] * max(0, 18 - len(buf))
    return padded


def build_isa_dataset(seed, n_per_class=120):
    """Synthesizes a realistic dataset of encoded instruction byte vectors for a given build seed."""
    random.seed(seed)
    np.random.seed(seed % 0x7FFFFFFF)
    op_map = generate_opcode_map(seed)
    layout = generate_field_layout(seed)

    X, y = [], []
    for cls in CLASSES:
        for _ in range(n_per_class):
            if cls in ("AddImm", "SubImm", "PushImm"):
                args = [random.randint(-100000, 100000)]
            elif cls in ("AddImmImm", "SubImmImm"):
                args = [random.randint(-50000, 50000), random.randint(-50000, 50000)]
            elif cls in ("SetRegImm", "AddRegImm"):
                args = [random.randint(0, 63), random.randint(-50000, 50000)]
            elif cls in ("PushReg", "PopReg"):
                args = [random.randint(0, 63)]
            elif cls == "JccRel":
                args = [random.randint(-500, 500), random.randint(0, 5)]
            else:
                args = []

            bytes_vec = encode_instruction(cls, args, op_map, layout)
            X.append(bytes_vec)
            y.append(CLASS2ID[cls])

    X = np.array(X, dtype=np.float32) / 255.0  # Normalized byte values in [0, 1]
    y = np.array(y, dtype=np.int64)

    # Shuffle
    idx = np.random.permutation(len(y))
    return X[idx], y[idx]


class HandlerSemanticsClassifier(nn.Module):
    """Neural Multi-Class Handler Semantics Classifier."""
    def __init__(self, in_dim=18, n_classes=NUM_CLASSES):
        super().__init__()
        self.net = nn.Sequential(
            nn.Linear(in_dim, 96),
            nn.ReLU(),
            nn.Dropout(0.1),
            nn.Linear(96, 48),
            nn.ReLU(),
            nn.Linear(48, n_classes)
        )

    def forward(self, x):
        return self.net(x)


def audit_superop_isa_diversity(seed_a=1337, seed_b=42, epochs=35, batch_size=32):
    """
    Trains classifier on Build A, evaluates In-Build accuracy on held-out A samples,
    and measures zero-shot transfer accuracy on Build B (different seed).
    """
    # 1. Generate Build A and Build B datasets
    XA_all, yA_all = build_isa_dataset(seed_a, n_per_class=120)
    XB_all, yB_all = build_isa_dataset(seed_b, n_per_class=60)

    # 75% train / 25% test on Build A
    split = int(len(yA_all) * 0.75)
    XA_tr, yA_tr = XA_all[:split], yA_all[:split]
    XA_te, yA_te = XA_all[split:], yA_all[split:]

    # 2. Train C_A on Build A
    torch.manual_seed(1337)
    clf = HandlerSemanticsClassifier()
    opt = torch.optim.Adam(clf.parameters(), lr=0.008, weight_decay=1e-4)
    loss_fn = nn.CrossEntropyLoss()

    X_tr_t = torch.tensor(XA_tr)
    y_tr_t = torch.tensor(yA_tr)

    for _ in range(epochs):
        clf.train()
        for i in range(0, len(XA_tr), batch_size):
            xb = X_tr_t[i:i + batch_size]
            yb = y_tr_t[i:i + batch_size]
            logits = clf(xb)
            loss = loss_fn(logits, yb)
            opt.zero_grad()
            loss.backward()
            opt.step()

    clf.eval()
    with torch.no_grad():
        # In-build test on Build A
        logits_A = clf(torch.tensor(XA_te))
        preds_A = torch.argmax(logits_A, dim=-1).numpy()
        in_build_acc = float(np.mean(preds_A == yA_te))

        # Cross-build zero-shot transfer on Build B
        logits_B = clf(torch.tensor(XB_all))
        preds_B = torch.argmax(logits_B, dim=-1).numpy()
        transfer_acc = float(np.mean(preds_B == yB_all))

    chance_baseline = 1.0 / float(NUM_CLASSES)
    transfer_ratio = transfer_acc / max(1e-9, in_build_acc)
    drs_isa = max(0.0, 100.0 * (1.0 - transfer_acc))

    return {
        "seed_a": seed_a,
        "seed_b": seed_b,
        "num_classes": NUM_CLASSES,
        "in_build_acc": in_build_acc,
        "transfer_acc": transfer_acc,
        "chance_baseline": chance_baseline,
        "transfer_ratio": transfer_ratio,
        "drs_isa": drs_isa
    }


def main():
    seed_a = int(sys.argv[1]) if len(sys.argv) > 1 and sys.argv[1].isdigit() else 1337
    seed_b = int(sys.argv[2]) if len(sys.argv) > 2 and sys.argv[2].isdigit() else 42

    print("=" * 86)
    print("      ASGARD-5877 SUPEROP ISA-DIVERSIFICATION & CROSS-BUILD AUDITOR (NOAS)")
    print("=" * 86)
    print("[*] Auditing Handler Semantics Classifier Transfer Across Independent Builds...")
    print(f"    Build A Seed: {seed_a} (Training & In-Build Evaluation)")
    print(f"    Build B Seed: {seed_b} (Zero-Shot Cross-Build Transfer Target)")
    print(f"    Classes:      {NUM_CLASSES} Stack-VM Superoperators & Core Instructions\n")

    res = audit_superop_isa_diversity(seed_a=seed_a, seed_b=seed_b)

    print(f"  In-Build Accuracy (C_A on Build A):          {res['in_build_acc']*100:>6.1f}%  (Baseline Competence)")
    print(f"  Zero-Shot Transfer Accuracy (C_A on Build B): {res['transfer_acc']*100:>6.1f}%  (Random Chance: {res['chance_baseline']*100:.1f}%)")
    print(f"  Cross-Build Transfer Ratio:                  {res['transfer_ratio']*100:>6.1f}%\n")

    print(f"  {'Metric':<35} {'Observed Value':>18} {'Target / Threshold':>20}")
    print("-" * 86)
    print(f"  {'In-Build Generalization':<35} {res['in_build_acc']*100:>17.1f}% {'> 70.0% (Valid)':>20}")
    print(f"  {'Cross-Build Transfer Accuracy':<35} {res['transfer_acc']*100:>17.1f}% {'< 50.0% (Blocked)':>20}")
    print(f"  {'Random-Guess Chance Baseline':<35} {res['chance_baseline']*100:>17.1f}% {'6.2%':>20}")

    print("  " + "-" * 82)
    def tier_label(drs):
        if drs >= 90.0: return "TIER 3+"
        elif drs >= 70.0: return "TIER 2"
        else: return "TIER 1"
    print(f"  ===> SUPEROP ISA DIVERSITY DRS:       {res['drs_isa']:>6.1f} / 100.0  [ {tier_label(res['drs_isa'])} ]")
    print("=" * 86 + "\n")


if __name__ == "__main__":
    main()
