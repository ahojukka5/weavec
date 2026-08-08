#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Validate compiler source units before the published bootstrap combiner sees them.

weavec-bootstrap-cat v0.3.1 silently drops a source file when it cannot find the
closing parenthesis of that file's outer ``(program ...)`` form. The compiler
build must fail at the malformed source instead of discovering the omission
later as an unrelated undefined-symbol error.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path


def fail(path: str, line: int | None, message: str) -> bool:
    where = f"{path}:{line}" if line is not None else path
    print(f"weavec compiler source: {where}: {message}", file=sys.stderr)
    return False


def validate_source(path: str) -> bool:
    source_path = Path(path)
    try:
        text = source_path.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as exc:
        return fail(path, None, f"cannot read UTF-8 source: {exc}")

    stack: list[tuple[int, int]] = []
    actual_program: tuple[int, int] | None = None
    in_string = False
    string_line: int | None = None
    i = 0
    line = 1

    while i < len(text):
        char = text[i]

        if in_string:
            if char == "\\":
                if i + 1 >= len(text):
                    return fail(path, line, "unterminated string escape")
                if text[i + 1] == "\n":
                    line += 1
                i += 2
                continue
            if char == '"':
                in_string = False
                string_line = None
            elif char == "\n":
                line += 1
            i += 1
            continue

        if char == ";":
            newline = text.find("\n", i)
            if newline == -1:
                break
            line += 1
            i = newline + 1
            continue

        if char == '"':
            in_string = True
            string_line = line
            i += 1
            continue

        if char == "(":
            if not stack and text.startswith("(program", i):
                end = i + len("(program")
                if end == len(text) or not (
                    text[end].isalnum() or text[end] in "_-"
                ):
                    if actual_program is not None:
                        return fail(path, line, "multiple top-level (program ...) forms")
                    actual_program = (i, line)
            stack.append((i, line))
        elif char == ")":
            if not stack:
                return fail(path, line, "unmatched ')' outside a list")
            stack.pop()
        elif char == "\n":
            line += 1

        i += 1

    if in_string:
        return fail(path, string_line, "unterminated string literal")
    if stack:
        open_line = stack[-1][1]
        return fail(path, open_line, "unmatched '('; outer program cannot be extracted")
    if actual_program is None:
        return fail(path, None, "missing top-level (program ...) form")

    bootstrap_match = re.search(r"\(program\b", text)
    if bootstrap_match is None:
        return fail(path, None, "published bootstrap combiner cannot locate (program ...) form")
    if bootstrap_match.start() != actual_program[0]:
        misleading_line = text.count("\n", 0, bootstrap_match.start()) + 1
        return fail(
            path,
            misleading_line,
            "'(program' appears before the top-level program; "
            "weavec-bootstrap-cat v0.3.1 would extract the wrong region",
        )

    return True


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print(
            "usage: validate-compiler-source.py <source.weave> [source.weave ...]",
            file=sys.stderr,
        )
        return 2

    valid = True
    for path in argv[1:]:
        valid = validate_source(path) and valid
    return 0 if valid else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
