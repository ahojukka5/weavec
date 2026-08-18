#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Raw #"..." and multiline """...""" strings (#239). Ordinary escaped
# "..." is unchanged. All four spellings lower to const_string_ptr.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-strings-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'string-literals: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}

expect_rejected() {
  local name="$1"
  local needle="$2"
  set +e
  "$WEAVEC" build "$TMP/$name.weave" -o "$TMP/$name.bin" \
    >"$TMP/$name.stdout" 2>"$TMP/$name.stderr"
  local status="$?"
  set -e
  if [[ "$status" -eq 0 ]]; then
    printf 'string-literals: %s was accepted\n' "$name" >&2
    exit 1
  fi
  if ! grep -Fq "$needle" "$TMP/$name.stderr"; then
    printf 'string-literals: %s missing diagnostic\n' "$name" >&2
    printf 'expected: %s\n' "$needle" >&2
    cat "$TMP/$name.stderr" >&2
    exit 1
  fi
}

cat > "$TMP/escaped.weave" <<'EOF'
(program
  (name "escaped")
  (version "0.1")
  (entry main
    (params)
    (returns ptr)
    (do (return "hello\nworld"))))
EOF
"$WEAVEC" --frontend "$TMP/escaped.wir" "$TMP/escaped.weave" \
  2>"$TMP/escaped.stderr" || {
  printf 'string-literals: escaped rejected\n' >&2
  cat "$TMP/escaped.stderr" >&2
  exit 1
}
grep -Fq '(const_string_ptr "hello\nworld")' "$TMP/escaped.wir"
if grep -Fq '(const_string_ptr "hello\\nworld")' "$TMP/escaped.wir"; then
  printf 'string-literals: escaped string was re-escaped\n' >&2
  exit 1
fi

cat > "$TMP/raw.weave" <<'EOF'
(program
  (name "raw")
  (version "0.1")
  (entry main
    (params)
    (returns ptr)
    (do (return #"hello\nworld"))))
EOF
"$WEAVEC" --frontend "$TMP/raw.wir" "$TMP/raw.weave" \
  2>"$TMP/raw.stderr" || {
  printf 'string-literals: raw rejected\n' >&2
  cat "$TMP/raw.stderr" >&2
  exit 1
}
grep -Fq '(const_string_ptr "hello\\nworld")' "$TMP/raw.wir"

cat > "$TMP/multiline.weave" <<'EOF'
(program
  (name "multiline")
  (version "0.1")
  (entry main
    (params)
    (returns ptr)
    (do (return """hello
world"""))))
EOF
"$WEAVEC" --frontend "$TMP/multiline.wir" "$TMP/multiline.weave" \
  2>"$TMP/multiline.stderr" || {
  printf 'string-literals: multiline rejected\n' >&2
  cat "$TMP/multiline.stderr" >&2
  exit 1
}
if [[ "$(grep -c '(const_string_ptr ' "$TMP/multiline.wir")" -ne 1 ]]; then
  printf 'string-literals: multiline did not lower to one string\n' >&2
  cat "$TMP/multiline.wir" >&2
  exit 1
fi
grep -Fq '(const_string_ptr "hello\nworld")' "$TMP/multiline.wir"

cat > "$TMP/raw-multiline.weave" <<'EOF'
(program
  (name "raw-multiline")
  (version "0.1")
  (entry main
    (params)
    (returns ptr)
    (do (return #"""hello\n
world"""))))
EOF
"$WEAVEC" --frontend "$TMP/raw-multiline.wir" "$TMP/raw-multiline.weave" \
  2>"$TMP/raw-multiline.stderr" || {
  printf 'string-literals: raw-multiline rejected\n' >&2
  cat "$TMP/raw-multiline.stderr" >&2
  exit 1
}
grep -Fq '(const_string_ptr "hello\\n\nworld")' "$TMP/raw-multiline.wir"

cat > "$TMP/empty.weave" <<'EOF'
(program
  (name "empty")
  (version "0.1")
  (entry main
    (params)
    (returns ptr)
    (do (return #""))))
EOF
"$WEAVEC" --frontend "$TMP/empty.wir" "$TMP/empty.weave" \
  2>"$TMP/empty.stderr" || {
  printf 'string-literals: empty raw rejected\n' >&2
  cat "$TMP/empty.stderr" >&2
  exit 1
}
grep -Fq '(const_string_ptr "")' "$TMP/empty.wir"

cat > "$TMP/format.weave" <<'EOF'
(program
  (name "format")
  (version "0.1")
  (entry main
    (params)
    (returns ptr)
    (do
      (let raw #"C:\path")
      (let multi """hello
world""")
      (return raw))))
EOF
"$WEAVEC" fmt --output "$TMP/format.out.weave" "$TMP/format.weave"
grep -Fq '#"C:\path"' "$TMP/format.out.weave"
grep -Fq '"""hello' "$TMP/format.out.weave"
grep -Fq 'world"""' "$TMP/format.out.weave"
"$WEAVEC" fmt --check "$TMP/format.out.weave"
cp "$TMP/format.out.weave" "$TMP/format.twice.weave"
"$WEAVEC" fmt "$TMP/format.twice.weave"
cmp "$TMP/format.out.weave" "$TMP/format.twice.weave"
"$WEAVEC" --frontend "$TMP/format.wir" "$TMP/format.out.weave" \
  2>"$TMP/format.stderr" || {
  printf 'string-literals: formatted source rejected\n' >&2
  cat "$TMP/format.stderr" >&2
  exit 1
}
grep -Fq '(const_string_ptr "C:\\path")' "$TMP/format.wir"
grep -Fq '(const_string_ptr "hello\nworld")' "$TMP/format.wir"

cat > "$TMP/unterminated-raw.weave" <<'EOF'
(program
  (name "unterminated-raw")
  (version "0.1")
  (entry main
    (params)
    (returns ptr)
    (do (return #"hello)))
EOF
expect_rejected unterminated-raw 'unterminated string literal'

cat > "$TMP/unterminated-multi.weave" <<'EOF'
(program
  (name "unterminated-multi")
  (version "0.1")
  (entry main
    (params)
    (returns ptr)
    (do (return """hello
world)))
EOF
expect_rejected unterminated-multi 'unterminated string literal'

printf 'string-literals: passed\n'
