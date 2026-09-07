#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Hosted-runner pull-request compile gate. Builds weavec from published SDKs
# and runs the fast behavioral subset. The full ladder and deep self-host
# still run on master after merge.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log() {
  printf '[weavec-pr-compile] %s\n' "$*"
}

log 'build compiler from published SDKs'
bash "$ROOT/scripts/build.sh"

log 'correctness suites'
bash "$ROOT/test.sh"

log 'command-line and file-IO diagnostics'
bash "$ROOT/test/cli-diagnostics/test.sh"

log 'parse diagnostics'
bash "$ROOT/test/parse-diagnostics/test.sh"

log 'surface conformance corpus'
bash "$ROOT/test/conformance/run.sh"

log 'diagnostic repairs'
bash "$ROOT/test/diagnostic-repairs/test.sh"

log 'canonical formatter'
bash "$ROOT/test/formatter/test.sh"

log 'canonical formatter layout'
bash "$ROOT/test/formatter-layout/test.sh"

log 'canonical function spacing'
bash "$ROOT/test/formatter-function-spacing/test.sh"

log 'canonical generic sibling spacing'
bash "$ROOT/test/formatter-generic-spacing/test.sh"

log 'explicit generic type parameters'
bash "$ROOT/test/generic-type-params/test.sh"

# Suites reclassified 'executes' in test/EXECUTION-MANIFEST run here, so the
# program they build is proven before merge rather than only in the ladder.
log 'expression-valued if'
bash "$ROOT/test/expr-if/test.sh"

log 'let type inference'
bash "$ROOT/test/let-infer/test.sh"

log 'variants and match'
bash "$ROOT/test/variant-match/test.sh"

log 'generic monomorphization'
bash "$ROOT/test/generic-monomorphization/test.sh"

log 'string interpolation'
bash "$ROOT/test/interp/test.sh"

log 'standalone comment statements'
bash "$ROOT/test/comment-statement/test.sh"

log 'owned in-memory WIR tree and builder invariants'
bash "$ROOT/test/wir-tree/test.sh"

log 'canonical WIR serializer and decimal lexemes'
bash "$ROOT/test/wir-serialize/test.sh"

log 'option and result'
bash "$ROOT/test/option-result/test.sh"

log 'option helpers'
bash "$ROOT/test/option-helpers/test.sh"

log 'passed'
