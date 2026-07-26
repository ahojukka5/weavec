#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-llvm-provenance-XXXXXX")"
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'test-llvm-provenance: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}
command -v clang >/dev/null 2>&1 || {
  printf 'test-llvm-provenance: clang is required\n' >&2
  exit 1
}

cat > "$TMP/library.weave" <<'WEAVE'
(program
  (name "llvm-provenance-library")
  (version "0.1")
  (fn add_two
    (params (x i32))
    (returns i32)
    (do
      (return (add_i32 (param_get x) (const_i32 2))))))
WEAVE

cat > "$TMP/main.weave" <<'WEAVE'
(program
  (name "llvm-provenance-main")
  (version "0.1")
  (entry main
    (params)
    (returns i32)
    (do
      (let answer i32 40)
      (return (call_i32 add_two (local_get answer))))))
WEAVE

kept_directory() {
  sed -n 's/^weavec: kept temporary build directory: //p' "$1" | tail -1
}

normalize_wir() {
  sed -E 's/; weavec-source-(file|span)-v1.*$//' "$1" |
    tr '\n\t\r' ' ' |
    sed -E 's/[[:space:]]+/ /g; s/\( /(/g; s/ \)/)/g; s/^ //; s/ $//'
}

slice_field() {
  local line="$1"
  local name="$2"
  case "$name" in
    bytes)
      printf '%s\n' "$line" |
        sed -E 's/.* bytes=([0-9]+)\.\.([0-9]+) wir-bytes=.*/\1 \2/'
      ;;
    wir-bytes)
      printf '%s\n' "$line" |
        sed -E 's/.* wir-bytes=([0-9]+)\.\.([0-9]+) path=.*/\1 \2/'
      ;;
    *) return 1 ;;
  esac
}

assert_slice() {
  local path="$1"
  local bounds="$2"
  local expected="$3"
  local start end
  read -r start end <<< "$bounds"
  local actual
  actual="$(dd if="$path" bs=1 skip="$start" count="$((end - start))" status=none)"
  [[ "$actual" == "$expected" ]] || {
    printf 'test-llvm-provenance: unexpected source slice\nexpected: %s\nactual: %s\n' \
      "$expected" "$actual" >&2
    exit 1
  }
}

"$WEAVEC" build "$TMP/library.weave" "$TMP/main.weave" \
  -o "$TMP/program" \
  --runtime "$ROOT/runtime/program.c" \
  --llvm-provenance \
  2>"$TMP/provenance.stderr"
PROVENANCE_DIR="$(kept_directory "$TMP/provenance.stderr")"
[[ -n "$PROVENANCE_DIR" && -d "$PROVENANCE_DIR" ]]

set +e
"$TMP/program"
program_status="$?"
set -e
[[ "$program_status" -eq 42 ]] || {
  printf 'test-llvm-provenance: expected exit 42, got %s\n' \
    "$program_status" >&2
  exit 1
}

LLVM="$PROVENANCE_DIR/program.ll"
WIR="$PROVENANCE_DIR/program.wir"
[[ -s "$LLVM" && -s "$WIR" ]]
grep -q '^; weave.source kind=function index=0 ' "$LLVM"
grep -q '^; weave.source kind=function index=1 ' "$LLVM"
grep -q '^; weave.source kind=statement index=0 ' "$LLVM"
grep -q '^; weave.source kind=statement index=1 ' "$LLVM"
grep -Fq "path=\"$TMP/library.weave\"" "$LLVM"
grep -Fq "path=\"$TMP/main.weave\"" "$LLVM"

library_function_line="$(grep -m1 '^; weave.source kind=function index=0 ' "$LLVM")"
main_function_line="$(grep -m1 '^; weave.source kind=function index=1 ' "$LLVM")"
main_statement_line="$(grep -m1 '^; weave.source kind=statement index=1 ' "$LLVM")"

assert_slice "$TMP/library.weave" \
  "$(slice_field "$library_function_line" bytes)" \
  $'(fn add_two\n    (params (x i32))\n    (returns i32)\n    (do\n      (return (add_i32 (param_get x) (const_i32 2)))))'
assert_slice "$TMP/main.weave" \
  "$(slice_field "$main_function_line" bytes)" \
  $'(entry main\n    (params)\n    (returns i32)\n    (do\n      (let answer i32 40)\n      (return (call_i32 add_two (local_get answer)))))'
assert_slice "$TMP/main.weave" \
  "$(slice_field "$main_statement_line" bytes)" \
  '(let answer i32 40)'

read -r wir_start wir_end <<< "$(slice_field "$main_function_line" wir-bytes)"
wir_function="$(dd if="$WIR" bs=1 skip="$wir_start" \
  count="$((wir_end - wir_start))" status=none)"
[[ "$wir_function" == '(fn '* && "$wir_function" == *')' ]]
[[ "$wir_function" == *$'\nmain '* ]]

if command -v llvm-as >/dev/null 2>&1; then
  llvm-as "$LLVM" -o "$TMP/program.bc"
else
  clang -Wno-override-module -c "$LLVM" -o "$TMP/program.o"
fi

"$WEAVEC" build "$TMP/library.weave" "$TMP/main.weave" \
  -o "$TMP/program-plain" \
  --runtime "$ROOT/runtime/program.c" \
  --keep-temporaries \
  2>"$TMP/plain.stderr"
PLAIN_DIR="$(kept_directory "$TMP/plain.stderr")"
[[ -n "$PLAIN_DIR" && -d "$PLAIN_DIR" ]]
! grep -q 'weave.source' "$PLAIN_DIR/program.ll"
! grep -q 'weavec-source-' "$PLAIN_DIR/program.wir"

sed -E '/^; weave.source /d; /^; source: /d' "$LLVM" > "$TMP/provenance-stripped.ll"
sed -E '/^; source: /d' "$PLAIN_DIR/program.ll" > "$TMP/plain-normalized.ll"
cmp "$TMP/provenance-stripped.ll" "$TMP/plain-normalized.ll"
cmp <(normalize_wir "$WIR") <(normalize_wir "$PLAIN_DIR/program.wir")

cat > "$TMP/plain.wir" <<'WIR'
(core-module
  (core-version 2)
  (decls
    (fn main (params) (returns i32) (do (return (const_i32 0))))
  )
)
WIR
WEAVEC_INTERNAL_LLVM_PROVENANCE=1 \
  "$WEAVEC" --backend "$TMP/plain.wir" "$TMP/plain.ll"
! grep -q 'weave.source' "$TMP/plain.ll"

printf 'test-llvm-provenance: passed\n'
