#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-tooling-artifacts-XXXXXX")"
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'tooling-artifacts: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}

SOURCE="$ROOT/test/correctness/surface/01_return_42.weave"
RUNTIME_ARGS=()
if [[ -f "$ROOT/runtime/program.c" ]]; then
  RUNTIME_ARGS=(--runtime "$ROOT/runtime/program.c")
fi

success="$TMP/success"
mkdir -p "$success"
"$WEAVEC" build "$SOURCE" -o "$success/program" \
  "${RUNTIME_ARGS[@]}" \
  --emit-wir "$success/program.wir" \
  --emit-llvm "$success/program.ll" \
  --trace-json "$success/trace.json" \
  --diagnostics-json "$success/diagnostics.json" \
  --llvm-provenance \
  2>"$success/stderr"

[[ -s "$success/program.wir" ]]
[[ -s "$success/program.ll" ]]
grep -q '^; weave.source kind=function index=0 ' "$success/program.ll"
grep -q '^; weave.source kind=statement index=0 ' "$success/program.ll"
if grep -q '^weavec: kept temporary build directory:' "$success/stderr"; then
  echo 'tooling-artifacts: explicit LLVM output must avoid retained temporaries' >&2
  exit 1
fi
set +e
"$success/program"
status=$?
set -e
[[ "$status" -eq 42 ]]

cat > "$TMP/backend-failure.weave" <<'EOF_SOURCE'
(program
  (name "tooling-backend-failure")
  (version "0.1")
  (entry main
    (params)
    (returns i32)
    (do (return (unknown_form_i32 0)))))
EOF_SOURCE
printf 'old-wir\n' > "$TMP/backend.wir"
printf 'old-llvm\n' > "$TMP/backend.ll"
set +e
"$WEAVEC" build "$TMP/backend-failure.weave" -o "$TMP/backend-program" \
  "${RUNTIME_ARGS[@]}" \
  --emit-wir "$TMP/backend.wir" \
  --emit-llvm "$TMP/backend.ll" \
  --diagnostics-json "$TMP/backend.json" \
  >/dev/null 2>&1
status=$?
set -e
[[ "$status" -eq 11 ]]
grep -q '^(core-module' "$TMP/backend.wir"
grep -q '^  (core-version 3)' "$TMP/backend.wir"
[[ "$(cat "$TMP/backend.ll")" == 'old-llvm' ]]
[[ ! -e "$TMP/backend-program" ]]

printf 'old-wir\n' > "$TMP/frontend.wir"
cat > "$TMP/frontend-failure.weave" <<'EOF_SOURCE'
(program
  (name "tooling-frontend-failure")
EOF_SOURCE
set +e
"$WEAVEC" build "$TMP/frontend-failure.weave" -o "$TMP/frontend-program" \
  "${RUNTIME_ARGS[@]}" \
  --emit-wir "$TMP/frontend.wir" \
  --diagnostics-json "$TMP/frontend.json" \
  >/dev/null 2>&1
status=$?
set -e
[[ "$status" -eq 10 ]]
[[ "$(cat "$TMP/frontend.wir")" == 'old-wir' ]]
[[ ! -e "$TMP/frontend-program" ]]

printf 'old-llvm\n' > "$TMP/codegen.ll"
set +e
"$WEAVEC" build "$SOURCE" -o "$TMP/codegen-program" \
  "${RUNTIME_ARGS[@]}" \
  --emit-wir "$TMP/codegen.wir" \
  --emit-llvm "$TMP/codegen.ll" \
  --codegen false \
  --diagnostics-json "$TMP/codegen.json" \
  >/dev/null 2>&1
status=$?
set -e
[[ "$status" -eq 12 ]]
grep -q '^(core-module' "$TMP/codegen.wir"
grep -q '^  (core-version 3)' "$TMP/codegen.wir"
grep -q '^define i32 @main()' "$TMP/codegen.ll"
[[ ! -e "$TMP/codegen-program" ]]

set +e
"$WEAVEC" build "$SOURCE" -o "$TMP/conflict" \
  "${RUNTIME_ARGS[@]}" \
  --emit-wir "$TMP/conflict" \
  --diagnostics-json "$TMP/conflict.json" \
  >/dev/null 2>&1
status=$?
set -e
[[ "$status" -eq 2 ]]
[[ ! -e "$TMP/conflict" ]]
grep -q 'driver.conflicting-output-paths' "$TMP/conflict.json"

protected_source="$TMP/protected.weave"
cp "$SOURCE" "$protected_source"
protected_contents="$(cat "$protected_source")"
set +e
"$WEAVEC" build "$protected_source" -o "$protected_source" \
  "${RUNTIME_ARGS[@]}" \
  --diagnostics-json "$TMP/protected.json" \
  >/dev/null 2>&1
status=$?
set -e
[[ "$status" -eq 2 ]]
[[ "$(cat "$protected_source")" == "$protected_contents" ]]
grep -q 'driver.output-aliases-source' "$TMP/protected.json"

mkdir -p "$TMP/relative"
relative_source="$TMP/relative/source.weave"
cp "$SOURCE" "$relative_source"
relative_contents="$(cat "$relative_source")"
set +e
"$WEAVEC" build "$relative_source" -o "$TMP/relative/./source.weave" \
  "${RUNTIME_ARGS[@]}" \
  --diagnostics-json "$TMP/relative.json" \
  >/dev/null 2>&1
status=$?
set -e
[[ "$status" -eq 2 ]]
[[ "$(cat "$relative_source")" == "$relative_contents" ]]
grep -q 'driver.output-aliases-source' "$TMP/relative.json"

hardlink_source="$TMP/hardlink-source.weave"
hardlink_output="$TMP/hardlink-output"
cp "$SOURCE" "$hardlink_source"
ln "$hardlink_source" "$hardlink_output"
hardlink_contents="$(cat "$hardlink_source")"
set +e
"$WEAVEC" build "$hardlink_source" -o "$hardlink_output" \
  "${RUNTIME_ARGS[@]}" \
  --diagnostics-json "$TMP/hardlink.json" \
  >/dev/null 2>&1
status=$?
set -e
[[ "$status" -eq 2 ]]
[[ "$(cat "$hardlink_source")" == "$hardlink_contents" ]]
[[ "$hardlink_source" -ef "$hardlink_output" ]]
grep -q 'driver.output-aliases-source' "$TMP/hardlink.json"

symlink_source="$TMP/symlink-source.weave"
symlink_output="$TMP/symlink-output"
cp "$SOURCE" "$symlink_source"
ln -s "$symlink_source" "$symlink_output"
symlink_contents="$(cat "$symlink_source")"
set +e
"$WEAVEC" build "$symlink_source" -o "$symlink_output" \
  "${RUNTIME_ARGS[@]}" \
  --diagnostics-json "$TMP/symlink.json" \
  >/dev/null 2>&1
status=$?
set -e
[[ "$status" -eq 2 ]]
[[ "$(cat "$symlink_source")" == "$symlink_contents" ]]
[[ -L "$symlink_output" ]]
grep -q 'driver.output-aliases-source' "$TMP/symlink.json"

diagnostics_source="$TMP/diagnostics-source.weave"
cp "$SOURCE" "$diagnostics_source"
diagnostics_contents="$(cat "$diagnostics_source")"
set +e
"$WEAVEC" build "$diagnostics_source" -o "$TMP/diagnostics-program" \
  "${RUNTIME_ARGS[@]}" \
  --diagnostics-json "$diagnostics_source" \
  >/dev/null 2>&1
status=$?
set -e
[[ "$status" -eq 2 ]]
[[ "$(cat "$diagnostics_source")" == "$diagnostics_contents" ]]
[[ ! -e "$TMP/diagnostics-program" ]]

emit_source="$TMP/emit-source.weave"
cp "$SOURCE" "$emit_source"
emit_contents="$(cat "$emit_source")"
set +e
"$WEAVEC" build "$emit_source" -o "$TMP/emit-program" \
  "${RUNTIME_ARGS[@]}" \
  --emit-wir "$emit_source" \
  --trace-json "$TMP/emit-trace.json" \
  --diagnostics-json "$TMP/emit.json" \
  >/dev/null 2>&1
status=$?
set -e
[[ "$status" -eq 2 ]]
[[ "$(cat "$emit_source")" == "$emit_contents" ]]
[[ ! -e "$TMP/emit-program" ]]
grep -q 'driver.output-aliases-source' "$TMP/emit.json"
grep -q '"phase": "driver"' "$TMP/emit-trace.json"

diagnostics_directory="$TMP/diagnostics-directory"
mkdir "$diagnostics_directory"
diagnostics_program="$TMP/diagnostics-publication-program"
set +e
"$WEAVEC" build "$SOURCE" -o "$diagnostics_program" \
  "${RUNTIME_ARGS[@]}" \
  --diagnostics-json "$diagnostics_directory" \
  >/dev/null 2>&1
diagnostics_status=$?
set -e
[[ "$diagnostics_status" -eq 14 ]]
[[ -x "$diagnostics_program" ]]
[[ -d "$diagnostics_directory" ]]
set +e
"$diagnostics_program"
program_status=$?
set -e
[[ "$program_status" -eq 42 ]]
if compgen -G "$diagnostics_directory.tmp.*" >/dev/null; then
  printf 'tooling-artifacts: diagnostics temporary file leaked\n' >&2
  exit 1
fi

printf 'tooling-artifacts: passed\n'
