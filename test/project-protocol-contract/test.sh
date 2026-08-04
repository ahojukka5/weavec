#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROJECT_SCHEMA="$ROOT/docs/schemas/weavec-project-facts-v1.schema.json"
DIAGNOSTICS_SCHEMA="$ROOT/docs/schemas/weavec-diagnostics-v1.schema.json"
SEMANTIC_SCHEMA="$ROOT/docs/schemas/weavec-semantic-index-v1.schema.json"
CAPABILITIES_SCHEMA="$ROOT/docs/schemas/weavec-capabilities-v1.schema.json"

python3 - \
  "$PROJECT_SCHEMA" \
  "$DIAGNOSTICS_SCHEMA" \
  "$SEMANTIC_SCHEMA" \
  "$CAPABILITIES_SCHEMA" <<'PY'
import json
import pathlib
import sys

project_path, diagnostics_path, semantic_path, capabilities_path = map(
    pathlib.Path, sys.argv[1:]
)
project = json.loads(project_path.read_text(encoding="utf-8"))
diagnostics = json.loads(diagnostics_path.read_text(encoding="utf-8"))
semantic = json.loads(semantic_path.read_text(encoding="utf-8"))
capabilities = json.loads(capabilities_path.read_text(encoding="utf-8"))

assert project["$schema"] == "https://json-schema.org/draft/2020-12/schema"
assert project["$id"] == "urn:weavec:schema:project-facts:v1"
assert project["title"] == "weavec-project-facts-v1"
assert project["properties"]["format"]["const"] == "weavec-project-facts-v1"

required = set(project["required"])
assert required == {
    "format",
    "complete",
    "resolution_phase",
    "selection",
    "name",
    "kind",
    "manifest",
    "root",
    "source_roots",
    "test_roots",
    "entry_module",
    "output",
    "resolved_output",
    "sources",
    "module_order",
    "module_graph",
}
assert set(project["properties"]["resolution_phase"]["enum"]) == {
    "project-manifest",
    "project-sources",
    "project-graph",
    "complete",
}
assert project["$defs"]["manifest"]["properties"]["logical_path"] == {
    "const": "weave.project"
}
assert project["$defs"]["source"]["required"] == [
    "module",
    "logical_path",
    "physical_path",
]
assert project["$defs"]["module"]["required"] == [
    "module",
    "source",
    "imports",
]

# Version-one host documents are explicitly extension-tolerant, so adding the
# project field does not invalidate existing consumers or require a host-format
# version bump.
assert diagnostics["additionalProperties"] is True
assert semantic["additionalProperties"] is True
assert capabilities["additionalProperties"] is True

print("project-protocol-contract: schema and additive hosts passed")
PY
