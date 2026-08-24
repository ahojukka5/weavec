#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-fmt-generic-spacing-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'formatter-generic-spacing: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}

LONG_FIELD="this_field_name_is_intentionally_long_enough_to_force_the_field_form_beyond_eighty_columns"

cat > "$TMP/a.weave" <<EOF_A
(program

  (name "formatter-generic-spacing")

  (version "0.1")

  (struct Record

    (field a i32)

    (field $LONG_FIELD i32)

    (field b i32))

  (entry main () i32
    (return 0)))
EOF_A

cat > "$TMP/b.weave" <<EOF_B
(program(name "formatter-generic-spacing")(version "0.1")
(struct Record(field a i32)(field $LONG_FIELD i32)(field b i32))
(entry main () i32(return 0)))
EOF_B

"$WEAVEC" fmt "$TMP/a.weave"
"$WEAVEC" fmt "$TMP/b.weave"
cmp "$TMP/a.weave" "$TMP/b.weave"

python3 - "$TMP/a.weave" "$LONG_FIELD" <<'PY'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text()
long_name = sys.argv[2]

# Two short top-level forms stay adjacent.
if '  (name "formatter-generic-spacing")\n  (version "0.1")' not in text:
    raise SystemExit(
        'formatter-generic-spacing: one-line top-level siblings gained blank-line noise')

short_a = text.index('    (field a i32)')
long_name_at = text.index(long_name)
long_start = text.rfind('    (field', short_a, long_name_at)
if long_start < 0:
    raise SystemExit('formatter-generic-spacing: long field form start not found')
short_a_end = short_a + len('    (field a i32)')
if text[short_a_end:long_start] != '\n\n':
    raise SystemExit(
        'formatter-generic-spacing: short -> multiline form needs exactly one blank line')

short_b = text.index('    (field b i32)', long_name_at)
long_end = text.rfind(')', long_name_at, short_b)
if long_end < 0:
    raise SystemExit('formatter-generic-spacing: long field form end not found')
if text[long_end + 1:short_b] != '\n\n':
    raise SystemExit(
        'formatter-generic-spacing: multiline -> short form needs exactly one blank line')

# No padding belongs at the beginning or end of the struct child list.
struct_at = text.index('  (struct Record')
first_field = text.index('    (field a i32)', struct_at)
if text[text.index('Record', struct_at) + len('Record'):first_field] != '\n':
    raise SystemExit(
        'formatter-generic-spacing: struct gained leading child-list padding')
if '\n\n' in text[short_b: text.index('  (entry main', short_b)]:
    # Exactly one separator is allowed between the multiline struct declaration
    # and the following top-level entry, but not inside the tail of the struct.
    tail = text[short_b:text.index('  (entry main', short_b)]
    if not tail.endswith('))\n\n'):
        raise SystemExit(
            'formatter-generic-spacing: struct gained trailing child-list padding')

# The multiline struct and following entry are form siblings at program level.
entry_at = text.index('  (entry main', short_b)
struct_end = text.rfind(')', short_b, entry_at)
if text[struct_end + 1:entry_at] != '\n\n':
    raise SystemExit(
        'formatter-generic-spacing: multiline top-level form needs one separator')
PY

cp "$TMP/a.weave" "$TMP/once.weave"
"$WEAVEC" fmt "$TMP/a.weave"
cmp "$TMP/once.weave" "$TMP/a.weave"

printf 'formatter-generic-spacing: passed\n'
