#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Shared loader for the canonical ordered compiler source manifest.

weavec_compiler_sources_error() {
  printf 'weavec compiler sources: %s\n' "$*" >&2
  return 1
}

weavec_load_compiler_sources() {
  local root="$1"
  local manifest="${2:-$root/compiler/sources.list}"
  local line line_number=0 existing

  WEAVEC_COMPILER_SOURCES=()

  [[ -f "$manifest" ]] || {
    weavec_compiler_sources_error "manifest not found: $manifest"
    return 1
  }

  while IFS= read -r line || [[ -n "$line" ]]; do
    line_number=$((line_number + 1))
    line="${line%$'\r'}"
    case "$line" in
      ''|'#'*) continue ;;
    esac

    if [[ "$line" == *[[:space:]]* ]]; then
      weavec_compiler_sources_error \
        "$manifest:$line_number: whitespace is not allowed in source entries"
      return 1
    fi

    case "$line" in
      src/*.weave) ;;
      *)
        weavec_compiler_sources_error \
          "$manifest:$line_number: expected relative src/*.weave path: $line"
        return 1
        ;;
    esac

    case "/$line/" in
      *'/../'*|*'/./'*|*'//'*)
        weavec_compiler_sources_error \
          "$manifest:$line_number: non-canonical source path: $line"
        return 1
        ;;
    esac

    for existing in "${WEAVEC_COMPILER_SOURCES[@]}"; do
      if [[ "$existing" == "$line" ]]; then
        weavec_compiler_sources_error \
          "$manifest:$line_number: duplicate source entry: $line"
        return 1
      fi
    done

    [[ -f "$root/$line" ]] || {
      weavec_compiler_sources_error \
        "$manifest:$line_number: source does not exist: $line"
      return 1
    }
    [[ ! -L "$root/$line" ]] || {
      weavec_compiler_sources_error \
        "$manifest:$line_number: compiler sources must not be symbolic links: $line"
      return 1
    }

    WEAVEC_COMPILER_SOURCES+=("$line")
  done < "$manifest"

  if [[ "${#WEAVEC_COMPILER_SOURCES[@]}" -eq 0 ]]; then
    weavec_compiler_sources_error "$manifest: no compiler sources declared"
    return 1
  fi
}
