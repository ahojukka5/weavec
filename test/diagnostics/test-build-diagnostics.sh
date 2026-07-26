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


cat > "$TMP/wrong-arity-duplicate.weave" <<'EOF'
(program
  (name "diagnostics-wrong-arity-duplicate")
  (version "0.1")
  (entry main
    (params)
    (returns i32)
    (do
      (let valid i32 (add_i32 (const_i32 1) (const_i32 2)))
      (return (add_i32 (local_get valid))))))
EOF

set +e
"$WEAVEC" build "$TMP/wrong-arity-duplicate.weave" \
  -o "$TMP/wrong-arity-duplicate" \
  --diagnostics-json "$TMP/wrong-arity-duplicate.diagnostics.json" \
  2>"$TMP/wrong-arity-duplicate.stderr"
wrong_arity_exit="$?"
set -e
[[ "$wrong_arity_exit" -eq 11 ]] || {
  printf 'test-build-diagnostics: expected wrong-arity backend exit 11, got %s\n' \
    "$wrong_arity_exit" >&2
  exit 1
}

cat > "$TMP/duplicate-helper.weave" <<'EOF'
(program
  (name "diagnostics-duplicate-helper")
  (version "0.1")
  (fn unknown_form
    (params)
    (returns i32)
    (do (return (const_i32 7)))))
EOF

cat > "$TMP/duplicate-main.weave" <<'EOF'
(program
  (name "diagnostics-duplicate-main")
  (version "0.1")
  (entry main
    (params)
    (returns i32)
    (do (return (unknown_form 0)))))
EOF

set +e
"$WEAVEC" build "$TMP/duplicate-helper.weave" "$TMP/duplicate-main.weave" \
  -o "$TMP/duplicate-multifile" \
  --diagnostics-json "$TMP/duplicate-multifile.diagnostics.json" \
  2>"$TMP/duplicate-multifile.stderr"
duplicate_multifile_exit="$?"
set -e
[[ "$duplicate_multifile_exit" -eq 11 ]] || {
  printf 'test-build-diagnostics: expected duplicate-token backend exit 11, got %s\n' \
    "$duplicate_multifile_exit" >&2
  exit 1
}

for stderr_file in "$TMP"/*.stderr; do
  if grep -q 'kept temporary build directory' "$stderr_file"; then
    printf 'test-build-diagnostics: internal temporary directory leaked to stderr: %s\n' \
      "$stderr_file" >&2
    exit 1
  fi
done

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
assert entry["span_origin"] == "propagated-wir-location"
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
assert entry["span_origin"] == "propagated-wir-location"
assert entry["span"] is not None
source = (root / "missing-call.weave").read_bytes()
start = entry["span"]["start_byte"]
end = entry["span"]["end_byte"]
assert source[start:end] == b"helper"


wrong_arity = json.loads((root / "wrong-arity-duplicate.diagnostics.json").read_text())
assert wrong_arity["phase"] == "backend"
assert wrong_arity["exit_code"] == 11
entry = wrong_arity["diagnostics"][0]
assert entry["code"] == "backend.wrong-arity"
assert entry["span_origin"] == "propagated-wir-location"
source = (root / "wrong-arity-duplicate.weave").read_bytes()
start = entry["span"]["start_byte"]
end = entry["span"]["end_byte"]
assert source[start:end] == b"add_i32"
assert start == source.rfind(b"add_i32")

duplicate = json.loads((root / "duplicate-multifile.diagnostics.json").read_text())
assert duplicate["phase"] == "backend"
assert duplicate["exit_code"] == 11
entry = duplicate["diagnostics"][0]
assert entry["code"] == "backend.unknown-expression-operator"
assert entry["span_origin"] == "propagated-wir-location"
assert pathlib.Path(entry["source"]) == root / "duplicate-main.weave"
source = (root / "duplicate-main.weave").read_bytes()
start = entry["span"]["start_byte"]
end = entry["span"]["end_byte"]
assert source[start:end] == b"unknown_form"
PY

printf 'test-build-diagnostics: passed\n'
