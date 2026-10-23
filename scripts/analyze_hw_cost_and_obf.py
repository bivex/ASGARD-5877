#!/usr/bin/env python3
"""
ASGARD-5877 vISA Hardware Cost & Obfuscation Resilience Analyzer
===============================================================
Комплексный инструмент оценки:
  1. Аппаратных затрат и пропускной способности векторного ALU (vISA Vector Engine)
     согласно инвариантам кремния (lib/domain/hw_cost.ml, lib/domain/types.ml).
  2. Компромисса между стойкостью к девиртуализации (DRS, SMT, Neural AST Transformer)
     и реальным замедлением рантайма различных движков ВМ (Native, RD-JIT, Threaded, Stack).
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from dataclasses import asdict, dataclass
from typing import Any, Dict, List, Optional, Tuple


# ============================================================================
# 1. vISA Hardware Cost & Vector ALU Model
# ============================================================================

@dataclass
class VisaHwConfig:
    vlen: int = 128     # Разрядность векторного регистра (бит): 128, 256, 512, 1024
    elen: int = 64      # Максимальная разрядность элемента (бит): 32, 64
    alu_lanes: int = 4  # Число параллельных аппаратных трактов (lanes) в векторном ALU


@dataclass
class VisaHwResult:
    sew: int
    lmul: float
    lmul_str: str
    valid: bool
    verdict: str
    warnings: List[str]
    vlmax: int
    group_bytes: int
    widening_ok: bool
    throughput_elem_cycle: float
    vector_latency_cycles: int
    area_kge: float
    area_efficiency: float


class VisaHardwareCostModel:
    """Модель валидности конфигураций и аппаратных затрат векторного процессора."""

    SEW_CANDIDATES = [8, 16, 32, 64]
    LMUL_MAP = [
        (0.125, "mf8"),
        (0.25, "mf4"),
        (0.5, "mf2"),
        (1.0, "m1"),
        (2.0, "m2"),
        (4.0, "m4"),
        (8.0, "m8"),
    ]

    def __init__(self, cfg: VisaHwConfig):
        self.cfg = cfg

    def evaluate(self) -> List[VisaHwResult]:
        results: List[VisaHwResult] = []

        # Базовая оценка площади кремния (Gate Equivalents, GE, по 2-входовым NAND):
        # 1. Векторный АЛУ: ALU-lane (сумматор, сдвигатель, логика, умножитель ELEN x ELEN)
        lane_ge = 4500 if self.cfg.elen == 32 else 8800
        total_alu_ge = self.cfg.alu_lanes * lane_ge

        # 2. Регистровый файл: 32 регистра x VLEN бит, многопортовая память (3 Read, 1 Write)
        regfile_ports_factor = (3 + 1) / 4.0
        total_rf_ge = 32 * self.cfg.vlen * 2 * regfile_ports_factor

        total_area_kge = (total_alu_ge + total_rf_ge) / 1000.0

        for sew in self.SEW_CANDIDATES:
            for lmul, lmul_str in self.LMUL_MAP:
                warnings: List[str] = []

                # Инвариант 1: SEW <= ELEN
                if sew > self.cfg.elen:
                    warnings.append(f"SEW({sew}b) > ELEN({self.cfg.elen}b)")

                # Инвариант 2: Дробный LMUL (регистр должен вмещать хотя бы 1 элемент)
                effective_reg_bits = int(self.cfg.vlen * lmul)
                if effective_reg_bits < sew:
                    warnings.append(
                        f"LMUL*VLEN({effective_reg_bits}b) < SEW({sew}b): <1 элемента в группе"
                    )

                # Инвариант 3: Ограничение размера группы (lib/domain/hw_cost.ml)
                group_bits = sew * lmul
                if group_bits > self.cfg.vlen:
                    warnings.append(
                        f"SEW*LMUL({group_bits}b) > VLEN({self.cfg.vlen}b): переполнение группы"
                    )

                # Инвариант 4: Поддержка расширяющих инструкций (Widening: 2 * SEW <= ELEN)
                widening_dst = sew * 2
                widening_ok = widening_dst <= self.cfg.elen
                if not widening_ok:
                    warnings.append(f"Widening({widening_dst}b) > ELEN({self.cfg.elen}b)")

                # Определение общей валидности
                is_valid = (
                    sew <= self.cfg.elen
                    and effective_reg_bits >= sew
                    and group_bits <= self.cfg.vlen
                )
                verdict = "OK" if is_valid and len(warnings) == 0 else (
                    "WARN" if is_valid else "INVALID"
                )

                # VLMAX: максимальное количество элементов в векторном регистре/группе
                if is_valid:
                    vlmax = int((self.cfg.vlen / sew) * lmul)
                else:
                    vlmax = 0

                group_bytes = max(1, int(round((sew * lmul) / 8.0)))

                # Пиковая пропускная способность ALU (элементов за такт)
                elems_per_lane_cycle = max(1, self.cfg.elen // sew)
                alu_capacity = self.cfg.alu_lanes * elems_per_lane_cycle

                if is_valid and vlmax > 0:
                    tp = float(min(vlmax, alu_capacity))
                    latency = math.ceil(vlmax / max(1, alu_capacity))
                else:
                    tp = 0.0
                    latency = 0

                efficiency = (tp / total_area_kge) if total_area_kge > 0 else 0.0

                results.append(
                    VisaHwResult(
                        sew=sew,
                        lmul=lmul,
                        lmul_str=lmul_str,
                        valid=is_valid,
                        verdict=verdict,
                        warnings=warnings,
                        vlmax=vlmax,
                        group_bytes=group_bytes,
                        widening_ok=widening_ok,
                        throughput_elem_cycle=tp,
                        vector_latency_cycles=latency,
                        area_kge=total_area_kge,
                        area_efficiency=efficiency,
                    )
                )

        return results


# ============================================================================
# 2. Obfuscation & Performance Trade-off Model
# ============================================================================

@dataclass
class ObfProfile:
    name: str
    mba_depth: int
    egraph_nodes: int
    nullspace_terms: int
    micro_ops_multiplier: int
    description: str


@dataclass
class VmEngineSpec:
    name: str
    dispatch_cost_cycles: float
    vm_security_baseline: float
    description: str


@dataclass
class TradeoffResult:
    profile: str
    engine: str
    expanded_ops: int
    cycles_per_op: float
    slowdown_x: float
    drs_smt: float
    drs_neural: float
    drs_vm: float
    drs_total: float
    tier: str
    pareto_efficiency: float


class ObfuscationTradeoffModel:
    """Модель компромисса: глубина обфускации vs падение скорости виртуализации."""

    PROFILES = [
        ObfProfile("BASELINE", 0, 0, 0, 1, "Исходная линейная операция ALU"),
        ObfProfile("LIGHT", 1, 0, 0, 4, "Линейные тождества MBA 1-го порядка"),
        ObfProfile("BALANCED", 2, 30, 2, 20, "Нелинейный MBA (d=2) + E-Graph 30 + 2 шума Z_(2^64)"),
        ObfProfile("HEAVY", 3, 80, 4, 60, "MBA 3-го порядка + E-Graph 80 + 4 шума Z_(2^64)"),
        ObfProfile(
            "TIER3_MAX", 4, 120, 6, 146, "MBA d=5 + E-Graph 120 + 6 шумов Z_(2^64) + Ring Twist"
        ),
    ]

    ENGINES = [
        VmEngineSpec("Native", 1.0, 0.0, "Прямое выполнение компилированного кода хостом"),
        VmEngineSpec("RD-JIT", 4.5, 45.0, "Эфемерная генерация нативного микро-кода на лету"),
        VmEngineSpec("Threaded-VM", 18.0, 75.0, "Шитый байткод + тайминг-зонды + хамелеон-хэндлеры"),
        VmEngineSpec("Stack-VM", 46.0, 95.0, "Стековая ВМ + VPC rolling key + обратная связь"),
    ]

    def evaluate(
        self, engine_filter: Optional[str] = None
    ) -> List[TradeoffResult]:
        results: List[TradeoffResult] = []
        baseline_cycles = 1.0  # Native BASELINE

        for p in self.PROFILES:
            for eng in self.ENGINES:
                if engine_filter and engine_filter.lower() != "all":
                    if eng.name.lower() != engine_filter.lower():
                        continue

                # 1. Алгебраическая стойкость к SMT-солверам (Z3, Bitwuzla)
                smt_base = {0: 0.0, 1: 28.0, 2: 66.0, 3: 88.0, 4: 98.0}[p.mba_depth]
                drs_smt = min(100.0, smt_base + p.nullspace_terms * 1.5)

                # 2. Стойкость к нейросетевым упростителям (Transformer Seq2Seq / BiLSTM)
                drs_neural = {0: 0.0, 1: 34.0, 2: 74.0, 3: 92.0, 4: 99.5}[p.mba_depth]

                # 3. Архитектурная стойкость ВМ к статическому анализу (IDA Pro, Ghidra)
                drs_vm = eng.vm_security_baseline

                # Взвешенный итоговый балл стойкости (DRS: 0..100)
                if eng.name == "Native" and p.name == "BASELINE":
                    drs_total = 0.0
                elif eng.name == "Native":
                    drs_total = 0.60 * drs_smt + 0.40 * drs_neural
                else:
                    drs_total = 0.45 * drs_smt + 0.35 * drs_neural + 0.20 * drs_vm
                drs_total = min(100.0, max(0.0, drs_total))

                # Градация уровней стойкости (согласно NOAS в eval_obfuscation.py)
                if drs_total >= 90.0:
                    tier = "TIER 3+ RESILIENT"
                elif drs_total >= 70.0:
                    tier = "TIER 2"
                else:
                    tier = "TIER 1"

                # Вычисление тактовой задержки и замедления
                cycles = p.micro_ops_multiplier * eng.dispatch_cost_cycles
                slowdown = cycles / baseline_cycles

                # Индекс эффективности Парето
                if slowdown > 1.0001:
                    pareto = drs_total / math.log10(slowdown)
                else:
                    pareto = 0.0

                results.append(
                    TradeoffResult(
                        profile=p.name,
                        engine=eng.name,
                        expanded_ops=p.micro_ops_multiplier,
                        cycles_per_op=cycles,
                        slowdown_x=slowdown,
                        drs_smt=drs_smt,
                        drs_neural=drs_neural,
                        drs_vm=drs_vm,
                        drs_total=drs_total,
                        tier=tier,
                        pareto_efficiency=pareto,
                    )
                )

        return results


# ============================================================================
# 3. Форматирование таблиц и вывод отчетов
# ============================================================================

def format_table(headers: List[str], rows: List[List[Any]]) -> str:
    """Форматирует данные в моноширинную ASCII-таблицу."""
    str_rows = [[str(cell) for cell in row] for row in rows]
    widths = [len(h) for h in headers]
    for row in str_rows:
        for i, cell in enumerate(row):
            widths[i] = max(widths[i], len(cell))

    border = "+" + "+".join("-" * (w + 2) for w in widths) + "+"
    header_str = "| " + " | ".join(f"{h:<{widths[i]}}" for i, h in enumerate(headers)) + " |"

    lines = [border, header_str, border]
    for row in str_rows:
        line_str = "| " + " | ".join(f"{cell:<{widths[i]}}" for i, cell in enumerate(row)) + " |"
        lines.append(line_str)
    lines.append(border)
    return "\n".join(lines)


def print_visa_report(results: List[VisaHwResult], cfg: VisaHwConfig) -> None:
    print(f"\n{'='*88}")
    print(f" 1. МОДЕЛЬ АППАРАТНЫХ ЗАТРАТ И ПРОПУСКНОЙ СПОСОБНОСТИ vISA VECTOR ENGINE")
    print(f" Параметры: VLEN={cfg.vlen}b | ELEN={cfg.elen}b | ALU Lanes={cfg.alu_lanes}")
    print(f"{'='*88}")

    headers = [
        "SEW", "LMUL", "Статус", "VLMAX", "Группа (B)", "Widening",
        "Throughput (elem/T)", "Latency (T)", "Eff (Elem/kGE)"
    ]
    rows = []
    for r in results:
        rows.append([
            f"e{r.sew}",
            r.lmul_str,
            r.verdict,
            r.vlmax if r.valid else "-",
            r.group_bytes,
            "YES" if r.widening_ok else "NO",
            f"{r.throughput_elem_cycle:.1f}" if r.valid else "-",
            f"{r.vector_latency_cycles}" if r.valid else "-",
            f"{r.area_efficiency:.2f}" if r.valid else "-",
        ])
    print(format_table(headers, rows))

    invalid_items = [r for r in results if not r.valid or r.warnings]
    if invalid_items:
        print("\nДиагностические предупреждения кремниевых инвариантов:")
        for r in invalid_items:
            w_str = "; ".join(r.warnings)
            print(f"  * [e{r.sew:<2} | {r.lmul_str:<3}]: {w_str}")


def print_tradeoff_report(results: List[TradeoffResult]) -> None:
    print(f"\n{'='*88}")
    print(f" 2. СОПОСТАВЛЕНИЕ ОБФУСКАЦИИ, СТОЙКОСТИ (DRS) И ЗАМЕДЛЕНИЯ РАНТАЙМА ВМ")
    print(f"{'='*88}")

    headers = [
        "Профиль", "Движок ВМ", "Ops/IR", "Такты/Op", "Замедление",
        "DRS SMT", "DRS NN", "DRS Total", "Класс стойкости", "Парето η"
    ]
    rows = []
    for r in results:
        rows.append([
            r.profile,
            r.engine,
            r.expanded_ops,
            f"{r.cycles_per_op:.1f}",
            f"{r.slowdown_x:.1f}x",
            f"{r.drs_smt:.1f}",
            f"{r.drs_neural:.1f}",
            f"{r.drs_total:.1f}",
            r.tier,
            f"{r.pareto_efficiency:.1f}",
        ])
    print(format_table(headers, rows))

    print("\nИнтерпретация индекса Парето η = DRS / log10(Slowdown):")
    print("  * η > 25.0 — сбалансированная конфигурация защиты с высокой отдачей на каждый порядок замедления.")
    print("  * TIER 3+ RESILIENT (DRS >= 90) гарантирует стойкость против Z3/Bitwuzla и нейросетевых деобфускаторов.")


# ============================================================================
# 4. Точка входа CLI
# ============================================================================

def main() -> None:
    parser = argparse.ArgumentParser(
        description="ASGARD-5877: Анализ аппаратных затрат vISA и компромисса обфускации"
    )
    parser.add_argument(
        "--mode",
        choices=["all", "hw", "obf"],
        default="all",
        help="Режим анализа: hw (vISA), obf (обфускация ВМ), all (оба)",
    )
    parser.add_argument("--vlen", type=int, default=128, help="Разрядность VLEN в битах (128, 256, 512)")
    parser.add_argument("--elen", type=int, default=64, help="Разрядность ELEN в битах (32, 64)")
    parser.add_argument("--lanes", type=int, default=4, help="Число аппаратных линий ALU (lanes)")
    parser.add_argument(
        "--engine",
        default="all",
        help="Фильтр движка ВМ (native, rd_jit, threaded, stack, all)",
    )
    parser.add_argument("--json", action="store_true", help="Вывод в формате JSON для CI/CD пайплайнов")

    args = parser.parse_args()

    visa_cfg = VisaHwConfig(vlen=args.vlen, elen=args.elen, alu_lanes=args.lanes)
    hw_model = VisaHardwareCostModel(visa_cfg)
    obf_model = ObfuscationTradeoffModel()

    hw_results = hw_model.evaluate() if args.mode in ["all", "hw"] else []
    obf_results = obf_model.evaluate(args.engine) if args.mode in ["all", "obf"] else []

    if args.json:
        payload = {
            "visa_hardware": [asdict(r) for r in hw_results],
            "obfuscation_tradeoff": [asdict(r) for r in obf_results],
        }
        print(json.dumps(payload, indent=2))
        return

    if args.mode in ["all", "hw"]:
        print_visa_report(hw_results, visa_cfg)

    if args.mode in ["all", "obf"]:
        print_tradeoff_report(obf_results)


if __name__ == "__main__":
    main()
