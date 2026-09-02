#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Validate the compiler-independent surface conformance corpus (#385).

This is a file-based completeness and discoverability guard. It never builds or
runs the compiler; `test/conformance/run.sh` owns behavior. The guard exists so
the corpus cannot silently shrink to a hand-maintained subset: every case
directory must be registered, every registered case must exist, every case must
declare a complete public-behavior expectation, every required coverage area
must have at least one case, and the runner must stay wired into the checks that
qualify a built compiler.
"""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CORPUS = ROOT / "test/conformance"
CASES = CORPUS / "cases"
MANIFEST = CORPUS / "MANIFEST"
RUNNER = CORPUS / "run.sh"
DOC = ROOT / "docs/conformance.md"
INDEX = ROOT / "docs/index.md"

WIRED_INTO = (
    ROOT / "scripts/pr-compile.sh",
    ROOT / "scripts/test-all.sh",
    ROOT / "scripts/selfhost.sh",
)

CASE_NAME = re.compile(r"[a-z][a-z0-9-]*\Z")
DIAGNOSTIC_CODE = re.compile(r"[a-z][a-z0-9.-]*\Z")
PROGRAM_EXIT = re.compile(r"(0|[1-9][0-9]{0,2})\Z")
STABLE_PHASE_EXITS = {"10", "11", "12", "13", "14", "15"}

MODES = {"run", "compile-fail", "format"}

# The corpus is a public language contract, so its coverage areas are fixed
# here rather than derived from whatever the corpus currently happens to hold.
REQUIRED_AREAS = {
    "control-flow",
    "functions-modules",
    "data-types",
    "option-result",
    "strings",
    "contracts",
    "stdlib",
    "formatting",
}

REQUIRED_KEYS = ("mode", "area", "sources", "canonical")

# Expectations must stay public behavior. These substrings are compiler-internal
# spellings that a conformance expectation must never assert.
FORBIDDEN_EXPECTATION_SUBSTRINGS = (
    "core-module",
    "core-version",
    "__weave_m_",
    "__s__",
    "call_i32",
    "call_ptr",
    "const_i32",
    "define ",
    "@main",
)

failures: list[str] = []


def fail(message: str) -> None:
    failures.append(message)


def read_manifest() -> list[str]:
    if not MANIFEST.is_file():
        fail(f"missing case manifest: {MANIFEST.relative_to(ROOT)}")
        return []
    names = []
    for line in MANIFEST.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        names.append(stripped)
    return names


def read_meta(path: Path) -> dict[str, str]:
    meta: dict[str, str] = {}
    for number, line in enumerate(
        path.read_text(encoding="utf-8").splitlines(), start=1
    ):
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if ":" not in stripped:
            fail(f"{path.relative_to(ROOT)}:{number}: expected 'key: value'")
            continue
        key, _, value = stripped.partition(":")
        key = key.strip()
        value = value.strip()
        if key in meta:
            fail(f"{path.relative_to(ROOT)}:{number}: duplicate key {key}")
            continue
        meta[key] = value
    return meta


def check_case(name: str) -> str | None:
    directory = CASES / name
    label = f"cases/{name}"
    if CASE_NAME.fullmatch(name) is None:
        fail(f"{label}: case directory must be lowercase kebab-case")
    meta_path = directory / "meta"
    if not meta_path.is_file():
        fail(f"{label}: missing meta")
        return None
    meta = read_meta(meta_path)
    for key in REQUIRED_KEYS:
        if key not in meta:
            fail(f"{label}: meta is missing {key}")
    mode = meta.get("mode", "")
    if mode not in MODES:
        fail(f"{label}: unknown mode {mode!r}")
    area = meta.get("area", "")
    if area not in REQUIRED_AREAS:
        fail(f"{label}: unknown area {area!r}")
    if meta.get("canonical") not in {"yes", "no"}:
        fail(f"{label}: canonical must be yes or no")

    declared = meta.get("sources", "").split()
    if not declared:
        fail(f"{label}: meta declares no sources")
    for source in declared:
        if not (directory / source).is_file():
            fail(f"{label}: declared source not found: {source}")
    present = sorted(path.name for path in directory.glob("*.weave"))
    for source in present:
        if source not in declared:
            fail(f"{label}: {source} is present but not declared in sources")
    if mode == "format" and len(declared) != 1:
        fail(f"{label}: a format case declares exactly one source")

    for module in meta.get("stdlib", "").split():
        if not (ROOT / "stdlib" / module).is_file():
            fail(f"{label}: unknown standard-library module: {module}")

    exit_code = meta.get("exit")
    if exit_code is not None:
        if PROGRAM_EXIT.fullmatch(exit_code) is None or int(exit_code) > 255:
            fail(f"{label}: exit {exit_code!r} is not a process exit status")

    if mode == "run":
        if not (directory / "expected-stdout").is_file():
            fail(f"{label}: a run case requires expected-stdout")
    if mode == "compile-fail":
        code = meta.get("diagnostic", "")
        if DIAGNOSTIC_CODE.fullmatch(code) is None:
            fail(f"{label}: compile-fail requires a stable diagnostic code")
        if meta.get("exit", "10") not in STABLE_PHASE_EXITS:
            fail(f"{label}: compile-fail exit must be a stable phase code")
        for artifact in ("expected-stdout", "expected-stderr"):
            if (directory / artifact).exists():
                fail(f"{label}: compile-fail must not declare {artifact}")
    if mode == "format":
        if not (directory / "expected-format").is_file():
            fail(f"{label}: a format case requires expected-format")

    for artifact in ("expected-stdout", "expected-stderr", "expected-format"):
        path = directory / artifact
        if not path.is_file():
            continue
        text = path.read_text(encoding="utf-8")
        for needle in FORBIDDEN_EXPECTATION_SUBSTRINGS:
            if needle in text and artifact != "expected-format":
                fail(
                    f"{label}/{artifact}: asserts compiler-internal "
                    f"spelling {needle!r}"
                )

    unknown = set(meta) - {
        "mode",
        "area",
        "sources",
        "stdlib",
        "args",
        "exit",
        "diagnostic",
        "canonical",
    }
    for key in sorted(unknown):
        fail(f"{label}: unknown meta key {key}")

    return area


def main() -> None:
    if not CASES.is_dir():
        raise SystemExit(f"conformance-corpus: missing {CASES.relative_to(ROOT)}")

    discovered = sorted(path.name for path in CASES.iterdir() if path.is_dir())
    registered = read_manifest()

    if sorted(registered) != registered:
        fail("MANIFEST entries must be sorted")
    if len(set(registered)) != len(registered):
        fail("MANIFEST contains a duplicate entry")
    for name in sorted(set(discovered) - set(registered)):
        fail(f"cases/{name} exists but is not registered in MANIFEST")
    for name in sorted(set(registered) - set(discovered)):
        fail(f"MANIFEST registers {name}, which has no case directory")

    if not discovered:
        fail("the corpus contains no cases")

    areas = set()
    for name in discovered:
        area = check_case(name)
        if area is not None:
            areas.add(area)
    for area in sorted(REQUIRED_AREAS - areas):
        fail(f"no case covers the required area: {area}")

    if not RUNNER.is_file():
        fail("missing test/conformance/run.sh")
    else:
        runner = RUNNER.read_text(encoding="utf-8")
        for name in discovered:
            if name in runner:
                fail(f"run.sh names case {name}; cases must be discovered")

    for script in WIRED_INTO:
        if not script.is_file():
            fail(f"missing {script.relative_to(ROOT)}")
            continue
        if "test/conformance/run.sh" not in script.read_text(encoding="utf-8"):
            fail(f"{script.relative_to(ROOT)} does not run the corpus")

    if not DOC.is_file():
        fail("missing docs/conformance.md")
    if INDEX.is_file() and "conformance.md" not in INDEX.read_text(
        encoding="utf-8"
    ):
        fail("docs/index.md does not link docs/conformance.md")

    if failures:
        for message in failures:
            print(f"conformance-corpus: {message}")
        raise SystemExit(1)
    print(f"conformance-corpus: {len(discovered)} cases, {len(areas)} areas")


if __name__ == "__main__":
    main()
