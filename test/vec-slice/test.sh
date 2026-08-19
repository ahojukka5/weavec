#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Generic Vec and Slice (#244). Vec<i32> grows and indexes safely.
# Out-of-range get returns None; set returns false. They do not abort.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-vec-slice-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'vec-slice: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}

SOURCES=(
  "$ROOT/stdlib/memory.weave"
  "$ROOT/stdlib/option.weave"
  "$ROOT/stdlib/vec.weave"
)

cat > "$TMP/app.weave" <<'EOF'
(program
  (name "grow")
  (version "0.1")
  (entry main
    (params)
    (returns i32)
    (do
      (let v (call vec_new (type-args i32)))
      (call vec_push (type-args i32) v 10)
      (call vec_push (type-args i32) v 20)
      (call vec_push (type-args i32) v 30)
      (let n (call vec_len (type-args i32) v))
      (let first (call vec_get (type-args i32) v 0))
      (let miss (call vec_get (type-args i32) v 99))
      (let okset (call vec_set (type-args i32) v 1 21))
      (let badset (call vec_set (type-args i32) v 99 0))
      (let sl (call vec_as_slice (type-args i32) v))
      (let sln (call slice_len (type-args i32) sl))
      (let slmiss (call slice_get (type-args i32) sl -1))
      (let slset (call slice_set (type-args i32) sl 2 31))
      (let mid (call vec_get (type-args i32) v 1))
      (let last (call slice_get (type-args i32) sl 2))
      (if
        (condition (call option_is_some (type-args i32) miss))
        (then (do (return 20))))
      (if
        (condition (call option_is_some (type-args i32) slmiss))
        (then (do (return 21))))
      (if
        (condition badset)
        (then (do (return 22))))
      (if
        (condition slset)
        (then (do))
        (else (do (return 23))))
      (if
        (condition okset)
        (then (do))
        (else (do (return 24))))
      (return (op add n
        (op add sln
          (op add (call option_unwrap_or (type-args i32) first 0)
            (op add (call option_unwrap_or (type-args i32) mid 0)
              (call option_unwrap_or (type-args i32) last 0))))))))))
EOF

"$WEAVEC" --frontend "$TMP/app.wir" "${SOURCES[@]}" "$TMP/app.weave" \
  2>"$TMP/app.stderr" || {
  printf 'vec-slice: app rejected\n' >&2
  cat "$TMP/app.stderr" >&2
  exit 1
}

grep -Fq '(fn Vec_new (params (data ptr) (len i32) (cap i32))' "$TMP/app.wir"
grep -Fq '(call_ptr vec_new__s__i32)' "$TMP/app.wir"
grep -Fq '(call_ptr vec_push__s__i32' "$TMP/app.wir"
grep -Fq '(call_ptr vec_get__s__i32 v (const_i32 99))' "$TMP/app.wir"
grep -Fq 'Option__s__i32_new_None' "$TMP/app.wir"
grep -Fq '(call_ptr Slice_new' "$TMP/app.wir"

if grep -Eq '\bptr\b|\bextern\b|ptr_add|load_|store_|weave_rt_|malloc|free' \
    "$TMP/app.weave"; then
  printf 'vec-slice: application source leaked low-level forms\n' >&2
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
assert "Vec" in names
assert "Slice" in names
assert "vec_new" in names
assert "vec_push" in names
assert "vec_get" in names
assert "slice_get" in names
print("vec-slice: semantic index passed")
PY

cat > "$TMP/f64.weave" <<'EOF'
(program
  (name "vec-f64")
  (version "0.1")
  (entry main
    (params)
    (returns i32)
    (do
      (let v (call vec_new (type-args f64)))
      (return 0))))
EOF
set +e
"$WEAVEC" --frontend "$TMP/f64.wir" "${SOURCES[@]}" "$TMP/f64.weave" \
  >"$TMP/f64.stdout" 2>"$TMP/f64.stderr"
f64_status="$?"
set -e
if [[ "$f64_status" -eq 0 ]]; then
  printf 'vec-slice: Vec f64 was accepted\n' >&2
  exit 1
fi
[[ ! -e "$TMP/f64.wir" ]] || {
  if grep -Fq 'vec_new__s__f64' "$TMP/f64.wir"; then
    printf 'vec-slice: Vec f64 still specialized\n' >&2
    exit 1
  fi
}
grep -Fq 'Vec element type must be i32' "$TMP/f64.stderr"

if command -v llc >/dev/null 2>&1; then
  "$WEAVEC" build "${SOURCES[@]}" "$TMP/app.weave" -o "$TMP/app"
  set +e
  "$TMP/app"
  status="$?"
  set -e
  if [[ "$status" -ne 68 ]]; then
    printf 'vec-slice: expected exit 68, got %s\n' "$status" >&2
    exit 1
  fi
fi

printf 'vec-slice: passed\n'
