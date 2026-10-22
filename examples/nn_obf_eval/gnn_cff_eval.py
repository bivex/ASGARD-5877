#!/usr/bin/env python3
"""
ASGARD-5877 GNN CFG Obfuscation & Deobfuscation Auditor
======================================================
Measures the resistance of Control-Flow Flattening (CFF), VPC dispatchers,
Spaghetti splitting, and Red Herring blocks against Graph Neural Network (GNN)
structural recovery and dispatcher localization attacks.

Uses a pure-PyTorch Graph Attention Network (GAT) with self-supervised edge
classification and hub identification heads.
"""

import os
import json
import math
import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F

OP_CATEGORIES = {
    "PushImm": 0, "PushReg": 1, "PopReg": 2, "ReadMem": 3, "WriteMem": 4,
    "Add": 5, "Sub": 5, "Mul": 5, "Nor": 5, "Nand": 5, "Shl": 5, "Shr": 5, "Sar": 5, "Div": 5, "Idiv": 5,
    "AddImm": 5, "SubImm": 5, "AddImmImm": 5, "SubImmImm": 5, "SetRegImm": 5, "AddRegImm": 5,
    "Cmp": 6, "Test": 6, "Setcc": 6, "Cmov": 6, "PushFlags": 6, "PopFlags": 6,
    "JmpRel": 7, "JccRel": 7, "Exit": 7,
    "CallExtern": 8, "ResolveSym": 8, "KeyAdjust": 8, "KeyFeedback": 8,
    "Dup": 9, "Dup2": 9, "Rot": 9, "Swap": 9,
}
NUM_OP_CATS = 10
FEAT_DIM = NUM_OP_CATS + 5  # 10 op categories + [total_ops, in_deg, out_deg, avg_delta, is_entry]


class GATLayer(nn.Module):
    """Multi-Head Graph Attention Layer with residual connection."""
    def __init__(self, in_features, out_features, num_heads=4, dropout=0.1, alpha=0.2):
        super().__init__()
        self.in_features = in_features
        self.out_features = out_features
        self.num_heads = num_heads
        self.dropout = dropout
        self.alpha = alpha

        self.W = nn.Linear(in_features, out_features * num_heads, bias=False)
        self.a_src = nn.Parameter(torch.zeros(num_heads, out_features))
        self.a_dst = nn.Parameter(torch.zeros(num_heads, out_features))
        self.leaky_relu = nn.LeakyReLU(alpha)
        self.res = nn.Linear(in_features, out_features * num_heads) if in_features != out_features * num_heads else nn.Identity()

        nn.init.xavier_uniform_(self.W.weight)
        nn.init.xavier_uniform_(self.a_src)
        nn.init.xavier_uniform_(self.a_dst)

    def forward(self, h, adj):
        # h: [N, in_features], adj: [N, N] binary adjacency
        N = h.size(0)
        Wh = self.W(h).view(N, self.num_heads, self.out_features)  # [N, H, D]

        # Self-attention coefficients
        e_src = (Wh * self.a_src).sum(dim=-1)  # [N, H]
        e_dst = (Wh * self.a_dst).sum(dim=-1)  # [N, H]
        e = e_src.unsqueeze(1) + e_dst.unsqueeze(0)  # [N, N, H]
        e = self.leaky_relu(e)

        # Mask non-edges
        mask = (adj == 0).unsqueeze(-1)
        e = e.masked_fill(mask, -1e9)
        alpha = F.softmax(e, dim=1)  # [N, N, H]
        alpha = F.dropout(alpha, p=self.dropout, training=self.training)

        # Message aggregation
        # alpha: [N, N, H], Wh: [N, H, D]
        # h_out[i, h, d] = sum_j alpha[i, j, h] * Wh[j, h, d]
        h_out = torch.einsum('ijh,jhd->ihd', alpha, Wh).contiguous().view(N, self.num_heads * self.out_features)
        return F.elu(h_out + self.res(h))


class CFGGraphNetwork(nn.Module):
    """Graph Neural Network for CFG analysis, hub classification, and link recovery."""
    def __init__(self, in_dim=FEAT_DIM, hidden_dim=64, embed_dim=32, num_heads=4):
        super().__init__()
        self.gat1 = GATLayer(in_dim, hidden_dim // num_heads, num_heads=num_heads)
        self.gat2 = GATLayer(hidden_dim, embed_dim // num_heads, num_heads=num_heads)

        # Hub classification head (is this node a dispatcher / hub?)
        self.hub_head = nn.Sequential(
            nn.Linear(embed_dim, 16),
            nn.ReLU(),
            nn.Linear(16, 1)
        )

        # Bilinear link recovery head (probability of direct control flow)
        self.link_w = nn.Bilinear(embed_dim, embed_dim, 1)

    def get_embeddings(self, x, adj):
        h = self.gat1(x, adj)
        h = self.gat2(h, adj)
        return h

    def forward(self, x, adj):
        emb = self.get_embeddings(x, adj)
        hub_logits = self.hub_head(emb).squeeze(-1)
        return emb, hub_logits

    def predict_link(self, emb, u, v):
        return torch.sigmoid(self.link_w(emb[u:u+1], emb[v:v+1])).item()


def parse_cfg_json(json_path):
    """Parses a Stack-IR JSON program dump and builds the graph representation."""
    with open(json_path) as f:
        data = json.load(f)

    blocks = data.get("blocks", [])
    N = len(blocks)
    if N == 0:
        return None

    id_to_idx = {b["id"]: i for i, b in enumerate(blocks)}
    entry_id = data.get("entry_id", 0)

    # 1. Build adjacency from real JmpRel/JccRel ops AND decoy_edges
    succs = [[] for _ in range(N)]
    decoy_succs = [[] for _ in range(N)]
    for i, b in enumerate(blocks):
        for op_entry in b.get("ops", []):
            op = op_entry.get("op", "")
            args = op_entry.get("args", [])
            if op in ("JmpRel", "JccRel") and len(args) > 0:
                target_id = int(args[0])
                if target_id in id_to_idx:
                    succs[i].append(id_to_idx[target_id])
        # Bogus edges from OCaml Anti-GNN pass
        for dec_id in b.get("decoy_edges", []):
            if dec_id in id_to_idx:
                decoy_succs[i].append(id_to_idx[dec_id])

    adj = np.zeros((N, N), dtype=np.float32)
    # Self-loops for GAT stability
    for i in range(N):
        adj[i, i] = 1.0
        for j in succs[i]:
            adj[i, j] = 1.0
        # Decoy edges appear in the adjacency; the GNN cannot tell them apart
        for j in decoy_succs[i]:
            adj[i, j] = 1.0

    in_degrees = adj.sum(axis=0) - 1.0
    out_degrees = adj.sum(axis=1) - 1.0

    # Ground-truth degrees in actual execution (excluding bogus decoys)
    real_in_degrees = np.zeros(N, dtype=np.float32)
    real_out_degrees = np.array([len(s) for s in succs], dtype=np.float32)
    for s_list in succs:
        for tgt in s_list:
            real_in_degrees[tgt] += 1.0

    # 2. Extract block feature matrix
    X = np.zeros((N, FEAT_DIM), dtype=np.float32)
    is_hub_ground_truth = np.zeros(N, dtype=np.float32)

    for i, b in enumerate(blocks):
        ops = b.get("ops", [])
        total_ops = len(ops)
        cat_counts = np.zeros(NUM_OP_CATS, dtype=np.float32)
        total_delta = 0

        has_dispatcher_token = False
        for op_entry in ops:
            op = op_entry.get("op", "")
            cat = OP_CATEGORIES.get(op, 0)
            cat_counts[cat] += 1.0
            total_delta += op_entry.get("delta", 0)
            lbl = b.get("label", "").lower()
            if "dispatcher" in lbl or "cff_disp_0" in lbl:
                has_dispatcher_token = True

        # Normalized feature distribution
        if total_ops > 0:
            cat_counts /= total_ops
        X[i, :NUM_OP_CATS] = cat_counts
        X[i, NUM_OP_CATS] = math.log1p(total_ops)
        X[i, NUM_OP_CATS + 1] = math.log1p(in_degrees[i])
        X[i, NUM_OP_CATS + 2] = math.log1p(out_degrees[i])
        X[i, NUM_OP_CATS + 3] = total_delta / max(1, total_ops)
        X[i, NUM_OP_CATS + 4] = 1.0 if b["id"] == entry_id else 0.0

        # Ground-truth hub label: real execution dispatcher hubs
        if has_dispatcher_token or (real_in_degrees[i] >= 3 and real_out_degrees[i] >= 3):
            is_hub_ground_truth[i] = 1.0
    return {
        "phase": data.get("phase", "unknown"),
        "N": N,
        "X": torch.tensor(X),
        "adj": torch.tensor(adj),
        "succs": succs,
        "decoy_succs": decoy_succs,
        "hubs": torch.tensor(is_hub_ground_truth)
    }

def audit_cfg_phase(cfg_data, epochs=45):
    """Trains a GNN on the CFG and computes ML resilience metrics."""
    if cfg_data is None:
        return None

    X = cfg_data["X"]
    adj = cfg_data["adj"]
    N = cfg_data["N"]
    hubs = cfg_data["hubs"]

    model = CFGGraphNetwork(in_dim=FEAT_DIM, hidden_dim=64, embed_dim=32, num_heads=4)
    optimizer = torch.optim.Adam(model.parameters(), lr=0.01, weight_decay=1e-4)

    # 1. Unsupervised Link Prediction Loss + Hub Loss (with held-out validation split)
    pos_edges = []
    for i in range(N):
        for j in cfg_data["succs"][i]:
            pos_edges.append((i, j))

    # Real deobfuscation attack: the deobfuscator tries to filter out the
    # bogus decoy edges injected by ASGARD from the candidate CFG.
    decoy_list = []
    for i in range(N):
        for j in cfg_data.get("decoy_succs", [[] for _ in range(N)])[i]:
            decoy_list.append((i, j))

    if len(decoy_list) > 0:
        neg_edges = decoy_list
    else:
        neg_edges = []
        for i in range(N):
            for j in range(N):
                if i != j and j not in cfg_data["succs"][i]:
                    neg_edges.append((i, j))

    if len(neg_edges) > len(pos_edges) * 3:
        np.random.seed(1337)
        idx_sub = np.random.choice(len(neg_edges), len(pos_edges) * 3, replace=False)
        neg_edges = [neg_edges[k] for k in idx_sub]

    # 70/30 Train/Validation edge split (standard ML link prediction benchmark)
    np.random.seed(1337)
    perm_pos = np.random.permutation(len(pos_edges)) if len(pos_edges) > 0 else []
    n_pos_train = max(1, int(len(pos_edges) * 0.70)) if len(pos_edges) > 0 else 0
    train_pos = [pos_edges[k] for k in perm_pos[:n_pos_train]]
    val_pos   = [pos_edges[k] for k in perm_pos[n_pos_train:]] if len(pos_edges) > 1 else pos_edges

    perm_neg = np.random.permutation(len(neg_edges)) if len(neg_edges) > 0 else []
    n_neg_train = max(1, int(len(neg_edges) * 0.70)) if len(neg_edges) > 0 else 0
    train_neg = [neg_edges[k] for k in perm_neg[:n_neg_train]]
    val_neg   = [neg_edges[k] for k in perm_neg[n_neg_train:]] if len(neg_edges) > 1 else neg_edges

    model.train()
    for _ in range(epochs):
        optimizer.zero_grad()
        emb, hub_logits = model(X, adj)

        # Loss 1: Hub detection BCE
        hub_weight = torch.tensor([4.0]) if hubs.sum() > 0 else torch.tensor([1.0])
        hub_loss = F.binary_cross_entropy_with_logits(hub_logits, hubs, pos_weight=hub_weight)

        # Loss 2: Link Prediction on train edges
        if len(train_pos) > 0 and len(train_neg) > 0:
            pos_u = torch.tensor([e[0] for e in train_pos], dtype=torch.long)
            pos_v = torch.tensor([e[1] for e in train_pos], dtype=torch.long)
            neg_u = torch.tensor([e[0] for e in train_neg], dtype=torch.long)
            neg_v = torch.tensor([e[1] for e in train_neg], dtype=torch.long)

            pos_preds = model.link_w(emb[pos_u], emb[pos_v]).squeeze(-1)
            neg_preds = model.link_w(emb[neg_u], emb[neg_v]).squeeze(-1)

            link_loss = F.binary_cross_entropy_with_logits(pos_preds, torch.ones_like(pos_preds)) + \
                        F.binary_cross_entropy_with_logits(neg_preds, torch.zeros_like(neg_preds))
        else:
            link_loss = torch.tensor(0.0)

        total_loss = hub_loss + link_loss
        total_loss.backward()
        optimizer.step()

    # 2. Evaluation Metrics on held-out validation edges
    model.eval()
    with torch.no_grad():
        emb, hub_logits = model(X, adj)
        hub_probs = torch.sigmoid(hub_logits).numpy()

        # Hub detection accuracy / F1
        hubs_np = hubs.numpy()
        preds_hub = (hub_probs >= 0.5).astype(np.float32)
        tp = np.sum((preds_hub == 1) & (hubs_np == 1))
        fp = np.sum((preds_hub == 1) & (hubs_np == 0))
        fn = np.sum((preds_hub == 0) & (hubs_np == 1))
        hub_f1 = (2 * tp) / max(1, 2 * tp + fp + fn)

        # Link Prediction AUC on unseen validation edges
        if len(val_pos) > 0 and len(val_neg) > 0:
            vpos_u = torch.tensor([e[0] for e in val_pos], dtype=torch.long)
            vpos_v = torch.tensor([e[1] for e in val_pos], dtype=torch.long)
            vneg_u = torch.tensor([e[0] for e in val_neg], dtype=torch.long)
            vneg_v = torch.tensor([e[1] for e in val_neg], dtype=torch.long)

            val_pos_preds = torch.sigmoid(model.link_w(emb[vpos_u], emb[vpos_v])).squeeze(-1).numpy()
            val_neg_preds = torch.sigmoid(model.link_w(emb[vneg_u], emb[vneg_v])).squeeze(-1).numpy()
            y_true = np.concatenate([np.ones_like(val_pos_preds), np.zeros_like(val_neg_preds)])
            y_scores = np.concatenate([val_pos_preds, val_neg_preds])

            order = np.argsort(y_scores)[::-1]
            y_true_sorted = y_true[order]
            n_pos = np.sum(y_true == 1)
            n_neg = np.sum(y_true == 0)
            tps = np.cumsum(y_true_sorted)
            fps = np.cumsum(1.0 - y_true_sorted)
            tpr = tps / max(1, n_pos)
            fpr = fps / max(1, n_neg)
            if hasattr(np, "trapezoid"):
                edge_auc = float(np.trapezoid(tpr, fpr))
            elif hasattr(np, "trapz"):
                edge_auc = float(np.trapz(tpr, fpr))
            else:
                edge_auc = float(np.sum((fpr[1:] - fpr[:-1]) * (tpr[1:] + tpr[:-1]) / 2.0))
        else:
            edge_auc = 0.50

    # 3. Devirtualization Resistance Score computation
    # Information-theoretic structural leakage: R^2 explained variance of link prediction
    auc_advantage = max(0.0, edge_auc - 0.5) * 2.0
    auc_leakage = auc_advantage ** 2               # R^2 explained variance (0.0 = perfect unrecoverability)
    hub_leakage = hub_f1 ** 2                      # F1^2 hub identification power
    composite_resilience = max(0.0, 100.0 * (1.0 - (0.6 * auc_leakage + 0.4 * hub_leakage)))

    return {
        "phase": cfg_data["phase"],
        "blocks": N,
        "edges": len(pos_edges),
        "hub_f1": float(hub_f1),
        "edge_auc": float(edge_auc),
        "drs_cff": float(composite_resilience)
    }


if __name__ == "__main__":
    import sys
    dump_dir = sys.argv[1] if len(sys.argv) > 1 else "/tmp/pipeline_dump"
    print(f"[*] Auditing CFG Obfuscation Phases in '{dump_dir}' using Graph Attention Network...")
    phases = ["1-lowered", "2-amplified", "3-cff", "4-spaghetti", "5-ghost", "7-balance", "7-balance_(final)"]

    print(f"{'Phase':<16} {'Blocks':<8} {'Edges':<8} {'Hub-F1':<10} {'Edge-AUC':<10} {'DRS (0-100)':<12}")
    print("-" * 68)
    for p in phases:
        fpath = os.path.join(dump_dir, f"phase_{p}.json")
        if os.path.exists(fpath):
            cfg = parse_cfg_json(fpath)
            res = audit_cfg_phase(cfg)
            if res:
                print(f"{res['phase']:<16} {res['blocks']:<8} {res['edges']:<8} {res['hub_f1']:<10.3f} {res['edge_auc']:<10.3f} {res['drs_cff']:<12.1f}")
