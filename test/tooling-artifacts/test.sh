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
    (do (return (unknown_form 0)))))
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
grep -q '^  (core-version 2)' "$TMP/backend.wir"
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
grep -q '^  (core-version 2)' "$TMP/codegen.wir"
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

printf 'tooling-artifacts: passed\n'
