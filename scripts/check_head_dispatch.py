#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Guard the surface head dispatch order in emit_node (#429).

`emit_node` tests `surface_is_call_node` before several named heads. A head
dispatched after that test is shaped like an ordinary call, so direct-call
resolution claims it first and the head's own handler becomes unreachable. The
failure is silent: the form is reported as an unresolved function.

That is exactly how `(qmeasure QUBIT NAME)` broke. `qgate` was listed in
`surface_ident_is_reserved_syntax` and survived; `qmeasure` was not, so it was
rejected as `unresolved function qmeasure`, which made `test/quantum` and
`test/trace` red and blocked `./selfhost.sh` at its stage-2 compilation-trace
step.

The invariant: every head that `emit_node` dispatches after the call check must
also be reserved in `surface_ident_is_reserved_syntax`. This check is
file-based and never builds the compiler.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EMIT = ROOT / "src/frontend/emit.weave"
ELABORATE = ROOT / "src/frontend/elaborate.weave"

HEAD_TEXT = re.compile(r'const_string_ptr "([A-Za-z_][A-Za-z0-9_-]*)"')

# WIR-shaped heads that emit_node names in its generic passthrough rather than
# dispatching to a handler. They are deliberately not reserved: `add_i32`,
# `ptr_add`, and friends stay ordinary WIR spellings, and these two are only
# inspected to reject pointer equality on enum values. Adding to this list
# means asserting the head has no handler that direct-call resolution could
# shadow.
PASSTHROUGH_HEADS = {
    "eq_ptr",
    "ne_ptr",
}


def fail(problems: list[str]) -> None:
    for problem in problems:
        print(f"head-dispatch: {problem}", file=sys.stderr)
    print(
        "head-dispatch: a head dispatched after the call check must be "
        "reserved, or direct-call resolution claims it first; see issue #429",
        file=sys.stderr,
    )
    raise SystemExit(1)


def function_bounds(lines: list[str], name: str) -> tuple[int, int]:
    """Return the [start, end) line range of a top-level function."""
    start = None
    for index, line in enumerate(lines):
        if line.strip().startswith(f"({name}") or line.strip().startswith(
            f"(fn {name}"
        ):
            start = index
            break
    if start is None:
        raise SystemExit(f"head-dispatch: cannot find {name}")
    indent = len(lines[start]) - len(lines[start].lstrip())
    for index in range(start + 1, len(lines)):
        stripped = lines[index]
        if stripped.strip().startswith("(fn ") and (
            len(stripped) - len(stripped.lstrip())
        ) <= indent:
            return start, index
    return start, len(lines)


def heads_near(lines: list[str], index: int, marker: str) -> list[str]:
    """Heads named on the line holding `marker` or the two lines after it."""
    if marker not in lines[index]:
        return []
    found: list[str] = []
    for offset in range(0, 3):
        if index + offset >= len(lines):
            break
        found.extend(HEAD_TEXT.findall(lines[index + offset]))
    return found


def main() -> int:
    problems: list[str] = []

    emit_lines = EMIT.read_text(encoding="utf-8").splitlines()
    start, end = function_bounds(emit_lines, "fn emit_node")

    call_check = None
    for index in range(start, end):
        if "surface_is_call_node" in emit_lines[index]:
            call_check = index
            break
    if call_check is None:
        fail(
            [
                f"{EMIT.name}: emit_node no longer tests surface_is_call_node. "
                f"If the dispatch order changed, this guard must be updated "
                f"deliberately rather than deleted"
            ]
        )

    dispatched: dict[str, int] = {}
    for index in range(call_check, end):
        for head in heads_near(emit_lines, index, "head_equals"):
            dispatched.setdefault(head, index + 1)

    elaborate_lines = ELABORATE.read_text(encoding="utf-8").splitlines()
    reserved_start, reserved_end = function_bounds(
        elaborate_lines, "fn surface_ident_is_reserved_syntax"
    )
    reserved: set[str] = set()
    for index in range(reserved_start, reserved_end):
        for head in heads_near(elaborate_lines, index, "ident_equals"):
            reserved.add(head)
    if not reserved:
        problems.append(
            f"{ELABORATE.name}: surface_ident_is_reserved_syntax named no "
            f"heads; the guard cannot verify anything"
        )

    for head, line in sorted(dispatched.items()):
        if head in PASSTHROUGH_HEADS or head in reserved:
            continue
        problems.append(
            f"{EMIT.name}:{line}: emit_node dispatches '{head}' after the "
            f"call check, but surface_ident_is_reserved_syntax does not "
            f"reserve it. Direct-call resolution will claim the form first "
            f"and report it as an unresolved function"
        )

    stale = sorted(PASSTHROUGH_HEADS - set(dispatched))
    for head in stale:
        problems.append(
            f"'{head}' is listed as a passthrough head but emit_node no "
            f"longer names it after the call check; drop it from the list"
        )

    if problems:
        fail(problems)

    guarded = len(dispatched) - len(PASSTHROUGH_HEADS & set(dispatched))
    print(
        f"head-dispatch: {guarded} dispatched heads after the call check are "
        f"reserved, {len(PASSTHROUGH_HEADS & set(dispatched))} passthrough"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
