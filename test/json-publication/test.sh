#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/test.c" <<EOF
#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
#include "$ROOT/runtime/json_writer.c"
#include "$ROOT/runtime/document_publish.c"

typedef struct sample_document {
    int fail;
} sample_document;

static int serialize_sample(
    weave_json_writer *writer,
    const void *opaque) {
    const sample_document *document = opaque;
    if (!weave_json_object_begin(writer) ||
        !weave_json_key(writer, "text") ||
        !weave_json_string(writer, "a\n\t\"\\\001") ||
        !weave_json_key(writer, "items") ||
        !weave_json_array_begin(writer) ||
        !weave_json_int64(writer, -3) ||
        !weave_json_uint64(writer, 42) ||
        !weave_json_nullable_string(writer, NULL) ||
        !weave_json_trusted_value(
            writer,
            (const unsigned char *)"false",
            5) ||
        !weave_json_object_begin(writer) ||
        !weave_json_key(writer, "ok") ||
        !weave_json_boolean(writer, 1) ||
        !weave_json_object_end(writer) ||
        !weave_json_array_end(writer)) {
        return 1;
    }
    if (document->fail) {
        return 1;
    }
    return weave_json_object_end(writer) ? 0 : 1;
}

static int serialize_compact(FILE *stream, const void *opaque) {
    (void)opaque;
    weave_json_writer writer;
    weave_json_writer_init_mode(&writer, stream, 0);
    return weave_json_object_begin(&writer) &&
        weave_json_key(&writer, "x") &&
        weave_json_uint64(&writer, 1) &&
        weave_json_object_end(&writer) &&
        weave_json_writer_finish(&writer);
}

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

int main(int argc, char **argv) {
    if (argc != 2) {
        return 1;
    }
    const char *path = argv[1];
    FILE *seed = fopen(path, "wb");
    if (seed == NULL || fputs("old\n", seed) == EOF || fclose(seed) != 0) {
        return 2;
    }

    sample_document bad = {.fail = 1};
    if (weave_publish_json_document(
            path,
            "sample document",
            serialize_sample,
            &bad) == 0) {
        return 3;
    }
    char *old = read_all(path);
    if (old == NULL || strcmp(old, "old\n") != 0) {
        free(old);
        return 4;
    }
    free(old);

    sample_document good = {0};
    if (weave_publish_json_document(
            path,
            "sample document",
            serialize_sample,
            &good) != 0) {
        return 5;
    }
    char *json = read_all(path);
    if (json == NULL ||
        strstr(json, "\\n\\t\\\"\\\\\\u0001") == NULL ||
        strstr(json, "\"items\": [") == NULL ||
        strstr(json, "\"ok\": true") == NULL) {
        free(json);
        return 6;
    }
    free(json);

    char compact[4096];
    if (snprintf(compact, sizeof(compact), "%s.compact", path) >=
        (int)sizeof(compact)) {
        return 7;
    }
    if (weave_publish_document(
            compact,
            "compact document",
            0644,
            serialize_compact,
            NULL) != 0) {
        return 8;
    }
    char *compact_json = read_all(compact);
    if (compact_json == NULL ||
        strcmp(compact_json, "{\"x\":1}\n") != 0) {
        free(compact_json);
        return 9;
    }
    free(compact_json);
    unlink(compact);
    return 0;
}
EOF

cc -std=c11 -Wall -Wextra -Werror \
  "$WORK/test.c" -o "$WORK/test"

DOCUMENT="$WORK/document.json"
"$WORK/test" "$DOCUMENT"
python3 -m json.tool "$DOCUMENT" >/dev/null

if compgen -G "$DOCUMENT.tmp.*" >/dev/null; then
  printf 'json-publication: temporary file leaked\n' >&2
  exit 1
fi

grep -Fq '"text": "a\n\t\"\\\u0001"' "$DOCUMENT"
grep -Fq '"ok": true' "$DOCUMENT"

printf 'json-publication: checked writer and transactional publication passed\n'
