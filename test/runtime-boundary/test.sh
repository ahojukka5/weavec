#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

[[ -r "$ROOT/docs/runtime-boundary.md" ]]
[[ -r "$ROOT/stdlib/io.weave" ]]
[[ ! -e "$ROOT/runtime/basic_io.c" ]]

if grep -ERn 'snprintf|printf|weave_rt_print_f64' \
    "$ROOT/runtime/program.c" "$ROOT/stdlib/io.weave"; then
  printf 'runtime-boundary: floating formatting escaped from Weave\n' >&2
  exit 1
fi

grep -Fq '(fn print_f64' "$ROOT/stdlib/io.weave"
grep -Fq '(fn write_fraction6' "$ROOT/stdlib/io.weave"
grep -Fq '(extern write' "$ROOT/stdlib/io.weave"
grep -Fq '(extern strlen' "$ROOT/stdlib/io.weave"

printf 'runtime-boundary: Weave-owned floating formatting passed\n'
