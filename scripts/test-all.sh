#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ "$(basename "$SCRIPT_DIR")" == scripts ]]; then
  ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
else
  ROOT="$SCRIPT_DIR"
fi

RUN_BUILD=1
for arg in "$@"; do
  case "$arg" in
    --no-build) RUN_BUILD=0 ;;
    -h|--help)
      cat <<'EOF'
usage: scripts/test-all.sh [--no-build]

Run the complete weavec test ladder. By default the final compiler is rebuilt
from published lower-stage SDKs first. Use --no-build to test an existing
build/weavec without touching dependency or compiler build products.
EOF
      exit 0
      ;;
    *)
      printf 'test-all: unknown argument: %s\n' "$arg" >&2
      exit 2
      ;;
  esac
done

log() {
  printf '[weavec-test-all] %s\n' "$*"
}

log 'WIR core-version audit'
python3 "$ROOT/scripts/check_wir_core_version.py"

log 'WIR next source-location fixtures'
python3 "$ROOT/scripts/check_wir_next_source_locations.py"

log 'WIR next source-location views'
python3 "$ROOT/scripts/wir_next_source_views.py" self-test

log 'WIR next available source bytes'
python3 "$ROOT/scripts/check_wir_next_source_bytes.py"

log 'compiler source manifest'
bash "$ROOT/test/compiler-sources/test.sh"

log 'self-host fixed-point verifier'
bash "$ROOT/test/selfhost-fixed-point/test.sh"

log 'surface semantic storage'
bash "$ROOT/test/surface-symbols/test.sh"

log 'semantic-index contract'
bash "$ROOT/test/semantic-index-contract/test.sh"

log 'build boundary'
bash "$ROOT/test/build-boundary/test.sh"

log 'development entrypoints'
bash "$ROOT/test/development-entrypoints/test.sh"

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

if (( RUN_BUILD )); then
  log 'build from published SDKs'
  bash "$ROOT/scripts/build.sh"
else
  log 'build skipped (--no-build)'
  [[ -x "$ROOT/build/weavec" ]] || {
    printf '[weavec-test-all] build/weavec not found for --no-build\n' >&2
    exit 1
  }
fi

log 'compiler version'
bash "$ROOT/test/version/test.sh"

log 'compiler capabilities'
bash "$ROOT/test/capabilities/test.sh"

log 'semantic-index emitter'
bash "$ROOT/test/semantic-index/test.sh"

log 'semantic-index module ordering'
bash "$ROOT/test/semantic-index-module-order/test.sh"

log 'canonical formatter'
bash "$ROOT/test/formatter/test.sh"

log 'correctness'
bash "$ROOT/test.sh"

log 'backend call validation'
bash "$ROOT/test/backend-call-validation/test.sh"

log 'surface elaboration'
bash "$ROOT/test/surface-elaboration/test.sh"

log 'contract result diagnostics'
bash "$ROOT/test/contract-result-requires/test.sh"

log 'struct layout'
bash "$ROOT/test/struct-layout/test.sh"

log 'semantic structs'
bash "$ROOT/test/semantic-structs/test.sh"

log 'module interfaces'
bash "$ROOT/test/modules/test.sh"

log 'module diagnostics'
bash "$ROOT/test/module-diagnostics/test.sh"

log 'module collision diagnostics'
bash "$ROOT/test/module-collisions/test.sh"

log 'module struct identities'
bash "$ROOT/test/module-structs/test.sh"

log 'module symbol names'
bash "$ROOT/test/module-symbols/test.sh"

log 'diagnostics'
bash "$ROOT/test/diagnostics/test-build-diagnostics.sh"

log 'diagnostic repairs'
bash "$ROOT/test/diagnostic-repairs/test.sh"

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
