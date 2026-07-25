#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-diagnostics-test-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'test-build-diagnostics: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}
command -v python3 >/dev/null 2>&1 || {
  printf 'test-build-diagnostics: python3 is required\n' >&2
  exit 1
}

cat > "$TMP/good.weave" <<'EOF'
(program
  (name "diagnostics-good")
  (version "0.1")
  (entry main
    (params)
    (returns i32)
    (do (return (const_i32 42)))))
EOF

"$WEAVEC" build "$TMP/good.weave" \
  -o "$TMP/good" \
  --diagnostics-json "$TMP/good.diagnostics.json" \
  --manifest-json "$TMP/good.manifest.json"
set +e
"$TMP/good"
good_exit="$?"
set -e
[[ "$good_exit" -eq 42 ]] || {
  printf 'test-build-diagnostics: expected executable exit 42, got %s\n' "$good_exit" >&2
  exit 1
}

cat > "$TMP/unclosed.weave" <<'EOF'
(program
  (name "diagnostics-unclosed")
EOF

set +e
"$WEAVEC" build "$TMP/unclosed.weave" \
  -o "$TMP/unclosed" \
  --diagnostics-json "$TMP/unclosed.diagnostics.json" \
  2>"$TMP/unclosed.stderr"
unclosed_exit="$?"
set -e
[[ "$unclosed_exit" -eq 10 ]] || {
  printf 'test-build-diagnostics: expected frontend exit 10, got %s\n' "$unclosed_exit" >&2
  exit 1
}
[[ ! -e "$TMP/unclosed" ]] || {
  printf 'test-build-diagnostics: parse failure published an executable\n' >&2
  exit 1
}

cat > "$TMP/unknown.weave" <<'EOF'
(program
  (name "diagnostics-unknown")
  (version "0.1")
  (entry main
    (params)
    (returns i32)
    (do (return (unknown_form 0)))))
EOF

set +e
"$WEAVEC" build "$TMP/unknown.weave" \
  -o "$TMP/unknown" \
  --diagnostics-json "$TMP/unknown.diagnostics.json" \
  2>"$TMP/unknown.stderr"
unknown_exit="$?"
set -e
[[ "$unknown_exit" -eq 11 ]] || {
  printf 'test-build-diagnostics: expected backend exit 11, got %s\n' "$unknown_exit" >&2
  exit 1
}
[[ ! -e "$TMP/unknown" ]] || {
  printf 'test-build-diagnostics: backend failure published an executable\n' >&2
  exit 1
}

cat > "$TMP/missing-call.weave" <<'EOF'
(program
  (name "diagnostics-missing-call")
  (version "0.1")
  (entry main
    (params)
    (returns i32)
    (do
      (return
        (call_i32 helper
          (const_i32 41))))))
EOF

set +e
"$WEAVEC" build "$TMP/missing-call.weave" \
  -o "$TMP/missing-call" \
  --diagnostics-json "$TMP/missing-call.diagnostics.json" \
  2>"$TMP/missing-call.stderr"
missing_call_exit="$?"
set -e
[[ "$missing_call_exit" -eq 11 ]] || {
  printf 'test-build-diagnostics: expected unresolved-call backend exit 11, got %s\n' \
    "$missing_call_exit" >&2
  exit 1
}
[[ ! -e "$TMP/missing-call" ]] || {
  printf 'test-build-diagnostics: unresolved call published an executable\n' >&2
  exit 1
}

python3 - "$TMP" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])

good = json.loads((root / "good.diagnostics.json").read_text())
assert good == {
    "format": "weavec-diagnostics-v1",
    "status": "succeeded",
    "phase": "complete",
    "exit_code": 0,
    "raw_exit_code": 0,
    "diagnostics": [],
}

unclosed = json.loads((root / "unclosed.diagnostics.json").read_text())
assert unclosed["format"] == "weavec-diagnostics-v1"
assert unclosed["status"] == "failed"
assert unclosed["phase"] == "frontend"
assert unclosed["exit_code"] == 10
entry = unclosed["diagnostics"][0]
assert entry["code"] == "frontend.parse.unclosed-list"
assert entry["span_origin"] == "compiler-preflight"
assert entry["span"]["start_byte"] == 0
assert entry["span"]["end_byte"] == 1
assert entry["span"]["start_line"] == 1
assert entry["span"]["start_column"] == 1

unknown = json.loads((root / "unknown.diagnostics.json").read_text())
assert unknown["format"] == "weavec-diagnostics-v1"
assert unknown["status"] == "failed"
assert unknown["phase"] == "backend"
assert unknown["exit_code"] == 11
entry = unknown["diagnostics"][0]
assert entry["code"] == "backend.unknown-expression-operator"
assert entry["message"] == "unknown expression operator: unknown_form"
assert entry["span_origin"] == "inferred-unique-token"
assert entry["span"] is not None
source = (root / "unknown.weave").read_bytes()
start = entry["span"]["start_byte"]
end = entry["span"]["end_byte"]
assert source[start:end] == b"unknown_form"

missing_call = json.loads((root / "missing-call.diagnostics.json").read_text())
assert missing_call["format"] == "weavec-diagnostics-v1"
assert missing_call["status"] == "failed"
assert missing_call["phase"] == "backend"
assert missing_call["exit_code"] == 11
entry = missing_call["diagnostics"][0]
assert entry["code"] == "backend.unknown-identifier"
assert entry["message"] == "unknown identifier: helper"
assert entry["span_origin"] == "inferred-unique-token"
assert entry["span"] is not None
source = (root / "missing-call.weave").read_bytes()
start = entry["span"]["start_byte"]
end = entry["span"]["end_byte"]
assert source[start:end] == b"helper"
PY

printf 'test-build-diagnostics: passed\n'
