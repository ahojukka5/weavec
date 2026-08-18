#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Exhaustive match (#148). Cases lower to tag tests; coverage is required.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-variant-match-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'variant-match: compiler not found: %s\n' "$WEAVEC" >&2
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
    printf 'variant-match: %s was accepted\n' "$name" >&2
    exit 1
  fi
  if ! grep -Fq "$needle" "$TMP/$name.stderr"; then
    printf 'variant-match: %s missing diagnostic\n' "$name" >&2
    printf 'expected: %s\n' "$needle" >&2
    cat "$TMP/$name.stderr" >&2
    exit 1
  fi
}

cat > "$TMP/color.weave" <<'EOF'
(program
  (name "color")
  (version "0.1")
  (enum Color
    (variant Red)
    (variant Blue i32))
  (entry main
    (params)
    (returns i32)
    (do
      (let blue Color (variant Color Blue 7))
      (return (match Color blue
        (case Red 0)
        (case Blue x x))))))
EOF
"$WEAVEC" --frontend "$TMP/color.wir" "$TMP/color.weave" \
  2>"$TMP/color.stderr" || {
  printf 'variant-match: color rejected\n' >&2
  cat "$TMP/color.stderr" >&2
  exit 1
}
for needle in \
  '(eq_i32 (call_i32 Color_tag (local_get __m0)) (const_i32 0))' \
  '(call_i32 Color_payload_Blue (local_get __m0))' \
  '(return (const_i32 0))'; do
  if ! grep -Fq "$needle" "$TMP/color.wir"; then
    printf 'variant-match: color missing %s\n' "$needle" >&2
    cat "$TMP/color.wir" >&2
    exit 1
  fi
done

cat > "$TMP/option.weave" <<'EOF'
(program
  (name "option")
  (version "0.1")
  (enum Option
    (type-params T)
    (variant None)
    (variant Some T))
  (entry main
    (params)
    (returns i32)
    (do
      (let some (type-app Option i32) (variant Option (type-args i32) Some 4))
      (let n i32 (match Option some
        (case None 0)
        (case Some x x)))
      (return n))))
EOF
"$WEAVEC" --frontend "$TMP/option.wir" "$TMP/option.weave" \
  2>"$TMP/option.stderr" || {
  printf 'variant-match: option rejected\n' >&2
  cat "$TMP/option.stderr" >&2
  exit 1
}
if ! grep -Fq 'Option__s__i32_payload_Some' "$TMP/option.wir"; then
  printf 'variant-match: missing specialized payload helper\n' >&2
  cat "$TMP/option.wir" >&2
  exit 1
fi

cat > "$TMP/wild.weave" <<'EOF'
(program
  (name "wild")
  (version "0.1")
  (enum Color
    (variant Red)
    (variant Blue i32))
  (entry main
    (params)
    (returns i32)
    (do
      (let red Color (variant Color Red))
      (return (match Color red
        (case Red 1)
        (case _ 2))))))
EOF
"$WEAVEC" --frontend "$TMP/wild.wir" "$TMP/wild.weave" \
  2>"$TMP/wild.stderr" || {
  printf 'variant-match: wild rejected\n' >&2
  cat "$TMP/wild.stderr" >&2
  exit 1
}

cat > "$TMP/missing.weave" <<'EOF'
(program
  (name "missing")
  (version "0.1")
  (enum Color
    (variant Red)
    (variant Blue i32))
  (entry main
    (params)
    (returns i32)
    (do
      (let red Color (variant Color Red))
      (return (match Color red
        (case Red 0))))))
EOF
expect_rejected missing 'non-exhaustive match'

cat > "$TMP/dup.weave" <<'EOF'
(program
  (name "dup")
  (version "0.1")
  (enum Color
    (variant Red)
    (variant Blue i32))
  (entry main
    (params)
    (returns i32)
    (do
      (let red Color (variant Color Red))
      (return (match Color red
        (case Red 0)
        (case Red 1)
        (case Blue x x))))))
EOF
expect_rejected dup 'duplicate match arm'

cat > "$TMP/unreachable.weave" <<'EOF'
(program
  (name "unreachable")
  (version "0.1")
  (enum Color
    (variant Red)
    (variant Blue i32))
  (entry main
    (params)
    (returns i32)
    (do
      (let red Color (variant Color Red))
      (return (match Color red
        (case Red 0)
        (case Blue x x)
        (case _ 2))))))
EOF
expect_rejected unreachable 'unreachable wildcard'

cat > "$TMP/disagree.weave" <<'EOF'
(program
  (name "disagree")
  (version "0.1")
  (enum Color
    (variant Red)
    (variant Blue i32))
  (entry main
    (params)
    (returns i32)
    (do
      (let red Color (variant Color Red))
      (return (match Color red
        (case Red 0)
        (case Blue x true))))))
EOF
expect_rejected disagree 'match arm types disagree'

printf 'variant-match: passed\n'
