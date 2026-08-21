#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Validate the weavec test specification corpus and JSON schema."""

from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DOC = ROOT / "docs/testing.md"
SCHEMA = ROOT / "docs/schemas/weavec-test-results-v1.schema.json"
CORPUS = ROOT / "spec/testing/corpus.json"

REQUIRED_DOC_PHRASES = (
    "(test NAME",
    "(expect EXPR)",
    "(expect-eq A B)",
    "(expect-ne A B)",
    "(fail)",
    "test.duplicate-name",
    "weavec-test-results-v1",
    "urn:weavec:schema:test-results:v1",
    "WIR v3",
    "`20`",
    "`21`",
    "filtered",
    "crashed",
)

IDENT = re.compile(r"[A-Za-z][A-Za-z0-9_-]*\Z")
TEST_STATUSES = {
    "passed",
    "failed",
    "error",
    "crashed",
    "skipped",
    "filtered",
}
DOC_STATUSES = {"passed", "failed", "error"}


def fail(message: str) -> None:
    raise SystemExit(f"testing-spec: {message}")


def require_ident(value: object, context: str) -> str:
    if not isinstance(value, str) or IDENT.fullmatch(value) is None:
        fail(f"{context} must be a portable identifier")
    return value


def validate_result_document(document: object, context: str) -> None:
    if not isinstance(document, dict):
        fail(f"{context} must be an object")
    for key in ("format", "status", "exit_code", "tests"):
        if key not in document:
            fail(f"{context} missing {key}")
    if document["format"] != "weavec-test-results-v1":
        fail(f"{context} format must be weavec-test-results-v1")
    if document["status"] not in DOC_STATUSES:
        fail(f"{context} status {document['status']!r} is not admitted")
    exit_code = document["exit_code"]
    if not isinstance(exit_code, int) or exit_code < 0:
        fail(f"{context} exit_code must be a non-negative integer")
    tests = document["tests"]
    if not isinstance(tests, list):
        fail(f"{context} tests must be an array")
    for index, record in enumerate(tests):
        prefix = f"{context} tests[{index}]"
        if not isinstance(record, dict):
            fail(f"{prefix} must be an object")
        for key in ("name", "module", "tags", "status", "message"):
            if key not in record:
                fail(f"{prefix} missing {key}")
        require_ident(record["name"], f"{prefix} name")
        require_ident(record["module"], f"{prefix} module")
        tags = record["tags"]
        if not isinstance(tags, list):
            fail(f"{prefix} tags must be an array")
        seen: set[str] = set()
        for tag in tags:
            ident = require_ident(tag, f"{prefix} tag")
            if ident in seen:
                fail(f"{prefix} duplicate tag {ident}")
            seen.add(ident)
        if record["status"] not in TEST_STATUSES:
            fail(f"{prefix} status {record['status']!r} is not admitted")
        message = record["message"]
        if message is not None and not isinstance(message, str):
            fail(f"{prefix} message must be a string or null")


def main() -> int:
    doc = DOC.read_text(encoding="utf-8")
    for phrase in REQUIRED_DOC_PHRASES:
        if phrase not in doc:
            fail(f"docs/testing.md missing {phrase!r}")

    schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
    if schema.get("$id") != "urn:weavec:schema:test-results:v1":
        fail("schema $id must be urn:weavec:schema:test-results:v1")
    if schema.get("properties", {}).get("format", {}).get("const") != (
        "weavec-test-results-v1"
    ):
        fail("schema format const is wrong")

    corpus = json.loads(CORPUS.read_text(encoding="utf-8"))
    for group in ("valid", "invalid", "results"):
        if group not in corpus or not isinstance(corpus[group], list):
            fail(f"corpus missing {group} array")
        if not corpus[group]:
            fail(f"corpus {group} is empty")

    for case in corpus["valid"]:
        name = case.get("name")
        source = case.get("source")
        if not name or not isinstance(source, str) or "(test " not in source:
            fail(f"valid case {name!r} must contain a test declaration")

    errors = {case["error"] for case in corpus["invalid"] if "error" in case}
    for code in (
        "test.nested",
        "test.duplicate-name",
        "test.duplicate-tag",
        "test.return",
        "test.collision",
        "test.expect-type",
        "test.expect-eq-type",
        "test.malformed-name",
    ):
        if code not in errors:
            fail(f"corpus missing invalid case for {code}")
        if code not in doc:
            fail(f"docs/testing.md missing diagnostic {code}")

    for case in corpus["results"]:
        validate_result_document(
            case.get("document"), f"results/{case.get('name')}"
        )

    print("testing-spec: forms, diagnostics, exits, and JSON schema passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
