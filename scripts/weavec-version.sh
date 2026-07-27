#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

weavec_validate_version() {
  [[ "$1" =~ ^v[0-9]+\.[0-9]+\.[0-9]+([+-][0-9A-Za-z.-]+)?$ ]]
}

weavec_version_string() {
  local root="$1"
  local base sha exact dirty

  if [[ -n "${WEAVEC_VERSION_OVERRIDE:-}" ]]; then
    base="$WEAVEC_VERSION_OVERRIDE"
    [[ "$base" == v* ]] || base="v$base"
    weavec_validate_version "$base" || {
      printf 'invalid WEAVEC_VERSION_OVERRIDE: %s\n' \
        "$WEAVEC_VERSION_OVERRIDE" >&2
      return 1
    }
    printf '%s\n' "$base"
    return 0
  fi

  if [[ ! -r "$root/VERSION" ]]; then
    printf '%s\n' 'v0.0.0+unknown'
    return 0
  fi

  base="$(tr -d '[:space:]' < "$root/VERSION")"
  [[ "$base" == v* ]] || base="v$base"
  weavec_validate_version "$base" || {
    printf 'invalid VERSION file value: %s\n' "$base" >&2
    return 1
  }

  if ! command -v git >/dev/null 2>&1 || \
     ! git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf '%s\n' "$base"
    return 0
  fi

  sha="$(git -C "$root" rev-parse --short=12 HEAD)"
  exact="$(git -C "$root" describe --tags --exact-match HEAD 2>/dev/null || true)"
  dirty=""
  if [[ -n "$(git -C "$root" status --porcelain --untracked-files=no)" ]]; then
    dirty=".dirty"
  fi

  if [[ "$exact" == "$base" && -z "$dirty" ]]; then
    printf '%s\n' "$base"
  else
    printf '%s+git.%s%s\n' "$base" "$sha" "$dirty"
  fi
}

weavec_write_version_llvm() {
  local version="$1"
  local output="$2"
  local length

  weavec_validate_version "$version" || {
    printf 'cannot embed invalid weavec version: %s\n' "$version" >&2
    return 1
  }
  length=$((${#version} + 1))
  cat > "$output" <<EOF
; Generated compiler build identity. Do not edit.
@weave_compiler_version = constant [$length x i8] c"$version\00"
EOF
}
