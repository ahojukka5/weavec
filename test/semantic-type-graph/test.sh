#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-semantic-type-graph-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

CC="${CC:-cc}"
"$CC" \
  -std=c11 \
  -Wall \
  -Wextra \
  -Werror \
  -pedantic \
  "$ROOT/test/semantic-type-graph/test.c" \
  -o "$TMP/semantic-type-graph-test"
"$TMP/semantic-type-graph-test"
