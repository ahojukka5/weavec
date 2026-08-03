#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-project-discovery-XXXXXX")"
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'project-discovery: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}

write_project() {
  local path="$1"
  local name="$2"
  local output="$3"
  mkdir -p "$path/src" "$path/test"
  cat > "$path/weave.project" <<EOF_PROJECT
(weave-project
  (format 1)
  (name $name)
  (kind executable)
  (source-roots "src")
  (test-roots "test")
  (entry application)
  (output "$output"))
EOF_PROJECT
  cat > "$path/src/application.weave" <<'EOF_SOURCE'
(module application
  (entry main
    (params)
    (returns i32)
    (do (return 0))))
EOF_SOURCE
}

expect_exit() {
  local expected="$1"
  shift
  set +e
  "$@"
  local actual=$?
  set -e
  if [[ "$actual" -ne "$expected" ]]; then
    printf 'project-discovery: expected exit %s, got %s: %s\n' \
      "$expected" "$actual" "$*" >&2
    exit 1
  fi
}

PARENT="$TMP/parent"
CHILD="$PARENT/child"
NESTED="$CHILD/nested"
write_project "$PARENT" parent-app parent-bin
write_project "$CHILD" child-app child-bin
mkdir -p "$NESTED"

# The nearest manifest wins and its default output is anchored at its directory.
expect_exit 2 bash -c \
  'cd "$1" && "$2" build >"$3" 2>"$4"' \
  _ "$NESTED" "$WEAVEC" "$TMP/nearest.out" "$TMP/nearest.err"
grep -F 'project.graph.pending' "$TMP/nearest.err"
grep -F 'discovered 1 project modules' "$TMP/nearest.err"
grep -F "$CHILD/child-bin" "$TMP/nearest.err"
if grep -F "$PARENT/parent-bin" "$TMP/nearest.err" >/dev/null; then
  printf 'project-discovery: skipped the nearer manifest\n' >&2
  exit 1
fi

# Explicit project directory and explicit manifest file are cwd-independent.
expect_exit 2 bash -c \
  'cd "$1" && "$2" build --project "$3" >"$4" 2>"$5"' \
  _ "$TMP" "$WEAVEC" "$CHILD" "$TMP/explicit-dir.out" "$TMP/explicit-dir.err"
grep -F 'project.graph.pending' "$TMP/explicit-dir.err"
grep -F "$CHILD/child-bin" "$TMP/explicit-dir.err"

expect_exit 2 bash -c \
  'cd "$1" && "$2" build --project "$3" -o custom-bin >"$4" 2>"$5"' \
  _ "$TMP" "$WEAVEC" "$CHILD/weave.project" \
  "$TMP/explicit-file.out" "$TMP/explicit-file.err"
grep -F 'project.graph.pending' "$TMP/explicit-file.err"
grep -F 'output custom-bin' "$TMP/explicit-file.err"

# An invalid nearer manifest is authoritative and must not fall back to a parent.
cat > "$CHILD/weave.project" <<'EOF_INVALID'
(weave-project
  (format 1)
  (name child-app)
  (kind executable)
  (source-roots "src")
  (entry application)
  (mystery true))
EOF_INVALID
expect_exit 2 bash -c \
  'cd "$1" && "$2" build >"$3" 2>"$4"' \
  _ "$NESTED" "$WEAVEC" "$TMP/invalid.out" "$TMP/invalid.err"
grep -F 'project.manifest.unknown-field' "$TMP/invalid.err"
grep -F "$CHILD/weave.project" "$TMP/invalid.err"
if grep -F "$PARENT/weave.project" "$TMP/invalid.err" >/dev/null; then
  printf 'project-discovery: fell back past an invalid nearer manifest\n' >&2
  exit 1
fi

# Diagnostics use the stable driver exit and project-manifest code.
expect_exit 15 bash -c \
  'cd "$1" && "$2" build --diagnostics-json "$3" >/dev/null 2>"$4"' \
  _ "$NESTED" "$WEAVEC" "$TMP/diagnostics.json" "$TMP/diagnostics.err"
python3 - "$TMP/diagnostics.json" "$CHILD/weave.project" <<'PY'
import json
import pathlib
import sys

document = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
assert document["format"] == "weavec-diagnostics-v1"
assert document["status"] == "failed"
assert document["phase"] == "driver"
assert document["exit_code"] == 15
assert len(document["diagnostics"]) == 1
item = document["diagnostics"][0]
assert item["code"] == "project.manifest.unknown-field"
assert item["source"] == sys.argv[2]
assert item["span"] is not None
PY

# Missing discovery is deterministic and explicit source mode ignores projects.
EMPTY="$TMP/empty/a/b"
mkdir -p "$EMPTY"
expect_exit 2 bash -c \
  'cd "$1" && "$2" build >/dev/null 2>"$3"' \
  _ "$EMPTY" "$WEAVEC" "$TMP/missing.err"
grep -F 'project.manifest.read' "$TMP/missing.err"

LEGACY="$TMP/legacy"
mkdir -p "$LEGACY"
cat > "$LEGACY/weave.project" <<'EOF_BROKEN_NEARBY'
(this-is-not-a-project)
EOF_BROKEN_NEARBY
cat > "$LEGACY/main.weave" <<'EOF_SOURCE'
(program
  (name "legacy")
  (version "0.1")
  (entry main
    (params)
    (returns i32)
    (do (return 0))))
EOF_SOURCE
(
  cd "$LEGACY"
  "$WEAVEC" build main.weave -o legacy-bin
  ./legacy-bin
)

# Project selection and source-list mode are mutually exclusive.
expect_exit 2 bash -c \
  'cd "$1" && "$2" build --project . main.weave -o mixed >/dev/null 2>"$3"' \
  _ "$LEGACY" "$WEAVEC" "$TMP/mixed.err"
grep -F 'driver.ambiguous-build-mode' "$TMP/mixed.err"
[[ ! -e "$LEGACY/mixed" ]]

# No requested or default output may overwrite the selected manifest.
write_project "$CHILD" child-app child-bin
cp "$CHILD/weave.project" "$TMP/manifest.before"
expect_exit 2 "$WEAVEC" build --project "$CHILD" \
  -o "$CHILD/weave.project" >/dev/null 2>"$TMP/alias.err"
grep -F 'driver.output-aliases-project-manifest' "$TMP/alias.err"
cmp "$TMP/manifest.before" "$CHILD/weave.project"

write_project "$CHILD" child-app weave.project
cp "$CHILD/weave.project" "$TMP/default-alias.before"
expect_exit 2 "$WEAVEC" build --project "$CHILD" \
  >/dev/null 2>"$TMP/default-alias.err"
grep -F 'driver.output-aliases-project-manifest' "$TMP/default-alias.err"
cmp "$TMP/default-alias.before" "$CHILD/weave.project"

# Diagnostic or trace publication must not replace even a malformed manifest.
cat > "$CHILD/weave.project" <<'EOF_MALFORMED'
(weave-project (format 1) (mystery true))
EOF_MALFORMED
cp "$CHILD/weave.project" "$TMP/protocol-alias.before"
expect_exit 2 "$WEAVEC" build --project "$CHILD" \
  --diagnostics-json "$CHILD/weave.project" \
  >/dev/null 2>"$TMP/protocol-alias.err"
grep -F 'driver.output-aliases-project-manifest' "$TMP/protocol-alias.err"
cmp "$TMP/protocol-alias.before" "$CHILD/weave.project"

# Escaped NUL bytes cannot be truncated into apparently valid path values.
cat > "$CHILD/weave.project" <<'EOF_NUL'
(weave-project
  (format 1)
  (name child-app)
  (kind executable)
  (source-roots "src\u0000-hidden")
  (entry application))
EOF_NUL
expect_exit 2 "$WEAVEC" build --project "$CHILD" \
  >/dev/null 2>"$TMP/nul.err"
grep -F 'project.manifest.path' "$TMP/nul.err"

"$WEAVEC" build --help > "$TMP/help.txt"
grep -F -- '--project <directory-or-manifest>' "$TMP/help.txt"
grep -F 'explicit source arguments' "$TMP/help.txt"

printf 'project-discovery: precedence, diagnostics, and safety checks passed\n'
