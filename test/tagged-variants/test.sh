#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Tagged variants (#147). Nullary and payload constructors lower to concrete
# WIR helpers; generic enums specialize by explicit type-args.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-tagged-variants-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'tagged-variants: compiler not found: %s\n' "$WEAVEC" >&2
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
    printf 'tagged-variants: %s was accepted\n' "$name" >&2
    exit 1
  fi
  if ! grep -Fq "$needle" "$TMP/$name.stderr"; then
    printf 'tagged-variants: %s missing diagnostic\n' "$name" >&2
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
  (fn tag-of
    (params (value Color))
    (returns i32)
    (do (return (variant-tag Color value))))
  (entry main
    (params)
    (returns i32)
    (do
      (let red Color (variant Color Red))
      (let blue Color (variant Color Blue 7))
      (return (op add (call tag-of red) (variant-payload Color Blue blue))))))
EOF
"$WEAVEC" --frontend "$TMP/color.wir" "$TMP/color.weave" \
  2>"$TMP/color.stderr" || {
  printf 'tagged-variants: color rejected\n' >&2
  cat "$TMP/color.stderr" >&2
  exit 1
}
for needle in \
  '(fn Color_new_Red' \
  '(fn Color_new_Blue' \
  '(fn Color_tag' \
  '(fn Color_payload_Blue' \
  '(store_i32 (local_get self) (const_i32 0))' \
  '(store_i32 (local_get self) (const_i32 1))'; do
  if ! grep -Fq "$needle" "$TMP/color.wir"; then
    printf 'tagged-variants: color missing %s\n' "$needle" >&2
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
      (let none (type-app Option i32) (variant Option (type-args i32) None))
      (let some (type-app Option i32) (variant Option (type-args i32) Some 4))
      (return (variant-payload Option Some some)))))
EOF
"$WEAVEC" --frontend "$TMP/option.wir" "$TMP/option.weave" \
  2>"$TMP/option.stderr" || {
  printf 'tagged-variants: option rejected\n' >&2
  cat "$TMP/option.stderr" >&2
  exit 1
}
if ! grep -Fq '(fn Option__s__i32_new_Some' "$TMP/option.wir"; then
  printf 'tagged-variants: missing specialized constructor\n' >&2
  cat "$TMP/option.wir" >&2
  exit 1
fi
if grep -Eq '^\s+\(fn Option_new_' "$TMP/option.wir"; then
  printf 'tagged-variants: generic enum template was emitted\n' >&2
  cat "$TMP/option.wir" >&2
  exit 1
fi

cat > "$TMP/dup.weave" <<'EOF'
(program
  (name "dup")
  (version "0.1")
  (enum Color
    (variant Red)
    (variant Red))
  (entry main (params) (returns i32) (do (return 0))))
EOF
expect_rejected dup 'duplicate variant'

cat > "$TMP/unknown.weave" <<'EOF'
(program
  (name "unknown")
  (version "0.1")
  (enum Color
    (variant Red))
  (entry main
    (params)
    (returns i32)
    (do (return (variant-tag Color (variant Color Blue))))))
EOF
expect_rejected unknown 'unknown variant constructor'

cat > "$TMP/payload.weave" <<'EOF'
(program
  (name "payload")
  (version "0.1")
  (enum Color
    (variant Blue void))
  (entry main (params) (returns i32) (do (return 0))))
EOF
expect_rejected payload 'unsupported variant payload type'

cat > "$TMP/nullary-payload.weave" <<'EOF'
(program
  (name "nullary-payload")
  (version "0.1")
  (enum Color
    (variant Red))
  (entry main
    (params)
    (returns i32)
    (do (return (variant-tag Color (variant Color Red 1))))))
EOF
expect_rejected nullary-payload 'variant constructor takes no payload'

printf 'tagged-variants: passed\n'
