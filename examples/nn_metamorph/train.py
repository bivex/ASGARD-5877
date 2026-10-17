#!/usr/bin/env python3
"""
ASGARD-5877 nn_metamorph - MLX training driver + architecture ladder
=====================================================================

Trains neural networks to emulate the I/O behavior of the ASGARD-protected
kernels (ground truth: the bit-exact numpy reference validated against the
real protected binary by validate_ref.py).

Single run:
    python3 train.py --arch mlp --width 512 --depth 4 --epochs 12

Architecture sweep (the editable LADDER below is what you iterate on):
    python3 train.py --sweep
    python3 train.py --sweep --rung 'mlp-s|xf-s'    # regex filter

Every run appends a JSON record to results/results.jsonl so architectures
can be compared across sessions.

Metrics:
    bit_acc   - per-bit accuracy over all 64 output bits (0.5 = coin flip)
    lo32/hi32 - bit accuracy split by output half (low bits carry the
                learnable carry-chain structure; high bits avalanche)
    hamming   - mean Hamming distance to the true 64-bit word (32 = random)
    exact     - rate of exact 64-bit matches
    p_early/p_full (compute only) - bit accuracy conditioned on the kernel's
                early-exit path (learnable) vs the full hash path (~ coin flip)

MLX 0.31.2 patterns (verified):
    from mlx.optimizers import Adam            # not mlx.nn.optim
    nn.losses.binary_cross_entropy(logits, y)  # with_logits=True by default
    nn.value_and_grad(model, fn)               # fn takes ONLY data args
"""

import argparse
import json
import os
import re
import time
from datetime import datetime, timezone

import mlx.core as mx
import mlx.nn as nn
import numpy as np
from mlx.optimizers import Adam

from dataset import make_dataset
from models import build_model, n_params

# --------------------------------------------------------------------------
# Architecture ladder -- edit this list to iterate on architectures.
# Epochs on the big transformer rungs are capped: d256/L4 measures ~56 s
# per 200k-sample epoch on an M-series laptop.
# --------------------------------------------------------------------------
LADDER = [
    dict(name="mlp-s", arch="mlp",         width=256,  depth=2, epochs=12, lr=1e-3, batch=4096),
    dict(name="mlp-m", arch="mlp",         width=512,  depth=4, epochs=12, lr=1e-3, batch=4096),
    dict(name="mlp-l", arch="mlp",         width=1024, depth=6, epochs=8,  lr=1e-3, batch=4096),
    dict(name="xf-s",  arch="transformer", dims=128, heads=4, layers=2,   epochs=8,  lr=3e-4, batch=1024),
    dict(name="xf-m",  arch="transformer", dims=192, heads=6, layers=3,   epochs=6,  lr=3e-4, batch=1024),
    dict(name="xf-l",  arch="transformer", dims=256, heads=8, layers=4,   epochs=4,  lr=3e-4, batch=512),
]

RESULTS_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "results")


# --------------------------------------------------------------------------
# Evaluation
# --------------------------------------------------------------------------
def evaluate(model: nn.Module, X: mx.array, Y: mx.array, aux,
             batch: int = 8192) -> dict:
    preds = []
    for i in range(0, X.shape[0], batch):
        preds.append((model(X[i:i + batch]) > 0).astype(mx.float32))
    pred = mx.concatenate(preds)
    eq = (pred == Y).astype(mx.float32)

    m = dict(
        bit_acc=float(eq.mean().item()),
        acc_lo32=float(eq[:, :32].mean().item()),
        acc_hi32=float(eq[:, 32:].mean().item()),
        hamming_mean=float(mx.abs(pred - Y).sum(axis=1).mean().item()),
        exact_rate=float((eq.sum(axis=1) == 64).astype(mx.float32).mean().item()),
    )
    if aux is not None:
        # mlx has no boolean fancy indexing: masked means via multiply/sum.
        row_acc = eq.mean(axis=1)
        early = (aux == 0).astype(mx.float32)
        full = 1.0 - early
        n_early = float(early.sum().item())
        n_full = float(full.sum().item())
        if n_early > 0:
            m["acc_path_early"] = float((row_acc * early).sum().item() / n_early)
        if n_full > 0:
            m["acc_path_full"] = float((row_acc * full).sum().item() / n_full)
    return m


# --------------------------------------------------------------------------
# Training
# --------------------------------------------------------------------------
def train_one(cfg: dict, data: dict, kernel: str, seed: int,
              eval_every: int, loss_name: str) -> tuple:
    """Returns (record_dict, final_val_metrics)."""
    mx.random.seed(seed)  # weight init determinism

    model = build_model(cfg["arch"], kernel, cfg)
    is_tok = cfg["arch"] == "transformer"
    Xtr = data["train"]["X_tok"] if is_tok else data["train"]["X_bits"]
    Ytr = data["train"]["Y"]
    Xva = data["val"]["X_tok"] if is_tok else data["val"]["X_bits"]
    Yva = data["val"]["Y"]
    Xte = data["test"]["X_tok"] if is_tok else data["test"]["X_bits"]
    Yte = data["test"]["Y"]
    aux_va, aux_te = data["val"]["aux"], data["test"]["aux"]

    def loss_fn(xb, yb):
        logits = model(xb)
        if loss_name == "bce":
            return nn.losses.binary_cross_entropy(logits, yb)
        # mse ablation: tanh-squashed predictions vs {-1,+1} targets
        return mx.mean(mx.square(mx.tanh(logits) - (2.0 * yb - 1.0)))

    loss_and_grad = nn.value_and_grad(model, loss_fn)  # fn takes ONLY data args
    opt = Adam(learning_rate=cfg["lr"])

    n = Xtr.shape[0]
    B = cfg["batch"]
    rng = np.random.default_rng(seed)  # data order determinism
    t0 = time.time()
    for epoch in range(cfg["epochs"]):
        perm = mx.array(rng.permutation(n))
        for i in range(0, n, B):
            sel = perm[i:i + B]
            loss, grads = loss_and_grad(Xtr[sel], Ytr[sel])
            opt.update(model, grads)
            mx.eval(model.parameters(), opt.state)
        if (epoch + 1) % eval_every == 0 or epoch == cfg["epochs"] - 1:
            vm = evaluate(model, Xva, Yva, aux_va)
            print(f"    [{cfg['name']}/{kernel}] epoch {epoch + 1}/{cfg['epochs']} "
                  f"loss={float(loss.item()):.4f} val_bit_acc={vm['bit_acc']:.4f} "
                  f"val_hamming={vm['hamming_mean']:.2f}")
    train_time = time.time() - t0

    val_m = evaluate(model, Xva, Yva, aux_va)
    test_m = evaluate(model, Xte, Yte, aux_te)

    record = dict(
        ts=datetime.now(timezone.utc).isoformat(timespec="seconds"),
        kernel=kernel,
        name=cfg["name"],
        cfg={k: v for k, v in cfg.items() if k != "name"},
        params=n_params(model),
        loss=loss_name,
        seed=seed,
        train_time_s=round(train_time, 2),
        val=val_m,
        test=test_m,
    )
    return record, val_m


def append_record(path: str, record: dict) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "a") as fh:
        fh.write(json.dumps(record) + "\n")


def print_table(rows: list) -> None:
    hdr = (f"{'name':<8} {'params':>9} {'time_s':>7} {'bit_acc':>8} "
           f"{'lo32':>7} {'hi32':>7} {'hamming':>8} {'exact':>7} {'p_early':>8} {'p_full':>7}")
    print(hdr)
    print("-" * len(hdr))
    for r in rows:
        v = r["val"]
        print(f"{r['name']:<8} {r['params']:>9,} {r['train_time_s']:>7.1f} "
              f"{v['bit_acc']:>8.4f} {v['acc_lo32']:>7.4f} {v['acc_hi32']:>7.4f} "
              f"{v['hamming_mean']:>8.2f} {v['exact_rate']:>7.4f} "
              f"{v.get('acc_path_early', float('nan')):>8.4f} "
              f"{v.get('acc_path_full', float('nan')):>7.4f}")


# --------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------
def main() -> None:
    ap = argparse.ArgumentParser(description="ASGARD nn_metamorph training")
    ap.add_argument("--kernel", choices=["compute", "mix", "both"], default="compute")
    ap.add_argument("--arch", choices=["mlp", "transformer"], default="mlp")
    ap.add_argument("--depth", type=int, default=4)
    ap.add_argument("--width", type=int, default=512)
    ap.add_argument("--dims", type=int, default=128)
    ap.add_argument("--heads", type=int, default=4)
    ap.add_argument("--layers", type=int, default=2)
    ap.add_argument("--epochs", type=int, default=12)
    ap.add_argument("--lr", type=float, default=1e-3)
    ap.add_argument("--batch", type=int, default=4096)
    ap.add_argument("--n-train", type=int, default=200000)
    ap.add_argument("--n-val", type=int, default=20000)
    ap.add_argument("--n-test", type=int, default=40000)
    ap.add_argument("--seed", type=int, default=0, help="model init seed")
    ap.add_argument("--data-seed", type=int, default=1)
    ap.add_argument("--loss", choices=["bce", "mse"], default="bce")
    ap.add_argument("--eval-every", type=int, default=4)
    ap.add_argument("--out", default=os.path.join(RESULTS_DIR, "results.jsonl"))
    ap.add_argument("--sweep", action="store_true", help="run the LADDER")
    ap.add_argument("--rung", default=None, help="regex filter on ladder rung names")
    args = ap.parse_args()

    kernels = ["compute", "mix"] if args.kernel == "both" else [args.kernel]

    for kernel in kernels:
        print(f"== dataset [{kernel}] (train {args.n_train:,} / "
              f"val {args.n_val:,} / test {args.n_test:,}) ==")
        t0 = time.time()
        ds_np = make_dataset(kernel, args.n_train, args.n_val, args.n_test,
                             seed=args.data_seed)
        data = {
            split: dict(
                X_bits=mx.array(ds_np[split]["X_bits"]),
                X_tok=mx.array(ds_np[split]["X_tok"]),
                Y=mx.array(ds_np[split]["Y"]),
                aux=None if ds_np[split]["aux"] is None
                else mx.array(ds_np[split]["aux"]),
            )
            for split in ("train", "val", "test")
        }
        mx.eval(*([data[s][k] for s in data for k in data[s]]))
        print(f"   generated in {time.time() - t0:.1f}s")

        if args.sweep:
            ladder = [c for c in LADDER
                      if args.rung is None or re.search(args.rung, c["name"])]
        else:
            ladder = [dict(name=f"{args.arch}", arch=args.arch,
                           **({"width": args.width, "depth": args.depth}
                              if args.arch == "mlp" else
                              {"dims": args.dims, "heads": args.heads,
                               "layers": args.layers}),
                           epochs=args.epochs, lr=args.lr, batch=args.batch)]

        records = []
        for cfg in ladder:
            print(f"== training {cfg['name']} [{kernel}] ==")
            record, _ = train_one(cfg, data, kernel, args.seed,
                                  args.eval_every, args.loss)
            append_record(args.out, record)
            records.append(record)

        print(f"\n== architecture comparison [{kernel}] (val split, "
              f"loss={args.loss}) ==")
        print_table(records)
        print(f"records appended to {args.out}")


if __name__ == "__main__":
    main()
