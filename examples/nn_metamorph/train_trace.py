#!/usr/bin/env python3
"""
ASGARD-5877 nn_metamorph - VM trace learnability bench
======================================================

Measures how predictable the ASGARD VM's dynamic behavior is for a neural
attacker, and whether that knowledge transfers between metamorphic seeds.

Task: next-handler-class prediction over the execution trace collected by
collect_traces.py (semantic handler classes, comparable across builds).

Reported per (config, seed):
    unigram  - per-build token frequency baseline (lower bound of structure)
    nn_within    - transformer accuracy, train and test on the SAME build
    nn_cross     - same model evaluated on the OTHER seed of the same config
                   (transfer = how much an attacker's model survives a
                   metamorphic rebuild)

Read it like this:
    nn_within >> unigram   -> the trace carries sequential structure an
                              attacker can exploit (control-flow leak)
    nn_cross ~= nn_within  -> the leak is seed-INDEPENDENT: rebuilding the
                              protection does not refresh the attacker's model
    nn_cross << nn_within  -> metamorphism works: knowledge does not transfer

Usage:
    python3 train_trace.py [--configs full plain] [--seeds 1001 2002]
                           [--kernel compute] [--epochs 3] [--windows 60000]
"""

import argparse
import os

import mlx.core as mx
import mlx.nn as nn
import numpy as np
from mlx.optimizers import Adam

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
TRACES_DIR = os.path.join(SCRIPT_DIR, "traces")

CTX = 32          # context window (previous handler classes)
DIMS = 64
HEADS = 4
LAYERS = 2


class TraceTransformer(nn.Module):
    def __init__(self, vocab: int):
        super().__init__()
        self.tok = nn.Embedding(vocab, DIMS)
        self.pos = nn.Embedding(CTX, DIMS)
        self.enc = nn.TransformerEncoder(LAYERS, DIMS, HEADS, mlp_dims=2 * DIMS)
        self.head = nn.Linear(DIMS, vocab)

    def __call__(self, idx: mx.array) -> mx.array:
        h = self.tok(idx) + self.pos(mx.arange(CTX))[None, :, :]
        h = self.enc(h, None)          # mask is a required positional arg
        return self.head(h[:, -1, :])  # predict the next token


def load_segments(tag: str, kernel: str):
    d = np.load(os.path.join(TRACES_DIR, f"{tag}.npz"))
    flat, offs, kidx = d["flat"], d["offs"], d["kidx"]
    want = 0 if kernel == "compute" else 1
    # drop segments shorter than the context window (early-exit vectors
    # produce tiny traces that cannot yield a full window)
    return [flat[offs[i]:offs[i + 1]]
            for i in range(len(kidx)) if kidx[i] == want
            and offs[i + 1] - offs[i] > CTX]


def sample_windows(segs: list, n: int, rng: np.random.Generator, ctx: int = CTX):
    """n random (context, target) windows across the segments."""
    seg_idx = rng.integers(0, len(segs), size=n)
    pos = np.array([rng.integers(ctx, len(segs[s])) for s in seg_idx])
    X = np.zeros((n, ctx), dtype=np.int32)
    y = np.zeros(n, dtype=np.int32)
    for j, (s, p) in enumerate(zip(seg_idx, pos)):
        X[j] = segs[s][p - ctx:p]
        y[j] = segs[s][p]
    return X, y


def unigram_accuracy(train_segs, test_segs) -> float:
    counts = np.bincount(np.concatenate(train_segs), minlength=256)
    pred = int(counts.argmax())
    test = np.concatenate(test_segs)
    return float((test == pred).mean())


def evaluate(model, segs, n: int, rng) -> float:
    X, y = sample_windows(segs, n, rng)
    pred = []
    for i in range(0, len(X), 4096):
        pred.append(np.argmax(model(mx.array(X[i:i + 4096])), axis=1))
    pred = np.concatenate(pred)
    return float((pred == y).mean())


def train_and_eval(tag: str, other_tag: str, kernel: str, args) -> dict:
    train_segs = load_segments(tag, kernel)
    other_segs = load_segments(other_tag, kernel)
    split = int(len(train_segs) * 0.8)
    tr, te = train_segs[:split], train_segs[split:]
    rng = np.random.default_rng(args.seed)

    vocab = 256
    mx.random.seed(args.seed)
    model = TraceTransformer(vocab)
    opt = Adam(learning_rate=1e-3)

    def loss_fn(xb, yb):
        # mlx cross_entropy returns per-sample losses; the vjp needs a scalar
        return mx.mean(nn.losses.cross_entropy(model(xb), yb))

    loss_and_grad = nn.value_and_grad(model, loss_fn)
    for epoch in range(args.epochs):
        for i in range(0, args.windows, args.batch):
            X, y = sample_windows(tr, args.batch, rng)
            loss, grads = loss_and_grad(mx.array(X), mx.array(y))
            opt.update(model, grads)
            mx.eval(model.parameters(), opt.state)
        ev_rng = np.random.default_rng(123)
        acc = evaluate(model, te, 5000, ev_rng)
        print(f"    [{tag}/{kernel}] epoch {epoch + 1}/{args.epochs} "
              f"loss={float(loss.item()):.4f} test_next_acc={acc:.4f}")

    ev_rng = np.random.default_rng(123)
    return dict(
        tag=tag,
        unigram=unigram_accuracy(tr, te),
        nn_within=evaluate(model, te, 10000, ev_rng),
        nn_cross=evaluate(model, other_segs, 10000, ev_rng),
        steps_per_trace=float(np.mean([len(s) for s in train_segs])),
    )


def main() -> None:
    ap = argparse.ArgumentParser(description="VM trace learnability bench")
    ap.add_argument("--configs", nargs="+", default=["full", "plain"])
    ap.add_argument("--seeds", type=int, nargs="+", default=[1001, 2002])
    ap.add_argument("--kernel", choices=["compute", "mix"], default="compute")
    ap.add_argument("--epochs", type=int, default=3)
    ap.add_argument("--windows", type=int, default=60000,
                    help="training windows per epoch")
    ap.add_argument("--batch", type=int, default=512)
    ap.add_argument("--seed", type=int, default=0)
    args = ap.parse_args()

    assert len(args.seeds) >= 2, "cross-seed transfer needs >= 2 seeds"
    rows = []
    for config in args.configs:
        for seed in args.seeds:
            tag, other = f"{config}_{seed}", f"{config}_{args.seeds[1] if seed == args.seeds[0] else args.seeds[0]}"
            print(f"== training [{tag}] -> transfer test on [{other}] ==")
            rows.append(train_and_eval(tag, other, args.kernel, args))

    hdr = (f"{'build':<12} {'steps/trace':>11} {'unigram':>8} "
           f"{'nn_within':>10} {'nn_cross':>9} {'transfer':>9}")
    print(f"\n== trace learnability [{args.kernel}] "
          f"(next-handler accuracy, chance = 1/256) ==")
    print(hdr)
    print("-" * len(hdr))
    for r in rows:
        tr = r["nn_cross"] / r["nn_within"] if r["nn_within"] else 0.0
        print(f"{r['tag']:<12} {r['steps_per_trace']:>11.0f} {r['unigram']:>8.4f} "
              f"{r['nn_within']:>10.4f} {r['nn_cross']:>9.4f} {tr:>9.2f}")


if __name__ == "__main__":
    main()
