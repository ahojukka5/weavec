#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Deterministic mutation-fuzzing lane (#387). The subject is compiler
# robustness: mutated surface and WIR inputs must terminate through
# documented exits, valid diagnostics, and no partial artifacts. Random
# accepts are not executed for semantic correctness.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
BUDGET="${WEAVEC_MUTATION_FUZZ_BUDGET:-pr}"
DUMP="${WEAVEC_MUTATION_FUZZ_DUMP:-$ROOT/build/mutation-fuzz}"

pick_python() {
  local candidate
  for candidate in python3 python3.12 python3.11 python3.10 python3.9; do
    command -v "$candidate" >/dev/null 2>&1 || continue
    if "$candidate" -c 'import sys; raise SystemExit(sys.version_info < (3, 8))'
    then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  printf 'mutation-fuzz: Python 3.8+ is required\n' >&2
  exit 1
}

PYTHON="$(pick_python)"

[[ -x "$WEAVEC" ]] || {
  printf 'mutation-fuzz: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}

"$PYTHON" "$ROOT/scripts/mutation_fuzz.py" --self-test
"$PYTHON" "$ROOT/scripts/mutation_fuzz.py" \
  --budget="$BUDGET" \
  --weavec="$WEAVEC" \
  --dump-dir="$DUMP"

printf 'mutation-fuzz: passed\n'
