#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

# Build only the final weavec compiler from published lower-stage SDKs.
# Rebuilding weavec0, weavec1, or weavec-bootstrap is intentionally outside this
# script and belongs to lower-stage release maintenance.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ "$(basename "$SCRIPT_DIR")" == scripts ]]; then
  WEAVEC_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
else
  # Compatibility with a root symlink or a copied test harness entrypoint.
  WEAVEC_DIR="$SCRIPT_DIR"
fi

BUILD_DIR="$WEAVEC_DIR/build"
VENDOR_DIR="$BUILD_DIR/vendor"
DOWNLOAD_DIR="$BUILD_DIR/downloads"

# shellcheck source=scripts/weavec-version.sh
source "$WEAVEC_DIR/scripts/weavec-version.sh"
# shellcheck source=scripts/compiler-sources.sh
source "$WEAVEC_DIR/scripts/compiler-sources.sh"
WEAVEC_VERSION="$(weavec_version_string "$WEAVEC_DIR")"

WEAVEC1_VERSION="${WEAVEC1_VERSION:-v0.3.2}"
WEAVEC1_LIBC="${WEAVEC1_LIBC:-glibc}"
WEAVEC1_RELEASE_BASE="${WEAVEC1_RELEASE_BASE:-https://github.com/ahojukka5/weavec1/releases/download}"

WEAVEC_BOOTSTRAP_VERSION="${WEAVEC_BOOTSTRAP_VERSION:-v0.3.1}"
WEAVEC_BOOTSTRAP_RELEASE_BASE="${WEAVEC_BOOTSTRAP_RELEASE_BASE:-https://github.com/ahojukka5/weavec-bootstrap/releases/download}"

WEAVEC1_SDK_DIR=""
WEAVEC1_BIN=""
WEAVEC_BOOTSTRAP_SDK_DIR=""
WEAVEC_BOOTSTRAP_BIN=""
WEAVEC_BOOTSTRAP_CAT=""
SDK_SUFFIX=""

log()  { printf '[weavec] %s\n' "$*" >&2; }
fail() { printf '[weavec] error: %s\n' "$*" >&2; exit 1; }

require_tool() {
  command -v "$1" >/dev/null 2>&1 || fail "required tool not found: $1"
}

resolve_sdk_suffix() {
  local system machine
  system="$(uname -s)"
  machine="$(uname -m)"

  case "$system:$machine" in
    Linux:x86_64)
      case "$WEAVEC1_LIBC" in
        glibc|musl) ;;
        *) fail "WEAVEC1_LIBC must be glibc or musl" ;;
      esac
      SDK_SUFFIX="linux-x86_64-$WEAVEC1_LIBC"
      ;;
    Darwin:arm64)
      SDK_SUFFIX="macos-arm64"
      ;;
    Darwin:x86_64)
      SDK_SUFFIX="macos-x86_64"
      ;;
    *)
      fail "no published lower-stage SDK contract for $system/$machine"
      ;;
  esac
}

sha256_file() {
  local path="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$path" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$path" | awk '{print $1}'
  else
    fail "required checksum tool not found: sha256sum or shasum"
  fi
}

fetch_sdk() {
  local component="$1"
  local version="$2"
  local release_base="$3"
  local package="$4"
  local vendor_root="$5"
  local archive="$package.tar.gz"
  local archive_path="$DOWNLOAD_DIR/$archive"
  local sums_path="$DOWNLOAD_DIR/$component-$version-SHA256SUMS"
  local sdk="$vendor_root/$package"

  if [[ -d "$sdk" ]]; then
    printf '%s\n' "$sdk"
    return
  fi

  require_tool curl
  require_tool tar
  mkdir -p "$DOWNLOAD_DIR" "$vendor_root"

  log "downloading $component SDK $version ($SDK_SUFFIX)"
  curl --fail --location --retry 3 --output "$archive_path" \
    "$release_base/$version/$archive" || \
    fail "published SDK asset is unavailable: $archive"
  curl --fail --location --retry 3 --output "$sums_path" \
    "$release_base/$version/SHA256SUMS" || \
    fail "published SDK checksums are unavailable for $component $version"

  local expected actual
  expected="$(awk -v name="$archive" '$2 == name { print $1; exit }' "$sums_path")"
  [[ -n "$expected" ]] || fail "checksum not found for $archive"
  actual="$(sha256_file "$archive_path")"
  [[ "$actual" == "$expected" ]] || \
    fail "checksum mismatch for $archive: expected $expected, got $actual"

  rm -rf "$sdk"
  tar -C "$vendor_root" -xzf "$archive_path"
  [[ -d "$sdk" ]] || fail "archive did not contain expected SDK root: $package"
  printf '%s\n' "$sdk"
}

validate_weavec1_sdk() {
  local sdk="$1"
  [[ -x "$sdk/bin/weavec1" ]] || \
    fail "weavec1 SDK compiler missing: $sdk/bin/weavec1"
  WEAVEC1_SDK_DIR="$sdk"
  WEAVEC1_BIN="$sdk/bin/weavec1"
}

validate_bootstrap_sdk() {
  local sdk="$1"
  [[ -x "$sdk/bin/weavec-bootstrap" ]] || \
    fail "bootstrap SDK compiler missing: $sdk/bin/weavec-bootstrap"
  [[ -x "$sdk/bin/weavec-bootstrap-cat" ]] || \
    fail "bootstrap SDK multifile driver missing: $sdk/bin/weavec-bootstrap-cat"

  WEAVEC_BOOTSTRAP_SDK_DIR="$sdk"
  WEAVEC_BOOTSTRAP_BIN="$sdk/bin/weavec-bootstrap"
  WEAVEC_BOOTSTRAP_CAT="$sdk/bin/weavec-bootstrap-cat"
}

ensure_weavec1_sdk() {
  local sdk package
  if [[ -n "${WEAVEC1_SDK:-}" ]]; then
    sdk="$WEAVEC1_SDK"
    log "using WEAVEC1_SDK: $sdk"
  else
    package="weavec1-$WEAVEC1_VERSION-$SDK_SUFFIX"
    sdk="$(fetch_sdk weavec1 "$WEAVEC1_VERSION" "$WEAVEC1_RELEASE_BASE" \
      "$package" "$VENDOR_DIR/weavec1-sdk")"
  fi
  validate_weavec1_sdk "$sdk"
}

ensure_bootstrap_sdk() {
  local sdk package
  if [[ -n "${WEAVEC_BOOTSTRAP_SDK:-}" ]]; then
    sdk="$WEAVEC_BOOTSTRAP_SDK"
    log "using WEAVEC_BOOTSTRAP_SDK: $sdk"
  else
    package="weavec-bootstrap-$WEAVEC_BOOTSTRAP_VERSION-$SDK_SUFFIX"
    sdk="$(fetch_sdk weavec-bootstrap "$WEAVEC_BOOTSTRAP_VERSION" \
      "$WEAVEC_BOOTSTRAP_RELEASE_BASE" "$package" \
      "$VENDOR_DIR/weavec-bootstrap-sdk")"
  fi
  validate_bootstrap_sdk "$sdk"
}

run_weavec1_backend() {
  local input="$1"
  local output="$2"

  if [[ "$(uname -s)" == Darwin ]]; then
    # Published weavec1 v0.3.2 recursively traverses the WIR tree. The current
    # self-hosted compiler is large enough to exhaust macOS's default 8 MiB
    # process stack, so raise only this bootstrap child process's soft limit.
    # The final weavec executable carries its own link-time stack size below.
    (
      ulimit -s 32768 || exit 125
      exec "$WEAVEC1_BIN" "$input" "$output"
    )
    return
  fi

  "$WEAVEC1_BIN" "$input" "$output"
}

weavec_load_compiler_sources "$WEAVEC_DIR"
SOURCES=("${WEAVEC_COMPILER_SOURCES[@]}")

build_weavec() {
  mkdir -p "$BUILD_DIR"

  local version_ll="$BUILD_DIR/weavec-version.ll"
  local version_bc="$BUILD_DIR/weavec-version.bc"
  weavec_write_version_llvm "$WEAVEC_VERSION" "$version_ll"
  llvm-as "$version_ll" -o "$version_bc" || \
    fail "failed to assemble compiler version module"

  log "lowering compiler sources to WIR"
  : > "$BUILD_DIR/weavec.wir"
  WEAVEC_BOOTSTRAP="$WEAVEC_BOOTSTRAP_BIN" \
    "$WEAVEC_BOOTSTRAP_CAT" \
    "$BUILD_DIR/weavec.wir" "${SOURCES[@]}" || \
    fail "weavec-bootstrap multifile lowering failed"
  chmod u+rw "$BUILD_DIR/weavec.wir" 2>/dev/null || true

  log "compiling WIR to LLVM IR"
  if [[ -n "${WEAVEC_BACKEND:-}" ]]; then
    [[ -x "$WEAVEC_BACKEND" ]] || \
      fail "WEAVEC_BACKEND is not executable: $WEAVEC_BACKEND"
    log "using explicit WEAVEC_BACKEND=$WEAVEC_BACKEND"
    "$WEAVEC_BACKEND" --backend "$BUILD_DIR/weavec.wir" \
      "$BUILD_DIR/weavec.ll" || \
      fail "self-hosted backend failed to compile weavec.wir"
  else
    run_weavec1_backend "$BUILD_DIR/weavec.wir" "$BUILD_DIR/weavec.ll" || \
      fail "weavec1 failed to compile weavec.wir"
  fi

  log "linking self-hosted compiler"
  llvm-link "$BUILD_DIR/weavec.ll" "$version_bc" \
    -o "$BUILD_DIR/weavec.bc" || fail "llvm-link failed"

  log "linking weavec executable"
  local stack_size="0x1000000"
  if [[ "$(uname -s)" == Darwin ]]; then
    clang "$BUILD_DIR/weavec.bc" "$WEAVEC_DIR/runtime/portable.c" \
      "$WEAVEC_DIR/runtime/formatter_driver.c" -o "$BUILD_DIR/weavec" \
      -Wl,-stack_size,"$stack_size" || fail "clang failed"
  else
    clang "$BUILD_DIR/weavec.bc" "$WEAVEC_DIR/runtime/portable.c" \
      "$WEAVEC_DIR/runtime/formatter_driver.c" -o "$BUILD_DIR/weavec" \
      -Wl,-z,stack-size="$stack_size" || fail "clang failed"
  fi
}

main() {
  require_tool awk
  require_tool clang
  require_tool llvm-as
  require_tool llvm-link
  require_tool python3
  resolve_sdk_suffix
  ensure_weavec1_sdk
  ensure_bootstrap_sdk
  build_weavec
  log "compiler version: $WEAVEC_VERSION"
  log "dependency mode: published SDKs ($SDK_SUFFIX)"
  log "build complete: $BUILD_DIR/weavec"
}

main "$@"
