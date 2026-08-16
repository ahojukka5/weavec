#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Pins the struct binding semantics the compiler currently has, which are a
# KNOWN GAP rather than the intended model.
#
# A struct value is a pointer, so binding aliases, and neither double release
# nor use after release is diagnosed. The intended model is that a struct is an
# owned value which binding moves — see docs/struct-ownership.md — and it is
# implemented by the ownership work, not by this compiler.
#
# This test exists so that gap cannot close silently. When move checking lands,
# these cases must start failing, and this file must be rewritten to assert the
# new behaviour rather than relaxed to keep passing.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-struct-aliasing-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'struct-aliasing: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}

# 1. Binding aliases: a write through one name is visible through the other.
cat > "$TMP/alias.weave" <<'EOF'
(program
  (name "struct-aliasing-bind")
  (version "0.1")
  (extern malloc (params (size i64)) (returns ptr))
  (extern free (params (value ptr)) (returns void))
  (struct Counter (field n i32))
  (entry main (params) (returns i32)
    (do
      (let a Counter (new Counter (n 1)))
      (let b Counter a)
      (field-set b n 42)
      (let seen i32 (field-get a n))
      (call free a)
      (return seen))))
EOF

"$WEAVEC" build "$TMP/alias.weave" -o "$TMP/alias" 2>"$TMP/alias.stderr" || {
  printf 'struct-aliasing: the aliasing program failed to build\n' >&2
  cat "$TMP/alias.stderr" >&2
  exit 1
}
set +e
"$TMP/alias"
alias_status="$?"
set -e
if [[ "$alias_status" -ne 42 ]]; then
  printf 'struct-aliasing: binding produced %s, expected 42\n' "$alias_status" >&2
  printf 'A result of 1 means binding now copies, and 0 or a crash means it\n' >&2
  printf 'moves. Either is the intended direction: update this test and\n' >&2
  printf 'docs/struct-ownership.md rather than restoring the old behaviour.\n' >&2
  exit 1
fi

# 2. Release, use after release, and a second release are all accepted with no
# diagnostic. This is the failure the ownership model exists to catch.
cat > "$TMP/unchecked.weave" <<'EOF'
(program
  (name "struct-aliasing-unchecked")
  (version "0.1")
  (extern malloc (params (size i64)) (returns ptr))
  (extern free (params (value ptr)) (returns void))
  (struct Owner (field block ptr) (field n i32))
  (fn consume (params (o Owner)) (returns void)
    (do (call free (field-get o block)) (call free o) (return)))
  (entry main (params) (returns i32)
    (do
      (let a Owner (new Owner (block (call malloc 64)) (n 7)))
      (call consume a)
      (let after i32 (field-get a n))
      (call free a)
      (return after))))
EOF

set +e
"$WEAVEC" build "$TMP/unchecked.weave" -o "$TMP/unchecked" \
  >"$TMP/unchecked.stdout" 2>"$TMP/unchecked.stderr"
unchecked_status="$?"
set -e
if [[ "$unchecked_status" -ne 0 ]]; then
  printf 'struct-aliasing: use after release is now diagnosed.\n' >&2
  printf 'That is the intended model arriving. Rewrite this test to assert the\n' >&2
  printf 'new diagnostic and update docs/struct-ownership.md and\n' >&2
  printf 'docs/semantic-structs.md, which both describe it as a known gap.\n' >&2
  cat "$TMP/unchecked.stderr" >&2
  exit 1
fi

# The gap must stay documented as a gap for as long as it exists.
for doc in docs/struct-ownership.md docs/semantic-structs.md; do
  if ! grep -Fq 'after releasing it' "$ROOT/$doc" && \
     ! grep -Fq 'use after release' "$ROOT/$doc"; then
    printf 'struct-aliasing: %s no longer documents the release gap\n' "$doc" >&2
    exit 1
  fi
done

printf 'struct-aliasing: passed (known gap pinned)\n'
