#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

usage() {
  printf 'usage: %s <stage1-dir> <stage2-dir> <evidence-dir>\n' "$0" >&2
}

[[ $# -eq 3 ]] || {
  usage
  exit 2
}

STAGE1="$1"
STAGE2="$2"
EVIDENCE="$3"

log() {
  printf '[weavec-fixed-point] %s\n' "$*"
}

fail() {
  printf '[weavec-fixed-point] error: %s\n' "$*" >&2
  exit 1
}

require_tool() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required tool: $1"
}

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    fail 'missing sha256sum or shasum'
  fi
}

normalize_wir() {
  tr '\n\t\r' '   ' < "$1" |
    sed -E 's/[[:space:]]+/ /g; s/\( /(/g; s/ \)/)/g; s/^ //; s/ $//'
  printf '\n'
}

normalize_llvm() {
  awk '
    /^; ModuleID = / { next }
    /^source_filename = / { next }
    /^; source: / { next }
    {
      sub(/[[:space:]]+$/, "")
      if ($0 == "") {
        if (!blank) print ""
        blank = 1
        next
      }
      blank = 0
      print
    }
  ' "$1"
}

summarize_llvm() {
  awk '
    BEGIN {
      definitions = declarations = blocks = instructions = 0
      calls = loads = stores = phis = branches = returns = 0
    }
    /^define[[:space:]]/ { definitions++ }
    /^declare[[:space:]]/ { declarations++ }
    /^[[:space:]]*[[:alnum:]$._-]+:/ { blocks++ }
    /^[[:space:]]+[^;[:space:]}]/ {
      instructions++
      if ($0 ~ /[[:space:]]call[[:space:]]/) calls++
      if ($0 ~ /[[:space:]]load[[:space:]]/) loads++
      if ($0 ~ /^[[:space:]]*store[[:space:]]/ || $0 ~ /=[[:space:]]*store[[:space:]]/) stores++
      if ($0 ~ /[[:space:]]phi[[:space:]]/) phis++
      if ($0 ~ /^[[:space:]]*br[[:space:]]/) branches++
      if ($0 ~ /^[[:space:]]*ret[[:space:]]/) returns++
    }
    END {
      printf "definitions=%d\n", definitions
      printf "declarations=%d\n", declarations
      printf "basic_blocks=%d\n", blocks
      printf "instructions=%d\n", instructions
      printf "calls=%d\n", calls
      printf "loads=%d\n", loads
      printf "stores=%d\n", stores
      printf "phis=%d\n", phis
      printf "branches=%d\n", branches
      printf "returns=%d\n", returns
    }
  ' "$1"
}

normalize_symbols() {
  llvm-nm --defined-only --extern-only --format=posix "$1" |
    awk 'NF >= 2 { print $1, $2 }' |
    LC_ALL=C sort -u
}

require_tool awk
require_tool diff
require_tool llvm-nm
require_tool sed
require_tool sort
require_tool tr

for directory in "$STAGE1" "$STAGE2"; do
  [[ -d "$directory" ]] || fail "stage directory not found: $directory"
  [[ -x "$directory/weavec" ]] || fail "stage compiler not found: $directory/weavec"
  [[ -s "$directory/weavec.wir" ]] || fail "stage WIR not found: $directory/weavec.wir"
  [[ -s "$directory/weavec.ll" ]] || fail "stage LLVM not found: $directory/weavec.ll"
done

rm -rf "$EVIDENCE"
mkdir -p "$EVIDENCE"
: > "$EVIDENCE/hashes.txt"
: > "$EVIDENCE/summary.txt"

mismatches=0

compare_artifact() {
  local label="$1"
  local kind="$2"
  local left="$3"
  local right="$4"
  local normalized_left="$EVIDENCE/$label.stage1.normalized"
  local normalized_right="$EVIDENCE/$label.stage2.normalized"
  local diff_path="$EVIDENCE/$label.diff"

  [[ -s "$left" ]] || fail "missing stage1 artifact: $left"
  [[ -s "$right" ]] || fail "missing stage2 artifact: $right"

  case "$kind" in
    wir)
      normalize_wir "$left" > "$normalized_left"
      normalize_wir "$right" > "$normalized_right"
      ;;
    llvm)
      normalize_llvm "$left" > "$normalized_left"
      normalize_llvm "$right" > "$normalized_right"
      summarize_llvm "$normalized_left" > "$EVIDENCE/$label.stage1.structure"
      summarize_llvm "$normalized_right" > "$EVIDENCE/$label.stage2.structure"
      ;;
    *) fail "unknown artifact kind: $kind" ;;
  esac

  printf '%s  %s\n' "$(sha256_file "$normalized_left")" \
    "$label.stage1.normalized" >> "$EVIDENCE/hashes.txt"
  printf '%s  %s\n' "$(sha256_file "$normalized_right")" \
    "$label.stage2.normalized" >> "$EVIDENCE/hashes.txt"

  if diff -u "$normalized_left" "$normalized_right" > "$diff_path"; then
    rm -f "$diff_path"
    printf '%s=converged\n' "$label" >> "$EVIDENCE/summary.txt"
  else
    mismatches=$((mismatches + 1))
    printf '%s=mismatch\n' "$label" >> "$EVIDENCE/summary.txt"
  fi
}

compare_artifact compiler-wir wir "$STAGE1/weavec.wir" "$STAGE2/weavec.wir"

shopt -s nullglob
stage1_llvm=("$STAGE1"/*.ll)
stage2_llvm=("$STAGE2"/*.ll)
[[ "${#stage1_llvm[@]}" -gt 0 ]] || fail "stage1 contains no LLVM artifacts"
[[ "${#stage2_llvm[@]}" -gt 0 ]] || fail "stage2 contains no LLVM artifacts"
for path in "${stage1_llvm[@]}"; do
  printf '%s\n' "${path##*/}"
done | LC_ALL=C sort > "$EVIDENCE/llvm-files.stage1.txt"
for path in "${stage2_llvm[@]}"; do
  printf '%s\n' "${path##*/}"
done | LC_ALL=C sort > "$EVIDENCE/llvm-files.stage2.txt"
if diff -u "$EVIDENCE/llvm-files.stage1.txt" "$EVIDENCE/llvm-files.stage2.txt" \
    > "$EVIDENCE/llvm-files.diff"; then
  rm -f "$EVIDENCE/llvm-files.diff"
  printf 'llvm-files=converged\n' >> "$EVIDENCE/summary.txt"
else
  mismatches=$((mismatches + 1))
  printf 'llvm-files=mismatch\n' >> "$EVIDENCE/summary.txt"
fi

for path in "${stage1_llvm[@]}"; do
  name="${path##*/}"
  [[ -s "$STAGE2/$name" ]] || continue
  if [[ "$name" == 'weavec.ll' ]]; then
    label='compiler-llvm'
  else
    label="runtime-${name%.ll}"
  fi
  compare_artifact "$label" llvm "$path" "$STAGE2/$name"
done

normalize_symbols "$STAGE1/weavec" > "$EVIDENCE/symbols.stage1.txt"
normalize_symbols "$STAGE2/weavec" > "$EVIDENCE/symbols.stage2.txt"
printf '%s  %s\n' "$(sha256_file "$EVIDENCE/symbols.stage1.txt")" \
  'symbols.stage1.txt' >> "$EVIDENCE/hashes.txt"
printf '%s  %s\n' "$(sha256_file "$EVIDENCE/symbols.stage2.txt")" \
  'symbols.stage2.txt' >> "$EVIDENCE/hashes.txt"
if diff -u "$EVIDENCE/symbols.stage1.txt" "$EVIDENCE/symbols.stage2.txt" \
    > "$EVIDENCE/symbols.diff"; then
  rm -f "$EVIDENCE/symbols.diff"
  printf 'symbols=converged\n' >> "$EVIDENCE/summary.txt"
else
  mismatches=$((mismatches + 1))
  printf 'symbols=mismatch\n' >> "$EVIDENCE/summary.txt"
fi

printf 'mismatches=%d\n' "$mismatches" >> "$EVIDENCE/summary.txt"
if [[ "$mismatches" -ne 0 ]]; then
  log "fixed point failed; retained evidence in $EVIDENCE"
  exit 1
fi

log "fixed point converged; evidence in $EVIDENCE"
