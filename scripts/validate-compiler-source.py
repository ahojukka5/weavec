#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Validate compiler source units before the published bootstrap combiner sees them.

weavec-bootstrap-cat v0.3.1 silently drops a source file when it cannot find the
closing parenthesis of that file's outer ``(program ...)`` form. The compiler
build must fail at the malformed source instead of discovering the omission
later as an unrelated undefined-symbol error.

weavec1 v0.3.2 leaks a local's type across functions in one file. A local
name bound at two types in one compiler source is rejected here rather than
discovered later as an llvm-link type error.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path


IDENT = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
LET_BINDING = re.compile(
    r"\(\s*let\s+(" + IDENT.pattern + r")\s+(" + IDENT.pattern + r")\b"
)


def fail(path: str, line: int | None, message: str) -> bool:
    where = f"{path}:{line}" if line is not None else path
    print(f"weavec compiler source: {where}: {message}", file=sys.stderr)
    return False


def source_without_comments_or_strings(text: str) -> str:
    """Replace comments and strings with spaces, keeping newlines."""
    chars: list[str] = []
    i = 0
    n = len(text)
    in_string = False
    while i < n:
        char = text[i]
        if in_string:
            if char == "\\" and i + 1 < n:
                chars.append(" ")
                if text[i + 1] == "\n":
                    chars.append("\n")
                else:
                    chars.append(" ")
                i += 2
                continue
            if char == '"':
                in_string = False
            chars.append("\n" if char == "\n" else " ")
            i += 1
            continue
        if char == ";":
            newline = text.find("\n", i)
            if newline == -1:
                chars.extend(" " * (n - i))
                break
            chars.extend(" " * (newline - i))
            chars.append("\n")
            i = newline + 1
            continue
        if char == '"':
            in_string = True
            chars.append(" ")
            i += 1
            continue
        chars.append(char)
        i += 1
    return "".join(chars)


def check_local_type_collisions(path: str, text: str) -> bool:
    """Reject a local name bound at two types in one file.

    weavec1 v0.3.2 leaks local-name type facts across functions. A later
    function that reuses the name at a different type miscompiles.
    """
    body = source_without_comments_or_strings(text)
    types: dict[str, dict[str, int]] = {}
    for match in LET_BINDING.finditer(body):
        name, ty = match.group(1), match.group(2)
        line = body.count("\n", 0, match.start()) + 1
        types.setdefault(name, {})[ty] = line
    ok = True
    for name, by_type in sorted(types.items()):
        if len(by_type) < 2:
            continue
        detail = ", ".join(
            f"{ty} (line {by_type[ty]})" for ty in sorted(by_type)
        )
        ok = (
            fail(
                path,
                None,
                f"local {name!r} is bound as {detail}; "
                "weavec1 v0.3.2 leaks local types across functions",
            )
            and ok
        )
    return ok


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

    return check_local_type_collisions(path, text)


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
