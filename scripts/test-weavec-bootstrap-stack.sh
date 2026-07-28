#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

WEAVEC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BOOTSTRAP_CAT="$WEAVEC_DIR/build/vendor/weavec-bootstrap/weavec-bootstrap-cat.sh"
OUT="/tmp/weavec-bootstrap-stack-test.wir"

# shellcheck source=scripts/compiler-sources.sh
source "$WEAVEC_DIR/scripts/compiler-sources.sh"
weavec_load_compiler_sources "$WEAVEC_DIR"
SOURCES=("${WEAVEC_COMPILER_SOURCES[@]}")

stack_kb="${1:-16384}"
ulimit -s "$stack_kb"
cd "$WEAVEC_DIR"
rm -f "$OUT"
bash "$BOOTSTRAP_CAT" "$OUT" "${SOURCES[@]}"
echo "ok stack=${stack_kb}KB bytes=$(wc -c <"$OUT")"
