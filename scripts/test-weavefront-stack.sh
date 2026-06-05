#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

WEAVEC2_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WF_CAT="$WEAVEC2_DIR/build/vendor/weavefront/weavefront-cat.sh"
OUT="/tmp/wf-stack-test.wir"

SOURCES=(
  src/core/extern.weave src/core/io.weave src/core/util.weave
  src/frontend/quantum_optimize.weave src/frontend/quantum_nativize.weave
  src/frontend/quantum_stats.weave src/frontend/emit.weave
  src/frontend/contract-lower.weave src/frontend/struct.weave src/frontend/lower.weave
  src/frontend/driver.weave src/frontend/explain-audit.weave
  src/frontend/contract-effects.weave src/frontend/audit-report.weave
  src/llvm/ctx.weave src/llvm/types.weave src/llvm/locals.weave
  src/llvm/strings.weave src/llvm/expr.weave src/llvm/loop-phi.weave
  src/llvm/stmt.weave src/llvm/fn.weave src/llvm/module.weave src/main.weave
)

stack_kb="${1:-16384}"
ulimit -s "$stack_kb"
cd "$WEAVEC2_DIR"
rm -f "$OUT"
bash "$WF_CAT" "$OUT" "${SOURCES[@]}"
echo "ok stack=${stack_kb}KB bytes=$(wc -c <"$OUT")"
