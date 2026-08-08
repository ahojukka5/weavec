#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

required_sources=(
  src/protocol/host.weave
  src/protocol/json.weave
  src/protocol/project_host.weave
  src/protocol/project_phase.weave
  src/protocol/project.weave
  src/protocol/capabilities_registry.weave
  src/protocol/capabilities_surface.weave
  src/protocol/capabilities_forms.weave
  src/protocol/capabilities.weave
  src/protocol/build_manifest.weave
  src/protocol/diagnostics.weave
  src/protocol/trace.weave
)
for path in "${required_sources[@]}"; do
  [[ -f "$ROOT/$path" ]] || {
    printf 'protocol-boundary: missing Weave protocol source: %s\n' "$path" >&2
    exit 1
  }
  grep -qxF "$path" "$ROOT/compiler/sources.list" || {
    printf 'protocol-boundary: protocol source is not linked: %s\n' "$path" >&2
    exit 1
  }
done

obsolete_capability_files=(
  runtime/capabilities_json_types.inc
  runtime/capabilities_json_registry.inc
  runtime/capabilities_json_emit.inc
  runtime/capabilities_json_document.inc
)
for path in "${obsolete_capability_files[@]}"; do
  [[ ! -e "$ROOT/$path" ]] || {
    printf 'protocol-boundary: obsolete C capability policy remains: %s\n' "$path" >&2
    exit 1
  }
done

policy_free_c=(
  runtime/capabilities_json.c
  runtime/build_manifest_json.c
  runtime/diagnostics_json.c
  runtime/trace_runtime.c
)
protocol_literals=(
  weavec-capabilities-v1
  urn:weavec:schema:capabilities:v1
  weavec-build-manifest-v1
  weavec-diagnostics-v1
  weavec-compilation-trace-v1
  weave-surface-grammar-v1
  typed-surface-elaboration
  canonical-formatting
)
for path in "${policy_free_c[@]}"; do
  code="$(grep -Ev '^[[:space:]]*(//|/\*|\*)' "$ROOT/$path" || true)"
  for literal in "${protocol_literals[@]}"; do
    if grep -Fq "$literal" <<<"$code"; then
      printf 'protocol-boundary: public policy literal %s leaked into %s\n' \
        "$literal" "$path" >&2
      exit 1
    fi
  done
  if grep -Eq 'weave_json_key\([^,]+,[[:space:]]*"' <<<"$code"; then
    printf 'protocol-boundary: C serializer owns a public field in %s\n' "$path" >&2
    exit 1
  fi
done

# The native formatter may ask the self-hosted frontend whether a legacy cast
# spelling is admitted, but it must not carry a private capability registry.
if grep -Eq 'capabilities_json_(types|registry)\.inc|weave_cap_cast_pairs' \
    "$ROOT/runtime/formatter_driver.c" \
    "$ROOT/runtime/formatter_driver_types.inc"; then
  printf 'protocol-boundary: formatter retained C capability registry policy\n' >&2
  exit 1
fi
grep -Fq 'sop_cast_pair_supported' "$ROOT/runtime/formatter_driver_types.inc" || {
  printf 'protocol-boundary: formatter does not query self-hosted cast policy\n' >&2
  exit 1
}

# Project orchestration may expose raw facts and perform a temporary generic
# object merge for the pre-existing semantic-index serializer. It must not own
# the additive project field or format identifier itself.
project_code="$(grep -Ev '^[[:space:]]*(//|/\*|\*)' \
  "$ROOT/runtime/project_protocols.c" || true)"
if grep -Fq '"weavec-project-facts-v1"' <<<"$project_code" ||
   grep -Eq 'weave_json_key\([^,]+,[[:space:]]*"project"' <<<"$project_code"; then
  printf 'protocol-boundary: project protocol schema leaked back into C\n' >&2
  exit 1
fi

printf 'protocol-boundary: Weave owns public protocol policy\n'