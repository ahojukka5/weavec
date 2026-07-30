#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-contract-result-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

EXPECTED='weavec: surface contract: result is available only in ensures; it cannot appear in requires'

[[ -x "$WEAVEC" ]] || {
  printf 'contract-result-requires: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}

cat > "$TMP/direct.weave" <<'WEAVE'
(program
  (name "result-requires-direct")
  (version "0.1")
  (fn checked
    (params (value i32))
    (returns i32)
    (requires result)
    (do (return value)))
  (entry main
    (params)
    (returns i32)
    (do (return (call checked 42)))))
WEAVE

cat > "$TMP/nested.weave" <<'WEAVE'
(program
  (name "result-requires-nested")
  (version "0.1")
  (fn identity
    (params (value i32))
    (returns i32)
    (do (return value)))
  (fn checked
    (params (value i32))
    (returns i32)
    (requires (op greater-than (call identity result) 0))
    (do (return value)))
  (entry main
    (params)
    (returns i32)
    (do (return (call checked 42)))))
WEAVE

cat > "$TMP/ensures.weave" <<'WEAVE'
(program
  (name "result-ensures-valid")
  (version "0.1")
  (fn checked
    (params (value i32))
    (returns i32)
    (ensures (op equal result value))
    (do (return value)))
  (entry main
    (params)
    (returns i32)
    (do (return (call checked 42)))))
WEAVE

expect_frontend_failure() {
  local name="$1"
  set +e
  "$WEAVEC" --frontend "$TMP/$name.wir" "$TMP/$name.weave" \
    >"$TMP/$name.stdout" 2>"$TMP/$name.stderr"
  local status="$?"
  set -e

  [[ "$status" -ne 0 ]] || {
    printf 'contract-result-requires: %s unexpectedly succeeded\n' "$name" >&2
    exit 1
  }
  grep -Fxq "$EXPECTED" "$TMP/$name.stderr"
  [[ ! -e "$TMP/$name.wir" ]] || {
    printf 'contract-result-requires: %s left partial WIR\n' "$name" >&2
    exit 1
  }
}

expect_frontend_failure direct
expect_frontend_failure nested

"$WEAVEC" --frontend "$TMP/ensures.wir" "$TMP/ensures.weave"
grep -Fq '(eq_i32' "$TMP/ensures.wir"

set +e
"$WEAVEC" build "$TMP/nested.weave" \
  -o "$TMP/nested" \
  --diagnostics-json "$TMP/nested.diagnostics.json" \
  >"$TMP/build.stdout" 2>"$TMP/build.stderr"
status="$?"
set -e

[[ "$status" -eq 10 ]] || {
  printf 'contract-result-requires: diagnostics build returned %s instead of 10\n' \
    "$status" >&2
  exit 1
}
[[ ! -e "$TMP/nested" ]]
[[ -s "$TMP/nested.diagnostics.json" ]]
grep -Fxq "$EXPECTED" "$TMP/build.stderr"

python3 - "$TMP/nested.weave" "$TMP/nested.diagnostics.json" "$EXPECTED" <<'PY'
import json
import pathlib
import sys

source_path = pathlib.Path(sys.argv[1])
diagnostics_path = pathlib.Path(sys.argv[2])
expected_message = sys.argv[3]
source = source_path.read_bytes()
document = json.loads(diagnostics_path.read_text(encoding="utf-8"))

assert document["format"] == "weavec-diagnostics-v1"
assert document["status"] == "failed"
assert document["phase"] == "frontend"
assert document["exit_code"] == 10
assert len(document["diagnostics"]) == 1

diagnostic = document["diagnostics"][0]
assert diagnostic["code"] == "frontend.contract.result-in-requires"
assert diagnostic["message"] == expected_message
assert pathlib.Path(diagnostic["source"]) == source_path
assert diagnostic["span_origin"] == "compiler-semantic"
assert diagnostic["analysis_complete"] is True
assert diagnostic["operand_role"] == "requires"
assert diagnostic["candidates"] == []
assert diagnostic["related_locations"] == []
assert diagnostic["repairs"] == []

span = diagnostic["span"]
assert span is not None
text = source[span["start_byte"] : span["end_byte"]]
assert text == b"(requires (op greater-than (call identity result) 0))"
PY

printf 'contract-result-requires: explicit diagnostics passed\n'
