#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"

usage() {
  cat <<'EOF'
usage: test/project-acceptance/test.sh [--compiler <path>]

Run the public project-workflow acceptance corpus with one compiler executable.
The default compiler is build/weavec. WEAVEC may also select the compiler.
EOF
}

while (($#)); do
  case "$1" in
    --compiler)
      [[ $# -ge 2 ]] || {
        printf 'project-acceptance: --compiler requires a path\n' >&2
        exit 2
      }
      WEAVEC="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'project-acceptance: unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

[[ -x "$WEAVEC" ]] || {
  printf 'project-acceptance: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}
WEAVEC="$(cd "$(dirname "$WEAVEC")" && pwd -P)/$(basename "$WEAVEC")"

run_suite() {
  local label="$1"
  local path="$2"
  printf '[weavec-project-acceptance] %s\n' "$label"
  env WEAVEC="$WEAVEC" bash "$ROOT/$path"
}

printf '[weavec-project-acceptance] compiler: %s\n' "$WEAVEC"
"$WEAVEC" --version

run_suite 'module visibility and explicit interfaces' \
  test/modules/test.sh
run_suite 'public nominal type interfaces' \
  test/module-type-interfaces/test.sh
run_suite 'project selection, precedence, and output safety' \
  test/project-discovery/test.sh
run_suite 'source admission, graph resolution, entries, and libraries' \
  test/project-source-discovery/test.sh
run_suite 'protocols, relocation determinism, and project analysis' \
  test/project-protocols/test.sh

printf '[weavec-project-acceptance] all public project checks passed\n'
