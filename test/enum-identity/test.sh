#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Enum values have no identity (#279). Equality and ptr escape are rejected
# so a later unboxed Option is not a breaking change.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-enum-identity-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'enum-identity: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}

NEEDLE='values have no identity; use match or variant-tag, not pointer equality'

expect_rejected() {
  local name="$1"
  set +e
  "$WEAVEC" --frontend "$TMP/$name.wir" "$TMP/$name.weave" \
    >"$TMP/$name.stdout" 2>"$TMP/$name.stderr"
  local status="$?"
  set -e
  if [[ "$status" -eq 0 ]]; then
    printf 'enum-identity: %s was accepted\n' "$name" >&2
    exit 1
  fi
  if ! grep -Fq "$NEEDLE" "$TMP/$name.stderr"; then
    printf 'enum-identity: %s missing diagnostic\n' "$name" >&2
    printf 'expected: %s\n' "$NEEDLE" >&2
    cat "$TMP/$name.stderr" >&2
    exit 1
  fi
}

cat > "$TMP/eq.weave" <<'EOF'
(program
  (name "eq")
  (version "0.1")
  (enum Color
    (variant Red)
    (variant Blue i32))
  (entry main
    (params)
    (returns i32)
    (do
      (let a Color (variant Color Red))
      (let b Color (variant Color Red))
      (if
        (condition (= a b))
        (then (do (return 1)))
        (else (do (return 0)))))))
EOF
expect_rejected eq

cat > "$TMP/eq-ptr.weave" <<'EOF'
(program
  (name "eq-ptr")
  (version "0.1")
  (enum Color
    (variant Red)
    (variant Blue i32))
  (entry main
    (params)
    (returns i32)
    (do
      (let a Color (variant Color Red))
      (let b Color (variant Color Red))
      (if
        (condition (eq_ptr (local_get a) (local_get b)))
        (then (do (return 1)))
        (else (do (return 0)))))))
EOF
expect_rejected eq-ptr

cat > "$TMP/to-ptr.weave" <<'EOF'
(program
  (name "to-ptr")
  (version "0.1")
  (enum Color
    (variant Red)
    (variant Blue i32))
  (extern free (params (value ptr)) (returns void))
  (entry main
    (params)
    (returns i32)
    (do
      (let a Color (variant Color Red))
      (free a)
      (return 0))))
EOF
expect_rejected to-ptr

cat > "$TMP/ok.weave" <<'EOF'
(program
  (name "ok")
  (version "0.1")
  (enum Color
    (variant Red)
    (variant Blue i32))
  (entry main
    (params)
    (returns i32)
    (do
      (let a Color (variant Color Red))
      (let b Color (variant Color Blue 7))
      (return (variant-tag Color a))))))
EOF
"$WEAVEC" --frontend "$TMP/ok.wir" "$TMP/ok.weave" \
  2>"$TMP/ok.stderr" || {
  printf 'enum-identity: tag comparison was rejected\n' >&2
  cat "$TMP/ok.stderr" >&2
  exit 1
}

printf 'enum-identity: passed\n'
