#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Validate the version-1 Weave project manifest specification corpus."""

from __future__ import annotations

import json
import re
from dataclasses import dataclass
from pathlib import Path

from check_wir_next_source_locations import (
    Atom,
    ValidationError,
    list_head,
    parse,
    require_list,
    require_string,
)

ROOT = Path(__file__).resolve().parents[1]
CORPUS = ROOT / "spec/project-manifest/corpus.json"
IDENT = re.compile(r"[A-Za-z][A-Za-z0-9_-]*\Z")
DRIVE = re.compile(r"[A-Za-z]:")
ALLOWED_FIELDS = {
    "format",
    "name",
    "kind",
    "source-roots",
    "test-roots",
    "entry",
    "output",
}


@dataclass(frozen=True)
class Manifest:
    name: str
    kind: str
    source_roots: tuple[str, ...]
    test_roots: tuple[str, ...]
    entry: str | None
    output: str


def require_identifier(node: object, context: str) -> str:
    if not isinstance(node, Atom) or node.kind != "atom":
        raise ValidationError(f"{context} must be an identifier")
    return node.value


def one_value(field: list[object], context: str) -> object:
    if len(field) != 2:
        raise ValidationError(f"{context} must contain exactly one value")
    return field[1]


def portable_identifier(node: object, context: str) -> str:
    value = require_identifier(node, context)
    if IDENT.fullmatch(value) is None:
        raise ValidationError(
            f"{context} must match [A-Za-z][A-Za-z0-9_-]*"
        )
    return value


def root_path(node: object, context: str) -> str:
    value = require_string(node, context)
    if not value:
        raise ValidationError(f"{context} must not be empty")
    if "\x00" in value:
        raise ValidationError(f"{context} must not contain NUL")
    if "\\" in value:
        raise ValidationError(f"{context} must use '/' separators")
    if value.startswith("/") or DRIVE.match(value):
        raise ValidationError(f"{context} must be project-relative")
    if any(part in {"", ".", ".."} for part in value.split("/")):
        raise ValidationError(f"{context} has a noncanonical path component")
    return value


def normalized_roots(
    values: list[str], context: str, *, nonempty: bool
) -> tuple[str, ...]:
    if nonempty and not values:
        raise ValidationError(f"{context} must contain at least one path")
    if len(set(values)) != len(values):
        raise ValidationError(f"{context} contains a duplicate path")
    ordered = tuple(sorted(values, key=lambda value: value.encode("utf-8")))
    for index, left in enumerate(ordered):
        for right in ordered[index + 1 :]:
            if right.startswith(left + "/"):
                raise ValidationError(
                    f"{context} contains overlapping paths {left!r} and {right!r}"
                )
    return ordered


def output_name(node: object) -> str:
    value = require_string(node, "output name")
    if not value:
        raise ValidationError("output name must not be empty")
    if "\x00" in value:
        raise ValidationError("output name must not contain NUL")
    if value in {".", ".."} or "/" in value or "\\" in value:
        raise ValidationError("output name must be one path component")
    return value


def validate(text: str) -> Manifest:
    if not text.strip():
        raise ValidationError("manifest is empty")
    root = require_list(parse(text), "manifest root")
    if list_head(root) != "weave-project":
        raise ValidationError("manifest root must be weave-project")

    fields: dict[str, list[object]] = {}
    for node in root[1:]:
        field = require_list(node, "manifest field")
        name = list_head(field)
        if name is None:
            raise ValidationError("manifest field must have an identifier head")
        if name not in ALLOWED_FIELDS:
            raise ValidationError(f"unknown manifest field {name!r}")
        if name in fields:
            raise ValidationError(f"duplicate manifest field {name!r}")
        fields[name] = field

    for required in ("format", "name", "kind", "source-roots"):
        if required not in fields:
            raise ValidationError(f"missing manifest field {required!r}")

    version = require_identifier(
        one_value(fields["format"], "format field"), "format version"
    )
    if version != "1":
        raise ValidationError("unsupported project manifest format")

    name = portable_identifier(
        one_value(fields["name"], "name field"), "project name"
    )
    kind = require_identifier(
        one_value(fields["kind"], "kind field"), "project kind"
    )
    if kind not in {"executable", "library"}:
        raise ValidationError("project kind must be executable or library")

    source_roots = normalized_roots(
        [root_path(node, "source root") for node in fields["source-roots"][1:]],
        "source-roots",
        nonempty=True,
    )
    test_nodes = fields["test-roots"][1:] if "test-roots" in fields else []
    test_values = (
        [root_path(node, "test root") for node in test_nodes]
        if "test-roots" in fields
        else ["test"]
    )
    test_roots = normalized_roots(test_values, "test-roots", nonempty=False)

    for source in source_roots:
        for test in test_roots:
            if (
                source == test
                or source.startswith(test + "/")
                or test.startswith(source + "/")
            ):
                raise ValidationError(
                    "source-roots and test-roots must not overlap: "
                    f"{source!r} and {test!r}"
                )

    entry = None
    if "entry" in fields:
        entry = portable_identifier(
            one_value(fields["entry"], "entry field"), "entry module"
        )
    if kind == "executable" and entry is None:
        raise ValidationError("executable project requires an entry field")
    if kind == "library" and entry is not None:
        raise ValidationError("library project must not contain an entry field")

    output = (
        output_name(one_value(fields["output"], "output field"))
        if "output" in fields
        else name
    )
    return Manifest(name, kind, source_roots, test_roots, entry, output)


def quote(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


def serialize(manifest: Manifest) -> str:
    lines = [
        "(weave-project",
        "  (format 1)",
        f"  (name {manifest.name})",
        f"  (kind {manifest.kind})",
        "  (source-roots"
        + "".join(f" {quote(path)}" for path in manifest.source_roots)
        + ")",
        "  (test-roots"
        + "".join(f" {quote(path)}" for path in manifest.test_roots)
        + ")",
    ]
    if manifest.entry is not None:
        lines.append(f"  (entry {manifest.entry})")
    lines.append(f"  (output {quote(manifest.output)}))")
    return "\n".join(lines) + "\n"


def corpus() -> tuple[list[object], list[object]]:
    try:
        data = json.loads(CORPUS.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ValidationError(f"cannot load project-manifest corpus: {exc}") from exc
    if not isinstance(data, dict):
        raise ValidationError("project-manifest corpus root must be an object")
    canonical = data.get("canonical")
    invalid = data.get("invalid")
    if not isinstance(canonical, list) or not isinstance(invalid, list):
        raise ValidationError("corpus requires canonical and invalid case arrays")
    return canonical, invalid


def case_strings(case: object, field: str) -> tuple[str, str, str]:
    if not isinstance(case, dict):
        raise ValidationError("corpus case must be an object")
    values = (case.get("name"), case.get("input"), case.get(field))
    if not all(isinstance(value, str) for value in values):
        raise ValidationError("corpus case fields must be strings")
    return values  # type: ignore[return-value]


def main() -> int:
    canonical, invalid = corpus()
    seen: set[str] = set()
    for case in canonical:
        name, source, expected = case_strings(case, "canonical")
        if name in seen:
            raise ValidationError(f"duplicate corpus case {name!r}")
        seen.add(name)
        actual = serialize(validate(source))
        if actual != expected:
            raise ValidationError(f"canonical case {name!r} mismatch")
        if serialize(validate(actual)) != actual:
            raise ValidationError(f"canonical case {name!r} is not idempotent")

    for case in invalid:
        name, source, expected = case_strings(case, "error")
        if name in seen:
            raise ValidationError(f"duplicate corpus case {name!r}")
        seen.add(name)
        try:
            validate(source)
        except ValidationError as exc:
            if str(exc) != expected:
                raise ValidationError(
                    f"invalid case {name!r} produced {str(exc)!r}; "
                    f"expected {expected!r}"
                ) from exc
        else:
            raise ValidationError(f"invalid case {name!r} unexpectedly passed")

    print(
        "project-manifest-spec: "
        f"{len(canonical)} canonical and {len(invalid)} invalid cases passed"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
