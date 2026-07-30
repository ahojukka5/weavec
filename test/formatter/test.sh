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
cmp "$TMP/original.wir" "$TMP/formatted.wir"

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

printf 'formatter: canonicalization, idempotence, comments, and atomicity passed\n'
