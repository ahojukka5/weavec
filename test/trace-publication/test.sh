#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/test.c" <<'EOF'
#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static size_t weave_source_form_end(
    const char *source,
    size_t start,
    size_t length) {
    (void)source;
    return start + length;
}

#include "json_writer.c"

// This unit owns only the native trace transport/publication boundary. Public
// trace schema lives in surface Weave and is exercised by the compiler-level
// trace tests after the compiler is built.
int weave_protocol_trace_event_serialize(
    void *opaque,
    const char *kind,
    const char *pass,
    const char *action,
    long long source_index,
    const char *source_path,
    long long span_start,
    long long span_end,
    const unsigned char *surface,
    long long surface_length,
    int detail_present,
    const unsigned char *detail,
    long long detail_length) {
    (void)kind;
    (void)pass;
    (void)action;
    (void)source_index;
    (void)source_path;
    (void)span_start;
    (void)span_end;
    (void)surface;
    (void)surface_length;
    (void)detail_present;
    (void)detail;
    (void)detail_length;
    weave_json_writer *writer = opaque;
    return weave_json_object_begin(writer) && weave_json_object_end(writer)
        ? 0 : 1;
}

int weave_protocol_trace_document_serialize(
    void *opaque,
    const char *status,
    const char *phase,
    char **sources,
    int source_count,
    const char *events_path) {
    (void)status;
    (void)phase;
    (void)sources;
    (void)source_count;
    (void)events_path;
    weave_json_writer *writer = opaque;
    return weave_json_object_begin(writer) && weave_json_object_end(writer)
        ? 0 : 1;
}

#include "document_publish.c"
#include "trace_runtime.c"

static void exercise_writer_mechanics(void) {
    FILE *stream = tmpfile();
    if (stream == NULL) {
        abort();
    }
    weave_json_writer writer;
    weave_json_writer_init(&writer, stream);
    static const unsigned char trusted[] = "true";
    if (!weave_json_object_begin(&writer) ||
        !weave_json_key(&writer, "signed") ||
        !weave_json_int64(&writer, -2) ||
        !weave_json_key(&writer, "unsigned") ||
        !weave_json_uint64(&writer, 2) ||
        !weave_json_key(&writer, "trusted") ||
        !weave_json_trusted_value(&writer, trusted, 4) ||
        !weave_json_key(&writer, "nullable") ||
        !weave_json_nullable_string(&writer, NULL) ||
        !weave_json_key(&writer, "items") ||
        !weave_json_array_begin(&writer) ||
        !weave_json_string(&writer, "value") ||
        !weave_json_array_end(&writer) ||
        !weave_json_object_end(&writer) ||
        !weave_json_writer_finish(&writer)) {
        abort();
    }
    fclose(stream);
}

int main(int argc, char **argv) {
    if (argc != 2) {
        return 1;
    }
    exercise_writer_mechanics();

    char events[4096];
    char output[4096];
    if (snprintf(events, sizeof(events), "%s/events.jsonl", argv[1]) >=
            (int)sizeof(events) ||
        snprintf(output, sizeof(output), "%s/trace.json", argv[1]) >=
            (int)sizeof(output)) {
        return 2;
    }
    if (setenv(WEAVEC_TRACE_EVENTS_ENV, events, 1) != 0) {
        return 3;
    }

    weave_rt_trace_set_source(0, "source.weave");
    const char source[] = "(let x \"a\\nb\")";
    weave_rt_trace_event(
        "lower",
        "frontend",
        "emit",
        source,
        0,
        (int64_t)(sizeof(source) - 1),
        7,
        6);

    char *sources[] = {"source.weave"};
    if (weave_trace_write_document(
            output,
            "succeeded",
            "complete",
            sources,
            1,
            events) != 0) {
        return 4;
    }

    FILE *stream = fopen(output, "rb");
    if (stream == NULL) {
        return 5;
    }
    char data[128];
    size_t count = fread(data, 1, sizeof(data) - 1, stream);
    data[count] = '\0';
    if (ferror(stream) || fclose(stream) != 0) {
        return 6;
    }
    if (strcmp(data, "{}\n") != 0) {
        return 7;
    }
    return 0;
}
EOF

cc -std=c11 -Wall -Wextra -Werror \
  -I"$ROOT/runtime" \
  "$WORK/test.c" -o "$WORK/test"

"$WORK/test" "$WORK"
python3 -m json.tool "$WORK/trace.json" >/dev/null

printf 'trace-publication: native transport and checked publication passed\n'
