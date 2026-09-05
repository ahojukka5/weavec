#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Enforce the runtime implementation boundary ledger (#432).

`docs/runtime-boundary.md` says portable language behavior belongs in Weave and
that C is a narrow host boundary. The repository contradicted that quietly: the
canonical formatter, the semantic index, the project system, and surface text
emission are all C, and each new surface form added a little more because the
surrounding code was already C.

This guard makes the boundary observable instead of aspirational. It is purely
file-based and never builds or runs the compiler.

It enforces:

* every C file under runtime/ is registered in runtime/BOUNDARY-MANIFEST;
* every registered path exists;
* no file exceeds its recorded ceiling, so `port-pending` C cannot grow;
* every `host` entry carries a `why:` comment justifying it, as the policy
  requires of new C;
* the manifest itself stays sorted and free of duplicates.

Lowering a ceiling after porting code to Weave always passes. Raising one is a
visible line in the manifest diff that a reviewer must accept.
"""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RUNTIME = ROOT / "runtime"
MANIFEST = RUNTIME / "BOUNDARY-MANIFEST"
DOC = ROOT / "docs/runtime-boundary.md"

CATEGORIES = ("host", "port-pending")
SUFFIXES = (".c", ".inc")


def fail(problems: list[str]) -> None:
    for problem in problems:
        print(f"runtime-boundary: {problem}", file=sys.stderr)
    print(
        "runtime-boundary: see docs/runtime-boundary.md and issue #432",
        file=sys.stderr,
    )
    raise SystemExit(1)


def parse_manifest() -> tuple[dict[str, tuple[str, int]], list[str]]:
    """Return {path: (category, ceiling)} plus any structural problems."""
    problems: list[str] = []
    entries: dict[str, tuple[str, int]] = {}
    block: list[str] = []
    block_start = 0
    pending_why = False

    def close_block() -> None:
        """Each section lists its paths in order; check them independently."""
        if block and block != sorted(block):
            problems.append(
                f"{MANIFEST.name}:{block_start}: the section starting here "
                f"must list paths in sorted order to keep diffs readable"
            )
        block.clear()

    for number, raw in enumerate(
        MANIFEST.read_text(encoding="utf-8").splitlines(), start=1
    ):
        line = raw.strip()
        if not line:
            close_block()
            continue
        if line.startswith("#"):
            if line[1:].strip().startswith("why:"):
                pending_why = True
            else:
                close_block()
            continue

        fields = line.split()
        if len(fields) != 3:
            problems.append(
                f"{MANIFEST.name}:{number}: expected "
                f"'<category> <ceiling> <path>', found {line!r}"
            )
            pending_why = False
            continue

        category, ceiling_text, path = fields
        if category not in CATEGORIES:
            problems.append(
                f"{MANIFEST.name}:{number}: unknown category {category!r}; "
                f"use one of {', '.join(CATEGORIES)}"
            )
        if not ceiling_text.isdigit():
            problems.append(
                f"{MANIFEST.name}:{number}: ceiling must be a line count, "
                f"found {ceiling_text!r}"
            )
            pending_why = False
            continue
        if path in entries:
            problems.append(f"{MANIFEST.name}:{number}: duplicate entry {path}")

        # The policy requires new C to explain why Weave cannot express it.
        # `port-pending` is pre-existing debt tracked by #432 and needs no
        # per-file rationale; `host` claims compliance, so it must justify.
        if category == "host" and not pending_why:
            problems.append(
                f"{MANIFEST.name}:{number}: host entry {path} needs a "
                f"'# why: ...' comment stating what Weave cannot express"
            )

        entries[path] = (category, int(ceiling_text))
        if not block:
            block_start = number
        block.append(path)
        pending_why = False

    close_block()
    return entries, problems


def main() -> int:
    problems: list[str] = []

    if not MANIFEST.is_file():
        fail([f"missing ledger: {MANIFEST.relative_to(ROOT)}"])
    if not DOC.is_file():
        problems.append(f"missing policy document: {DOC.relative_to(ROOT)}")

    entries, problems_from_manifest = parse_manifest()
    problems.extend(problems_from_manifest)

    discovered = {
        str(path.relative_to(ROOT))
        for path in sorted(RUNTIME.rglob("*"))
        if path.is_file() and path.suffix in SUFFIXES
    }

    for path in sorted(discovered - set(entries)):
        problems.append(
            f"{path} is not registered in {MANIFEST.name}. New portable "
            f"behavior belongs in src/ as Weave; register a 'host' entry with "
            f"a 'why:' comment only for a real platform or ABI boundary"
        )

    for path in sorted(set(entries) - discovered):
        problems.append(f"{path} is registered but does not exist")

    total_host = 0
    total_pending = 0
    for path in sorted(discovered & set(entries)):
        category, ceiling = entries[path]
        actual = len((ROOT / path).read_text(encoding="utf-8").splitlines())
        if actual > ceiling:
            problems.append(
                f"{path} grew to {actual} lines, above its ceiling of "
                f"{ceiling}. Move the new behavior to Weave, or state why the "
                f"ceiling must rise"
            )
        if category == "host":
            total_host += actual
        else:
            total_pending += actual

    if problems:
        fail(problems)

    total = total_host + total_pending
    share = (100.0 * total_host / total) if total else 0.0
    print(
        f"runtime-boundary: {len(entries)} registered C files, "
        f"{total_host} host lines and {total_pending} awaiting the Weave port "
        f"({share:.0f}% of runtime C is a genuine host boundary)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
