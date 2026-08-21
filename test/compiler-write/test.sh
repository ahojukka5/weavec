#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Compiler output writes are buffered, flushed, and checked (#277).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-compiler-write-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'compiler-write: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}

if grep -Fq '(call_ptr malloc (const_i64 1))' "$ROOT/src/core/io.weave"; then
  printf 'compiler-write: write_byte still allocates one byte per call\n' >&2
  exit 1
fi
if grep -Eq 'call_i64 write ' "$ROOT/src/core/io.weave"; then
  printf 'compiler-write: io.weave still calls write() directly\n' >&2
  exit 1
fi
grep -Fq 'WEAVE_IO_CAP' "$ROOT/runtime/portable.c" || {
  printf 'compiler-write: missing host output buffer\n' >&2
  exit 1
}

cat > "$TMP/app.weave" <<'EOF'
(program
  (name "tiny")
  (version "0.1")
  (entry main
    (params)
    (returns i32)
    (do (return 0))))
EOF

"$WEAVEC" --frontend "$TMP/app.wir" "$TMP/app.weave" 2>"$TMP/front.stderr" || {
  printf 'compiler-write: frontend failed\n' >&2
  cat "$TMP/front.stderr" >&2
  exit 1
}

grep -Fq '(core-version 3)' "$TMP/app.wir" || {
  printf 'compiler-write: truncated WIR header\n' >&2
  cat "$TMP/app.wir" >&2
  exit 1
}
if ! tail -n 1 "$TMP/app.wir" | grep -Fxq ')'; then
  printf 'compiler-write: truncated WIR footer\n' >&2
  cat "$TMP/app.wir" >&2
  exit 1
fi

"$WEAVEC" --backend "$TMP/app.wir" "$TMP/app.ll" 2>"$TMP/back.stderr" || {
  printf 'compiler-write: backend failed\n' >&2
  cat "$TMP/back.stderr" >&2
  exit 1
}
grep -Eq '^define ' "$TMP/app.ll" || {
  printf 'compiler-write: truncated LLVM\n' >&2
  cat "$TMP/app.ll" >&2
  exit 1
}

if [[ -e /dev/full ]]; then
  set +e
  "$WEAVEC" --frontend /dev/full "$TMP/app.weave" \
    >"$TMP/full.stdout" 2>"$TMP/full.stderr"
  status=$?
  set -e
  if [[ "$status" -eq 0 ]]; then
    printf 'compiler-write: frontend write to /dev/full succeeded\n' >&2
    exit 1
  fi
  if ! grep -Fq 'write failed' "$TMP/full.stderr"; then
    printf 'compiler-write: missing write-failed diagnostic\n' >&2
    cat "$TMP/full.stderr" >&2
    exit 1
  fi

  set +e
  "$WEAVEC" --backend "$TMP/app.wir" /dev/full \
    >"$TMP/full-back.stdout" 2>"$TMP/full-back.stderr"
  status=$?
  set -e
  if [[ "$status" -eq 0 ]]; then
    printf 'compiler-write: backend write to /dev/full succeeded\n' >&2
    exit 1
  fi
  if ! grep -Fq 'write failed' "$TMP/full-back.stderr"; then
    printf 'compiler-write: missing backend write-failed diagnostic\n' >&2
    cat "$TMP/full-back.stderr" >&2
    exit 1
  fi
fi

printf 'compiler-write: all checks passed\n'
