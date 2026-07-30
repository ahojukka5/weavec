#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-build-boundary-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

CHECKOUT="$TMP/checkout"
TOOLS="$TMP/tools"
WEAVEC1_SDK="$TMP/weavec1-sdk"
BOOTSTRAP_SDK="$TMP/bootstrap-sdk"
LOG="$TMP/invocations.log"
mkdir -p \
  "$CHECKOUT/scripts" \
  "$CHECKOUT/build/selfhost/stage2" \
  "$TOOLS" \
  "$WEAVEC1_SDK/bin" \
  "$BOOTSTRAP_SDK/bin" \
  "$BOOTSTRAP_SDK/lib"

cp "$ROOT/build.sh" "$CHECKOUT/build.sh"
chmod +x "$CHECKOUT/build.sh"

cp "$ROOT/scripts/compiler-sources.sh" "$CHECKOUT/scripts/compiler-sources.sh"
ln -s "$ROOT/compiler" "$CHECKOUT/compiler"
ln -s "$ROOT/src" "$CHECKOUT/src"

cat > "$CHECKOUT/scripts/weavec-version.sh" <<'EOF_VERSION'
weavec_version_string() {
  printf '%s\n' "${WEAVEC_VERSION_OVERRIDE:-v0.0.0+test}"
}

weavec_write_version_llvm() {
  printf '; test version %s\n' "$1" > "$2"
}
EOF_VERSION

cat > "$WEAVEC1_SDK/bin/weavec1" <<EOF_WEAVEC1
#!/usr/bin/env bash
printf 'weavec1 %s %s\n' "\$1" "\$2" >> "$LOG"
printf '; seed llvm\n' > "\$2"
EOF_WEAVEC1
chmod +x "$WEAVEC1_SDK/bin/weavec1"

cat > "$BOOTSTRAP_SDK/bin/weavec-bootstrap" <<'EOF_BOOTSTRAP'
#!/usr/bin/env bash
exit 0
EOF_BOOTSTRAP
chmod +x "$BOOTSTRAP_SDK/bin/weavec-bootstrap"

cat > "$BOOTSTRAP_SDK/bin/weavec-bootstrap-cat" <<EOF_BOOTSTRAP_CAT
#!/usr/bin/env bash
printf 'bootstrap %s\n' "\$1" >> "$LOG"
printf '(core-module (core-version 2) (decls))\n' > "\$1"
EOF_BOOTSTRAP_CAT
chmod +x "$BOOTSTRAP_SDK/bin/weavec-bootstrap-cat"
printf 'parser bitcode\n' > "$BOOTSTRAP_SDK/lib/libweave-sexpr.bc"

cat > "$CHECKOUT/build/selfhost/stage2/weavec" <<EOF_STALE
#!/usr/bin/env bash
printf 'stale-stage2 %s\n' "\$*" >> "$LOG"
exit 99
EOF_STALE
chmod +x "$CHECKOUT/build/selfhost/stage2/weavec"

cat > "$TMP/explicit-backend" <<EOF_EXPLICIT
#!/usr/bin/env bash
printf 'explicit-backend %s %s %s\n' "\$1" "\$2" "\$3" >> "$LOG"
printf '; explicit llvm\n' > "\$3"
EOF_EXPLICIT
chmod +x "$TMP/explicit-backend"

cat > "$TOOLS/llvm-as" <<'EOF_LLVM_AS'
#!/usr/bin/env bash
input="$1"
shift
[[ "$1" == -o ]]
printf 'assembled %s\n' "$input" > "$2"
EOF_LLVM_AS
chmod +x "$TOOLS/llvm-as"

cat > "$TOOLS/llvm-link" <<'EOF_LLVM_LINK'
#!/usr/bin/env bash
output=""
while [[ "$#" -gt 0 ]]; do
  if [[ "$1" == -o ]]; then
    output="$2"
    break
  fi
  shift
done
[[ -n "$output" ]]
printf 'linked bitcode\n' > "$output"
EOF_LLVM_LINK
chmod +x "$TOOLS/llvm-link"

cat > "$TOOLS/clang" <<'EOF_CLANG'
#!/usr/bin/env bash
output=""
while [[ "$#" -gt 0 ]]; do
  if [[ "$1" == -o ]]; then
    output="$2"
    break
  fi
  shift
done
[[ -n "$output" ]]
printf '#!/usr/bin/env bash\nexit 0\n' > "$output"
chmod +x "$output"
EOF_CLANG
chmod +x "$TOOLS/clang"

run_build() {
  (
    cd "$CHECKOUT"
    PATH="$TOOLS:$PATH" \
    WEAVEC1_SDK="$WEAVEC1_SDK" \
    WEAVEC_BOOTSTRAP_SDK="$BOOTSTRAP_SDK" \
    WEAVEC_VERSION_OVERRIDE=v0.0.0+test \
    "$@"
  )
}

: > "$LOG"
run_build ./build.sh >/dev/null 2>&1
grep -q '^weavec1 ' "$LOG"
if grep -q '^stale-stage2 ' "$LOG"; then
  echo 'build-boundary: stale stage-two backend was selected implicitly' >&2
  exit 1
fi

: > "$LOG"
run_build env WEAVEC_BACKEND="$TMP/explicit-backend" ./build.sh >/dev/null 2>&1
grep -q '^explicit-backend --backend ' "$LOG"
if grep -q '^weavec1 ' "$LOG"; then
  echo 'build-boundary: seed backend ran despite explicit override' >&2
  exit 1
fi

printf 'build-boundary: passed\n'
