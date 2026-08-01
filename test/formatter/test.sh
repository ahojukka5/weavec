#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-formatter-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'formatter: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}
command -v python3 >/dev/null 2>&1 || {
  printf 'formatter: python3 is required\n' >&2
  exit 1
}

python3 - "$TMP/input.weave" <<'PY'
from pathlib import Path
import sys

source = '''; leading source comment  
(program(name "formatter-e2e")(version "0.1")
(fn add-one(params(value i32))(returns i32)(do(return(add_i32(param_get value)(const_i32 1)))))
(entry main(params)(returns i32); entry body  
(do(let wide i64(const_i64 41))(let narrowed i32(cast_i64_to_i32(local_get wide)))(return(call_i32 add-one(local_get narrowed)))))); trailing source comment  
'''
Path(sys.argv[1]).write_bytes(source.replace("\n", "\r\n").encode())
PY
cp "$TMP/input.weave" "$TMP/input.before"

set +e
"$WEAVEC" fmt --check "$TMP/input.weave"
check_exit="$?"
set -e
[[ "$check_exit" -eq 1 ]] || {
  printf 'formatter: expected noncanonical check exit 1, got %s\n' "$check_exit" >&2
  exit 1
}
cmp "$TMP/input.before" "$TMP/input.weave"

"$WEAVEC" fmt --output "$TMP/formatted.weave" "$TMP/input.weave"
cat > "$TMP/expected.weave" <<'EOF_EXPECTED'
; leading source comment
(program
  (name "formatter-e2e")
  (version "0.1")
  (fn add-one
    (params (value i32))
    (returns i32)
    (do (return (op add value 1))))
  (entry main
    (params)
    (returns i32)
    ; entry body
    (do
      (let wide i64 41)
      (let narrowed i32 (cast i32 wide))
      (return (call add-one narrowed)))))
; trailing source comment
EOF_EXPECTED
cmp "$TMP/expected.weave" "$TMP/formatted.weave"
"$WEAVEC" fmt --check "$TMP/formatted.weave"

cp "$TMP/formatted.weave" "$TMP/twice.weave"
"$WEAVEC" fmt "$TMP/twice.weave"
cmp "$TMP/formatted.weave" "$TMP/twice.weave"

"$WEAVEC" --frontend "$TMP/original.wir" "$TMP/input.weave"
"$WEAVEC" --frontend "$TMP/formatted.wir" "$TMP/formatted.weave"

# A bare identifier and its explicit (param_get X)/(local_get X) spelling are
# equivalent admitted WIR v2 operand forms; canonical elaboration consistently
# emits the bare spelling (matching #55-#57), so compare modulo that
# already-established equivalence rather than requiring identical bytes.
normalize_refs() {
  sed -E \
    's/\(param_get ([A-Za-z_][A-Za-z0-9_-]*)\)/\1/g
     s/\(local_get ([A-Za-z_][A-Za-z0-9_-]*)\)/\1/g' "$1"
}
diff -u <(normalize_refs "$TMP/original.wir") <(normalize_refs "$TMP/formatted.wir")

"$WEAVEC" build "$TMP/formatted.weave" -o "$TMP/formatted-program"
set +e
"$TMP/formatted-program"
program_exit="$?"
set -e
[[ "$program_exit" -eq 42 ]] || {
  printf 'formatter: expected native exit 42, got %s\n' "$program_exit" >&2
  exit 1
}

cat > "$TMP/library.weave" <<'EOF_LIBRARY'
(program(name "library")(version "0.1")(fn answer(params)(returns i32)(do(return(const_i32 42)))))
EOF_LIBRARY
cat > "$TMP/application.weave" <<'EOF_APPLICATION'
(program(name "application")(version "0.1")(entry main(params)(returns i32)(do(return(call_i32 answer)))))
EOF_APPLICATION
"$WEAVEC" fmt "$TMP/library.weave"
"$WEAVEC" fmt "$TMP/application.weave"
grep -Fq '(call answer)' "$TMP/application.weave"
if grep -Fq 'call_i32' "$TMP/application.weave"; then
  printf 'formatter: cross-file compatibility call remained typed\n' >&2
  exit 1
fi
"$WEAVEC" build "$TMP/library.weave" "$TMP/application.weave" \
  -o "$TMP/multifile-program"
set +e
"$TMP/multifile-program"
multifile_exit="$?"
set -e
[[ "$multifile_exit" -eq 42 ]] || {
  printf 'formatter: expected multi-file exit 42, got %s\n' "$multifile_exit" >&2
  exit 1
}

printf 'previous output\n' > "$TMP/atomic.weave"
cp "$TMP/atomic.weave" "$TMP/atomic.before"
printf '(program (name "broken")\n' > "$TMP/broken.weave"
set +e
"$WEAVEC" fmt --output "$TMP/atomic.weave" "$TMP/broken.weave" \
  2>"$TMP/broken.stderr"
broken_exit="$?"
set -e
[[ "$broken_exit" -eq 3 ]] || {
  printf 'formatter: expected malformed-source exit 3, got %s\n' "$broken_exit" >&2
  exit 1
}
cmp "$TMP/atomic.before" "$TMP/atomic.weave"
grep -Eq 'lexical analysis failed|parse failed|formatting failed' "$TMP/broken.stderr"

set +e
"$WEAVEC" fmt --unknown "$TMP/formatted.weave" 2>"$TMP/usage.stderr"
usage_exit="$?"
set -e
[[ "$usage_exit" -eq 2 ]] || {
  printf 'formatter: expected usage exit 2, got %s\n' "$usage_exit" >&2
  exit 1
}
grep -Fq 'usage: weavec fmt' "$TMP/usage.stderr"

if compgen -G "$TMP/*.fmt.*" >/dev/null; then
  printf 'formatter: sibling temporary output leaked\n' >&2
  exit 1
fi

# A typed call whose callee signature the formatter cannot resolve on its own
# (struct-synthesized accessors are never a literal fn/extern declaration)
# must keep its original typed spelling rather than a guessed rewrite to bare
# `call`, since the compiler's own canonical-call resolver has the same gap
# and would otherwise reject the reformatted program as unresolved.
cp "$ROOT/test/correctness/surface/57_struct_basic.weave" "$TMP/struct.weave"
"$WEAVEC" build "$TMP/struct.weave" -o "$TMP/struct-original"
set +e
"$TMP/struct-original"
struct_original_exit="$?"
set -e
[[ "$struct_original_exit" -eq 42 ]] || {
  printf 'formatter: expected struct fixture native exit 42, got %s\n' \
    "$struct_original_exit" >&2
  exit 1
}
"$WEAVEC" fmt --output "$TMP/struct-formatted.weave" "$TMP/struct.weave"
grep -Fq '(call_i64 Buffer_get_len buf)' "$TMP/struct-formatted.weave"
"$WEAVEC" build "$TMP/struct-formatted.weave" -o "$TMP/struct-formatted"
set +e
"$TMP/struct-formatted"
struct_formatted_exit="$?"
set -e
[[ "$struct_formatted_exit" -eq 42 ]] || {
  printf 'formatter: expected formatted struct fixture native exit 42, got %s\n' \
    "$struct_formatted_exit" >&2
  exit 1
}
cp "$TMP/struct-formatted.weave" "$TMP/struct-twice.weave"
"$WEAVEC" fmt "$TMP/struct-twice.weave"
cmp "$TMP/struct-formatted.weave" "$TMP/struct-twice.weave"

cat > "$TMP/semantic-struct.weave" <<'EOF_SEMANTIC_STRUCT'
(program(name "semantic-struct-format")(version "0.1")
(struct Record(field total i64)(field flag bool)(field count i32))
(entry main(params)(returns i32)(do
(let record Record(new Record
; count field comment
(count(const_i32 40))
; total field comment
(total(const_i64 2))
; flag field comment
(flag(const_bool true))))
(return(op add(cast i32(field-get record total))(field-get record count))))))
EOF_SEMANTIC_STRUCT

"$WEAVEC" build "$TMP/semantic-struct.weave" \
  -o "$TMP/semantic-struct-original"
set +e
"$TMP/semantic-struct-original"
semantic_original_exit="$?"
set -e
[[ "$semantic_original_exit" -eq 42 ]] || {
  printf 'formatter: expected semantic struct exit 42, got %s\n' \
    "$semantic_original_exit" >&2
  exit 1
}

set +e
"$WEAVEC" fmt --check "$TMP/semantic-struct.weave"
semantic_check_exit="$?"
set -e
[[ "$semantic_check_exit" -eq 1 ]] || {
  printf 'formatter: expected unordered struct check exit 1, got %s\n' \
    "$semantic_check_exit" >&2
  exit 1
}

"$WEAVEC" fmt --output "$TMP/semantic-struct-formatted.weave" \
  "$TMP/semantic-struct.weave"
python3 - "$TMP/semantic-struct-formatted.weave" <<'PY'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text()
expected = [
    ("; total field comment", "(total 2)"),
    ("; flag field comment", "(flag true)"),
    ("; count field comment", "(count 40)"),
]
positions = []
for comment, field in expected:
    comment_at = text.index(comment)
    field_at = text.index(field)
    if comment_at >= field_at:
        raise SystemExit(f"comment did not move with {field}")
    positions.append(field_at)
if positions != sorted(positions):
    raise SystemExit("constructor fields are not in declaration order")
for legacy in ("const_i32", "const_i64", "const_bool"):
    if legacy in text:
        raise SystemExit(f"contextual constructor literal remained: {legacy}")
PY
"$WEAVEC" fmt --check "$TMP/semantic-struct-formatted.weave"
cp "$TMP/semantic-struct-formatted.weave" \
  "$TMP/semantic-struct-twice.weave"
"$WEAVEC" fmt "$TMP/semantic-struct-twice.weave"
cmp "$TMP/semantic-struct-formatted.weave" \
  "$TMP/semantic-struct-twice.weave"

"$WEAVEC" build "$TMP/semantic-struct-formatted.weave" \
  -o "$TMP/semantic-struct-formatted"
set +e
"$TMP/semantic-struct-formatted"
semantic_formatted_exit="$?"
set -e
[[ "$semantic_formatted_exit" -eq 42 ]] || {
  printf 'formatter: expected formatted semantic struct exit 42, got %s\n' \
    "$semantic_formatted_exit" >&2
  exit 1
}

cat > "$TMP/incomplete-struct.weave" <<'EOF_INCOMPLETE_STRUCT'
(program(name "incomplete-struct-format")(version "0.1")
(struct Record(field total i64)(field flag bool)(field count i32))
(entry main(params)(returns i32)(do
(let record Record(new Record(count(const_i32 40))(total(const_i64 2))))
(return 42))))
EOF_INCOMPLETE_STRUCT
"$WEAVEC" fmt --output "$TMP/incomplete-struct-formatted.weave" \
  "$TMP/incomplete-struct.weave"
python3 - "$TMP/incomplete-struct-formatted.weave" <<'PY'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text()
if text.index("(count") >= text.index("(total"):
    raise SystemExit("incomplete constructor was silently reordered")
PY

printf 'formatter: canonicalization, structs, comments, and atomicity passed\n'
