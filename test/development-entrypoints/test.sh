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

# LLVM toolchain skew detection (#441). A clang newer than llc emits IR the
# code generator cannot parse, and every native build then fails with an LLVM
# parse error naming no Weave source.
#
# These stubs test the version comparison and the message, not the claim about
# IR syntax: that was observed against the real Apple clang 21 and LLVM 18.1.0
# on macOS, and a stub cannot establish it.
TOOLCHAIN_TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-toolchain-XXXXXX")"
trap 'rm -rf "$TOOLCHAIN_TMP"' EXIT

make_stub() {
  printf '#!/bin/sh\necho "%s version %s.0.0"\n' "$2" "$3" > "$1"
  chmod +x "$1"
}

make_stub "$TOOLCHAIN_TMP/new-clang" clang 21
make_stub "$TOOLCHAIN_TMP/old-llc" LLVM 18
make_stub "$TOOLCHAIN_TMP/new-llc" LLVM 21

set +e
WEAVEC_OPTIMIZER="$TOOLCHAIN_TMP/new-clang" \
  WEAVEC_TARGET_CODEGEN="$TOOLCHAIN_TMP/old-llc" \
  bash "$ROOT/scripts/build.sh" >"$TOOLCHAIN_TMP/skew.out" \
  2>"$TOOLCHAIN_TMP/skew.err"
set -e
# The skew is a warning: the compiler build itself does not use the code
# generator and succeeds, so only `weavec build` of a target program fails.
for needle in 'warning: LLVM toolchain skew' 'is version 21' 'is version 18' \
  'WEAVEC_TARGET_CODEGEN'; do
  grep -Fq "$needle" "$TOOLCHAIN_TMP/skew.err" || {
    printf 'development-entrypoints: skew message missing: %s\n' "$needle" >&2
    cat "$TOOLCHAIN_TMP/skew.err" >&2
    exit 1
  }
done
# The skew must be reported before any SDK download work begins, and must
# not stop the build: the compiler builds fine under skew.
if ! grep -Eq 'warning: LLVM toolchain skew' "$TOOLCHAIN_TMP/skew.err"; then
  printf 'development-entrypoints: skew was not reported\n' >&2
  exit 1
fi
if grep -Fq 'error: LLVM toolchain skew' "$TOOLCHAIN_TMP/skew.err"; then
  printf 'development-entrypoints: skew must warn, not fail the build\n' >&2
  exit 1
fi

# A matching pair must not be rejected by the check. The build continues past
# it and may fail later for unrelated reasons, so only the check's own message
# is asserted absent.
set +e
WEAVEC_OPTIMIZER="$TOOLCHAIN_TMP/new-clang" \
  WEAVEC_TARGET_CODEGEN="$TOOLCHAIN_TMP/new-llc" \
  bash "$ROOT/scripts/build.sh" >"$TOOLCHAIN_TMP/match.out" \
  2>"$TOOLCHAIN_TMP/match.err"
set -e
if grep -Fq 'LLVM toolchain skew' "$TOOLCHAIN_TMP/match.err"; then
  printf 'development-entrypoints: matching toolchain was rejected\n' >&2
  cat "$TOOLCHAIN_TMP/match.err" >&2
  exit 1
fi
# A tool that refuses --version must not stop the build. Probing one is
# advisory, and piping it into awk under `set -o pipefail` propagated its exit
# status and aborted the script, which broke test/build-boundary on any host
# with llc installed. That failure was silent: the build died before doing
# anything, and the suite's grep found an empty log.
make_stub "$TOOLCHAIN_TMP/refuses-version" ignored 0
printf '#!/bin/sh\nexit 1\n' > "$TOOLCHAIN_TMP/refuses-version"
chmod +x "$TOOLCHAIN_TMP/refuses-version"

set +e
WEAVEC_OPTIMIZER="$TOOLCHAIN_TMP/refuses-version" \
  WEAVEC_TARGET_CODEGEN="$TOOLCHAIN_TMP/new-llc" \
  bash "$ROOT/scripts/build.sh" >"$TOOLCHAIN_TMP/refuse.out" \
  2>"$TOOLCHAIN_TMP/refuse.err"
set -e
# The build proceeds past the probe and fails later for its own reasons; what
# matters is that it got past it rather than dying inside the version check.
if ! grep -qE 'weavec1|SDK|required tool' "$TOOLCHAIN_TMP/refuse.err"; then
  printf 'development-entrypoints: version probe stopped the build\n' >&2
  cat "$TOOLCHAIN_TMP/refuse.err" >&2
  exit 1
fi
printf 'development-entrypoints: version probe is advisory\n'

printf 'development-entrypoints: toolchain skew detection passed\n'

printf 'development-entrypoints: SDK-only canonical scripts passed\n'
