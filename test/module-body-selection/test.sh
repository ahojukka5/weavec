#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-module-body-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'module-body-selection: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}

cat > "$TMP/application.weave" <<'EOF_SOURCE'
(module application
  (import arithmetic (answer))
  (entry main
    (params)
    (returns i32)
    (do (return (call answer)))))
EOF_SOURCE
cat > "$TMP/arithmetic.weave" <<'EOF_SOURCE'
(module arithmetic
  (export answer)
  (fn answer
    (params)
    (returns i32)
    (do (return 42))))
EOF_SOURCE

sources=("$TMP/application.weave" "$TMP/arithmetic.weave")

# The ordinary complete unit remains independently valid through the public
# frontend/backend path.
"$WEAVEC" --frontend "$TMP/complete.wir" "${sources[@]}"
"$WEAVEC" --backend "$TMP/complete.wir" "$TMP/complete.ll"
grep -F 'define i32 @main' "$TMP/complete.ll"
grep -F 'define i32 @answer' "$TMP/complete.ll"

env WEAVEC_INTERNAL_BODY_SOURCE_INDEX=0 \
  "$WEAVEC" --frontend "$TMP/application.wir" "${sources[@]}"
env WEAVEC_INTERNAL_BODY_SOURCE_INDEX=1 \
  "$WEAVEC" --frontend "$TMP/arithmetic.wir" "${sources[@]}"

# The entry unit contains only the entry body. Its imported call remains typed.
grep -F '(fn main ' "$TMP/application.wir"
grep -F 'call_i32 answer' "$TMP/application.wir"
if grep -F '(fn answer ' "$TMP/application.wir" >/dev/null; then
  printf 'module-body-selection: dependency body entered application unit\n' >&2
  exit 1
fi

# The dependency unit contains only its exported implementation.
grep -F '(fn answer ' "$TMP/arithmetic.wir"
if grep -F '(fn main ' "$TMP/arithmetic.wir" >/dev/null; then
  printf 'module-body-selection: entry body entered arithmetic unit\n' >&2
  exit 1
fi

# Invalid cross-module interfaces still fail before body selection.
cat > "$TMP/invalid.weave" <<'EOF_SOURCE'
(module invalid
  (import arithmetic (missing))
  (fn local (params) (returns i32) (do (return 0))))
EOF_SOURCE
set +e
env WEAVEC_INTERNAL_BODY_SOURCE_INDEX=1 \
  "$WEAVEC" --frontend "$TMP/invalid.wir" \
  "$TMP/invalid.weave" "$TMP/arithmetic.weave" \
  >"$TMP/invalid.out" 2>"$TMP/invalid.err"
status=$?
set -e
[[ "$status" -ne 0 ]]
[[ ! -e "$TMP/invalid.wir" ]]
grep -F 'imported symbol does not exist missing' "$TMP/invalid.err"

printf 'module-body-selection: all checks passed\n'
