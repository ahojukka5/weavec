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
#include "semantic_diagnostic_transport.c"

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

const char *project_protocol_effective_diagnostic_phase(
    const char *current,
    const char *code) {
    (void)code;
    return current;
}

#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wunused-parameter"
int weave_protocol_diagnostics_serialize(
    void *opaque,
    const char *status,
    const char *document_phase,
    int stable_exit_code,
    int raw_exit_code,
    int record_present,
    const char *record_code,
    const char *record_severity,
    const char *record_phase,
    const char *record_message,
    const char *record_source,
    const char *record_span_origin,
    int span_present,
    long long span_start,
    long long span_end,
    long long span_start_line,
    long long span_start_column,
    long long span_end_line,
    long long span_end_column,
    int semantic_present,
    int semantic_flags,
    const char *semantic_code,
    const char *semantic_source,
    const char *expected_type,
    const char *actual_type,
    int argument_index,
    int expected_count,
    int actual_count,
    const char *operand_role,
    const char *symbol,
    const char *replacement,
    const char *repair_confidence,
    int replacement_span_present,
    long long replacement_start,
    long long replacement_end,
    long long replacement_start_line,
    long long replacement_start_column,
    long long replacement_end_line,
    long long replacement_end_column) {
    if (status == NULL) return 1;
    weave_json_writer *writer = opaque;
    return weave_json_object_begin(writer) && weave_json_object_end(writer)
        ? 0 : 1;
}
#pragma GCC diagnostic pop

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
            &writer, (const unsigned char *)"false", 5) ||
        !weave_json_key(&writer, "items") ||
        !weave_json_array_begin(&writer) ||
        !weave_json_array_end(&writer) ||
        !weave_json_object_end(&writer) ||
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
    exercise_writer_mechanics();
    const char *path = argv[1];
    const char *source = argv[2];

    weave_diagnostics_span resolved = weave_diagnostics_resolve_span(source, 3, 6);
    if (!resolved.present || resolved.start_line != 2 ||
        resolved.start_column != 1 || resolved.end_line != 2 ||
        resolved.end_column != 4) {
        return 2;
    }

    FILE *seed = fopen(path, "wb");
    if (seed == NULL || fputs("old\n", seed) == EOF || fclose(seed) != 0) {
        return 3;
    }
    weave_semantic_saved_env semantic_env = {0};
    if (!weave_semantic_begin_env(path, &semantic_env)) {
        return 4;
    }
    weave_diag_record record = {
        .code = "frontend.test",
        .severity = "error",
        .phase = "frontend",
        .message = "bad token",
        .source = source,
        .span_origin = "compiler-preflight",
        .start_byte = 3,
        .end_byte = 6,
        .has_span = 1,
    };
    if (weave_diag_write_result(path, NULL, "frontend", 10, 1, &record) == 0) {
        return 5;
    }
    char *old = read_all(path);
    if (old == NULL || strcmp(old, "old\n") != 0) {
        free(old);
        return 6;
    }
    free(old);

    if (weave_diag_write_result(
            path, "failed", "frontend", 10, 1, &record) != 0) {
        return 7;
    }
    weave_semantic_end_env(&semantic_env);
    return 0;
}
C

printf 'α\nbad\n' > "$WORK/source.weave"
cc -std=c11 -Wall -Wextra -Werror \
  -I"$ROOT/runtime" \
  "$WORK/test.c" -o "$WORK/test"

DOCUMENT="$WORK/diagnostics.json"
"$WORK/test" "$DOCUMENT" "$WORK/source.weave"
python3 - <<'PY' "$DOCUMENT"
import json
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    document = json.load(stream)
assert document == {}
PY

if compgen -G "$DOCUMENT.tmp.*" >/dev/null; then
  printf 'diagnostics-publication: temporary file leaked\n' >&2
  exit 1
fi

printf 'diagnostics-publication: native spans and transactional publication passed\n'
