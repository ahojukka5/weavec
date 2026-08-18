#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Standard-library layout and naming (#241). Each stdlib/<id>.weave is
# named std.<id>. Packages copy the directory as a whole.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DOC="$ROOT/docs/stdlib.md"
README="$ROOT/stdlib/README.md"
PACKAGE_SCRIPT="$ROOT/scripts/package-linux-release.sh"

[[ -f "$DOC" ]] || {
  printf 'stdlib-layout: missing %s\n' "$DOC" >&2
  exit 1
}
[[ -f "$README" ]] || {
  printf 'stdlib-layout: missing %s\n' "$README" >&2
  exit 1
}

count=0
for module in "$ROOT"/stdlib/*.weave; do
  stem="$(basename "$module" .weave)"
  name="std.${stem}"
  path="stdlib/${stem}.weave"
  count=$((count + 1))

  if ! grep -Eq '\(name[[:space:]]+"'"$name"'"\)' "$module"; then
    printf 'stdlib-layout: %s is not named %s\n' "$path" "$name" >&2
    exit 1
  fi
  if ! grep -Fq "\`$path\`" "$DOC" || ! grep -Fq "\`$name\`" "$DOC"; then
    printf 'stdlib-layout: %s is not catalogued in docs/stdlib.md\n' \
      "$path" >&2
    exit 1
  fi
  if ! grep -Fq "\`$path\`" "$README" || ! grep -Fq "\`$name\`" "$README"; then
    printf 'stdlib-layout: %s is not catalogued in stdlib/README.md\n' \
      "$path" >&2
    exit 1
  fi
done

[[ "$count" -gt 0 ]] || {
  printf 'stdlib-layout: no stdlib modules found\n' >&2
  exit 1
}

if ! grep -Fq 'cp -R "$ROOT/stdlib" "$PACKAGE_DIR/stdlib"' \
  "$PACKAGE_SCRIPT"; then
  printf 'stdlib-layout: package script does not copy stdlib/\n' >&2
  exit 1
fi
if ! grep -Fq 'EXTRACTED_PACKAGE/stdlib/' "$PACKAGE_SCRIPT"; then
  printf 'stdlib-layout: package script does not check shipped modules\n' \
    >&2
  exit 1
fi

if grep -Eq 'src/runtime|libweave-runtime' "$ROOT"/stdlib/*.weave; then
  printf 'stdlib-layout: a standard module refers to the private runtime archive\n' >&2
  exit 1
fi

printf 'stdlib-layout: passed\n'
