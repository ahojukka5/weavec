#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/test.c" <<'C'
#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include "json_writer.c"

// This unit owns native transactional publication only. The public manifest
// schema is Weave-owned and is validated through build/integration tests.
int weave_protocol_build_manifest_serialize(
    void *opaque,
    const char *status,
    const char *phase,
    const char *target,
    const char *compiler,
    const char *runtime,
    const char *optimizer,
    const char *codegen,
    const char *linker,
    const char *objdump,
    const char *optimization,
    const char *cpu,
    const char *tune_cpu,
    const char *output,
    char **sources,
    int source_count) {
    (void)phase;
    (void)target;
    (void)compiler;
    (void)runtime;
    (void)optimizer;
    (void)codegen;
    (void)linker;
    (void)objdump;
    (void)optimization;
    (void)cpu;
    (void)tune_cpu;
    (void)output;
    (void)sources;
    (void)source_count;
    if (status == NULL) return 1;
    weave_json_writer *writer = opaque;
    return weave_json_object_begin(writer) && weave_json_object_end(writer)
        ? 0 : 1;
}

#include "document_publish.c"
#include "build_manifest_json.c"

static char *read_all(const char *path) {
    FILE *stream = fopen(path, "rb");
    if (stream == NULL) {
        return NULL;
    }
    if (fseek(stream, 0, SEEK_END) != 0) {
        fclose(stream);
        return NULL;
    }
    long end = ftell(stream);
    if (end < 0 || fseek(stream, 0, SEEK_SET) != 0) {
        fclose(stream);
        return NULL;
    }
    char *data = malloc((size_t)end + 1);
    if (data == NULL) {
        fclose(stream);
        return NULL;
    }
    if (fread(data, 1, (size_t)end, stream) != (size_t)end) {
        free(data);
        fclose(stream);
        return NULL;
    }
    data[end] = '\0';
    fclose(stream);
    return data;
}

static void exercise_writer_mechanics(void) {
    FILE *stream = tmpfile();
    if (stream == NULL) abort();
    weave_json_writer writer;
    weave_json_writer_init_mode(&writer, stream, 0);
    if (!weave_json_object_begin(&writer) ||
        !weave_json_key(&writer, "text") ||
        !weave_json_string(&writer, "value") ||
        !weave_json_key(&writer, "nullable") ||
        !weave_json_nullable_string(&writer, NULL) ||
        !weave_json_key(&writer, "signed") ||
        !weave_json_int64(&writer, -1) ||
        !weave_json_key(&writer, "unsigned") ||
        !weave_json_uint64(&writer, 2) ||
        !weave_json_key(&writer, "trusted") ||
        !weave_json_trusted_value(
            &writer,
            (const unsigned char *)"false",
            5) ||
        !weave_json_key(&writer, "items") ||
        !weave_json_array_begin(&writer) ||
        !weave_json_array_end(&writer) ||
        !weave_json_object_end(&writer) ||
        !weave_json_writer_finish(&writer)) {
        abort();
    }
    fclose(stream);
}

int main(int argc, char **argv) {
    if (argc != 2) return 1;
    exercise_writer_mechanics();

    const char *path = argv[1];
    FILE *seed = fopen(path, "wb");
    if (seed == NULL || fputs("old\n", seed) == EOF || fclose(seed) != 0) {
        return 2;
    }

    char *sources[] = {"one.weave", "two.weave"};
    if (weave_build_manifest_write(
            path,
            NULL,
            "complete",
            "x86_64-unknown-linux-gnu",
            "/compiler/path",
            "/runtime/path",
            "clang",
            "llc",
            "clang",
            "llvm-objdump",
            "O3",
            "native",
            NULL,
            "program",
            sources,
            2) == 0) {
        return 3;
    }
    char *old = read_all(path);
    if (old == NULL || strcmp(old, "old\n") != 0) {
        free(old);
        return 4;
    }
    free(old);

    if (weave_build_manifest_write(
            path,
            "succeeded",
            "complete",
            "x86_64-unknown-linux-gnu",
            "/compiler/path",
            "/runtime/path",
            "clang",
            "llc",
            "clang",
            "llvm-objdump",
            "O3",
            "native",
            NULL,
            "program",
            sources,
            2) != 0) {
        return 5;
    }
    return 0;
}
C

cc -std=c11 -Wall -Wextra -Werror \
  -I"$ROOT/runtime" \
  "$WORK/test.c" -o "$WORK/test"

MANIFEST="$WORK/manifest.json"
"$WORK/test" "$MANIFEST"
python3 - <<'PY' "$MANIFEST"
import json
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    document = json.load(stream)
assert document == {}
PY

if compgen -G "$MANIFEST.tmp.*" >/dev/null; then
  printf 'manifest-publication: temporary file leaked\n' >&2
  exit 1
fi

printf 'manifest-publication: native transactional publication passed\n'
