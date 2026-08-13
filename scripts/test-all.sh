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

log 'project manifest version 1'
python3 "$ROOT/scripts/check_project_manifest_spec.py"

log 'compiler source manifest'
bash "$ROOT/test/compiler-sources/test.sh"

log 'self-host fixed-point verifier'
bash "$ROOT/test/selfhost-fixed-point/test.sh"

log 'surface semantic storage'
bash "$ROOT/test/surface-symbols/test.sh"

log 'semantic-index contract'
bash "$ROOT/test/semantic-index-contract/test.sh"

log 'project protocol contract'
bash "$ROOT/test/project-protocol-contract/test.sh"

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

log 'structured semantic type graph'
bash "$ROOT/test/semantic-type-graph/test.sh"

log 'public project acceptance'
bash "$ROOT/test/project-acceptance/test.sh"

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

log 'floating-point arithmetic'
bash "$ROOT/test/float-arithmetic/test.sh"

log 'process arguments'
bash "$ROOT/test/process-arguments/test.sh"

log 'floating-point text parsing'
bash "$ROOT/test/parse-f64/test.sh"

log 'floating-point square root'
bash "$ROOT/test/sqrt-f64/test.sh"

log 'trigonometric math'
bash "$ROOT/test/trigonometry-math/test.sh"

log 'fixed-six floating output'
bash "$ROOT/test/fixed-f64-output/test.sh"

log 'trigonometry table'
bash "$ROOT/test/trigonometry-table/test.sh"

log 'standard error output'
bash "$ROOT/test/io-stderr/test.sh"

log 'Pythagorean command-line program'
bash "$ROOT/test/pythagoras/test.sh"

log 'three-dimensional vector dot product'
bash "$ROOT/test/vector-dot/test.sh"

log 'vector lengths and angle'
bash "$ROOT/test/vector-geometry/test.sh"

log '3x3 matrix-vector multiplication'
bash "$ROOT/test/matrix-vector/test.sh"

log 'descriptive statistics'
bash "$ROOT/test/statistics/test.sh"

log 'quadratic equation solver'
bash "$ROOT/test/quadratic/test.sh"

log 'projectile motion'
bash "$ROOT/test/projectile-motion/test.sh"

log 'Newton square root'
bash "$ROOT/test/newton-root/test.sh"

log 'file-based numeric summary'
bash "$ROOT/test/file-statistics/test.sh"

log 'contract result diagnostics'
bash "$ROOT/test/contract-result-requires/test.sh"

log 'struct layout'
bash "$ROOT/test/struct-layout/test.sh"

log 'semantic structs'
bash "$ROOT/test/semantic-structs/test.sh"

log 'module diagnostics'
bash "$ROOT/test/module-diagnostics/test.sh"

log 'module collision diagnostics'
bash "$ROOT/test/module-collisions/test.sh"

log 'module struct identities'
bash "$ROOT/test/module-structs/test.sh"

log 'module symbol names'
bash "$ROOT/test/module-symbols/test.sh"

log 'parse diagnostics'
bash "$ROOT/test/parse-diagnostics/test.sh"

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
