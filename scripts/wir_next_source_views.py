#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Materialize canonical and executable WIR vNext source views."""

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Sequence

from check_wir_next_source_locations import (
    Atom,
    ValidationError,
    list_head,
    parse,
    validate,
)

ROOT = Path(__file__).resolve().parents[1]
FIXTURE_DIR = ROOT / "spec/wir-vnext-source-locations"
MANIFEST = FIXTURE_DIR / "manifest.json"


def canonical_text(node: object) -> str:
    """Serialize one parsed tree into the compact canonical reference form."""
    if isinstance(node, Atom):
        if node.kind == "atom":
            return node.value
        if node.kind == "string":
            return json.dumps(node.value, ensure_ascii=False)
        raise ValidationError(f"unsupported token kind {node.kind!r}")
    if isinstance(node, list):
        return "(" + " ".join(canonical_text(child) for child in node) + ")"
    raise ValidationError(f"unsupported parsed node {type(node).__name__}")


def strip_observational(node: object) -> object:
    """Remove observational wrappers while preserving the wrapped WIR tree."""
    if not isinstance(node, list):
        return node

    head = list_head(node)
    if head == "located":
        if len(node) != 3:
            raise ValidationError("located has noncanonical shape")
        return strip_observational(node[2])
    if head == "annotated":
        if len(node) != 3 or list_head(node[1]) != "metadata":
            raise ValidationError("annotated has noncanonical shape")
        return strip_observational(node[2])

    return [strip_observational(child) for child in node]


def executable_tree(root: object) -> object:
    """Remove source tables and observational wrappers from one module."""
    if not isinstance(root, list) or list_head(root) != "core-module":
        raise ValidationError("expected core-module root")

    result: list[object] = [root[0]]
    for child in root[1:]:
        if list_head(child) in {"sources", "locations"}:
            continue
        result.append(strip_observational(child))
    return result


def load_module(path: Path) -> object:
    text = path.read_text(encoding="utf-8")
    validate(text)
    return parse(text)


def materialize(mode: str, path: Path) -> str:
    root = load_module(path)
    if mode == "canonical":
        view = root
    elif mode == "executable":
        view = executable_tree(root)
    else:
        raise ValidationError(f"unknown comparison mode {mode!r}")
    return canonical_text(view) + "\n"


def compare(mode: str, left: Path, right: Path) -> bool:
    return materialize(mode, left) == materialize(mode, right)


def self_test() -> None:
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))

    for name in manifest["valid"]:
        path = FIXTURE_DIR / name
        root = load_module(path)

        canonical = canonical_text(root)
        if canonical_text(parse(canonical)) != canonical:
            raise ValidationError(f"canonical view is not idempotent for {name}")

        executable = canonical_text(executable_tree(root))
        if canonical_text(parse(executable)) != executable:
            raise ValidationError(
                f"executable view is not idempotent for {name}"
            )
        for forbidden in ("(sources ", "(locations ", "(located ", "(annotated "):
            if forbidden in executable:
                raise ValidationError(
                    f"executable view retained {forbidden.strip()} in {name}"
                )

    pair = manifest["comparison_pair"]
    left = FIXTURE_DIR / pair["left"]
    right = FIXTURE_DIR / pair["right"]
    if compare("canonical", left, right):
        raise ValidationError("canonical comparison ignored source metadata")
    if not compare("executable", left, right):
        raise ValidationError("executable comparison retained source metadata")

    print(
        "wir-next-source-views: canonical and executable comparisons passed"
    )


def usage() -> str:
    return (
        "usage:\n"
        "  wir_next_source_views.py self-test\n"
        "  wir_next_source_views.py canonical PATH\n"
        "  wir_next_source_views.py executable PATH\n"
        "  wir_next_source_views.py compare MODE LEFT RIGHT\n"
    )


def main(argv: Sequence[str]) -> int:
    try:
        if list(argv) == ["self-test"]:
            self_test()
            return 0
        if len(argv) == 2 and argv[0] in {"canonical", "executable"}:
            sys.stdout.write(materialize(argv[0], Path(argv[1])))
            return 0
        if len(argv) == 4 and argv[0] == "compare":
            mode, left, right = argv[1:]
            equal = compare(mode, Path(left), Path(right))
            print("equal" if equal else "different")
            return 0 if equal else 1
    except (OSError, json.JSONDecodeError, ValidationError) as exc:
        print(f"wir-next-source-views: {exc}", file=sys.stderr)
        return 2

    print(usage(), file=sys.stderr, end="")
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
