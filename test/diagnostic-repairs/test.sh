#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-diagnostic-repairs-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'diagnostic-repairs: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}

cat > "$TMP/unresolved.weave" <<'WEAVE'
(program
  (name "diagnostic-unresolved")
  (version "0.1")
  (entry main
    (params)
    (returns i32)
    (do (return (call missing 42)))))
WEAVE

cat > "$TMP/wrong-arity.weave" <<'WEAVE'
(program
  (name "diagnostic-wrong-arity")
  (version "0.1")
  (fn add-two
    (params (left i32) (right i32))
    (returns i32)
    (do (return (op add left right))))
  (entry main
    (params)
    (returns i32)
    (do (return (call add-two 40)))))
WEAVE

cat > "$TMP/argument-type.weave" <<'WEAVE'
(program
  (name "diagnostic-argument-type")
  (version "0.1")
  (fn consume
    (params (value i32))
    (returns i32)
    (do (return value)))
  (entry main
    (params)
    (returns i32)
    (do
      (let wide i64 42)
      (return (call consume wide)))))
WEAVE

cat > "$TMP/operator-type.weave" <<'WEAVE'
(program
  (name "diagnostic-operator-type")
  (version "0.1")
  (entry main
    (params)
    (returns i32)
    (do
      (let wide i64 2)
      (return (op add (const_i32 40) wide)))))
WEAVE

cat > "$TMP/invalid-cast.weave" <<'WEAVE'
(program
  (name "diagnostic-invalid-cast")
  (version "0.1")
  (entry main
    (params)
    (returns i32)
    (do (return (cast ptr (const_i32 1))))))
WEAVE

run_failure() {
  local name="$1"
  set +e
  "$WEAVEC" build "$TMP/$name.weave" \
    -o "$TMP/$name" \
    --diagnostics-json "$TMP/$name.diagnostics.json" \
    2>"$TMP/$name.stderr"
  local status="$?"
  set -e
  if [[ "$status" -ne 10 ]]; then
    printf 'diagnostic-repairs: %s returned %s instead of 10\n' \
      "$name" "$status" >&2
    exit 1
  fi
  [[ ! -e "$TMP/$name" ]] || {
    printf 'diagnostic-repairs: %s published an executable\n' "$name" >&2
    exit 1
  }
  grep -Fq 'weavec: surface' "$TMP/$name.stderr"
  if grep -Fq 'weavec-semantic-diagnostic' "$TMP/$name.stderr"; then
    printf 'diagnostic-repairs: private sidecar path leaked for %s\n' "$name" >&2
    exit 1
  fi
}

for name in unresolved wrong-arity argument-type operator-type invalid-cast; do
  run_failure "$name"
done

set +e
"$WEAVEC" build "$TMP/unresolved.weave" \
  -o "$TMP/unresolved-second" \
  --diagnostics-json "$TMP/unresolved-second.diagnostics.json" \
  2>"$TMP/unresolved-second.stderr"
status="$?"
set -e
[[ "$status" -eq 10 ]]

python3 -m py_compile "$ROOT/test/diagnostic-repairs/verify.py"
python3 "$ROOT/test/diagnostic-repairs/verify.py" \
  "$TMP" "$ROOT/docs/schemas/weavec-diagnostics-v1.schema.json"

printf 'diagnostic-repairs: semantic context and repairs passed\n'
