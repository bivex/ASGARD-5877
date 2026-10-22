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
    """Graph Neural Network with Multi-Head Attention (GAT)."""
    def __init__(self, in_dim=FEAT_DIM, hidden_dim=64, embed_dim=32, num_heads=4):
        super().__init__()
        self.gat1 = GATLayer(in_dim, hidden_dim // num_heads, num_heads=num_heads)
        self.gat2 = GATLayer(hidden_dim, embed_dim // num_heads, num_heads=num_heads)
        self.hub_head = nn.Sequential(nn.Linear(embed_dim, 16), nn.ReLU(), nn.Linear(16, 1))
        self.link_w = nn.Bilinear(embed_dim, embed_dim, 1)

    def get_embeddings(self, x, adj):
        h = self.gat1(x, adj)
        return self.gat2(h, adj)

    def forward(self, x, adj):
        emb = self.get_embeddings(x, adj)
        hub_logits = self.hub_head(emb).squeeze(-1)
        return emb, hub_logits


class GCNLayer(nn.Module):
    """Kipf & Welling GCN layer with symmetric Laplacian normalization."""
    def __init__(self, in_features, out_features):
        super().__init__()
        self.W = nn.Linear(in_features, out_features, bias=False)
        self.res = nn.Linear(in_features, out_features) if in_features != out_features else nn.Identity()

    def forward(self, h, adj):
        N = h.size(0)
        A_tilde = adj + torch.eye(N, device=adj.device)
        deg = A_tilde.sum(dim=1)
        deg_inv_sqrt = torch.pow(deg.clamp(min=1e-5), -0.5)
        norm_adj = deg_inv_sqrt.unsqueeze(1) * A_tilde * deg_inv_sqrt.unsqueeze(0)
        out = norm_adj @ self.W(h)
        return F.elu(out + self.res(h))


class CFGGCNNetwork(nn.Module):
    """Spectral Graph Convolutional Network without attention."""
    def __init__(self, in_dim=FEAT_DIM, hidden_dim=64, embed_dim=32):
        super().__init__()
        self.gcn1 = GCNLayer(in_dim, hidden_dim)
        self.gcn2 = GCNLayer(hidden_dim, embed_dim)
        self.hub_head = nn.Sequential(nn.Linear(embed_dim, 16), nn.ReLU(), nn.Linear(16, 1))
        self.link_w = nn.Bilinear(embed_dim, embed_dim, 1)

    def forward(self, x, adj):
        h = self.gcn1(x, adj)
        h = self.gcn2(h, adj)
        hub_logits = self.hub_head(h).squeeze(-1)
        return h, hub_logits


class GraphSAGELayer(nn.Module):
    """GraphSAGE layer with mean neighborhood aggregation and concatenation."""
    def __init__(self, in_features, out_features):
        super().__init__()
        self.W = nn.Linear(in_features * 2, out_features)

    def forward(self, h, adj):
        deg = adj.sum(dim=1, keepdim=True).clamp(min=1.0)
        neigh_mean = (adj @ h) / deg
        concat = torch.cat([h, neigh_mean], dim=-1)
        return F.elu(self.W(concat))


class CFGGraphSAGENetwork(nn.Module):
    """Inductive GraphSAGE Network with mean pooling."""
    def __init__(self, in_dim=FEAT_DIM, hidden_dim=64, embed_dim=32):
        super().__init__()
        self.sage1 = GraphSAGELayer(in_dim, hidden_dim)
        self.sage2 = GraphSAGELayer(hidden_dim, embed_dim)
        self.hub_head = nn.Sequential(nn.Linear(embed_dim, 16), nn.ReLU(), nn.Linear(16, 1))
        self.link_w = nn.Bilinear(embed_dim, embed_dim, 1)

    def forward(self, x, adj):
        h = self.sage1(x, adj)
        h = self.sage2(h, adj)
        hub_logits = self.hub_head(h).squeeze(-1)
        return h, hub_logits


def compute_auc_hanley_mcneil(pos_preds, neg_preds):
    """Computes ROC-AUC along with Hanley & McNeil (1982) Standard Error, z-score,
    p-value against random baseline (0.50), and 95% Confidence Upper Bound."""
    n_pos = len(pos_preds)
    n_neg = len(neg_preds)
    if n_pos == 0 or n_neg == 0:
        return {"auc": 0.5, "se": 0.05, "z": 0.0, "p_value": 0.5, "auc_95_upper": 0.5}

    y_true = np.concatenate([np.ones_like(pos_preds), np.zeros_like(neg_preds)])
    y_scores = np.concatenate([pos_preds, neg_preds])
    order = np.argsort(y_scores)[::-1]
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

    # Hanley & McNeil (1982) Standard Error for ROC Area
    theta = max(0.001, min(0.999, auc))
    q1 = theta / (2.0 - theta)
    q2 = 2.0 * theta * theta / (1.0 + theta)
    num = theta * (1.0 - theta) + (n_pos - 1) * (q1 - theta * theta) + (n_neg - 1) * (q2 - theta * theta)
    se = math.sqrt(max(1e-9, num / (n_pos * n_neg)))
    z = (theta - 0.5) / se
    p_val = 0.5 * math.erfc(z / math.sqrt(2.0))
    auc_95_upper = min(1.0, theta + 1.96 * se)

    return {
        "auc": auc,
        "se": se,
        "z": z,
        "p_value": p_val,
        "auc_95_upper": auc_95_upper
    }


def evaluate_tabular_baseline(X, train_pos, train_neg, val_pos, val_neg):
    """Non-graph baseline: Regularized Logistic Regression on pairwise edge features."""
    def edge_features(edges):
        u = [e[0] for e in edges]
        v = [e[1] for e in edges]
        xu = X[u].numpy()
        xv = X[v].numpy()
        diff = np.abs(xu - xv)
        prod = xu * xv
        return np.concatenate([xu, xv, diff, prod], axis=-1)

    if len(train_pos) == 0 or len(train_neg) == 0 or len(val_pos) == 0 or len(val_neg) == 0:
        return compute_auc_hanley_mcneil(np.array([0.5]), np.array([0.5]))

    X_tr = np.vstack([edge_features(train_pos), edge_features(train_neg)])
    y_tr = np.concatenate([np.ones(len(train_pos)), np.zeros(len(train_neg))])

    X_tr_t = torch.tensor(X_tr, dtype=torch.float32)
    y_tr_t = torch.tensor(y_tr, dtype=torch.float32)
    lin = nn.Linear(X_tr.shape[1], 1)
    opt = torch.optim.Adam(lin.parameters(), lr=0.03, weight_decay=1e-3)
    for _ in range(35):
        opt.zero_grad()
        pred = lin(X_tr_t).squeeze(-1)
        loss = F.binary_cross_entropy_with_logits(pred, y_tr_t)
        loss.backward()
        opt.step()

    lin.eval()
    with torch.no_grad():
        val_p_x = torch.tensor(edge_features(val_pos), dtype=torch.float32)
        val_n_x = torch.tensor(edge_features(val_neg), dtype=torch.float32)
        p_scores = torch.sigmoid(lin(val_p_x)).squeeze(-1).numpy()
        n_scores = torch.sigmoid(lin(val_n_x)).squeeze(-1).numpy()
    return compute_auc_hanley_mcneil(p_scores, n_scores)

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

    torch.manual_seed(1337)
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

    # Helper: trains a graph model and evaluates link prediction
    def train_eval_graph_model(model, opt, n_epochs=35):
        model.train()
        for _ in range(n_epochs):
            opt.zero_grad()
            emb, hub_logits = model(X, adj)
            hub_weight = torch.tensor([4.0]) if hubs.sum() > 0 else torch.tensor([1.0])
            hub_loss = F.binary_cross_entropy_with_logits(hub_logits, hubs, pos_weight=hub_weight)
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
            (hub_loss + link_loss).backward()
            opt.step()

        model.eval()
        with torch.no_grad():
            emb, hub_logits = model(X, adj)
            hub_probs = torch.sigmoid(hub_logits).numpy()
            hubs_np = hubs.numpy()
            preds_hub = (hub_probs >= 0.5).astype(np.float32)
            tp = np.sum((preds_hub == 1) & (hubs_np == 1))
            fp = np.sum((preds_hub == 1) & (hubs_np == 0))
            fn = np.sum((preds_hub == 0) & (hubs_np == 1))
            hub_f1 = (2 * tp) / max(1, 2 * tp + fp + fn)

            if len(val_pos) > 0 and len(val_neg) > 0:
                vpos_u = torch.tensor([e[0] for e in val_pos], dtype=torch.long)
                vpos_v = torch.tensor([e[1] for e in val_pos], dtype=torch.long)
                vneg_u = torch.tensor([e[0] for e in val_neg], dtype=torch.long)
                vneg_v = torch.tensor([e[1] for e in val_neg], dtype=torch.long)
                val_pos_preds = torch.sigmoid(model.link_w(emb[vpos_u], emb[vpos_v])).squeeze(-1).numpy()
                val_neg_preds = torch.sigmoid(model.link_w(emb[vneg_u], emb[vneg_v])).squeeze(-1).numpy()
                stats = compute_auc_hanley_mcneil(val_pos_preds, val_neg_preds)
            else:
                stats = {"auc": 0.50, "se": 0.05, "z": 0.0, "p_value": 0.50, "auc_95_upper": 0.50}
        return hub_f1, stats

    # 1. Model A: GAT (Graph Attention Network)
    torch.manual_seed(1337)
    gat_model = CFGGraphNetwork(in_dim=FEAT_DIM, hidden_dim=64, embed_dim=32, num_heads=4)
    gat_opt = torch.optim.Adam(gat_model.parameters(), lr=0.01, weight_decay=1e-4)
    hub_f1_gat, gat_stats = train_eval_graph_model(gat_model, gat_opt, n_epochs=epochs)

    # 2. Model B: GCN (Kipf & Welling Spectral Convolution)
    torch.manual_seed(1337)
    gcn_model = CFGGCNNetwork(in_dim=FEAT_DIM, hidden_dim=64, embed_dim=32)
    gcn_opt = torch.optim.Adam(gcn_model.parameters(), lr=0.01, weight_decay=1e-4)
    hub_f1_gcn, gcn_stats = train_eval_graph_model(gcn_model, gcn_opt, n_epochs=epochs)

    # 3. Model C: GraphSAGE (Mean Pooling + Concatenation)
    torch.manual_seed(1337)
    sage_model = CFGGraphSAGENetwork(in_dim=FEAT_DIM, hidden_dim=64, embed_dim=32)
    sage_opt = torch.optim.Adam(sage_model.parameters(), lr=0.01, weight_decay=1e-4)
    hub_f1_sage, sage_stats = train_eval_graph_model(sage_model, sage_opt, n_epochs=epochs)

    # 4. Model D: Non-Graph Tabular Baseline (Regularized Logistic on edge feature pairs)
    tab_stats = evaluate_tabular_baseline(X, train_pos, train_neg, val_pos, val_neg)

    # Conservative DRS: computed using the 95% Confidence Upper Bound on AUC
    def compute_drs(stats, hub_f1):
        auc_adv = max(0.0, stats["auc_95_upper"] - 0.5) * 2.0
        auc_leak = auc_adv ** 2
        hub_leak = hub_f1 ** 2
        return max(0.0, 100.0 * (1.0 - (0.6 * auc_leak + 0.4 * hub_leak)))

    drs_gat = compute_drs(gat_stats, hub_f1_gat)
    drs_gcn = compute_drs(gcn_stats, hub_f1_gcn)
    drs_sage = compute_drs(sage_stats, hub_f1_sage)
    drs_tab = compute_drs(tab_stats, 0.0)

    # The reported DRS is the CONSERVATIVE MINIMUM across all 4 attack architectures
    conservative_drs = min([drs_gat, drs_gcn, drs_sage, drs_tab])
    worst_stats = max([gat_stats, gcn_stats, sage_stats, tab_stats], key=lambda s: s["auc_95_upper"])

    return {
        "phase": cfg_data["phase"],
        "blocks": N,
        "edges": len(pos_edges),
        "hub_f1": float(hub_f1_gat),
        "edge_auc": float(gat_stats["auc"]),
        "edge_auc_gcn": float(gcn_stats["auc"]),
        "edge_auc_sage": float(sage_stats["auc"]),
        "edge_auc_tab": float(tab_stats["auc"]),
        "worst_auc_95": float(worst_stats["auc_95_upper"]),
        "z_score": float(worst_stats["z"]),
        "p_value": float(worst_stats["p_value"]),
        "drs_cff": float(conservative_drs)
    }

if __name__ == "__main__":
    import sys
    dump_dir = sys.argv[1] if len(sys.argv) > 1 else "/tmp/pipeline_dump"
    print(f"[*] Auditing CFG Obfuscation Phases in '{dump_dir}' using Multi-Model Red-Team Ensemble...")
    print("    Models: GAT (Attention), GCN (Spectral), GraphSAGE (Inductive), Tabular (Pairwise Logistic)")
    phases = ["1-lowered", "2-amplified", "3-cff", "4-spaghetti", "5-ghost", "7-balance", "7-balance_(final)"]

    header = f"{'Phase':<16} {'Blocks':<7} {'Edges':<7} {'Hub-F1':<8} {'GAT':<7} {'GCN':<7} {'SAGE':<7} {'Tab':<7} {'Worst-AUC95':<12} {'p-val':<8} {'DRS (0-100)':<12}"
    print(header)
    print("-" * len(header))
    for p in phases:
        fpath = os.path.join(dump_dir, f"phase_{p}.json")
        if os.path.exists(fpath):
            cfg = parse_cfg_json(fpath)
            res = audit_cfg_phase(cfg)
            if res:
                row = f"{res['phase']:<16} {res['blocks']:<7} {res['edges']:<7} {res['hub_f1']:<8.3f} {res['edge_auc']:<7.3f} {res['edge_auc_gcn']:<7.3f} {res['edge_auc_sage']:<7.3f} {res['edge_auc_tab']:<7.3f} {res['worst_auc_95']:<12.3f} {res['p_value']:<8.4f} {res['drs_cff']:<12.1f}"
                print(row)
