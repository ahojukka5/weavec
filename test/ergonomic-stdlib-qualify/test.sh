#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Checkout qualification for the ergonomic stdlib (#248). The
# user-facing example is file-statistics. Focused suites keep their
# own coverage; this checks shuffled order, relocated copies, and a
# native run together.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-ergonomic-qualify-XXXXXX")"
trap 'chmod -R u+rwX "$TMP" 2>/dev/null || true; rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'ergonomic-stdlib-qualify: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}

normalize_wir() {
  sed -E '/^[[:space:]]*; weavec-source-(file|span)-v1 /d' "$1"
}

APP="$ROOT/examples/file-statistics/main.weave"
if grep -Eq '\bptr\b|\bextern\b|ptr_add|load_|store_|weave_rt_|fopen|fwrite' \
    "$APP"; then
  printf 'ergonomic-stdlib-qualify: application source leaked low-level forms\n' >&2
  exit 1
fi

SOURCES=(
  "$ROOT/stdlib/memory.weave"
  "$ROOT/stdlib/process.weave"
  "$ROOT/stdlib/parse.weave"
  "$ROOT/stdlib/math.weave"
  "$ROOT/stdlib/io.weave"
  "$ROOT/stdlib/statistics.weave"
  "$ROOT/stdlib/result.weave"
  "$ROOT/stdlib/file.weave"
  "$APP"
)

SHUFFLED=(
  "$ROOT/stdlib/io.weave"
  "$ROOT/stdlib/math.weave"
  "$ROOT/stdlib/memory.weave"
  "$ROOT/stdlib/parse.weave"
  "$ROOT/stdlib/process.weave"
  "$ROOT/stdlib/result.weave"
  "$ROOT/stdlib/statistics.weave"
  "$ROOT/stdlib/file.weave"
  "$APP"
)

"$WEAVEC" --frontend "$TMP/forward.wir" "${SOURCES[@]}"
"$WEAVEC" --frontend "$TMP/shuffled.wir" "${SHUFFLED[@]}"

for needle in \
  '(fn file_open_text' \
  '(fn FileError_new_Failed' \
  'Result__s__bool__enum__FileError_new_Err' \
  '(fn samples_new'; do
  if ! grep -Fq "$needle" "$TMP/forward.wir"; then
    printf 'ergonomic-stdlib-qualify: forward WIR missing %s\n' "$needle" >&2
    exit 1
  fi
  if ! grep -Fq "$needle" "$TMP/shuffled.wir"; then
    printf 'ergonomic-stdlib-qualify: shuffled WIR missing %s\n' "$needle" >&2
    exit 1
  fi
done

copy_tree() {
  local dest="$1"
  mkdir -p "$dest/stdlib" "$dest/examples/file-statistics"
  cp "$ROOT/stdlib/memory.weave" "$dest/stdlib/memory.weave"
  cp "$ROOT/stdlib/process.weave" "$dest/stdlib/process.weave"
  cp "$ROOT/stdlib/parse.weave" "$dest/stdlib/parse.weave"
  cp "$ROOT/stdlib/math.weave" "$dest/stdlib/math.weave"
  cp "$ROOT/stdlib/io.weave" "$dest/stdlib/io.weave"
  cp "$ROOT/stdlib/statistics.weave" "$dest/stdlib/statistics.weave"
  cp "$ROOT/stdlib/result.weave" "$dest/stdlib/result.weave"
  cp "$ROOT/stdlib/file.weave" "$dest/stdlib/file.weave"
  cp "$APP" "$dest/examples/file-statistics/main.weave"
}

copy_tree "$TMP/first"
copy_tree "$TMP/second"

first_sources=(
  "$TMP/first/stdlib/memory.weave"
  "$TMP/first/stdlib/process.weave"
  "$TMP/first/stdlib/parse.weave"
  "$TMP/first/stdlib/math.weave"
  "$TMP/first/stdlib/io.weave"
  "$TMP/first/stdlib/statistics.weave"
  "$TMP/first/stdlib/result.weave"
  "$TMP/first/stdlib/file.weave"
  "$TMP/first/examples/file-statistics/main.weave"
)
second_sources=(
  "$TMP/second/stdlib/memory.weave"
  "$TMP/second/stdlib/process.weave"
  "$TMP/second/stdlib/parse.weave"
  "$TMP/second/stdlib/math.weave"
  "$TMP/second/stdlib/io.weave"
  "$TMP/second/stdlib/statistics.weave"
  "$TMP/second/stdlib/result.weave"
  "$TMP/second/stdlib/file.weave"
  "$TMP/second/examples/file-statistics/main.weave"
)

"$WEAVEC" --frontend "$TMP/relocated-first.wir" "${first_sources[@]}"
"$WEAVEC" --frontend "$TMP/relocated-second.wir" "${second_sources[@]}"
diff -u \
  <(normalize_wir "$TMP/relocated-first.wir") \
  <(normalize_wir "$TMP/relocated-second.wir")

"$WEAVEC" analyze "${SOURCES[@]}" --semantic-index-json "$TMP/index.json"
python3 - "$TMP/index.json" <<'PY'
import json
import pathlib
import sys

doc = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
names = {item["name"] for item in doc["symbols"]}
for name in (
    "file_open_text",
    "file_write_text",
    "FileError",
    "Failed",
    "Result",
    "samples_new",
    "program_main",
):
    assert name in names, name
print("ergonomic-stdlib-qualify: semantic index passed")
PY

if command -v llc >/dev/null 2>&1; then
  "$WEAVEC" build "${SOURCES[@]}" -o "$TMP/file-statistics"
  printf '1\n2\n3\n4\n' >"$TMP/values.txt"
  set +e
  LC_ALL=C "$TMP/file-statistics" "$TMP/values.txt" \
    >"$TMP/out" 2>"$TMP/err"
  status="$?"
  set -e
  if [[ "$status" -ne 0 || -s "$TMP/err" ]]; then
    printf 'ergonomic-stdlib-qualify: native run failed (status=%s)\n' \
      "$status" >&2
    cat "$TMP/err" >&2
    exit 1
  fi
  cat >"$TMP/expected" <<'EOF'
count = 4
mean = 2.5
variance = 1.25
stddev = 1.118034
EOF
  cmp "$TMP/expected" "$TMP/out"

  set +e
  LC_ALL=C "$TMP/file-statistics" >"$TMP/usage.out" 2>"$TMP/usage.err"
  usage_status="$?"
  set -e
  if [[ "$usage_status" -ne 2 ]]; then
    printf 'ergonomic-stdlib-qualify: usage exit %s, expected 2\n' \
      "$usage_status" >&2
    exit 1
  fi
  grep -Fq 'usage: file-statistics <path>' "$TMP/usage.err"
  [[ ! -s "$TMP/usage.out" ]]
fi

printf 'ergonomic-stdlib-qualify: passed\n'
