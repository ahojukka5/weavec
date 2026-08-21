#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-parse-digits-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'parse-digits: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}

BIN="$TMP/parse-digits"
WIR="$TMP/parse-digits.wir"
SOURCES=(
  "$ROOT/stdlib/process.weave"
  "$ROOT/stdlib/parse.weave"
  "$ROOT/stdlib/option.weave"
  "$ROOT/stdlib/result.weave"
  "$ROOT/stdlib/io.weave"
  "$ROOT/examples/parse-digits/main.weave"
)

"$WEAVEC" --frontend "$WIR" "${SOURCES[@]}"

for needle in \
  '(fn identity__s__i32' \
  '(fn Option__s__i32_new_None' \
  '(fn Option__s__i32_new_Some' \
  '(fn Result__s__i32__i32_new_Ok' \
  '(fn Result__s__i32__i32_new_Err' \
  'Result__s__i32__i32_payload_Ok' \
  'Result__s__i32__i32_payload_Err' \
  '(call_ptr malloc (const_i64 16))'; do
  if ! grep -Fq "$needle" "$WIR"; then
    printf 'parse-digits: frontend WIR missing %s\n' "$needle" >&2
    cat "$WIR" >&2
    exit 1
  fi
done
if grep -Eq '^\s+\(fn identity ' "$WIR"; then
  printf 'parse-digits: generic identity template was emitted\n' >&2
  cat "$WIR" >&2
  exit 1
fi
if grep -Eq '^\s+\(fn Option_new_|^\s+\(fn Result_new_' "$WIR"; then
  printf 'parse-digits: generic enum template was emitted\n' >&2
  cat "$WIR" >&2
  exit 1
fi

if grep -Eq '\bptr\b|\bextern\b|call_(i32|i64|f32|f64|ptr|void)|const_[a-z0-9_]+|ptr_add|load_|store_|weave_rt_' \
    "$ROOT/examples/parse-digits/main.weave"; then
  printf 'parse-digits: application source leaked low-level forms\n' >&2
  exit 1
fi

if ! command -v llc >/dev/null 2>&1; then
  printf 'parse-digits: frontend passed (llc not present; native skipped)\n'
  exit 0
fi

"$WEAVEC" build "${SOURCES[@]}" -o "$BIN" --emit-wir "$WIR"

run_case() {
  local name="$1"
  local expected_status="$2"
  local expected_stdout="$3"
  local expected_stderr="$4"
  shift 4

  local stdout="$TMP/$name.stdout"
  local stderr="$TMP/$name.stderr"
  local want_stdout="$TMP/$name.expected.stdout"
  local want_stderr="$TMP/$name.expected.stderr"
  printf '%s' "$expected_stdout" > "$want_stdout"
  printf '%s' "$expected_stderr" > "$want_stderr"

  set +e
  LC_ALL=C "$BIN" "$@" >"$stdout" 2>"$stderr"
  local status="$?"
  set -e

  if [[ "$status" -ne "$expected_status" ]]; then
    printf 'parse-digits: %s exited %s, expected %s\n' \
      "$name" "$status" "$expected_status" >&2
    cat "$stdout" >&2 || true
    cat "$stderr" >&2 || true
    exit 1
  fi
  cmp "$want_stdout" "$stdout" || {
    printf 'parse-digits: %s stdout mismatch\n' "$name" >&2
    diff -u "$want_stdout" "$stdout" >&2 || true
    exit 1
  }
  cmp "$want_stderr" "$stderr" || {
    printf 'parse-digits: %s stderr mismatch\n' "$name" >&2
    diff -u "$want_stderr" "$stderr" >&2 || true
    exit 1
  }
}

run_case documented 0 $'digits = 1 2 3\nsum = 6\n' '' 1 2 3
run_case ends 0 $'digits = 0 9\nsum = 9\n' '' 0 9
run_case decimal 0 $'digits = 1\nsum = 1\n' '' 1.0
run_case usage 2 '' $'usage: parse-digits <digit>...\n'
run_case malformed 2 $'digits = 1' $'error: not a digit: x\n' 1 x
run_case too-large 2 '' $'error: not a digit: 10\n' 10
run_case negative 2 '' $'error: not a digit: -1\n' -1
run_case fraction 2 '' $'error: not a digit: 1.5\n' 1.5

printf 'parse-digits: passed\n'
