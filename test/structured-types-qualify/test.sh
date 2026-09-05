#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# End-to-end qualification for generics, variants, match, Option, Result,
# and try (#151). Focused feature suites keep their own coverage; this
# corpus checks the public interfaces together.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP_RAW="$(mktemp -d "${TMPDIR:-/tmp}/weavec-qualify-types-XXXXXX")"
TMP="$(cd "$TMP_RAW" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'structured-types-qualify: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}

HAS_LLC=0
if command -v llc >/dev/null 2>&1; then
  HAS_LLC=1
fi

normalize_wir() {
  sed -E '/^[[:space:]]*; weavec-source-(file|span)-v1 /d' "$1"
}

EXAMPLE_SOURCES=(
  "$ROOT/stdlib/process.weave"
  "$ROOT/stdlib/parse.weave"
  "$ROOT/stdlib/option.weave"
  "$ROOT/stdlib/result.weave"
  "$ROOT/stdlib/io.weave"
  "$ROOT/examples/parse-digits/main.weave"
)

expect_rejected() {
  local name="$1"
  local needle="$2"
  shift 2
  set +e
  "$WEAVEC" --frontend "$TMP/$name.wir" "$@" \
    >"$TMP/$name.stdout" 2>"$TMP/$name.stderr"
  local status="$?"
  set -e
  if [[ "$status" -eq 0 ]]; then
    printf 'structured-types-qualify: %s was accepted\n' "$name" >&2
    exit 1
  fi
  if [[ -s "$TMP/$name.wir" ]]; then
    printf 'structured-types-qualify: %s published WIR after failure\n' \
      "$name" >&2
    exit 1
  fi
  if ! grep -Fq "$needle" "$TMP/$name.stderr"; then
    printf 'structured-types-qualify: %s missing diagnostic\n' "$name" >&2
    printf 'expected: %s\n' "$needle" >&2
    cat "$TMP/$name.stderr" >&2
    exit 1
  fi
}

# --- User-facing example: WIR, indexes, shuffled order, relocated copies.

"$WEAVEC" --frontend "$TMP/example-forward.wir" "${EXAMPLE_SOURCES[@]}"
# Independent stdlib files may be reordered; the application still follows
# the types and helpers it uses.
"$WEAVEC" --frontend "$TMP/example-shuffled.wir" \
  "$ROOT/stdlib/io.weave" \
  "$ROOT/stdlib/result.weave" \
  "$ROOT/stdlib/option.weave" \
  "$ROOT/stdlib/parse.weave" \
  "$ROOT/stdlib/process.weave" \
  "$ROOT/examples/parse-digits/main.weave"

for needle in \
  '(fn identity__s__i32' \
  '(fn Option__s__i32_new_Some' \
  '(fn Result__s__i32__i32_new_Ok' \
  '(fn Result__s__i32__i32_new_Err' \
  '(call_ptr malloc (const_i64 16))' \
  '(store_i32 (local_get self) (const_i32 0))' \
  '(store_i32 (local_get self) (const_i32 1))' \
  '(ptr_add (local_get self) (const_i64 8))'; do
  if ! grep -Fq "$needle" "$TMP/example-forward.wir"; then
    printf 'structured-types-qualify: example WIR missing %s\n' "$needle" >&2
    cat "$TMP/example-forward.wir" >&2
    exit 1
  fi
  if ! grep -Fq "$needle" "$TMP/example-shuffled.wir"; then
    printf 'structured-types-qualify: shuffled WIR missing %s\n' "$needle" >&2
    cat "$TMP/example-shuffled.wir" >&2
    exit 1
  fi
done

copy_example() {
  local dest="$1"
  mkdir -p "$dest/stdlib" "$dest/examples/parse-digits"
  cp "$ROOT/stdlib/process.weave" "$dest/stdlib/process.weave"
  cp "$ROOT/stdlib/parse.weave" "$dest/stdlib/parse.weave"
  cp "$ROOT/stdlib/option.weave" "$dest/stdlib/option.weave"
  cp "$ROOT/stdlib/result.weave" "$dest/stdlib/result.weave"
  cp "$ROOT/stdlib/io.weave" "$dest/stdlib/io.weave"
  cp "$ROOT/examples/parse-digits/main.weave" \
    "$dest/examples/parse-digits/main.weave"
}

FIRST="$TMP/first"
SECOND="$TMP/relocated/second"
copy_example "$FIRST"
copy_example "$SECOND"

first_sources=(
  "$FIRST/stdlib/process.weave"
  "$FIRST/stdlib/parse.weave"
  "$FIRST/stdlib/option.weave"
  "$FIRST/stdlib/result.weave"
  "$FIRST/stdlib/io.weave"
  "$FIRST/examples/parse-digits/main.weave"
)
second_sources=(
  "$SECOND/stdlib/process.weave"
  "$SECOND/stdlib/parse.weave"
  "$SECOND/stdlib/option.weave"
  "$SECOND/stdlib/result.weave"
  "$SECOND/stdlib/io.weave"
  "$SECOND/examples/parse-digits/main.weave"
)

"$WEAVEC" --frontend "$TMP/relocated-first.wir" "${first_sources[@]}"
"$WEAVEC" --frontend "$TMP/relocated-second.wir" "${second_sources[@]}"
diff -u \
  <(normalize_wir "$TMP/relocated-first.wir") \
  <(normalize_wir "$TMP/relocated-second.wir")

"$WEAVEC" analyze "${first_sources[@]}" \
  --semantic-index-json "$TMP/first.index.json"
"$WEAVEC" analyze "${second_sources[@]}" \
  --semantic-index-json "$TMP/second.index.json"
"$WEAVEC" analyze \
  "$ROOT/stdlib/io.weave" \
  "$ROOT/stdlib/result.weave" \
  "$ROOT/stdlib/option.weave" \
  "$ROOT/stdlib/parse.weave" \
  "$ROOT/stdlib/process.weave" \
  "$ROOT/examples/parse-digits/main.weave" \
  --semantic-index-json "$TMP/shuffled.index.json"

python3 - "$TMP/first.index.json" "$TMP/second.index.json" \
  "$TMP/shuffled.index.json" \
  "$ROOT/docs/schemas/weavec-semantic-index-v1.schema.json" <<'PY'
import json
import pathlib
import sys

first = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
second = json.loads(pathlib.Path(sys.argv[2]).read_text(encoding="utf-8"))
shuffled = json.loads(pathlib.Path(sys.argv[3]).read_text(encoding="utf-8"))
schema = json.loads(pathlib.Path(sys.argv[4]).read_text(encoding="utf-8"))


def facts(document):
    assert document["format"] == "weavec-semantic-index-v1"
    kinds = {item["kind"] for item in document["symbols"]}
    assert "enum" in kinds
    assert "variant" in kinds
    assert "fn" in kinds
    roles = {item["role"] for item in document["references"]}
    assert "construct" in roles
    assert "pattern" in roles
    fn_specs = sorted(
        (item["generic_name"], item["specialized_name"])
        for item in document["specializations"]
        if item["kind"] == "fn"
    )
    enum_specs = sorted(
        (item["generic_name"], item["specialized_name"])
        for item in document["specializations"]
        if item["kind"] == "enum"
    )
    assert ("identity", "identity__s__i32") in fn_specs
    assert ("Option", "Option__s__i32") in enum_specs
    assert ("Result", "Result__s__i32__i32") in enum_specs
    assert document["matches"]
    return {
        "fn_specs": fn_specs,
        "enum_specs": enum_specs,
        "match_count": len(document["matches"]),
        "kinds": sorted(kinds),
        "roles": sorted(roles),
    }


left = facts(first)
right = facts(second)
reordered = facts(shuffled)
assert left == right, (left, right)
assert left == reordered, (left, reordered)
assert "enum" in schema["$defs"]["symbol"]["properties"]["kind"]["enum"]
assert "construct" in schema["$defs"]["reference"]["properties"]["role"]["enum"]
print("structured-types-qualify: example indexes match")
PY

# Surface-only program files share a namespace, so analysis can be complete
# without the low-level stdlib helpers.
cat > "$TMP/surface-option.weave" <<'EOF'
(program
  (name "std.option")
  (version "0.1")
  (enum Option
    (type-params T)
    (variant None)
    (variant Some T)))
EOF
cat > "$TMP/surface-result.weave" <<'EOF'
(program
  (name "std.result")
  (version "0.1")
  (enum Result
    (type-params T E)
    (variant Ok T)
    (variant Err E)))
EOF
cat > "$TMP/surface-app.weave" <<'EOF'
(program
  (name "surface-app")
  (version "0.1")
  (fn identity
    (type-params T)
    (params (value T))
    (returns T)
    (do
      (return value)))
  (fn parse-digit
    (params (n i32))
    (returns (type-app Result i32 i32))
    (do
      (if
        (condition (op less-than n 0))
        (then (do (return (variant Result (type-args i32 i32) Err 1))))
        (else (do)))
      (if
        (condition (op greater-than n 9))
        (then (do (return (variant Result (type-args i32 i32) Err 1))))
        (else (do)))
      (return (variant Result (type-args i32 i32) Ok
        (call identity (type-args i32) n)))))
  (fn double
    (params (n i32))
    (returns (type-app Result i32 i32))
    (do
      (let digit i32 (try (call parse-digit n)))
      (return (variant Result (type-args i32 i32) Ok (op add digit digit)))))
  (entry main
    (params)
    (returns i32)
    (do
      (let none (type-app Option i32) (variant Option (type-args i32) None))
      (let some (type-app Option i32) (variant Option (type-args i32) Some 4))
      (let present i32 (match Option some
        (case None 0)
        (case Some x x)))
      (let result (type-app Result i32 i32) (call double 3))
      (return (match Result result
        (case Ok x (op add x present))
        (case Err e e))))))
EOF

"$WEAVEC" --frontend "$TMP/surface-forward.wir" \
  "$TMP/surface-option.weave" \
  "$TMP/surface-result.weave" \
  "$TMP/surface-app.weave"
"$WEAVEC" --frontend "$TMP/surface-shuffled.wir" \
  "$TMP/surface-result.weave" \
  "$TMP/surface-option.weave" \
  "$TMP/surface-app.weave"
for needle in \
  '(fn identity__s__i32' \
  '(fn Option__s__i32_new_Some' \
  '(fn Result__s__i32__i32_new_Ok' \
  '(call_ptr malloc (const_i64 16))'; do
  grep -Fq "$needle" "$TMP/surface-forward.wir"
  grep -Fq "$needle" "$TMP/surface-shuffled.wir"
done

mkdir -p "$TMP/relocated/surface"
cp "$TMP/surface-option.weave" "$TMP/relocated/surface/option.weave"
cp "$TMP/surface-result.weave" "$TMP/relocated/surface/result.weave"
cp "$TMP/surface-app.weave" "$TMP/relocated/surface/app.weave"

"$WEAVEC" analyze \
  "$TMP/surface-option.weave" \
  "$TMP/surface-result.weave" \
  "$TMP/surface-app.weave" \
  --semantic-index-json "$TMP/surface-first.index.json"
"$WEAVEC" analyze \
  "$TMP/relocated/surface/result.weave" \
  "$TMP/relocated/surface/option.weave" \
  "$TMP/relocated/surface/app.weave" \
  --semantic-index-json "$TMP/surface-second.index.json"

python3 - "$TMP/surface-first.index.json" "$TMP/surface-second.index.json" <<'PY'
import json
import pathlib
import sys

first = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
second = json.loads(pathlib.Path(sys.argv[2]).read_text(encoding="utf-8"))


def facts(document):
    assert document["analysis"]["status"] == "complete"
    assert document["analysis"]["complete"] is True
    constructs = [
        item for item in document["references"] if item["role"] == "construct"
    ]
    patterns = [
        item for item in document["references"] if item["role"] == "pattern"
    ]
    assert constructs
    assert patterns
    assert all(item["status"] == "resolved" for item in constructs)
    assert all(item["status"] == "resolved" for item in patterns)
    specs = sorted(
        item["specialized_name"] for item in document["specializations"]
    )
    assert "identity__s__i32" in specs
    assert "Option__s__i32" in specs
    assert "Result__s__i32__i32" in specs
    assert document["matches"]
    assert all(item["exhaustive"] is True for item in document["matches"])
    assert all(item["enum_symbol_id"] is not None for item in document["matches"])
    return {
        "specs": specs,
        "match_count": len(document["matches"]),
        "construct_count": len(constructs),
        "pattern_count": len(patterns),
    }


assert facts(first) == facts(second)
print("structured-types-qualify: surface indexes match")
PY

# --- Same-spelled private Box types in explicit modules.

mkdir -p "$TMP/boxes/src"
cat > "$TMP/boxes/weave.project" <<'EOF'
(weave-project
  (format 1)
  (name boxes)
  (kind executable)
  (source-roots "src")
  (test-roots)
  (entry application)
  (output "boxes"))
EOF
cat > "$TMP/boxes/src/left.weave" <<'EOF'
(module left
  (export left-tag)
  (struct Box
    (field value i32))
  (fn left-tag
    (params)
    (returns i32)
    (do
      (let box Box (new Box (value 3)))
      (return (field-get box value)))))
EOF
cat > "$TMP/boxes/src/right.weave" <<'EOF'
(module right
  (export right-tag)
  (struct Box
    (field value i32))
  (fn right-tag
    (params)
    (returns i32)
    (do
      (let box Box (new Box (value 4)))
      (return (field-get box value)))))
EOF
cat > "$TMP/boxes/src/application.weave" <<'EOF'
(module application
  (import left (left-tag))
  (import right (right-tag))
  (enum Color
    (variant Red)
    (variant Blue i32))
  (fn identity
    (type-params T)
    (params (value T))
    (returns T)
    (do
      (return value)))
  (entry main
    (params)
    (returns i32)
    (do
      (let blue Color (variant Color Blue 7))
      (let extra i32 (match Color blue
        (case Red 0)
        (case Blue x x)))
      (let wide i64 (call identity (type-args i64) (cast i64 0)))
      (return (op add
        (op add
          (call identity (type-args i32) (call left-tag))
          (call identity (type-args i32) (call right-tag)))
        extra)))))
EOF

"$WEAVEC" --frontend "$TMP/boxes-forward.wir" \
  "$TMP/boxes/src/application.weave" \
  "$TMP/boxes/src/left.weave" \
  "$TMP/boxes/src/right.weave"
"$WEAVEC" --frontend "$TMP/boxes-reverse.wir" \
  "$TMP/boxes/src/right.weave" \
  "$TMP/boxes/src/left.weave" \
  "$TMP/boxes/src/application.weave"

left_box='__weave_m_6c656674__t_426f78'
right_box='__weave_m_7269676874__t_426f78'
for wir in "$TMP/boxes-forward.wir" "$TMP/boxes-reverse.wir"; do
  for needle in \
    '(fn identity__s__i32' \
    '(fn identity__s__i64' \
    '(fn Color_new_Blue' \
    '(call_ptr malloc (const_i64 16))' \
    "(fn ${left_box}_new " \
    "(fn ${right_box}_new "; do
    if ! grep -Fq "$needle" "$wir"; then
      printf 'structured-types-qualify: %s missing %s\n' \
        "$(basename "$wir")" "$needle" >&2
      cat "$wir" >&2
      exit 1
    fi
  done
  if grep -Eq '^\s+\(fn identity ' "$wir"; then
    printf 'structured-types-qualify: generic identity template was emitted\n' >&2
    exit 1
  fi
done

mkdir -p "$TMP/relocated/boxes"
cp -R "$TMP/boxes/." "$TMP/relocated/boxes/"
"$WEAVEC" analyze --project "$TMP/boxes" \
  --semantic-index-json "$TMP/boxes.index.json"
"$WEAVEC" analyze --project "$TMP/relocated/boxes" \
  --semantic-index-json "$TMP/boxes-relocated.index.json"

python3 - "$TMP/boxes.index.json" "$TMP/boxes-relocated.index.json" <<'PY'
import json
import pathlib
import sys

first = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
second = json.loads(pathlib.Path(sys.argv[2]).read_text(encoding="utf-8"))


def facts(document):
    assert document["analysis"]["status"] == "complete"
    modules = {item["name"] for item in document["modules"]}
    assert modules == {"application", "left", "right"}
    boxes = [
        item for item in document["symbols"]
        if item["kind"] == "struct" and item["name"] == "Box"
    ]
    assert len(boxes) == 2
    assert {item["visibility"] for item in boxes} == {"private"}
    colors = [
        item for item in document["symbols"]
        if item["kind"] == "enum" and item["name"] == "Color"
    ]
    assert len(colors) == 1
    specs = sorted(
        item["specialized_name"] for item in document["specializations"]
    )
    assert "identity__s__i32" in specs
    assert "identity__s__i64" in specs
    assert document["matches"]
    assert document["matches"][0]["exhaustive"] is True
    return {
        "modules": sorted(modules),
        "box_count": len(boxes),
        "specs": specs,
        "match_count": len(document["matches"]),
    }


assert facts(first) == facts(second)
print("structured-types-qualify: module indexes match")
PY

# --- Failure classes: exact human diagnostics, no published WIR.

cat > "$TMP/empty-params.weave" <<'EOF'
(program
  (name "empty-params")
  (version "0.1")
  (fn identity
    (type-params)
    (params (value i32))
    (returns i32)
    (do (return value)))
  (entry main (params) (returns i32) (do (return 0))))
EOF
expect_rejected empty-params 'must name at least one parameter' \
  "$TMP/empty-params.weave"

cat > "$TMP/arity.weave" <<'EOF'
(program
  (name "arity")
  (version "0.1")
  (fn identity
    (type-params T)
    (params (value T))
    (returns T)
    (do (return value)))
  (entry main
    (params)
    (returns i32)
    (do (return (call identity (type-args i32 i32) 1)))))
EOF
expect_rejected arity 'expects 1 type argument(s), got 2' \
  "$TMP/arity.weave"

cat > "$TMP/cycle.weave" <<'EOF'
(program
  (name "cycle")
  (version "0.1")
  (struct Box
    (type-params T)
    (field value T))
  (fn nest
    (type-params T)
    (params (value i32))
    (returns i32)
    (do
      (return (call nest (type-args (type-app Box T)) value))))
  (entry main
    (params)
    (returns i32)
    (do (return (call nest (type-args i32) 1)))))
EOF
expect_rejected cycle 'too many generic specializations' \
  "$TMP/cycle.weave"

cat > "$TMP/dup-variant.weave" <<'EOF'
(program
  (name "dup-variant")
  (version "0.1")
  (enum Color
    (variant Red)
    (variant Red))
  (entry main (params) (returns i32) (do (return 0))))
EOF
expect_rejected dup-variant 'duplicate variant' \
  "$TMP/dup-variant.weave"

cat > "$TMP/missing-arm.weave" <<'EOF'
(program
  (name "missing-arm")
  (version "0.1")
  (enum Color
    (variant Red)
    (variant Blue i32))
  (entry main
    (params)
    (returns i32)
    (do
      (let red Color (variant Color Red))
      (return (match Color red
        (case Red 0))))))
EOF
expect_rejected missing-arm 'non-exhaustive match' \
  "$TMP/missing-arm.weave"

cat > "$TMP/unreachable.weave" <<'EOF'
(program
  (name "unreachable")
  (version "0.1")
  (enum Color
    (variant Red)
    (variant Blue i32))
  (entry main
    (params)
    (returns i32)
    (do
      (let red Color (variant Color Red))
      (return (match Color red
        (case Red 0)
        (case Blue x x)
        (case _ 2))))))
EOF
expect_rejected unreachable 'unreachable wildcard' \
  "$TMP/unreachable.weave"

cat > "$TMP/try-not-result.weave" <<'EOF'
(program
  (name "try-not-result")
  (version "0.1")
  (enum Result
    (type-params T E)
    (variant Ok T)
    (variant Err E))
  (entry main
    (params)
    (returns i32)
    (do
      (let v i32 (try (variant Result (type-args i32 i32) Ok 1)))
      (return v))))
EOF
expect_rejected try-not-result 'try requires a Result-returning function' \
  "$TMP/try-not-result.weave"

cat > "$TMP/try-mismatch.weave" <<'EOF'
(program
  (name "try-mismatch")
  (version "0.1")
  (enum Result
    (type-params T E)
    (variant Ok T)
    (variant Err E))
  (fn wrap
    (params (n i32))
    (returns (type-app Result i32 i32))
    (do
      (let v i32 (try (variant Result (type-args i32 i64) Err (cast i64 1))))
      (return (variant Result (type-args i32 i32) Ok v)))))
EOF
expect_rejected try-mismatch \
  'try error type does not match the function Result' \
  "$TMP/try-mismatch.weave"

set +e
"$WEAVEC" analyze "$TMP/missing-arm.weave" \
  --semantic-index-json "$TMP/missing-arm.index.json" \
  >"$TMP/missing-arm.analyze.stdout" 2>"$TMP/missing-arm.analyze.stderr"
missing_status="$?"
set -e
[[ "$missing_status" -ne 0 ]] || {
  printf 'structured-types-qualify: missing arm analysis succeeded\n' >&2
  exit 1
}
python3 - "$TMP/missing-arm.index.json" <<'PY'
import json
import pathlib
import sys

document = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
assert document["format"] == "weavec-semantic-index-v1"
assert document["analysis"]["status"] == "failed"
assert document["analysis"]["complete"] is False
assert document["diagnostics"]["items"]
print("structured-types-qualify: failed analysis document passed")
PY

if [[ "$HAS_LLC" -eq 0 ]]; then
  printf 'structured-types-qualify: frontend passed (llc not present; native skipped)\n'
  exit 0
fi

# --- Native behavior, traces, and cache invalidation.

"$WEAVEC" build "${EXAMPLE_SOURCES[@]}" \
  -o "$TMP/parse-digits" \
  --emit-wir "$TMP/example-build.wir" \
  --diagnostics-json "$TMP/example.diagnostics.json" \
  --trace-json "$TMP/example.trace.json" \
  --manifest-json "$TMP/example.manifest.json"

set +e
LC_ALL=C "$TMP/parse-digits" 1 2 3 \
  >"$TMP/parse-digits.stdout" 2>"$TMP/parse-digits.stderr"
example_status="$?"
set -e
[[ "$example_status" -eq 0 && ! -s "$TMP/parse-digits.stderr" ]] || {
  printf 'structured-types-qualify: parse-digits native run failed\n' >&2
  cat "$TMP/parse-digits.stderr" >&2 || true
  exit 1
}
printf 'digits = 1 2 3\nsum = 6\n' > "$TMP/parse-digits.expected"
cmp "$TMP/parse-digits.expected" "$TMP/parse-digits.stdout"

python3 - \
  "$TMP/example.diagnostics.json" \
  "$TMP/example.trace.json" \
  "$TMP/example.manifest.json" \
  "$ROOT/examples/parse-digits/main.weave" <<'PY'
import json
import pathlib
import sys

diagnostics, trace, manifest, main = map(pathlib.Path, sys.argv[1:])
diag = json.loads(diagnostics.read_text(encoding="utf-8"))
assert diag["format"] == "weavec-diagnostics-v1"
assert diag["status"] == "succeeded"
assert diag["diagnostics"] == []

trace_doc = json.loads(trace.read_text(encoding="utf-8"))
assert trace_doc["format"] == "weavec-compilation-trace-v1"
assert trace_doc["status"] == "succeeded"
assert str(main) in trace_doc["sources"]

manifest_doc = json.loads(manifest.read_text(encoding="utf-8"))
assert manifest_doc["format"] == "weavec-build-manifest-v1"
print("structured-types-qualify: example protocols passed")
PY

# An evidence flag sends the build down the full protocol path, which does not
# use the module cache (#435). Prove that combination reports itself rather
# than silently dropping --cache-report, then run the caching sequence below
# without one so the module decisions are meaningful.
"$WEAVEC" build --project "$TMP/boxes" \
  --emit-wir "$TMP/boxes-build.wir" \
  --cache-dir "$TMP/cache-bypassed" \
  --cache-report "$TMP/boxes-cache-bypassed.json"
[[ -f "$TMP/boxes-cache-bypassed.json" ]] || {
  printf 'structured-types-qualify: --cache-report wrote no file\n' >&2
  exit 1
}
python3 - "$TMP/boxes-cache-bypassed.json" <<'PY'
import json
import pathlib
import sys

report = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
assert report["format"] == "weavec-project-module-cache-v1", report["format"]
assert report["status"] == "bypassed", report["status"]
assert report["bypassed_by"] == "--emit-wir", report["bypassed_by"]
assert report["cache_dir"] == "", report["cache_dir"]
assert report["modules"] == [], report["modules"]
assert report["exit_code"] == 0, report["exit_code"]
print("structured-types-qualify: bypassed cache report passed")
PY
rm -f "$TMP/boxes/boxes"

"$WEAVEC" build --project "$TMP/boxes" \
  --cache-dir "$TMP/cache" \
  --cache-report "$TMP/boxes-cache-first.json"
set +e
"$TMP/boxes/boxes"
boxes_status="$?"
set -e
[[ "$boxes_status" -eq 14 ]] || {
  printf 'structured-types-qualify: boxes exited %s, expected 14\n' \
    "$boxes_status" >&2
  exit 1
}

cat > "$TMP/boxes/src/left.weave" <<'EOF'
(module left
  (export left-tag)
  (struct Box
    (field value i32))
  (fn left-tag
    (params)
    (returns i32)
    (do
      (let box Box (new Box (value 5)))
      (return (field-get box value)))))
EOF
rm -f "$TMP/boxes/boxes"
"$WEAVEC" build --project "$TMP/boxes" \
  --cache-dir "$TMP/cache" \
  --cache-report "$TMP/boxes-cache-second.json"
set +e
"$TMP/boxes/boxes"
boxes_status="$?"
set -e
[[ "$boxes_status" -eq 16 ]] || {
  printf 'structured-types-qualify: rebuilt boxes exited %s, expected 16\n' \
    "$boxes_status" >&2
  exit 1
}

python3 - "$TMP/boxes-cache-first.json" "$TMP/boxes-cache-second.json" <<'PY'
import json
import pathlib
import sys

first = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
second = json.loads(pathlib.Path(sys.argv[2]).read_text(encoding="utf-8"))
assert first["format"] == "weavec-project-module-cache-v1"
assert second["format"] == "weavec-project-module-cache-v1"
first_decisions = {item["name"]: item["decision"] for item in first["modules"]}
second_decisions = {item["name"]: item["decision"] for item in second["modules"]}
assert first_decisions["left"] == "rebuilt"
assert first_decisions["right"] == "rebuilt"
assert first_decisions["application"] == "rebuilt"
assert second_decisions["left"] == "rebuilt"
assert second_decisions["right"] == "reused"
assert second_decisions["application"] == "reused"
print("structured-types-qualify: cache invalidation passed")
PY

printf 'structured-types-qualify: passed\n'
