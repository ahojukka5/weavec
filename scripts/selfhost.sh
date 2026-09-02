#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Build weavec with weavec itself.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ "$(basename "$SCRIPT_DIR")" == scripts ]]; then
  ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
else
  ROOT="$SCRIPT_DIR"
fi

SEED="$ROOT/build/weavec"
BUILD_DIR="$ROOT/build/selfhost"
VERSION_LL="$BUILD_DIR/weavec-version.ll"
VERSION_BC="$BUILD_DIR/weavec-version.bc"
SMOKE_SOURCE="$BUILD_DIR/selfhost-smoke.weave"

# shellcheck source=scripts/weavec-version.sh
source "$ROOT/scripts/weavec-version.sh"
# shellcheck source=scripts/compiler-sources.sh
source "$ROOT/scripts/compiler-sources.sh"
WEAVEC_VERSION="$(weavec_version_string "$ROOT")"

log() { printf '[weavec-selfhost] %s\n' "$*"; }
fail() { printf '[weavec-selfhost] error: %s\n' "$*" >&2; exit 1; }

require_tool() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required tool: $1"
}

ensure_recursive_stack() {
  local target_kib=32768
  local current_kib
  current_kib="$(ulimit -S -s)"
  if [[ "$current_kib" == unlimited ]]; then
    return 0
  fi
  if [[ "$current_kib" =~ ^[0-9]+$ ]] && (( current_kib < target_kib )); then
    ulimit -S -s "$target_kib" || \
      fail "cannot raise stack limit to ${target_kib} KiB for self-host compiler"
  fi
}

[[ -x "$SEED" ]] || \
  fail "seed compiler not found at $SEED; run scripts/build.sh first"
require_tool llvm-link
require_tool llvm-as
require_tool llvm-nm
require_tool clang

# Each self-host generation recursively traverses the full compiler program.
# Match the established large-WIR stack allowance used by bootstrap builds.
ensure_recursive_stack

chmod -R u+rw "$BUILD_DIR" 2>/dev/null || true
mkdir -p "$BUILD_DIR"
weavec_write_version_llvm "$WEAVEC_VERSION" "$VERSION_LL"
llvm-as "$VERSION_LL" -o "$VERSION_BC"

cat > "$SMOKE_SOURCE" <<'WEAVE'
(program
  (name "selfhost-smoke")
  (version "0.1")
  (entry main
    (params)
    (returns i32)
    (do (return 42))))
WEAVE

weavec_load_compiler_sources "$ROOT"
SOURCES=()
for source in "${WEAVEC_COMPILER_SOURCES[@]}"; do
  SOURCES+=("$ROOT/$source")
done

link_stage_binary() {
  local bc="$1"
  local out_bin="$2"
  local stack_size="0x1000000"
  local tmp_bin="$out_bin.tmp"
  local failed_bin="$out_bin.failed"
  local smoke_wir="$out_bin.smoke.wir"
  local smoke_stdout="$out_bin.smoke.stdout"
  local smoke_stderr="$out_bin.smoke.stderr"
  local version_output="$out_bin.version.txt"
  local version_status frontend_status actual_version

  rm -f \
    "$out_bin" "$tmp_bin" "$failed_bin" "$smoke_wir" \
    "$smoke_stdout" "$smoke_stderr" "$version_output"

  log "clang $out_bin"
  if [[ "$(uname -s)" == Darwin ]]; then
    clang "$bc" "$ROOT/runtime/portable.c" "$ROOT/runtime/formatter_driver.c" \
      -o "$tmp_bin" -Wl,-stack_size,"$stack_size"
  else
    clang "$bc" "$ROOT/runtime/portable.c" "$ROOT/runtime/formatter_driver.c" \
      -o "$tmp_bin" -Wl,-z,stack-size="$stack_size"
  fi

  set +e
  "$tmp_bin" --version >"$version_output" 2>"$smoke_stderr"
  version_status="$?"
  actual_version="$(cat "$version_output" 2>/dev/null)"
  "$tmp_bin" --frontend "$smoke_wir" "$SMOKE_SOURCE" \
    >"$smoke_stdout" 2>>"$smoke_stderr"
  frontend_status="$?"
  set -e

  if [[ "$version_status" -eq 0 && \
        "$actual_version" == "weavec $WEAVEC_VERSION" && \
        "$frontend_status" -eq 0 && -s "$smoke_wir" ]]; then
    mv "$tmp_bin" "$out_bin"
    rm -f "$smoke_wir" "$smoke_stdout" "$smoke_stderr" "$version_output"
    return 0
  fi

  mv "$tmp_bin" "$failed_bin"
  fail "linked compiler failed validation; retained $failed_bin, $version_output, $smoke_wir, $smoke_stdout, and $smoke_stderr"
}

build_stage() {
  local compiler="$1"
  local out_dir="$2"
  local out_bin="$out_dir/weavec"
  local backend_stdout="$out_dir/weavec.backend.stdout"
  local backend_stderr="$out_dir/weavec.backend.stderr"
  local backend_status

  mkdir -p "$out_dir"
  rm -f "$backend_stdout" "$backend_stderr"

  log "frontend $out_dir/weavec.wir"
  "$compiler" --frontend "$out_dir/weavec.wir" "${SOURCES[@]}"

  log "backend $out_dir/weavec.ll"
  set +e
  "$compiler" --backend "$out_dir/weavec.wir" "$out_dir/weavec.ll" \
    >"$backend_stdout" 2>"$backend_stderr"
  backend_status="$?"
  set -e
  if [[ "$backend_status" -ne 0 ]]; then
    cat "$backend_stdout"
    cat "$backend_stderr" >&2
    fail "stage backend failed with status $backend_status; retained $out_dir/weavec.wir, $backend_stdout, and $backend_stderr"
  fi
  rm -f "$backend_stdout" "$backend_stderr"

  log "link $out_dir/weavec.bc"
  llvm-link "$out_dir/weavec.ll" "$VERSION_BC" \
    -o "$out_dir/weavec.bc"

  link_stage_binary "$out_dir/weavec.bc" "$out_bin"
}

build_stage "$SEED" "$BUILD_DIR/stage1"
build_stage "$BUILD_DIR/stage1/weavec" "$BUILD_DIR/stage2"

log "verify stage1/stage2 fixed point"
if ! bash "$ROOT/scripts/verify-selfhost-fixed-point.sh" \
    "$BUILD_DIR/stage1" \
    "$BUILD_DIR/stage2" \
    "$BUILD_DIR/fixed-point"; then
  fail "self-host generations did not converge; inspect $BUILD_DIR/fixed-point"
fi

STAGE2="$BUILD_DIR/stage2/weavec"
STAGE2_TEST_DIR="$BUILD_DIR/stage2-tests"
rm -rf "$STAGE2_TEST_DIR"

log "stage2 full correctness suite"
WEAVEC="$STAGE2" \
WEAVEC_TEST_BUILD_DIR="$STAGE2_TEST_DIR/correctness" \
  bash "$ROOT/test.sh"

log "stage2 surface conformance corpus"
WEAVEC="$STAGE2" \
WEAVEC_RUNTIME="$ROOT/runtime/program.c" \
  bash "$ROOT/test/conformance/run.sh"

log "stage2 diagnostics protocol suite"
WEAVEC="$STAGE2" \
WEAVEC_RUNTIME="$ROOT/runtime/program.c" \
  bash "$ROOT/test/diagnostics/test-build-diagnostics.sh"

log "stage2 compilation-trace protocol suite"
WEAVEC="$STAGE2" \
WEAVEC_RUNTIME="$ROOT/runtime/program.c" \
  bash "$ROOT/test/trace/test.sh"

log "stage2 tooling-artifact protocol suite"
WEAVEC="$STAGE2" \
WEAVEC_RUNTIME="$ROOT/runtime/program.c" \
  bash "$ROOT/test/tooling-artifacts/test.sh"

log "compiler version: $WEAVEC_VERSION"
log "complete: $BUILD_DIR/stage2/weavec"
