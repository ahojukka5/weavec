#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# A plain `weavec build` must report malformed sources on stderr. Machine-
# readable diagnostics are a separate opt-in concern covered by
# test/diagnostics/test-build-diagnostics.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-parse-diagnostics-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

expect_stderr() {
  local name="$1"
  local expected="$2"
  local source="$TMP/$name.weave"
  local binary="$TMP/$name"

  set +e
  "$WEAVEC" build "$source" -o "$binary" \
    >"$TMP/$name.stdout" 2>"$TMP/$name.stderr"
  local status="$?"
  set -e

  if [[ "$status" -eq 0 ]]; then
    printf 'parse-diagnostics: %s built successfully\n' "$name" >&2
    exit 1
  fi
  if [[ -e "$binary" ]]; then
    printf 'parse-diagnostics: %s published an executable\n' "$name" >&2
    exit 1
  fi
  if [[ -s "$TMP/$name.stdout" ]]; then
    printf 'parse-diagnostics: %s wrote unexpected stdout\n' "$name" >&2
    exit 1
  fi
  if ! grep -qF "$expected" "$TMP/$name.stderr"; then
    printf 'parse-diagnostics: %s missing expected stderr\n' "$name" >&2
    printf 'expected to contain: %s\n' "$expected" >&2
    cat "$TMP/$name.stderr" >&2
    exit 1
  fi
}

cat > "$TMP/unclosed.weave" <<'EOF'
(program
  (name "parse-diagnostics-unclosed")
  (version "0.1")
  (entry main
    (params)
    (returns i32)
    (do (return (const_i32 0))))
EOF
expect_stderr unclosed \
  'weavec: error: '"$TMP"'/unclosed.weave:1:1: unclosed list'

cat > "$TMP/unmatched.weave" <<'EOF'
(program
  (name "parse-diagnostics-unmatched")
  (version "0.1"))
)
EOF
expect_stderr unmatched \
  'weavec: error: '"$TMP"'/unmatched.weave:4:1: unmatched closing parenthesis'

cat > "$TMP/unterminated.weave" <<'EOF'
(program
  (name "parse-diagnostics-unterminated)
EOF
expect_stderr unterminated \
  'weavec: error: '"$TMP"'/unterminated.weave:2:9: unterminated string literal'

# A well-formed build keeps stderr silent and still produces an executable.
cat > "$TMP/good.weave" <<'EOF'
(program
  (name "parse-diagnostics-good")
  (version "0.1")
  (entry main
    (params)
    (returns i32)
    (do (return (const_i32 7)))))
EOF
"$WEAVEC" build "$TMP/good.weave" -o "$TMP/good" 2>"$TMP/good.stderr"
if [[ -s "$TMP/good.stderr" ]]; then
  printf 'parse-diagnostics: successful build wrote stderr\n' >&2
  cat "$TMP/good.stderr" >&2
  exit 1
fi
set +e
"$TMP/good"
good_status="$?"
set -e
if [[ "$good_status" -ne 7 ]]; then
  printf 'parse-diagnostics: expected exit 7, got %s\n' "$good_status" >&2
  exit 1
fi

# Option values must never be preflighted as sources. An explicit --project
# path is a directory or manifest, not compilable Weave.
PROJECT="$TMP/project"
mkdir -p "$PROJECT/src"
cat > "$PROJECT/weave.project" <<'EOF'
(weave-project
  (format 1)
  (name parse-diagnostics-project)
  (kind executable)
  (source-roots "src")
  (entry application)
  (output "application"))
EOF
cat > "$PROJECT/src/application.weave" <<'EOF'
(module application
  (entry main
    (params)
    (returns i32)
    (do (return (const_i32 5)))))
EOF
"$WEAVEC" build --project "$PROJECT" -o "$TMP/project-app" 2>"$TMP/project.stderr"
if [[ -s "$TMP/project.stderr" ]]; then
  printf 'parse-diagnostics: project build wrote stderr\n' >&2
  cat "$TMP/project.stderr" >&2
  exit 1
fi
set +e
"$TMP/project-app"
project_status="$?"
set -e
if [[ "$project_status" -ne 5 ]]; then
  printf 'parse-diagnostics: expected project exit 5, got %s\n' "$project_status" >&2
  exit 1
fi

printf 'parse-diagnostics: passed\n'
