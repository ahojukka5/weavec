#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/test.c" <<'C'
#define _POSIX_C_SOURCE 200809L
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include "json_writer.c"
#include "document_publish.c"

typedef struct weave_diag_record {
    const char *code;
    const char *severity;
    const char *phase;
    const char *message;
    const char *source;
    const char *span_origin;
    size_t start_byte;
    size_t end_byte;
    int has_span;
    int owns_message;
} weave_diag_record;

static unsigned char *weave_diag_read_file(
    const char *path,
    size_t *length_out) {
    FILE *stream = fopen(path, "rb");
    if (stream == NULL) return NULL;
    if (fseek(stream, 0, SEEK_END) != 0) {
        fclose(stream);
        return NULL;
    }
    long end = ftell(stream);
    if (end < 0 || fseek(stream, 0, SEEK_SET) != 0) {
        fclose(stream);
        return NULL;
    }
    unsigned char *data = malloc((size_t)end + 1);
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
    *length_out = (size_t)end;
    return data;
}

static void weave_diag_position(
    const unsigned char *data,
    size_t length,
    size_t offset,
    size_t *line,
    size_t *column) {
    if (offset > length) offset = length;
    size_t current_line = 1;
    size_t current_column = 1;
    for (size_t i = 0; i < offset; ++i) {
        if (data[i] == '\n') {
            ++current_line;
            current_column = 1;
        } else if ((data[i] & 0xc0) != 0x80) {
            ++current_column;
        }
    }
    *line = current_line;
    *column = current_column;
}

#include "diagnostics_json.c"

static void exercise_remaining_json_operations(void) {
    FILE *stream = tmpfile();
    if (stream == NULL) abort();
    weave_json_writer writer;
    weave_json_writer_init_mode(&writer, stream, 0);
    if (!weave_json_array_begin(&writer) ||
        !weave_json_trusted_value(
            &writer, (const unsigned char *)"false", 5) ||
        !weave_json_array_end(&writer) ||
        !weave_json_writer_finish(&writer)) {
        abort();
    }
    fclose(stream);
}

static char *read_all(const char *path) {
    size_t length = 0;
    return (char *)weave_diag_read_file(path, &length);
}

int main(int argc, char **argv) {
    if (argc != 3) return 1;
    exercise_remaining_json_operations();
    const char *path = argv[1];
    const char *source = argv[2];

    FILE *seed = fopen(path, "wb");
    if (seed == NULL || fputs("old\n", seed) == EOF || fclose(seed) != 0) {
        return 2;
    }
    weave_diag_record record = {
        .code = "frontend.test",
        .severity = "error",
        .phase = "frontend",
        .message = "bad \"token\"\nline",
        .source = source,
        .span_origin = "compiler-preflight",
        .start_byte = 3,
        .end_byte = 6,
        .has_span = 1,
    };
    if (weave_diag_write_result(path, NULL, "frontend", 10, 1, &record) == 0) {
        return 3;
    }
    char *old = read_all(path);
    if (old == NULL || strcmp(old, "old\n") != 0) {
        free(old);
        return 4;
    }
    free(old);

    if (weave_diag_write_result(
            path, "failed", "frontend", 10, 1, &record) != 0) {
        return 5;
    }
    return 0;
}
C

printf 'α\nbad\n' > "$WORK/source.weave"
cc -std=c11 -Wall -Wextra -Werror \
  -I"$ROOT/runtime" \
  "$WORK/test.c" -o "$WORK/test"

DOCUMENT="$WORK/diagnostics.json"
"$WORK/test" "$DOCUMENT" "$WORK/source.weave"
python3 - <<'PY' "$DOCUMENT" "$WORK/source.weave"
import json
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    document = json.load(stream)
assert document == {
    "format": "weavec-diagnostics-v1",
    "status": "failed",
    "phase": "frontend",
    "exit_code": 10,
    "raw_exit_code": 1,
    "diagnostics": [{
        "code": "frontend.test",
        "severity": "error",
        "phase": "frontend",
        "message": 'bad "token"\nline',
        "source": sys.argv[2],
        "span_origin": "compiler-preflight",
        "span": {
            "start_byte": 3,
            "end_byte": 6,
            "start_line": 2,
            "start_column": 1,
            "end_line": 2,
            "end_column": 4,
        },
    }],
}
PY

if compgen -G "$DOCUMENT.tmp.*" >/dev/null; then
  printf 'diagnostics-publication: temporary file leaked\n' >&2
  exit 1
fi

printf 'diagnostics-publication: typed transactional diagnostics passed\n'
