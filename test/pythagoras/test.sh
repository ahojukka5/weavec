#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-pythagoras-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'pythagoras: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}

BIN="$TMP/pythagoras"
WIR="$TMP/pythagoras.wir"

"$WEAVEC" build \
  "$ROOT/stdlib/process.weave" \
  "$ROOT/stdlib/parse.weave" \
  "$ROOT/stdlib/math.weave" \
  "$ROOT/stdlib/io.weave" \
  "$ROOT/examples/pythagoras/main.weave" \
  -o "$BIN" \
  --emit-wir "$WIR"

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
    printf 'pythagoras: %s exited %s, expected %s\n' \
      "$name" "$status" "$expected_status" >&2
    cat "$stdout" >&2 || true
    cat "$stderr" >&2 || true
    exit 1
  fi
  cmp "$want_stdout" "$stdout" || {
    printf 'pythagoras: %s stdout mismatch\n' "$name" >&2
    diff -u "$want_stdout" "$stdout" >&2 || true
    exit 1
  }
  cmp "$want_stderr" "$stderr" || {
    printf 'pythagoras: %s stderr mismatch\n' "$name" >&2
    diff -u "$want_stderr" "$stderr" >&2 || true
    exit 1
  }
}

assert_wir_contains() {
  local needle="$1"
  if ! grep -Fq "$needle" "$WIR"; then
    printf 'pythagoras: emitted WIR is missing: %s\n' "$needle" >&2
    exit 1
  fi
}

run_case integer 0 $'5.0\n' '' 3 4
run_case decimal 0 $'2.5\n' '' 1.5 2.0
run_case zero 2 '' $'error: side lengths must be positive\n' 0 4
run_case negative 2 '' $'error: side lengths must be positive\n' -3 4
run_case arity 2 '' $'usage: pythagoras <a> <b>\n' 3
run_case malformed 2 '' $'error: arguments must be numbers\n' 3 nope
run_case trailing 2 '' $'error: arguments must be numbers\n' 3 4x

# Application source stays on the ordinary surface. Low-level pointer and host
# mechanics are confined to the reusable standard modules and runtime boundary.
if grep -Eq '\bptr\b|\bextern\b|call_(i32|i64|f32|f64|ptr|void)|const_[a-z0-9_]+|ptr_add|load_|store_|weave_rt_' \
    "$ROOT/examples/pythagoras/main.weave"; then
  printf 'pythagoras: application source leaked low-level forms\n' >&2
  exit 1
fi
if grep -Eq 'strtod|strtof|atof|sscanf' "$ROOT/stdlib/parse.weave"; then
  printf 'pythagoras: numeric parsing leaked into libc\n' >&2
  exit 1
fi
if grep -Fq 'weave_rt_sqrt' "$ROOT/runtime/program.c" "$ROOT/stdlib/math.weave"; then
  printf 'pythagoras: square-root semantics leaked into the C runtime\n' >&2
  exit 1
fi
assert_wir_contains '(params (argc i32) (argv ptr))'
assert_wir_contains '(call_void weave_rt_process_capture'
assert_wir_contains '(fn program_main'
assert_wir_contains '(fn args_count'
assert_wir_contains '(fn parse_f64'
assert_wir_contains '(fn sqrt_f64'

printf 'pythagoras: passed\n'
