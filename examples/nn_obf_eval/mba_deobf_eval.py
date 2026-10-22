#!/usr/bin/env python3
"""
ASGARD-5877 Neural MBA Simplifier & Incompressibility Evaluator
==============================================================
Evaluates whether a Sequence-to-Sequence Transformer can learn to simplify
Mixed Boolean-Arithmetic (MBA) expressions back to canonical arithmetic forms,
measuring the algebraic incompressibility of NLMBA and Nullspace transformations.
"""

import math
import random
import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F

# Vocabulary of MBA tokens
TOKENS = ["<PAD>", "<SOS>", "<EOS>", "x", "y", "+", "-", "*", "^", "&", "|", "~", "(", ")", "0", "1", "2"]
TOKEN2ID = {t: i for i, t in enumerate(TOKENS)}
ID2TOKEN = {i: t for i, t in enumerate(TOKENS)}
PAD_ID = TOKEN2ID["<PAD>"]
SOS_ID = TOKEN2ID["<SOS>"]
EOS_ID = TOKEN2ID["<EOS>"]
VOCAB_SIZE = len(TOKENS)


class MBATransformer(nn.Module):
    """Transformer Encoder-Decoder for neural MBA simplification."""
    def __init__(self, vocab_size=VOCAB_SIZE, d_model=64, nhead=4, num_layers=2, max_len=128):
        super().__init__()
        self.d_model = d_model
        self.emb = nn.Embedding(vocab_size, d_model)
        self.pos_emb = nn.Embedding(max_len, d_model)
        self.transformer = nn.Transformer(
            d_model=d_model, nhead=nhead,
            num_encoder_layers=num_layers, num_decoder_layers=num_layers,
            dim_feedforward=d_model * 2, batch_first=True
        )
        self.out_head = nn.Linear(d_model, vocab_size)

    def forward(self, src, tgt):
        # src: [B, S_len], tgt: [B, T_len]
        B, S_len = src.size()
        _, T_len = tgt.size()

        src_pos = torch.arange(S_len, device=src.device).unsqueeze(0).expand(B, -1)
        tgt_pos = torch.arange(T_len, device=tgt.device).unsqueeze(0).expand(B, -1)

        src_repr = self.emb(src) + self.pos_emb(src_pos)
        tgt_repr = self.emb(tgt) + self.pos_emb(tgt_pos)

        tgt_mask = self.transformer.generate_square_subsequent_mask(T_len).to(src.device)
        src_key_padding_mask = (src == PAD_ID)
        tgt_key_padding_mask = (tgt == PAD_ID)

        out = self.transformer(
            src_repr, tgt_repr,
            tgt_mask=tgt_mask,
            src_key_padding_mask=src_key_padding_mask,
            tgt_key_padding_mask=tgt_key_padding_mask
        )
        return self.out_head(out)


def generate_mba_dataset(depth=1, n_samples=300):
    """Synthesizes dataset of (obfuscated_tokens, canonical_tokens) at given MBA depth."""
    random.seed(1337 + depth)
    samples = []

    # Ground truth canonical operations
    canonical_ops = [
        (["x", "+", "y"], "add"),
        (["x", "^", "y"], "xor"),
        (["x", "&", "y"], "and"),
        (["x", "|", "y"], "or"),
        (["x", "-", "y"], "sub"),
    ]

    for _ in range(n_samples):
        canon_toks, kind = random.choice(canonical_ops)

        def rewrite_node(k, d):
            if d == 0:
                if k == "add": return ["x", "+", "y"]
                if k == "xor": return ["x", "^", "y"]
                if k == "and": return ["x", "&", "y"]
                if k == "or":  return ["x", "|", "y"]
                if k == "sub": return ["x", "-", "y"]
                return ["x"]

            # Rewrite rules:
            if k == "add":
                # (x ^ y) + 2 * (x & y)
                sub1 = rewrite_node("xor", d - 1)
                sub2 = rewrite_node("and", d - 1)
                return ["("] + sub1 + [")", "+", "2", "*", "("] + sub2 + [")"]
            elif k == "sub":
                # (x ^ y) - 2 * (~x & y)
                sub1 = rewrite_node("xor", d - 1)
                return ["("] + sub1 + [")", "-", "2", "*", "(", "~", "x", "&", "y", ")"]
            elif k == "xor":
                # (x | y) - (x & y)
                sub1 = rewrite_node("or", d - 1)
                sub2 = rewrite_node("and", d - 1)
                return ["("] + sub1 + [")", "-", "("] + sub2 + [")"]
            elif k == "or":
                # (x & y) + (x ^ y)
                sub1 = rewrite_node("and", d - 1)
                sub2 = rewrite_node("xor", d - 1)
                return ["("] + sub1 + [")", "+", "("] + sub2 + [")"]
            else: # and
                # (x | y) - (x ^ y)
                sub1 = rewrite_node("or", d - 1)
                sub2 = rewrite_node("xor", d - 1)
                return ["("] + sub1 + [")", "-", "("] + sub2 + [")"]

        obf_tokens = rewrite_node(kind, depth)
        samples.append((obf_tokens, canon_toks))

    return samples


def pad_and_tensorize(samples, max_src_len=96, max_tgt_len=16):
    """Converts token lists to padded integer tensors."""
    src_list = []
    tgt_in_list = []
    tgt_out_list = []

    for obf, canon in samples:
        # Source
        s_ids = [TOKEN2ID.get(t, PAD_ID) for t in obf][:max_src_len] + [EOS_ID]
        s_pad = s_ids + [PAD_ID] * (max_src_len + 1 - len(s_ids))
        src_list.append(s_pad)

        # Target (Teacher forcing)
        t_ids = [TOKEN2ID.get(t, PAD_ID) for t in canon][:max_tgt_len]
        t_in = [SOS_ID] + t_ids
        t_out = t_ids + [EOS_ID]
        t_in_pad = t_in + [PAD_ID] * (max_tgt_len + 1 - len(t_in))
        t_out_pad = t_out + [PAD_ID] * (max_tgt_len + 1 - len(t_out))
        tgt_in_list.append(t_in_pad)
        tgt_out_list.append(t_out_pad)

    return (
        torch.tensor(src_list, dtype=torch.long),
        torch.tensor(tgt_in_list, dtype=torch.long),
        torch.tensor(tgt_out_list, dtype=torch.long),
    )


def audit_mba_depth(depth=1, epochs=35):
    """Trains a Transformer to simplify MBA expressions at given depth and measures incompressibility."""
    dataset = generate_mba_dataset(depth=depth, n_samples=350)
    split = int(len(dataset) * 0.8)
    train_data = dataset[:split]
    val_data = dataset[split:]

    src_train, tgt_in_train, tgt_out_train = pad_and_tensorize(train_data)
    src_val, tgt_in_val, tgt_out_val = pad_and_tensorize(val_data)

    model = MBATransformer()
    optimizer = torch.optim.Adam(model.parameters(), lr=1e-3)
    loss_fn = nn.CrossEntropyLoss(ignore_index=PAD_ID)

    # Train
    model.train()
    batch_size = 64
    for _ in range(epochs):
        permutation = torch.randperm(src_train.size(0))
        for i in range(0, src_train.size(0), batch_size):
            indices = permutation[i:i + batch_size]
            b_src = src_train[indices]
            b_tgt_in = tgt_in_train[indices]
            b_tgt_out = tgt_out_train[indices]

            optimizer.zero_grad()
            logits = model(b_src, b_tgt_in)
            loss = loss_fn(logits.reshape(-1, VOCAB_SIZE), b_tgt_out.reshape(-1))
            loss.backward()
            optimizer.step()

    # Evaluate
    model.eval()
    with torch.no_grad():
        val_logits = model(src_val, tgt_in_val)
        val_loss = float(loss_fn(val_logits.reshape(-1, VOCAB_SIZE), tgt_out_val.reshape(-1)))
        preds = torch.argmax(val_logits, dim=-1)

        # Exact token match percentage
        exact_matches = 0
        for i in range(len(val_data)):
            p = preds[i].tolist()
            t = tgt_out_val[i].tolist()
            # truncate at EOS
            p_eos = p.index(EOS_ID) if EOS_ID in p else len(p)
            t_eos = t.index(EOS_ID) if EOS_ID in t else len(t)
            if p[:p_eos] == t[:t_eos]:
                exact_matches += 1

        exact_rate = exact_matches / len(val_data)
        avg_len = sum(len(s[0]) for s in val_data) / len(val_data)

    # DRS score: 100% when exact recovery rate is 0.0
    drs_mba = max(0.0, 100.0 * (1.0 - exact_rate))

    return {
        "depth": depth,
        "avg_tokens": avg_len,
        "exact_rate": exact_rate,
        "val_loss": val_loss,
        "drs_mba": drs_mba
    }


if __name__ == "__main__":
    print("[*] Auditing Algebraic MBA Incompressibility across Depths using Transformer...")
    print(f"{'Depth':<8} {'Avg Tokens':<12} {'Simplification Rate':<22} {'Loss':<10} {'DRS (0-100)':<12}")
    print("-" * 66)
    for d in [1, 2, 3, 4]:
        res = audit_mba_depth(depth=d)
        print(f"{res['depth']:<8} {res['avg_tokens']:<12.1f} {res['exact_rate']*100:<20.1f}% {res['val_loss']:<10.3f} {res['drs_mba']:<12.1f}")
