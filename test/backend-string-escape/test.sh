#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# String-literal emission (#268). Unknown WIR escapes must not produce
# invalid LLVM. Raw control bytes are hex-escaped. Pass-1 and pass-2
# string indices stay aligned (main first).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-string-escape-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'backend-string-escape: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}

cat > "$TMP/known.wir" <<'EOF'
(core-module
  (core-version 3)
  (decls
    (extern puts (params (s ptr)) (returns i32))
    (fn main (params) (returns i32)
      (do
        (call_i32 puts (const_string_ptr "hello\nworld"))
        (call_i32 puts (const_string_ptr "quote: \"x\""))
        (call_i32 puts (const_string_ptr "slash: \\"))
        (call_i32 puts (const_string_ptr "nul:\0z"))
        (return (const_i32 0))))))
EOF

"$WEAVEC" --backend "$TMP/known.wir" "$TMP/known.ll" \
  2>"$TMP/known.stderr" || {
  printf 'backend-string-escape: known escapes rejected\n' >&2
  cat "$TMP/known.stderr" >&2
  exit 1
}

grep -Fq 'c"hello\0Aworld\00"' "$TMP/known.ll"
grep -Fq 'c"quote: \22x\22\00"' "$TMP/known.ll"
grep -Fq 'c"slash: \5C\00"' "$TMP/known.ll"
grep -Fq 'c"nul:\00z\00"' "$TMP/known.ll"

if command -v llvm-as >/dev/null 2>&1; then
  llvm-as "$TMP/known.ll" -o "$TMP/known.bc"
fi

cat > "$TMP/tab.wir" <<'EOF'
(core-module
  (core-version 3)
  (decls
    (extern puts (params (s ptr)) (returns i32))
    (fn main (params) (returns i32)
      (do
        (call_i32 puts (const_string_ptr "hello\tworld"))
        (return (const_i32 0))))))
EOF

set +e
"$WEAVEC" --backend "$TMP/tab.wir" "$TMP/tab.ll" 2>"$TMP/tab.stderr"
tab_status="$?"
set -e
if [[ "$tab_status" -eq 0 ]]; then
  printf 'backend-string-escape: \\t was accepted\n' >&2
  exit 1
fi
[[ ! -e "$TMP/tab.ll" ]]
grep -Fq 'unknown string escape: \t' "$TMP/tab.stderr"

python3 - "$TMP/rawtab.wir" <<'PY'
import pathlib
import sys

pathlib.Path(sys.argv[1]).write_text(
    '(core-module\n'
    '  (core-version 3)\n'
    '  (decls\n'
    '    (extern puts (params (s ptr)) (returns i32))\n'
    '    (fn main (params) (returns i32)\n'
    '      (do\n'
    '        (call_i32 puts (const_string_ptr "hello\tworld"))\n'
    '        (return (const_i32 0))))))\n',
    encoding='utf-8',
)
PY

"$WEAVEC" --backend "$TMP/rawtab.wir" "$TMP/rawtab.ll" \
  2>"$TMP/rawtab.stderr" || {
  printf 'backend-string-escape: raw tab rejected\n' >&2
  cat "$TMP/rawtab.stderr" >&2
  exit 1
}
grep -Fq 'c"hello\09world\00"' "$TMP/rawtab.ll"
if command -v llvm-as >/dev/null 2>&1; then
  llvm-as "$TMP/rawtab.ll" -o "$TMP/rawtab.bc"
fi

cat > "$TMP/order.wir" <<'EOF'
(core-module
  (core-version 3)
  (decls
    (extern puts (params (s ptr)) (returns i32))
    (fn helper (params) (returns i32)
      (do
        (call_i32 puts (const_string_ptr "helper"))
        (return (const_i32 1))))
    (fn main (params) (returns i32)
      (do
        (call_i32 puts (const_string_ptr "main"))
        (return (call_i32 helper))))))
EOF

"$WEAVEC" --backend "$TMP/order.wir" "$TMP/order.ll" \
  2>"$TMP/order.stderr" || {
  printf 'backend-string-escape: two-function order rejected\n' >&2
  cat "$TMP/order.stderr" >&2
  exit 1
}
grep -Fq '@.str0 = private unnamed_addr constant [5 x i8] c"main\00"' \
  "$TMP/order.ll"
grep -Fq '@.str1 = private unnamed_addr constant [7 x i8] c"helper\00"' \
  "$TMP/order.ll"
if grep -Fq 'string literal index drifted' "$TMP/order.stderr"; then
  printf 'backend-string-escape: false drift on aligned strings\n' >&2
  exit 1
fi

printf 'backend-string-escape: passed\n'
