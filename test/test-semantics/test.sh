#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-test-semantics-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'test-semantics: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}

fail_case() {
  local name="$1"
  local code="$2"
  local role="$3"
  local text="$4"
  shift 4

  rm -f "$TMP/$name" "$TMP/$name.json"
  set +e
  "$WEAVEC" build "$@" \
    -o "$TMP/$name" \
    --diagnostics-json "$TMP/$name.json" \
    >"$TMP/$name.stdout" 2>"$TMP/$name.stderr"
  local status="$?"
  set -e

  [[ "$status" -eq 10 ]] || {
    printf 'test-semantics: %s returned %s instead of 10\n' "$name" "$status" >&2
    cat "$TMP/$name.stderr" >&2
    exit 1
  }
  [[ ! -e "$TMP/$name" ]] || {
    printf 'test-semantics: %s published an executable\n' "$name" >&2
    exit 1
  }
  grep -Fq 'weavec: surface test:' "$TMP/$name.stderr"
  python3 - "$TMP/$name.json" "$code" "$role" "$text" <<'PY'
import json
import pathlib
import sys

path, code, role, text = sys.argv[1:]
document = json.loads(pathlib.Path(path).read_text(encoding="utf-8"))
assert document["status"] == "failed"
assert document["phase"] == "frontend"
diagnostic = document["diagnostics"][0]
assert diagnostic["code"] == code, diagnostic
assert diagnostic["operand_role"] == role, diagnostic
assert diagnostic["symbol"] == text, diagnostic
PY
}

ok_frontend() {
  local name="$1"
  shift
  set +e
  "$WEAVEC" --frontend "$TMP/$name.wir" "$@" \
    >"$TMP/$name.stdout" 2>"$TMP/$name.stderr"
  local status="$?"
  set -e
  [[ "$status" -eq 0 ]] || {
    printf 'test-semantics: %s frontend returned %s\n' "$name" "$status" >&2
    cat "$TMP/$name.stderr" >&2
    exit 1
  }
  if grep -Fq 'test.private-cross-module' "$TMP/$name.stderr"; then
    printf 'test-semantics: %s reported a private cross-module use\n' "$name" >&2
    exit 1
  fi
}

cat > "$TMP/duplicate.weave" <<'WEAVE'
(module m
  (test twice
    (do))
  (test twice
    (do)))
WEAVE
fail_case duplicate test.duplicate-name test-name twice "$TMP/duplicate.weave"

cat > "$TMP/fn-collision.weave" <<'WEAVE'
(module m
  (fn t
    (params)
    (returns i32)
    (do (return 0)))
  (test t
    (do)))
WEAVE
fail_case fn-collision test.collision test-name t "$TMP/fn-collision.weave"

cat > "$TMP/const-collision.weave" <<'WEAVE'
(module m
  (const LIMIT i32 100)
  (test LIMIT
    (do)))
WEAVE
fail_case const-collision test.collision test-name LIMIT "$TMP/const-collision.weave"

cat > "$TMP/entry-collision.weave" <<'WEAVE'
(module m
  (entry main
    (params)
    (returns i32)
    (do (return 0)))
  (test main
    (do)))
WEAVE
fail_case entry-collision test.collision test-name main "$TMP/entry-collision.weave"

cat > "$TMP/secret.weave" <<'WEAVE'
(module secret
  (fn hidden
    (params)
    (returns i32)
    (do (return 1))))
WEAVE
cat > "$TMP/user.weave" <<'WEAVE'
(module user
  (test peek
    (do
      (expect-eq (hidden) 1))))
WEAVE
fail_case private-cross-module \
  test.private-cross-module test-use hidden \
  "$TMP/secret.weave" "$TMP/user.weave"

cat > "$TMP/same-a.weave" <<'WEAVE'
(module alpha
  (test same
    (do)))
WEAVE
cat > "$TMP/same-b.weave" <<'WEAVE'
(module beta
  (test same
    (do)))
WEAVE
ok_frontend shared-name "$TMP/same-a.weave" "$TMP/same-b.weave"

cat > "$TMP/local-private.weave" <<'WEAVE'
(module owner
  (fn hidden
    (params)
    (returns i32)
    (do (return 1)))
  (test peek
    (do
      (expect-eq (hidden) 1))))
WEAVE
ok_frontend same-module-private "$TMP/local-private.weave"

cat > "$TMP/exported.weave" <<'WEAVE'
(module secret
  (export hidden)
  (fn hidden
    (params)
    (returns i32)
    (do (return 1))))
WEAVE
cat > "$TMP/exported-user.weave" <<'WEAVE'
(module user
  (test peek
    (do
      (expect-eq (hidden) 1))))
WEAVE
ok_frontend exported-foreign \
  "$TMP/exported.weave" "$TMP/exported-user.weave"

cat > "$TMP/let-local.weave" <<'WEAVE'
(module secret
  (fn hidden
    (params)
    (returns i32)
    (do (return 1))))
WEAVE
cat > "$TMP/let-user.weave" <<'WEAVE'
(module user
  (test peek
    (do
      (let hidden i32 1))))
WEAVE
ok_frontend let-binder "$TMP/let-local.weave" "$TMP/let-user.weave"

cat > "$TMP/indexed.weave" <<'WEAVE'
(module arithmetic
  (export add-two)
  (fn add-two
    (params (left i32) (right i32))
    (returns i32)
    (do (return 0)))
  (test add-two-basic
    (tags unit slow)
    (do)))
WEAVE
"$WEAVEC" analyze "$TMP/indexed.weave" \
  --semantic-index-json "$TMP/indexed.json"
"$WEAVEC" analyze "$TMP/indexed.weave" \
  --semantic-index-json "$TMP/indexed-again.json"
cmp "$TMP/indexed.json" "$TMP/indexed-again.json"
python3 - "$TMP/indexed.json" <<'PY'
import json
import pathlib
import sys

doc = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
assert doc["analysis"]["status"] == "complete"
tests = doc["tests"]
assert len(tests) == 1
assert tests[0]["name"] == "add-two-basic"
assert tests[0]["module"] == "arithmetic"
assert tests[0]["tags"] == ["unit", "slow"]
assert tests[0]["span"]["end"] > tests[0]["span"]["start"]
assert all(symbol["kind"] != "test" for symbol in doc["symbols"])
PY

cat > "$TMP/plain.weave" <<'WEAVE'
(program
  (name "plain")
  (version "0.1")
  (fn main
    (params)
    (returns i32)
    (do (return 0))))
WEAVE
"$WEAVEC" analyze "$TMP/plain.weave" \
  --semantic-index-json "$TMP/plain.json"
python3 - "$TMP/plain.json" <<'PY'
import json
import pathlib
import sys

doc = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
assert doc["analysis"]["status"] == "complete"
assert "tests" not in doc
PY

set +e
"$WEAVEC" analyze "$TMP/duplicate.weave" \
  --semantic-index-json "$TMP/failed.json" \
  >"$TMP/failed.stdout" 2>"$TMP/failed.stderr"
status="$?"
set -e
[[ "$status" -ne 0 ]]
python3 - "$TMP/failed.json" <<'PY'
import json
import pathlib
import sys

doc = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
assert doc["analysis"]["status"] == "failed"
assert "tests" not in doc
assert doc["symbols"] == []
PY

printf 'test-semantics: passed\n'
