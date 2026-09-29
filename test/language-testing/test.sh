#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-language-testing-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'language-testing: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}

cat > "$TMP/legacy.weave" <<'EOF'
(program
  (name "legacy")
  (version "0.1")
  (fn id ((value i32)) i32
    (return value)))
EOF
"$WEAVEC" fmt "$TMP/legacy.weave"
"$WEAVEC" fmt --check "$TMP/legacy.weave"

cat > "$TMP/tags.weave" <<'EOF'
(module arithmetic
  (fn add-two ((a i32) (b i32)) i32
    (return (+ a b)))
  (test add-two-basic
    (tags unit slow)
    (do
      (expect-eq (add-two 40 2) 42))))
EOF
"$WEAVEC" fmt "$TMP/tags.weave"
"$WEAVEC" fmt --check "$TMP/tags.weave"
grep -q '(tags slow unit)' "$TMP/tags.weave" || {
  printf 'language-testing: tags were not sorted\n' >&2
  cat "$TMP/tags.weave" >&2
  exit 1
}

reject() {
  local name="$1"
  local code="$2"
  local path="$TMP/$name.weave"
  set +e
  local stderr
  stderr="$("$WEAVEC" fmt "$path" 2>&1)"
  local status="$?"
  set -e
  [[ "$status" -eq 3 ]] || {
    printf 'language-testing: %s exited %s, want 3\n' "$name" "$status" >&2
    printf '%s\n' "$stderr" >&2
    exit 1
  }
  printf '%s\n' "$stderr" | grep -q "\\[$code\\]" || {
    printf 'language-testing: %s missing [%s]\n%s\n' "$name" "$code" "$stderr" >&2
    exit 1
  }
  printf '%s\n' "$stderr" | grep -q ':[0-9][0-9]*:[0-9][0-9]*:' || {
    printf 'language-testing: %s missing an exact span\n%s\n' "$name" "$stderr" >&2
    exit 1
  }
}

cat > "$TMP/malformed.weave" <<'EOF'
(module m
  (test 1bad
    (do
      (expect true))))
EOF
reject malformed test.malformed-name

cat > "$TMP/duplicate.weave" <<'EOF'
(module m
  (test t
    (tags unit unit)
    (do
      (expect true))))
EOF
reject duplicate test.duplicate-tag

cat > "$TMP/nested.weave" <<'EOF'
(module m
  (test outer
    (do
      (test inner
        (do
          (expect true))))))
EOF
reject nested test.nested

printf 'language-testing: formatter admits tests and rejects surface errors\n'
