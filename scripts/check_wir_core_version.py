#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Audit the self-hosted compiler and repository corpus for the current WIR core
version.

Exactly one core version is live at a time: the compiler emits it, accepts it,
and rejects every other. This audit is driven by `CURRENT_CORE_VERSION` and
`SUPERSEDED_CORE_VERSIONS` below, so a coordinated version transition edits those
two constants here rather than the version literals scattered through the checks.

Superseding a version *adds* a rejection case rather than replacing one: every
version the compiler once accepted must still be refused by name afterwards, so
a stale toolchain fails loudly instead of producing wrong code.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# The one version the compiler emits and accepts.
CURRENT_CORE_VERSION = 3

# Every version the compiler once accepted and must now reject, mapped to the
# fixture that proves it. Superseding a version means adding an entry here with
# the next free fixture number -- a deliberate act, not a generated name.
SUPERSEDED_CORE_VERSION_FIXTURES = {
    1: "test/correctness/wir/67_core_version_1_rejected.wir",
    2: "test/correctness/wir/78_core_version_2_rejected.wir",
}

SUPERSEDED_CORE_VERSIONS = tuple(sorted(SUPERSEDED_CORE_VERSION_FIXTURES))

DECLARED = f"(core-version {CURRENT_CORE_VERSION})"
LLVM_HEADER = f"; core-version: {CURRENT_CORE_VERSION}"

_REJECTED_MODULE = """(core-module
  (core-version {version})
  (decls
    (fn main
      (params)
      (returns i32)
      (do (return (const_i32 42))))))
"""

INVALID_VERSION_FIXTURES = {
    ROOT / path: _REJECTED_MODULE.format(version=version)
    for version, path in sorted(SUPERSEDED_CORE_VERSION_FIXTURES.items())
}

INVALID_VERSION_FIXTURES |= {
    ROOT / "test/correctness/wir/68_core_version_missing.wir": """(core-module
  (decls
    (fn main
      (params)
      (returns i32)
      (do (return (const_i32 42))))))
""",
    ROOT / "test/correctness/wir/69_core_version_duplicate.wir": f"""(core-module
  {DECLARED}
  {DECLARED}
  (decls
    (fn main
      (params)
      (returns i32)
      (do (return (const_i32 42))))))
""",
    ROOT / "test/correctness/wir/70_wrong_root.wir": f"""(program
  {DECLARED}
  (decls
    (fn main
      (params)
      (returns i32)
      (do (return (const_i32 42))))))
""",
    ROOT / "test/correctness/wir/71_core_version_missing_value.wir": """(core-module
  (core-version)
  (decls
    (fn main
      (params)
      (returns i32)
      (do (return (const_i32 42))))))
""",
    ROOT / "test/correctness/wir/72_core_version_string_rejected.wir": f"""(core-module
  (core-version "{CURRENT_CORE_VERSION}")
  (decls
    (fn main
      (params)
      (returns i32)
      (do (return (const_i32 42))))))
""",
}

AUDIT_ROOTS = (
    ROOT / "test/correctness",
    ROOT / "test/performance",
    ROOT / "test/quantum",
    ROOT / "test/selfhost",
)

CURRENT_DOCS = (
    ROOT / "README.md",
    ROOT / "CONTRIBUTING.md",
    ROOT / "docs/index.md",
    ROOT / "docs/architecture.md",
    ROOT / "docs/command-reference.md",
    ROOT / "docs/language-reference.md",
    ROOT / "docs/quantum.md",
    ROOT / "docs/source-style.md",
    # The contract document itself. Omitting it let the whole file describe a
    # superseded version while docs/index.md linked it under the current one.
    ROOT / "docs/wir.md",
)

# Words that make a superseded-version mention legitimate: either it is
# attributed to a frozen stage, or it is stated to be refused. Anything else is
# a claim about what this compiler currently does.
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
)

# Terms that assert a superseded version is what the compiler currently emits.
#
# The spaced prose form ("core version 2") is deliberately NOT banned. The frozen
# lower stages really are version-2 artifacts and always will be, so current
# documentation has to keep naming them accurately -- `weavec1` is a WIR core
# version 2 to LLVM backend, and no transition changes that. Only the envelope
# literal and the hyphenated module descriptor are claims about current output.
STALE_DOC_TERMS = tuple(
    term
    for version in SUPERSEDED_CORE_VERSIONS
    for term in (
        f"(core-version {version})",
        f"core-version-{version}",
    )
) + ("version split",)

SENTINEL_REGRESSION = ROOT / "test/correctness/surface/74_call_ptr_missing_callee.weave"


def relative(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def duplicated_source_manifest(path: Path, text: str) -> list[str]:
    """Report documentation that reproduces the compiler source manifest.

    `compiler/sources.list` is the single authority for which files are compiler
    inputs and in what order. A handwritten second copy in prose drifts: the
    architecture document once listed 28 files while the manifest linked 75, and
    included one the manifest explicitly excludes.

    Inline mentions in backticks are fine and useful. What is refused is a
    fenced block that is nothing but a list of source paths, which is the shape
    that goes stale silently.
    """
    problems: list[str] = []
    for block in re.findall(r"```[a-z]*\n(.*?)```", text, re.S):
        lines = [line.strip() for line in block.strip().split("\n") if line.strip()]
        if len(lines) < 2:
            continue
        if all(re.fullmatch(r"!?src/[A-Za-z0-9_/.-]+\.weave", line) for line in lines):
            problems.append(
                f"{relative(path)} reproduces the compiler source manifest "
                f"({len(lines)} paths beginning {lines[0]!r}); "
                f"compiler/sources.list is the single authority"
            )
    return problems


def unattributed_superseded_mentions(path: Path, text: str) -> list[str]:
    """Report prose that names a superseded version without saying whose it is.

    The spaced form cannot simply be banned: `weavec1` really is a WIR core
    version 2 backend, and a superseded version must still be documented as
    rejected. What distinguishes those from a stale claim is whether the
    paragraph says whose version it is, or that it is refused.

    Checked over a paragraph and the one before it, rather than per line: the
    attribution and the version routinely land on different lines of a wrapped
    sentence, and a lead-in sentence often precedes the list or diagram that
    carries the version.
    """
    problems: list[str] = []
    blocks = text.split("\n\n")
    for index, block in enumerate(blocks):
        lowered = block.lower()
        mentions = [
            phrase
            for version in SUPERSEDED_CORE_VERSIONS
            for phrase in (f"core version {version}", f"wir v{version}")
            if phrase in lowered
        ]
        if not mentions:
            continue
        # A lead-in sentence attributing the version routinely sits in the
        # paragraph before a list or a fenced diagram, so look at both.
        context = (blocks[index - 1].lower() if index else "") + lowered
        if any(marker in context for marker in FROZEN_STAGE_MARKERS):
            continue
        first = block.strip().splitlines()[0][:60]
        problems.append(
            f"{relative(path)} paragraph {index + 1} mentions {mentions[0]!r} "
            f"without naming the frozen stage it belongs to: {first!r}"
        )
    return problems


def audit() -> list[str]:
    errors: list[str] = []

    for emitter in ("src/frontend/lower.weave", "src/frontend/lower_program_emit.weave"):
        emitter_text = (ROOT / emitter).read_text(encoding="utf-8")
        if f'(const_string_ptr "  {DECLARED}")' not in emitter_text:
            errors.append(
                f"{emitter} does not emit core version {CURRENT_CORE_VERSION}"
            )
        for version in SUPERSEDED_CORE_VERSIONS:
            if f"core-version {version}" in emitter_text:
                errors.append(f"{emitter} still references core version {version}")

    module_text = (ROOT / "src/llvm/module.weave").read_text(encoding="utf-8")
    for required in (
        "(fn validate_core_module",
        f"expected exactly one {DECLARED}",
        "expected WIR core-module root",
        "missing version value",
        "(call_i32 node_int)",
        LLVM_HEADER,
    ):
        if required not in module_text:
            errors.append(f"src/llvm/module.weave missing {required!r}")
    for version in SUPERSEDED_CORE_VERSIONS:
        if f"core-version {version}" in module_text:
            errors.append(
                f"src/llvm/module.weave still references core version {version}"
            )

    extern_text = (ROOT / "src/core/extern.weave").read_text(encoding="utf-8")
    if "(extern unlink (params (path ptr)) (returns i32))" not in extern_text:
        errors.append("src/core/extern.weave does not declare unlink")

    util_text = (ROOT / "src/core/util.weave").read_text(encoding="utf-8")
    for required in (
        "Missing optional children use node -1",
        "(condition (eq_i64 (param_get node) (const_i64 -1)))",
        "(then (do (return (const_i32 0))))",
    ):
        if required not in util_text:
            errors.append(f"src/core/util.weave missing sentinel guard {required!r}")

    main_text = (ROOT / "src/main.weave").read_text(encoding="utf-8")
    if "(call_i32 validate_core_module" not in main_text:
        errors.append(
            "src/main.weave does not validate the WIR envelope before output creation"
        )
    if "(call_i32 unlink (param_get output_path))" not in main_text:
        errors.append("src/main.weave does not remove failed backend output")

    for root in AUDIT_ROOTS:
        for path in sorted(root.rglob("*")):
            if not path.is_file() or path in INVALID_VERSION_FIXTURES:
                continue
            text = path.read_text(encoding="utf-8")
            if path.suffix == ".wir":
                if text.count(DECLARED) != 1:
                    errors.append(
                        f"{relative(path)} must contain exactly one {DECLARED}"
                    )
                for version in SUPERSEDED_CORE_VERSIONS:
                    if f"(core-version {version})" in text:
                        errors.append(
                            f"{relative(path)} still declares core version {version}"
                        )
            elif path.suffix == ".ll":
                for version in SUPERSEDED_CORE_VERSIONS:
                    if f"; core-version: {version}" in text:
                        errors.append(
                            f"{relative(path)} still records core version {version}"
                        )
                if "; generated by weavec" in text and LLVM_HEADER not in text:
                    errors.append(
                        f"{relative(path)} lacks the core-version-{CURRENT_CORE_VERSION}"
                        " header"
                    )

    for path, expected in INVALID_VERSION_FIXTURES.items():
        if not path.exists():
            errors.append(f"missing negative fixture {relative(path)}")
        elif path.read_text(encoding="utf-8") != expected:
            errors.append(f"negative fixture changed unexpectedly: {relative(path)}")

    if not SENTINEL_REGRESSION.exists():
        errors.append(f"missing sentinel regression {relative(SENTINEL_REGRESSION)}")
    else:
        sentinel_text = SENTINEL_REGRESSION.read_text(encoding="utf-8")
        if "(call_ptr)" not in sentinel_text:
            errors.append(f"{relative(SENTINEL_REGRESSION)} no longer exercises a missing callee")

    test_text = (ROOT / "test.sh").read_text(encoding="utf-8")
    for fixture in INVALID_VERSION_FIXTURES:
        if fixture.stem not in test_text:
            errors.append(f"test.sh does not register {fixture.stem}")
    if "backend failure created output" not in test_text:
        errors.append("test.sh does not reject partial backend outputs")
    if "effect allocation walk guards missing call_ptr callee" not in test_text:
        errors.append("test.sh does not run the AST sentinel regression")

    test_all_text = (ROOT / "test-all.sh").read_text(encoding="utf-8")
    if 'python3 "$ROOT/scripts/check_wir_core_version.py"' not in test_all_text:
        errors.append("test-all.sh does not run the WIR core-version audit")

    for path in CURRENT_DOCS:
        text = path.read_text(encoding="utf-8")
        for term in STALE_DOC_TERMS:
            if term in text:
                errors.append(f"{relative(path)} contains stale WIR text {term!r}")
        errors.extend(unattributed_superseded_mentions(path, text))
        errors.extend(duplicated_source_manifest(path, text))
    index_text = (ROOT / "docs/index.md").read_text(encoding="utf-8")
    if f"[WIR core version {CURRENT_CORE_VERSION}](wir.md)" not in index_text:
        errors.append("docs/index.md does not link the current WIR contract")

    return errors


def main() -> int:
    errors = audit()
    if errors:
        for error in errors:
            print(f"wir-core-version: error: {error}", file=sys.stderr)
        return 1

    print("wir-core-version: self-hosted compiler, fixtures, docs, and AST guards are valid")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
