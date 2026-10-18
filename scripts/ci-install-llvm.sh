#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# GitHub-hosted Ubuntu does not guarantee the full LLVM/musl development
# toolchain. Install it before the post-merge ladder or release jobs.
set -euo pipefail

if [[ "${RUNNER_OS:-Linux}" != Linux ]]; then
  echo "This toolchain setup supports GitHub-hosted Linux only" >&2
  exit 1
fi

sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  clang llvm musl-tools binutils file

# The distro's LLVM metapackage normally supplies unsuffixed commands.
# Fall back to matching versioned binaries without writing to /usr/local.
bin_dir="${RUNNER_TEMP:?}/weavec-llvm-tools"
mkdir -p "$bin_dir"
for tool in llvm-as llvm-link llvm-dis llc; do
  if command -v "$tool" >/dev/null 2>&1; then
    continue
  fi
  found=false
  for version in 20 19 18 17 16 15 14; do
    if command -v "${tool}-${version}" >/dev/null 2>&1; then
      ln -s "$(command -v "${tool}-${version}")" "$bin_dir/$tool"
      found=true
      break
    fi
  done
  if [[ "$found" != true ]]; then
    echo "Missing LLVM tool: $tool" >&2
    exit 1
  fi
done
echo "$bin_dir" >> "$GITHUB_PATH"

clang --version
musl-gcc --version
