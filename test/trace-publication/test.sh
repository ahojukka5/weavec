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
#include "document_publish.c"
#include "trace_runtime.c"

static void exercise_remaining_writer_operations(void) {
    FILE *stream = tmpfile();
    if (stream == NULL) {
        abort();
    }
    weave_json_writer writer;
    weave_json_writer_init(&writer, stream);
    if (!weave_json_array_begin(&writer) ||
        !weave_json_nullable_string(&writer, NULL) ||
        !weave_json_array_end(&writer) ||
        !weave_json_writer_finish(&writer)) {
        abort();
    }
    fclose(stream);
}

int main(int argc, char **argv) {
    if (argc != 2) {
        return 1;
    }
    exercise_remaining_writer_operations();

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
    char data[8192];
    size_t count = fread(data, 1, sizeof(data) - 1, stream);
    data[count] = '\0';
    if (ferror(stream) || fclose(stream) != 0) {
        return 6;
    }
    if (strstr(data, "weavec-compilation-trace-v1") == NULL ||
        strstr(data, "\\\"a\\\\nb\\\"") == NULL) {
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
python3 - <<'PY' "$WORK/trace.json"
import json
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    document = json.load(stream)
assert document["format"] == "weavec-compilation-trace-v1"
assert document["status"] == "succeeded"
assert document["phase"] == "complete"
assert document["sources"] == ["source.weave"]
assert len(document["events"]) == 1
assert document["events"][0]["source"] == "source.weave"
assert document["events"][0]["detail"] == '"a\\nb"'
PY

printf 'trace-publication: checked event and document serialization passed\n'
