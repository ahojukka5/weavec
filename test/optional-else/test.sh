#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# An `if` may omit its else. The short form is normalized to the full one, so
# the WIR contract still carries both branches and nothing downstream changes.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-optional-else-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'optional-else: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}

# An else-less if guarding an early return.
cat > "$TMP/guard.weave" <<'EOF'
(program
  (name "optional-else-guard")
  (version "0.1")
  (fn clamp_low
    (params (value i32))
    (returns i32)
    (do
      (if (condition (op less-than value 0))
        (then (do (return 0))))
      (return value)))
  (entry main (params) (returns i32) (do (return (call clamp_low -5)))))
EOF
"$WEAVEC" build "$TMP/guard.weave" -o "$TMP/guard" --emit-wir "$TMP/guard.wir" \
  2>"$TMP/guard.stderr"
if [[ -s "$TMP/guard.stderr" ]]; then
  printf 'optional-else: guard build wrote stderr\n' >&2
  cat "$TMP/guard.stderr" >&2
  exit 1
fi
set +e
"$TMP/guard"
guard_status="$?"
set -e
if [[ "$guard_status" -ne 0 ]]; then
  printf 'optional-else: guard exited %s, expected 0\n' "$guard_status" >&2
  exit 1
fi
# The short form is normalized: the WIR still carries an else branch.
if ! grep -Fq '(else (do))' "$TMP/guard.wir"; then
  printf 'optional-else: normalized WIR is missing the else branch\n' >&2
  exit 1
fi

# The long form keeps working and produces the same program.
cat > "$TMP/explicit.weave" <<'EOF'
(program
  (name "optional-else-explicit")
  (version "0.1")
  (fn clamp_low
    (params (value i32))
    (returns i32)
    (do
      (if (condition (op less-than value 0))
        (then (do (return 0)))
        (else (do)))
      (return value)))
  (entry main (params) (returns i32) (do (return (call clamp_low -5)))))
EOF
"$WEAVEC" build "$TMP/explicit.weave" -o "$TMP/explicit" \
  --emit-wir "$TMP/explicit.wir" 2>/dev/null
set +e
"$TMP/explicit"
explicit_status="$?"
set -e
if [[ "$explicit_status" -ne "$guard_status" ]]; then
  printf 'optional-else: short and long forms disagree (%s vs %s)\n' \
    "$guard_status" "$explicit_status" >&2
  exit 1
fi
# Both spellings must lower to the same statement.
sed 's/optional-else-guard/PROGRAM/' "$TMP/guard.wir" > "$TMP/guard.norm"
sed 's/optional-else-explicit/PROGRAM/' "$TMP/explicit.wir" > "$TMP/explicit.norm"
cmp "$TMP/guard.norm" "$TMP/explicit.norm" || {
  printf 'optional-else: the two spellings lower differently\n' >&2
  diff -u "$TMP/guard.norm" "$TMP/explicit.norm" >&2 || true
  exit 1
}

# An else-less if does not satisfy the terminator rule: it can fall through.
cat > "$TMP/not-terminator.weave" <<'EOF'
(program
  (name "optional-else-not-terminator")
  (version "0.1")
  (fn bad
    (params (flag bool))
    (returns i32)
    (do
      (if (condition flag)
        (then (do (return 1))))))
  (entry main (params) (returns i32) (do (return (call bad true)))))
EOF
set +e
"$WEAVEC" build "$TMP/not-terminator.weave" -o "$TMP/not-terminator" \
  >/dev/null 2>"$TMP/not-terminator.stderr"
not_terminator_status="$?"
set -e
if [[ "$not_terminator_status" -eq 0 ]]; then
  printf 'optional-else: an else-less if was treated as a terminator\n' >&2
  exit 1
fi
if ! grep -Fq 'can reach the end of its body' "$TMP/not-terminator.stderr"; then
  printf 'optional-else: expected the terminator diagnostic\n' >&2
  cat "$TMP/not-terminator.stderr" >&2
  exit 1
fi

# Nested else-less ifs.
cat > "$TMP/nested.weave" <<'EOF'
(program
  (name "optional-else-nested")
  (version "0.1")
  (fn classify
    (params (value i32))
    (returns i32)
    (do
      (if (condition (op greater-than value 0))
        (then (do
          (if (condition (op greater-than value 10))
            (then (do (return 2))))
          (return 1))))
      (return 0)))
  (entry main (params) (returns i32) (do (return (call classify 5)))))
EOF
"$WEAVEC" build "$TMP/nested.weave" -o "$TMP/nested" 2>/dev/null
set +e
"$TMP/nested"
nested_status="$?"
set -e
if [[ "$nested_status" -ne 1 ]]; then
  printf 'optional-else: nested case exited %s, expected 1\n' "$nested_status" >&2
  exit 1
fi

printf 'optional-else: passed\n'
