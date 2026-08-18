#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Option, Result, and try (#149). Types come from the shipped stdlib
# modules; try unwraps Ok or returns Err.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-option-result-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'option-result: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}

OPTION="$ROOT/stdlib/option.weave"
RESULT="$ROOT/stdlib/result.weave"

expect_rejected() {
  local name="$1"
  local needle="$2"
  set +e
  "$WEAVEC" --frontend "$TMP/$name.wir" "$OPTION" "$RESULT" "$TMP/$name.weave" \
    >"$TMP/$name.stdout" 2>"$TMP/$name.stderr"
  local status="$?"
  set -e
  if [[ "$status" -eq 0 ]]; then
    printf 'option-result: %s was accepted\n' "$name" >&2
    exit 1
  fi
  if ! grep -Fq "$needle" "$TMP/$name.stderr"; then
    printf 'option-result: %s missing diagnostic\n' "$name" >&2
    printf 'expected: %s\n' "$needle" >&2
    cat "$TMP/$name.stderr" >&2
    exit 1
  fi
}

cat > "$TMP/parse.weave" <<'EOF'
(program
  (name "parse")
  (version "0.1")
  (fn parse-digit
    (params (n i32))
    (returns (type-app Result i32 i32))
    (do
      (if
        (condition (op less-than n 0))
        (then (do (return (variant Result (type-args i32 i32) Err 1))))
        (else (do (return (variant Result (type-args i32 i32) Ok n))))))))
EOF

cat > "$TMP/app.weave" <<'EOF'
(program
  (name "app")
  (version "0.1")
  (fn double
    (params (n i32))
    (returns (type-app Result i32 i32))
    (do
      (let v i32 (try (call parse-digit n)))
      (return (variant Result (type-args i32 i32) Ok (op add v v)))))
  (entry main
    (params)
    (returns i32)
    (do
      (let none (type-app Option i32) (variant Option (type-args i32) None))
      (let some (type-app Option i32) (variant Option (type-args i32) Some 4))
      (let r (type-app Result i32 i32) (call double 3))
      (return (match Result r
        (case Ok x x)
        (case Err e e))))))
EOF
"$WEAVEC" --frontend "$TMP/app.wir" "$OPTION" "$RESULT" \
  "$TMP/parse.weave" "$TMP/app.weave" \
  >"$TMP/app.stdout" 2>"$TMP/app.stderr" || {
  printf 'option-result: app rejected\n' >&2
  cat "$TMP/app.stdout" >&2
  cat "$TMP/app.stderr" >&2
  exit 1
}
for needle in \
  '(fn Option__s__i32_new_None' \
  '(fn Result__s__i32__i32_new_Ok' \
  '(fn Result__s__i32__i32_new_Err' \
  'Result__s__i32__i32_payload_Ok' \
  'Result__s__i32__i32_payload_Err' \
  'Result__s__i32__i32_new_Err'; do
  if ! grep -Fq "$needle" "$TMP/app.wir"; then
    printf 'option-result: app missing %s\n' "$needle" >&2
    cat "$TMP/app.wir" >&2
    exit 1
  fi
done

cat > "$TMP/not-result-fn.weave" <<'EOF'
(program
  (name "not-result-fn")
  (version "0.1")
  (entry main
    (params)
    (returns i32)
    (do
      (let v i32 (try (variant Result (type-args i32 i32) Ok 1)))
      (return v))))
EOF
expect_rejected not-result-fn 'try requires a Result-returning function'

cat > "$TMP/not-result-val.weave" <<'EOF'
(program
  (name "not-result-val")
  (version "0.1")
  (fn wrap
    (params (n i32))
    (returns (type-app Result i32 i32))
    (do
      (let v i32 (try n))
      (return (variant Result (type-args i32 i32) Ok v)))))
EOF
expect_rejected not-result-val 'try needs a Result value'

cat > "$TMP/err-mismatch.weave" <<'EOF'
(program
  (name "err-mismatch")
  (version "0.1")
  (fn wrap
    (params (n i32))
    (returns (type-app Result i32 i32))
    (do
      (let v i32 (try (variant Result (type-args i32 i64) Err (cast i64 1))))
      (return (variant Result (type-args i32 i32) Ok v)))))
EOF
expect_rejected err-mismatch 'try error type does not match the function Result'

printf 'option-result: passed\n'
