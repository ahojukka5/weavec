#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Authoritative local type inference (#238). (let NAME EXPR) is accepted
# when EXPR has one known type. Emitted WIR still names that type.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-let-infer-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'let-infer: compiler not found: %s\n' "$WEAVEC" >&2
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
    printf 'let-infer: %s was accepted\n' "$name" >&2
    exit 1
  fi
  if ! grep -Fq "$needle" "$TMP/$name.stderr"; then
    printf 'let-infer: %s missing diagnostic\n' "$name" >&2
    printf 'expected: %s\n' "$needle" >&2
    cat "$TMP/$name.stderr" >&2
    exit 1
  fi
}

cat > "$TMP/i32.weave" <<'EOF'
(program
  (name "i32")
  (version "0.1")
  (entry main
    (params)
    (returns i32)
    (do
      (let n 1)
      (return n))))
EOF
"$WEAVEC" --frontend "$TMP/i32.wir" "$TMP/i32.weave" \
  2>"$TMP/i32.stderr" || {
  printf 'let-infer: i32 rejected\n' >&2
  cat "$TMP/i32.stderr" >&2
  exit 1
}
grep -Fq '(let n i32 (const_i32 1))' "$TMP/i32.wir"

cat > "$TMP/f64.weave" <<'EOF'
(program
  (name "f64")
  (version "0.1")
  (entry main
    (params)
    (returns i32)
    (do
      (let gain 1.5)
      (return 0))))
EOF
"$WEAVEC" --frontend "$TMP/f64.wir" "$TMP/f64.weave" \
  2>"$TMP/f64.stderr" || {
  printf 'let-infer: f64 rejected\n' >&2
  cat "$TMP/f64.stderr" >&2
  exit 1
}
grep -Fq '(let gain f64 (const_f64 1.5))' "$TMP/f64.wir"

cat > "$TMP/generic.weave" <<'EOF'
(program
  (name "generic")
  (version "0.1")
  (fn identity
    (type-params T)
    (params (value T))
    (returns T)
    (do (return value)))
  (entry main
    (params)
    (returns i32)
    (do
      (let n (call identity (type-args i64) 1))
      (return 0))))
EOF
"$WEAVEC" --frontend "$TMP/generic.wir" "$TMP/generic.weave" \
  2>"$TMP/generic.stderr" || {
  printf 'let-infer: generic rejected\n' >&2
  cat "$TMP/generic.stderr" >&2
  exit 1
}
grep -Fq '(let n i64' "$TMP/generic.wir"

cat > "$TMP/if.weave" <<'EOF'
(program
  (name "if")
  (version "0.1")
  (entry main
    (params)
    (returns i32)
    (do
      (let n (if (condition true) (then 1) (else 2)))
      (return n))))
EOF
"$WEAVEC" --frontend "$TMP/if.wir" "$TMP/if.weave" \
  2>"$TMP/if.stderr" || {
  printf 'let-infer: if rejected\n' >&2
  cat "$TMP/if.stderr" >&2
  exit 1
}
grep -Fq '(let n i32' "$TMP/if.wir"

cat > "$TMP/explicit.weave" <<'EOF'
(program
  (name "explicit")
  (version "0.1")
  (entry main
    (params)
    (returns i32)
    (do
      (let n i32 3)
      (return n))))
EOF
"$WEAVEC" --frontend "$TMP/explicit.wir" "$TMP/explicit.weave" \
  2>"$TMP/explicit.stderr" || {
  printf 'let-infer: explicit rejected\n' >&2
  cat "$TMP/explicit.stderr" >&2
  exit 1
}
grep -Fq '(let n i32 (const_i32 3))' "$TMP/explicit.wir"

cat > "$TMP/null.weave" <<'EOF'
(program
  (name "null")
  (version "0.1")
  (entry main
    (params)
    (returns i32)
    (do
      (let p null)
      (return 0))))
EOF
"$WEAVEC" --frontend "$TMP/null.wir" "$TMP/null.weave" \
  2>"$TMP/null.stderr" || {
  printf 'let-infer: null rejected\n' >&2
  cat "$TMP/null.stderr" >&2
  exit 1
}
grep -Fq '(let p ptr (const_null))' "$TMP/null.wir"

cat > "$TMP/untyped.weave" <<'EOF'
(program
  (name "untyped")
  (version "0.1")
  (fn nope
    (params)
    (returns void)
    (do (return)))
  (entry main
    (params)
    (returns i32)
    (do
      (let n (call nope))
      (return 0))))
EOF
expect_rejected untyped 'let needs a type annotation'

"$WEAVEC" analyze "$TMP/i32.weave" \
  --semantic-index-json "$TMP/i32.index.json"
python3 - "$TMP/i32.index.json" <<'PY'
import json
import pathlib
import sys

doc = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
assert doc["analysis"]["status"] == "complete"
assert doc["analysis"]["complete"] is True
print("let-infer: semantic index passed")
PY

printf 'let-infer: passed\n'
