#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Deterministic generic monomorphization (#146). A generic function with
# explicit type-args lowers to one concrete WIR function per distinct
# instantiation, shared across uses.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-generic-mono-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'generic-monomorphization: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}

expect_rejected() {
  local name="$1"
  local needle="$2"
  set +e
  "$WEAVEC" --frontend "$TMP/$name.wir" "$TMP/$name.weave" \
    >"$TMP/$name.stdout" 2>"$TMP/$name.stderr"
  local status="$?"
  set -e
  if [[ "$status" -eq 0 ]]; then
    printf 'generic-monomorphization: %s was accepted\n' "$name" >&2
    exit 1
  fi
  if ! grep -Fq "$needle" "$TMP/$name.stderr"; then
    printf 'generic-monomorphization: %s missing diagnostic\n' "$name" >&2
    printf 'expected: %s\n' "$needle" >&2
    cat "$TMP/$name.stderr" >&2
    exit 1
  fi
}

# One specialization, two uses share it.
cat > "$TMP/identity-i32.weave" <<'EOF'
(program
  (name "identity-i32")
  (version "0.1")
  (fn identity
    (type-params T)
    (params (value T))
    (returns T)
    (do (return value)))
  (entry main
    (params)
    (returns i32)
    (do
      (let a i32 (call identity (type-args i32) 1))
      (let b i32 (call identity (type-args i32) 2))
      (return (op add a b)))))
EOF
"$WEAVEC" --frontend "$TMP/identity-i32.wir" "$TMP/identity-i32.weave" \
  2>"$TMP/identity-i32.stderr" || {
  printf 'generic-monomorphization: identity-i32 rejected\n' >&2
  cat "$TMP/identity-i32.stderr" >&2
  exit 1
}
if ! grep -Fq '(fn identity__s__i32' "$TMP/identity-i32.wir"; then
  printf 'generic-monomorphization: missing specialized function\n' >&2
  cat "$TMP/identity-i32.wir" >&2
  exit 1
fi
if ! grep -Fq '(params (value i32))' "$TMP/identity-i32.wir"; then
  printf 'generic-monomorphization: specialized params were not concrete\n' >&2
  cat "$TMP/identity-i32.wir" >&2
  exit 1
fi
uses=$(grep -o 'identity__s__i32' "$TMP/identity-i32.wir" | wc -l | tr -d ' ')
if [[ "$uses" -lt 3 ]]; then
  printf 'generic-monomorphization: expected decl plus two calls, saw %s\n' \
    "$uses" >&2
  cat "$TMP/identity-i32.wir" >&2
  exit 1
fi
if grep -Eq '^\s+\(fn identity ' "$TMP/identity-i32.wir"; then
  printf 'generic-monomorphization: generic template was emitted\n' >&2
  cat "$TMP/identity-i32.wir" >&2
  exit 1
fi

# Distinct type arguments produce distinct specializations.
cat > "$TMP/identity-two.weave" <<'EOF'
(program
  (name "identity-two")
  (version "0.1")
  (fn identity
    (type-params T)
    (params (value T))
    (returns T)
    (do (return value)))
  (fn use-i64
    (params (value i64))
    (returns i64)
    (do (return (call identity (type-args i64) value))))
  (entry main
    (params)
    (returns i32)
    (do (return (call identity (type-args i32) 4)))))
EOF
"$WEAVEC" --frontend "$TMP/identity-two.wir" "$TMP/identity-two.weave" \
  2>"$TMP/identity-two.stderr" || {
  printf 'generic-monomorphization: identity-two rejected\n' >&2
  cat "$TMP/identity-two.stderr" >&2
  exit 1
}
if ! grep -Fq '(fn identity__s__i32' "$TMP/identity-two.wir"; then
  printf 'generic-monomorphization: missing i32 specialization\n' >&2
  cat "$TMP/identity-two.wir" >&2
  exit 1
fi
if ! grep -Fq '(fn identity__s__i64' "$TMP/identity-two.wir"; then
  printf 'generic-monomorphization: missing i64 specialization\n' >&2
  cat "$TMP/identity-two.wir" >&2
  exit 1
fi

# File order does not change specialized names.
cat > "$TMP/lib.weave" <<'EOF'
(program
  (name "lib")
  (version "0.1")
  (fn identity
    (type-params T)
    (params (value T))
    (returns T)
    (do (return value))))
EOF
cat > "$TMP/app.weave" <<'EOF'
(program
  (name "app")
  (version "0.1")
  (fn use
    (params)
    (returns i32)
    (do (return (call identity (type-args i32) 9))))
  (entry main (params) (returns i32) (do (return (call use)))))
EOF
"$WEAVEC" --frontend "$TMP/order-a.wir" "$TMP/lib.weave" "$TMP/app.weave"
"$WEAVEC" --frontend "$TMP/order-b.wir" "$TMP/app.weave" "$TMP/lib.weave"
if ! grep -Fq 'identity__s__i32' "$TMP/order-a.wir"; then
  printf 'generic-monomorphization: order-a missing specialization\n' >&2
  cat "$TMP/order-a.wir" >&2
  exit 1
fi
if ! grep -Fq 'identity__s__i32' "$TMP/order-b.wir"; then
  printf 'generic-monomorphization: order-b missing specialization\n' >&2
  cat "$TMP/order-b.wir" >&2
  exit 1
fi

# Wrong type-args arity.
cat > "$TMP/arity.weave" <<'EOF'
(program
  (name "arity")
  (version "0.1")
  (fn identity
    (type-params T)
    (params (value T))
    (returns T)
    (do (return value)))
  (entry main
    (params)
    (returns i32)
    (do (return (call identity (type-args i32 i32) 1)))))
EOF
expect_rejected arity 'expects 1 type argument(s), got 2'

printf 'generic-monomorphization: passed\n'
