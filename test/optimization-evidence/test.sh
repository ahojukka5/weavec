#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-optimization-evidence-XXXXXX")"
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'optimization-evidence: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}
command -v llvm-as >/dev/null 2>&1 || {
  printf 'optimization-evidence: llvm-as is required\n' >&2
  exit 1
}
command -v llc >/dev/null 2>&1 || {
  printf 'optimization-evidence: llc is required\n' >&2
  exit 1
}
command -v llvm-objdump >/dev/null 2>&1 || {
  printf 'optimization-evidence: llvm-objdump is required\n' >&2
  exit 1
}

SOURCE="$ROOT/test/optimization-evidence/fibonacci.weave"
RUNTIME_ARGS=()
if [[ -f "$ROOT/runtime/program.c" ]]; then
  RUNTIME_ARGS=(--runtime "$ROOT/runtime/program.c")
fi

mkdir -p "$TMP/o3-native"
"$WEAVEC" build "$SOURCE" -o "$TMP/o3-native/fibonacci" \
  "${RUNTIME_ARGS[@]}" \
  -O3 --native \
  --emit-wir "$TMP/o3-native/fibonacci.wir" \
  --emit-llvm "$TMP/o3-native/fibonacci.raw.ll" \
  --emit-optimized-llvm "$TMP/o3-native/fibonacci.optimized.ll" \
  --emit-assembly "$TMP/o3-native/fibonacci.s" \
  --emit-disassembly "$TMP/o3-native/fibonacci.disasm" \
  --optimization-record "$TMP/o3-native/fibonacci.opt.yaml" \
  --manifest-json "$TMP/o3-native/fibonacci.build.json" \
  --diagnostics-json "$TMP/o3-native/fibonacci.diagnostics.json" \
  --llvm-provenance

set +e
"$TMP/o3-native/fibonacci"
status=$?
set -e
[[ "$status" -eq 55 ]]

for artifact in \
  fibonacci.wir \
  fibonacci.raw.ll \
  fibonacci.optimized.ll \
  fibonacci.s \
  fibonacci.disasm \
  fibonacci.opt.yaml \
  fibonacci.build.json \
  fibonacci.diagnostics.json; do
  [[ -s "$TMP/o3-native/$artifact" ]] || {
    printf 'optimization-evidence: missing artifact: %s\n' "$artifact" >&2
    exit 1
  }
done

llvm-as "$TMP/o3-native/fibonacci.raw.ll" -o "$TMP/raw.bc"
llvm-as "$TMP/o3-native/fibonacci.optimized.ll" -o "$TMP/optimized.bc"

grep -q '^; weave.source kind=function ' "$TMP/o3-native/fibonacci.raw.ll"
grep -q '^define internal .*@fib' "$TMP/o3-native/fibonacci.raw.ll"
! grep -q '^define .*@fib' "$TMP/o3-native/fibonacci.optimized.ll"
! grep -Eq '^_?fib:' "$TMP/o3-native/fibonacci.s"
! grep -Eq '<_?fib>:' "$TMP/o3-native/fibonacci.disasm"
! grep -Eq '<_?weave_rt_contract_fail>:' "$TMP/o3-native/fibonacci.disasm"
grep -q '^# weavec optimization stage: llvm-ir' "$TMP/o3-native/fibonacci.opt.yaml"
grep -q '^# weavec optimization stage: target-codegen' "$TMP/o3-native/fibonacci.opt.yaml"

python3 - "$TMP/o3-native/fibonacci.build.json" <<'PY'
import json
import pathlib
import sys

document = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
assert document["format"] == "weavec-build-manifest-v1"
assert document["status"] == "succeeded"
assert document["phase"] == "complete"
assert document["optimization"] == {
    "level": "O3",
    "cpu": "native",
    "tune_cpu": "native",
}
assert document["optimizer"] == "clang"
assert document["codegen"] == "llc"
assert document["objdump"] == "llvm-objdump"
PY

# The optimizer must simplify at least one raw structural pattern in this
# fixture. This proves that the optimized artifact is not merely a copy.
raw_instructions="$(grep -Ec '^  (%[^ ]+ = )?(alloca|load|store|add|br|phi|icmp|ret|call)\b' \
  "$TMP/o3-native/fibonacci.raw.ll")"
optimized_instructions="$(grep -Ec '^  (%[^ ]+ = )?(alloca|load|store|add|br|phi|icmp|ret|call)\b' \
  "$TMP/o3-native/fibonacci.optimized.ll")"
[[ "$optimized_instructions" -lt "$raw_instructions" ]] || {
  printf 'optimization-evidence: O3 did not simplify Fibonacci (%s -> %s)\n' \
    "$raw_instructions" "$optimized_instructions" >&2
  exit 1
}

# The default profile is portable O2 and records no host-specific CPU request.
"$WEAVEC" build "$ROOT/test/correctness/surface/01_return_42.weave" \
  -o "$TMP/default-program" \
  "${RUNTIME_ARGS[@]}" \
  --manifest-json "$TMP/default.build.json"
python3 - "$TMP/default.build.json" <<'PY'
import json
import pathlib
import sys

document = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
assert document["optimization"] == {
    "level": "O2",
    "cpu": None,
    "tune_cpu": None,
}
PY

# Raw LLVM is published before optimization. A failed optimizer must retain it
# while leaving later-stage artifacts and the executable unpublished.
printf 'old-optimized\n' > "$TMP/failure.optimized.ll"
set +e
"$WEAVEC" build "$ROOT/test/correctness/surface/01_return_42.weave" \
  -o "$TMP/failure-program" \
  "${RUNTIME_ARGS[@]}" \
  --optimizer false \
  --emit-llvm "$TMP/failure.raw.ll" \
  --emit-optimized-llvm "$TMP/failure.optimized.ll" \
  --diagnostics-json "$TMP/failure.diagnostics.json" \
  >/dev/null 2>&1
status=$?
set -e
[[ "$status" -eq 12 ]]
grep -q '^define i32 @main()' "$TMP/failure.raw.ll"
[[ "$(cat "$TMP/failure.optimized.ll")" == 'old-optimized' ]]
[[ ! -e "$TMP/failure-program" ]]
python3 - "$TMP/failure.diagnostics.json" <<'PY'
import json
import pathlib
import sys

document = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
assert document["phase"] == "optimize"
assert document["exit_code"] == 12
assert document["diagnostics"][0]["code"] == "codegen.optimize-failed"
PY

# Target code generation consumes the published optimized module. A codegen
# failure leaves raw and optimized LLVM available but publishes no executable.
set +e
"$WEAVEC" build "$ROOT/test/correctness/surface/01_return_42.weave" \
  -o "$TMP/codegen-failure-program" \
  "${RUNTIME_ARGS[@]}" \
  --target-codegen false \
  --emit-llvm "$TMP/codegen-failure.raw.ll" \
  --emit-optimized-llvm "$TMP/codegen-failure.optimized.ll" \
  --diagnostics-json "$TMP/codegen-failure.diagnostics.json" \
  >/dev/null 2>&1
status=$?
set -e
[[ "$status" -eq 12 ]]
[[ -s "$TMP/codegen-failure.raw.ll" ]]
[[ -s "$TMP/codegen-failure.optimized.ll" ]]
[[ ! -e "$TMP/codegen-failure-program" ]]
python3 - "$TMP/codegen-failure.diagnostics.json" <<'PY'
import json
import pathlib
import sys

document = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
assert document["phase"] == "codegen"
assert document["exit_code"] == 12
assert document["diagnostics"][0]["code"] == "codegen.failed"
PY

# Every requested output path, including the new evidence artifacts, is unique.
set +e
"$WEAVEC" build "$ROOT/test/correctness/surface/01_return_42.weave" \
  -o "$TMP/conflict" \
  "${RUNTIME_ARGS[@]}" \
  --emit-optimized-llvm "$TMP/conflict" \
  --diagnostics-json "$TMP/conflict.json" \
  >/dev/null 2>&1
status=$?
set -e
[[ "$status" -eq 2 ]]
[[ ! -e "$TMP/conflict" ]]
grep -q 'driver.conflicting-output-paths' "$TMP/conflict.json"

printf 'optimization-evidence: passed (%s -> %s structural instructions)\n' \
  "$raw_instructions" "$optimized_instructions"
