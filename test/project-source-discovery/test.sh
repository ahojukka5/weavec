#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP_RAW="$(mktemp -d "${TMPDIR:-/tmp}/weavec-project-sources-XXXXXX")"
TMP="$(cd "$TMP_RAW" && pwd -P)"
trap 'chmod -R u+rwX "$TMP" 2>/dev/null || true; rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'project-source-discovery: compiler not found: %s\n' "$WEAVEC" >&2
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
    printf 'project-source-discovery: expected exit %s, got %s: %s\n' \
      "$expected" "$actual" "$*" >&2
    exit 1
  fi
}

write_manifest() {
  local project="$1"
  mkdir -p "$project/src" "$project/lib" "$project/test"
  cat > "$project/weave.project" <<'EOF_PROJECT'
(weave-project
  (format 1)
  (name discovery)
  (kind executable)
  (source-roots "src" "lib")
  (test-roots "test")
  (entry application)
  (output "discovery"))
EOF_PROJECT
}

write_module() {
  local path="$1"
  local module="$2"
  mkdir -p "$(dirname "$path")"
  cat > "$path" <<EOF_MODULE
(module $module
  (export value)
  (const value i32 1))
EOF_MODULE
}

populate_first_order() {
  local project="$1"
  write_manifest "$project"
  write_module "$project/src/zeta.weave" zeta
  write_module "$project/lib/gamma.weave" gamma
  write_module "$project/src/nested/alpha.weave" alpha
  write_module "$project/src/generated/beta.weave" beta
  printf 'not a Weave source\n' > "$project/src/README.txt"
  write_module "$project/src/.hidden.weave" hidden
  mkdir -p "$project/src/.cache"
  write_module "$project/src/.cache/cached.weave" cached
}

populate_second_order() {
  local project="$1"
  write_manifest "$project"
  mkdir -p "$project/src/.cache"
  write_module "$project/src/.cache/cached.weave" cached
  write_module "$project/src/generated/beta.weave" beta
  write_module "$project/src/nested/alpha.weave" alpha
  write_module "$project/lib/gamma.weave" gamma
  write_module "$project/src/zeta.weave" zeta
  write_module "$project/src/.hidden.weave" hidden
  printf 'not a Weave source\n' > "$project/src/README.txt"
}

FIRST="$TMP/first"
SECOND="$TMP/relocated/second"
populate_first_order "$FIRST"
populate_second_order "$SECOND"

cat > "$TMP/expected.tsv" <<'EOF_EXPECTED'
gamma	lib/gamma.weave
beta	src/generated/beta.weave
alpha	src/nested/alpha.weave
zeta	src/zeta.weave
EOF_EXPECTED

expect_exit 2 env WEAVEC_INTERNAL_PROJECT_SOURCES="$TMP/first.tsv" \
  "$WEAVEC" build --project "$FIRST" >"$TMP/first.out" 2>"$TMP/first.err"
expect_exit 2 env WEAVEC_INTERNAL_PROJECT_SOURCES="$TMP/second.tsv" \
  "$WEAVEC" build --project "$SECOND" >"$TMP/second.out" 2>"$TMP/second.err"
cmp "$TMP/expected.tsv" "$TMP/first.tsv"
cmp "$TMP/expected.tsv" "$TMP/second.tsv"
grep -F 'project.graph.pending' "$TMP/first.err"
grep -F 'discovered 4 project modules' "$TMP/first.err"
if grep -E 'hidden|cached|README' "$TMP/first.tsv" >/dev/null; then
  printf 'project-source-discovery: ignored entry entered source registry\n' >&2
  exit 1
fi

# Duplicate compiler-declared module identities point at the later logical path.
DUPLICATE="$TMP/duplicate"
write_manifest "$DUPLICATE"
write_module "$DUPLICATE/lib/first.weave" shared
write_module "$DUPLICATE/src/second.weave" shared
expect_exit 15 "$WEAVEC" build --project "$DUPLICATE" \
  --diagnostics-json "$TMP/duplicate.json" \
  >"$TMP/duplicate.out" 2>"$TMP/duplicate.err"
grep -F 'project.source.duplicate-module' "$TMP/duplicate.err"
grep -F 'src/second.weave' "$TMP/duplicate.err"
python3 - "$TMP/duplicate.json" <<'PY'
import json
import pathlib
import sys

document = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
assert document["format"] == "weavec-diagnostics-v1"
assert document["exit_code"] == 15
item = document["diagnostics"][0]
assert item["code"] == "project.source.duplicate-module"
assert item["source"] == "src/second.weave"
assert item["span"] is not None
assert item["span"]["end_byte"] > item["span"]["start_byte"]
PY

# Project mode admits explicit module roots only.
LEGACY="$TMP/legacy"
write_manifest "$LEGACY"
cat > "$LEGACY/src/legacy.weave" <<'EOF_LEGACY'
(program
  (name "legacy")
  (version "0.1"))
EOF_LEGACY
expect_exit 2 "$WEAVEC" build --project "$LEGACY" \
  >"$TMP/legacy.out" 2>"$TMP/legacy.err"
grep -F 'project.source.legacy-root' "$TMP/legacy.err"

MISSING_ROOT="$TMP/missing-root"
write_manifest "$MISSING_ROOT"
cat > "$MISSING_ROOT/src/not-module.weave" <<'EOF_NOT_MODULE'
(arbitrary root)
EOF_NOT_MODULE
expect_exit 2 "$WEAVEC" build --project "$MISSING_ROOT" \
  >"$TMP/missing-root.out" 2>"$TMP/missing-root.err"
grep -F 'project.source.module-root' "$TMP/missing-root.err"

EMPTY="$TMP/empty"
write_manifest "$EMPTY"
printf 'ignored\n' > "$EMPTY/src/notes.md"
expect_exit 2 "$WEAVEC" build --project "$EMPTY" \
  >"$TMP/empty.out" 2>"$TMP/empty.err"
grep -F 'project.source.empty' "$TMP/empty.err"

# Requested outputs may not overwrite discovered sources.
ALIAS="$TMP/alias"
write_manifest "$ALIAS"
write_module "$ALIAS/src/application.weave" application
cp "$ALIAS/src/application.weave" "$TMP/application.before"
expect_exit 2 "$WEAVEC" build --project "$ALIAS" \
  -o "$ALIAS/src/application.weave" \
  >"$TMP/alias.out" 2>"$TMP/alias.err"
grep -F 'driver.output-aliases-project-source' "$TMP/alias.err"
cmp "$TMP/application.before" "$ALIAS/src/application.weave"

# Symlinks are rejected rather than followed, including links that stay in-tree.
SYMLINK="$TMP/symlink"
write_manifest "$SYMLINK"
write_module "$SYMLINK/src/application.weave" application
if ln -s application.weave "$SYMLINK/src/linked.weave" 2>/dev/null; then
  expect_exit 2 "$WEAVEC" build --project "$SYMLINK" \
    >"$TMP/symlink.out" 2>"$TMP/symlink.err"
  grep -F 'project.source.symlink' "$TMP/symlink.err"
  grep -F 'src/linked.weave' "$TMP/symlink.err"
fi

# Unreadable admitted files fail deterministically where permissions are honored.
UNREADABLE="$TMP/unreadable"
write_manifest "$UNREADABLE"
write_module "$UNREADABLE/src/application.weave" application
chmod 000 "$UNREADABLE/src/application.weave"
if [[ ! -r "$UNREADABLE/src/application.weave" ]]; then
  expect_exit 2 "$WEAVEC" build --project "$UNREADABLE" \
    >"$TMP/unreadable.out" 2>"$TMP/unreadable.err"
  grep -F 'project.source.read' "$TMP/unreadable.err"
fi
chmod 600 "$UNREADABLE/src/application.weave"

printf 'project-source-discovery: deterministic module registry passed\n'
