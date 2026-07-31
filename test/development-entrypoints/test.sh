#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

for name in build test-all selfhost; do
  canonical="$ROOT/scripts/$name.sh"
  compatibility="$ROOT/$name.sh"

  [[ -x "$canonical" ]] || {
    printf 'development-entrypoints: missing executable %s\n' "$canonical" >&2
    exit 1
  }
  [[ -L "$compatibility" ]] || {
    printf 'development-entrypoints: %s is not a compatibility symlink\n' \
      "$compatibility" >&2
    exit 1
  }
  [[ "$(readlink "$compatibility")" == "scripts/$name.sh" ]] || {
    printf 'development-entrypoints: unexpected target for %s\n' \
      "$compatibility" >&2
    exit 1
  }
  bash -n "$canonical"
done

if grep -Eq \
  'git clone|checkout_ref|ensure_.*_source|WEAVEC0|WEAVEC1_REPO|WEAVEC_BOOTSTRAP_REPO' \
  "$ROOT/scripts/build.sh"; then
  printf 'development-entrypoints: final build contains a source fallback\n' >&2
  exit 1
fi

grep -Fq -- '--no-build' "$ROOT/scripts/test-all.sh"
grep -Fq 'scripts/build.sh first' "$ROOT/scripts/selfhost.sh"

printf 'development-entrypoints: SDK-only canonical scripts passed\n'
