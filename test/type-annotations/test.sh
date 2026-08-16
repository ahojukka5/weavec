#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# A type annotation must be a name. Before this check a parenthesised type was
# swallowed: `(let v (owned Vec3) ...)` lowered to `(let v unknown ...)` and
# compiled clean whenever the binding went unused, and reported "receiver is not
# a known struct value" against the field access when it did not.
#
# This matters beyond the confusion. `(owned T)` and `(borrow T)` are the
# qualifiers the ownership work introduces, so accepting them silently would let
# source be written against a spelling that means nothing yet.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-type-annotations-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'type-annotations: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}

expect_rejected() {
  local name="$1"
  local needle="$2"

  set +e
  "$WEAVEC" build "$TMP/$name.weave" -o "$TMP/$name" \
    >"$TMP/$name.stdout" 2>"$TMP/$name.stderr"
  local status="$?"
  set -e

  if [[ "$status" -eq 0 ]]; then
    printf 'type-annotations: %s was accepted\n' "$name" >&2
    exit 1
  fi
  if [[ -e "$TMP/$name" ]]; then
    printf 'type-annotations: %s published an executable\n' "$name" >&2
    exit 1
  fi
  if ! grep -Fq "$needle" "$TMP/$name.stderr"; then
    printf 'type-annotations: %s missing expected diagnostic\n' "$name" >&2
    printf 'expected to contain: %s\n' "$needle" >&2
    cat "$TMP/$name.stderr" >&2
    exit 1
  fi
}

PRELUDE='(program
  (name "PROGRAM")
  (version "0.1")
  (extern malloc (params (size i64)) (returns ptr))
  (struct Vec3 (field x f64) (field y f64) (field z f64))'

# An unused binding is the case that previously compiled clean, so it is the
# one most worth pinning.
cat > "$TMP/binding-unused.weave" <<EOF
${PRELUDE/PROGRAM/binding-unused}
  (entry main (params) (returns i32)
    (do
      (let v (owned Vec3) (new Vec3 (x 1.0) (y 2.0) (z 3.0)))
      (return 0))))
EOF
expect_rejected binding-unused \
  'surface binding: type must be a name, not a compound expression'

cat > "$TMP/binding-used.weave" <<EOF
${PRELUDE/PROGRAM/binding-used}
  (entry main (params) (returns i32)
    (do
      (let v (owned Vec3) (new Vec3 (x 1.0) (y 2.0) (z 3.0)))
      (let got f64 (field-get v y))
      (return (cast i32 got)))))
EOF
expect_rejected binding-used \
  'surface binding: type must be a name, not a compound expression'

cat > "$TMP/parameter.weave" <<EOF
${PRELUDE/PROGRAM/parameter}
  (fn takes (params (v (owned Vec3))) (returns i32) (do (return 0)))
  (entry main (params) (returns i32) (do (return 0))))
EOF
expect_rejected parameter \
  'surface parameter: type must be a name, not a compound expression'

cat > "$TMP/return-type.weave" <<EOF
${PRELUDE/PROGRAM/return-type}
  (fn gives (params) (returns (owned Vec3))
    (do (return (new Vec3 (x 1.0) (y 2.0) (z 3.0)))))
  (entry main (params) (returns i32) (do (return 0))))
EOF
expect_rejected return-type \
  'surface return: type must be a name, not a compound expression'

# Any compound type expression, not only the ownership qualifiers.
cat > "$TMP/arbitrary.weave" <<EOF
${PRELUDE/PROGRAM/arbitrary}
  (entry main (params) (returns i32)
    (do
      (let n (nonsense i32) 1)
      (return 0))))
EOF
expect_rejected arbitrary \
  'surface binding: type must be a name, not a compound expression'

# Ordinary annotations keep working, including a struct name and Qubit.
cat > "$TMP/accepted.weave" <<'EOF'
(program
  (name "accepted")
  (version "0.1")
  (extern malloc (params (size i64)) (returns ptr))
  (extern free (params (value ptr)) (returns void))
  (struct Vec3 (field x f64) (field y f64) (field z f64))
  (fn scale (params (v Vec3) (by f64)) (returns f64)
    (do (return (op mul (field-get v x) by))))
  (entry main (params) (returns i32)
    (do
      (let v Vec3 (new Vec3 (x 3.0) (y 2.0) (z 1.0)))
      (let got f64 (call scale v 2.0))
      (call free v)
      (return (cast i32 got)))))
EOF
"$WEAVEC" build "$TMP/accepted.weave" -o "$TMP/accepted" 2>"$TMP/accepted.stderr" || {
  printf 'type-annotations: ordinary annotations were rejected\n' >&2
  cat "$TMP/accepted.stderr" >&2
  exit 1
}
set +e
"$TMP/accepted"
accepted_status="$?"
set -e
if [[ "$accepted_status" -ne 6 ]]; then
  printf 'type-annotations: accepted case exited %s, expected 6\n' \
    "$accepted_status" >&2
  exit 1
fi

printf 'type-annotations: passed\n'
