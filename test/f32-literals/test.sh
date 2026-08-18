#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# f32/f64 decimal constants must be valid LLVM (#261). 0.1 is not an
# exact f32 decimal token; -0.0 must keep its sign bit.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-f32-literals-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'f32-literals: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}

cat > "$TMP/const.wir" <<'EOF'
(core-module
  (core-version 3)
  (decls
    (fn main (params) (returns i32)
      (do
        (let a f32 (const_f32 0.1))
        (let b f32 (const_f32 -0.0))
        (let c f64 (const_f64 0.1))
        (let d f64 (const_f64 -0.0))
        (return (const_i32 0))))))
EOF

"$WEAVEC" --backend "$TMP/const.wir" "$TMP/const.ll" 2>"$TMP/const.stderr" || {
  printf 'f32-literals: backend rejected WIR\n' >&2
  cat "$TMP/const.stderr" >&2
  exit 1
}

if grep -Eq 'fadd (float|double) 0\.0,' "$TMP/const.ll"; then
  printf 'f32-literals: still materializes constants by adding zero\n' >&2
  cat "$TMP/const.ll" >&2
  exit 1
fi
if grep -Eq 'float 0\.1|double 0\.1|float -0\.0|double -0\.0' "$TMP/const.ll"; then
  printf 'f32-literals: spliced a non-representable decimal into LLVM\n' >&2
  cat "$TMP/const.ll" >&2
  exit 1
fi
grep -Fq 'bitcast i32 1036831949 to float' "$TMP/const.ll"
grep -Fq 'bitcast i32 2147483648 to float' "$TMP/const.ll"
grep -Fq 'bitcast i64 4591870180066957722 to double' "$TMP/const.ll"
grep -Fq 'bitcast i64 -9223372036854775808 to double' "$TMP/const.ll"

if command -v llvm-as >/dev/null 2>&1; then
  llvm-as "$TMP/const.ll" -o "$TMP/const.bc"
elif command -v clang >/dev/null 2>&1; then
  clang -x ir -c "$TMP/const.ll" -o "$TMP/const.o"
fi

cat > "$TMP/app.weave" <<'EOF'
(program
  (name "f32-lit")
  (version "0.1")
  (entry main
    (params)
    (returns i32)
    (do
      (let x f32 0.1)
      (let z f32 -0.0)
      (return 0))))
EOF

"$WEAVEC" --frontend "$TMP/app.wir" "$TMP/app.weave" 2>"$TMP/app.stderr" || {
  printf 'f32-literals: surface frontend rejected\n' >&2
  cat "$TMP/app.stderr" >&2
  exit 1
}
grep -Fq '(const_f32 0.1)' "$TMP/app.wir"
grep -Fq '(const_f32 -0.0)' "$TMP/app.wir"
"$WEAVEC" --backend "$TMP/app.wir" "$TMP/app.ll" 2>"$TMP/app.backend.stderr" || {
  printf 'f32-literals: surface backend rejected\n' >&2
  cat "$TMP/app.backend.stderr" >&2
  exit 1
}
grep -Fq 'bitcast i32 1036831949 to float' "$TMP/app.ll"
grep -Fq 'bitcast i32 2147483648 to float' "$TMP/app.ll"

printf 'f32-literals: passed\n'
