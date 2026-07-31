#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

CHECKOUT="$WORK/weavec"
FAKEBIN="$WORK/bin"
COUNT_FILE="$WORK/clang-count"
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
  bash "$CHECKOUT/selfhost.sh" > "$WORK/selfhost.stdout" 2> "$WORK/selfhost.stderr"
status="$?"
set -e

[[ "$status" -ne 0 ]] || {
  printf 'selfhost-link-policy: unusable compiler unexpectedly succeeded\n' >&2
  exit 1
}
[[ "$(cat "$COUNT_FILE")" == 1 ]] || {
  printf 'selfhost-link-policy: expected one clang invocation, got %s\n' \
    "$(cat "$COUNT_FILE")" >&2
  exit 1
}

stage="$CHECKOUT/build/selfhost/stage1/weavec"
[[ ! -e "$stage" ]]
[[ -x "$stage.failed" ]]
[[ -s "$stage.version.txt" ]]
[[ -s "$stage.smoke.wir" ]]
[[ -e "$stage.smoke.stdout" ]]
[[ -s "$stage.smoke.stderr" ]]
grep -Fq 'linked compiler failed validation' "$WORK/selfhost.stderr"
grep -Fq 'synthetic frontend failure' "$stage.smoke.stderr"

printf 'selfhost-link-policy: single-attempt failure retention passed\n'
