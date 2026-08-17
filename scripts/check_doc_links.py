#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Check that every relative link in repository Markdown resolves.

CONTRIBUTING requires local links to resolve. Nothing enforced it, so a deleted
page left five documents pointing at a 404 and the failure was only found by
someone following a link by hand.

Only relative targets are checked. External URLs are not fetched: this must stay
offline and deterministic, and a link checker that depends on the network fails
for reasons unrelated to the repository.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# Inline links and reference definitions: [text](target) and [label]: target
LINK = re.compile(r"\[[^\]]*\]\(([^)]+)\)")

SKIPPED_PREFIXES = ("http://", "https://", "mailto:", "#")

# Directories that are not authored documentation.
SKIPPED_DIRS = {".git", "build", "node_modules", ".github"}


def markdown_files() -> list[Path]:
    files: list[Path] = []
    for path in sorted(ROOT.rglob("*.md")):
        if any(part in SKIPPED_DIRS for part in path.relative_to(ROOT).parts):
            continue
        files.append(path)
    return files


def check(path: Path) -> list[str]:
    problems: list[str] = []
    text = path.read_text(encoding="utf-8")
    for line_number, line in enumerate(text.split("\n"), 1):
        for target in LINK.findall(line):
            target = target.strip()
            if not target or target.startswith(SKIPPED_PREFIXES):
                continue
            # Strip a fragment; a link to a heading resolves against the file.
            file_part = target.split("#", 1)[0]
            if not file_part:
                continue
            resolved = (path.parent / file_part).resolve()
            if resolved.exists():
                continue
            problems.append(
                f"{path.relative_to(ROOT).as_posix()}:{line_number}: "
                f"link target does not exist: {target}"
            )
    return problems


def main() -> int:
    problems: list[str] = []
    for path in markdown_files():
        problems.extend(check(path))

    if problems:
        for problem in problems:
            print(f"doc-links: error: {problem}", file=sys.stderr)
        return 1

    print(f"doc-links: {len(markdown_files())} documents, all relative links resolve")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
