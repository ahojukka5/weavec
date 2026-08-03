#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-si-order-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'semantic-index-order: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}

cat > "$TMP/arithmetic.weave" <<'WEAVE'
(module arithmetic
  (export add-two)
  (fn private-helper
    (params (value i32))
    (returns i32)
    (do (return (op add value 1))))
  (fn add-two
    (params (left i32) (right i32))
    (returns i32)
    (do (return (op add left right)))))
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
  --semantic-index-json "$TMP/forward.json"
"$WEAVEC" analyze \
  "$TMP/application.weave" "$TMP/arithmetic.weave" \
  --semantic-index-json "$TMP/reverse.json"

python3 - "$TMP/forward.json" "$TMP/reverse.json" <<'PY'
import json
import pathlib
import sys

forward = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
reverse = json.loads(pathlib.Path(sys.argv[2]).read_text(encoding="utf-8"))

for document in (forward, reverse):
    assert document["analysis"]["status"] == "complete"
    assert document["analysis"]["complete"] is True


def semantic_graph(document):
    modules = {item["id"]: item for item in document["modules"]}
    symbols = {item["id"]: item for item in document["symbols"]}
    sources = {item["id"]: item for item in document["sources"]}
    references = {item["id"]: item for item in document["references"]}

    def module_name(module_id):
        return None if module_id is None else modules[module_id]["name"]

    def symbol_key(symbol_id):
        if symbol_id is None:
            return None
        symbol = symbols[symbol_id]
        return (
            module_name(symbol["module_id"]),
            symbol["kind"],
            symbol["name"],
            symbol["visibility"],
            symbol["signature"]["canonical"],
        )

    def span_key(span):
        source = sources[span["source_id"]]
        data = pathlib.Path(source["path"]).read_bytes()
        text = data[span["start"]:span["end"]].decode("utf-8")
        return (
            pathlib.Path(source["path"]).name,
            span["start"],
            span["end"],
            text,
        )

    module_facts = {}
    for module in document["modules"]:
        module_facts[module["name"]] = {
            "definition": span_key(module["definition"]),
            "interface_hash": module["interface"]["sha256"],
            "exports": sorted(
                symbol_key(symbol_id)
                for symbol_id in module["interface"]["exports"]
            ),
        }

    import_facts = sorted(
        (
            module_name(item["module_id"]),
            item["source_module"],
            module_name(item["imported_module_id"]),
            item["imported_name"],
            item["local_name"],
            symbol_key(item["symbol_id"]),
            span_key(item["span"]),
            item["status"],
        )
        for item in document["imports"]
    )
    export_facts = sorted(
        (
            module_name(item["module_id"]),
            item["name"],
            symbol_key(item["symbol_id"]),
            span_key(item["span"]),
            item["status"],
        )
        for item in document["exports"]
    )
    reference_facts = sorted(
        (
            item["role"],
            symbol_key(item["symbol_id"]),
            span_key(item["span"]),
            item["status"],
        )
        for item in document["references"]
    )
    edge_facts = sorted(
        (
            symbol_key(item["caller_symbol_id"]),
            symbol_key(item["callee_symbol_id"]),
            reference_facts_for_id(
                references[item["call_reference_id"]],
                symbol_key,
                span_key,
            ),
            item["status"],
        )
        for item in document["call_edges"]
    )
    return {
        "modules": module_facts,
        "imports": import_facts,
        "exports": export_facts,
        "references": reference_facts,
        "call_edges": edge_facts,
    }


def reference_facts_for_id(item, symbol_key, span_key):
    return (
        item["role"],
        symbol_key(item["symbol_id"]),
        span_key(item["span"]),
        item["status"],
    )


assert semantic_graph(forward) == semantic_graph(reverse)
assert forward["analysis"]["source_set_sha256"] != (
    reverse["analysis"]["source_set_sha256"]
)

forward_modules = {item["name"]: item["id"] for item in forward["modules"]}
reverse_modules = {item["name"]: item["id"] for item in reverse["modules"]}
assert forward_modules["arithmetic"] == "module:0"
assert reverse_modules["arithmetic"] == "module:1"
assert forward_modules["application"] == "module:1"
assert reverse_modules["application"] == "module:0"

print("semantic-index-order: module graph is source-order independent")
PY
