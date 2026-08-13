#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# The examples index is the entry point a user reads first, so it must stay in
# step with the programs that actually exist and must not require knowing how
# the compiler works.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INDEX="$ROOT/examples/README.md"

[[ -f "$INDEX" ]] || {
  printf 'examples-index: %s is missing\n' "$INDEX" >&2
  exit 1
}

# Every example directory is listed, and every listed example exists.
for directory in "$ROOT"/examples/*/; do
  name="$(basename "$directory")"
  [[ -f "$directory/main.weave" ]] || continue
  if ! grep -Fq "($name/README.md)" "$INDEX"; then
    printf 'examples-index: %s is not listed in the index\n' "$name" >&2
    exit 1
  fi
  if [[ ! -f "$directory/README.md" ]]; then
    printf 'examples-index: %s has no README\n' "$name" >&2
    exit 1
  fi
done

while read -r listed; do
  [[ -n "$listed" ]] || continue
  if [[ ! -f "$ROOT/examples/$listed/main.weave" ]]; then
    printf 'examples-index: index lists %s, which does not exist\n' \
      "$listed" >&2
    exit 1
  fi
done < <(grep -oE '\([a-z0-9-]+/README\.md\)' "$INDEX" \
  | tr -d '()' | sed 's|/README.md||' | sort -u)

# Every standard module a user can build against is described.
for module in "$ROOT"/stdlib/*.weave; do
  name="stdlib/$(basename "$module")"
  if ! grep -Fq "$name" "$INDEX"; then
    printf 'examples-index: %s is not described in the index\n' "$name" >&2
    exit 1
  fi
done

# The index is user-facing: it must not lean on compiler internals.
if grep -Eiq '\bWIR\b|self-host|bootstrap|monomorphi|LLVM|elaborat' "$INDEX"; then
  printf 'examples-index: index refers to compiler internals\n' >&2
  exit 1
fi

printf 'examples-index: passed\n'
