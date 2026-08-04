#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP_RAW="$(mktemp -d "${TMPDIR:-/tmp}/weavec-module-types-XXXXXX")"
TMP="$(cd "$TMP_RAW" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'module-type-interfaces: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}

normalize_wir() {
  sed -E '/^[[:space:]]*; weavec-source-(file|span)-v1 /d' "$1"
}

run_status() {
  local expected="$1"
  shift
  set +e
  "$@"
  local actual=$?
  set -e
  [[ "$actual" -eq "$expected" ]] || {
    printf 'module-type-interfaces: expected status %s, got %s: %s\n' \
      "$expected" "$actual" "$*" >&2
    exit 1
  }
}

run_case() {
  local name="$1"
  local code="$2"
  local role="$3"
  local expected_span="$4"
  local expected_symbol="$expected_span"
  shift 4

  if [[ "$expected_span" == *'|'* ]]; then
    expected_symbol="${expected_span#*|}"
    expected_span="${expected_span%%|*}"
  fi
  printf 'module-type-interfaces: negative case %s\n' "$name"

  rm -f "$TMP/$name" "$TMP/$name.json"
  set +e
  "$WEAVEC" build "$@" \
    -o "$TMP/$name" \
    --diagnostics-json "$TMP/$name.json" \
    >"$TMP/$name.stdout" 2>"$TMP/$name.stderr"
  local status=$?
  set -e

  [[ "$status" -eq 10 ]] || {
    printf 'module-type-interfaces: %s returned %s instead of 10\n' \
      "$name" "$status" >&2
    cat "$TMP/$name.stderr" >&2
    exit 1
  }
  [[ ! -e "$TMP/$name" ]]

  python3 - \
    "$TMP/$name.json" "$code" "$role" "$expected_span" "$expected_symbol" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
expected_code, expected_role, expected_span, expected_symbol = sys.argv[2:]
document = json.loads(path.read_text(encoding="utf-8"))
assert document["format"] == "weavec-diagnostics-v1", document
assert document["status"] == "failed", document
assert document["phase"] == "frontend", document
assert document["exit_code"] == 10, document
matches = [
    item for item in document["diagnostics"]
    if item["code"] == expected_code
]
assert len(matches) == 1, (expected_code, document["diagnostics"])
diagnostic = matches[0]
assert diagnostic["span_origin"] == "compiler-semantic", diagnostic
assert diagnostic["analysis_complete"] is True, diagnostic
assert diagnostic["operand_role"] == expected_role, diagnostic
assert diagnostic["symbol"] == expected_symbol, diagnostic
source = pathlib.Path(diagnostic["source"]).read_bytes()
span = diagnostic["span"]
actual_span = source[span["start_byte"]:span["end_byte"]].decode()
assert actual_span == expected_span, (actual_span, expected_span, diagnostic)
PY
}

cat > "$TMP/records.weave" <<'WEAVE'
(module records
  (export Record make-record read-record bump-record)
  (extern malloc (params (size i64)) (returns ptr))
  (struct Record
    (field value i32))
  (fn make-record
    (params (value i32))
    (returns Record)
    (do
      (return (new Record (value value)))))
  (fn read-record
    (params (item Record))
    (returns i32)
    (do
      (return (field-get item value))))
  (fn bump-record
    (params (item Record))
    (returns Record)
    (do
      (field-set item value
        (op add (field-get item value) 1))
      (return item))))
WEAVE

cat > "$TMP/main.weave" <<'WEAVE'
(module application
  (import records (Record make-record read-record bump-record))
  (fn identity
    (params (item Record))
    (returns Record)
    (do
      (return item)))
  (entry main
    (params)
    (returns i32)
    (do
      (let first Record (new Record (value 19)))
      (field-set first value 20)
      (let same Record (call identity first))
      (let second Record (call make-record 21))
      (let third Record (call bump-record second))
      (return
        (op add
          (call read-record same)
          (field-get third value))))))
WEAVE

"$WEAVEC" --frontend "$TMP/forward.wir" \
  "$TMP/main.weave" "$TMP/records.weave"
"$WEAVEC" --frontend "$TMP/reverse.wir" \
  "$TMP/records.weave" "$TMP/main.weave"
diff -u \
  <(normalize_wir "$TMP/forward.wir") \
  <(normalize_wir "$TMP/reverse.wir")

record_base='__weave_m_7265636f726473__t_5265636f7264'
grep -Fq "(fn ${record_base}_new " "$TMP/forward.wir"
grep -Fq "(call_ptr ${record_base}_new " "$TMP/forward.wir"
grep -Fq "(call_void ${record_base}_set_value " "$TMP/forward.wir"
grep -Fq "(call_i32 ${record_base}_get_value " "$TMP/forward.wir"
grep -Fq 'identity (params (item ptr)) (returns ptr)' "$TMP/forward.wir"
grep -Fq 'make-record (params (value i32)) (returns ptr)' "$TMP/forward.wir"
grep -Fq 'read-record (params (item ptr)) (returns i32)' "$TMP/forward.wir"

for order in forward reverse; do
  if [[ "$order" == forward ]]; then
    sources=("$TMP/main.weave" "$TMP/records.weave")
  else
    sources=("$TMP/records.weave" "$TMP/main.weave")
  fi
  "$WEAVEC" build "${sources[@]}" -o "$TMP/$order"
  run_status 42 "$TMP/$order"
done

# Project mode consumes the same public nominal interface without an explicit
# source list and keeps the generated WIR independent of checkout location.
write_project() {
  local project="$1"
  local reverse="$2"
  mkdir -p "$project/src"
  cat > "$project/weave.project" <<'PROJECT'
(weave-project
  (format 1)
  (name nominal-types)
  (kind executable)
  (source-roots "src")
  (test-roots)
  (entry application)
  (output "nominal-types"))
PROJECT
  if [[ "$reverse" == 0 ]]; then
    cp "$TMP/records.weave" "$project/src/records.weave"
    sed 's/main\.weave/application.weave/' "$TMP/main.weave" \
      > "$project/src/application.weave"
  else
    sed 's/main\.weave/application.weave/' "$TMP/main.weave" \
      > "$project/src/application.weave"
    cp "$TMP/records.weave" "$project/src/records.weave"
  fi
}

PROJECT_A="$TMP/project-a"
PROJECT_B="$TMP/relocated/project-b"
write_project "$PROJECT_A" 0
write_project "$PROJECT_B" 1
"$WEAVEC" build --project "$PROJECT_A" \
  --emit-wir "$TMP/project-a.wir"
"$WEAVEC" build --project "$PROJECT_B" \
  --emit-wir "$TMP/project-b.wir"
run_status 42 "$PROJECT_A/nominal-types"
run_status 42 "$PROJECT_B/nominal-types"
diff -u \
  <(normalize_wir "$TMP/project-a.wir") \
  <(normalize_wir "$TMP/project-b.wir")

# Struct declarations already participate in the module interface hash. Verify
# that the import and every Record type use resolve to the defining struct symbol.
"$WEAVEC" analyze "$TMP/records.weave" "$TMP/main.weave" \
  --semantic-index-json "$TMP/index-forward.json"
"$WEAVEC" analyze "$TMP/main.weave" "$TMP/records.weave" \
  --semantic-index-json "$TMP/index-reverse.json"
python3 - "$TMP/index-forward.json" "$TMP/index-reverse.json" <<'PY'
import json
import pathlib
import sys

forward = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
reverse = json.loads(pathlib.Path(sys.argv[2]).read_text(encoding="utf-8"))


def facts(document):
    assert document["analysis"]["status"] == "complete"
    modules = {item["id"]: item for item in document["modules"]}
    symbols = {item["id"]: item for item in document["symbols"]}
    sources = {
        item["id"]: pathlib.Path(item["path"]).read_text(encoding="utf-8")
        for item in document["sources"]
    }
    records = next(item for item in document["modules"] if item["name"] == "records")
    record = next(
        item for item in document["symbols"]
        if modules[item["module_id"]]["name"] == "records"
        and item["kind"] == "struct"
        and item["name"] == "Record"
    )
    assert record["visibility"] == "public"
    canonical = record["signature"]["canonical"]
    assert canonical.startswith("(struct"), canonical
    assert canonical.endswith(")"), canonical
    assert canonical.count("(field ") == 1, canonical
    assert "(field value i32)" in canonical, canonical
    imported = next(
        item for item in document["imports"]
        if item["imported_name"] == "Record"
    )
    assert imported["status"] == "resolved"
    assert symbols[imported["symbol_id"]]["kind"] == "struct"
    assert symbols[imported["symbol_id"]]["name"] == "Record"
    assert modules[symbols[imported["symbol_id"]]["module_id"]]["name"] == "records"

    def referenced_text(reference):
        span = reference["span"]
        return sources[span["source_id"]][span["start"]:span["end"]]

    type_references = [
        reference for reference in document["references"]
        if reference["role"] == "type"
        and referenced_text(reference) == "Record"
    ]
    assert len(type_references) >= 10, type_references
    assert all(reference["status"] == "resolved" for reference in type_references)
    assert all(reference["symbol_id"] == record["id"] for reference in type_references)
    return (
        records["interface"]["sha256"],
        canonical,
        imported["status"],
        len(type_references),
    )


assert facts(forward) == facts(reverse)
PY

# Private and missing nominal interfaces use the established module diagnostics.
cat > "$TMP/private-records.weave" <<'WEAVE'
(module private-records
  (struct Hidden
    (field value i32)))
WEAVE
cat > "$TMP/private-use.weave" <<'WEAVE'
(module private-use
  (import private-records (Hidden))
  (fn consume
    (params (item Hidden))
    (returns i32)
    (do (return (field-get item value)))))
WEAVE
run_case private-type \
  frontend.module.import-private-symbol import-symbol Hidden \
  "$TMP/private-use.weave" "$TMP/private-records.weave"

cat > "$TMP/missing-records.weave" <<'WEAVE'
(module missing-records
  (struct Present
    (field value i32)))
WEAVE
cat > "$TMP/missing-use.weave" <<'WEAVE'
(module missing-use
  (import missing-records (Absent))
  (fn consume
    (params (item Absent))
    (returns i32)
    (do (return 0))))
WEAVE
run_case missing-type \
  frontend.module.import-missing-symbol import-symbol Absent \
  "$TMP/missing-use.weave" "$TMP/missing-records.weave"

# An imported type is not locally owned and cannot be re-exported implicitly.
cat > "$TMP/reexport.weave" <<'WEAVE'
(module reexport
  (import records (Record))
  (export Record))
WEAVE
run_case reexport-type \
  frontend.module.export-undeclared export-symbol Record \
  "$TMP/reexport.weave" "$TMP/records.weave"

# Imported type bindings share the local declaration namespace.
cat > "$TMP/import-collision.weave" <<'WEAVE'
(module import-collision
  (import records (Record))
  (struct Record
    (field other i32)))
WEAVE
run_case imported-local-collision \
  frontend.module.import-local-collision import-symbol Record \
  "$TMP/import-collision.weave" "$TMP/records.weave"

cat > "$TMP/type-value-collision.weave" <<'WEAVE'
(module type-value-collision
  (struct Record
    (field value i32))
  (fn Record
    (params)
    (returns i32)
    (do (return 0))))
WEAVE
run_case local-type-value-collision \
  frontend.module.type-value-collision declaration-name Record \
  "$TMP/type-value-collision.weave"

# Equal source spellings from different modules remain distinct nominal types.
cat > "$TMP/alpha-type.weave" <<'WEAVE'
(module alpha-type
  (export Record make-alpha)
  (extern malloc (params (size i64)) (returns ptr))
  (struct Record
    (field value i32))
  (fn make-alpha
    (params)
    (returns Record)
    (do (return (new Record (value 1))))))
WEAVE
cat > "$TMP/beta-type.weave" <<'WEAVE'
(module beta-type
  (export Record accept-beta)
  (struct Record
    (field value i32))
  (fn accept-beta
    (params (item Record))
    (returns i32)
    (do (return (field-get item value)))))
WEAVE
cat > "$TMP/nominal-mismatch.weave" <<'WEAVE'
(module nominal-mismatch
  (import alpha-type (Record make-alpha))
  (import beta-type (accept-beta))
  (entry main
    (params)
    (returns i32)
    (do
      (let value Record (call make-alpha))
      (return (call accept-beta value)))))
WEAVE
run_case same-name-nominal-mismatch \
  frontend.call.argument-type-mismatch argument 'value|accept-beta' \
  "$TMP/nominal-mismatch.weave" \
  "$TMP/alpha-type.weave" "$TMP/beta-type.weave"

printf 'module-type-interfaces: public nominal interfaces passed\n'