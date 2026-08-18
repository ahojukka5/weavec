#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Primitive conversion and formatting (#245). format_i32 / format_f64
# match the documented decimal spelling. Parse failures are Result Err.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-convert-format-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'convert-format: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}

SOURCES=(
  "$ROOT/stdlib/memory.weave"
  "$ROOT/stdlib/option.weave"
  "$ROOT/stdlib/result.weave"
  "$ROOT/stdlib/parse.weave"
  "$ROOT/stdlib/io.weave"
  "$ROOT/stdlib/bytes.weave"
  "$ROOT/stdlib/string.weave"
  "$ROOT/stdlib/convert.weave"
)

cat > "$TMP/app.weave" <<'EOF'
(program
  (name "conv")
  (version "0.1")
  (entry main
    (params)
    (returns i32)
    (do
      (let s (call format_i32 42))
      (let n (call string_len s))
      (let c0 (call option_unwrap_or (type-args i32) (call string_get s 0) 0))
      (let c1 (call option_unwrap_or (type-args i32) (call string_get s 1) 0))
      (let ok (call parse_i32 "42"))
      (let bad (call parse_i32 "x"))
      (let f (call format_f64 1.5))
      (let fn (call string_len f))
      (let f0 (call option_unwrap_or (type-args i32) (call string_get f 0) 0))
      (let f1 (call option_unwrap_or (type-args i32) (call string_get f 1) 0))
      (let f2 (call option_unwrap_or (type-args i32) (call string_get f 2) 0))
      (let fl (call parse_float "1.5"))
      (let fb (call parse_float "nope"))
      (let tb (call parse_bool "true"))
      (let bb (call parse_bool "yes"))
      (let one (call format_f64 1.0))
      (let neg (call format_i32 -7))
      (let pneg (call parse_i32 "-7"))
      (let big (call parse_i32 "2147483648"))
      (if
        (condition (call result_is_err (type-args i32 i32) ok))
        (then (do (return 20))))
      (if
        (condition (call result_is_ok (type-args i32 i32) bad))
        (then (do (return 21))))
      (if
        (condition (call result_is_ok (type-args f64 i32) fb))
        (then (do (return 22))))
      (if
        (condition (call result_is_err (type-args f64 i32) fl))
        (then (do (return 23))))
      (if
        (condition (call result_is_err (type-args bool i32) tb))
        (then (do (return 24))))
      (if
        (condition (call result_is_ok (type-args bool i32) bb))
        (then (do (return 25))))
      (if
        (condition (op not-equal (call string_len one) 3))
        (then (do (return 26))))
      (if
        (condition (op not-equal
          (call option_unwrap_or (type-args i32) (call string_get one 2) 0)
          48))
        (then (do (return 27))))
      (if
        (condition (op not-equal (call string_len neg) 2))
        (then (do (return 28))))
      (if
        (condition (op not-equal
          (call result_unwrap_or (type-args i32 i32) pneg 0)
          -7))
        (then (do (return 29))))
      (if
        (condition (call result_is_ok (type-args i32 i32) big))
        (then (do (return 30))))
      (return (op add n
        (op add c0
          (op add c1
            (op add (call result_unwrap_or (type-args i32 i32) ok 0)
              (op add fn
                (op add f0
                  (op add f1 f2)))))))))))
EOF

"$WEAVEC" --frontend "$TMP/app.wir" "${SOURCES[@]}" "$TMP/app.weave" \
  2>"$TMP/app.stderr" || {
  printf 'convert-format: app rejected\n' >&2
  cat "$TMP/app.stderr" >&2
  exit 1
}

grep -Fq '(call_ptr format_i32 (const_i32 42))' "$TMP/app.wir"
grep -Fq '(call_ptr format_f64 (const_f64 1.5))' "$TMP/app.wir"
grep -Fq '(call_ptr parse_i32 (const_string_ptr "42"))' "$TMP/app.wir"
grep -Fq '(call_ptr parse_i32 (const_string_ptr "x"))' "$TMP/app.wir"
grep -Fq '(call_ptr parse_float (const_string_ptr "nope"))' "$TMP/app.wir"
grep -Fq 'Result__s__i32__i32_new_Err' "$TMP/app.wir"

if grep -Eq '\bptr\b|\bextern\b|ptr_add|load_|store_|weave_rt_|malloc|free' \
    "$TMP/app.weave"; then
  printf 'convert-format: application source leaked low-level forms\n' >&2
  exit 1
fi

"$WEAVEC" analyze "${SOURCES[@]}" "$TMP/app.weave" \
  --semantic-index-json "$TMP/app.index.json"
python3 - "$TMP/app.index.json" <<'PY'
import json
import pathlib
import sys

doc = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
names = {item["name"] for item in doc["symbols"]}
for name in (
    "format_i32",
    "format_f64",
    "format_bool",
    "parse_i32",
    "parse_float",
    "parse_bool",
):
    assert name in names, name
print("convert-format: semantic index passed")
PY

if command -v llc >/dev/null 2>&1; then
  "$WEAVEC" build "${SOURCES[@]}" "$TMP/app.weave" -o "$TMP/app"
  set +e
  "$TMP/app"
  status="$?"
  set -e
  if [[ "$status" -ne 297 ]]; then
    printf 'convert-format: expected exit 297, got %s\n' "$status" >&2
    exit 1
  fi
fi

printf 'convert-format: passed\n'
