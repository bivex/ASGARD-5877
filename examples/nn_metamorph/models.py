#!/usr/bin/env python3
"""
ASGARD-5877 nn_metamorph - MLX models
=====================================

Two architectures mapping kernel inputs to 64 per-bit logits:

  * MLP                - flat bit vector (dataset.featurize_*)
  * BitTokenTransformer - byte-value token grid (dataset.token_ids_*)

MLX 0.31.2 notes baked in:
  - layers must live in an nn.Sequential (plain list attributes are NOT
    registered as parameters);
  - TransformerEncoder.__call__(x, mask) takes a REQUIRED positional mask
    (pass None for full attention);
  - from mlx.optimizers import Adam  (mlx.nn.optim does not exist).
"""

import mlx.core as mx
import mlx.nn as nn
from mlx.utils import tree_flatten

from dataset import N_TOKENS_COMPUTE, N_TOKENS_MIX, VOCAB

IN_DIM = {"compute": 296, "mix": 646}
N_TOKENS = {"compute": N_TOKENS_COMPUTE, "mix": N_TOKENS_MIX}
FIELD_SIZES = {"compute": [8, 8, 4, 8, 8, 1],   # a, b, c, d, e, flags
               "mix": [8, 65]}                    # seed, blob+length


class MLP(nn.Module):
    """Baseline: depth x (Linear -> ReLU) over the flat bit vector."""

    def __init__(self, in_dim: int, width: int, depth: int):
        super().__init__()
        layers = []
        d = in_dim
        for _ in range(depth):
            layers.append(nn.Linear(d, width))
            layers.append(nn.ReLU())
            d = width
        layers.append(nn.Linear(d, 64))
        self.net = nn.Sequential(*layers)

    def __call__(self, x: mx.array) -> mx.array:
        return self.net(x)


class BitTokenTransformer(nn.Module):
    """Byte tokens + positional + field embeddings -> encoder -> mean pool."""

    def __init__(self, n_tokens: int, vocab: int, dims: int, heads: int,
                 layers: int, field_sizes=None):
        super().__init__()
        self.n_tokens = n_tokens
        self.field_sizes = field_sizes or [n_tokens]
        n_fields = len(self.field_sizes)
        self.tok = nn.Embedding(vocab, dims)
        self.pos = nn.Embedding(n_tokens, dims)
        self.field = nn.Embedding(n_fields, dims)
        self.enc = nn.TransformerEncoder(layers, dims, heads, mlp_dims=2 * dims)
        self.head = nn.Linear(dims, 64)

    def __call__(self, idx: mx.array) -> mx.array:
        T = idx.shape[1]
        field_ids = mx.concatenate(
            [mx.full((s,), i, mx.int32) for i, s in enumerate(self.field_sizes)])
        h = self.tok(idx) + self.pos(mx.arange(T))[None, :, :] + self.field(field_ids)[None, :, :]
        h = self.enc(h, None)   # mask is a required positional arg in 0.31.2
        return self.head(mx.mean(h, axis=1))


def build_model(arch: str, kernel: str, cfg: dict) -> nn.Module:
    if arch == "mlp":
        return MLP(IN_DIM[kernel], cfg["width"], cfg["depth"])
    if arch == "transformer":
        return BitTokenTransformer(N_TOKENS[kernel], VOCAB, cfg["dims"],
                                   cfg["heads"], cfg["layers"],
                                   field_sizes=FIELD_SIZES[kernel])
    raise ValueError(f"unknown arch: {arch}")


def n_params(model: nn.Module) -> int:
    return sum(p.size for _, p in tree_flatten(model.parameters()))
