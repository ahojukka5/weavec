#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Validate WIR vNext digests and spans when source bytes are available."""

from __future__ import annotations

import hashlib
from pathlib import Path

from check_wir_next_source_locations import (
    ValidationError,
    list_head,
    one_section,
    parse,
    require_list,
    require_nonnegative_int,
    require_string,
    validate,
)

ROOT = Path(__file__).resolve().parents[1]
FIXTURE_DIR = ROOT / "spec/wir-vnext-source-bytes"
VALID = FIXTURE_DIR / "valid-utf8-span.wir-next"
OUT_OF_BOUNDS = FIXTURE_DIR / "invalid-out-of-bounds.wir-next"
VALID_DIGEST = "e57d8a8ea6845243ba02420f4a325aa4ff1927fb83a168bdb6a3a102099c24ab"


def source_path(logical_name: str) -> Path:
    path = (FIXTURE_DIR / logical_name).resolve()
    try:
        path.relative_to(FIXTURE_DIR.resolve())
    except ValueError as exc:
        raise ValidationError(
            f"source name escapes fixture directory: {logical_name}"
        ) from exc
    return path


def validate_available_bytes(text: str) -> None:
    """Apply structural validation plus available-source integrity checks."""
    validate(text)
    root = require_list(parse(text), "module")

    source_bytes: dict[int, bytes] = {}
    sources = one_section(root, "sources")
    for entry in sources[1:]:
        source = require_list(entry, "source entry")
        source_id = require_nonnegative_int(source[1], "source id")
        name_field = require_list(source[2], "source name")
        digest_field = require_list(source[3], "source digest")
        name = require_string(name_field[1], "source name")
        expected = require_string(digest_field[1], "source digest")
        data = source_path(name).read_bytes()
        actual = hashlib.sha256(data).hexdigest()
        if actual != expected:
            raise ValidationError(f"source digest mismatch for {name}")
        source_bytes[source_id] = data

    locations = one_section(root, "locations")
    for entry in locations[1:]:
        location = require_list(entry, "location entry")
        for field in location[2:]:
            field_list = require_list(field, "location field")
            if list_head(field_list) != "origin":
                continue
            span = require_list(field_list[2], "origin span")
            source_id = require_nonnegative_int(span[1], "span source id")
            end = require_nonnegative_int(span[3], "span end")
            length = len(source_bytes[source_id])
            if end > length:
                raise ValidationError(
                    f"span end {end} exceeds source length {length}"
                )


def expect_failure(text: str, expected: str) -> None:
    try:
        validate_available_bytes(text)
    except ValidationError as exc:
        if expected not in str(exc):
            raise ValidationError(
                f"produced {exc!s}; expected diagnostic containing {expected!r}"
            ) from exc
    else:
        raise ValidationError(f"malformed source-byte fixture passed: {expected}")


def main() -> int:
    valid_text = VALID.read_text(encoding="utf-8")
    validate_available_bytes(valid_text)

    digest_mismatch = valid_text.replace(VALID_DIGEST, "0" * 64, 1)
    expect_failure(digest_mismatch, "source digest mismatch for utf8.weave")

    expect_failure(
        OUT_OF_BOUNDS.read_text(encoding="utf-8"),
        "span end 9 exceeds source length 8",
    )

    source = (FIXTURE_DIR / "utf8.weave").read_bytes()
    if source[0:2].decode("utf-8") != "π":
        raise ValidationError("two-byte UTF-8 span did not select pi")

    print("wir-next-source-bytes: digest and UTF-8 span checks passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
