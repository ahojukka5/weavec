#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

CHECKOUT="$WORK/weavec"
FAKEBIN="$WORK/bin"
COUNT_FILE="$WORK/clang-count"
ARGS_FILE="$WORK/clang-args"
mkdir -p \
  "$CHECKOUT/scripts" \
  "$CHECKOUT/build" \
  "$CHECKOUT/runtime" \
  "$FAKEBIN"

cp "$ROOT/selfhost.sh" "$CHECKOUT/selfhost.sh"
cp "$ROOT/scripts/weavec-version.sh" "$CHECKOUT/scripts/weavec-version.sh"
cp "$ROOT/scripts/compiler-sources.sh" "$CHECKOUT/scripts/compiler-sources.sh"
ln -s "$ROOT/compiler" "$CHECKOUT/compiler"
ln -s "$ROOT/src" "$CHECKOUT/src"
printf '0\n' > "$COUNT_FILE"
: > "$ARGS_FILE"

cat > "$CHECKOUT/build/weavec" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  --frontend)
    printf '%s\n' '(core-module (core-version 2) (decls))' > "$2"
    ;;
  --backend)
    printf '%s\n' '; fake LLVM' > "$3"
    ;;
  --version)
    printf '%s\n' 'weavec v0.3.0'
    ;;
  *)
    exit 2
    ;;
esac
EOF
chmod +x "$CHECKOUT/build/weavec"

cat > "$FAKEBIN/llvm-as" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
output=""
while (($#)); do
  if [[ "$1" == -o ]]; then
    output="$2"
    shift 2
  else
    shift
  fi
done
[[ -n "$output" ]]
printf '%s\n' 'fake bitcode' > "$output"
EOF
chmod +x "$FAKEBIN/llvm-as"

cat > "$FAKEBIN/llvm-link" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
output=""
while (($#)); do
  if [[ "$1" == -o ]]; then
    output="$2"
    shift 2
  else
    shift
  fi
done
[[ -n "$output" ]]
printf '%s\n' 'linked fake bitcode' > "$output"
EOF
chmod +x "$FAKEBIN/llvm-link"

cat > "$FAKEBIN/llvm-nm" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
chmod +x "$FAKEBIN/llvm-nm"

cat > "$FAKEBIN/clang" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
count="$(cat "$WEAVEC_TEST_CLANG_COUNT")"
printf '%s\n' "$((count + 1))" > "$WEAVEC_TEST_CLANG_COUNT"
printf '%q ' "$@" >> "$WEAVEC_TEST_CLANG_ARGS"
printf '\n' >> "$WEAVEC_TEST_CLANG_ARGS"

output=""
compile_only=0
while (($#)); do
  case "$1" in
    -c)
      compile_only=1
      shift
      ;;
    -o)
      output="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
[[ -n "$output" ]]

if [[ "$compile_only" -eq 1 ]]; then
  printf '%s\n' 'fake decimal support bitcode' > "$output"
  exit 0
fi

cat > "$output" <<'BROKEN'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  --version)
    printf '%s\n' 'weavec v0.3.0-wrong'
    ;;
  --frontend)
    printf '%s\n' '(broken-smoke)' > "$2"
    printf '%s\n' 'synthetic frontend failure' >&2
    exit 7
    ;;
  *)
    exit 2
    ;;
esac
BROKEN
chmod +x "$output"
EOF
chmod +x "$FAKEBIN/clang"

set +e
PATH="$FAKEBIN:$PATH" \
WEAVEC_VERSION_OVERRIDE=v0.3.0 \
WEAVEC_TEST_CLANG_COUNT="$COUNT_FILE" \
WEAVEC_TEST_CLANG_ARGS="$ARGS_FILE" \
  bash "$CHECKOUT/selfhost.sh" > "$WORK/selfhost.stdout" 2> "$WORK/selfhost.stderr"
status="$?"
set -e

[[ "$status" -ne 0 ]] || {
  printf 'selfhost-link-policy: unusable compiler unexpectedly succeeded\n' >&2
  exit 1
}
[[ "$(cat "$COUNT_FILE")" == 2 ]] || {
  printf 'selfhost-link-policy: expected support compile plus one link, got %s\n' \
    "$(cat "$COUNT_FILE")" >&2
  exit 1
}
[[ "$(wc -l < "$ARGS_FILE")" -eq 2 ]]
sed -n '1p' "$ARGS_FILE" | grep -Fq -- '-emit-llvm'
sed -n '1p' "$ARGS_FILE" | grep -Fq -- '-c'
sed -n '1p' "$ARGS_FILE" | grep -Fq -- 'runtime/decimal_surface.c'
sed -n '1p' "$ARGS_FILE" | grep -Fq -- 'decimal-surface.bc'
if sed -n '2p' "$ARGS_FILE" | grep -Fq -- '-emit-llvm'; then
  printf 'selfhost-link-policy: final compiler link became a compile-only step\n' >&2
  exit 1
fi
sed -n '2p' "$ARGS_FILE" | grep -Fq -- 'runtime/portable.c'
sed -n '2p' "$ARGS_FILE" | grep -Fq -- 'runtime/formatter_driver.c'

stage="$CHECKOUT/build/selfhost/stage1/weavec"
[[ ! -e "$stage" ]]
[[ -x "$stage.failed" ]]
[[ -s "$stage.version.txt" ]]
[[ -s "$stage.smoke.wir" ]]
[[ -e "$stage.smoke.stdout" ]]
[[ -s "$stage.smoke.stderr" ]]
grep -Fq 'linked compiler failed validation' "$WORK/selfhost.stderr"
grep -Fq 'synthetic frontend failure' "$stage.smoke.stderr"

printf 'selfhost-link-policy: support compile and single-attempt failure retention passed\n'
