#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

# =============================================================================
# weavec — self-hosted surface-Weave compiler
# =============================================================================
#
# Bootstrap chain:
#
#   weavec0            hand-written LLVM-IR seed compiler
#   weavec1            WIR-written backend compiler
#   weavec-bootstrap   surface Weave → WIR bootstrap frontend
#   weavec             final self-hosted compiler
#
# The bootstrap frontend exports one reusable parser library,
# build/libweave-sexpr.bc. This build consumes that named artifact rather than
# reaching into another repository for individual generated parser modules.
#
# Environment overrides:
#
#   WEAVEC0=/path/to/weavec0
#   WEAVEC0_TAG=v0.2.1
#   WEAVEC1=/path/to/weavec1
#   WEAVEC1_TAG=v0.2.0
#   WEAVEC_BOOTSTRAP=/path/to/weavec-bootstrap
#   WEAVEC_BOOTSTRAP_REF=<commit-or-tag>
#   WEAVEC_BACKEND=/path/to/self-hosted/weavec
# =============================================================================

WEAVEC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$WEAVEC_DIR/build"
VENDOR_DIR="$BUILD_DIR/vendor"

WEAVEC0_TAG="${WEAVEC0_TAG:-v0.2.1}"
WEAVEC0_REPO="https://github.com/ahojukka5/weavec0.git"

WEAVEC1_TAG="${WEAVEC1_TAG:-v0.2.0}"
WEAVEC1_REPO="https://github.com/ahojukka5/weavec1.git"

# Canonical bootstrap commit: final command names, one parser library, and the
# bootstrap frontend's 16 MiB stack requirement are owned upstream.
WEAVEC_BOOTSTRAP_REF="${WEAVEC_BOOTSTRAP_REF:-924dba10c8ac75657bd6fe65e9b1e54238f2bc80}"
WEAVEC_BOOTSTRAP_REPO="https://github.com/ahojukka5/weavec-bootstrap.git"

WEAVEC0_DIR=""
WEAVEC1_DIR=""
WEAVEC_BOOTSTRAP_DIR=""
WEAVEC1_BIN=""
WEAVEC_BOOTSTRAP_BIN=""
WEAVE_SEXPR_LIBRARY=""
RUNTIME_C=""

log()  { printf '[weavec] %s\n' "$*" >&2; }
fail() { printf '[weavec] error: %s\n' "$*" >&2; exit 1; }
require_tool() {
  command -v "$1" >/dev/null 2>&1 || fail "required tool not found: $1"
}

checkout_ref() {
  local repo="$1"
  local ref="$2"
  local dir="$3"

  if [[ ! -d "$dir/.git" ]]; then
    mkdir -p "$(dirname "$dir")"
    git clone --filter=blob:none --no-checkout "$repo" "$dir"
  fi

  git -C "$dir" fetch --depth 1 origin "$ref"
  git -C "$dir" checkout --detach --force FETCH_HEAD
}

ensure_weavec0() {
  if [[ -n "${WEAVEC0:-}" ]]; then
    WEAVEC0_DIR="$WEAVEC0"
    log "using WEAVEC0 source tree: $WEAVEC0_DIR"
  else
    WEAVEC0_DIR="$VENDOR_DIR/weavec0"
    if [[ ! -d "$WEAVEC0_DIR/.git" ]]; then
      log "fetching weavec0 $WEAVEC0_TAG"
      git clone --depth 1 --branch "$WEAVEC0_TAG" "$WEAVEC0_REPO" \
        "$WEAVEC0_DIR"
    fi
  fi

  [[ -x "$WEAVEC0_DIR/build.sh" ]] || \
    fail "weavec0 build.sh missing: $WEAVEC0_DIR/build.sh"
  if [[ ! -x "$WEAVEC0_DIR/weavec0" ]] || \
     [[ ! -d "$WEAVEC0_DIR/build/bootstrap-tests/bc" ]]; then
    log "building weavec0"
    (cd "$WEAVEC0_DIR" && ./build.sh) || fail "weavec0 build failed"
  fi

  RUNTIME_C="$WEAVEC0_DIR/runtime.c"
  [[ -f "$RUNTIME_C" ]] || fail "weavec0 runtime missing: $RUNTIME_C"
}

ensure_weavec1() {
  if [[ -n "${WEAVEC1:-}" ]]; then
    WEAVEC1_DIR="$WEAVEC1"
    log "using WEAVEC1 source tree: $WEAVEC1_DIR"
  else
    WEAVEC1_DIR="$VENDOR_DIR/weavec1"
    if [[ ! -d "$WEAVEC1_DIR/.git" ]]; then
      log "fetching weavec1 $WEAVEC1_TAG"
      git clone --depth 1 --branch "$WEAVEC1_TAG" "$WEAVEC1_REPO" \
        "$WEAVEC1_DIR"
    fi
  fi

  [[ -x "$WEAVEC1_DIR/build.sh" ]] || \
    fail "weavec1 build.sh missing: $WEAVEC1_DIR/build.sh"

  WEAVEC1_BIN="$WEAVEC1_DIR/build/weavec1"
  if [[ ! -x "$WEAVEC1_BIN" ]]; then
    log "building weavec1"
    (cd "$WEAVEC1_DIR" && WEAVEC0="$WEAVEC0_DIR" ./build.sh) \
      || fail "weavec1 build failed"
  fi
  [[ -x "$WEAVEC1_BIN" ]] || fail "weavec1 compiler missing: $WEAVEC1_BIN"
}

ensure_weavec_bootstrap() {
  local vendored=0
  if [[ -n "${WEAVEC_BOOTSTRAP:-}" ]]; then
    WEAVEC_BOOTSTRAP_DIR="$WEAVEC_BOOTSTRAP"
    log "using WEAVEC_BOOTSTRAP source tree: $WEAVEC_BOOTSTRAP_DIR"
  else
    vendored=1
    WEAVEC_BOOTSTRAP_DIR="$VENDOR_DIR/weavec-bootstrap"
    log "fetching weavec-bootstrap $WEAVEC_BOOTSTRAP_REF"
    checkout_ref "$WEAVEC_BOOTSTRAP_REPO" "$WEAVEC_BOOTSTRAP_REF" \
      "$WEAVEC_BOOTSTRAP_DIR"
  fi

  [[ -x "$WEAVEC_BOOTSTRAP_DIR/build.sh" ]] || \
    fail "weavec-bootstrap build.sh missing: $WEAVEC_BOOTSTRAP_DIR/build.sh"
  [[ -x "$WEAVEC_BOOTSTRAP_DIR/weavec-bootstrap-cat.sh" ]] || \
    fail "weavec-bootstrap multifile driver missing"

  WEAVEC_BOOTSTRAP_BIN="$WEAVEC_BOOTSTRAP_DIR/build/weavec-bootstrap"
  WEAVE_SEXPR_LIBRARY="$WEAVEC_BOOTSTRAP_DIR/build/libweave-sexpr.bc"

  local ref_file="$WEAVEC_BOOTSTRAP_DIR/build/.source-ref"
  local source_ref="local"
  local built_ref=""
  local rebuild=0

  if (( vendored )); then
    source_ref="$(git -C "$WEAVEC_BOOTSTRAP_DIR" rev-parse HEAD)"
    [[ -f "$ref_file" ]] && built_ref="$(cat "$ref_file")"
  else
    rebuild=1
  fi

  if [[ ! -x "$WEAVEC_BOOTSTRAP_BIN" ]] || \
     [[ ! -s "$WEAVE_SEXPR_LIBRARY" ]] || \
     [[ "$built_ref" != "$source_ref" ]]; then
    rebuild=1
  fi

  if (( rebuild )); then
    rm -f "$WEAVEC_BOOTSTRAP_BIN" "$WEAVE_SEXPR_LIBRARY"
    log "building weavec-bootstrap"
    (cd "$WEAVEC_BOOTSTRAP_DIR" && \
      WEAVEC0="$WEAVEC0_DIR" WEAVEC1="$WEAVEC1_DIR" ./build.sh) \
      || fail "weavec-bootstrap build failed"
    if (( vendored )); then
      printf '%s\n' "$source_ref" > "$ref_file"
    fi
  fi

  [[ -x "$WEAVEC_BOOTSTRAP_BIN" ]] || \
    fail "weavec-bootstrap compiler missing: $WEAVEC_BOOTSTRAP_BIN"
  [[ -s "$WEAVE_SEXPR_LIBRARY" ]] || \
    fail "weavec-bootstrap parser library missing: $WEAVE_SEXPR_LIBRARY"
}

# Source ordering is part of the deterministic bootstrap contract.
SOURCES=(
  src/core/extern.weave
  src/core/io.weave
  src/core/util.weave
  src/frontend/quantum_optimize.weave
  src/frontend/quantum_nativize.weave
  src/frontend/quantum_stats.weave
  src/frontend/emit.weave
  src/frontend/contract-lower.weave
  src/frontend/struct.weave
  src/frontend/lower.weave
  src/frontend/driver.weave
  src/frontend/explain-audit.weave
  src/frontend/contract-effects.weave
  src/frontend/audit-report.weave
  src/llvm/ctx.weave
  src/llvm/types.weave
  src/llvm/locals.weave
  src/llvm/strings.weave
  src/llvm/expr.weave
  src/llvm/loop-phi.weave
  src/llvm/stmt.weave
  src/llvm/fn.weave
  src/llvm/module.weave
  src/main.weave
)

build_weavec() {
  mkdir -p "$BUILD_DIR"

  log "lowering compiler sources to WIR"
  : > "$BUILD_DIR/weavec.wir"
  WEAVEC_BOOTSTRAP="$WEAVEC_BOOTSTRAP_BIN" \
    "$WEAVEC_BOOTSTRAP_DIR/weavec-bootstrap-cat.sh" \
    "$BUILD_DIR/weavec.wir" "${SOURCES[@]}" \
    || fail "weavec-bootstrap multifile lowering failed"
  chmod u+rw "$BUILD_DIR/weavec.wir" 2>/dev/null || true

  if [[ -z "${WEAVEC_BACKEND:-}" && \
        -x "$BUILD_DIR/selfhost/stage2/weavec" ]]; then
    WEAVEC_BACKEND="$BUILD_DIR/selfhost/stage2/weavec"
    log "auto-selected WEAVEC_BACKEND=$WEAVEC_BACKEND"
  fi

  log "compiling WIR to LLVM IR"
  if [[ -n "${WEAVEC_BACKEND:-}" ]]; then
    [[ -x "$WEAVEC_BACKEND" ]] || \
      fail "WEAVEC_BACKEND is not executable: $WEAVEC_BACKEND"
    "$WEAVEC_BACKEND" --backend "$BUILD_DIR/weavec.wir" \
      "$BUILD_DIR/weavec.ll" \
      || fail "self-hosted backend failed to compile weavec.wir"
  else
    "$WEAVEC1_BIN" "$BUILD_DIR/weavec.wir" "$BUILD_DIR/weavec.ll" \
      || fail "weavec1 failed to compile weavec.wir"
  fi

  log "linking compiler and parser library"
  llvm-link \
    "$BUILD_DIR/weavec.ll" \
    "$WEAVE_SEXPR_LIBRARY" \
    -o "$BUILD_DIR/weavec.bc" \
    || fail "llvm-link failed"

  log "linking weavec executable"
  local stack_size="0x1000000"
  if [[ "$(uname -s)" == Darwin ]]; then
    clang "$BUILD_DIR/weavec.bc" "$WEAVEC_DIR/runtime/portable.c" \
      -o "$BUILD_DIR/weavec" \
      -Wl,-stack_size,"$stack_size" \
      || fail "clang failed"
  else
    clang "$BUILD_DIR/weavec.bc" "$WEAVEC_DIR/runtime/portable.c" \
      -o "$BUILD_DIR/weavec" \
      -Wl,-z,stack-size="$stack_size" \
      || fail "clang failed"
  fi
}

main() {
  require_tool clang
  require_tool git
  require_tool llvm-as
  require_tool llvm-link
  ensure_weavec0
  ensure_weavec1
  ensure_weavec_bootstrap
  build_weavec
  log "build complete: $BUILD_DIR/weavec"
}

main "$@"
