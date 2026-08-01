#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCHEMA="$ROOT/docs/schemas/weavec-semantic-index-v1.schema.json"
EXAMPLE="$ROOT/docs/schemas/examples/weavec-semantic-index-v1.example.json"

python3 - "$SCHEMA" "$EXAMPLE" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

schema_path = Path(sys.argv[1])
example_path = Path(sys.argv[2])
schema = json.loads(schema_path.read_text(encoding="utf-8"))
doc = json.loads(example_path.read_text(encoding="utf-8"))

assert schema["$schema"] == "https://json-schema.org/draft/2020-12/schema"
assert schema["$id"] == "urn:weavec:schema:semantic-index:v1"
assert schema["title"] == "weavec-semantic-index-v1"

required = set(schema["required"])
assert required <= set(doc)
assert doc["format"] == "weavec-semantic-index-v1"
assert doc["schema_id"] == schema["$id"]
assert doc["schema_version"] == 1
assert doc["analysis"]["status"] == "complete"
assert doc["analysis"]["complete"] is True
assert doc["analysis"]["diagnostics_complete"] is True
assert doc["diagnostics"]["complete"] is True

hex64 = lambda value: (
    isinstance(value, str)
    and len(value) == 64
    and all(char in "0123456789abcdef" for char in value)
)
assert hex64(doc["analysis"]["source_set_sha256"])
assert hex64(doc["analysis"]["options_sha256"])

sources = doc["sources"]
assert [item["index"] for item in sources] == list(range(len(sources)))
assert [item["id"] for item in sources] == [
    f"source:{index}" for index in range(len(sources))
]
source_by_id = {item["id"]: item for item in sources}
assert len(source_by_id) == len(sources)
for source in sources:
    assert source["path"] and not source["path"].startswith("/")
    assert source["byte_length"] >= 0
    assert hex64(source["sha256"])

source_order = {item["id"]: item["index"] for item in sources}

def check_span(span):
    source = source_by_id[span["source_id"]]
    assert 0 <= span["start"] <= span["end"] <= source["byte_length"]

modules = doc["modules"]
assert [item["id"] for item in modules] == [
    f"module:{index}" for index in range(len(modules))
]
assert modules == sorted(
    modules,
    key=lambda item: (
        source_order[item["source_id"]],
        item["definition"]["start"],
        item["name"].encode("utf-8"),
    ),
)
module_by_id = {item["id"]: item for item in modules}
assert len(module_by_id) == len(modules)
for module in modules:
    assert module["source_id"] in source_by_id
    check_span(module["definition"])
    assert module["definition"]["source_id"] == module["source_id"]
    assert module["interface"]["hash_algorithm"] == "sha256-weave-interface-v1"
    assert hex64(module["interface"]["sha256"])

symbols = doc["symbols"]
assert [item["id"] for item in symbols] == [
    f"symbol:{index}" for index in range(len(symbols))
]
assert symbols == sorted(
    symbols,
    key=lambda item: (
        int(item["module_id"].split(":", 1)[1]),
        item["definition"]["start"],
        item["kind"].encode("utf-8"),
        item["name"].encode("utf-8"),
    ),
)
symbol_by_id = {item["id"]: item for item in symbols}
assert len(symbol_by_id) == len(symbols)
for symbol in symbols:
    assert symbol["module_id"] in module_by_id
    check_span(symbol["definition"])
    assert symbol["signature"]["canonical"]

references = doc["references"]
assert [item["id"] for item in references] == [
    f"reference:{index}" for index in range(len(references))
]
assert references == sorted(
    references,
    key=lambda item: (
        source_order[item["span"]["source_id"]],
        item["span"]["start"],
        item["span"]["end"],
        item["role"].encode("utf-8"),
        (item["symbol_id"] or "").encode("utf-8"),
    ),
)
reference_by_id = {item["id"]: item for item in references}
assert len(reference_by_id) == len(references)
for reference in references:
    check_span(reference["span"])
    if reference["symbol_id"] is not None:
        assert reference["symbol_id"] in symbol_by_id

for index, item in enumerate(doc["imports"]):
    assert item["id"] == f"import:{index}"
    assert item["module_id"] in module_by_id
    assert item["imported_module_id"] in module_by_id
    assert item["symbol_id"] in symbol_by_id
    check_span(item["span"])

for index, item in enumerate(doc["exports"]):
    assert item["id"] == f"export:{index}"
    assert item["module_id"] in module_by_id
    assert item["symbol_id"] in symbol_by_id
    check_span(item["span"])

for index, edge in enumerate(doc["call_edges"]):
    assert edge["id"] == f"call-edge:{index}"
    assert edge["caller_symbol_id"] in symbol_by_id
    assert edge["callee_symbol_id"] in symbol_by_id
    assert edge["call_reference_id"] in reference_by_id
    assert reference_by_id[edge["call_reference_id"]]["role"] == "call"

for module in modules:
    exported = [symbol_by_id[symbol_id] for symbol_id in module["interface"]["exports"]]
    assert all(symbol["module_id"] == module["id"] for symbol in exported)
    assert all(symbol["visibility"] == "public" for symbol in exported)
    exported = sorted(
        exported,
        key=lambda symbol: (
            symbol["name"].encode("utf-8"),
            symbol["kind"].encode("utf-8"),
            symbol["signature"]["canonical"].encode("utf-8"),
        ),
    )
    canonical = {
        "module": module["name"],
        "exports": [
            {
                "kind": symbol["kind"],
                "name": symbol["name"],
                "signature": symbol["signature"]["canonical"],
            }
            for symbol in exported
        ],
    }
    payload = json.dumps(
        canonical,
        ensure_ascii=False,
        separators=(",", ":"),
    ).encode("utf-8")
    actual = hashlib.sha256(payload).hexdigest()
    assert actual == module["interface"]["sha256"]

print("semantic-index-contract: schema and example passed")
PY
