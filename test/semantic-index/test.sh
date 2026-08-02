#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-semantic-index-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'semantic-index: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}

cat > "$TMP/arithmetic.weave" <<'WEAVE'
(module arithmetic
  (export add-two)
  (fn add-two
    (params (left i32) (right i32))
    (returns i32)
    (do (return (op add (param_get left) (param_get right)))))
  (fn private-helper
    (params (value i32))
    (returns i32)
    (do (return (param_get value)))))
WEAVE

cat > "$TMP/application.weave" <<'WEAVE'
(module application
  (import arithmetic (add-two))
  (entry main
    (params)
    (returns i32)
    (do (return (call add-two 19 23)))))
WEAVE

"$WEAVEC" analyze \
  "$TMP/arithmetic.weave" "$TMP/application.weave" \
  --semantic-index-json "$TMP/first.json"
"$WEAVEC" analyze \
  "$TMP/arithmetic.weave" "$TMP/application.weave" \
  --semantic-index-json "$TMP/second.json"
cmp "$TMP/first.json" "$TMP/second.json"

python3 - "$TMP/first.json" <<'PY'
import json
import pathlib
import sys

doc = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
assert doc["format"] == "weavec-semantic-index-v1"
assert doc["analysis"]["status"] == "incomplete"
assert doc["analysis"]["complete"] is False
assert doc["analysis"]["incomplete_reason"] == (
    "read/write/type references are not emitted yet"
)
assert doc["diagnostics"] == {
    "format": "weavec-diagnostics-v1",
    "complete": True,
    "items": [],
}
assert [source["id"] for source in doc["sources"]] == ["source:0", "source:1"]
assert [module["name"] for module in doc["modules"]] == [
    "arithmetic", "application"
]

symbols = {symbol["name"]: symbol for symbol in doc["symbols"]}
assert symbols["add-two"]["visibility"] == "public"
assert symbols["private-helper"]["visibility"] == "private"
assert symbols["main"]["kind"] == "entry"
assert symbols["add-two"]["signature"]["canonical"] == (
    "(fn (params (left i32) (right i32)) (returns i32))"
)

roles = [reference["role"] for reference in doc["references"]]
assert roles.count("export") == 1
assert roles.count("import") == 1
assert roles.count("call") == 1
assert all(reference["status"] == "resolved" for reference in doc["references"])

assert len(doc["imports"]) == 1
assert doc["imports"][0]["status"] == "resolved"
assert doc["imports"][0]["imported_name"] == "add-two"
assert len(doc["exports"]) == 1
assert doc["exports"][0]["status"] == "resolved"

assert len(doc["call_edges"]) == 1
edge = doc["call_edges"][0]
symbol_by_id = {symbol["id"]: symbol for symbol in doc["symbols"]}
reference_by_id = {item["id"]: item for item in doc["references"]}
assert symbol_by_id[edge["caller_symbol_id"]]["name"] == "main"
assert symbol_by_id[edge["callee_symbol_id"]]["name"] == "add-two"
assert reference_by_id[edge["call_reference_id"]]["role"] == "call"
assert edge["status"] == "resolved"
PY

python3 - "$TMP/first.json" "$TMP/arithmetic.hash" <<'PY'
import json
import pathlib
import sys

doc = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
module = next(item for item in doc["modules"] if item["name"] == "arithmetic")
pathlib.Path(sys.argv[2]).write_text(module["interface"]["sha256"], encoding="utf-8")
PY

# Private implementation changes must preserve the public interface hash.
python3 - "$TMP/arithmetic.weave" <<'PY'
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
path.write_text(text.replace(
    "(do (return (param_get value)))",
    "(do (return (op add (param_get value) 1)))",
), encoding="utf-8")
PY
"$WEAVEC" analyze \
  "$TMP/arithmetic.weave" "$TMP/application.weave" \
  --semantic-index-json "$TMP/private-change.json"
python3 - "$TMP/private-change.json" "$TMP/arithmetic.hash" <<'PY'
import json
import pathlib
import sys

doc = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
module = next(item for item in doc["modules"] if item["name"] == "arithmetic")
expected = pathlib.Path(sys.argv[2]).read_text(encoding="utf-8")
assert module["interface"]["sha256"] == expected
PY

# A public signature change must change the interface hash. Update the call site
# too so the source set remains valid and the hash assertion tests only ABI data.
python3 - "$TMP/arithmetic.weave" "$TMP/application.weave" <<'PY'
import pathlib
import sys
arithmetic = pathlib.Path(sys.argv[1])
application = pathlib.Path(sys.argv[2])
text = arithmetic.read_text(encoding="utf-8")
text = text.replace(
    "(params (left i32) (right i32))",
    "(params (left i32) (right i32) (extra i32))",
    1,
).replace(
    "(op add (param_get left) (param_get right))",
    "(op add (op add (param_get left) (param_get right)) (param_get extra))",
    1,
)
arithmetic.write_text(text, encoding="utf-8")
application.write_text(
    application.read_text(encoding="utf-8").replace(
        "(call add-two 19 23)", "(call add-two 19 23 0)"
    ),
    encoding="utf-8",
)
PY
"$WEAVEC" analyze \
  "$TMP/arithmetic.weave" "$TMP/application.weave" \
  --semantic-index-json "$TMP/public-change.json"
python3 - "$TMP/public-change.json" "$TMP/arithmetic.hash" <<'PY'
import json
import pathlib
import sys

doc = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
module = next(item for item in doc["modules"] if item["name"] == "arithmetic")
previous = pathlib.Path(sys.argv[2]).read_text(encoding="utf-8")
assert module["interface"]["sha256"] != previous
PY

# Invalid semantic input returns non-zero but still publishes an explicit failed
# document. Consumers must never infer completeness from empty graph arrays.
cat > "$TMP/invalid.weave" <<'WEAVE'
(module invalid
  (import arithmetic (private-helper))
  (entry main
    (params)
    (returns i32)
    (do (return (call private-helper 1)))))
WEAVE
if "$WEAVEC" analyze \
    "$TMP/arithmetic.weave" "$TMP/invalid.weave" \
    --semantic-index-json "$TMP/failed.json"; then
  printf 'semantic-index: invalid source set was accepted\n' >&2
  exit 1
fi
python3 - "$TMP/failed.json" <<'PY'
import json
import pathlib
import sys

doc = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
assert doc["analysis"]["status"] == "failed"
assert doc["analysis"]["complete"] is False
assert doc["modules"] == []
assert doc["symbols"] == []
assert doc["references"] == []
assert doc["call_edges"] == []
assert doc["diagnostics"]["complete"] is True
assert doc["diagnostics"]["items"]
assert doc["diagnostics"]["items"][0]["severity"] == "error"
PY

printf 'semantic-index: deterministic graph and failure checks passed\n'
