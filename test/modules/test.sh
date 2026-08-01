#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-modules-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

command -v cc >/dev/null 2>&1 || {
  printf 'modules: cc is required\n' >&2
  exit 1
}
[[ -x "$WEAVEC" ]] || {
  printf 'modules: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}

cat > "$TMP/registry.c" <<'C'
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include "runtime/surface_symbols.c"

static int32_t begin_module(const char *source, int64_t start, int64_t length) {
    return weave_surface_module_begin(source, start, length);
}

int main(void) {
    const char names[] =
        "alphaanswerhiddenbetamainsharedgammaafnbfndelta";

    weave_surface_symbols_reset();
    assert(weave_surface_module_use_legacy() == 0);
    assert(weave_surface_symbol_begin(names, 5, 6, 2) == 0);
    assert(weave_surface_symbol_return_type(names, 5, 6) == 2);
    assert(weave_surface_symbol_resolution_status() == 0);
    weave_surface_symbols_reset();

    assert(begin_module(names, 0, 5) == 0);                 /* alpha */
    assert(weave_surface_module_add_export(names, 5, 6) == 0); /* answer */
    assert(weave_surface_symbol_begin(names, 5, 6, 2) == 0);
    assert(weave_surface_symbol_begin(names, 11, 6, 3) == 1); /* hidden */

    assert(begin_module(names, 17, 4) == 1);                /* beta */
    assert(weave_surface_module_add_import(
        names, 0, 5, 5, 6) == 0);
    assert(weave_surface_symbol_begin(names, 21, 4, 2) == 2); /* main */
    assert(weave_surface_symbol_return_type(names, 5, 6) == 2);
    assert(weave_surface_symbol_resolution_status() == 0);
    assert(weave_surface_symbol_return_type(names, 11, 6) == 0);
    assert(weave_surface_symbol_resolution_status() == 3); /* private */

    assert(begin_module(names, 31, 5) == 2);                /* gamma */
    assert(weave_surface_symbol_return_type(names, 5, 6) == 0);
    assert(weave_surface_symbol_resolution_status() == 2); /* not imported */
    assert(weave_surface_module_select(names, 17, 4) == 1);
    assert(weave_surface_module_add_import(
        names, 0, 5, 5, 6) == -2);                         /* duplicate */
    assert(weave_surface_module_add_import(
        names, 31, 5, 5, 6) == -3);                        /* conflict */
    assert(weave_surface_module_import_status(
        names, 0, 5, 5, 6) == 0);
    assert(weave_surface_module_import_status(
        names, 0, 5, 11, 6) == -3);
    assert(weave_surface_module_import_status(
        names, 31, 5, 5, 6) == -2);
    weave_surface_symbols_reset();

    assert(begin_module(names, 36, 3) == 0);                /* afn */
    assert(weave_surface_module_add_import(
        names, 39, 3, 39, 3) == 0);                        /* bfn */
    assert(begin_module(names, 39, 3) == 1);                /* bfn */
    assert(weave_surface_module_add_import(
        names, 36, 3, 36, 3) == 0);                        /* afn */
    assert(weave_surface_module_select(names, 36, 3) == 0);
    assert(weave_surface_module_current_has_cycle() == 1);
    weave_surface_symbols_reset();

    assert(begin_module(names, 42, 5) == 0);                /* delta */
    assert(weave_surface_module_use_legacy() == -2);
    weave_surface_symbols_reset();

    puts("modules: registry semantics passed");
    return 0;
}
C
cc -std=c11 -Wall -Wextra -Werror -I"$ROOT" \
  "$TMP/registry.c" -o "$TMP/registry"
"$TMP/registry"

cat > "$TMP/arithmetic.weave" <<'WEAVE'
(module arithmetic
  (export add-two)
  (fn add-two
    (params (left i32) (right i32))
    (returns i32)
    (do
      (return (op add left right)))))
WEAVE

cat > "$TMP/main.weave" <<'WEAVE'
(module application
  (import arithmetic (add-two))
  (entry main
    (params)
    (returns i32)
    (do
      (return (call add-two 40 2)))))
WEAVE

"$WEAVEC" --frontend "$TMP/ordered.wir" \
  "$TMP/main.weave" "$TMP/arithmetic.weave"
"$WEAVEC" --frontend "$TMP/reversed.wir" \
  "$TMP/arithmetic.weave" "$TMP/main.weave"

normalize_wir() {
  sed -E \
    '/^[[:space:]]*; weavec-source-(file|span)-v1 /d' "$1"
}
diff -u \
  <(normalize_wir "$TMP/ordered.wir") \
  <(normalize_wir "$TMP/reversed.wir")

grep -Fq '(call_i32 add-two (const_i32 40) (const_i32 2))' \
  "$TMP/ordered.wir"

"$WEAVEC" build "$TMP/main.weave" "$TMP/arithmetic.weave" \
  -o "$TMP/module-program"
set +e
"$TMP/module-program"
module_status="$?"
set -e
[[ "$module_status" -eq 42 ]]

cat > "$TMP/legacy.weave" <<'WEAVE'
(program
  (name "legacy-module-compatibility")
  (version "0.1")
  (entry main (params) (returns i32) (do (return 42))))
WEAVE
"$WEAVEC" build "$TMP/legacy.weave" -o "$TMP/legacy-program"
set +e
"$TMP/legacy-program"
legacy_status="$?"
set -e
[[ "$legacy_status" -eq 42 ]]

expect_failure() {
  local name="$1"
  local expected="$2"
  shift 2
  rm -f "$TMP/$name.wir"
  set +e
  "$WEAVEC" --frontend "$TMP/$name.wir" "$@" \
    >"$TMP/$name.stdout" 2>"$TMP/$name.stderr"
  local status="$?"
  set -e
  [[ "$status" -ne 0 ]] || {
    printf 'modules: %s unexpectedly succeeded\n' "$name" >&2
    exit 1
  }
  [[ ! -e "$TMP/$name.wir" ]] || {
    printf 'modules: %s published partial WIR\n' "$name" >&2
    exit 1
  }
  grep -Fq "$expected" "$TMP/$name.stderr" || {
    cat "$TMP/$name.stderr" >&2
    printf 'modules: %s missing diagnostic: %s\n' "$name" "$expected" >&2
    exit 1
  }
}

cat > "$TMP/missing-module.weave" <<'WEAVE'
(module application
  (import absent (answer))
  (entry main (params) (returns i32) (do (return (call answer)))))
WEAVE
expect_failure missing-module \
  'weavec: surface module: imported module does not exist absent' \
  "$TMP/missing-module.weave"

cat > "$TMP/private-library.weave" <<'WEAVE'
(module library
  (fn hidden (params) (returns i32) (do (return 42))))
WEAVE
cat > "$TMP/private-main.weave" <<'WEAVE'
(module application
  (import library (hidden))
  (entry main (params) (returns i32) (do (return (call hidden)))))
WEAVE
expect_failure private-import \
  'weavec: surface module: imported symbol is private hidden' \
  "$TMP/private-main.weave" "$TMP/private-library.weave"

cat > "$TMP/missing-symbol-library.weave" <<'WEAVE'
(module library
  (export answer)
  (fn answer (params) (returns i32) (do (return 42))))
WEAVE
cat > "$TMP/missing-symbol-main.weave" <<'WEAVE'
(module application
  (import library (other))
  (entry main (params) (returns i32) (do (return 0))))
WEAVE
expect_failure missing-symbol \
  'weavec: surface module: imported symbol does not exist other' \
  "$TMP/missing-symbol-main.weave" "$TMP/missing-symbol-library.weave"

cat > "$TMP/unimported-main.weave" <<'WEAVE'
(module application
  (entry main (params) (returns i32) (do (return (call answer)))))
WEAVE
expect_failure unimported \
  'weavec: surface call: unresolved function answer' \
  "$TMP/unimported-main.weave" "$TMP/missing-symbol-library.weave"

cat > "$TMP/unknown-export.weave" <<'WEAVE'
(module library
  (export absent)
  (fn answer (params) (returns i32) (do (return 42))))
WEAVE
expect_failure unknown-export \
  'weavec: surface module: exported symbol is not declared in this module absent' \
  "$TMP/unknown-export.weave"

cat > "$TMP/duplicate-module-a.weave" <<'WEAVE'
(module duplicate
  (fn first (params) (returns i32) (do (return 1))))
WEAVE
cat > "$TMP/duplicate-module-b.weave" <<'WEAVE'
(module duplicate
  (fn second (params) (returns i32) (do (return 2))))
WEAVE
expect_failure duplicate-module \
  'weavec: surface module: duplicate module duplicate' \
  "$TMP/duplicate-module-a.weave" "$TMP/duplicate-module-b.weave"

cat > "$TMP/duplicate-export.weave" <<'WEAVE'
(module duplicate-export
  (export answer answer)
  (fn answer (params) (returns i32) (do (return 42))))
WEAVE
expect_failure duplicate-export \
  'weavec: surface module: duplicate export answer' \
  "$TMP/duplicate-export.weave"

cat > "$TMP/duplicate-import.weave" <<'WEAVE'
(module duplicate-import
  (import library (answer))
  (import library (answer))
  (entry main (params) (returns i32) (do (return (call answer)))))
WEAVE
expect_failure duplicate-import \
  'weavec: surface module: duplicate import answer' \
  "$TMP/duplicate-import.weave" "$TMP/missing-symbol-library.weave"

cat > "$TMP/conflicting-import.weave" <<'WEAVE'
(module application
  (import alpha (shared))
  (import beta (shared))
  (entry main (params) (returns i32) (do (return 0))))
WEAVE
expect_failure conflicting-import \
  'weavec: surface module: conflicting imported binding shared' \
  "$TMP/conflicting-import.weave"

cat > "$TMP/cycle-a.weave" <<'WEAVE'
(module cycle-a
  (export from-a)
  (import cycle-b (from-b))
  (fn from-a (params) (returns i32) (do (return 1))))
WEAVE
cat > "$TMP/cycle-b.weave" <<'WEAVE'
(module cycle-b
  (export from-b)
  (import cycle-a (from-a))
  (fn from-b (params) (returns i32) (do (return 2))))
WEAVE
expect_failure import-cycle \
  'weavec: surface module: import cycle includes module' \
  "$TMP/cycle-a.weave" "$TMP/cycle-b.weave"

cat > "$TMP/mixed-program.weave" <<'WEAVE'
(program
  (name "mixed")
  (version "0.1")
  (fn legacy (params) (returns i32) (do (return 1))))
WEAVE
expect_failure mixed-roots \
  'cannot mix legacy program and explicit module roots' \
  "$TMP/arithmetic.weave" "$TMP/mixed-program.weave"

printf 'modules: interfaces, visibility, cycles, and compatibility passed\n'
