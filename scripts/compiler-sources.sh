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
  local line line_number=0 path classification seen=$'\n'

  WEAVEC_COMPILER_SOURCES=()
  WEAVEC_NONLINKED_SOURCES=()

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

    classification=linked
    path="$line"
    case "$line" in
      !*)
        classification=nonlinked
        path="${line#!}"
        ;;
    esac

    case "$path" in
      src/*.weave) ;;
      *)
        weavec_compiler_sources_error \
          "$manifest:$line_number: expected relative src/*.weave path: $line"
        return 1
        ;;
    esac

    case "/$path/" in
      *'/../'*|*'/./'*|*'//'*)
        weavec_compiler_sources_error \
          "$manifest:$line_number: non-canonical source path: $line"
        return 1
        ;;
    esac

    case "$seen" in
      *$'\n'"$path"$'\n'*)
        weavec_compiler_sources_error \
          "$manifest:$line_number: duplicate source entry: $path"
        return 1
        ;;
    esac
    seen+="$path"$'\n'

    [[ -f "$root/$path" ]] || {
      weavec_compiler_sources_error \
        "$manifest:$line_number: source does not exist: $path"
      return 1
    }
    [[ ! -L "$root/$path" ]] || {
      weavec_compiler_sources_error \
        "$manifest:$line_number: compiler sources must not be symbolic links: $path"
      return 1
    }

    if [[ "$classification" == linked ]]; then
      WEAVEC_COMPILER_SOURCES+=("$path")
    else
      WEAVEC_NONLINKED_SOURCES+=("$path")
    fi
  done < "$manifest"

  if [[ "${#WEAVEC_COMPILER_SOURCES[@]}" -eq 0 ]]; then
    weavec_compiler_sources_error "$manifest: no linked compiler sources declared"
    return 1
  fi
}
