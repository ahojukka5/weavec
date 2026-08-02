#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-module-collisions-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'module-collisions: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}

cat > "$TMP/library.weave" <<'WEAVE'
(module library
  (export answer)
  (fn answer
    (params)
    (returns i32)
    (do (return 42))))
WEAVE

cat > "$TMP/application.weave" <<'WEAVE'
(module application
  (import library (answer))
  (fn answer
    (params)
    (returns i32)
    (do (return 7)))
  (entry main
    (params)
    (returns i32)
    (do (return (call answer)))))
WEAVE

run_collision() {
  local name="$1"
  shift

  set +e
  "$WEAVEC" build "$@" \
    -o "$TMP/$name" \
    --diagnostics-json "$TMP/$name.json" \
    >"$TMP/$name.stdout" 2>"$TMP/$name.stderr"
  local status="$?"
  set -e

  [[ "$status" -eq 10 ]] || {
    printf 'module-collisions: %s returned %s instead of 10\n' \
      "$name" "$status" >&2
    exit 1
  }
  [[ ! -e "$TMP/$name" ]] || {
    printf 'module-collisions: %s published an executable\n' "$name" >&2
    exit 1
  }
  grep -Fq \
    'weavec: surface module: imported binding conflicts with local declaration answer' \
    "$TMP/$name.stderr"

  python3 - "$TMP/$name.json" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
document = json.loads(path.read_text(encoding="utf-8"))
assert document["format"] == "weavec-diagnostics-v1"
assert document["status"] == "failed"
assert document["phase"] == "frontend"
assert document["exit_code"] == 10
assert len(document["diagnostics"]) == 1

diagnostic = document["diagnostics"][0]
assert diagnostic["code"] == "frontend.module.import-local-collision"
assert diagnostic["phase"] == "frontend"
assert diagnostic["severity"] == "error"
assert diagnostic["span_origin"] == "compiler-semantic"
assert diagnostic["analysis_complete"] is True
assert diagnostic["operand_role"] == "import-symbol"
assert diagnostic["symbol"] == "answer"
assert diagnostic["candidates"] == []
assert diagnostic["related_locations"] == []
assert diagnostic["repairs"] == []

source_path = pathlib.Path(diagnostic["source"])
assert source_path.name == "application.weave"
source = source_path.read_bytes()
span = diagnostic["span"]
actual = source[span["start_byte"]:span["end_byte"]]
assert actual == b"answer", actual
PY
}

run_collision application-first \
  "$TMP/application.weave" "$TMP/library.weave"
run_collision library-first \
  "$TMP/library.weave" "$TMP/application.weave"

cmp "$TMP/application-first.json" "$TMP/library-first.json"
cmp "$TMP/application-first.stderr" "$TMP/library-first.stderr"

printf 'module-collisions: local import collision diagnostics passed\n'
