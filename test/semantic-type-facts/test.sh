#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Structured type and specialization facts (#150).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-type-facts-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'semantic-type-facts: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}

cat > "$TMP/types.weave" <<'EOF'
(program
  (name "types")
  (version "0.1")
  (enum Option
    (type-params T)
    (variant None)
    (variant Some T))
  (fn identity
    (type-params T)
    (params (value T))
    (returns T)
    (do (return value)))
  (fn wrap
    (params (n i32))
    (returns (type-app Option i32))
    (do
      (let some (type-app Option i32) (variant Option (type-args i32) Some n))
      (return (match Option some
        (case None (variant Option (type-args i32) None))
        (case Some x (variant Option (type-args i32) Some x))))))
  (entry main
    (params)
    (returns i32)
    (do
      (let v i32 (call identity (type-args i32) 1))
      (return v))))
EOF

"$WEAVEC" analyze "$TMP/types.weave" \
  --semantic-index-json "$TMP/first.json"
"$WEAVEC" analyze "$TMP/types.weave" \
  --semantic-index-json "$TMP/second.json"
cmp "$TMP/first.json" "$TMP/second.json"

python3 - "$TMP/first.json" \
  "$ROOT/docs/schemas/weavec-semantic-index-v1.schema.json" <<'PY'
import json
import pathlib
import sys

doc = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
schema = json.loads(pathlib.Path(sys.argv[2]).read_text(encoding="utf-8"))
assert doc["format"] == "weavec-semantic-index-v1"
assert doc["analysis"]["status"] == "complete"
assert doc["analysis"]["complete"] is True

kinds = schema["$defs"]["symbol"]["properties"]["kind"]["enum"]
assert "enum" in kinds
assert "variant" in kinds
roles = schema["$defs"]["reference"]["properties"]["role"]["enum"]
assert "construct" in roles
assert "pattern" in roles

symbols = {symbol["name"]: symbol for symbol in doc["symbols"]}
assert symbols["Option"]["kind"] == "enum"
assert "(type-params T)" in symbols["Option"]["signature"]["canonical"]
assert "(variant None)" in symbols["Option"]["signature"]["canonical"]
assert symbols["None"]["kind"] == "variant"
assert symbols["Some"]["kind"] == "variant"
assert symbols["identity"]["signature"]["canonical"].startswith(
    "(fn (type-params T)"
)

type_names = [
    ref for ref in doc["references"] if ref["role"] == "type"
]
constructs = [
    ref for ref in doc["references"] if ref["role"] == "construct"
]
patterns = [
    ref for ref in doc["references"] if ref["role"] == "pattern"
]
assert constructs
assert patterns
assert all(ref["status"] == "resolved" for ref in constructs)
assert all(ref["status"] == "resolved" for ref in patterns)

fn_specs = [
    item for item in doc["specializations"] if item["kind"] == "fn"
]
enum_specs = [
    item for item in doc["specializations"] if item["kind"] == "enum"
]
assert any(item["specialized_name"] == "identity__s__i32" for item in fn_specs)
assert any(item["specialized_name"] == "Option__s__i32" for item in enum_specs)
assert doc["matches"]
assert doc["matches"][0]["exhaustive"] is True
assert doc["matches"][0]["wildcard"] is False
assert doc["matches"][0]["arm_count"] == 2
assert doc["matches"][0]["enum_symbol_id"] == symbols["Option"]["id"]
print("semantic-type-facts: success document passed")
PY

cat > "$TMP/option.weave" <<'EOF'
(program
  (name "option")
  (version "0.1")
  (enum Option
    (type-params T)
    (variant None)
    (variant Some T)))
EOF
cat > "$TMP/app.weave" <<'EOF'
(program
  (name "app")
  (version "0.1")
  (entry main
    (params)
    (returns i32)
    (do
      (let some (type-app Option i32) (variant Option (type-args i32) Some 4))
      (return (match Option some
        (case None 0)
        (case Some x x))))))
EOF
"$WEAVEC" analyze "$TMP/option.weave" "$TMP/app.weave" \
  --semantic-index-json "$TMP/cross-file.json"
python3 - "$TMP/cross-file.json" <<'PY'
import json
import pathlib
import sys

doc = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
assert doc["analysis"]["status"] == "complete"
assert doc["analysis"]["complete"] is True
constructs = [
    item for item in doc["references"] if item["role"] == "construct"
]
patterns = [
    item for item in doc["references"] if item["role"] == "pattern"
]
assert constructs
assert patterns
assert all(item["status"] == "resolved" for item in constructs)
assert all(item["status"] == "resolved" for item in patterns)
assert doc["matches"]
assert doc["matches"][0]["exhaustive"] is True
assert doc["matches"][0]["enum_symbol_id"] is not None
print("semantic-type-facts: cross-file document passed")
PY

cat > "$TMP/bad.weave" <<'EOF'
(program
  (name "bad")
  (version "0.1")
  (enum Color
    (variant Red)
    (variant Red))
  (entry main (params) (returns i32) (do (return 0))))
EOF
set +e
"$WEAVEC" analyze "$TMP/bad.weave" \
  --semantic-index-json "$TMP/failed.json" \
  >"$TMP/failed.stdout" 2>"$TMP/failed.stderr"
status=$?
set -e
[[ "$status" -ne 0 ]] || {
  printf 'semantic-type-facts: malformed enum was accepted\n' >&2
  exit 1
}
python3 - "$TMP/failed.json" <<'PY'
import json
import pathlib
import sys

doc = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
assert doc["analysis"]["status"] == "failed"
assert doc["analysis"]["complete"] is False
assert doc["symbols"] == []
assert doc["specializations"] == []
assert doc["matches"] == []
assert doc["diagnostics"]["items"]
print("semantic-type-facts: failed document passed")
PY

printf 'semantic-type-facts: passed\n'
