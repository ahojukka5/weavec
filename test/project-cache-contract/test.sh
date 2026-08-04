#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCHEMA="$ROOT/docs/schemas/weavec-project-module-cache-v1.schema.json"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-project-cache-contract-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'project-cache-contract: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}

"$WEAVEC" capabilities --json > "$TMP/capabilities.json"

python3 - "$SCHEMA" "$TMP/capabilities.json" <<'PY'
import json
import pathlib
import sys

schema = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
capabilities = json.loads(pathlib.Path(sys.argv[2]).read_text(encoding="utf-8"))

assert schema["$schema"] == "https://json-schema.org/draft/2020-12/schema"
assert schema["$id"] == "urn:weavec:schema:project-module-cache:v1"
assert schema["title"] == "weavec-project-module-cache-v1"
assert schema["properties"]["format"]["const"] == (
    "weavec-project-module-cache-v1"
)
assert set(schema["required"]) == {
    "format",
    "status",
    "cache_dir",
    "exit_code",
    "modules",
}
module = schema["$defs"]["module"]
assert module["required"] == [
    "name",
    "source",
    "interface_sha256",
    "key",
    "decision",
    "reason",
]
successful = schema["$defs"]["successful_module"]["allOf"][1]["properties"]
assert successful["decision"]["enum"] == ["rebuilt", "reused"]
assert successful["key"]["$ref"] == "#/$defs/sha256"
assert successful["interface_sha256"]["$ref"] == "#/$defs/sha256"
assert schema["additionalProperties"] is True

feature = capabilities["incremental_project_builds"]
assert feature["feature"] == {
    "id": "incremental-project-builds",
    "status": "experimental",
    "issue": 125,
}
assert feature["protocol"] == "weavec-project-module-cache-v1"
assert feature["controls"] == [
    "--clean",
    "--no-cache",
    "--cache-dir <path>",
    "--cache-report <path>",
]
assert feature["default_cache"] == "<project-root>/.weave/cache"
assert feature["validation"] == "full-project-before-cache"
assert feature["invalidation"] == "source-and-import-interface-hashes"
assert feature["physical_paths_in_keys"] is False

print("project-cache-contract: schema and capabilities passed")
PY
