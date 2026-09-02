#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Command-line and file-I/O failures must report a stable diagnostic code and a
# human message instead of exiting silently. The low-level compiler modes keep
# their historical exit status; only stderr gains content. Machine-readable
# `weavec build` diagnostics are covered here for the newly classified
# end-of-input case and in test/diagnostics/test-build-diagnostics.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-cli-diagnostics-XXXXXX")"
trap 'chmod -R u+rwX "$TMP" 2>/dev/null || true; rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'cli-diagnostics: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}

checks=0

# Run weavec, then require the exact exit status and every expected stderr
# fragment. stdout must stay empty on a failing invocation.
expect_failure() {
  local name="$1"
  local expected_exit="$2"
  shift 2
  local -a fragments=()
  while [[ "$#" -gt 0 && "$1" != "--" ]]; do
    fragments+=("$1")
    shift
  done
  [[ "$#" -gt 0 ]] && shift

  set +e
  "$WEAVEC" "$@" >"$TMP/$name.stdout" 2>"$TMP/$name.stderr"
  local status="$?"
  set -e

  if [[ "$status" -ne "$expected_exit" ]]; then
    printf 'cli-diagnostics: %s expected exit %s, got %s\n' \
      "$name" "$expected_exit" "$status" >&2
    cat "$TMP/$name.stderr" >&2
    exit 1
  fi
  if [[ -s "$TMP/$name.stdout" ]]; then
    printf 'cli-diagnostics: %s wrote unexpected stdout\n' "$name" >&2
    exit 1
  fi
  if [[ ! -s "$TMP/$name.stderr" ]]; then
    printf 'cli-diagnostics: %s failed with an empty stderr\n' "$name" >&2
    exit 1
  fi
  local fragment
  for fragment in "${fragments[@]}"; do
    if ! grep -qF -- "$fragment" "$TMP/$name.stderr"; then
      printf 'cli-diagnostics: %s missing stderr fragment\n' "$name" >&2
      printf 'expected to contain: %s\n' "$fragment" >&2
      cat "$TMP/$name.stderr" >&2
      exit 1
    fi
  done
  checks=$((checks + 1))
}

cat > "$TMP/valid.weave" <<'EOF'
(program
  (name "cli-diagnostics-valid")
  (version "0.1")
  (entry main
    (params)
    (returns i32)
    (do (return (const_i32 0)))))
EOF

cat > "$TMP/valid.wir" <<'EOF'
(core-module (core-version 3) (decls))
EOF

MISSING="$TMP/does-not-exist.weave"
MISSING_WIR="$TMP/does-not-exist.wir"

# --- Malformed command lines -------------------------------------------------

expect_failure no-command 1 \
  'weavec: error: missing command [driver.usage.missing-command]' \
  'usage:' \
  '  weavec build <input.weave> [input2.weave ...] -o <program>' \
  --

expect_failure unknown-command 1 \
  'weavec: error: unknown command or option: bogus-mode [driver.usage.unknown-command]' \
  'usage:' \
  -- bogus-mode

expect_failure unknown-option 1 \
  'weavec: error: unknown command or option: --not-a-mode [driver.usage.unknown-command]' \
  -- --not-a-mode

expect_failure version-extra 1 \
  'weavec: error: wrong arguments for --version [driver.usage.invalid-arguments]' \
  -- --version extra

expect_failure capabilities-arity 1 \
  'weavec: error: wrong arguments for capabilities [driver.usage.invalid-arguments]' \
  -- capabilities

expect_failure capabilities-option 1 \
  'weavec: error: capabilities accepts only --json, got --xml [driver.usage.invalid-arguments]' \
  -- capabilities --xml

expect_failure backend-arity 1 \
  'weavec: error: wrong arguments for --backend [driver.usage.invalid-arguments]' \
  -- --backend "$TMP/valid.wir"

expect_failure frontend-arity 1 \
  'weavec: error: wrong arguments for --frontend [driver.usage.invalid-arguments]' \
  -- --frontend "$TMP/out.wir"

expect_failure frontend-missing-output 1 \
  'weavec: error: wrong arguments for --frontend [driver.usage.invalid-arguments]' \
  -- --frontend --strict-contracts "$TMP/out.wir"

expect_failure quantum-arity 1 \
  'weavec: error: wrong arguments for --dump-quantum-stats [driver.usage.invalid-arguments]' \
  -- --dump-quantum-stats "$TMP/out.metrics"

expect_failure explain-arity 1 \
  'weavec: error: wrong arguments for --explain [driver.usage.invalid-arguments]' \
  -- --explain "$TMP/valid.weave" extra

expect_failure explain-json-arity 1 \
  'weavec: error: wrong arguments for --explain-json [driver.usage.invalid-arguments]' \
  -- --explain-json

expect_failure audit-arity 1 \
  'weavec: error: wrong arguments for --audit [driver.usage.invalid-arguments]' \
  -- --audit

expect_failure audit-json-arity 1 \
  'weavec: error: wrong arguments for --audit-json [driver.usage.invalid-arguments]' \
  -- --audit-json

# --- Missing input files -----------------------------------------------------

expect_failure frontend-missing-source 1 \
  "weavec: error: $MISSING: cannot read source file [frontend.source-unreadable]" \
  -- --frontend "$TMP/out.wir" "$MISSING"

expect_failure explain-missing-source 1 \
  "weavec: error: $MISSING: cannot read source file [frontend.source-unreadable]" \
  -- --explain "$MISSING"

expect_failure explain-json-missing-source 1 \
  "weavec: error: $MISSING: cannot read source file [frontend.source-unreadable]" \
  -- --explain-json "$MISSING"

expect_failure audit-missing-source 1 \
  "weavec: error: $MISSING: cannot read source file [frontend.source-unreadable]" \
  -- --audit "$MISSING"

expect_failure audit-json-missing-source 1 \
  "weavec: error: $MISSING: cannot read source file [frontend.source-unreadable]" \
  -- --audit-json "$MISSING"

expect_failure quantum-missing-source 1 \
  "weavec: error: $MISSING: cannot read source file [frontend.source-unreadable]" \
  -- --dump-quantum-stats "$TMP/out.metrics" "$MISSING"

expect_failure backend-missing-input 1 \
  "weavec: error: $MISSING_WIR: cannot read WIR input file [backend.input-unreadable]" \
  -- --backend "$MISSING_WIR" "$TMP/out.ll"

# --- Unreadable input files --------------------------------------------------

if [[ "$(id -u)" != 0 ]]; then
  cp "$TMP/valid.weave" "$TMP/unreadable.weave"
  cp "$TMP/valid.wir" "$TMP/unreadable.wir"
  chmod 000 "$TMP/unreadable.weave" "$TMP/unreadable.wir"

  expect_failure frontend-unreadable-source 1 \
    "weavec: error: $TMP/unreadable.weave: cannot read source file [frontend.source-unreadable]" \
    -- --frontend "$TMP/out.wir" "$TMP/unreadable.weave"

  expect_failure explain-unreadable-source 1 \
    "weavec: error: $TMP/unreadable.weave: cannot read source file [frontend.source-unreadable]" \
    -- --explain "$TMP/unreadable.weave"

  expect_failure backend-unreadable-input 1 \
    "weavec: error: $TMP/unreadable.wir: cannot read WIR input file [backend.input-unreadable]" \
    -- --backend "$TMP/unreadable.wir" "$TMP/out.ll"
else
  printf 'cli-diagnostics: skipping unreadable-file checks as root\n'
fi

# --- Unwritable outputs ------------------------------------------------------

expect_failure frontend-unwritable-output 1 \
  'weavec: error: /nonexistent-weavec-directory/out.wir: cannot create output file [driver.output-unwritable]' \
  -- --frontend /nonexistent-weavec-directory/out.wir "$TMP/valid.weave"

expect_failure quantum-unwritable-output 1 \
  'weavec: error: /nonexistent-weavec-directory/out.metrics: cannot create output file [driver.output-unwritable]' \
  -- --dump-quantum-stats /nonexistent-weavec-directory/out.metrics "$TMP/valid.weave"

# --- Positioned parse errors -------------------------------------------------

cat > "$TMP/unclosed.weave" <<'EOF'
(program
  (name "cli-diagnostics-unclosed")
  (version "0.1")
  (entry main
    (params)
    (returns i32)
    (do (return (const_i32 0))))
EOF
expect_failure frontend-unclosed 1 \
  "weavec: error: $TMP/unclosed.weave:1:1: unclosed list [frontend.parse.unclosed-list]" \
  -- --frontend "$TMP/out.wir" "$TMP/unclosed.weave"

# The innermost open list owns the reported position, on its own line and
# column, so a caller can jump straight to the offending parenthesis.
printf '(program\n  (name "x")\n  (entry main\n' > "$TMP/nested.weave"
expect_failure frontend-unclosed-nested 1 \
  "weavec: error: $TMP/nested.weave:3:3: unclosed list [frontend.parse.unclosed-list]" \
  -- --frontend "$TMP/out.wir" "$TMP/nested.weave"

# A leading closing parenthesis leaves nothing an S-expression can start with.
# Trailing junk after a complete root form is still ignored by the parser and
# is reported by the build driver's preflight scanner instead.
printf ')\n' > "$TMP/only-stray.weave"
expect_failure frontend-only-stray-paren 1 \
  "weavec: error: $TMP/only-stray.weave:1:1: unmatched closing parenthesis [frontend.parse.unmatched-closing-paren]" \
  -- --frontend "$TMP/out.wir" "$TMP/only-stray.weave"

: > "$TMP/empty.weave"
expect_failure frontend-empty 1 \
  "weavec: error: $TMP/empty.weave:1:1: unexpected end of input; expected an expression [frontend.parse.unexpected-end-of-input]" \
  -- --frontend "$TMP/out.wir" "$TMP/empty.weave"

expect_failure explain-unclosed 1 \
  "weavec: error: $TMP/unclosed.weave:1:1: unclosed list [frontend.parse.unclosed-list]" \
  -- --explain "$TMP/unclosed.weave"

expect_failure quantum-unclosed 1 \
  "weavec: error: $TMP/unclosed.weave:1:1: unclosed list [frontend.parse.unclosed-list]" \
  -- --dump-quantum-stats "$TMP/out.metrics" "$TMP/unclosed.weave"

printf '(core-module (core-version 3)\n  (decls)\n' > "$TMP/unclosed.wir"
expect_failure backend-unclosed 1 \
  "weavec: error: $TMP/unclosed.wir:1:1: unclosed list [backend.parse.unclosed-list]" \
  -- --backend "$TMP/unclosed.wir" "$TMP/out.ll"

: > "$TMP/empty.wir"
expect_failure backend-empty 1 \
  "weavec: error: $TMP/empty.wir:1:1: unexpected end of input; expected an expression [backend.parse.unexpected-end-of-input]" \
  -- --backend "$TMP/empty.wir" "$TMP/out.ll"

printf ')\n' > "$TMP/stray.wir"
expect_failure backend-stray-paren 1 \
  "weavec: error: $TMP/stray.wir:1:1: unmatched closing parenthesis [backend.parse.unmatched-closing-paren]" \
  -- --backend "$TMP/stray.wir" "$TMP/out.ll"

# --- Malformed WIR module ----------------------------------------------------

printf '(core-module (core-version 3))\n' > "$TMP/no-decls.wir"
expect_failure backend-no-decls 1 \
  "weavec: error: $TMP/no-decls.wir: WIR module has no (decls ...) section [backend.invalid-module]" \
  -- --backend "$TMP/no-decls.wir" "$TMP/out.ll"

# --- `weavec build` reports an input with no S-expression at all -------------

expect_failure build-empty-human 1 \
  "weavec: error: $TMP/empty.weave:1:1: unexpected end of input; expected an expression" \
  -- build "$TMP/empty.weave" -o "$TMP/empty-program"

printf '; only a comment, no program\n' > "$TMP/comment-only.weave"
expect_failure build-comment-only-human 1 \
  "weavec: error: $TMP/comment-only.weave:2:1: unexpected end of input; expected an expression" \
  -- build "$TMP/comment-only.weave" -o "$TMP/comment-only-program"

# Stable public phase exit 10 and a classified weavec-diagnostics-v1 entry.
expect_failure build-empty-json 10 \
  "weavec: error: $TMP/empty.weave:1:1: unexpected end of input; expected an expression" \
  -- build "$TMP/empty.weave" -o "$TMP/empty-program" \
  --diagnostics-json "$TMP/empty.diagnostics.json"

python3 - "$TMP/empty.diagnostics.json" "$TMP/empty.weave" <<'PY'
import json
import sys

document = json.load(open(sys.argv[1]))
assert document["format"] == "weavec-diagnostics-v1", document["format"]
assert document["status"] == "failed", document["status"]
assert document["phase"] == "frontend", document["phase"]
assert document["exit_code"] == 10, document["exit_code"]
assert document["raw_exit_code"] == 1, document["raw_exit_code"]
entries = document["diagnostics"]
assert len(entries) == 1, entries
entry = entries[0]
assert entry["code"] == "frontend.parse.unexpected-end-of-input", entry["code"]
assert entry["severity"] == "error", entry["severity"]
assert entry["phase"] == "frontend", entry["phase"]
assert entry["source"] == sys.argv[2], entry["source"]
assert entry["span_origin"] == "compiler-preflight", entry["span_origin"]
span = entry["span"]
assert span is not None
assert span["start_byte"] == 0 and span["end_byte"] == 0, span
assert span["start_line"] == 1 and span["start_column"] == 1, span
assert entry["candidates"] == []
assert entry["related_locations"] == []
assert entry["repairs"] == []
PY

[[ ! -e "$TMP/empty-program" ]] || {
  printf 'cli-diagnostics: a failed build published an executable\n' >&2
  exit 1
}

# A missing explicit source keeps its existing classification.
expect_failure build-missing-json 10 \
  "weavec: error: $MISSING: cannot read source file" \
  -- build "$MISSING" -o "$TMP/missing-program" \
  --diagnostics-json "$TMP/missing.diagnostics.json"

python3 - "$TMP/missing.diagnostics.json" <<'PY'
import json
import sys

document = json.load(open(sys.argv[1]))
entry = document["diagnostics"][0]
assert entry["code"] == "frontend.source-unreadable", entry["code"]
assert document["exit_code"] == 10, document["exit_code"]
PY

# --- Success paths stay silent ----------------------------------------------

"$WEAVEC" --frontend "$TMP/ok.wir" "$TMP/valid.weave" \
  >"$TMP/ok.stdout" 2>"$TMP/ok.stderr"
[[ -s "$TMP/ok.stderr" ]] && {
  printf 'cli-diagnostics: successful --frontend wrote stderr\n' >&2
  cat "$TMP/ok.stderr" >&2
  exit 1
}
"$WEAVEC" --backend "$TMP/valid.wir" "$TMP/ok.ll" \
  >"$TMP/ok-backend.stdout" 2>"$TMP/ok-backend.stderr"
[[ -s "$TMP/ok-backend.stderr" ]] && {
  printf 'cli-diagnostics: successful --backend wrote stderr\n' >&2
  cat "$TMP/ok-backend.stderr" >&2
  exit 1
}
"$WEAVEC" --version >/dev/null 2>"$TMP/version.stderr"
[[ -s "$TMP/version.stderr" ]] && {
  printf 'cli-diagnostics: --version wrote stderr\n' >&2
  exit 1
}

printf 'cli-diagnostics: %s diagnosed failures passed\n' "$checks"
