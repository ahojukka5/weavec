#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Option and Result helpers (#242). Predicates and unwrap-or are generic
# functions over match. They specialize for i32 and do not abort.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-option-helpers-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'option-helpers: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}

OPTION="$ROOT/stdlib/option.weave"
RESULT="$ROOT/stdlib/result.weave"

cat > "$TMP/app.weave" <<'EOF'
(program
  (name "helpers")
  (version "0.1")
  (entry main
    (params)
    (returns i32)
    (do
      (let some (type-app Option i32) (variant Option (type-args i32) Some 4))
      (let none (type-app Option i32) (variant Option (type-args i32) None))
      (let ok (type-app Result i32 i32) (variant Result (type-args i32 i32) Ok 5))
      (let err (type-app Result i32 i32) (variant Result (type-args i32 i32) Err 1))
      (if
        (condition (op not (call option_is_some (type-args i32) some)))
        (then (do (return 10))))
      (if
        (condition (op not (call option_is_none (type-args i32) none)))
        (then (do (return 11))))
      (if
        (condition (op not (call result_is_ok (type-args i32 i32) ok)))
        (then (do (return 12))))
      (if
        (condition (op not (call result_is_err (type-args i32 i32) err)))
        (then (do (return 13))))
      (let a i32 (call option_unwrap_or (type-args i32) some 0))
      (let b i32 (call option_unwrap_or (type-args i32) none 2))
      (let c i32 (call result_unwrap_or (type-args i32 i32) ok 0))
      (let d i32 (call result_unwrap_or (type-args i32 i32) err 3))
      (return (op add (op add a b) (op add c d))))))
EOF

"$WEAVEC" --frontend "$TMP/app.wir" "$OPTION" "$RESULT" "$TMP/app.weave" \
  2>"$TMP/app.stderr" || {
  printf 'option-helpers: app rejected\n' >&2
  cat "$TMP/app.stderr" >&2
  exit 1
}

for needle in \
  '(fn option_is_some__s__i32' \
  '(fn option_is_none__s__i32' \
  '(fn option_unwrap_or__s__i32' \
  '(fn result_is_ok__s__i32__i32' \
  '(fn result_is_err__s__i32__i32' \
  '(fn result_unwrap_or__s__i32__i32'; do
  if ! grep -Fq "$needle" "$TMP/app.wir"; then
    printf 'option-helpers: missing %s\n' "$needle" >&2
    cat "$TMP/app.wir" >&2
    exit 1
  fi
done

if grep -Eq '^\s+\(fn option_is_some ' "$TMP/app.wir"; then
  printf 'option-helpers: generic option helper was emitted\n' >&2
  exit 1
fi
if grep -Eq '^\s+\(fn result_is_ok ' "$TMP/app.wir"; then
  printf 'option-helpers: generic result helper was emitted\n' >&2
  exit 1
fi

if grep -Eq '\bptr\b|\bextern\b|call_(i32|i64|ptr|void)|const_|ptr_add|load_|store_|weave_rt_' \
    "$TMP/app.weave"; then
  printf 'option-helpers: application source leaked low-level forms\n' >&2
  exit 1
fi

"$WEAVEC" analyze "$OPTION" "$RESULT" "$TMP/app.weave" \
  --semantic-index-json "$TMP/app.index.json"
python3 - "$TMP/app.index.json" <<'PY'
import json
import pathlib
import sys

doc = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
assert doc["analysis"]["status"] == "complete"
names = {item["name"] for item in doc["symbols"]}
assert "option_is_some" in names
assert "result_unwrap_or" in names
print("option-helpers: semantic index passed")
PY

if command -v llc >/dev/null 2>&1; then
  "$WEAVEC" build "$OPTION" "$RESULT" "$TMP/app.weave" -o "$TMP/app"
  set +e
  "$TMP/app"
  status="$?"
  set -e
  if [[ "$status" -ne 14 ]]; then
    printf 'option-helpers: expected exit 14, got %s\n' "$status" >&2
    exit 1
  fi
fi

printf 'option-helpers: passed\n'
