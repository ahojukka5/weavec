#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-module-diagnostics-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'module-diagnostics: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}

run_case() {
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
    printf 'module-diagnostics: %s returned %s instead of 10\n' \
      "$name" "$status" >&2
    exit 1
  }
  [[ ! -e "$TMP/$name" ]] || {
    printf 'module-diagnostics: %s published an executable\n' "$name" >&2
    exit 1
  }
  grep -Fq 'weavec: surface module:' "$TMP/$name.stderr"

  python3 - "$TMP/$name.json" "$code" "$role" "$text" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
expected_code = sys.argv[2]
expected_role = sys.argv[3]
expected_text = sys.argv[4].encode()

document = json.loads(path.read_text(encoding="utf-8"))
assert document["format"] == "weavec-diagnostics-v1"
assert document["status"] == "failed"
assert document["phase"] == "frontend"
assert document["exit_code"] == 10
assert len(document["diagnostics"]) == 1

diagnostic = document["diagnostics"][0]
assert diagnostic["code"] == expected_code
assert diagnostic["phase"] == "frontend"
assert diagnostic["severity"] == "error"
assert diagnostic["span_origin"] == "compiler-semantic"
assert diagnostic["analysis_complete"] is True
assert diagnostic["operand_role"] == expected_role
assert diagnostic["symbol"] == expected_text.decode()
assert diagnostic["candidates"] == []
assert diagnostic["related_locations"] == []
assert diagnostic["repairs"] == []

source = pathlib.Path(diagnostic["source"]).read_bytes()
span = diagnostic["span"]
actual = source[span["start_byte"]:span["end_byte"]]
assert actual == expected_text, (actual, expected_text)
PY
}

cat > "$TMP/missing-module.weave" <<'WEAVE'
(module application
  (import absent (answer))
  (entry main (params) (returns i32) (do (return (call answer)))))
WEAVE
run_case missing-module \
  frontend.module.import-missing-module import-module absent \
  "$TMP/missing-module.weave"

cat > "$TMP/private-library.weave" <<'WEAVE'
(module library
  (fn hidden (params) (returns i32) (do (return 42))))
WEAVE
cat > "$TMP/private-main.weave" <<'WEAVE'
(module application
  (import library (hidden))
  (entry main (params) (returns i32) (do (return (call hidden)))))
WEAVE
run_case private-import \
  frontend.module.import-private-symbol import-symbol hidden \
  "$TMP/private-main.weave" "$TMP/private-library.weave"

cat > "$TMP/library.weave" <<'WEAVE'
(module library
  (export answer)
  (fn answer (params) (returns i32) (do (return 42))))
WEAVE
cat > "$TMP/missing-symbol.weave" <<'WEAVE'
(module application
  (import library (other))
  (entry main (params) (returns i32) (do (return 0))))
WEAVE
run_case missing-symbol \
  frontend.module.import-missing-symbol import-symbol other \
  "$TMP/missing-symbol.weave" "$TMP/library.weave"

cat > "$TMP/unknown-export.weave" <<'WEAVE'
(module library
  (export absent)
  (fn answer (params) (returns i32) (do (return 42))))
WEAVE
run_case unknown-export \
  frontend.module.export-undeclared export-symbol absent \
  "$TMP/unknown-export.weave"

cat > "$TMP/duplicate-module-a.weave" <<'WEAVE'
(module duplicate
  (fn first (params) (returns i32) (do (return 1))))
WEAVE
cat > "$TMP/duplicate-module-b.weave" <<'WEAVE'
(module duplicate
  (fn second (params) (returns i32) (do (return 2))))
WEAVE
run_case duplicate-module \
  frontend.module.duplicate module-name duplicate \
  "$TMP/duplicate-module-a.weave" "$TMP/duplicate-module-b.weave"

cat > "$TMP/duplicate-export.weave" <<'WEAVE'
(module duplicate-export
  (export answer answer)
  (fn answer (params) (returns i32) (do (return 42))))
WEAVE
run_case duplicate-export \
  frontend.module.duplicate-export export-symbol answer \
  "$TMP/duplicate-export.weave"

cat > "$TMP/duplicate-import.weave" <<'WEAVE'
(module duplicate-import
  (import library (answer))
  (import library (answer))
  (entry main (params) (returns i32) (do (return (call answer)))))
WEAVE
run_case duplicate-import \
  frontend.module.duplicate-import import-symbol answer \
  "$TMP/duplicate-import.weave" "$TMP/library.weave"

cat > "$TMP/alpha.weave" <<'WEAVE'
(module alpha
  (export shared)
  (fn shared (params) (returns i32) (do (return 1))))
WEAVE
cat > "$TMP/beta.weave" <<'WEAVE'
(module beta
  (export shared)
  (fn shared (params) (returns i32) (do (return 2))))
WEAVE
cat > "$TMP/conflicting-import.weave" <<'WEAVE'
(module application
  (import alpha (shared))
  (import beta (shared))
  (entry main (params) (returns i32) (do (return 0))))
WEAVE
run_case conflicting-import \
  frontend.module.conflicting-import import-symbol shared \
  "$TMP/conflicting-import.weave" "$TMP/alpha.weave" "$TMP/beta.weave"

# The same source set must publish a byte-identical diagnostic document.
set +e
"$WEAVEC" build "$TMP/missing-module.weave" \
  -o "$TMP/missing-module-repeat" \
  --diagnostics-json "$TMP/missing-module-repeat.json" \
  >/dev/null 2>"$TMP/missing-module-repeat.stderr"
repeat_status="$?"
set -e
[[ "$repeat_status" -eq 10 ]]
cmp "$TMP/missing-module.json" "$TMP/missing-module-repeat.json"

printf 'module-diagnostics: structured interface failures passed\n'
