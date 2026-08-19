#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Statement-position call_f32/call_f64 (#267). A float-returning call
# used only for its side effects must compile, not fall through as an
# unknown statement.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-stmt-call-float-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'backend-stmt-call-float: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}

cat > "$TMP/stmt-float.wir" <<'EOF'
(core-module
  (core-version 3)
  (decls
    (fn bump_f32 (params (x f32)) (returns f32)
      (do (return (add_f32 (param_get x) (const_f32 1.0)))))
    (fn bump_f64 (params (x f64)) (returns f64)
      (do (return (add_f64 (param_get x) (const_f64 1.0)))))
    (fn main (params) (returns i32)
      (do
        (call_f32 bump_f32 (const_f32 1.0))
        (call_f64 bump_f64 (const_f64 1.0))
        (return (const_i32 0))))))
EOF

"$WEAVEC" --backend "$TMP/stmt-float.wir" "$TMP/stmt-float.ll" \
  2>"$TMP/stmt-float.stderr" || {
  printf 'backend-stmt-call-float: statement-position float call rejected\n' >&2
  cat "$TMP/stmt-float.stderr" >&2
  exit 1
}

if grep -Fq 'unknown expression operator' "$TMP/stmt-float.stderr"; then
  printf 'backend-stmt-call-float: still treated as unknown\n' >&2
  cat "$TMP/stmt-float.stderr" >&2
  exit 1
fi

grep -Fq 'call float @bump_f32' "$TMP/stmt-float.ll"
grep -Fq 'call double @bump_f64' "$TMP/stmt-float.ll"

# Existing integer discard path must still compile through the shared matcher.
cat > "$TMP/stmt-i32.wir" <<'EOF'
(core-module
  (core-version 3)
  (decls
    (fn bump (params (x i32)) (returns i32)
      (do (return (add_i32 (param_get x) (const_i32 1)))))
    (fn main (params) (returns i32)
      (do
        (call_i32 bump (const_i32 1))
        (return (const_i32 0))))))
EOF

"$WEAVEC" --backend "$TMP/stmt-i32.wir" "$TMP/stmt-i32.ll" \
  2>"$TMP/stmt-i32.stderr" || {
  printf 'backend-stmt-call-float: statement-position i32 call rejected\n' >&2
  cat "$TMP/stmt-i32.stderr" >&2
  exit 1
}
grep -Fq 'call i32 @bump' "$TMP/stmt-i32.ll"

if command -v llvm-as >/dev/null 2>&1; then
  llvm-as "$TMP/stmt-float.ll" -o "$TMP/stmt-float.bc"
fi

printf 'backend-stmt-call-float: passed\n'
