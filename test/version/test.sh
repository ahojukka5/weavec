#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COMPILER="$ROOT/build/weavec"

fail() {
  printf '[weavec-version-test] error: %s\n' "$*" >&2
  exit 1
}

# shellcheck source=scripts/weavec-version.sh
source "$ROOT/scripts/weavec-version.sh"

[[ -x "$COMPILER" ]] || fail "compiler missing: $COMPILER"
expected="$(weavec_version_string "$ROOT")"
actual="$("$COMPILER" --version)"
[[ "$actual" == "weavec $expected" ]] || \
  fail "expected 'weavec $expected', got '$actual'"
[[ "$expected" =~ ^v[0-9]+\.[0-9]+\.[0-9]+([+-][0-9A-Za-z.-]+)?$ ]] || \
  fail "unexpected version grammar: $expected"

override="$(WEAVEC_VERSION_OVERRIDE=9.8.7 \
  weavec_version_string "$ROOT")"
[[ "$override" == "v9.8.7" ]] || fail "override normalization failed: $override"

set +e
WEAVEC_VERSION_OVERRIDE='bad" -DBROKEN=1' \
  weavec_version_string "$ROOT" >/dev/null 2>&1
invalid_status=$?
"$COMPILER" --version extra >/dev/null 2>&1
argument_status=$?
set -e
[[ "$invalid_status" -ne 0 ]] || fail "malformed override was accepted"
[[ "$argument_status" -ne 0 ]] || fail "extra version argument was accepted"

printf '[weavec-version-test] %s\n' "$actual"
