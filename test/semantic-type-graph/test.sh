#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-semantic-type-graph-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

WEAVEC="$ROOT/build/weavec"
[[ -x "$WEAVEC" ]] || {
  printf 'semantic-type-graph: build/weavec is required\n' >&2
  exit 1
}

# Guard architecture as well as behavior. These C files may retain the opaque
# process-state cell and raw storage bridge, but no type-system implementation.
if grep -Eq 'weave_type_(graph|node|kind)|weave_semantic_type_(primitive|display|wir)|weave_semantic_types_compatible' \
    "$ROOT/runtime/semantic_type_graph.c" \
    "$ROOT/runtime/semantic_surface_types.c"; then
  printf 'semantic-type-graph: language-level type semantics leaked into runtime C\n' >&2
  exit 1
fi

"$WEAVEC" build \
  "$ROOT/src/types/graph_support.weave" \
  "$ROOT/src/types/graph_storage.weave" \
  "$ROOT/src/types/graph_metadata.weave" \
  "$ROOT/src/types/graph_identity.weave" \
  "$ROOT/src/types/graph_application.weave" \
  "$ROOT/src/types/graph_function.weave" \
  "$ROOT/src/types/graph_variant.weave" \
  "$ROOT/src/types/graph_qualifier.weave" \
  "$ROOT/src/types/graph_query.weave" \
  "$ROOT/test/semantic-type-graph/fixture.weave" \
  "$ROOT/test/semantic-type-graph/main.weave" \
  -o "$TMP/semantic-type-graph-test"

"$TMP/semantic-type-graph-test"

printf 'semantic-type-graph: self-hosted Weave implementation passed\n'
