#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Deterministic (interp PIECE...) (#240). Admitted pieces are i32, i64,
# bool, and text. The result is ptr and lowers to helper calls.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-interp-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'interp: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}

expect_rejected() {
  local name="$1"
  local needle="$2"
  set +e
  "$WEAVEC" --frontend "$TMP/$name.wir" "$TMP/$name.weave" \
    >"$TMP/$name.stdout" 2>"$TMP/$name.stderr"
  local status="$?"
  set -e
  if [[ "$status" -eq 0 ]]; then
    printf 'interp: %s was accepted\n' "$name" >&2
    exit 1
  fi
  if ! grep -Fq "$needle" "$TMP/$name.stderr"; then
    printf 'interp: %s missing diagnostic\n' "$name" >&2
    printf 'expected: %s\n' "$needle" >&2
    cat "$TMP/$name.stderr" >&2
    exit 1
  fi
}

cat > "$TMP/ok.weave" <<'EOF'
(program
  (name "ok")
  (version "0.1")
  (extern puts (params (text ptr)) (returns i32))
  (entry main
    (params)
    (returns i32)
    (do
      (let n 7)
      (let flag true)
      (let msg (interp "n=" n " ok=" flag))
      (call puts msg)
      (return 0))))
EOF
"$WEAVEC" --frontend "$TMP/ok.wir" "$TMP/ok.weave" \
  2>"$TMP/ok.stderr" || {
  printf 'interp: ok rejected\n' >&2
  cat "$TMP/ok.stderr" >&2
  exit 1
}
grep -Fq '(call_ptr __weave_interp_concat' "$TMP/ok.wir"
grep -Fq '(call_ptr __weave_interp_i32' "$TMP/ok.wir"
grep -Fq '(call_ptr __weave_interp_bool' "$TMP/ok.wir"
grep -Fq '(fn __weave_interp_concat' "$TMP/ok.wir"
grep -Fq '(fn __weave_interp_i64' "$TMP/ok.wir"
grep -Fq '(const_string_ptr "n=")' "$TMP/ok.wir"
grep -Fq '(const_string_ptr " ok=")' "$TMP/ok.wir"

cat > "$TMP/empty.weave" <<'EOF'
(program
  (name "empty")
  (version "0.1")
  (entry main
    (params)
    (returns ptr)
    (do (return (interp)))))
EOF
"$WEAVEC" --frontend "$TMP/empty.wir" "$TMP/empty.weave" \
  2>"$TMP/empty.stderr" || {
  printf 'interp: empty rejected\n' >&2
  cat "$TMP/empty.stderr" >&2
  exit 1
}
grep -Fq '(const_string_ptr "")' "$TMP/empty.wir"

cat > "$TMP/text-only.weave" <<'EOF'
(program
  (name "text-only")
  (version "0.1")
  (entry main
    (params)
    (returns ptr)
    (do (return (interp "hello")))))
EOF
"$WEAVEC" --frontend "$TMP/text-only.wir" "$TMP/text-only.weave" \
  2>"$TMP/text-only.stderr" || {
  printf 'interp: text-only rejected\n' >&2
  cat "$TMP/text-only.stderr" >&2
  exit 1
}
grep -Fq '(const_string_ptr "hello")' "$TMP/text-only.wir"
if grep -Fq '__weave_interp_concat' "$TMP/text-only.wir"; then
  printf 'interp: single text piece used concat\n' >&2
  exit 1
fi

cat > "$TMP/float.weave" <<'EOF'
(program
  (name "float")
  (version "0.1")
  (entry main
    (params)
    (returns ptr)
    (do
      (let g 1.5)
      (return (interp "g=" g)))))
EOF
expect_rejected float 'interp cannot format a floating value'

cat > "$TMP/null-piece.weave" <<'EOF'
(program
  (name "null-piece")
  (version "0.1")
  (entry main
    (params)
    (returns ptr)
    (do (return (interp null)))))
EOF
expect_rejected null-piece 'interp cannot format null'

"$WEAVEC" fmt --output "$TMP/ok.fmt.weave" "$TMP/ok.weave"
grep -Fq '(interp "n=" n " ok=" flag)' "$TMP/ok.fmt.weave"
"$WEAVEC" fmt --check "$TMP/ok.fmt.weave"

"$WEAVEC" analyze "$TMP/ok.weave" \
  --semantic-index-json "$TMP/ok.index.json"
python3 - "$TMP/ok.index.json" <<'PY'
import json
import pathlib
import sys

doc = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
assert doc["analysis"]["status"] == "complete"
assert doc["analysis"]["complete"] is True
print("interp: semantic index passed")
PY

printf 'interp: passed\n'
