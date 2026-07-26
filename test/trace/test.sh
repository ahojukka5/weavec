#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-trace-test-XXXXXX")"
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'test-compilation-trace: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}
command -v clang >/dev/null 2>&1 || {
  printf 'test-compilation-trace: clang is required\n' >&2
  exit 1
}
command -v python3 >/dev/null 2>&1 || {
  printf 'test-compilation-trace: python3 is required\n' >&2
  exit 1
}

cat > "$TMP/library.weave" <<'WEAVE'
(program
  (name "trace-library")
  (version "0.1")
  (fn checked
    (params (x i32))
    (returns i32)
    (requires (ge_i32 x (const_i32 0)))
    (ensures (eq_i32 result x))
    (do (return x))))
WEAVE

cat > "$TMP/main.weave" <<'WEAVE'
(program
  (name "trace-main")
  (version "0.1")
  (extern qrt_ry (params (q i64) (theta i64)) (returns void))
  (extern qrt_rz (params (q i64) (theta i64)) (returns void))
  (extern qrt_x (params (q i64)) (returns void))
  (extern qrt_z (params (q i64)) (returns void))
  (extern qrt_measure (params (q i64)) (returns i32))
  (entry main
    (params)
    (returns i32)
    (do
      (let q0 Qubit 0)
      (qgate H q0)
      (qgate X q0)
      (qgate X q0)
      (qgate Z q0)
      (qmeasure q0 measured)
      (let answer i32 42)
      (return (call_i32 checked (local_get answer))))))
WEAVE

cat > "$TMP/runtime.c" <<'C'
#include <unistd.h>

void weave_rt_contract_fail(const char *message) {
    (void)message;
    _exit(99);
}

void qrt_ry(long qubit, long angle) {
    (void)qubit;
    (void)angle;
}

void qrt_rz(long qubit, long angle) {
    (void)qubit;
    (void)angle;
}

void qrt_x(long qubit) {
    (void)qubit;
}

void qrt_z(long qubit) {
    (void)qubit;
}

int qrt_measure(long qubit) {
    (void)qubit;
    return 0;
}
C
clang -c "$TMP/runtime.c" -o "$TMP/runtime.o"

build_trace() {
  local output="$1"
  local trace="$2"
  shift 2
  "$WEAVEC" build "$TMP/library.weave" "$TMP/main.weave" \
    -o "$output" \
    --runtime "$TMP/runtime.o" \
    --trace-json "$trace" \
    "$@"
}

build_trace "$TMP/program" "$TMP/trace.json" \
  --diagnostics-json "$TMP/diagnostics.json"
build_trace "$TMP/program-second" "$TMP/trace-second.json"

set +e
"$TMP/program"
program_status="$?"
set -e
[[ "$program_status" -eq 42 ]] || {
  printf 'test-compilation-trace: expected exit 42, got %s\n' \
    "$program_status" >&2
  exit 1
}

cmp "$TMP/trace.json" "$TMP/trace-second.json"

python3 - "$TMP" "$ROOT/test/trace/expected-actions.txt" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
expected_actions = pathlib.Path(sys.argv[2])
source_paths = [root / "library.weave", root / "main.weave"]
sources = [path.read_bytes() for path in source_paths]
trace = json.loads((root / "trace.json").read_text(encoding="utf-8"))

assert trace["format"] == "weavec-compilation-trace-v1"
assert trace["status"] == "succeeded"
assert trace["phase"] == "complete"
assert trace["sources"] == [str(path) for path in source_paths]
assert trace["events"]

actions = {}
for event in trace["events"]:
    index = event["source_index"]
    assert index in (0, 1)
    assert event["source"] == str(source_paths[index])
    span = event["span"]
    start = span["start_byte"]
    end = span["end_byte"]
    assert 0 <= start < end <= len(sources[index])
    assert sources[index][start:end].decode("utf-8") == event["surface"]
    assert event["surface"] != "("
    actions.setdefault(event["action"], []).append(event)

required = {
    line.strip()
    for line in expected_actions.read_text(encoding="utf-8").splitlines()
    if line.strip()
}
assert required <= actions.keys()

for action in ("insert-requires-check", "insert-ensures-check"):
    assert all(event["source_index"] == 0 for event in actions[action])
for action in required - {"insert-requires-check", "insert-ensures-check"}:
    assert all(event["source_index"] == 1 for event in actions[action])

assert actions["insert-requires-check"][0]["surface"].startswith("(requires ")
assert actions["insert-ensures-check"][0]["surface"].startswith("(ensures ")
assert actions["decompose-h-to-rz-ry"][0]["surface"] == "(qgate H q0)"
assert actions["cancel-self-inverse-pair"][0]["surface"] == (
    "(qgate X q0)\n      (qgate X q0)"
)
assert actions["lower-gate-to-runtime-call"][0]["detail"] == "Z"
assert actions["lower-measurement-to-runtime-call"][0]["detail"] == "q0"

successful_diagnostics = json.loads(
    (root / "diagnostics.json").read_text(encoding="utf-8")
)
assert successful_diagnostics["status"] == "succeeded"
assert successful_diagnostics["diagnostics"] == []
PY

cat > "$TMP/unclosed.weave" <<'WEAVE'
(program
  (name "trace-unclosed")
WEAVE
set +e
"$WEAVEC" build "$TMP/unclosed.weave" \
  -o "$TMP/unclosed" \
  --runtime "$TMP/runtime.o" \
  --trace-json "$TMP/unclosed.trace.json" \
  --diagnostics-json "$TMP/unclosed.diagnostics.json" \
  2>"$TMP/unclosed.stderr"
unclosed_status="$?"
set -e
[[ "$unclosed_status" -eq 10 ]] || {
  printf 'test-compilation-trace: expected frontend exit 10, got %s\n' \
    "$unclosed_status" >&2
  exit 1
}
[[ ! -e "$TMP/unclosed" ]]

python3 - "$TMP/unclosed.trace.json" <<'PY'
import json
import pathlib
import sys

document = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
assert document["format"] == "weavec-compilation-trace-v1"
assert document["status"] == "failed"
assert document["phase"] == "frontend"
assert document["events"] == []
PY

printf 'preserve-me\n' > "$TMP/preserved-output"
set +e
build_trace "$TMP/preserved-output" "$TMP/missing/trace.json" \
  2>"$TMP/trace-write.stderr"
trace_write_status="$?"
set -e
[[ "$trace_write_status" -ne 0 ]] || {
  printf 'test-compilation-trace: unwritable trace unexpectedly succeeded\n' >&2
  exit 1
}
[[ "$(cat "$TMP/preserved-output")" == "preserve-me" ]] || {
  printf 'test-compilation-trace: trace failure replaced existing output\n' >&2
  exit 1
}

set +e
"$WEAVEC" build "$TMP/main.weave" \
  -o "$TMP/conflict" \
  --runtime "$TMP/runtime.o" \
  --trace-json "$TMP/conflict" \
  2>"$TMP/conflict.stderr"
conflict_status="$?"
set -e
[[ "$conflict_status" -eq 2 ]] || {
  printf 'test-compilation-trace: expected conflict exit 2, got %s\n' \
    "$conflict_status" >&2
  exit 1
}
[[ ! -e "$TMP/conflict" ]]

printf 'test-compilation-trace: passed\n'
