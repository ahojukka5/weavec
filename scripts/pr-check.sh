#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Light pull-request contracts. These checks are file-based and do not build
# the compiler or occupy the self-hosted ladder fleet. The compile-and-fast-suite
# gate is scripts/pr-compile.sh. The full ladder runs on master after merge.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log() {
  printf '[weavec-pr-check] %s\n' "$*"
}

log 'runtime implementation boundary'
python3 "$ROOT/scripts/check_runtime_boundary.py"

log 'WIR core-version audit'
python3 "$ROOT/scripts/check_wir_core_version.py"

log 'documentation WIR core-version claims'
python3 "$ROOT/scripts/check_doc_wir_versions.py"

log 'documentation links'
python3 "$ROOT/scripts/check_doc_links.py"

log 'WIR next source-location fixtures'
python3 "$ROOT/scripts/check_wir_next_source_locations.py"

log 'WIR next source-location views'
python3 "$ROOT/scripts/wir_next_source_views.py" self-test

log 'WIR next available source bytes'
python3 "$ROOT/scripts/check_wir_next_source_bytes.py"

log 'project manifest version 1'
python3 "$ROOT/scripts/check_project_manifest_spec.py"

log 'language testing contract'
python3 "$ROOT/scripts/check_testing_spec.py"

log 'surface conformance corpus completeness'
python3 "$ROOT/scripts/check_conformance_corpus.py"

log 'compiler source manifest'
bash "$ROOT/test/compiler-sources/test.sh"

log 'semantic-index contract'
bash "$ROOT/test/semantic-index-contract/test.sh"

log 'project protocol contract'
bash "$ROOT/test/project-protocol-contract/test.sh"

log 'development entrypoints'
bash "$ROOT/test/development-entrypoints/test.sh"

log 'PR compile gate script'
bash -n "$ROOT/scripts/pr-compile.sh"
[[ -x "$ROOT/scripts/pr-compile.sh" ]] || {
  printf 'pr-check: scripts/pr-compile.sh must be executable\n' >&2
  exit 1
}

log 'passed'
