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

write_manifest() {
  local project="$1"
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
}

write_application() {
  local project="$1"
  cat > "$project/src/application.weave" <<'EOF_SOURCE'
(module application
  (import arithmetic (answer))
  (entry main
    (params)
    (returns i32)
    (do (return (call answer)))))
EOF_SOURCE
}

write_arithmetic() {
  local project="$1"
  local exports="$2"
  local extra="$3"
  cat > "$project/src/arithmetic.weave" <<EOF_SOURCE
(module arithmetic
  (import constants (base))
  (export $exports)
  (fn answer
    (params)
    (returns i32)
    (do (return (call base))))
$extra)
EOF_SOURCE
}

write_constants() {
  local project="$1"
  local value="$2"
  local exports="$3"
  local extra="$4"
  cat > "$project/src/constants.weave" <<EOF_SOURCE
(module constants
  (export $exports)
  (fn base
    (params)
    (returns i32)
    (do (return $value)))
$extra)
EOF_SOURCE
}

write_unrelated() {
  local project="$1"
  cat > "$project/src/unrelated.weave" <<'EOF_SOURCE'
(module unrelated
  (export marker)
  (fn marker
    (params)
    (returns i32)
    (do (return 7))))
EOF_SOURCE
}

write_project() {
  local project="$1"
  local value="$2"
  write_manifest "$project"
  write_application "$project"
  write_arithmetic "$project" answer ""
  write_constants "$project" "$value" base ""
  write_unrelated "$project"
}

assert_report() {
  local path="$1"
  local expectations="$2"
  python3 - "$path" "$expectations" <<'PY'
import json
import pathlib
import sys

document = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
assert document["format"] == "weavec-project-module-cache-v1", document
assert document["status"] == "succeeded", document
assert document["exit_code"] == 0, document
assert document["cache_dir"].endswith(
    "/weavec-project-cache-v1/modules"
), document
modules = {item["name"]: item for item in document["modules"]}
assert set(modules) == {"application", "arithmetic", "constants", "unrelated"}
for item in modules.values():
    assert len(item["key"]) == 64
    assert len(item["interface_sha256"]) == 64
for pair in sys.argv[2].split(","):
    name, expected = pair.split("=", 1)
    assert modules[name]["decision"] == expected, (name, modules[name], document)
PY
}

module_key() {
  local report="$1"
  local module="$2"
  python3 - "$report" "$module" <<'PY'
import json
import pathlib
import sys

document = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
for item in document["modules"]:
    if item["name"] == sys.argv[2]:
        print(item["key"])
        break
else:
    raise SystemExit(f"missing module {sys.argv[2]}")
PY
}

FIRST="$TMP/first"
SECOND="$TMP/relocated/second"
CACHE="$TMP/shared-cache"
write_project "$FIRST" 42

expect_exit 0 "$WEAVEC" build --project "$FIRST" \
  --cache-dir "$CACHE" --cache-report "$TMP/first.json"
assert_report "$TMP/first.json" \
  'application=rebuilt,arithmetic=rebuilt,constants=rebuilt,unrelated=rebuilt'
expect_exit 42 "$FIRST/incremental"
cp "$FIRST/incremental" "$TMP/first-artifact"

rm "$FIRST/incremental"
expect_exit 0 "$WEAVEC" build --project "$FIRST" \
  --cache-dir "$CACHE" --cache-report "$TMP/hit.json"
assert_report "$TMP/hit.json" \
  'application=reused,arithmetic=reused,constants=reused,unrelated=reused'
cmp "$TMP/first-artifact" "$FIRST/incremental"
expect_exit 42 "$FIRST/incremental"

mkdir -p "$(dirname "$SECOND")"
cp -R "$FIRST" "$SECOND"
rm -f "$SECOND/incremental"
expect_exit 0 "$WEAVEC" build --project "$SECOND" \
  --cache-dir "$CACHE" --cache-report "$TMP/relocated.json"
assert_report "$TMP/relocated.json" \
  'application=reused,arithmetic=reused,constants=reused,unrelated=reused'
cmp "$TMP/first-artifact" "$SECOND/incremental"
expect_exit 42 "$SECOND/incremental"

# A private implementation change rebuilds only its owning module. Both direct
# and transitive callers reuse objects because the public interface is unchanged.
write_constants "$FIRST" 41 base ""
rm -f "$FIRST/incremental"
expect_exit 0 "$WEAVEC" build --project "$FIRST" \
  --cache-dir "$CACHE" --cache-report "$TMP/private.json"
assert_report "$TMP/private.json" \
  'application=reused,arithmetic=reused,constants=rebuilt,unrelated=reused'
expect_exit 41 "$FIRST/incremental"
cp "$FIRST/incremental" "$TMP/private-artifact"

# Changing a dependency interface rebuilds that module and its direct importer,
# but a transitive importer whose required interface is unchanged remains reusable.
write_constants "$FIRST" 41 'base extra-base' \
  '  (fn extra-base (params) (returns i32) (do (return 5)))'
rm -f "$FIRST/incremental"
expect_exit 0 "$WEAVEC" build --project "$FIRST" \
  --cache-dir "$CACHE" --cache-report "$TMP/dependency-interface.json"
assert_report "$TMP/dependency-interface.json" \
  'application=reused,arithmetic=rebuilt,constants=rebuilt,unrelated=reused'
expect_exit 41 "$FIRST/incremental"

# Changing the arithmetic public interface invalidates the entry module that
# imports it, while the unrelated module remains reusable.
write_arithmetic "$FIRST" 'answer extra-answer' \
  '  (fn extra-answer (params) (returns i32) (do (return 9)))'
rm -f "$FIRST/incremental"
expect_exit 0 "$WEAVEC" build --project "$FIRST" \
  --cache-dir "$CACHE" --cache-report "$TMP/public-interface.json"
assert_report "$TMP/public-interface.json" \
  'application=rebuilt,arithmetic=rebuilt,constants=reused,unrelated=reused'
expect_exit 41 "$FIRST/incremental"

# A corrupt object is rejected and rebuilt without invalidating valid neighbors.
arithmetic_key="$(module_key "$TMP/public-interface.json" arithmetic)"
printf 'corrupt' > \
  "$CACHE/weavec-project-cache-v1/modules/$arithmetic_key/artifact"
rm -f "$FIRST/incremental"
expect_exit 0 "$WEAVEC" build --project "$FIRST" \
  --cache-dir "$CACHE" --cache-report "$TMP/corrupt.json"
assert_report "$TMP/corrupt.json" \
  'application=reused,arithmetic=rebuilt,constants=reused,unrelated=reused'
expect_exit 41 "$FIRST/incremental"

# A different optimization profile has a distinct object key.
rm -f "$FIRST/incremental"
expect_exit 0 "$WEAVEC" build --project "$FIRST" -O0 \
  --cache-dir "$CACHE" --cache-report "$TMP/profile.json"
assert_report "$TMP/profile.json" \
  'application=rebuilt,arithmetic=rebuilt,constants=rebuilt,unrelated=rebuilt'
expect_exit 41 "$FIRST/incremental"
rm -f "$FIRST/incremental"
expect_exit 0 "$WEAVEC" build --project "$FIRST" -O0 \
  --cache-dir "$CACHE" --cache-report "$TMP/profile-hit.json"
assert_report "$TMP/profile-hit.json" \
  'application=reused,arithmetic=reused,constants=reused,unrelated=reused'
expect_exit 41 "$FIRST/incremental"

# Clean and incremental builds publish byte-identical executables.
cp "$FIRST/incremental" "$TMP/incremental-artifact"
rm -f "$FIRST/incremental"
expect_exit 0 "$WEAVEC" build --project "$FIRST" -O0 \
  --cache-dir "$CACHE" --clean --cache-report "$TMP/clean.json"
assert_report "$TMP/clean.json" \
  'application=rebuilt,arithmetic=rebuilt,constants=rebuilt,unrelated=rebuilt'
cmp "$TMP/incremental-artifact" "$FIRST/incremental"
expect_exit 41 "$FIRST/incremental"

rm -f "$FIRST/incremental"
expect_exit 0 "$WEAVEC" build --project "$FIRST" -O0 \
  --cache-dir "$CACHE" --no-cache --cache-report "$TMP/disabled.json"
assert_report "$TMP/disabled.json" \
  'application=rebuilt,arithmetic=rebuilt,constants=rebuilt,unrelated=rebuilt'
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
