#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Failed call-argument expressions must not become %t-1 (#265).
# The structured diagnostic stays, and no LLVM file is published.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-backend-call-arg-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'backend-call-arg: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}

cat > "$TMP/bad-arg.wir" <<'EOF'
(core-module
  (core-version 3)
  (decls
    (fn add2 (params (x i32) (y i32)) (returns i32)
      (do (return (add_i32 (param_get x) (param_get y)))))
    (fn sink (params (x i32)) (returns void)
      (do (return_void)))
    (fn main (params) (returns i32)
      (do
        (call_void sink (unknown_op 1))
        (return (call_i32 add2 (unknown_op 2) (const_i32 3)))))))
EOF

set +e
"$WEAVEC" --backend "$TMP/bad-arg.wir" "$TMP/bad-arg.ll" 2>"$TMP/bad-arg.stderr"
status="$?"
set -e

if [[ "$status" -eq 0 ]]; then
  printf 'backend-call-arg: backend accepted a failed call argument\n' >&2
  exit 1
fi
if [[ "$status" -ge 128 ]]; then
  printf 'backend-call-arg: backend terminated by signal %s\n' "$status" >&2
  cat "$TMP/bad-arg.stderr" >&2
  exit 1
fi
[[ ! -e "$TMP/bad-arg.ll" ]] || {
  printf 'backend-call-arg: published LLVM after a failed argument\n' >&2
  cat "$TMP/bad-arg.ll" >&2
  exit 1
}
if grep -Fq '%t-1' "$TMP/bad-arg.stderr"; then
  printf 'backend-call-arg: diagnostic mentioned %%t-1\n' >&2
  cat "$TMP/bad-arg.stderr" >&2
  exit 1
fi
grep -Fq 'unknown expression operator: unknown_op' "$TMP/bad-arg.stderr"

printf 'backend-call-arg: passed\n'
