#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Validate the isolated WIR vNext source-location specification fixtures."""

from __future__ import annotations

import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterator

ROOT = Path(__file__).resolve().parents[1]
FIXTURE_DIR = ROOT / "spec/wir-vnext-source-locations"
MANIFEST = FIXTURE_DIR / "manifest.json"

ROLE_ORDER = {
    "direct": 0,
    "lowering": 1,
    "expansion": 2,
    "related": 3,
}
HEX_64 = re.compile(r"[0-9a-f]{64}\Z")


class ValidationError(ValueError):
    """A deterministic fixture validation failure."""


@dataclass(frozen=True)
class Atom:
    kind: str
    value: str
    offset: int


def tokenize(text: str) -> Iterator[Atom]:
    i = 0
    while i < len(text):
        ch = text[i]
        if ch.isspace():
            i += 1
            continue
        if ch == ";":
            newline = text.find("\n", i)
            i = len(text) if newline == -1 else newline + 1
            continue
        if ch in "()":
            yield Atom(ch, ch, i)
            i += 1
            continue
        if ch == '"':
            start = i
            i += 1
            escaped = False
            while i < len(text):
                current = text[i]
                if escaped:
                    escaped = False
                elif current == "\\":
                    escaped = True
                elif current == '"':
                    i += 1
                    token = text[start:i]
                    try:
                        value = json.loads(token)
                    except json.JSONDecodeError as exc:
                        raise ValidationError(
                            f"invalid string at byte {start}: {exc.msg}"
                        ) from exc
                    yield Atom("string", value, start)
                    break
                i += 1
            else:
                raise ValidationError(f"unterminated string at byte {start}")
            continue

        start = i
        while i < len(text):
            current = text[i]
            if current.isspace() or current in "();":
                break
            i += 1
        if i == start:
            raise ValidationError(f"unexpected byte at offset {i}")
        yield Atom("atom", text[start:i], start)


def parse(text: str) -> object:
    tokens = list(tokenize(text))
    index = 0

    def expression() -> object:
        nonlocal index
        if index >= len(tokens):
            raise ValidationError("unexpected end of input")
        token = tokens[index]
        index += 1
        if token.kind == ")":
            raise ValidationError(f"unexpected ')' at byte {token.offset}")
        if token.kind != "(":
            return token

        items: list[object] = []
        while True:
            if index >= len(tokens):
                raise ValidationError(
                    f"unclosed list starting at byte {token.offset}"
                )
            if tokens[index].kind == ")":
                index += 1
                return items
            items.append(expression())

    root = expression()
    if index != len(tokens):
        raise ValidationError(
            f"trailing expression at byte {tokens[index].offset}"
        )
    return root


def list_head(node: object) -> str | None:
    if (
        isinstance(node, list)
        and node
        and isinstance(node[0], Atom)
        and node[0].kind == "atom"
    ):
        return node[0].value
    return None


def require_list(node: object, context: str) -> list[object]:
    if not isinstance(node, list):
        raise ValidationError(f"{context} must be a list")
    return node


def require_atom(node: object, context: str) -> str:
    if not isinstance(node, Atom) or node.kind != "atom":
        raise ValidationError(f"{context} must be an atom")
    return node.value


def require_string(node: object, context: str) -> str:
    if not isinstance(node, Atom) or node.kind != "string":
        raise ValidationError(f"{context} must be a string")
    return node.value


def require_nonnegative_int(node: object, context: str) -> int:
    value = require_atom(node, context)
    if not value.isdigit():
        raise ValidationError(f"{context} must be a nonnegative integer")
    return int(value)


def one_section(root: list[object], name: str) -> list[object]:
    matches = [
        child
        for child in root[1:]
        if isinstance(child, list) and list_head(child) == name
    ]
    if len(matches) != 1:
        raise ValidationError(
            f"expected exactly one {name} section, found {len(matches)}"
        )
    return matches[0]


def validate_source_name(name: str) -> None:
    if not name:
        raise ValidationError("source name must not be empty")
    if "\\" in name:
        raise ValidationError("source name must use '/' separators")
    if name.startswith("/") or re.match(r"[A-Za-z]:", name):
        raise ValidationError("source name must be logical, not absolute")
    parts = name.split("/")
    if any(part in {"", ".", ".."} for part in parts):
        raise ValidationError("source name has a noncanonical path component")


def validate(text: str) -> None:
    root = require_list(parse(text), "module")
    if list_head(root) != "core-module":
        raise ValidationError("expected core-module root")

    allowed_sections = {"core-version", "sources", "locations", "decls"}
    for child in root[1:]:
        head = list_head(child)
        if head not in allowed_sections:
            raise ValidationError(f"unknown module section {head!r}")

    version = one_section(root, "core-version")
    if len(version) != 2 or require_atom(
        version[1], "core version"
    ) != "3":
        raise ValidationError("expected exactly (core-version 3)")

    sources_section = one_section(root, "sources")
    source_ids: list[int] = []
    referenced_sources: set[int] = set()
    for entry in sources_section[1:]:
        source = require_list(entry, "source entry")
        if list_head(source) != "source" or len(source) != 4:
            raise ValidationError("source entry has noncanonical shape")
        source_id = require_nonnegative_int(source[1], "source id")
        name_field = require_list(source[2], "source name")
        digest_field = require_list(source[3], "source digest")
        if list_head(name_field) != "name" or len(name_field) != 2:
            raise ValidationError("source name has noncanonical shape")
        if list_head(digest_field) != "sha256" or len(digest_field) != 2:
            raise ValidationError("source digest has noncanonical shape")
        validate_source_name(require_string(name_field[1], "source name"))
        digest = require_string(digest_field[1], "source digest")
        if HEX_64.fullmatch(digest) is None:
            raise ValidationError("source digest must be 64 lowercase hex digits")
        source_ids.append(source_id)

    expected_sources = list(range(len(source_ids)))
    if source_ids != expected_sources:
        raise ValidationError(
            f"source ids must be dense and ordered: {expected_sources}"
        )
    source_id_set = set(source_ids)

    locations_section = one_section(root, "locations")
    location_ids: list[int] = []
    derived_edges: dict[int, list[int]] = {}
    for entry in locations_section[1:]:
        location = require_list(entry, "location entry")
        if list_head(location) != "location" or len(location) < 3:
            raise ValidationError("location entry has noncanonical shape")
        location_id = require_nonnegative_int(location[1], "location id")
        location_ids.append(location_id)

        origins: list[tuple[int, int, int, int, str]] = []
        generated = False
        derived: list[int] = []
        for field in location[2:]:
            field_list = require_list(field, "location field")
            field_head = list_head(field_list)
            if field_head == "origin":
                if len(field_list) != 3:
                    raise ValidationError("origin has noncanonical shape")
                role = require_atom(field_list[1], "origin role")
                if role not in ROLE_ORDER:
                    raise ValidationError(f"unknown origin role {role!r}")
                span = require_list(field_list[2], "origin span")
                if list_head(span) != "span" or len(span) != 4:
                    raise ValidationError("span has noncanonical shape")
                source_id = require_nonnegative_int(span[1], "span source id")
                start = require_nonnegative_int(span[2], "span start")
                end = require_nonnegative_int(span[3], "span end")
                if source_id not in source_id_set:
                    raise ValidationError(f"unknown source id {source_id}")
                if end < start:
                    raise ValidationError("span end precedes start")
                referenced_sources.add(source_id)
                origins.append(
                    (ROLE_ORDER[role], source_id, start, end, role)
                )
            elif field_head == "generated":
                if len(field_list) != 1:
                    raise ValidationError("generated has noncanonical shape")
                if generated:
                    raise ValidationError("duplicate generated marker")
                generated = True
            elif field_head == "derived-from":
                if len(field_list) < 3:
                    raise ValidationError(
                        "derived-from requires a role and location ids"
                    )
                role = require_atom(field_list[1], "derived-from role")
                if role not in ROLE_ORDER:
                    raise ValidationError(
                        f"unknown derived-from role {role!r}"
                    )
                derived = [
                    require_nonnegative_int(item, "derived location id")
                    for item in field_list[2:]
                ]
                if derived != sorted(set(derived)):
                    raise ValidationError(
                        "derived location ids must be unique and ordered"
                    )
            else:
                raise ValidationError(
                    f"unknown location field {field_head!r}"
                )

        if generated and origins:
            raise ValidationError(
                "generated location must not contain direct origins"
            )
        if not generated and not origins:
            raise ValidationError(
                "location requires an origin or generated marker"
            )
        if origins != sorted(origins):
            raise ValidationError("origins are not in canonical order")
        derived_edges[location_id] = derived

    expected_locations = list(range(len(location_ids)))
    if location_ids != expected_locations:
        raise ValidationError(
            f"location ids must be dense and ordered: {expected_locations}"
        )
    location_id_set = set(location_ids)
    for targets in derived_edges.values():
        for target in targets:
            if target not in location_id_set:
                raise ValidationError(f"unknown location id {target}")

    state: dict[int, int] = {}

    def visit(location_id: int) -> None:
        marker = state.get(location_id, 0)
        if marker == 1:
            raise ValidationError("location cycle")
        if marker == 2:
            return
        state[location_id] = 1
        for target in derived_edges[location_id]:
            visit(target)
        state[location_id] = 2

    for location_id in location_ids:
        visit(location_id)

    decls = one_section(root, "decls")
    referenced_locations: set[int] = set()
    derived_targets = {
        target
        for targets in derived_edges.values()
        for target in targets
    }

    def walk(node: object) -> None:
        if not isinstance(node, list):
            return
        if list_head(node) == "located":
            if len(node) != 3:
                raise ValidationError("located has noncanonical shape")
            location_id = require_nonnegative_int(
                node[1], "located location id"
            )
            if location_id not in location_id_set:
                raise ValidationError(f"unknown location id {location_id}")
            if list_head(node[2]) == "located":
                raise ValidationError("nested located wrappers are noncanonical")
            referenced_locations.add(location_id)
            walk(node[2])
            return
        for child in node:
            walk(child)

    for declaration in decls[1:]:
        walk(declaration)

    used_locations = referenced_locations | derived_targets
    unreferenced_locations = location_id_set - used_locations
    if unreferenced_locations:
        first = min(unreferenced_locations)
        raise ValidationError(f"unreferenced location id {first}")

    unreferenced_sources = source_id_set - referenced_sources
    if unreferenced_sources:
        first = min(unreferenced_sources)
        raise ValidationError(f"unreferenced source id {first}")


def main() -> int:
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    valid = manifest["valid"]
    invalid = manifest["invalid"]

    listed = set(valid) | set(invalid)
    actual = {path.name for path in FIXTURE_DIR.glob("*.wir-next")}
    if listed != actual:
        missing = sorted(actual - listed)
        stale = sorted(listed - actual)
        raise SystemExit(
            "wir-next-locations: manifest mismatch: "
            f"unlisted={missing} missing={stale}"
        )

    for name in valid:
        try:
            validate((FIXTURE_DIR / name).read_text(encoding="utf-8"))
        except ValidationError as exc:
            raise SystemExit(
                f"wir-next-locations: valid fixture {name} failed: {exc}"
            ) from exc

    for name, expected in invalid.items():
        try:
            validate((FIXTURE_DIR / name).read_text(encoding="utf-8"))
        except ValidationError as exc:
            if expected not in str(exc):
                raise SystemExit(
                    f"wir-next-locations: {name} produced {exc!s}; "
                    f"expected {expected!r}"
                ) from exc
        else:
            raise SystemExit(
                f"wir-next-locations: malformed fixture {name} passed"
            )

    print(
        "wir-next-locations: "
        f"{len(valid)} valid and {len(invalid)} malformed fixtures passed"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
