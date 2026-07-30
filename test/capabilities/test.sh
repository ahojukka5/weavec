#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-capabilities-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'capabilities: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}

"$WEAVEC" capabilities --json > "$TMP/first.json"
"$WEAVEC" capabilities --json > "$TMP/second.json"
cmp "$TMP/first.json" "$TMP/second.json"

if "$WEAVEC" capabilities >/dev/null 2>&1; then
  printf 'capabilities: missing --json was accepted\n' >&2
  exit 1
fi
if "$WEAVEC" capabilities --text >/dev/null 2>&1; then
  printf 'capabilities: unsupported output mode was accepted\n' >&2
  exit 1
fi
if "$WEAVEC" capabilities --json extra >/dev/null 2>&1; then
  printf 'capabilities: extra argument was accepted\n' >&2
  exit 1
fi

python3 - "$TMP/first.json" \
  "$ROOT/test/capabilities/expected-summary.json" \
  "$ROOT/docs/schemas/weavec-capabilities-v1.schema.json" <<'PY'
import json
import pathlib
import sys

actual_path = pathlib.Path(sys.argv[1])
expected_path = pathlib.Path(sys.argv[2])
schema_path = pathlib.Path(sys.argv[3])

actual = json.loads(actual_path.read_text(encoding="utf-8"))
expected = json.loads(expected_path.read_text(encoding="utf-8"))
schema = json.loads(schema_path.read_text(encoding="utf-8"))

assert actual["format"] == "weavec-capabilities-v1"
assert actual["schema_id"] == "urn:weavec:schema:capabilities:v1"
assert actual["schema_version"] == 1
assert schema["$id"] == actual["schema_id"]
assert schema["properties"]["format"]["const"] == actual["format"]
assert schema["additionalProperties"] is True

version = actual["compiler"]["version"]
assert version and version.startswith("v")
default_target = actual["targets"]["default"]
assert default_target
installed = actual["targets"]["installed"]
assert len(installed) == 1
assert installed[0]["triple"] == default_target

summary = {
    "format": actual["format"],
    "schema_id": actual["schema_id"],
    "schema_version": actual["schema_version"],
    "compiler": [
        actual["compiler"]["name"],
        "<compiler-version>",
        actual["compiler"]["public_variant"],
    ],
    "language": [
        actual["language"][key]
        for key in (
            "name", "surface_version", "grammar_id", "syntax",
            "case_sensitive", "wir_core_version",
        )
    ],
    "protocols": [
        [item["id"], item["kind"], item["version"]]
        for item in actual["protocols"]
    ],
    "commands": [
        [
            item["name"], item["spelling"], item["audience"],
            item["status"], item["protocols"],
        ]
        for item in actual["commands"]
    ],
    "targets": [
        "<default-target>",
        [[
            "<default-target>", item["native"], item["cross_compilation"],
            item["runtime"], item["optimization_levels"], item["cpu_selection"],
        ] for item in installed],
    ],
    "features": [
        [item["id"], item["status"], item["issue"]]
        for item in actual["features"]
    ],
    "types": actual["surface"]["types"],
    "operators": [
        [item["id"], item["names"], item["arity"], item["types"], item["result"]]
        for item in actual["surface"]["operators"]
    ],
    "casts": [
        [item["source"], item["target"]]
        for item in actual["surface"]["casts"]
    ],
    "literals": [
        [item["kind"], item["types"], item["contexts"]]
        for item in actual["surface"]["contextual_literals"]
    ],
    "forms": [
        [
            item["head"], item["status"], item["arity"]["min_children"],
            item["arity"]["max_children"], item["type_information"],
            item["feature"], item["canonical_replacement"],
        ]
        for item in actual["surface"]["forms"]
    ],
    "families": [
        [
            item["id"], item["status"], item["head_pattern"],
            item["canonical_replacement"], item["type_information"],
            item["grammar_reference"], item["members"],
        ]
        for item in actual["surface"]["compatibility_families"]
    ],
}
assert summary == expected

protocol_ids = [item["id"] for item in actual["protocols"]
command_names = [item["name"] for item in actual["commands"]
feature_ids = [item["id"] for item in actual["features"]
form_heads = [item["head"] for item in actual["surface"]["forms"]
family_ids = [item["id"] for item in actual["surface"]["compatibility_families"]

for name, values in (
    ("protocol", protocol_ids),
    ("command", command_names),
    ("feature", feature_ids),
    ("form", form_heads),
    ("compatibility family", family_ids),
):
    assert len(values) == len(set(values)), f"duplicate {name}"

assert {
    "weavec-capabilities-v1",
    "weavec-build-manifest-v1",
    "weavec-diagnostics-v1",
    "weavec-compilation-trace-v1",
    "weave-wir-core-v2",
}.issubset(protocol_ids)
assert {
    "capabilities",
    "build",
    "frontend",
    "backend",
    "version",
}.issubset(command_names)
assert {
    "program",
    "fn",
    "entry",
    "call",
    "op",
    "cast",
    "requires",
    "ensures",
}.issubset(form_heads)

known_features = set(feature_ids)
for form in actual["surface"]["forms"]:
    arity = form["arity"]
    assert arity["min_children"] >= 0
    if arity["max_children"] is not None:
        assert arity["max_children"] >= arity["min_children"]
    positions = [role["position"] for role in form["roles"]]
    assert positions == sorted(positions)
    if form["feature"] is not None:
        assert form["feature"] in known_features
    if form["status"] == "canonical":
        assert form["canonical_replacement"] is None

for family in actual["surface"]["compatibility_families"]:
    assert family["status"] == "compatibility"
    assert family["grammar_reference"] == "weave-wir-core-v2"

serialized = json.dumps(actual, sort_keys=True)
for forbidden in ("weavec0", "weavec1", "weavec-bootstrap"):
    assert forbidden not in serialized

assert actual["compiler"]["public_variant"] == "final"
assert actual["language"]["syntax"] == "s-expression"
assert actual["language"]["case_sensitive"] is True
assert actual["language"]["wir_core_version"] == 2
assert actual["surface"]["child_count_excludes_head"] is True
PY

printf 'capabilities: deterministic registry and schema checks passed\n'
