#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Refuse documentation that names a superseded WIR core version as current.

`scripts/check_wir_core_version.py` audits emitters, fixtures, goldens, and an
opt-in list of documents. That opt-in list is the problem this check exists for:
seven live contract documents were never on it, so they kept claiming "WIR core
version 2" and "WIR v2" long after the self-hosted compiler moved to version 3.
An agent loading `docs/modules.md` and `docs/wir.md` together received two
different answers about the same compiler.

This check is therefore deny-by-default over the whole authored Markdown
corpus. A superseded version may be named only where the surrounding prose says
whose version it is -- a frozen lower stage -- or that the compiler refuses it.
Anything else is a claim about what `weavec` currently emits and accepts, and is
reported with the offending file and line.

The frozen bootstrap boundary is permanent, not stale: `weavec-bootstrap` emits
core version 2 and `weavec1` consumes it forever. Documentation has to keep
saying so, which is why attribution rather than the version number decides.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# Keep in step with scripts/check_wir_core_version.py, which owns the
# authoritative constants for the live and superseded versions.
CURRENT_CORE_VERSION = 3
SUPERSEDED_CORE_VERSIONS = (1, 2)

# Authored prose. Roots are scanned recursively for Markdown.
SCANNED_ROOTS = (Path("docs"), Path("spec"))
SCANNED_FILES = (Path("README.md"), Path("CONTRIBUTING.md"), Path("AGENTS.md"))

# Released history, not a live contract. A changelog entry describing the
# version-2 era must keep saying "version 2"; rewriting it would falsify the
# record.
EXCLUDED_FILES = frozenset({Path("CHANGELOG.md")})

# Files exempt from the attribution rule entirely.
#
# This list is deliberately short and each entry needs a reason that the
# per-sentence attribution below cannot express. It is not a place to park a
# document that merely failed the check.
#
# (Empty: every current frozen-boundary document -- docs/architecture.md,
# docs/wir.md, docs/command-reference.md, docs/quantum.md, README.md, and
# CONTRIBUTING.md among them -- attributes its version-2 mentions in the
# sentence that carries them, which is exactly the discipline this check is
# meant to enforce. Adding a file here removes it from coverage, so prefer
# fixing the attribution in the prose.)
FROZEN_BOUNDARY_DOCS: frozenset[Path] = frozenset()

# Spellings that name a core version. Every documented form the repository has
# actually used, so a claim cannot hide behind punctuation.
# `\s+` rather than a literal space: prose wrapped at 80 columns regularly
# splits "WIR core / version 2" across a line break, and a version claim that
# happens to land on a wrap point is still a version claim.
VERSION_SPELLINGS = (
    r"\(core-version\s+{v}\)",
    r"core-version-{v}\b",
    r"core\s+versions?\s+{v}\b",
    r"wir[ -]v{v}\b",
    r"weave-wir-core-v{v}\b",
)

SUPERSEDED_PATTERN = re.compile(
    "|".join(
        spelling.format(v=version)
        for version in SUPERSEDED_CORE_VERSIONS
        for spelling in VERSION_SPELLINGS
    ),
    re.IGNORECASE,
)

# Words that make a superseded-version mention legitimate: the sentence either
# attributes the version to a frozen stage or states that it is refused. Kept
# aligned with FROZEN_STAGE_MARKERS in scripts/check_wir_core_version.py.
FROZEN_STAGE_MARKERS = (
    "weavec0",
    "weavec1",
    "weavec-bootstrap",
    "frozen",
    "seed",
    "bootstrap",
    "reject",
    "refuse",
    "not accepted",
    "superseded",
    "historical",
)


def relative(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def scanned_files() -> list[Path]:
    files: set[Path] = set()
    for root in SCANNED_ROOTS:
        files.update((ROOT / root).rglob("*.md"))
    for name in SCANNED_FILES:
        candidate = ROOT / name
        if candidate.is_file():
            files.add(candidate)
    excluded = {ROOT / name for name in EXCLUDED_FILES}
    return sorted(path for path in files if path not in excluded)


# A sentence boundary: terminal punctuation followed by whitespace or the end
# of the document. Requiring the following whitespace keeps `v0.3.1`,
# `docs/wir.md`, and a decimal literal from splitting a sentence in half.
SENTENCE_END = re.compile(r"[.!?](?=\s|$)")


def sentence_context(text: str, position: int) -> str:
    """Return the lowercased sentence containing `position`.

    Scoped to the sentence rather than the paragraph on purpose. A paragraph is
    too wide: `docs/canonical-surface.md` said the frontend "emits ordinary WIR
    v2 forms" one sentence away from an unrelated sentence about a rejected
    argument type, and a paragraph-wide search accepted that stale claim on the
    strength of the word "rejected".

    A sentence is nevertheless wide enough for real attribution. Prose wrapped
    at 80 columns keeps the stage name and the version number in one sentence
    across the line break, and a fenced pipeline diagram carries no terminal
    punctuation at all, so the lead-in sentence introducing it stays in scope.
    """
    start = 0
    for match in SENTENCE_END.finditer(text, 0, position):
        start = match.end()
    end_match = SENTENCE_END.search(text, position)
    end = end_match.end() if end_match else len(text)
    return text[start:end].lower()


def check(path: Path) -> list[str]:
    problems: list[str] = []
    text = path.read_text(encoding="utf-8")
    for match in SUPERSEDED_PATTERN.finditer(text):
        context = sentence_context(text, match.start())
        if any(marker in context for marker in FROZEN_STAGE_MARKERS):
            continue
        line = text.count("\n", 0, match.start()) + 1
        quoted = " ".join(match.group(0).split())
        problems.append(
            f"{relative(path)}:{line}: names superseded WIR "
            f"{quoted!r} without attributing it to a frozen stage or "
            f"stating that it is refused; the self-hosted compiler is at core "
            f"version {CURRENT_CORE_VERSION}"
        )
    return problems


def audit() -> list[str]:
    problems: list[str] = []
    files = scanned_files()
    if not files:
        return ["no documentation was scanned; the scan roots are wrong"]

    for path in files:
        if path.relative_to(ROOT) in FROZEN_BOUNDARY_DOCS:
            continue
        problems.extend(check(path))

    # A stale exemption is as misleading as a stale version claim: it silently
    # removes a document from coverage.
    for name in sorted(FROZEN_BOUNDARY_DOCS):
        candidate = ROOT / name
        if not candidate.is_file():
            problems.append(
                f"{name.as_posix()}: allowlisted as a frozen-boundary document "
                f"but does not exist"
            )
        elif not SUPERSEDED_PATTERN.search(
            candidate.read_text(encoding="utf-8")
        ):
            problems.append(
                f"{name.as_posix()}: allowlisted as a frozen-boundary document "
                f"but names no superseded version; remove the exemption"
            )

    return problems


def main() -> int:
    problems = audit()
    if problems:
        for problem in problems:
            print(f"doc-wir-versions: error: {problem}", file=sys.stderr)
        return 1

    print(
        "doc-wir-versions: "
        f"{len(scanned_files())} documents name only core version "
        f"{CURRENT_CORE_VERSION} as current"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
