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

log 'diagnostic repairs'
bash "$ROOT/test/diagnostic-repairs/test.sh"

log 'canonical formatter'
bash "$ROOT/test/formatter/test.sh"

log 'option and result'
bash "$ROOT/test/option-result/test.sh"

log 'option helpers'
bash "$ROOT/test/option-helpers/test.sh"

log 'passed'
