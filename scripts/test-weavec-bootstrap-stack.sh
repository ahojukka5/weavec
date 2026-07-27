#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

WEAVEC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BOOTSTRAP_CAT="$WEAVEC_DIR/build/vendor/weavec-bootstrap/weavec-bootstrap-cat.sh"
OUT="/tmp/weavec-bootstrap-stack-test.wir"

SOURCES=(
  src/core/extern.weave src/core/io.weave src/core/util.weave
  src/core/trace_registry.weave
  src/frontend/quantum_optimize.weave src/frontend/quantum_nativize.weave
  src/frontend/quantum_stats.weave src/frontend/emit.weave
  src/frontend/contract-lower.weave src/frontend/struct.weave src/frontend/lower.weave
  src/frontend/driver.weave src/frontend/explain-audit.weave
  src/frontend/contract-effects.weave src/frontend/audit-report.weave
  src/llvm/ctx.weave src/llvm/types.weave src/llvm/locals.weave
  src/llvm/strings.weave src/llvm/expr.weave
  src/llvm/stmt.weave src/llvm/fn.weave src/llvm/module.weave src/main.weave
)

stack_kb="${1:-16384}"
ulimit -s "$stack_kb"
cd "$WEAVEC_DIR"
rm -f "$OUT"
bash "$BOOTSTRAP_CAT" "$OUT" "${SOURCES[@]}"
echo "ok stack=${stack_kb}KB bytes=$(wc -c <"$OUT")"
