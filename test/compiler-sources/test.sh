#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=scripts/compiler-sources.sh
source "$ROOT/scripts/compiler-sources.sh"

fail() {
  printf 'compiler-sources: %s\n' "$*" >&2
  exit 1
}

weavec_load_compiler_sources "$ROOT"
[[ "${#WEAVEC_COMPILER_SOURCES[@]}" -gt 0 ]] || \
  fail 'canonical manifest produced no compiler sources'

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
printf '%s\n' "${WEAVEC_COMPILER_SOURCES[@]}" > "$WORK/loaded.list"
grep -Ev '^(#|$)' "$ROOT/compiler/sources.list" > "$WORK/declared.list"
diff -u "$WORK/declared.list" "$WORK/loaded.list" || \
  fail 'loader changed canonical source ordering'

for consumer in \
  "$ROOT/build.sh" \
  "$ROOT/selfhost.sh" \
  "$ROOT/scripts/test-weavec-bootstrap-stack.sh"; do
  grep -Fq 'weavec_load_compiler_sources' "$consumer" || \
    fail "consumer does not load canonical source manifest: $consumer"
  if grep -Eq '^[[:space:]]+src/(core|frontend|llvm)/.*\.weave' "$consumer"; then
    fail "consumer contains a private compiler source list: $consumer"
  fi
done

expect_rejected() {
  local name="$1"
  local content="$2"
  local manifest="$WORK/$name.list"
  printf '%s\n' "$content" > "$manifest"
  if weavec_load_compiler_sources "$ROOT" "$manifest" >/dev/null 2>&1; then
    fail "invalid manifest was accepted: $name"
  fi
}

expect_rejected duplicate $'src/core/extern.weave\nsrc/core/extern.weave'
expect_rejected absolute '/tmp/source.weave'
expect_rejected traversal 'src/core/../main.weave'
expect_rejected missing 'src/core/not-present.weave'
expect_rejected whitespace 'src/core/extern.weave '
expect_rejected empty '# comments only'

mkdir -p "$WORK/symlink-root/src/core"
ln -s "$ROOT/src/core/extern.weave" \
  "$WORK/symlink-root/src/core/extern.weave"
printf 'src/core/extern.weave\n' > "$WORK/symlink.list"
if weavec_load_compiler_sources \
    "$WORK/symlink-root" "$WORK/symlink.list" >/dev/null 2>&1; then
  fail 'symbolic-link compiler source was accepted'
fi

printf 'compiler-sources: canonical ordered manifest passed\n'
