#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Track which suites execute a program and which only inspect text (#440).

Five of the seven defects fixed on 2026-09-04 and 2026-09-05 were covered by a
suite that was green the whole time, because the suite asserted substrings of
emitted text and never ran the program. `test/loop-control` matched every
substring it looked for while `for`, `break`, and `continue` produced WIR the
backend rejected outright.

This guard does not decide whether a suite is adequate; that needs reading it.
It keeps the question visible and makes the answer accumulate:

* every suite directory with a `test.sh` is registered in
  `test/EXECUTION-MANIFEST`, and every registered suite exists;
* the number of `unreviewed` suites may fall but never rise, so the backlog
  drains and no new suite joins it;
* a suite classified `executes` must still look like it runs something, which
  catches an execution case being deleted from one.

It is file-based and never builds or runs the compiler.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TESTS = ROOT / "test"
MANIFEST = TESTS / "EXECUTION-MANIFEST"

CLASSES = ("executes", "contract", "unreviewed")

# The mechanical signal for `executes`: a produced artifact appears in command
# position, rather than only as an argument to grep or python.
RUNS_ARTIFACT = re.compile(
    r'^\s*(?:"?\$\{?(?:TMP|WORK|OUT|BUILD)\b[^"\s]*"?)\s*(?:>|2>|\||;|&&|\|\||$)',
    re.M,
)

# Lowered as suites are reviewed. Never raise it: classify instead.
UNREVIEWED_CEILING = 50


def fail(problems: list[str]) -> None:
    for problem in problems:
        print(f"suite-execution: {problem}", file=sys.stderr)
    print(
        "suite-execution: see CONTRIBUTING.md and issue #440",
        file=sys.stderr,
    )
    raise SystemExit(1)


def main() -> int:
    problems: list[str] = []
    if not MANIFEST.is_file():
        fail([f"missing ledger: {MANIFEST.relative_to(ROOT)}"])

    registered: dict[str, str] = {}
    for number, raw in enumerate(
        MANIFEST.read_text(encoding="utf-8").splitlines(), start=1
    ):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        fields = line.split()
        if len(fields) != 2:
            problems.append(
                f"{MANIFEST.name}:{number}: expected '<class> <suite>', "
                f"found {line!r}"
            )
            continue
        cls, suite = fields
        if cls not in CLASSES:
            problems.append(
                f"{MANIFEST.name}:{number}: unknown class {cls!r}; use one of "
                f"{', '.join(CLASSES)}"
            )
        if suite in registered:
            problems.append(f"{MANIFEST.name}:{number}: duplicate {suite}")
        registered[suite] = cls

    discovered = {
        path.parent.name
        for path in sorted(TESTS.glob("*/test.sh"))
        if path.is_file()
    }

    for suite in sorted(discovered - set(registered)):
        problems.append(
            f"test/{suite} is not registered in {MANIFEST.name}. Classify it "
            f"as 'executes' when it builds and runs a program, or 'contract' "
            f"when emitted text, a diagnostic, or a document is genuinely its "
            f"subject"
        )
    for suite in sorted(set(registered) - discovered):
        problems.append(f"{suite} is registered but has no test/{suite}/test.sh")

    unreviewed = sorted(
        suite for suite, cls in registered.items() if cls == "unreviewed"
    )
    if len(unreviewed) > UNREVIEWED_CEILING:
        problems.append(
            f"{len(unreviewed)} unreviewed suites, above the ceiling of "
            f"{UNREVIEWED_CEILING}. A new suite must be classified, not left "
            f"unreviewed"
        )

    for suite in sorted(discovered & set(registered)):
        if registered[suite] != "executes":
            continue
        body = (TESTS / suite / "test.sh").read_text(
            encoding="utf-8", errors="replace"
        )
        if not RUNS_ARTIFACT.search(body):
            problems.append(
                f"test/{suite} is classified 'executes' but no longer runs a "
                f"produced artifact. Restore the execution case, or "
                f"reclassify it deliberately"
            )

    if problems:
        fail(problems)

    executes = sum(1 for cls in registered.values() if cls == "executes")
    contract = sum(1 for cls in registered.values() if cls == "contract")
    print(
        f"suite-execution: {len(registered)} suites, {executes} execute a "
        f"program, {contract} assert a contract, {len(unreviewed)} unreviewed "
        f"(ceiling {UNREVIEWED_CEILING})"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
