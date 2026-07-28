#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() {
  printf '[weavec-test-all] %s\n' "$*"
}

log 'WIR core-version audit'
python3 "$ROOT/scripts/check_wir_core_version.py"

log 'build boundary'
"$ROOT/test/build-boundary/test.sh"

log 'self-host link policy'
bash "$ROOT/test/selfhost-link-policy/test.sh"

log 'JSON publication'
bash "$ROOT/test/json-publication/test.sh"

log 'trace publication'
bash "$ROOT/test/trace-publication/test.sh"

log 'build'
"$ROOT/build.sh"

log 'compiler version'
bash "$ROOT/test/version/test.sh"

log 'correctness'
"$ROOT/test.sh"

log 'diagnostics'
"$ROOT/test/diagnostics/test-build-diagnostics.sh"

log 'performance'
"$ROOT/test/performance/test.sh"

log 'LLVM structural quality'
"$ROOT/scripts/check-llvm-quality.sh"

log 'quantum'
"$ROOT/test/quantum/test.sh"

log 'quantum-e2e'
"$ROOT/test/quantum/test-e2e.sh"

log 'quantum-llvm'
"$ROOT/test/quantum/test-llvm.sh"

log 'trace-registry'
"$ROOT/scripts/check-trace-registry.sh"

log 'compilation-trace'
"$ROOT/test/trace/test.sh"

log 'LLVM provenance'
"$ROOT/test/llvm-provenance/test.sh"

log 'tooling artifacts'
"$ROOT/test/tooling-artifacts/test.sh"

log 'optimization evidence'
"$ROOT/test/optimization-evidence/test.sh"

log 'self-host'
"$ROOT/test/selfhost/test.sh"

log 'all weavec checks passed'
