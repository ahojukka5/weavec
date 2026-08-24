#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-fmt-function-spacing-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'formatter-function-spacing: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}

cat > "$TMP/input.weave" <<'EOF_INPUT'
(program
  (name "formatter-function-spacing")
  (version "0.1")

  (fn sample ((x i32)) i32

    (ensures (= 1 1))

    (effects deterministic pure)

    (example (= 1 1))

    (doc "Return a non-negative value.")

    (requires (= 1 1))

    (let y x)

    (let z y)

    (when (< z 10)
      (write_stderr "this deliberately long statement keeps the control form beyond eighty columns")
      (return z))

    (return z))

  (fn plain () i32


    (let x 1)


    (return x)))
EOF_INPUT

"$WEAVEC" fmt "$TMP/input.weave"

python3 - "$TMP/input.weave" <<'PY'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text()

ordered = [
    '    (doc "Return a non-negative value.")',
    '    (example (= 1 1))',
    '    (effects pure deterministic)',
    '    (requires (= 1 1))',
    '    (ensures (= 1 1))',
]
positions = [text.index(item) for item in ordered]
if positions != sorted(positions):
    raise SystemExit('formatter-function-spacing: header order is not canonical')

header_body = '    (ensures (= 1 1))\n\n    (let y x)\n    (let z y)'
if header_body not in text:
    raise SystemExit(
        'formatter-function-spacing: expected exactly one blank line at header/body boundary')

if '    (let y x)\n\n    (let z y)' in text:
    raise SystemExit(
        'formatter-function-spacing: consecutive inline body statements gained a blank line')

when_start = text.index('    (when')
return_after = text.index('\n    (return z)', when_start) + 1
segment = text[when_start:return_after]
if not segment.endswith('\n\n'):
    raise SystemExit(
        'formatter-function-spacing: multiline body form must be separated from following sibling')

plain = text[text.index('  (fn plain'):]
if '  (fn plain () i32\n\n    (let x 1)' in plain:
    raise SystemExit(
        'formatter-function-spacing: headerless function gained a leading blank line')
if '  (fn plain () i32\n    (let x 1)\n    (return x))' not in plain:
    raise SystemExit(
        'formatter-function-spacing: headerless inline body spacing is not compact')
PY

cp "$TMP/input.weave" "$TMP/once.weave"
"$WEAVEC" fmt "$TMP/input.weave"
cmp "$TMP/once.weave" "$TMP/input.weave"

printf 'formatter-function-spacing: passed\n'
