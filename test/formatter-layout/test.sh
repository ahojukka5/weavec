#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-formatter-layout-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'formatter-layout: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}

require_line() {
  local pattern="$1"
  local path="$2"
  if ! grep -Fq "$pattern" "$path"; then
    printf 'formatter-layout: expected line fragment not found: %s\n' "$pattern" >&2
    printf '%s\n' '--- canonical output ---' >&2
    cat "$path" >&2
    printf '%s\n' '--- end canonical output ---' >&2
    exit 1
  fi
}

cat > "$TMP/compact.weave" <<'EOF_COMPACT'
(program
  (name "formatter-layout")
  (version "0.1")
  (entry main () i32
    (when (< 1 2)
      (return 0))))
EOF_COMPACT

"$WEAVEC" fmt "$TMP/compact.weave"
require_line '    (when (< 1 2) (return 0)))' "$TMP/compact.weave"
cp "$TMP/compact.weave" "$TMP/compact.once"
"$WEAVEC" fmt "$TMP/compact.weave"
cmp "$TMP/compact.once" "$TMP/compact.weave"

cat > "$TMP/legacy.weave" <<'EOF_LEGACY'
(program
  (name "formatter-layout-legacy")
  (version "0.1")
  (entry main (params) (returns i32)
    (do
      (if
        (condition (< 1 2))
        (then (do (return 0)))
        (else (do))))))
EOF_LEGACY

"$WEAVEC" fmt "$TMP/legacy.weave"
require_line '    (when (< 1 2) (return 0)))' "$TMP/legacy.weave"
cp "$TMP/legacy.weave" "$TMP/legacy.once"
"$WEAVEC" fmt "$TMP/legacy.weave"
cmp "$TMP/legacy.once" "$TMP/legacy.weave"

cat > "$TMP/long.weave" <<'EOF_LONG'
(program
  (name "formatter-layout-long")
  (version "0.1")
  (entry main () i32
    (when (< 1 2)
      (write_stderr "this deliberately makes the complete control form exceed eighty columns")
      (return 0))))
EOF_LONG

"$WEAVEC" fmt "$TMP/long.weave"
if grep -Fq '    (when (< 1 2) (write_stderr' "$TMP/long.weave"; then
  printf 'formatter-layout: long when unexpectedly rendered inline\n' >&2
  cat "$TMP/long.weave" >&2
  exit 1
fi
require_line '    (when' "$TMP/long.weave"
require_line '      (< 1 2)' "$TMP/long.weave"
require_line '      (return 0))))' "$TMP/long.weave"
cp "$TMP/long.weave" "$TMP/long.once"
"$WEAVEC" fmt "$TMP/long.weave"
cmp "$TMP/long.once" "$TMP/long.weave"

printf 'formatter-layout: passed\n'
