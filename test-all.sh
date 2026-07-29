#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() {
  printf '[weavec-test-all] %s\n' "$*"
}

log 'WIR core-version audit'
python3 "$ROOT/scripts/check_wir_core_version.py"

log 'compiler source manifest'
bash "$ROOT/test/compiler-sources/test.sh"

log 'self-host fixed-point verifier'
bash "$ROOT/test/selfhost-fixed-point/test.sh"

log 'surface semantic storage'
bash "$ROOT/test/surface-symbols/test.sh"

log 'build boundary'
bash "$ROOT/test/build-boundary/test.sh"

log 'self-host link policy'
bash "$ROOT/test/selfhost-link-policy/test.sh"

log 'JSON publication'
bash "$ROOT/test/json-publication/test.sh"

log 'trace publication'
bash "$ROOT/test/trace-publication/test.sh"

log 'manifest publication'
bash "$ROOT/test/manifest-publication/test.sh"

log 'diagnostics publication'
bash "$ROOT/test/diagnostics-publication/test.sh"

log 'build'
bash "$ROOT/build.sh"

log 'compiler version'
bash "$ROOT/test/version/test.sh"

log 'correctness'
bash "$ROOT/test.sh"

log 'surface elaboration'
bash "$ROOT/test/surface-elaboration/test.sh"

log 'diagnostics'
bash "$ROOT/test/diagnostics/test-build-diagnostics.sh"

log 'performance'
bash "$ROOT/test/performance/test.sh"

log 'LLVM structural quality'
bash "$ROOT/scripts/check-llvm-quality.sh"

log 'quantum'
bash "$ROOT/test/quantum/test.sh"

log 'quantum-e2e'
bash "$ROOT/test/quantum/test-e2e.sh"

log 'quantum-llvm'
bash "$ROOT/test/quantum/test-llvm.sh"

log 'trace-registry'
bash "$ROOT/scripts/check-trace-registry.sh"

log 'compilation-trace'
bash "$ROOT/test/trace/test.sh"

log 'LLVM provenance'
bash "$ROOT/test/llvm-provenance/test.sh"

log 'tooling artifacts'
bash "$ROOT/test/tooling-artifacts/test.sh"

log 'optimization evidence'
bash "$ROOT/test/optimization-evidence/test.sh"

log 'self-host'
bash "$ROOT/test/selfhost/test.sh"

log 'all weavec checks passed'
