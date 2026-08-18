#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Expression-valued if (#236). Both branches are expressions of one type.
# Else is required. Statement if is unchanged.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-expr-if-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'expr-if: compiler not found: %s\n' "$WEAVEC" >&2
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
    printf 'expr-if: %s was accepted\n' "$name" >&2
    exit 1
  fi
  if ! grep -Fq "$needle" "$TMP/$name.stderr"; then
    printf 'expr-if: %s missing diagnostic\n' "$name" >&2
    printf 'expected: %s\n' "$needle" >&2
    cat "$TMP/$name.stderr" >&2
    exit 1
  fi
}

cat > "$TMP/let.weave" <<'EOF'
(program
  (name "let")
  (version "0.1")
  (entry main
    (params)
    (returns i32)
    (do
      (let n i32 (if (condition true) (then 1) (else 2)))
      (return n))))
EOF
"$WEAVEC" --frontend "$TMP/let.wir" "$TMP/let.weave" \
  2>"$TMP/let.stderr" || {
  printf 'expr-if: let rejected\n' >&2
  cat "$TMP/let.stderr" >&2
  exit 1
}
grep -Fq '(let n i32' "$TMP/let.wir"
grep -Fq '(set n (const_i32 1))' "$TMP/let.wir"
grep -Fq '(set n (const_i32 2))' "$TMP/let.wir"
grep -Fq '(condition (const_bool true))' "$TMP/let.wir"

cat > "$TMP/ret.weave" <<'EOF'
(program
  (name "ret")
  (version "0.1")
  (entry main
    (params)
    (returns i32)
    (do
      (return (if (condition false) (then 3) (else 4))))))
EOF
"$WEAVEC" --frontend "$TMP/ret.wir" "$TMP/ret.weave" \
  2>"$TMP/ret.stderr" || {
  printf 'expr-if: return rejected\n' >&2
  cat "$TMP/ret.stderr" >&2
  exit 1
}
grep -Fq '(return (const_i32 3))' "$TMP/ret.wir"
grep -Fq '(return (const_i32 4))' "$TMP/ret.wir"

cat > "$TMP/stmt.weave" <<'EOF'
(program
  (name "stmt")
  (version "0.1")
  (entry main
    (params)
    (returns i32)
    (do
      (if (condition true)
        (then (do (return 5)))
        (else (do (return 6)))))))
EOF
"$WEAVEC" --frontend "$TMP/stmt.wir" "$TMP/stmt.weave" \
  2>"$TMP/stmt.stderr" || {
  printf 'expr-if: statement if rejected\n' >&2
  cat "$TMP/stmt.stderr" >&2
  exit 1
}
if grep -Fq 'expression if' "$TMP/stmt.stderr"; then
  printf 'expr-if: statement if was treated as an expression\n' >&2
  exit 1
fi

cat > "$TMP/missing-else.weave" <<'EOF'
(program
  (name "missing-else")
  (version "0.1")
  (entry main
    (params)
    (returns i32)
    (do
      (let n i32 (if (condition true) (then 1)))
      (return n))))
EOF
expect_rejected missing-else 'expression if requires an else'

cat > "$TMP/disagree.weave" <<'EOF'
(program
  (name "disagree")
  (version "0.1")
  (entry main
    (params)
    (returns i32)
    (do
      (let n i32 (if (condition true) (then 1) (else true)))
      (return n))))
EOF
expect_rejected disagree 'if branch types disagree'

cat > "$TMP/as-stmt.weave" <<'EOF'
(program
  (name "as-stmt")
  (version "0.1")
  (entry main
    (params)
    (returns i32)
    (do
      (if (condition true) (then 1) (else 2))
      (return 0))))
EOF
expect_rejected as-stmt 'expression if must initialize a let or be returned'

printf 'expr-if: passed\n'
