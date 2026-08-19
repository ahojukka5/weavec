#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Binding and call-argument tables must not overflow silently (#263).
# 65 locals is rejected. A 33-argument call is sized from the actual
# count and compiles.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-backend-table-limits-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'backend-table-limits: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}

python3 - "$TMP" <<'PY'
from pathlib import Path
import sys

tmp = Path(sys.argv[1])

lets = "\n".join(
    f"        (let v{i} i32 (const_i32 {i}))" for i in range(65)
)
(tmp / "too-many-locals.wir").write_text(
    "(core-module\n"
    "  (core-version 3)\n"
    "  (decls\n"
    "    (fn main (params) (returns i32)\n"
    "      (do\n"
    f"{lets}\n"
    "        (return (local_get v0))))))\n",
    encoding="utf-8",
)

lets64 = "\n".join(
    f"        (let v{i} i32 (const_i32 {i}))" for i in range(64)
)
(tmp / "sixty-four-locals.wir").write_text(
    "(core-module\n"
    "  (core-version 3)\n"
    "  (decls\n"
    "    (fn main (params) (returns i32)\n"
    "      (do\n"
    f"{lets64}\n"
    "        (return (local_get v0))))))\n",
    encoding="utf-8",
)

params = " ".join(f"(a{i} i32)" for i in range(33))
args = " ".join(f"(const_i32 {i})" for i in range(33))
(tmp / "wide-call.wir").write_text(
    "(core-module\n"
    "  (core-version 3)\n"
    "  (decls\n"
    f"    (fn wide (params {params}) (returns i32)\n"
    "      (do (return (param_get a0))))\n"
    "    (fn main (params) (returns i32)\n"
    f"      (do (return (call_i32 wide {args}))))))\n",
    encoding="utf-8",
)
PY

set +e
"$WEAVEC" --backend "$TMP/too-many-locals.wir" "$TMP/too-many-locals.ll" \
  2>"$TMP/too-many-locals.stderr"
status="$?"
set -e
if [[ "$status" -eq 0 ]]; then
  printf 'backend-table-limits: 65 locals were accepted\n' >&2
  exit 1
fi
[[ ! -e "$TMP/too-many-locals.ll" ]] || {
  printf 'backend-table-limits: published LLVM for 65 locals\n' >&2
  exit 1
}
grep -Fq 'function exceeds 64 locals' "$TMP/too-many-locals.stderr"

"$WEAVEC" --backend "$TMP/sixty-four-locals.wir" "$TMP/sixty-four-locals.ll" \
  2>"$TMP/sixty-four-locals.stderr" || {
  printf 'backend-table-limits: 64 locals rejected\n' >&2
  cat "$TMP/sixty-four-locals.stderr" >&2
  exit 1
}
grep -Fq 'define i32 @main()' "$TMP/sixty-four-locals.ll"

"$WEAVEC" --backend "$TMP/wide-call.wir" "$TMP/wide-call.ll" \
  2>"$TMP/wide-call.stderr" || {
  printf 'backend-table-limits: 33-argument call rejected\n' >&2
  cat "$TMP/wide-call.stderr" >&2
  exit 1
}
grep -Fq 'call i32 @wide(' "$TMP/wide-call.ll"
if grep -Fq '%t-1' "$TMP/wide-call.ll"; then
  printf 'backend-table-limits: wide call emitted %%t-1\n' >&2
  exit 1
fi

printf 'backend-table-limits: passed\n'
