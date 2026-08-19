#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Binding soundness (#264): sibling lets stay distinct, unknown lookups
# are errors, and temps live in %.tN so a param named t0 cannot collide.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-backend-binding-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'backend-binding-soundness: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}

cat > "$TMP/sibling-lets.wir" <<'EOF'
(core-module
  (core-version 3)
  (decls
    (fn main (params) (returns i32)
      (do
        (if (condition (const_bool true))
          (then (do
            (let x i32 (const_i32 1))
            (return (local_get x))))
          (else (do
            (let x i32 (const_i32 2))
            (return (local_get x)))))))))
EOF

"$WEAVEC" --backend "$TMP/sibling-lets.wir" "$TMP/sibling-lets.ll" \
  2>"$TMP/sibling-lets.stderr" || {
  printf 'backend-binding-soundness: sibling lets rejected\n' >&2
  cat "$TMP/sibling-lets.stderr" >&2
  exit 1
}
if grep -Fq 'duplicate local' "$TMP/sibling-lets.stderr"; then
  printf 'backend-binding-soundness: sibling lets treated as duplicates\n' >&2
  exit 1
fi
grep -Fq 'ret i32 1' "$TMP/sibling-lets.ll"
grep -Fq 'ret i32 2' "$TMP/sibling-lets.ll"

cat > "$TMP/same-block-dup.wir" <<'EOF'
(core-module
  (core-version 3)
  (decls
    (fn main (params) (returns i32)
      (do
        (let x i32 (const_i32 1))
        (let x i32 (const_i32 2))
        (return (local_get x))))))
EOF

set +e
"$WEAVEC" --backend "$TMP/same-block-dup.wir" "$TMP/same-block-dup.ll" \
  2>"$TMP/same-block-dup.stderr"
status="$?"
set -e
if [[ "$status" -eq 0 ]]; then
  printf 'backend-binding-soundness: same-block duplicate let accepted\n' >&2
  exit 1
fi
[[ ! -e "$TMP/same-block-dup.ll" ]]
grep -Fq 'duplicate local: x' "$TMP/same-block-dup.stderr"

cat > "$TMP/unknown-local.wir" <<'EOF'
(core-module
  (core-version 3)
  (decls
    (fn main (params) (returns i32)
      (do (return (local_get missing))))))
EOF

set +e
"$WEAVEC" --backend "$TMP/unknown-local.wir" "$TMP/unknown-local.ll" \
  2>"$TMP/unknown-local.stderr"
status="$?"
set -e
if [[ "$status" -eq 0 ]]; then
  printf 'backend-binding-soundness: unknown local accepted\n' >&2
  exit 1
fi
[[ ! -e "$TMP/unknown-local.ll" ]]
grep -Fq 'unknown identifier: missing' "$TMP/unknown-local.stderr"

cat > "$TMP/param-t0.wir" <<'EOF'
(core-module
  (core-version 3)
  (decls
    (fn main (params (t0 i32)) (returns i32)
      (do (return (add_i32 (param_get t0) (const_i32 1)))))))
EOF

"$WEAVEC" --backend "$TMP/param-t0.wir" "$TMP/param-t0.ll" \
  2>"$TMP/param-t0.stderr" || {
  printf 'backend-binding-soundness: param t0 rejected\n' >&2
  cat "$TMP/param-t0.stderr" >&2
  exit 1
}
grep -Fq '%t0' "$TMP/param-t0.ll"
grep -Fq '%.t0' "$TMP/param-t0.ll"
if grep -Eq 'add i32 %t0, %t0|add i32 %.t0, %.t0' "$TMP/param-t0.ll"; then
  printf 'backend-binding-soundness: param and temp collapsed\n' >&2
  cat "$TMP/param-t0.ll" >&2
  exit 1
fi
grep -Fq 'add i32 %t0, 1' "$TMP/param-t0.ll"

printf 'backend-binding-soundness: passed\n'
