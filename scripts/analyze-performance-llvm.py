#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Summarize raw LLVM lowering pressure in the performance goldens.

Reads test/performance/expected-llvm/*.ll and reports the mutable stack traffic
that the selected LLVM optimization profile is expected to promote or simplify.

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

    # Mutable locals used in functions containing loops.
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


def score_promotion_pressure(m: dict) -> int:
    """Higher means more raw work is intentionally delegated to LLVM."""
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
        opp = score_promotion_pressure(metrics)
        rows.append((path.stem, metrics, opp))
        if metrics["has_stack_carried"]:
            by_tag["stack_carried"].append(opp)

    rows.sort(key=lambda r: r[2], reverse=True)

    lines: list[str] = []
    lines.append("# Raw LLVM lowering analysis (generated)")
    lines.append("")
    lines.append(
        "Metrics are static counts on checked-in raw `expected-llvm/` output. "
        "High promotion pressure is expected for mutable loops: `weavec` emits "
        "uniform stack semantics and the selected LLVM profile constructs SSA."
    )
    lines.append("")
    lines.append(f"Fixtures scanned: {len(rows)}")
    lines.append(
        f"With mutable locals used in loop-bearing functions: "
        f"{sum(1 for _, m, _ in rows if m['has_stack_carried'])}"
    )
    lines.append("")
    lines.append("## Highest raw promotion pressure")
    lines.append("")
    lines.append(
        "| Id | alloca | load | store | phi | body loads | add+0 | "
        "sitofp | mutable candidates | pressure |"
    )
    lines.append(
        "|----|--------|------|-------|-----|-----------|-------|"
        "--------|--------------------|----------|"
    )
    for stem, m, opp in rows[: args.top]:
        sc = ", ".join(m["stack_carried_candidates"][:4])
        if len(m["stack_carried_candidates"]) > 4:
            sc += ", …"
        lines.append(
            f"| {stem} | {m['alloca']} | {m['load']} | {m['store']} | "
            f"{m['phi']} | {m['loop_body_addr_loads']} | {m['add_zero']} | "
            f"{m['sitofp']} | {sc or '-'} | {opp} |"
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
        "3. Treat raw stack traffic as an LLVM workload, not by itself as a "
        "compiler defect."
    )
    lines.append(
        "4. Add backend transformations only for semantic information that "
        "LLVM cannot reconstruct from correct raw IR."
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
