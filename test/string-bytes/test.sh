#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Owned String and Bytes (#243). User source concatenates text without
# naming ptr. Out-of-range get returns None. #266: string_from_text
# must release its temporary Bytes; string_append must not release
# left and grown, which alias.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-string-bytes-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'string-bytes: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}

SOURCES=(
  "$ROOT/stdlib/memory.weave"
  "$ROOT/stdlib/option.weave"
  "$ROOT/stdlib/bytes.weave"
  "$ROOT/stdlib/string.weave"
)

cat > "$TMP/app.weave" <<'EOF'
(program
  (name "cat")
  (version "0.1")
  (entry main
    (params)
    (returns i32)
    (do
      (let s (call string_from_text "hello"))
      (call string_append s (call string_from_text " world"))
      (let n (call string_len s))
      (let ch (call string_get s 0))
      (let miss (call string_get s 99))
      (if
        (condition (call option_is_some (type-args i32) miss))
        (then (do (return 20))))
      (let raw (call bytes_from_string s))
      (let again (call string_from_bytes raw))
      (return (op add n (call option_unwrap_or (type-args i32) ch 0))))))
EOF

"$WEAVEC" --frontend "$TMP/app.wir" "${SOURCES[@]}" "$TMP/app.weave" \
  2>"$TMP/app.stderr" || {
  printf 'string-bytes: app rejected\n' >&2
  cat "$TMP/app.stderr" >&2
  exit 1
}

grep -Fq '(call_ptr string_from_text (const_string_ptr "hello"))' "$TMP/app.wir"
grep -Fq '(call_ptr string_append' "$TMP/app.wir"
grep -Fq '(call_ptr string_get s (const_i32 99))' "$TMP/app.wir"
grep -Fq 'Option__s__i32_new_None' "$TMP/app.wir"

python3 - "$TMP/app.wir" "$ROOT/stdlib/string.weave" <<'PY'
import re
import sys
from pathlib import Path

wir = Path(sys.argv[1]).read_text(encoding="utf-8")
src = Path(sys.argv[2]).read_text(encoding="utf-8")


def fn_body(text, name):
    match = re.search(
        rf"\(fn {re.escape(name)}\b.*?(?=\n    \(fn |\n    \(entry |\Z)",
        text,
        re.S,
    )
    assert match, f"missing function {name}"
    return match.group(0)


from_text = fn_body(wir, "string_from_text")
append = fn_body(wir, "string_append")
src_from_text = fn_body(src, "string_from_text")
src_append = fn_body(src, "string_append")

assert "bytes_from_text" in from_text, "string_from_text lost bytes_from_text"
assert "bytes_release" in from_text, (
    "string_from_text leaked the bytes_from_text temporary"
)
assert "bytes_release" in src_from_text, (
    "string_from_text source no longer releases src"
)

assert "bytes_release (local_get right)" in src_append
assert "bytes_release (local_get grown)" in src_append
assert "bytes_release (local_get left)" not in src_append, (
    "string_append released left and grown; they alias and that is a double free"
)
assert "bytes_release" in append, "string_append WIR lost bytes_release"
print("string-bytes: leak-check passed")
PY

if grep -Eq '\bptr\b|\bextern\b|ptr_add|load_|store_|weave_rt_|malloc|free' \
    "$TMP/app.weave"; then
  printf 'string-bytes: application source leaked low-level forms\n' >&2
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
assert "String" in names
assert "Bytes" in names
assert "string_from_text" in names
assert "bytes_get" in names
print("string-bytes: semantic index passed")
PY

if command -v llc >/dev/null 2>&1; then
  "$WEAVEC" build "${SOURCES[@]}" "$TMP/app.weave" -o "$TMP/app"
  set +e
  "$TMP/app"
  status="$?"
  set -e
  if [[ "$status" -ne 115 ]]; then
    printf 'string-bytes: expected exit 115, got %s\n' "$status" >&2
    exit 1
  fi
fi

printf 'string-bytes: passed\n'
