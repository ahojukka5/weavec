#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Paths, files, process, and environment. Application source names no
# ptr. file_write_text is Result bool FileError. env_get uses Option.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-cli-io-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'cli-io: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}

MEMORY="$ROOT/stdlib/memory.weave"
OPTION="$ROOT/stdlib/option.weave"
RESULT="$ROOT/stdlib/result.weave"
BYTES="$ROOT/stdlib/bytes.weave"
STRING="$ROOT/stdlib/string.weave"
PROCESS="$ROOT/stdlib/process.weave"
FILE="$ROOT/stdlib/file.weave"
PATH_MOD="$ROOT/stdlib/path.weave"
ENV="$ROOT/stdlib/env.weave"
IO="$ROOT/stdlib/io.weave"

expect_frontend() {
  local name="$1"
  shift
  "$WEAVEC" --frontend "$TMP/$name.wir" "$@" "$TMP/$name.weave" \
    2>"$TMP/$name.stderr" || {
    printf 'cli-io: %s rejected\n' "$name" >&2
    cat "$TMP/$name.stderr" >&2
    exit 1
  }
}

# Path join, absolute, and basename. Native runs when llc is present.
cat > "$TMP/paths.weave" <<'EOF'
(program
  (name "paths")
  (version "0.1")
  (entry main
    (params)
    (returns i32)
    (do
      (let joined (call path_join "/tmp" "out.txt"))
      (let abs (call path_is_absolute "/tmp"))
      (let rel (call path_is_absolute "out.txt"))
      (let base (call path_basename "/tmp/out.txt"))
      (if
        (condition (op not abs))
        (then (do (return 10))))
      (if
        (condition rel)
        (then (do (return 11))))
      (return (call string_len joined)))))
EOF
expect_frontend paths \
  "$MEMORY" "$OPTION" "$BYTES" "$STRING" "$PATH_MOD"
grep -Fq '(call_ptr path_join' "$TMP/paths.wir"
grep -Fq '(call_bool path_is_absolute' "$TMP/paths.wir"
grep -Fq '(call_ptr path_basename' "$TMP/paths.wir"
if grep -Eq '\bptr\b|\bextern\b|ptr_add|load_|store_|weave_rt_|malloc|free' \
    "$TMP/paths.weave"; then
  printf 'cli-io: paths source leaked low-level forms\n' >&2
  exit 1
fi

# Missing names are None, not an empty string.
cat > "$TMP/env.weave" <<'EOF'
(program
  (name "env")
  (version "0.1")
  (entry main
    (params)
    (returns i32)
    (do
      (let home (call env_get "PATH"))
      (let miss (call env_get "WEAVEC_CLI_IO_MISSING_VAR_XYZ"))
      (if
        (condition (call option_is_none (type-args String) home))
        (then (do (return 10))))
      (if
        (condition (call option_is_some (type-args String) miss))
        (then (do (return 11))))
      (return 0))))
EOF
expect_frontend env \
  "$MEMORY" "$OPTION" "$BYTES" "$STRING" "$ENV"
grep -Fq '(call_ptr env_get' "$TMP/env.wir"
grep -Fq 'Option__s__String_new_None' "$TMP/env.wir"
if grep -Eq '\bptr\b|\bextern\b|ptr_add|load_|store_|weave_rt_|malloc|free' \
    "$TMP/env.weave"; then
  printf 'cli-io: env source leaked low-level forms\n' >&2
  exit 1
fi

# Direct Result from file_write_text, with a stable FileError constructor.
cat > "$TMP/wrap.weave" <<'EOF'
(program
  (name "wrap")
  (version "0.1")
  (fn program_main
    (params)
    (returns i32)
    (do
      (let r (call file_write_text (call arg 0) "ok\n"))
      (if
        (condition (call result_is_err (type-args bool FileError) r))
        (then (do (return 2)))
        (else (do)))
      (return 0))))
EOF
expect_frontend wrap \
  "$MEMORY" "$RESULT" "$PROCESS" "$FILE"
grep -Fq '(call_ptr file_write_text' "$TMP/wrap.wir"
grep -Fq 'FileError_new_Failed' "$TMP/wrap.wir"
grep -Fq 'Result__s__bool__enum__FileError_new_Err' "$TMP/wrap.wir"

"$WEAVEC" analyze \
  "$MEMORY" "$OPTION" "$BYTES" "$STRING" "$PATH_MOD" "$ENV" \
  "$TMP/paths.weave" --semantic-index-json "$TMP/paths.index.json"
python3 - "$TMP/paths.index.json" <<'PY'
import json
import pathlib
import sys

doc = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
names = {item["name"] for item in doc["symbols"]}
for name in ("path_join", "path_is_absolute", "path_basename", "env_get"):
    assert name in names, name
print("cli-io: semantic index passed")
PY

# Native process_exit and file_write_text.
if command -v llc >/dev/null 2>&1; then
  cat > "$TMP/exit.weave" <<'EOF'
(program
  (name "exit")
  (version "0.1")
  (fn program_main
    (params)
    (returns i32)
    (do
      (call process_exit 7)
      (return 0))))
EOF
  "$WEAVEC" build "$PROCESS" "$TMP/exit.weave" -o "$TMP/exit"
  set +e
  "$TMP/exit"
  status="$?"
  set -e
  if [[ "$status" -ne 7 ]]; then
    printf 'cli-io: process_exit exited %s, expected 7\n' "$status" >&2
    exit 1
  fi

  out="$TMP/written.txt"
  cat > "$TMP/write.weave" <<'EOF'
(program
  (name "write")
  (version "0.1")
  (fn program_main
    (params)
    (returns i32)
    (do
      (if
        (condition (op not-equal (call args_count) 1))
        (then (do
          (call write_stderr "usage: write <path>\n")
          (call process_exit 2)
          (return 2)))
        (else (do)))
      (if
        (condition (call result_is_err (type-args bool FileError)
          (call file_write_text (call arg 0) "hi\n")))
        (then (do (return 3)))
        (else (do)))
      (let bad (call file_write_text "/no/such/dir/weavec-cli-io.txt" "x"))
      (if
        (condition (call result_is_ok (type-args bool FileError) bad))
        (then (do (return 4)))
        (else (do)))
      (let err FileError (match Result bad
        (case Ok x (variant FileError Failed))
        (case Err e e)))
      (let kind i32 (match FileError err
        (case Failed 0)))
      (if
        (condition (op not-equal kind 0))
        (then (do (return 6)))
        (else (do)))
      (let file (call file_open_text (call arg 0)))
      (if
        (condition (op not (call text_file_is_open file)))
        (then (do
          (call text_file_close file)
          (return 5)))
        (else (do)))
      (call write_stdout (call text_file_line file 0))
      (call write_stdout "\n")
      (call text_file_close file)
      (return 0))))
EOF
  if grep -Eq '\bptr\b|\bextern\b|call_(i32|i64|ptr|void)|const_|ptr_add|load_|store_|weave_rt_|fopen|fwrite' \
      "$TMP/write.weave"; then
    printf 'cli-io: write source leaked low-level forms\n' >&2
    exit 1
  fi
  "$WEAVEC" build \
    "$MEMORY" "$RESULT" "$PROCESS" "$IO" "$FILE" "$TMP/write.weave" -o "$TMP/write"
  set +e
  "$TMP/write" "$out" >"$TMP/write.stdout" 2>"$TMP/write.stderr"
  status="$?"
  set -e
  if [[ "$status" -ne 0 ]]; then
    printf 'cli-io: write exited %s\n' "$status" >&2
    cat "$TMP/write.stdout" >&2 || true
    cat "$TMP/write.stderr" >&2 || true
    exit 1
  fi
  printf 'hi\n' >"$TMP/write.expected"
  cmp "$TMP/write.expected" "$TMP/write.stdout" || {
    printf 'cli-io: write stdout mismatch\n' >&2
    diff -u "$TMP/write.expected" "$TMP/write.stdout" >&2 || true
    exit 1
  }
  [[ ! -s "$TMP/write.stderr" ]] || {
    printf 'cli-io: write wrote to stderr\n' >&2
    cat "$TMP/write.stderr" >&2
    exit 1
  }
fi

printf 'cli-io: passed\n'
