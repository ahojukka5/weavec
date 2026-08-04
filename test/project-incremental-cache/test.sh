#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP_RAW="$(mktemp -d "${TMPDIR:-/tmp}/weavec-project-cache-XXXXXX")"
TMP="$(cd "$TMP_RAW" && pwd -P)"
trap 'chmod -R u+rwX "$TMP" 2>/dev/null || true; rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'project-cache: compiler not found: %s\n' "$WEAVEC" >&2
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
    printf 'project-cache: expected exit %s, got %s: %s\n' \
      "$expected" "$actual" "$*" >&2
    exit 1
  fi
}

write_project() {
  local project="$1"
  local expression="$2"
  mkdir -p "$project/src" "$project/test"
  cat > "$project/weave.project" <<'EOF_PROJECT'
(weave-project
  (format 1)
  (name incremental)
  (kind executable)
  (source-roots "src")
  (test-roots "test")
  (entry application)
  (output "incremental"))
EOF_PROJECT
  cat > "$project/src/application.weave" <<'EOF_SOURCE'
(module application
  (import arithmetic (answer))
  (entry main
    (params)
    (returns i32)
    (do (return (call answer)))))
EOF_SOURCE
  cat > "$project/src/arithmetic.weave" <<EOF_SOURCE
(module arithmetic
  (export answer)
  (fn answer
    (params)
    (returns i32)
    (do (return $expression))))
EOF_SOURCE
}

assert_report() {
  local path="$1"
  local expected="$2"
  python3 - "$path" "$expected" <<'PY'
import json
import pathlib
import sys

document = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
assert document["format"] == "weavec-project-cache-v1"
assert document["status"] == sys.argv[2], document
assert document["exit_code"] == 0
assert len(document["key"]) == 64
assert document["cache_dir"].endswith("/weavec-project-cache-v1")
PY
}

FIRST="$TMP/first"
SECOND="$TMP/relocated/second"
CACHE="$TMP/shared-cache"
write_project "$FIRST" 42

expect_exit 0 "$WEAVEC" build --project "$FIRST" \
  --cache-dir "$CACHE" --cache-report "$TMP/miss.json"
assert_report "$TMP/miss.json" miss
expect_exit 42 "$FIRST/incremental"
cp "$FIRST/incremental" "$TMP/first-artifact"

rm "$FIRST/incremental"
expect_exit 0 "$WEAVEC" build --project "$FIRST" \
  --cache-dir "$CACHE" --cache-report "$TMP/hit.json"
assert_report "$TMP/hit.json" hit
cmp "$TMP/first-artifact" "$FIRST/incremental"
expect_exit 42 "$FIRST/incremental"

mkdir -p "$(dirname "$SECOND")"
cp -R "$FIRST" "$SECOND"
rm -f "$SECOND/incremental"
expect_exit 0 "$WEAVEC" build --project "$SECOND" \
  --cache-dir "$CACHE" --cache-report "$TMP/relocated.json"
assert_report "$TMP/relocated.json" hit
cmp "$TMP/first-artifact" "$SECOND/incremental"
expect_exit 42 "$SECOND/incremental"

write_project "$FIRST" 41
rm -f "$FIRST/incremental"
expect_exit 0 "$WEAVEC" build --project "$FIRST" \
  --cache-dir "$CACHE" --cache-report "$TMP/changed.json"
assert_report "$TMP/changed.json" miss
expect_exit 41 "$FIRST/incremental"

python3 - "$TMP/changed.json" <<'PY'
import json
import pathlib
import sys

report = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
artifact = pathlib.Path(report["cache_dir"]) / report["key"] / "artifact"
artifact.write_bytes(b"corrupt")
PY
rm -f "$FIRST/incremental"
expect_exit 0 "$WEAVEC" build --project "$FIRST" \
  --cache-dir "$CACHE" --cache-report "$TMP/corrupt.json"
assert_report "$TMP/corrupt.json" miss
expect_exit 41 "$FIRST/incremental"

rm -f "$FIRST/incremental"
expect_exit 0 "$WEAVEC" build --project "$FIRST" \
  --cache-dir "$CACHE" --clean --cache-report "$TMP/clean.json"
assert_report "$TMP/clean.json" miss
expect_exit 41 "$FIRST/incremental"

rm -f "$FIRST/incremental"
expect_exit 0 "$WEAVEC" build --project "$FIRST" \
  --cache-dir "$CACHE" --no-cache --cache-report "$TMP/disabled.json"
assert_report "$TMP/disabled.json" disabled
expect_exit 41 "$FIRST/incremental"

cp "$FIRST/src/arithmetic.weave" "$TMP/arithmetic.before"
expect_exit 2 "$WEAVEC" build --project "$FIRST" \
  --cache-dir "$CACHE" \
  --cache-report "$FIRST/src/arithmetic.weave" \
  >"$TMP/alias.out" 2>"$TMP/alias.err"
grep -F 'cache report aliases a project input or output' "$TMP/alias.err"
cmp "$TMP/arithmetic.before" "$FIRST/src/arithmetic.weave"

"$WEAVEC" build --help >"$TMP/help.txt"
grep -F -- '--no-cache' "$TMP/help.txt"
grep -F -- '--cache-report' "$TMP/help.txt"

printf 'project-cache: all checks passed\n'
