#!/usr/bin/env python3
"""
ASGARD-5877: Trajectory Balance GFlowNet Pass Rate & Budget Scheduler
=====================================================================
Optimizes protection pass intensity schedules under target binary size budgets
(target_size_budget_kb) to maximize Devirtualization Resistance Score (DRS)
while preventing the multiplicative 400x bytecode explosion across Stack-VM passes.

Key Mechanisms:
  1. Trajectory Balance GFlowNet: Learns a forward policy P_F(a_t | s_t) over
     discrete rate assignments across 20 sequential protection passes.
  2. Budget Barrier Reward: Enforces hard logarithmic/exponential penalty when
     cumulative program size breaches target_size_budget_kb.
  3. Action Masking: Dynamically suppresses high-expansion rates when remaining
     budget headroom cannot accommodate minimum future pass expansion.
  4. Schedule Export: Synthesizes Pareto-optimal rate schedules for standard
     presets (compact=100KB, balanced=256KB, heavy=2500KB).
"""

import sys
import os
import math
import time
import random
import json
import argparse
from typing import List, Tuple, Dict, NamedTuple

import torch
import torch.nn as nn
import torch.optim as optim
from torch.distributions.categorical import Categorical

# ---------------------------------------------------------------------------
# 1. Protection Pass Definitions & Empirical Expansion Priors
# ---------------------------------------------------------------------------

class PassProfile(NamedTuple):
    name: str
    kind: str          # "expansion", "structural", "essential"
    default_rate: float
    bloat_factor: float  # Multiplier on code size at rate=1.0 (e.g. 1.5 = +50% ops)
    drs_weight: float    # Contribution to security score
    perf_cost: float     # Relative runtime execution overhead

PIPELINE_PASSES: List[PassProfile] = [
    PassProfile("0-stall",            "essential",  1.0, 1.05, 0.04, 1.02),
    PassProfile("1a-algebraic-flags", "essential",  1.0, 1.08, 0.03, 1.01),
    PassProfile("2a-pre-superop",     "essential",  1.0, 0.85, 0.02, 0.90), # Size reduction
    PassProfile("2a-domain-enc",      "structural", 1.0, 1.15, 0.08, 1.05),
    PassProfile("2a-multiplicity",    "expansion",  0.5, 1.60, 0.09, 1.25),
    PassProfile("2-amplifier",        "expansion",  0.3, 1.80, 0.12, 1.35),
    PassProfile("2a-post-superop",    "essential",  1.0, 0.90, 0.02, 0.95), # Size reduction
    PassProfile("2b-mba",             "structural", 0.3, 1.70, 0.14, 1.30),
    PassProfile("2c-braid",           "structural", 0.5, 1.20, 0.06, 1.08),
    PassProfile("2d-homomorphic",     "structural", 0.5, 1.25, 0.07, 1.10),
    PassProfile("3-cff",              "structural", 0.3, 1.45, 0.15, 1.20),
    PassProfile("4-spaghetti",        "expansion",  0.3, 1.50, 0.08, 1.15),
    PassProfile("5-ghost",            "expansion",  0.3, 1.40, 0.05, 1.12),
    PassProfile("5b-avid",            "expansion",  0.3, 1.35, 0.04, 1.10),
    PassProfile("5d-transducer",      "structural", 0.25, 1.18, 0.05, 1.06),
    PassProfile("5e-polymba",         "structural", 0.3, 1.30, 0.08, 1.12),
    PassProfile("5h-finite-field",    "structural", 0.2, 1.22, 0.06, 1.08),
    PassProfile("5c-memweb",          "structural", 0.2, 1.15, 0.05, 1.05),
    PassProfile("5i-sink-barrier",    "structural", 0.25, 1.12, 0.04, 1.04),
    PassProfile("6-balance",          "essential",  1.0, 1.05, 0.02, 1.01),
]

DISCRETE_RATES: List[float] = [0.00, 0.10, 0.25, 0.50, 0.75, 1.00]

# ---------------------------------------------------------------------------
# 2. Simulated Environment for Protection Pipeline Rollout
# ---------------------------------------------------------------------------

class PipelineEnvironment:
    def __init__(self, target_budget_kb: float, initial_instrs: int = 40):
        self.target_budget_bytes = target_budget_kb * 1024.0
        self.initial_instrs = initial_instrs
        self.reset()

    def reset(self):
        self.step_idx = 0
        self.current_instrs = float(self.initial_instrs)
        self.current_blocks = max(1.0, float(self.initial_instrs // 10))
        # Estimate: average Stack-IR instruction with immediate is ~12 bytes
        self.current_size_bytes = self.current_instrs * 12.0
        self.accumulated_drs = 0.0
        self.accumulated_perf = 1.0
        self.history_actions: List[float] = []

    def get_state(self) -> torch.Tensor:
        size_ratio = self.current_size_bytes / self.target_budget_bytes
        headroom = max(0.0, 1.0 - size_ratio)
        future_passes = PIPELINE_PASSES[self.step_idx:]
        future_log_expansion = sum(math.log(max(1.0, p.bloat_factor)) for p in future_passes)

        state = torch.tensor([
            float(self.step_idx) / float(len(PIPELINE_PASSES)),
            math.log2(self.current_instrs + 1.0) / 16.0,
            math.log2(self.current_blocks + 1.0) / 8.0,
            min(2.0, size_ratio),
            headroom,
            min(5.0, future_log_expansion),
            self.accumulated_drs / 100.0,
        ], dtype=torch.float32)
        return state

    def get_action_mask(self) -> torch.Tensor:
        if self.step_idx >= len(PIPELINE_PASSES):
            return torch.ones(len(DISCRETE_RATES), dtype=torch.bool)

        current_pass = PIPELINE_PASSES[self.step_idx]
        mask = torch.ones(len(DISCRETE_RATES), dtype=torch.bool)

        # Essential passes cannot be disabled
        if current_pass.kind == "essential":
            mask[0] = False  # rate 0.0 disallowed
            return mask

        # If already near or over budget, suppress high expansion rates
        remaining_budget = self.target_budget_bytes - self.current_size_bytes
        for a_idx, rate in enumerate(DISCRETE_RATES):
            pass_bloat = 1.0 + rate * (current_pass.bloat_factor - 1.0)
            next_size = self.current_size_bytes * pass_bloat
            # Hard limit: do not allow any action that pushes size > 1.25x budget
            if next_size > self.target_budget_bytes * 1.25 and a_idx > 0:
                mask[a_idx] = False

        # Ensure at least rate 0.0 is always valid
        if not mask.any():
            mask[0] = True
        return mask

    def step(self, action_idx: int) -> bool:
        rate = DISCRETE_RATES[action_idx]
        current_pass = PIPELINE_PASSES[self.step_idx]
        self.history_actions.append(rate)

        # Dynamic bloat scaling
        pass_bloat = 1.0 + rate * (current_pass.bloat_factor - 1.0)
        self.current_instrs *= pass_bloat
        self.current_size_bytes *= pass_bloat
        if current_pass.name == "4-spaghetti":
            self.current_blocks += self.current_blocks * rate * 0.5

        # Security and performance accumulation
        self.accumulated_drs += rate * current_pass.drs_weight * 100.0
        self.accumulated_perf *= (1.0 + rate * (current_pass.perf_cost - 1.0))

        self.step_idx += 1
        done = self.step_idx >= len(PIPELINE_PASSES)
        return done

    def compute_reward(self) -> float:
        # 1. Security reward (DRS scale: 0..100)
        r_security = self.accumulated_drs

        # 2. Budget penalty (exponential barrier when exceeding budget)
        size_ratio = self.current_size_bytes / self.target_budget_bytes
        if size_ratio <= 1.0:
            # Reward dense packing near target without overflow
            psi_budget = 1.0 - 0.20 * (size_ratio - 0.85) ** 2
        else:
            # Steep exponential decay for overflowing target budget
            psi_budget = math.exp(-30.0 * (size_ratio - 1.0))

        # 3. Performance penalty
        omega_perf = 1.0 / (1.0 + 0.35 * max(0.0, self.accumulated_perf - 2.5))

        total_reward = max(1e-6, r_security * psi_budget * omega_perf)
        return total_reward

# ---------------------------------------------------------------------------
# 3. GFlowNet Policy Network Architecture
# ---------------------------------------------------------------------------

class GFlowNetPassPolicy(nn.Module):
    def __init__(self, state_dim: int = 7, hidden_dim: int = 128, n_actions: int = len(DISCRETE_RATES)):
        super().__init__()
        self.trunk = nn.Sequential(
            nn.Linear(state_dim, hidden_dim),
            nn.LayerNorm(hidden_dim),
            nn.LeakyReLU(0.2),
            nn.Linear(hidden_dim, hidden_dim),
            nn.LayerNorm(hidden_dim),
            nn.LeakyReLU(0.2),
        )
        self.forward_policy = nn.Linear(hidden_dim, n_actions)
        self.log_Z = nn.Parameter(torch.zeros(1))

    def forward(self, state: torch.Tensor, mask: torch.Tensor = None) -> Categorical:
        feat = self.trunk(state)
        logits = self.forward_policy(feat)
        if mask is not None:
            logits = logits.masked_fill(~mask, -1e9)
        return Categorical(logits=logits)

# ---------------------------------------------------------------------------
# 4. Trajectory Balance Training Loop
# ---------------------------------------------------------------------------

def train_gflownet(
    epochs: int = 400,
    batch_size: int = 32,
    lr: float = 1e-3,
    lr_z: float = 1e-2,
    device: str = "cpu"
) -> GFlowNetPassPolicy:
    model = GFlowNetPassPolicy().to(device)
    optimizer = optim.Adam([
        {"params": model.trunk.parameters(), "lr": lr},
        {"params": model.forward_policy.parameters(), "lr": lr},
        {"params": [model.log_Z], "lr": lr_z},
    ])

    print("=" * 70)
    print("🚀 ASGARD-5877: Training TB-GFlowNet Budget & Pass Rate Scheduler")
    print(f"   Passes: {len(PIPELINE_PASSES)} | Actions: {len(DISCRETE_RATES)} | Device: {device}")
    print("=" * 70)

    start_time = time.time()
    for epoch in range(1, epochs + 1):
        optimizer.zero_grad()
        loss_batch = []
        rewards_batch = []
        overflow_count = 0

        for _ in range(batch_size):
            # Sample random benchmark program sizes and budget targets
            init_instrs = random.randint(20, 250)
            target_kb = random.choice([64.0, 128.0, 256.0, 512.0, 1024.0])
            env = PipelineEnvironment(target_budget_kb=target_kb, initial_instrs=init_instrs)

            log_p_f_sum = torch.tensor(0.0, device=device)
            done = False

            while not done:
                state = env.get_state().to(device)
                mask = env.get_action_mask().to(device)
                dist = model(state, mask)

                action = dist.sample()
                log_prob = dist.log_prob(action)
                log_p_f_sum = log_p_f_sum + log_prob

                done = env.step(action.item())

            reward = env.compute_reward()
            rewards_batch.append(reward)
            if env.current_size_bytes > env.target_budget_bytes:
                overflow_count += 1

            # Trajectory Balance Loss: L_TB = (log Z + sum(log P_F) - log R)^2
            log_r = torch.tensor(math.log(reward), device=device)
            tb_loss = (model.log_Z + log_p_f_sum - log_r) ** 2
            loss_batch.append(tb_loss)

        total_loss = torch.stack(loss_batch).mean()
        total_loss.backward()

        # Joint gradient clipping
        nn.utils.clip_grad_norm_(model.parameters(), max_norm=5.0)
        optimizer.step()

        if epoch % 50 == 0 or epoch == 1:
            avg_rew = sum(rewards_batch) / len(rewards_batch)
            overflow_pct = (overflow_count / batch_size) * 100.0
            elapsed = time.time() - start_time
            print(f"[{epoch:03d}/{epochs:03d}] Loss: {total_loss.item():8.4f} | "
                  f"Avg Reward: {avg_rew:6.2f} | Log_Z: {model.log_Z.item():6.2f} | "
                  f"Overflow: {overflow_pct:4.1f}% | Time: {elapsed:5.1f}s")

    print("\n✅ GFlowNet Training Completed Successfully.")
    return model

# ---------------------------------------------------------------------------
# 5. Schedule Synthesis & Evaluation
# ---------------------------------------------------------------------------

def synthesize_preset_schedules(model: GFlowNetPassPolicy, device: str = "cpu") -> Dict:
    presets = {
        "compact_100kb":  {"budget_kb": 100.0,  "init_ops": 80},
        "balanced_256kb": {"budget_kb": 256.0,  "init_ops": 150},
        "heavy_2500kb":   {"budget_kb": 2500.0, "init_ops": 300},
    }

    schedules = {}
    model.eval()

    print("\n" + "=" * 70)
    print("📊 Synthesizing Pareto-Optimal Pass Schedules Across Budgets")
    print("=" * 70)

    with torch.no_grad():
        for preset_name, p_info in presets.items():
            env = PipelineEnvironment(target_budget_kb=p_info["budget_kb"], initial_instrs=p_info["init_ops"])
            done = False
            schedule_map = {}

            while not done:
                pass_name = PIPELINE_PASSES[env.step_idx].name
                state = env.get_state().to(device)
                mask = env.get_action_mask().to(device)

                dist = model(state, mask)
                # Greedy mode for synthesis
                action_idx = torch.argmax(dist.probs).item()
                rate = DISCRETE_RATES[action_idx]

                schedule_map[pass_name] = int(round(rate * 100))
                done = env.step(action_idx)

            final_kb = env.current_size_bytes / 1024.0
            schedules[preset_name] = {
                "budget_kb": p_info["budget_kb"],
                "final_kb": round(final_kb, 1),
                "drs_score": round(env.accumulated_drs, 1),
                "rates": schedule_map,
            }

            print(f"\n--- Preset: {preset_name} (Budget: {p_info['budget_kb']} KB) ---")
            print(f"  Final Size: {final_kb:.1f} KB (Usage: {(final_kb / p_info['budget_kb']) * 100.0:.1f}%)")
            print(f"  DRS Score : {env.accumulated_drs:.1f} / 100.0")
            print("  Selected Rates:")
            for p_name, r_pct in schedule_map.items():
                print(f"    {p_name:<24} : {r_pct:>3d}%")

    return schedules

# ---------------------------------------------------------------------------
# Main CLI Interface
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description="ASGARD-5877 GFlowNet Pass Rate & Budget Scheduler")
    parser.add_argument("--epochs", type=int, default=150, help="Number of GFlowNet training epochs")
    parser.add_argument("--batch-size", type=int, default=32, help="Rollout batch size per epoch")
    parser.add_argument("--export-json", type=str, default="scripts/budget_schedules.json", help="Path to save synthesized schedules")
    args = parser.parse_args()

    device = "cpu"
    if torch.backends.mps.is_available():
        device = "mps"

    model = train_gflownet(epochs=args.epochs, batch_size=args.batch_size, device=device)
    schedules = synthesize_preset_schedules(model, device=device)

    with open(args.export_json, "w") as f:
        json.dump(schedules, f, indent=2)
    print(f"\n💾 Saved synthesized preset schedules to: {args.export_json}")

if __name__ == "__main__":
    main()
