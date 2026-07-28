#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

# =============================================================================
# weavec — self-hosted surface-Weave compiler
# =============================================================================
#
# Normal Linux x86-64 builds consume published weavec1 and weavec-bootstrap
# SDKs. macOS and unsupported hosts use pinned source fallbacks.
#
# Environment overrides:
#
#   WEAVEC1_SDK=/path/to/extracted/sdk
#   WEAVEC1_VERSION=v0.3.1
#   WEAVEC1_LIBC=glibc|musl
#   WEAVEC1=/path/to/source
#   WEAVEC1_TAG=v0.3.1
#
#   WEAVEC_BOOTSTRAP_SDK=/path/to/extracted/sdk
#   WEAVEC_BOOTSTRAP_VERSION=v0.3.0
#   WEAVEC_BOOTSTRAP_LIBC=glibc|musl
#   WEAVEC_BOOTSTRAP=/path/to/source
#   WEAVEC_BOOTSTRAP_REF=v0.3.0
#
#   WEAVEC_BACKEND=/path/to/self-hosted/weavec
#   WEAVEC_VERSION_OVERRIDE=v0.3.0
# =============================================================================

WEAVEC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$WEAVEC_DIR/build"
VENDOR_DIR="$BUILD_DIR/vendor"
DOWNLOAD_DIR="$BUILD_DIR/downloads"

# shellcheck source=scripts/weavec-version.sh
source "$WEAVEC_DIR/scripts/weavec-version.sh"
WEAVEC_VERSION="$(weavec_version_string "$WEAVEC_DIR")"

WEAVEC0_TAG="${WEAVEC0_TAG:-v0.4.0}"
WEAVEC0_REPO="https://github.com/ahojukka5/weavec0.git"

WEAVEC1_VERSION="${WEAVEC1_VERSION:-v0.3.1}"
WEAVEC1_TAG="${WEAVEC1_TAG:-$WEAVEC1_VERSION}"
WEAVEC1_LIBC="${WEAVEC1_LIBC:-glibc}"
WEAVEC1_RELEASE_BASE="${WEAVEC1_RELEASE_BASE:-https://github.com/ahojukka5/weavec1/releases/download}"
WEAVEC1_REPO="https://github.com/ahojukka5/weavec1.git"

WEAVEC_BOOTSTRAP_VERSION="${WEAVEC_BOOTSTRAP_VERSION:-v0.3.0}"
WEAVEC_BOOTSTRAP_REF="${WEAVEC_BOOTSTRAP_REF:-$WEAVEC_BOOTSTRAP_VERSION}"
WEAVEC_BOOTSTRAP_LIBC="${WEAVEC_BOOTSTRAP_LIBC:-$WEAVEC1_LIBC}"
WEAVEC_BOOTSTRAP_RELEASE_BASE="${WEAVEC_BOOTSTRAP_RELEASE_BASE:-https://github.com/ahojukka5/weavec-bootstrap/releases/download}"
WEAVEC_BOOTSTRAP_REPO="https://github.com/ahojukka5/weavec-bootstrap.git"

WEAVEC0_DIR=""
WEAVEC1_MODE=""
WEAVEC1_DIR=""
WEAVEC1_SDK_DIR=""
WEAVEC1_BIN=""
WEAVEC_BOOTSTRAP_MODE=""
WEAVEC_BOOTSTRAP_DIR=""
WEAVEC_BOOTSTRAP_SDK_DIR=""
WEAVEC_BOOTSTRAP_BIN=""
WEAVEC_BOOTSTRAP_CAT=""
WEAVE_SEXPR_LIBRARY=""

log()  { printf '[weavec] %s\n' "$*" >&2; }
fail() { printf '[weavec] error: %s\n' "$*" >&2; exit 1; }
require_tool() {
  command -v "$1" >/dev/null 2>&1 || fail "required tool not found: $1"
}

host_has_linux_sdk() {
  [[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]]
}

validate_libc() {
  case "$1" in
    glibc|musl) ;;
    *) fail "unsupported libc: $1 (expected glibc or musl)" ;;
  esac
}

verify_and_extract() {
  local release_base="$1"
  local version="$2"
  local archive="$3"
  local archive_path="$4"
  local sums_path="$5"
  local destination="$6"

  require_tool curl
  require_tool sha256sum
  require_tool tar
  mkdir -p "$DOWNLOAD_DIR" "$destination"

  curl --fail --location --retry 3 --output "$archive_path" \
    "$release_base/$version/$archive"
  curl --fail --location --retry 3 --output "$sums_path" \
    "$release_base/$version/SHA256SUMS"

  local expected
  expected="$(awk -v name="$archive" '$2 == name { print $1; exit }' \
    "$sums_path")"
  [[ -n "$expected" ]] || fail "checksum not found for $archive"
  printf '%s  %s\n' "$expected" "$archive_path" | sha256sum --check -

  tar -C "$destination" -xzf "$archive_path"
}

checkout_ref() {
  local repo="$1"
  local ref="$2"
  local dir="$3"
  require_tool git

  if [[ ! -d "$dir/.git" ]]; then
    mkdir -p "$(dirname "$dir")"
    git clone --filter=blob:none --no-checkout "$repo" "$dir"
  fi
  git -C "$dir" fetch --depth 1 origin "$ref"
  git -C "$dir" checkout --detach --force FETCH_HEAD
}

validate_weavec1_sdk() {
  local sdk="$1"
  [[ -x "$sdk/bin/weavec1" ]] || \
    fail "weavec1 SDK compiler missing: $sdk/bin/weavec1"
  WEAVEC1_MODE=sdk
  WEAVEC1_SDK_DIR="$sdk"
  WEAVEC1_BIN="$sdk/bin/weavec1"
}

download_weavec1_sdk() {
  validate_libc "$WEAVEC1_LIBC"
  local package="weavec1-${WEAVEC1_VERSION}-linux-x86_64-${WEAVEC1_LIBC}"
  local archive="$package.tar.gz"
  local root="$VENDOR_DIR/weavec1-sdk"
  local sdk="$root/$package"

  if [[ ! -d "$sdk" ]]; then
    log "downloading weavec1 SDK $WEAVEC1_VERSION ($WEAVEC1_LIBC)"
    rm -rf "$sdk"
    verify_and_extract \
      "$WEAVEC1_RELEASE_BASE" \
      "$WEAVEC1_VERSION" \
      "$archive" \
      "$DOWNLOAD_DIR/$archive" \
      "$DOWNLOAD_DIR/weavec1-${WEAVEC1_VERSION}-SHA256SUMS" \
      "$root"
  else
    log "using cached weavec1 SDK: $sdk"
  fi
  validate_weavec1_sdk "$sdk"
}

ensure_weavec0_source() {
  require_tool git
  if [[ -n "${WEAVEC0:-}" ]]; then
    WEAVEC0_DIR="$WEAVEC0"
    log "using WEAVEC0 source tree: $WEAVEC0_DIR"
  else
    WEAVEC0_DIR="$VENDOR_DIR/weavec0-source"
    if [[ ! -d "$WEAVEC0_DIR/.git" ]]; then
      log "fetching weavec0 source fallback $WEAVEC0_TAG"
      git clone --depth 1 --branch "$WEAVEC0_TAG" "$WEAVEC0_REPO" \
        "$WEAVEC0_DIR"
    fi
  fi

  [[ -x "$WEAVEC0_DIR/build.sh" ]] || \
    fail "weavec0 build.sh missing: $WEAVEC0_DIR/build.sh"
  if [[ ! -x "$WEAVEC0_DIR/weavec0" ]] || \
     [[ ! -d "$WEAVEC0_DIR/build/bootstrap-tests/bc" ]]; then
    log "building weavec0 source fallback"
    (cd "$WEAVEC0_DIR" && ./build.sh) || fail "weavec0 build failed"
  fi
}

ensure_weavec1_source() {
  ensure_weavec0_source
  require_tool git

  if [[ -n "${WEAVEC1:-}" ]]; then
    WEAVEC1_DIR="$WEAVEC1"
    log "using WEAVEC1 source tree: $WEAVEC1_DIR"
  else
    WEAVEC1_DIR="$VENDOR_DIR/weavec1-source"
    if [[ ! -d "$WEAVEC1_DIR/.git" ]]; then
      log "fetching weavec1 source fallback $WEAVEC1_TAG"
      git clone --depth 1 --branch "$WEAVEC1_TAG" "$WEAVEC1_REPO" \
        "$WEAVEC1_DIR"
    fi
  fi

  [[ -x "$WEAVEC1_DIR/build.sh" ]] || \
    fail "weavec1 build.sh missing: $WEAVEC1_DIR/build.sh"
  WEAVEC1_BIN="$WEAVEC1_DIR/build/weavec1"
  if [[ ! -x "$WEAVEC1_BIN" ]]; then
    log "building weavec1 source fallback"
    (cd "$WEAVEC1_DIR" && WEAVEC0="$WEAVEC0_DIR" ./build.sh) \
      || fail "weavec1 build failed"
  fi
  [[ -x "$WEAVEC1_BIN" ]] || fail "weavec1 compiler missing: $WEAVEC1_BIN"
  WEAVEC1_MODE=source
}

ensure_weavec1() {
  if [[ -n "${WEAVEC1_SDK:-}" ]]; then
    log "using WEAVEC1_SDK: $WEAVEC1_SDK"
    validate_weavec1_sdk "$WEAVEC1_SDK"
  elif [[ -n "${WEAVEC1:-}" ]]; then
    ensure_weavec1_source
  elif host_has_linux_sdk; then
    download_weavec1_sdk
  else
    log "no weavec1 SDK for $(uname -s)/$(uname -m); using source fallback"
    ensure_weavec1_source
  fi
}

validate_bootstrap_sdk() {
  local sdk="$1"
  [[ -x "$sdk/bin/weavec-bootstrap" ]] || \
    fail "bootstrap SDK compiler missing: $sdk/bin/weavec-bootstrap"
  [[ -x "$sdk/bin/weavec-bootstrap-cat" ]] || \
    fail "bootstrap SDK multifile driver missing: $sdk/bin/weavec-bootstrap-cat"
  [[ -s "$sdk/lib/libweave-sexpr.bc" ]] || \
    fail "bootstrap SDK parser library missing: $sdk/lib/libweave-sexpr.bc"

  WEAVEC_BOOTSTRAP_MODE=sdk
  WEAVEC_BOOTSTRAP_SDK_DIR="$sdk"
  WEAVEC_BOOTSTRAP_BIN="$sdk/bin/weavec-bootstrap"
  WEAVEC_BOOTSTRAP_CAT="$sdk/bin/weavec-bootstrap-cat"
  WEAVE_SEXPR_LIBRARY="$sdk/lib/libweave-sexpr.bc"
}

download_bootstrap_sdk() {
  validate_libc "$WEAVEC_BOOTSTRAP_LIBC"
  local package="weavec-bootstrap-${WEAVEC_BOOTSTRAP_VERSION}-linux-x86_64-${WEAVEC_BOOTSTRAP_LIBC}"
  local archive="$package.tar.gz"
  local root="$VENDOR_DIR/weavec-bootstrap-sdk"
  local sdk="$root/$package"

  if [[ ! -d "$sdk" ]]; then
    log "downloading weavec-bootstrap SDK $WEAVEC_BOOTSTRAP_VERSION ($WEAVEC_BOOTSTRAP_LIBC)"
    rm -rf "$sdk"
    verify_and_extract \
      "$WEAVEC_BOOTSTRAP_RELEASE_BASE" \
      "$WEAVEC_BOOTSTRAP_VERSION" \
      "$archive" \
      "$DOWNLOAD_DIR/$archive" \
      "$DOWNLOAD_DIR/weavec-bootstrap-${WEAVEC_BOOTSTRAP_VERSION}-SHA256SUMS" \
      "$root"
  else
    log "using cached weavec-bootstrap SDK: $sdk"
  fi
  validate_bootstrap_sdk "$sdk"
}

ensure_bootstrap_source() {
  local vendored=0
  if [[ -n "${WEAVEC_BOOTSTRAP:-}" ]]; then
    WEAVEC_BOOTSTRAP_DIR="$WEAVEC_BOOTSTRAP"
    log "using WEAVEC_BOOTSTRAP source tree: $WEAVEC_BOOTSTRAP_DIR"
  else
    vendored=1
    WEAVEC_BOOTSTRAP_DIR="$VENDOR_DIR/weavec-bootstrap-source"
    log "fetching weavec-bootstrap source fallback $WEAVEC_BOOTSTRAP_REF"
    checkout_ref "$WEAVEC_BOOTSTRAP_REPO" "$WEAVEC_BOOTSTRAP_REF" \
      "$WEAVEC_BOOTSTRAP_DIR"
  fi

  [[ -x "$WEAVEC_BOOTSTRAP_DIR/build.sh" ]] || \
    fail "weavec-bootstrap build.sh missing: $WEAVEC_BOOTSTRAP_DIR/build.sh"
  [[ -x "$WEAVEC_BOOTSTRAP_DIR/weavec-bootstrap-cat.sh" ]] || \
    fail "weavec-bootstrap multifile driver missing"

  WEAVEC_BOOTSTRAP_BIN="$WEAVEC_BOOTSTRAP_DIR/build/weavec-bootstrap"
  WEAVEC_BOOTSTRAP_CAT="$WEAVEC_BOOTSTRAP_DIR/weavec-bootstrap-cat.sh"
  WEAVE_SEXPR_LIBRARY="$WEAVEC_BOOTSTRAP_DIR/build/libweave-sexpr.bc"

  local ref_file="$WEAVEC_BOOTSTRAP_DIR/build/.source-ref"
  local source_ref=local
  local built_ref=""
  local rebuild=0
  if (( vendored )); then
    source_ref="$(git -C "$WEAVEC_BOOTSTRAP_DIR" rev-parse HEAD)"
    [[ -f "$ref_file" ]] && built_ref="$(cat "$ref_file")"
  fi
  if [[ ! -x "$WEAVEC_BOOTSTRAP_BIN" ]] || \
     [[ ! -s "$WEAVE_SEXPR_LIBRARY" ]] || \
     { (( vendored )) && [[ "$built_ref" != "$source_ref" ]]; }; then
    rebuild=1
  fi

  if (( rebuild )); then
    rm -f "$WEAVEC_BOOTSTRAP_BIN" "$WEAVE_SEXPR_LIBRARY"
    log "building weavec-bootstrap source fallback"
    if [[ "$WEAVEC1_MODE" == sdk ]]; then
      (cd "$WEAVEC_BOOTSTRAP_DIR" && \
        WEAVEC1_SDK="$WEAVEC1_SDK_DIR" ./build.sh) \
        || fail "weavec-bootstrap build failed"
    else
      (cd "$WEAVEC_BOOTSTRAP_DIR" && \
        WEAVEC0="$WEAVEC0_DIR" WEAVEC1="$WEAVEC1_DIR" ./build.sh) \
        || fail "weavec-bootstrap build failed"
    fi
    if (( vendored )); then
      printf '%s\n' "$source_ref" > "$ref_file"
    fi
  fi

  [[ -x "$WEAVEC_BOOTSTRAP_BIN" ]] || \
    fail "weavec-bootstrap compiler missing: $WEAVEC_BOOTSTRAP_BIN"
  [[ -s "$WEAVE_SEXPR_LIBRARY" ]] || \
    fail "weavec-bootstrap parser library missing: $WEAVE_SEXPR_LIBRARY"
  WEAVEC_BOOTSTRAP_MODE=source
}

ensure_weavec_bootstrap() {
  if [[ -n "${WEAVEC_BOOTSTRAP_SDK:-}" ]]; then
    log "using WEAVEC_BOOTSTRAP_SDK: $WEAVEC_BOOTSTRAP_SDK"
    validate_bootstrap_sdk "$WEAVEC_BOOTSTRAP_SDK"
  elif [[ -n "${WEAVEC_BOOTSTRAP:-}" ]]; then
    ensure_bootstrap_source
  elif host_has_linux_sdk; then
    download_bootstrap_sdk
  else
    log "no bootstrap SDK for $(uname -s)/$(uname -m); using source fallback"
    ensure_bootstrap_source
  fi
}

# Source ordering is part of the deterministic bootstrap contract.
SOURCES=(
  src/core/extern.weave
  src/core/io.weave
  src/core/util.weave
  src/core/trace_registry.weave
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
  src/llvm/stmt.weave
  src/llvm/fn.weave
  src/llvm/module.weave
  src/main.weave
)

build_weavec() {
  mkdir -p "$BUILD_DIR"

  local version_ll="$BUILD_DIR/weavec-version.ll"
  local version_bc="$BUILD_DIR/weavec-version.bc"
  weavec_write_version_llvm "$WEAVEC_VERSION" "$version_ll"
  llvm-as "$version_ll" -o "$version_bc" \
    || fail "failed to assemble compiler version module"

  log "lowering compiler sources to WIR"
  : > "$BUILD_DIR/weavec.wir"
  WEAVEC_BOOTSTRAP="$WEAVEC_BOOTSTRAP_BIN" \
    "$WEAVEC_BOOTSTRAP_CAT" \
    "$BUILD_DIR/weavec.wir" "${SOURCES[@]}" \
    || fail "weavec-bootstrap multifile lowering failed"
  chmod u+rw "$BUILD_DIR/weavec.wir" 2>/dev/null || true

  log "compiling WIR to LLVM IR"
  if [[ -n "${WEAVEC_BACKEND:-}" ]]; then
    [[ -x "$WEAVEC_BACKEND" ]] || \
      fail "WEAVEC_BACKEND is not executable: $WEAVEC_BACKEND"
    log "using explicit WEAVEC_BACKEND=$WEAVEC_BACKEND"
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
    "$version_bc" \
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
  require_tool awk
  require_tool clang
  require_tool llvm-as
  require_tool llvm-link
  require_tool python3
  ensure_weavec1
  ensure_weavec_bootstrap
  build_weavec
  log "compiler version: $WEAVEC_VERSION"
  log "dependency modes: weavec1=$WEAVEC1_MODE bootstrap=$WEAVEC_BOOTSTRAP_MODE"
  log "build complete: $BUILD_DIR/weavec"
}

main "$@"
