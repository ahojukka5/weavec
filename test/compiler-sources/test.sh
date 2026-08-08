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
  fail 'canonical manifest produced no linked compiler sources'

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
printf '%s\n' "${WEAVEC_COMPILER_SOURCES[@]}" > "$WORK/loaded.list"
grep -Ev '^(#|$|!)' "$ROOT/compiler/sources.list" > "$WORK/declared.list"
diff -u "$WORK/declared.list" "$WORK/loaded.list" || \
  fail 'loader changed canonical source ordering'

{
  printf '%s\n' "${WEAVEC_COMPILER_SOURCES[@]}"
  if [[ "${#WEAVEC_NONLINKED_SOURCES[@]}" -gt 0 ]]; then
    printf '%s\n' "${WEAVEC_NONLINKED_SOURCES[@]}"
  fi
} | LC_ALL=C sort > "$WORK/classified.list"
find "$ROOT/src" -type f -name '*.weave' -print |
  sed "s#^$ROOT/##" |
  LC_ALL=C sort > "$WORK/discovered.list"
diff -u "$WORK/discovered.list" "$WORK/classified.list" || \
  fail 'src/*.weave files are not completely classified by compiler/sources.list'

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

expect_rejected duplicate $'src/core/extern.weave\n!src/core/extern.weave'
expect_rejected absolute '/tmp/source.weave'
expect_rejected excluded_absolute '!/tmp/source.weave'
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

mkdir -p "$WORK/valid-root/src/core"
cat > "$WORK/valid-root/src/core/unit.weave" <<'WEAVE'
(program
  (name "valid")
  (version "0.1")
  (fn valid_source
    (params)
    (returns void)
    (do (return_void))))
WEAVE
printf 'src/core/unit.weave\n' > "$WORK/valid.list"
weavec_load_compiler_sources "$WORK/valid-root" "$WORK/valid.list" || \
  fail 'well-formed compiler source unit was rejected'

mkdir -p "$WORK/unbalanced-root/src/core"
cat > "$WORK/unbalanced-root/src/core/unit.weave" <<'WEAVE'
(program
  (name "unbalanced")
  (version "0.1")
  (fn broken
    (params)
    (returns void)
    (do (return_void)))
WEAVE
printf 'src/core/unit.weave\n' > "$WORK/unbalanced.list"
if weavec_load_compiler_sources \
    "$WORK/unbalanced-root" "$WORK/unbalanced.list" >/dev/null 2>&1; then
  fail 'unbalanced compiler source unit was accepted'
fi

mkdir -p "$WORK/misleading-root/src/core"
cat > "$WORK/misleading-root/src/core/unit.weave" <<'WEAVE'
; A comment mentioning (program before the real source wrapper must be rejected
; while the published v0.3.1 multifile combiner is in the bootstrap chain.
(program
  (name "misleading")
  (version "0.1")
  (fn valid_source
    (params)
    (returns void)
    (do (return_void))))
WEAVE
printf 'src/core/unit.weave\n' > "$WORK/misleading.list"
if weavec_load_compiler_sources \
    "$WORK/misleading-root" "$WORK/misleading.list" >/dev/null 2>&1; then
  fail 'bootstrap-misleading compiler source unit was accepted'
fi

mkdir -p "$WORK/nested-root/src/core"
cat > "$WORK/nested-root/src/core/unit.weave" <<'WEAVE'
(wrapper
  (program
    (name "nested")
    (version "0.1")))
WEAVE
printf 'src/core/unit.weave\n' > "$WORK/nested.list"
if weavec_load_compiler_sources \
    "$WORK/nested-root" "$WORK/nested.list" >/dev/null 2>&1; then
  fail 'nested compiler program wrapper was accepted'
fi

bash "$ROOT/test/protocol-boundary/test.sh"
printf 'compiler-sources: canonical ordered manifest passed\n'
