#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Summarize weavec performance LLVM goldens for codegen quality.

Reads test/performance/expected-llvm/*.ll and prints metrics that highlight
missed SSA promotion, memory traffic, and other speed-related patterns.

Usage:
  python3 scripts/analyze-performance-llvm.py
  python3 scripts/analyze-performance-llvm.py --markdown docs/llvm-codegen-analysis-report.md
"""

from __future__ import annotations

import argparse
import re
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LLVM_DIR = ROOT / "test" / "performance" / "expected-llvm"


def analyze_ll(text: str) -> dict[str, int | bool | list[str]]:
    m: dict[str, int | bool | list[str]] = {}
    m["alloca"] = len(re.findall(r"\balloca\b", text))
    m["load"] = len(re.findall(r"\bload\b", text))
    m["store"] = len(re.findall(r"\bstore\b", text))
    m["phi"] = len(re.findall(r"\bphi\b", text))
    m["loop_phi"] = len(re.findall(r"\.phi\d*\s*=", text))
    m["sitofp"] = len(re.findall(r"\bsitofp\b", text))
    m["fadd"] = len(re.findall(r"\bfadd\b", text))
    m["add_i64"] = len(re.findall(r"\badd i64\b", text))
    m["add_zero"] = len(re.findall(r"add i32 %[^,]+, 0\b", text))
    m["add_zero"] += len(re.findall(r"add i64 %[^,]+, 0\b", text))

    body_loads = 0
    in_body = False
    for line in text.splitlines():
        if re.search(r"^while\.body", line.strip()):
            in_body = True
            continue
        if in_body and re.search(r"^(while\.|endif|else)", line.strip()):
            if "while.body" not in line:
                in_body = False
        if in_body and "load " in line and ".addr" in line:
            body_loads += 1
    m["loop_body_addr_loads"] = body_loads

  # Locals with .addr but no .phi in the same function.
    funcs = re.split(r"(?=define )", text)
    stack_only: list[str] = []
    for func in funcs:
        if "define " not in func:
            continue
        addrs = set(re.findall(r"%([a-zA-Z0-9_]+)\.addr\b", func))
        phis = set(re.findall(r"%([a-zA-Z0-9_]+)\.phi", func))
        for name in sorted(addrs - phis):
            if name in ("i", "j", "k", "n"):
                continue
            if re.search(rf"load [^,]+, ptr %{name}\.addr", func) and re.search(
                r"while\.body", func
            ):
                stack_only.append(name)
    m["stack_carried_candidates"] = stack_only
    m["has_stack_carried"] = bool(stack_only)
    return m


def score_opportunity(m: dict) -> int:
    """Higher = more obvious room for weavec speedups (not runtime of benchmark)."""
    s = 0
    s += m["loop_body_addr_loads"] * 3
    s += len(m["stack_carried_candidates"]) * 5
    s += m["add_zero"] * 2
    s += m["sitofp"] * 2
    if m["alloca"] > 8:
        s += m["alloca"] - 8
    return s


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--markdown",
        type=Path,
        help="Write a markdown report to this path",
    )
    parser.add_argument(
        "--top",
        type=int,
        default=20,
        help="How many fixtures to list in the hot-spot table",
    )
    args = parser.parse_args()

    rows: list[tuple[str, dict, int]] = []
    by_tag: dict[str, list[int]] = defaultdict(list)

    for path in sorted(LLVM_DIR.glob("*.ll")):
        text = path.read_text(encoding="utf-8")
        metrics = analyze_ll(text)
        opp = score_opportunity(metrics)
        rows.append((path.stem, metrics, opp))
        if metrics["has_stack_carried"]:
            by_tag["stack_carried"].append(opp)

    rows.sort(key=lambda r: r[2], reverse=True)

    lines: list[str] = []
    lines.append("# LLVM golden analysis (generated)")
    lines.append("")
    lines.append(
        "Metrics are static counts on checked-in `expected-llvm/` output. "
        "High opportunity scores usually mean weavec emits stack slots where "
        "LLVM would prefer loop phis after mem2reg."
    )
    lines.append("")
    lines.append(f"Fixtures scanned: {len(rows)}")
    lines.append(
        f"With stack-carried locals in loops (no phi): "
        f"{sum(1 for _, m, _ in rows if m['has_stack_carried'])}"
    )
    lines.append("")
    lines.append("## Top optimization opportunities")
    lines.append("")
    lines.append(
        "| Id | alloca | load | store | phi | loop-phi | "
        "body loads | add+0 | sitofp | stack-carried | score |"
    )
    lines.append(
        "|----|--------|------|-------|-----|----------|"
        "-----------|-------|--------|-----------------|-------|"
    )
    for stem, m, opp in rows[: args.top]:
        sc = ", ".join(m["stack_carried_candidates"][:4])
        if len(m["stack_carried_candidates"]) > 4:
            sc += ", …"
        lines.append(
            f"| {stem} | {m['alloca']} | {m['load']} | {m['store']} | "
            f"{m['phi']} | {m['loop_phi']} | {m['loop_body_addr_loads']} | "
            f"{m['add_zero']} | {m['sitofp']} | {sc or '-'} | {opp} |"
        )

    lines.append("")
    lines.append("## Evidence-first review order")
    lines.append("")
    lines.append(
        "1. Compare each raw golden with the selected LLVM-optimized IR."
    )
    lines.append(
        "2. Inspect final linked-binary disassembly before treating raw "
        "instruction counts as code-generation defects."
    )
    lines.append(
        "3. A/B test the current custom loop-phi machinery against a simpler "
        "uniform lowering under the same LLVM profile and CPU target."
    )
    lines.append(
        "4. Remove custom transformations when optimized IR, machine code, "
        "and measured performance are equivalent or better without them."
    )
    lines.append(
        "5. Add backend logic only for a general semantic property that LLVM "
        "cannot recover, never for one fixture-shaped pattern."
    )
    lines.append("")
    report = "\n".join(lines)
    print(report)

    if args.markdown:
        args.markdown.parent.mkdir(parents=True, exist_ok=True)
        header = (
            "<!-- Auto-generated by scripts/analyze-performance-llvm.py. "
            "Re-run after changing goldens. -->\n\n"
        )
        args.markdown.write_text(header + report, encoding="utf-8")
        print(f"wrote {args.markdown}", file=__import__("sys").stderr)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
