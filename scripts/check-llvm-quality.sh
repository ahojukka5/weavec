#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LLVM_DIR="${WEAVEC_LLVM_QUALITY_DIR:-$ROOT/test/performance/expected-llvm}"
BASELINE="${WEAVEC_LLVM_QUALITY_BASELINE:-$ROOT/test/performance/llvm-quality-baseline.tsv}"
MODE=check

case "${1:-}" in
  "") ;;
  --write-baseline) MODE=write ;;
  *)
    printf 'usage: %s [--write-baseline]\n' "$0" >&2
    exit 2
    ;;
esac

[[ -d "$LLVM_DIR" ]] || {
  printf 'llvm-quality: missing LLVM directory: %s\n' "$LLVM_DIR" >&2
  exit 1
}

metrics() {
  awk '
    /^define[[:space:]]/ { in_function = 1; next }
    in_function && /^}/ { in_function = 0; next }
    in_function {
      line = $0
      sub(/^[[:space:]]+/, "", line)
      if (line == "" || line ~ /^;/ || line ~ /^[A-Za-z0-9_.-]+:$/) next
      instructions++
      if (line ~ /(^|= )alloca[[:space:]]/) alloca++
      if (line ~ /(^|= )load[[:space:]]/) load++
      if (line ~ /^store[[:space:]]/) store++
      if (line ~ /(^|= )call[[:space:]]/) call++
      if (line ~ /(^|= )phi[[:space:]]/) phi++
      if (line ~ /^br[[:space:]]/) branch++
      if (line ~ /(add|or|xor) i(32|64) [^,]+, 0([[:space:]]|$)/ ||
          line ~ /mul i(32|64) [^,]+, 1([[:space:]]|$)/) identity++
    }
    END {
      printf "%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\n",
        instructions, alloca, load, store, call, phi, branch, identity
    }
  ' "$1"
}

validate_names_and_values() {
  local path="$1"
  local failed=0
  if grep -En '(^|[^A-Za-z0-9_])%[0-9]+([^A-Za-z0-9_]|$)' "$path" >/tmp/weavec-llvm-quality.$$ 2>/dev/null; then
    printf 'llvm-quality: anonymous numeric SSA value in %s\n' "$path" >&2
    cat /tmp/weavec-llvm-quality.$$ >&2
    failed=1
  fi
  if grep -En '^[[:space:]]*[0-9]+:' "$path" >/tmp/weavec-llvm-quality.$$ 2>/dev/null; then
    printf 'llvm-quality: anonymous numeric block label in %s\n' "$path" >&2
    cat /tmp/weavec-llvm-quality.$$ >&2
    failed=1
  fi
  if grep -En '(^|[[:space:],(])(undef|poison)([[:space:],)]|$)' "$path" >/tmp/weavec-llvm-quality.$$ 2>/dev/null; then
    printf 'llvm-quality: undefined or poison value in %s\n' "$path" >&2
    cat /tmp/weavec-llvm-quality.$$ >&2
    failed=1
  fi
  rm -f /tmp/weavec-llvm-quality.$$
  return "$failed"
}

mapfile_portable() {
  # Bash 3 on macOS has no mapfile. Populate the named array through eval using
  # shell-quoted paths produced by printf %q.
  local array_name="$1"
  shift
  local assignment="$array_name=("
  local value
  while IFS= read -r value; do
    printf -v value '%q' "$value"
    assignment+=" $value"
  done < <("$@")
  assignment+=")"
  eval "$assignment"
}

list_llvm() {
  find "$LLVM_DIR" -maxdepth 1 -type f -name '*.ll' -print | sort
}

mapfile_portable llvm_files list_llvm
[[ "${#llvm_files[@]}" -gt 0 ]] || {
  printf 'llvm-quality: no LLVM files found in %s\n' "$LLVM_DIR" >&2
  exit 1
}

if [[ "$MODE" == write ]]; then
  tmp="$BASELINE.tmp.$$"
  mkdir -p "$(dirname "$BASELINE")"
  {
    printf '# weavec-llvm-quality-v1\n'
    printf '# file\tinstructions\talloca\tload\tstore\tcall\tphi\tbranch\tidentity\n'
    for path in "${llvm_files[@]}"; do
      validate_names_and_values "$path"
      printf '%s\t' "$(basename "$path")"
      metrics "$path"
    done
  } > "$tmp"
  mv "$tmp" "$BASELINE"
  printf 'llvm-quality: wrote %s for %d fixtures\n' \
    "$BASELINE" "${#llvm_files[@]}"
  exit 0
fi

[[ -f "$BASELINE" ]] || {
  printf 'llvm-quality: missing baseline: %s\n' "$BASELINE" >&2
  printf 'llvm-quality: run scripts/check-llvm-quality.sh --write-baseline\n' >&2
  exit 1
}

failed=0
seen=0
while IFS=$'\t' read -r file instructions alloca load store call phi branch identity; do
  [[ -n "$file" && "$file" != \#* ]] || continue
  path="$LLVM_DIR/$file"
  if [[ ! -f "$path" ]]; then
    printf 'llvm-quality: baseline references missing fixture: %s\n' "$file" >&2
    failed=1
    continue
  fi
  seen=$((seen + 1))
  if ! validate_names_and_values "$path"; then
    failed=1
  fi
  read -r actual_instructions actual_alloca actual_load actual_store \
    actual_call actual_phi actual_branch actual_identity < <(
      metrics "$path" | tr '\t' ' '
    )
  names=(instructions alloca load store call phi branch identity)
  expected=("$instructions" "$alloca" "$load" "$store" "$call" "$phi" "$branch" "$identity")
  actual=("$actual_instructions" "$actual_alloca" "$actual_load" "$actual_store" "$actual_call" "$actual_phi" "$actual_branch" "$actual_identity")
  for index in "${!names[@]}"; do
    if (( actual[index] > expected[index] )); then
      printf 'llvm-quality: %s %s increased: %s -> %s\n' \
        "$file" "${names[index]}" "${expected[index]}" "${actual[index]}" >&2
      failed=1
    fi
  done
done < "$BASELINE"

if (( seen != ${#llvm_files[@]} )); then
  printf 'llvm-quality: fixture count differs: baseline=%d current=%d\n' \
    "$seen" "${#llvm_files[@]}" >&2
  failed=1
fi

for path in "${llvm_files[@]}"; do
  file="$(basename "$path")"
  if ! grep -Fq "$file"$'\t' "$BASELINE"; then
    printf 'llvm-quality: fixture missing from baseline: %s\n' "$file" >&2
    failed=1
  fi
done

if (( failed != 0 )); then
  exit 1
fi
printf 'llvm-quality: %d fixtures within structural budgets\n' "${#llvm_files[@]}"
