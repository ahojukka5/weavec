#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/weavec-surface-symbols-XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/test.c" <<'C'
#include <assert.h>
#include <stdint.h>
#include "surface_symbols.c"

int main(void) {
    const char source0[] = "add left right local";
    const char source1[] = "add";
    weave_surface_symbols_reset();
    assert(weave_surface_symbol_begin(source0, 0, 3, 2) == 0);
    assert(weave_surface_symbol_add_parameter(2) == 0);
    assert(weave_surface_symbol_add_parameter(3) == 0);
    assert(weave_surface_symbol_return_type(source1, 0, 3) == 2);
    assert(weave_surface_symbol_parameter_count(source1, 0, 3) == 2);
    assert(weave_surface_symbol_parameter_type(source1, 0, 3, 0) == 2);
    assert(weave_surface_symbol_parameter_type(source1, 0, 3, 1) == 3);
    assert(weave_surface_symbol_begin(source1, 0, 3, 2) == -2);
    weave_surface_locals_reset();
    assert(weave_surface_local_add(source0, 15, 5, 3) == 0);
    assert(weave_surface_local_type(source0, 15, 5) == 3);
    weave_surface_set_return_type(6);
    assert(weave_surface_get_return_type() == 6);
    weave_surface_set_error();
    assert(weave_surface_has_error() == 1);
    weave_surface_symbols_reset();
    assert(weave_surface_symbol_return_type(source1, 0, 3) == 0);
    assert(weave_surface_local_type(source0, 15, 5) == 0);
    assert(weave_surface_get_return_type() == 0);
    assert(weave_surface_has_error() == 0);
    return 0;
}
C

"${CC:-cc}" -std=c11 -Wall -Wextra -Werror -I"$ROOT/runtime" \
  "$WORK/test.c" -o "$WORK/test"
"$WORK/test"
printf 'surface-symbols: all checks passed\n'
