#!/usr/bin/env python3
"""
ASGARD-5877: Neural VM Opcode & Superoperator Synthesizer
=========================================================
Implements a Trajectory Balance GFlowNet (Generative Flow Network)
coupled with a formal Z3 SMT oracle to discover novel, provably sound,
non-linear VM opcodes and superoperators for the ASGARD Stack-VM / JIT architecture.

Key Features & Fixes:
  1. Full Autograd Flow (P0): Unbroken autograd graph across batched rollout;
     all model weights and log_Z receive valid gradients on every training step.
  2. Consistent Deterministic Backward Policy (P1): Sequence graph is an
     autoregressive tree with a unique parent for each prefix; log P_B == 0.0.
  3. Batched Parallel Rollout (P2): Rollout is vectorized across batch_size
     parallel trajectories with dynamic per-element stack-depth masking.
  4. Joint Grad Clipping (P3): Clips norm across both model parameters AND log_Z.
  5. Trivial Algebraic Collapse Filter (Anti-Peephole): Rejects / penalizes
     pseudo-MBA that trivially collapses under standard term rewriting (e.g. (x+c)-c).
     Ensures non-linear mixed Boolean-arithmetic entanglement survives z3.simplify.
"""

import sys
import os
import math
import time
import random
from typing import List, Tuple, Optional, Dict

import torch
import torch.nn as nn
import torch.optim as optim
from torch.distributions.categorical import Categorical
import z3

# ---------------------------------------------------------------------------
# 1. ASGARD Stack-IR Grammar & Hard Invariants
# ---------------------------------------------------------------------------

class OpDef:
    def __init__(self, name: str, min_depth: int, delta: int, is_terminal: bool = False):
        self.name = name
        self.min_depth = min_depth  # Min stack depth required to execute op
        self.delta = delta          # Net stack change (+1, 0, -1, +2)
        self.is_terminal = is_terminal

# Allowable Stack-IR primitives for JIT / Stack-VM
VOCAB: List[OpDef] = [
    OpDef("ADD",       min_depth=2, delta=-1),
    OpDef("SUB",       min_depth=2, delta=-1),
    OpDef("MUL",       min_depth=2, delta=-1),
    OpDef("NOR",       min_depth=2, delta=-1),
    OpDef("NAND",      min_depth=2, delta=-1),
    OpDef("DUP",       min_depth=1, delta=1),
    OpDef("DUP2",      min_depth=2, delta=2),
    OpDef("SWAP",      min_depth=2, delta=0),
    OpDef("ROT",       min_depth=3, delta=0),
    OpDef("PUSH_0",    min_depth=0, delta=1),
    OpDef("PUSH_1",    min_depth=0, delta=1),
    OpDef("PUSH_2",    min_depth=0, delta=1),
    OpDef("PUSH_M1",   min_depth=0, delta=1),  # -1 (0xFFFFFFFFFFFFFFFF)
    OpDef("PUSH_ODD",  min_depth=0, delta=1),  # Hull-Dobell ring multiplier
    OpDef("HALT",      min_depth=1, delta=0, is_terminal=True),
]

OP_TO_ID = {op.name: idx for idx, op in enumerate(VOCAB)}
ID_TO_OP = {idx: op for idx, op in enumerate(VOCAB)}
VOCAB_SIZE = len(VOCAB)
HALT_ID = OP_TO_ID["HALT"]
START_TOKEN = VOCAB_SIZE

MAX_STACK_DEPTH = 4   # Evaluation window limit in ASGARD Stack-JIT
MAX_TRAJECTORY_LEN = 16
MASK64 = 0xFFFFFFFFFFFFFFFF
ODD_CONST = 0x58771337CAFEBEED

# ---------------------------------------------------------------------------
# 2. Fast Concrete Evaluator & Formal Z3 Verification Oracle
# ---------------------------------------------------------------------------

def eval_concrete(ops: List[str], x: int, y: int) -> Optional[int]:
    """Microsecond-scale Python 64-bit stack simulation for fast rejection."""
    stk = [y & MASK64, x & MASK64]
    for op in ops:
        if op == "HALT":
            break
        elif op == "ADD":
            if len(stk) < 2: return None
            b, a = stk.pop(), stk.pop()
            stk.append((a + b) & MASK64)
        elif op == "SUB":
            if len(stk) < 2: return None
            b, a = stk.pop(), stk.pop()
            stk.append((a - b) & MASK64)
        elif op == "MUL":
            if len(stk) < 2: return None
            b, a = stk.pop(), stk.pop()
            stk.append((a * b) & MASK64)
        elif op == "NOR":
            if len(stk) < 2: return None
            b, a = stk.pop(), stk.pop()
            stk.append((~(a | b)) & MASK64)
        elif op == "NAND":
            if len(stk) < 2: return None
            b, a = stk.pop(), stk.pop()
            stk.append((~(a & b)) & MASK64)
        elif op == "DUP":
            if len(stk) < 1: return None
            stk.append(stk[-1])
        elif op == "DUP2":
            if len(stk) < 2: return None
            stk.extend([stk[-2], stk[-1]])
        elif op == "SWAP":
            if len(stk) < 2: return None
            stk[-1], stk[-2] = stk[-2], stk[-1]
        elif op == "ROT":
            if len(stk) < 3: return None
            a, b, c = stk.pop(), stk.pop(), stk.pop()
            stk.extend([b, a, c])
        elif op == "PUSH_0":
            stk.append(0)
        elif op == "PUSH_1":
            stk.append(1)
        elif op == "PUSH_2":
            stk.append(2)
        elif op == "PUSH_M1":
            stk.append(MASK64)
        elif op == "PUSH_ODD":
            stk.append(ODD_CONST)
        if len(stk) > MAX_STACK_DEPTH:
            return None
    return stk[-1] if len(stk) == 1 else None

def build_z3_expr(ops: List[str], x: z3.BitVecRef, y: z3.BitVecRef) -> Optional[z3.BitVecRef]:
    """Builds a Z3 BitVec expression tree from stack operations."""
    stk = [y, x]
    try:
        for op in ops:
            if op == "HALT":
                break
            elif op == "ADD":
                b, a = stk.pop(), stk.pop()
                stk.append(a + b)
            elif op == "SUB":
                b, a = stk.pop(), stk.pop()
                stk.append(a - b)
            elif op == "MUL":
                b, a = stk.pop(), stk.pop()
                stk.append(a * b)
            elif op == "NOR":
                b, a = stk.pop(), stk.pop()
                stk.append(~(a | b))
            elif op == "NAND":
                b, a = stk.pop(), stk.pop()
                stk.append(~(a & b))
            elif op == "DUP":
                stk.append(stk[-1])
            elif op == "DUP2":
                stk.extend([stk[-2], stk[-1]])
            elif op == "SWAP":
                stk[-1], stk[-2] = stk[-2], stk[-1]
            elif op == "ROT":
                a = stk.pop()
                b = stk.pop()
                c = stk.pop()
                stk.extend([b, a, c])
            elif op == "PUSH_0":
                stk.append(z3.BitVecVal(0, 64))
            elif op == "PUSH_1":
                stk.append(z3.BitVecVal(1, 64))
            elif op == "PUSH_2":
                stk.append(z3.BitVecVal(2, 64))
            elif op == "PUSH_M1":
                stk.append(z3.BitVecVal(-1, 64))
            elif op == "PUSH_ODD":
                stk.append(z3.BitVecVal(ODD_CONST, 64))
    except Exception:
        return None

    return stk[-1] if len(stk) == 1 else None

def verify_equivalence_z3(ops: List[str], target_op: str = "SUB", timeout_ms: int = 1500) -> Tuple[bool, bool, float]:
    """
    Formally proves mathematical equivalence in Z_{2^64} and checks for trivial collapse.
    Returns: (is_proven_sound, is_trivial_collapse, proof_time_sec)
    """
    x = z3.BitVec('x', 64)
    y = z3.BitVec('y', 64)
    res_expr = build_z3_expr(ops, x, y)
    if res_expr is None:
        return False, False, 0.0

    target = (x + y) if target_op == "ADD" else (x - y)

    # 1. Trivial algebraic collapse check (anti-peephole filter)
    # If basic term rewriting immediately collapses the expression to target,
    # then it was fake linear/constant noise, not genuine MBA.
    simp_res = z3.simplify(res_expr)
    simp_target = z3.simplify(target)
    is_trivial = z3.eq(simp_res, simp_target)

    # 2. Formal SMT BitVec proof
    s = z3.Solver()
    s.set("timeout", timeout_ms)
    s.add(res_expr != target)

    t0 = time.time()
    chk = s.check()
    t_solve = time.time() - t0

    is_sound = (chk == z3.unsat)
    return is_sound, is_trivial, t_solve

# ---------------------------------------------------------------------------
# 3. Adversarial Security Evaluator (Reward Function)
# ---------------------------------------------------------------------------

def compute_reward(ops: List[str], target_op: str = "SUB") -> Tuple[float, Dict[str, float]]:
    clean_ops = [op for op in ops if op != "HALT"]
    L = len(clean_ops)
    if L < 2:
        return 1e-4, {}

    # Fast Reject via 32 random test vectors
    target_fn = (lambda a, b: (a + b) & MASK64) if target_op == "ADD" else (lambda a, b: (a - b) & MASK64)
    rng = random.Random(42)
    for _ in range(32):
        rx = rng.getrandbits(64)
        ry = rng.getrandbits(64)
        if eval_concrete(clean_ops, rx, ry) != target_fn(rx, ry):
            return 1e-4, {}

    # Formal SMT proof + Anti-Peephole Collapse Check
    is_sound, is_trivial, t_smt = verify_equivalence_z3(clean_ops, target_op=target_op)
    if not is_sound:
        return 1e-4, {}

    # Heavy penalty for trivial peephole cancellations (e.g. (x+c)-c)
    if is_trivial:
        return 0.1, {"score": 0.1, "len": L, "trivial": 1.0}

    # Security metrics for genuine MBA / Opaque superoperators
    non_linear_count = sum(1 for op in clean_ops if op in ("NOR", "NAND", "MUL"))
    rot_swap_count = sum(1 for op in clean_ops if op in ("ROT", "SWAP", "DUP2"))
    unique_ops = len(set(clean_ops))

    # Pareto length score: sweet spot is 4..10 instructions
    len_score = 1.0 if (4 <= L <= 10) else (0.5 if L < 4 else max(0.1, 1.0 - (L - 10) * 0.1))

    total_score = (12.0 + non_linear_count * 3.0 + rot_swap_count * 1.5 + unique_ops * 1.5 + min(5.0, t_smt * 100.0)) * len_score
    reward = math.exp(min(12.0, total_score / 5.0))

    metrics = {
        "score": total_score,
        "len": L,
        "nl_ops": non_linear_count,
        "unique": unique_ops,
        "t_smt_ms": t_smt * 1000.0,
        "trivial": 0.0
    }
    return reward, metrics

# ---------------------------------------------------------------------------
# 4. Neural Policy & Vectorized Action Masking
# ---------------------------------------------------------------------------

class OpcodePolicyNet(nn.Module):
    """Autoregressive Transformer Policy Network."""
    def __init__(self, vocab_size: int = VOCAB_SIZE, d_model: int = 128, nhead: int = 4, num_layers: int = 2):
        super().__init__()
        self.tok_embed = nn.Embedding(vocab_size + 1, d_model)  # +1 for START_TOKEN
        self.pos_embed = nn.Embedding(MAX_TRAJECTORY_LEN + 2, d_model)
        layer = nn.TransformerEncoderLayer(d_model=d_model, nhead=nhead, dim_feedforward=256, dropout=0.1, batch_first=True)
        self.transformer = nn.TransformerEncoder(layer, num_layers=num_layers)
        self.head = nn.Linear(d_model, vocab_size)

    def forward(self, seq_tokens: torch.Tensor) -> torch.Tensor:
        B, T = seq_tokens.shape
        pos = torch.arange(T, device=seq_tokens.device).unsqueeze(0).expand(B, T)
        x = self.tok_embed(seq_tokens) + self.pos_embed(pos)
        mask = torch.triu(torch.full((T, T), float('-inf'), device=seq_tokens.device), diagonal=1)
        hidden = self.transformer(x, mask=mask)
        return self.head(hidden[:, -1, :])

def get_action_mask_batch(depths: torch.Tensor, step: int) -> torch.Tensor:
    """Vectorized action mask computation over a batch of stack depths."""
    B = depths.shape[0]
    masks = torch.zeros((B, VOCAB_SIZE), dtype=torch.bool, device=depths.device)
    for idx, op in enumerate(VOCAB):
        if op.is_terminal:
            masks[:, idx] = (depths == 1) & (step >= 2)
        else:
            masks[:, idx] = (depths >= op.min_depth) & ((depths + op.delta) <= MAX_STACK_DEPTH)
    return masks

# ---------------------------------------------------------------------------
# 5. Batched Trajectory Balance GFlowNet Agent
# ---------------------------------------------------------------------------

class ExperienceBuffer:
    def __init__(self, capacity: int = 256):
        self.capacity = capacity
        self.buffer: List[Tuple[List[str], float, Dict]] = []

    def add(self, ops: List[str], reward: float, metrics: Dict):
        for b_ops, _, _ in self.buffer:
            if b_ops == ops: return
        self.buffer.append((ops, reward, metrics))
        self.buffer.sort(key=lambda x: x[1], reverse=True)
        if len(self.buffer) > self.capacity: self.buffer.pop()

    def sample(self, k: int) -> List[Tuple[List[str], float, Dict]]:
        return random.sample(self.buffer, min(k, len(self.buffer))) if self.buffer else []

class TBGFlowNetAgent:
    def __init__(self, target_op: str = "SUB", lr: float = 3e-4, lr_z: float = 1e-2):
        self.target_op = target_op
        self.model = OpcodePolicyNet()
        self.log_Z = nn.Parameter(torch.tensor(3.0))
        self.optimizer = optim.Adam([
            {'params': self.model.parameters(), 'lr': lr},
            {'params': [self.log_Z], 'lr': lr_z}
        ])
        self.buffer = ExperienceBuffer()
        self._seed_demonstrations()

    def _seed_demonstrations(self):
        """Seeds canonical two's complement identity: x - y = x + ~(y | y) + 1."""
        seed1 = ["SWAP", "DUP", "NOR", "PUSH_1", "ADD", "ADD", "HALT"]
        r1, m1 = compute_reward(seed1, target_op=self.target_op)
        if r1 > 1.0:
            self.buffer.add(seed1, r1, m1)

    def sample_batch_rollout(self, batch_size: int = 12, epsilon: float = 0.15) -> Tuple[torch.Tensor, List[List[str]], torch.Tensor, List[Dict]]:
        """
        P2: Vectorized parallel rollout across batch_size trajectories.
        P0: Maintains full, unbroken autograd computation graph for log_pf.
        """
        device = next(self.model.parameters()).device
        seq_tensor = torch.full((batch_size, 1), fill_value=START_TOKEN, dtype=torch.long, device=device)
        
        depths = torch.full((batch_size,), 2, dtype=torch.long, device=device)
        active = torch.ones(batch_size, dtype=torch.bool, device=device)
        log_pf = torch.zeros(batch_size, device=device)
        
        actions_per_sample: List[List[int]] = [[] for _ in range(batch_size)]

        for step in range(MAX_TRAJECTORY_LEN):
            if not active.any():
                break

            # Forward pass over all active trajectories in batch
            logits = self.model(seq_tensor)
            masks = get_action_mask_batch(depths, step)
            
            # Action masking
            logits[~masks] = -1e9
            dist = Categorical(logits=logits)
            
            # Epsilon-exploration with valid mask respect
            if random.random() < epsilon:
                sampled_actions = []
                for b in range(batch_size):
                    valid_idx = torch.where(masks[b])[0]
                    if len(valid_idx) > 0 and active[b]:
                        sampled_actions.append(valid_idx[random.randint(0, len(valid_idx) - 1)])
                    else:
                        sampled_actions.append(torch.tensor(HALT_ID, device=device))
                action = torch.stack(sampled_actions)
            else:
                action = dist.sample()

            step_log_p = dist.log_prob(action)

            # Update state for active trajectories
            for b in range(batch_size):
                if active[b]:
                    act_id = action[b].item()
                    actions_per_sample[b].append(act_id)
                    # P0: Tensor addition maintains autograd graph
                    log_pf[b] = log_pf[b] + step_log_p[b]
                    
                    op_def = ID_TO_OP[act_id]
                    depths[b] += op_def.delta
                    if op_def.is_terminal:
                        active[b] = False

            # Append action to sequence tensor
            seq_tensor = torch.cat([seq_tensor, action.unsqueeze(1)], dim=1)

        # Compute rewards and metrics
        all_ops = [[ID_TO_OP[a].name for a in sample] for sample in actions_per_sample]
        rewards = []
        metrics_list = []
        for ops in all_ops:
            r, m = compute_reward(ops, target_op=self.target_op)
            rewards.append(r)
            metrics_list.append(m)
            if r > 10.0:
                self.buffer.add(ops, r, m)

        rewards_tensor = torch.tensor(rewards, dtype=torch.float32, device=device)
        return log_pf, all_ops, rewards_tensor, metrics_list

    def evaluate_replay_loss(self, ops: List[str], reward: float) -> torch.Tensor:
        """Differentiable forward re-evaluation of replay trajectories."""
        device = next(self.model.parameters()).device
        actions = [OP_TO_ID[o] for o in ops]
        seq = [START_TOKEN]
        log_pf = torch.tensor(0.0, device=device)
        depth = 2

        for step, act in enumerate(actions):
            state = torch.tensor([seq], dtype=torch.long, device=device)
            logits = self.model(state).squeeze(0)
            mask = get_action_mask_batch(torch.tensor([depth]), step).squeeze(0)
            logits[~mask] = -1e9
            dist = Categorical(logits=logits)
            log_pf = log_pf + dist.log_prob(torch.tensor(act, device=device))
            seq.append(act)
            depth += ID_TO_OP[act].delta

        # P1: log P_B == 0.0 for tree structure
        log_r = math.log(max(1e-5, reward))
        return (self.log_Z + log_pf - log_r) ** 2

    def train_step(self, batch_size: int = 12) -> Tuple[float, List[Tuple[List[str], float, Dict]]]:
        """Runs a Trajectory Balance (TB) update step with joint clipping."""
        # 1. Batched on-policy rollout
        log_pf, all_ops, rewards, metrics = self.sample_batch_rollout(batch_size=batch_size - 3)
        
        # P1: log P_B == 0.0 for deterministic autoregressive tree
        log_r = torch.log(torch.clamp(rewards, min=1e-5))
        on_policy_losses = (self.log_Z + log_pf - log_r) ** 2

        losses = [on_policy_losses[b] for b in range(len(all_ops))]
        trajectories = list(zip(all_ops, rewards.tolist(), metrics))

        # 2. Replay buffer samples to reinforce valid basins of attraction
        for ops, r, m in self.buffer.sample(3):
            losses.append(self.evaluate_replay_loss(ops, r))

        total_loss = torch.stack(losses).mean()
        self.optimizer.zero_grad()
        total_loss.backward()

        # P3: Joint gradient clipping across model weights AND log_Z
        torch.nn.utils.clip_grad_norm_([*self.model.parameters(), self.log_Z], 1.0)
        self.optimizer.step()

        return total_loss.item(), trajectories

# ---------------------------------------------------------------------------
# 6. OCaml EDSL Exporter (AGENTS.md Rule 2 Compliant)
# ---------------------------------------------------------------------------

def export_asgard_ocaml(name: str, ops: List[str], target_op: str) -> str:
    clean = [op for op in ops if op != "HALT"]
    ir_ops_str = "; ".join(
        f"PushImm {ODD_CONST}L" if o == "PUSH_ODD" else
        "PushImm 0L" if o == "PUSH_0" else
        "PushImm 1L" if o == "PUSH_1" else
        "PushImm 2L" if o == "PUSH_2" else
        "PushImm 0xFFFFFFFFFFFFFFFFL" if o == "PUSH_M1" else
        o.capitalize()
        for o in clean
    )
    return f"""(* Discovered by ASGARD Neural Opcode Synthesizer (GFlowNet+Z3) *)
(* Target: {target_op} (modulo 2^64) | Length: {len(clean)} ops | Peak stack depth <= 4 *)
let synth_{name.lower()} () : stack_op list =
  [
    {ir_ops_str}
  ]
"""

# ---------------------------------------------------------------------------
# 7. Main Execution / Demonstration Loop
# ---------------------------------------------------------------------------

def main():
    print("=" * 65)
    print("   ASGARD-5877: Neural VM Opcode & Superoperator Synthesizer")
    print("   [Batched GFlowNet + Z3 Oracle + Anti-Peephole Filter]")
    print("=" * 65)

    target_op = "SUB"
    agent = TBGFlowNetAgent(target_op=target_op, lr=1e-3, lr_z=1e-2)

    print(f"[*] Target Operation: {target_op} (x - y mod 2^64)")
    print(f"[*] Evaluation Stack Constraint: peak_depth <= {MAX_STACK_DEPTH}")
    print("[*] Starting GFlowNet Trajectory Balance training loop...\n")

    best_discovery = agent.buffer.buffer[0] if agent.buffer.buffer else None
    best_reward = best_discovery[1] if best_discovery else 0.0

    for epoch in range(1, 41):
        loss, batch_trajs = agent.train_step(batch_size=12)

        for ops, r, m in batch_trajs:
            if r > 10.0 and r > best_reward:
                best_reward = r
                best_discovery = (ops, r, m)
                print(f"[*] [Epoch {epoch:02d}] NEW PARETO DISCOVERY! Reward={r:.1f}")
                print(f"    Sequence ({m['len']} ops): {' -> '.join(ops)}")
                print(f"    Z3 Proof Time: {m['t_smt_ms']:.1f}ms | Non-linear ops: {m['nl_ops']}")
                print()

        if epoch % 10 == 0:
            print(f"[Epoch {epoch:02d}/40] TB Loss: {loss:.3f} | log(Z): {agent.log_Z.item():.2f} | Best Reward: {best_reward:.1f}")

    print("\n" + "=" * 65)
    print("   SYNTHESIS RESULTS & OCAML CODEGEN")
    print("=" * 65)
    if best_discovery:
        ops, r, m = best_discovery
        print(f"[+] Optimal Sound Opcode Found (Reward: {r:.2f}):")
        print("    " + " -> ".join(ops) + "\n")
        print(export_asgard_ocaml(f"mba_{target_op.lower()}_neural", ops, target_op))
    else:
        print("[-] Training concluded. Continue exploring with higher epoch count.")

if __name__ == "__main__":
    main()
