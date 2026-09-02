#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Compiler-independent surface conformance corpus (#385).
#
# Every case is declared only in terms of public behavior: canonical surface
# source, compile success or a stable diagnostic code, native stdout/stderr/exit,
# and canonical formatter observations. Nothing here asserts WIR text, LLVM text,
# mangled names, or any other compiler-internal spelling, so the same corpus
# qualifies the checkout compiler, an extracted release package, and a stage-2
# self-host binary through the ordinary WEAVEC override:
#
#   WEAVEC=/path/to/weavec bash test/conformance/run.sh
#
# See docs/conformance.md.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CORPUS="$ROOT/test/conformance"
CASES_DIR="$CORPUS/cases"
MANIFEST="$CORPUS/MANIFEST"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"

selected=""
list_only=0
for arg in "$@"; do
  case "$arg" in
    --list) list_only=1 ;;
    --case=*) selected="${arg#--case=}" ;;
    -h|--help)
      cat <<'USAGE'
usage: test/conformance/run.sh [--list] [--case=NAME]

Run the compiler-independent surface conformance corpus. The compiler under
test is $WEAVEC, defaulting to build/weavec. The user-facing standard library
is $WEAVEC_STDLIB, defaulting to the stdlib directory beside the compiler and
then to the repository stdlib.

  --list        print the discovered case names and exit
  --case=NAME   run one case instead of the whole corpus
USAGE
      exit 0
      ;;
    *)
      printf 'conformance: unknown argument: %s\n' "$arg" >&2
      exit 2
      ;;
  esac
done

log() {
  printf '[conformance] %s\n' "$*"
}

# Case directories are discovered from the filesystem, never from a
# hand-maintained list, so the corpus cannot silently shrink to a subset.
discover_cases() {
  local dir
  for dir in "$CASES_DIR"/*/; do
    [[ -d "$dir" ]] || continue
    printf '%s\n' "$(basename "$dir")"
  done | LC_ALL=C sort
}

discovered=()
while IFS= read -r discovered_case; do
  [[ -n "$discovered_case" ]] || continue
  discovered+=("$discovered_case")
done < <(discover_cases)

[[ "${#discovered[@]}" -gt 0 ]] || {
  printf 'conformance: no cases discovered under %s\n' "$CASES_DIR" >&2
  exit 1
}

if [[ "$list_only" -eq 1 ]]; then
  printf '%s\n' "${discovered[@]}"
  exit 0
fi

# Discoverability guard: the registered manifest and the discovered directories
# must agree exactly, in both directions.
[[ -f "$MANIFEST" ]] || {
  printf 'conformance: missing case manifest: %s\n' "$MANIFEST" >&2
  exit 1
}
if ! diff -u \
  <(grep -v '^[[:space:]]*\(#.*\)\?$' "$MANIFEST" | LC_ALL=C sort) \
  <(printf '%s\n' "${discovered[@]}") >/dev/null; then
  printf 'conformance: MANIFEST does not match the discovered cases\n' >&2
  diff -u \
    <(grep -v '^[[:space:]]*\(#.*\)\?$' "$MANIFEST" | LC_ALL=C sort) \
    <(printf '%s\n' "${discovered[@]}") >&2 || true
  exit 1
fi

[[ -x "$WEAVEC" ]] || {
  printf 'conformance: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}

# An extracted release package keeps stdlib beside the installed compiler; a
# checkout resolves the same relative path to the repository stdlib.
resolve_stdlib() {
  if [[ -n "${WEAVEC_STDLIB:-}" ]]; then
    printf '%s\n' "$WEAVEC_STDLIB"
    return
  fi
  local beside
  beside="$(cd "$(dirname "$WEAVEC")/.." && pwd)/stdlib"
  if [[ -f "$beside/io.weave" ]]; then
    printf '%s\n' "$beside"
    return
  fi
  printf '%s\n' "$ROOT/stdlib"
}
STDLIB="$(resolve_stdlib)"
[[ -f "$STDLIB/io.weave" ]] || {
  printf 'conformance: standard library not found: %s\n' "$STDLIB" >&2
  exit 1
}

TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-conformance-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

native_supported=1
for tool in llc clang; do
  command -v "$tool" >/dev/null 2>&1 || native_supported=0
done

pass_count=0
fail_count=0
skip_count=0

case_failed=0

fail() {
  printf '[conformance] FAIL %s: %s\n' "$1" "$2" >&2
  case_failed=1
}

meta_value() {
  local file="$1"
  local key="$2"
  sed -n -E "s/^${key}:[[:space:]]*(.*)$/\1/p" "$file" | head -n 1
}

run_one_case() {
  local name="$1"
  local dir="$CASES_DIR/$name"
  local meta="$dir/meta"
  local work="$TMP/$name"
  case_failed=0
  mkdir -p "$work"

  [[ -f "$meta" ]] || {
    fail "$name" "missing meta"
    return
  }

  local mode area sources stdlib_mods
  mode="$(meta_value "$meta" mode)"
  area="$(meta_value "$meta" area)"
  sources="$(meta_value "$meta" sources)"
  stdlib_mods="$(meta_value "$meta" stdlib)"

  [[ -n "$area" ]] || fail "$name" "meta is missing area"
  [[ -n "$sources" ]] || fail "$name" "meta is missing sources"
  if [[ "$case_failed" -ne 0 ]]; then
    return
  fi

  local -a inputs=()
  local module
  for module in $stdlib_mods; do
    [[ -f "$STDLIB/$module" ]] || {
      fail "$name" "standard-library module not found: $module"
      return
    }
    inputs+=("$STDLIB/$module")
  done
  local source
  for source in $sources; do
    [[ -f "$dir/$source" ]] || {
      fail "$name" "declared source not found: $source"
      return
    }
    inputs+=("$dir/$source")
  done

  case "$mode" in
    run) run_native_case "$name" "$dir" "$meta" "$work" "${inputs[@]}" ;;
    compile-fail) run_compile_fail_case "$name" "$dir" "$meta" "$work" "${inputs[@]}" ;;
    format) run_format_case "$name" "$dir" "$meta" "$work" ;;
    *)
      fail "$name" "unknown mode: ${mode:-<empty>}"
      return
      ;;
  esac

  if [[ "$case_failed" -ne 0 ]]; then
    return
  fi
  check_canonical_sources "$name" "$dir" "$meta" "$sources"
}

# Cases that declare canonical sources must already be in canonical form, so
# `weavec fmt --check` observes the formatter contract on real corpus source.
check_canonical_sources() {
  local name="$1" dir="$2" meta="$3" sources="$4"
  local canonical
  canonical="$(meta_value "$meta" canonical)"
  [[ "$canonical" == "yes" ]] || return 0
  local source
  for source in $sources; do
    if ! "$WEAVEC" fmt --check "$dir/$source" >/dev/null 2>&1; then
      fail "$name" "declared canonical source is not canonical: $source"
    fi
  done
}

run_native_case() {
  local name="$1" dir="$2" meta="$3" work="$4"
  shift 4
  local -a inputs=("$@")

  if [[ "$native_supported" -eq 0 ]]; then
    printf '[conformance] SKIP %s: llc or clang unavailable\n' "$name"
    skip_count=$((skip_count + 1))
    case_failed=2
    return
  fi

  local expected_exit args
  expected_exit="$(meta_value "$meta" exit)"
  expected_exit="${expected_exit:-0}"
  args="$(meta_value "$meta" args)"

  [[ -f "$dir/expected-stdout" ]] || {
    fail "$name" "run case is missing expected-stdout"
    return
  }

  if ! "$WEAVEC" build "${inputs[@]}" -o "$work/program" \
    >"$work/build.out" 2>"$work/build.err"; then
    fail "$name" "build failed"
    cat "$work/build.err" >&2
    return
  fi

  local status=0
  set +e
  # shellcheck disable=SC2086
  LC_ALL=C "$work/program" $args >"$work/stdout" 2>"$work/stderr"
  status="$?"
  set -e

  if [[ "$status" != "$expected_exit" ]]; then
    fail "$name" "expected exit $expected_exit, got $status"
    cat "$work/stderr" >&2
    return
  fi
  if ! cmp -s "$dir/expected-stdout" "$work/stdout"; then
    fail "$name" "stdout mismatch"
    diff -u "$dir/expected-stdout" "$work/stdout" >&2 || true
    return
  fi
  if [[ -f "$dir/expected-stderr" ]]; then
    if ! cmp -s "$dir/expected-stderr" "$work/stderr"; then
      fail "$name" "stderr mismatch"
      diff -u "$dir/expected-stderr" "$work/stderr" >&2 || true
      return
    fi
  elif [[ -s "$work/stderr" ]]; then
    fail "$name" "unexpected stderr output"
    cat "$work/stderr" >&2
    return
  fi
}

run_compile_fail_case() {
  local name="$1" dir="$2" meta="$3" work="$4"
  shift 4
  local -a inputs=("$@")

  local expected_code expected_exit
  expected_code="$(meta_value "$meta" diagnostic)"
  expected_exit="$(meta_value "$meta" exit)"
  expected_exit="${expected_exit:-10}"

  [[ -n "$expected_code" ]] || {
    fail "$name" "compile-fail case is missing diagnostic"
    return
  }

  rm -f "$work/program" "$work/diagnostics.json"
  local status=0
  set +e
  "$WEAVEC" build "${inputs[@]}" -o "$work/program" \
    --diagnostics-json "$work/diagnostics.json" \
    >"$work/build.out" 2>"$work/build.err"
  status="$?"
  set -e

  if [[ "$status" != "$expected_exit" ]]; then
    fail "$name" "expected stable exit $expected_exit, got $status"
    cat "$work/build.err" >&2
    return
  fi
  if [[ -e "$work/program" ]]; then
    fail "$name" "failed build published an executable"
    return
  fi
  [[ -f "$work/diagnostics.json" ]] || {
    fail "$name" "no diagnostics document was published"
    return
  }
  if ! python3 - "$work/diagnostics.json" "$expected_code" "$expected_exit" <<'PY'
import json
import sys

document = json.load(open(sys.argv[1], encoding="utf-8"))
expected_code = sys.argv[2]
expected_exit = int(sys.argv[3])
if document.get("format") != "weavec-diagnostics-v1":
    sys.exit("unexpected diagnostics format: %r" % document.get("format"))
if document.get("status") != "failed":
    sys.exit("unexpected diagnostics status: %r" % document.get("status"))
if document.get("exit_code") != expected_exit:
    sys.exit("unexpected diagnostics exit_code: %r" % document.get("exit_code"))
codes = [entry.get("code") for entry in document.get("diagnostics", [])]
if expected_code not in codes:
    sys.exit("expected diagnostic %s, got %s" % (expected_code, codes))
PY
  then
    fail "$name" "diagnostics document did not match the expected contract"
    return
  fi
}

run_format_case() {
  local name="$1" dir="$2" meta="$3" work="$4"
  local input
  input="$(meta_value "$meta" sources)"

  [[ -f "$dir/expected-format" ]] || {
    fail "$name" "format case is missing expected-format"
    return
  }

  cp "$dir/$input" "$work/input.weave"
  local status=0
  set +e
  "$WEAVEC" fmt --check "$work/input.weave" >/dev/null 2>&1
  status="$?"
  set -e
  if [[ "$status" -ne 1 ]]; then
    fail "$name" "expected noncanonical fmt --check exit 1, got $status"
    return
  fi
  if ! cmp -s "$dir/$input" "$work/input.weave"; then
    fail "$name" "fmt --check modified the input"
    return
  fi

  if ! "$WEAVEC" fmt --output "$work/formatted.weave" "$work/input.weave" \
    >"$work/fmt.out" 2>"$work/fmt.err"; then
    fail "$name" "fmt --output failed"
    cat "$work/fmt.err" >&2
    return
  fi
  if ! cmp -s "$dir/expected-format" "$work/formatted.weave"; then
    fail "$name" "canonical output mismatch"
    diff -u "$dir/expected-format" "$work/formatted.weave" >&2 || true
    return
  fi
  if ! "$WEAVEC" fmt --check "$work/formatted.weave" >/dev/null 2>&1; then
    fail "$name" "canonical output is not itself canonical"
    return
  fi
}

log "compiler: $WEAVEC"
log "standard library: $STDLIB"
log "cases: ${#discovered[@]}"
[[ "$native_supported" -eq 1 ]] || \
  log 'llc or clang missing: native run cases are skipped'

executed=0
for name in "${discovered[@]}"; do
  if [[ -n "$selected" && "$name" != "$selected" ]]; then
    continue
  fi
  executed=$((executed + 1))
  run_one_case "$name"
  if [[ "$case_failed" -eq 0 ]]; then
    log "ok $name"
    pass_count=$((pass_count + 1))
  elif [[ "$case_failed" -eq 1 ]]; then
    fail_count=$((fail_count + 1))
  fi
done

if [[ -n "$selected" && "$executed" -eq 0 ]]; then
  printf 'conformance: no such case: %s\n' "$selected" >&2
  exit 1
fi

# The corpus is complete only when every discovered case actually ran.
if [[ -z "$selected" && "$executed" -ne "${#discovered[@]}" ]]; then
  printf 'conformance: ran %s of %s discovered cases\n' \
    "$executed" "${#discovered[@]}" >&2
  exit 1
fi

log "$pass_count passed, $fail_count failed, $skip_count skipped"
[[ "$fail_count" -eq 0 ]] || exit 1
log 'passed'
