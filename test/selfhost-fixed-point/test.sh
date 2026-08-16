#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/bin" "$WORK/stage1" "$WORK/stage2"
cat > "$WORK/bin/llvm-nm" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
for argument in "$@"; do
  case "$argument" in
    -*) ;;
    *) input="$argument" ;;
  esac
done
cat "$input.symbols"
SH
chmod +x "$WORK/bin/llvm-nm"

write_stage() {
  local stage="$1"
  cat > "$stage/weavec.wir" <<'WIR'
(core-module
  (core-version 3)
  (decls))
WIR
  cat > "$stage/weavec.ll" <<LLVM
; ModuleID = '$stage/weavec.ll'
source_filename = "$stage/weavec.ll"
define i32 @main() {
entry:
  ret i32 0
}
LLVM
  for module in sexpr_tokens sexpr_tree sexpr_lexer sexpr_parser; do
    cat > "$stage/$module.ll" <<LLVM
; ModuleID = '$module'
define i32 @${module}_value() {
entry:
  ret i32 0
}
LLVM
  done
  printf '#!/usr/bin/env bash\nexit 0\n' > "$stage/weavec"
  chmod +x "$stage/weavec"
  printf 'main T 0 0\nshared_symbol T 0 0\n' > "$stage/weavec.symbols"
}

write_stage "$WORK/stage1"
write_stage "$WORK/stage2"

PATH="$WORK/bin:$PATH" \
  bash "$ROOT/scripts/verify-selfhost-fixed-point.sh" \
    "$WORK/stage1" "$WORK/stage2" "$WORK/evidence-pass"
grep -Fq 'mismatches=0' "$WORK/evidence-pass/summary.txt"
[[ ! -e "$WORK/evidence-pass/compiler-llvm.diff" ]]

printf '  %%value = add i32 1, 1\n' \
  >> "$WORK/stage2/weavec.ll"
set +e
PATH="$WORK/bin:$PATH" \
  bash "$ROOT/scripts/verify-selfhost-fixed-point.sh" \
    "$WORK/stage1" "$WORK/stage2" "$WORK/evidence-fail" \
    >/dev/null 2>&1
status="$?"
set -e
[[ "$status" -ne 0 ]]
grep -Fq 'compiler-llvm=mismatch' "$WORK/evidence-fail/summary.txt"
[[ -s "$WORK/evidence-fail/compiler-llvm.diff" ]]
[[ -s "$WORK/evidence-fail/compiler-llvm.stage1.structure" ]]
[[ -s "$WORK/evidence-fail/compiler-llvm.stage2.structure" ]]

cp "$WORK/stage1/weavec.ll" "$WORK/stage2/weavec.ll"
printf 'extra_symbol T 0 0\n' >> "$WORK/stage2/weavec.symbols"
set +e
PATH="$WORK/bin:$PATH" \
  bash "$ROOT/scripts/verify-selfhost-fixed-point.sh" \
    "$WORK/stage1" "$WORK/stage2" "$WORK/evidence-symbols" \
    >/dev/null 2>&1
status="$?"
set -e
[[ "$status" -ne 0 ]]
grep -Fq 'symbols=mismatch' "$WORK/evidence-symbols/summary.txt"
[[ -s "$WORK/evidence-symbols/symbols.diff" ]]

printf 'selfhost-fixed-point: convergence and evidence retention passed\n'
