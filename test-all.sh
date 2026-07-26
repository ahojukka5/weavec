#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() {
  printf '[weavec-test-all] %s\n' "$*"
}

log 'WIR core-version audit'
python3 "$ROOT/scripts/check_wir_core_version.py"

log 'build'
"$ROOT/build.sh"

log 'correctness'
"$ROOT/test.sh"

log 'performance'
"$ROOT/test/performance/test.sh"

log 'quantum'
"$ROOT/test/quantum/test.sh"

log 'quantum-e2e'
"$ROOT/test/quantum/test-e2e.sh"

log 'quantum-llvm'
"$ROOT/test/quantum/test-llvm.sh"

log 'compilation-trace'
"$ROOT/test/trace/test.sh"

log 'self-host'
"$ROOT/test/selfhost/test.sh"

log 'all weavec checks passed'
