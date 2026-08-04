#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP_RAW="$(mktemp -d "${TMPDIR:-/tmp}/weavec-project-protocols-XXXXXX")"
TMP="$(cd "$TMP_RAW" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'project-protocols: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}

expect_exit() {
  local expected="$1"
  shift
  set +e
  "$@"
  local actual=$?
  set -e
  if [[ "$actual" -ne "$expected" ]]; then
    printf 'project-protocols: expected exit %s, got %s: %s\n' \
      "$expected" "$actual" "$*" >&2
    exit 1
  fi
}

write_project() {
  local project="$1"
  mkdir -p "$project/src" "$project/test"
  cat > "$project/weave.project" <<'EOF_PROJECT'
(weave-project
  (format 1)
  (name protocol-demo)
  (kind executable)
  (source-roots "src")
  (test-roots "test")
  (entry application)
  (output "protocol-demo"))
EOF_PROJECT
  cat > "$project/src/records.weave" <<'EOF_RECORDS'
(module records
  (export Record make-record)

  (struct Record
    (field value i32))

  (fn make-record
    (params (value i32))
    (returns Record)
    (do
      (return (new Record (value value))))))
EOF_RECORDS
  cat > "$project/src/application.weave" <<'EOF_APPLICATION'
(module application
  (import records (Record make-record))

  (fn identity
    (params (record Record))
    (returns Record)
    (do
      (return record)))

  (entry main
    (params)
    (returns i32)
    (do
      (let record Record (call make-record 42))
      (let copy Record (call identity record))
      (return (field-get copy value)))))
EOF_APPLICATION
}

FIRST="$TMP/first"
SECOND="$TMP/relocated/second"
write_project "$FIRST"
write_project "$SECOND"

build_project() {
  local project="$1"
  local prefix="$2"
  expect_exit 0 "$WEAVEC" build --project "$project" \
    --manifest-json "$prefix.manifest.json" \
    --diagnostics-json "$prefix.diagnostics.json" \
    --trace-json "$prefix.trace.json" \
    --emit-wir "$prefix.wir"
  expect_exit 42 "$project/protocol-demo"
  expect_exit 0 "$WEAVEC" analyze --project "$project" \
    --semantic-index-json "$prefix.index.json"
}

build_project "$FIRST" "$TMP/first"
build_project "$SECOND" "$TMP/second"

expect_exit 0 "$WEAVEC" capabilities --json > "$TMP/capabilities.json"

python3 - \
  "$TMP/first" \
  "$TMP/second" \
  "$FIRST" \
  "$SECOND" \
  "$TMP/capabilities.json" <<'PY'
import copy
import json
import pathlib
import sys

first_prefix = pathlib.Path(sys.argv[1])
second_prefix = pathlib.Path(sys.argv[2])
first_root = pathlib.Path(sys.argv[3]).resolve()
second_root = pathlib.Path(sys.argv[4]).resolve()
capabilities_path = pathlib.Path(sys.argv[5])


def load(prefix: pathlib.Path, suffix: str):
    return json.loads(
        pathlib.Path(f"{prefix}.{suffix}.json").read_text(encoding="utf-8")
    )


def assert_project(project):
    assert project["format"] == "weavec-project-facts-v1"
    assert project["complete"] is True
    assert project["resolution_phase"] == "complete"
    assert project["name"] == "protocol-demo"
    assert project["kind"] == "executable"
    assert project["manifest"]["logical_path"] == "weave.project"
    assert pathlib.Path(project["manifest"]["physical_path"]).is_absolute()
    assert pathlib.Path(project["root"]["physical_path"]).is_absolute()
    assert project["source_roots"] == ["src"]
    assert project["test_roots"] == ["test"]
    assert project["entry_module"] == "application"
    assert project["output"] == "protocol-demo"
    assert [item["module"] for item in project["sources"]] == [
        "application",
        "records",
    ]
    assert [item["logical_path"] for item in project["sources"]] == [
        "src/application.weave",
        "src/records.weave",
    ]
    assert project["module_order"] == ["records", "application"]
    graph = {item["module"]: item for item in project["module_graph"]}
    assert graph["records"]["imports"] == []
    assert graph["application"]["imports"] == ["records"]


def normalize(value, root: pathlib.Path):
    root_text = str(root)
    if isinstance(value, dict):
        result = {}
        for key, item in value.items():
            if key == "selection":
                result[key] = None
            elif key == "resolved_output":
                result[key] = "<project-output>" if item is not None else None
            else:
                result[key] = normalize(item, root)
        return result
    if isinstance(value, list):
        return [normalize(item, root) for item in value]
    if isinstance(value, str):
        return value.replace(root_text, "<project-root>")
    return value


for prefix in (first_prefix, second_prefix):
    manifest = load(prefix, "manifest")
    diagnostics = load(prefix, "diagnostics")
    trace = load(prefix, "trace")
    index = load(prefix, "index")

    assert manifest["format"] == "weavec-build-manifest-v1"
    assert manifest["status"] == "succeeded"
    assert_project(manifest["project"])

    assert diagnostics["format"] == "weavec-diagnostics-v1"
    assert diagnostics["status"] == "succeeded"
    assert diagnostics["phase"] == "complete"
    assert diagnostics["diagnostics"] == []
    assert_project(diagnostics["project"])

    assert trace["format"] == "weavec-compilation-trace-v1"
    assert trace["status"] == "succeeded"
    assert_project(trace["project"])

    assert index["format"] == "weavec-semantic-index-v1"
    assert index["analysis"]["complete"] is True
    assert_project(index["project"])
    assert [source["path"] for source in index["sources"]] == [
        "src/records.weave",
        "src/application.weave",
    ]
    modules = {module["name"]: module for module in index["modules"]}
    records = modules["records"]
    exported = set(records["interface"]["exports"])
    symbols = {symbol["id"]: symbol for symbol in index["symbols"]}
    public_structs = [
        symbol
        for symbol in symbols.values()
        if symbol["kind"] == "struct"
        and symbol["name"] == "Record"
        and symbol["visibility"] == "public"
    ]
    assert len(public_structs) == 1
    assert public_structs[0]["id"] in exported

first_documents = {
    suffix: load(first_prefix, suffix)
    for suffix in ("manifest", "diagnostics", "trace", "index")
}
second_documents = {
    suffix: load(second_prefix, suffix)
    for suffix in ("manifest", "diagnostics", "trace", "index")
}
for suffix in first_documents:
    first = normalize(copy.deepcopy(first_documents[suffix]), first_root)
    second = normalize(copy.deepcopy(second_documents[suffix]), second_root)
    assert first == second, suffix

capabilities = json.loads(capabilities_path.read_text(encoding="utf-8"))
mode = capabilities["project_mode"]
assert mode["feature"] == {
    "id": "project-builds",
    "status": "experimental",
    "issue": 123,
}
assert mode["protocol"]["id"] == "weavec-project-facts-v1"
assert mode["protocol"]["field"] == "project"
assert "weavec-semantic-index-v1" in mode["protocol"]["extends"]
assert mode["manifest"]["name"] == "weave.project"
assert mode["manifest"]["version"] == 1
PY

# Graph failures publish project phases and partial project facts, not products.
MISSING="$TMP/missing"
write_project "$MISSING"
sed -i.bak 's/(import records /(import absent /' \
  "$MISSING/src/application.weave"
rm -f "$MISSING/src/application.weave.bak"
expect_exit 15 "$WEAVEC" build --project "$MISSING" \
  --diagnostics-json "$TMP/missing.diagnostics.json" \
  --trace-json "$TMP/missing.trace.json" \
  --manifest-json "$TMP/missing.manifest.json" \
  --emit-wir "$TMP/missing.wir" \
  >"$TMP/missing.out" 2>"$TMP/missing.err"
grep -F 'project.graph.missing-module' "$TMP/missing.err"
[[ ! -e "$MISSING/protocol-demo" ]]
[[ ! -e "$TMP/missing.wir" ]]
[[ ! -e "$TMP/missing.manifest.json" ]]

python3 - \
  "$TMP/missing.diagnostics.json" \
  "$TMP/missing.trace.json" <<'PY'
import json
import pathlib
import sys

diagnostics = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
trace = json.loads(pathlib.Path(sys.argv[2]).read_text(encoding="utf-8"))
assert diagnostics["phase"] == "project-graph"
assert diagnostics["diagnostics"][0]["phase"] == "project-graph"
assert diagnostics["diagnostics"][0]["code"] == "project.graph.missing-module"
assert diagnostics["diagnostics"][0]["source"] == "src/application.weave"
assert diagnostics["project"]["complete"] is False
assert diagnostics["project"]["resolution_phase"] == "project-graph"
assert diagnostics["project"]["module_order"] == []
assert trace["phase"] == "project-graph"
assert trace["project"]["resolution_phase"] == "project-graph"
PY

# Source and manifest failures use their own stable protocol phases.
DUPLICATE="$TMP/duplicate"
write_project "$DUPLICATE"
cat > "$DUPLICATE/src/duplicate.weave" <<'EOF_DUPLICATE'
(module records
  (const duplicate i32 1))
EOF_DUPLICATE
expect_exit 15 "$WEAVEC" build --project "$DUPLICATE" \
  --diagnostics-json "$TMP/duplicate.diagnostics.json" \
  --trace-json "$TMP/duplicate.trace.json" \
  >"$TMP/duplicate.out" 2>"$TMP/duplicate.err"

MALFORMED="$TMP/malformed"
mkdir -p "$MALFORMED"
cat > "$MALFORMED/weave.project" <<'EOF_MALFORMED'
(weave-project
  (format 1)
  (name malformed)
EOF_MALFORMED
expect_exit 15 "$WEAVEC" build --project "$MALFORMED" \
  --diagnostics-json "$TMP/malformed.diagnostics.json" \
  --trace-json "$TMP/malformed.trace.json" \
  >"$TMP/malformed.out" 2>"$TMP/malformed.err"

python3 - \
  "$TMP/duplicate.diagnostics.json" \
  "$TMP/duplicate.trace.json" \
  "$TMP/malformed.diagnostics.json" \
  "$TMP/malformed.trace.json" <<'PY'
import json
import pathlib
import sys

duplicate_diagnostics = json.loads(pathlib.Path(sys.argv[1]).read_text())
duplicate_trace = json.loads(pathlib.Path(sys.argv[2]).read_text())
malformed_diagnostics = json.loads(pathlib.Path(sys.argv[3]).read_text())
malformed_trace = json.loads(pathlib.Path(sys.argv[4]).read_text())

assert duplicate_diagnostics["phase"] == "project-sources"
assert duplicate_diagnostics["diagnostics"][0]["phase"] == "project-sources"
assert duplicate_diagnostics["project"]["resolution_phase"] == "project-sources"
assert duplicate_trace["phase"] == "project-sources"

assert malformed_diagnostics["phase"] == "project-manifest"
assert malformed_diagnostics["diagnostics"][0]["phase"] == "project-manifest"
assert (
    malformed_diagnostics["project"]["resolution_phase"]
    == "project-manifest"
)
assert malformed_diagnostics["project"]["manifest"] is None
assert malformed_trace["phase"] == "project-manifest"
PY

printf 'project-protocols: public project facts and failures passed\n'
