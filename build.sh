#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

# =============================================================================
# weavec2 — surface-Weave compiler, build script
# =============================================================================
#
# weavec2 is the surface-Weave compiler, written in surface Weave itself.
# Bootstrapping it requires the rest of the chain:
#
#   weavec0     hand-written LLVM-IR seed compiler  (runtime.c)
#   weavec1     WIR-written compiler                (compiles weavec2.wir → .ll)
#   weavefront  surface → WIR frontend              (compiles src/**/*.weave → .wir,
#                                                    plus sexpr_*.ll runtime modules
#                                                    that the resulting weavec2
#                                                    binary links against)
#
# Pipeline:
#
#   1. Acquire each dependency. Honour the WEAVEC0 / WEAVEC1 / WEAVEFRONT
#      env vars (paths to pre-built source trees), or clone the pinned
#      $WEAVEC0_TAG / $WEAVEC1_TAG / $WEAVEFRONT_TAG from upstream into
#      build/vendor/. weavec1 is built with WEAVEC0 pre-set to avoid a
#      double-fetch; weavefront is built with both WEAVEC0 and WEAVEC1
#      pre-set.
#
#   2. Concatenate src/**/*.weave into build/weavec2.wir via
#      weavefront-cat.sh (strips the (program ...) wrapper of each
#      source and re-emits a single combined program).
#
#   3. Compile build/weavec2.wir → build/weavec2.ll with weavec1.
#
#   4. Link with weavefront's parser runtime modules (sexpr_tokens,
#      sexpr_tree, sexpr_lexer, sexpr_parser) and weavec0's runtime.c
#      into the weavec2 binary.
#
# Environment:
#
#   WEAVEC0 / WEAVEC0_TAG       (default tag: v0.2.0)
#   WEAVEC1 / WEAVEC1_TAG       (default tag: v0.1.0)
#   WEAVEFRONT / WEAVEFRONT_TAG (default tag: v0.1.0)
#   WEAVEC2_BACKEND              optional path to a self-hosted weavec2 binary;
#                                when set, WIR → LLVM uses --backend instead of weavec1.
#                                If unset and build/selfhost/stage2/weavec2 exists, that
#                                binary is auto-selected (weavec1 miscompiles guarded tree
#                                walks in the combined frontend module).
# =============================================================================

WEAVEC2_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$WEAVEC2_DIR/build"
VENDOR_DIR="$BUILD_DIR/vendor"

WEAVEC0_TAG="${WEAVEC0_TAG:-v0.2.0}"
WEAVEC0_REPO="https://github.com/ahojukka5/weavec0.git"

WEAVEC1_TAG="${WEAVEC1_TAG:-v0.1.0}"
WEAVEC1_REPO="https://github.com/ahojukka5/weavec1.git"

WEAVEFRONT_TAG="${WEAVEFRONT_TAG:-v0.1.0}"
WEAVEFRONT_REPO="https://github.com/ahojukka5/weavefront.git"

WEAVEC0_DIR=""
WEAVEC1_DIR=""
WEAVEFRONT_DIR=""
WEAVEC1_BIN=""
WEAVEFRONT_BIN=""
WEAVEFRONT_BUILD=""        # sexpr_*.ll runtime modules live here
RUNTIME_C=""

log()  { printf '[weavec2] %s\n' "$*" >&2; }
fail() { printf '[weavec2] error: %s\n' "$*" >&2; exit 1; }
require_tool() { command -v "$1" >/dev/null 2>&1 || fail "required tool not found: $1"; }

ensure_weavec0() {
  if [[ -n "${WEAVEC0:-}" ]]; then
    WEAVEC0_DIR="$WEAVEC0"
    log "using WEAVEC0 from env: $WEAVEC0_DIR"
  else
    WEAVEC0_DIR="$VENDOR_DIR/weavec0"
    if [[ ! -d "$WEAVEC0_DIR/.git" ]]; then
      log "fetching weavec0 $WEAVEC0_TAG from $WEAVEC0_REPO"
      mkdir -p "$(dirname "$WEAVEC0_DIR")"
      git clone --depth 1 --branch "$WEAVEC0_TAG" "$WEAVEC0_REPO" "$WEAVEC0_DIR"
    fi
  fi

  [[ -d "$WEAVEC0_DIR" ]] || fail "weavec0 source dir not found: $WEAVEC0_DIR"
  [[ -x "$WEAVEC0_DIR/build.sh" ]] || fail "weavec0 build.sh not found at $WEAVEC0_DIR/build.sh"

  if [[ ! -x "$WEAVEC0_DIR/weavec0" ]] || [[ ! -d "$WEAVEC0_DIR/build/bootstrap-tests/bc" ]]; then
    log "building weavec0 ($WEAVEC0_DIR)"
    ( cd "$WEAVEC0_DIR" && ./build.sh ) || fail "weavec0 build failed"
  fi

  RUNTIME_C="$WEAVEC0_DIR/runtime.c"
  [[ -f "$RUNTIME_C" ]] || fail "weavec0 runtime.c not found at $RUNTIME_C"
}

ensure_weavec1() {
  if [[ -n "${WEAVEC1:-}" ]]; then
    WEAVEC1_DIR="$WEAVEC1"
    log "using WEAVEC1 from env: $WEAVEC1_DIR"
  else
    WEAVEC1_DIR="$VENDOR_DIR/weavec1"
    if [[ ! -d "$WEAVEC1_DIR/.git" ]]; then
      log "fetching weavec1 $WEAVEC1_TAG from $WEAVEC1_REPO"
      mkdir -p "$(dirname "$WEAVEC1_DIR")"
      git clone --depth 1 --branch "$WEAVEC1_TAG" "$WEAVEC1_REPO" "$WEAVEC1_DIR"
    fi
  fi

  [[ -d "$WEAVEC1_DIR" ]] || fail "weavec1 source dir not found: $WEAVEC1_DIR"
  [[ -x "$WEAVEC1_DIR/build.sh" ]] || fail "weavec1 build.sh not found at $WEAVEC1_DIR/build.sh"

  WEAVEC1_BIN="$WEAVEC1_DIR/build/weavec1"
  if [[ ! -x "$WEAVEC1_BIN" ]]; then
    log "building weavec1 ($WEAVEC1_DIR)"
    ( cd "$WEAVEC1_DIR" && WEAVEC0="$WEAVEC0_DIR" ./build.sh ) \
      || fail "weavec1 build failed"
  fi
  [[ -x "$WEAVEC1_BIN" ]] || fail "weavec1 binary not built at $WEAVEC1_BIN"
}

ensure_weavefront() {
  if [[ -n "${WEAVEFRONT:-}" ]]; then
    WEAVEFRONT_DIR="$WEAVEFRONT"
    log "using WEAVEFRONT from env: $WEAVEFRONT_DIR"
  else
    WEAVEFRONT_DIR="$VENDOR_DIR/weavefront"
    if [[ ! -d "$WEAVEFRONT_DIR/.git" ]]; then
      log "fetching weavefront $WEAVEFRONT_TAG from $WEAVEFRONT_REPO"
      mkdir -p "$(dirname "$WEAVEFRONT_DIR")"
      git clone --depth 1 --branch "$WEAVEFRONT_TAG" "$WEAVEFRONT_REPO" "$WEAVEFRONT_DIR"
    fi
  fi

  [[ -d "$WEAVEFRONT_DIR" ]] || fail "weavefront source dir not found: $WEAVEFRONT_DIR"
  [[ -x "$WEAVEFRONT_DIR/build.sh" ]] || fail "weavefront build.sh not found at $WEAVEFRONT_DIR/build.sh"

  # weavefront v0.1.0 overflows the default stack on weavec2's combined
  # surface; patch the vendor build script and rebuild when needed.
  "$WEAVEC2_DIR/scripts/patch-weavefront-stack.sh" "$WEAVEFRONT_DIR/build.sh"

  WEAVEFRONT_BIN="$WEAVEFRONT_DIR/build/weavefront"
  WEAVEFRONT_BUILD="$WEAVEFRONT_DIR/build"
  if [[ ! -x "$WEAVEFRONT_BIN" ]] || ! "$WEAVEC2_DIR/scripts/weavefront-has-stack-patch.sh" "$WEAVEFRONT_BIN"; then
    if [[ -x "$WEAVEFRONT_BIN" ]]; then
      log "rebuilding weavefront (stack-size link patch)"
      rm -f "$WEAVEFRONT_BIN"
    else
      log "building weavefront ($WEAVEFRONT_DIR)"
    fi
    ( cd "$WEAVEFRONT_DIR" && WEAVEC0="$WEAVEC0_DIR" WEAVEC1="$WEAVEC1_DIR" ./build.sh ) \
      || fail "weavefront build failed"
  fi
  [[ -x "$WEAVEFRONT_BIN" ]] || fail "weavefront binary not built at $WEAVEFRONT_BIN"

  # The weavec2 binary links against weavefront's parser runtime modules.
  for mod in sexpr_tokens.ll sexpr_tree.ll sexpr_lexer.ll sexpr_parser.ll; do
    [[ -f "$WEAVEFRONT_BUILD/$mod" ]] \
      || fail "weavefront runtime module missing: $WEAVEFRONT_BUILD/$mod"
  done
}

# Source ordering matches what weavefront-cat.sh expects: each file
# must be a (program ...) wrapper; the script strips wrappers and
# emits one combined program.
SOURCES=(
  # core: C runtime interface, I/O helpers, tree utilities
  src/core/extern.weave
  src/core/io.weave
  src/core/util.weave
  # frontend: surface Weave → WIR lowering
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
  # llvm: WIR → LLVM IR backend
  src/llvm/ctx.weave
  src/llvm/types.weave
  src/llvm/locals.weave
  src/llvm/strings.weave
  src/llvm/expr.weave
  src/llvm/loop-phi.weave
  src/llvm/stmt.weave
  src/llvm/fn.weave
  src/llvm/module.weave
  # entry point
  src/main.weave
)

build_weavec2() {
  mkdir -p "$BUILD_DIR"

  log "concatenating source files"
  : > "$BUILD_DIR/weavec2.wir"
  WEAVEFRONT="$WEAVEFRONT_BIN" "$WEAVEFRONT_DIR/weavefront-cat.sh" \
    "$BUILD_DIR/weavec2.wir" "${SOURCES[@]}" \
    || fail "weavefront-cat.sh failed"
  chmod u+rw "$BUILD_DIR/weavec2.wir" 2>/dev/null || true

  if [[ -z "${WEAVEC2_BACKEND:-}" && -x "$BUILD_DIR/selfhost/stage2/weavec2" ]]; then
    WEAVEC2_BACKEND="$BUILD_DIR/selfhost/stage2/weavec2"
    log "auto-selected WEAVEC2_BACKEND=$WEAVEC2_BACKEND"
  fi

  log "compiling WIR → LLVM IR"
  if [[ -n "${WEAVEC2_BACKEND:-}" ]]; then
    [[ -x "$WEAVEC2_BACKEND" ]] || fail "WEAVEC2_BACKEND is not executable: $WEAVEC2_BACKEND"
    log "using self-hosted backend: $WEAVEC2_BACKEND"
    "$WEAVEC2_BACKEND" --backend "$BUILD_DIR/weavec2.wir" "$BUILD_DIR/weavec2.ll" \
      || fail "weavec2 --backend failed to compile weavec2.wir"
  else
    "$WEAVEC1_BIN" "$BUILD_DIR/weavec2.wir" "$BUILD_DIR/weavec2.ll" \
      || fail "weavec1 failed to compile weavec2.wir"
  fi

  log "linking LLVM modules"
  llvm-link \
    "$BUILD_DIR/weavec2.ll" \
    "$WEAVEFRONT_BUILD/sexpr_tokens.ll" \
    "$WEAVEFRONT_BUILD/sexpr_tree.ll" \
    "$WEAVEFRONT_BUILD/sexpr_lexer.ll" \
    "$WEAVEFRONT_BUILD/sexpr_parser.ll" \
    -o "$BUILD_DIR/weavec2.bc" \
    || fail "llvm-link failed"

  log "compiling to executable"
  # runtime/portable.c provides weave_rt_open_write_trunc, which wraps
  # the POSIX open() call so we don't bake platform-specific flag
  # constants (macOS vs Linux) into the WIR source.
  # Combined surface lowering recurses deeply; default ~8 MiB stack overflows.
  local stack_size="0x1000000"
  if [[ "$(uname -s)" == "Darwin" ]]; then
    clang "$BUILD_DIR/weavec2.bc" "$WEAVEC2_DIR/runtime/portable.c" \
      -o "$BUILD_DIR/weavec2" \
      -Wl,-stack_size,"$stack_size" \
      || fail "clang failed"
  else
    clang "$BUILD_DIR/weavec2.bc" "$WEAVEC2_DIR/runtime/portable.c" \
      -o "$BUILD_DIR/weavec2" \
      -Wl,-z,stack-size="$stack_size" \
      || fail "clang failed"
  fi
}

main() {
  require_tool clang
  require_tool llvm-as
  require_tool llvm-link
  require_tool git
  ensure_weavec0
  ensure_weavec1
  ensure_weavefront
  build_weavec2
  log "build complete: $BUILD_DIR/weavec2"
}

main "$@"
