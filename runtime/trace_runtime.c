// SPDX-License-Identifier: Apache-2.0
//
// Private event transport for weavec-compilation-trace-v1.
//
// The self-hosted frontend calls these helpers only at real lowering and
// optimization sites. The child frontend appends deterministic JSON objects to
// a private event stream; build_driver.c wraps them in the public trace document.

#ifndef WEAVEC_TRACE_EVENTS_ENV
#define WEAVEC_TRACE_EVENTS_ENV "WEAVEC_INTERNAL_TRACE_EVENTS"
#endif

static int64_t weave_trace_source_index = -1;
static const char *weave_trace_source_path = NULL;

static void weave_trace_json_bytes(
    FILE *stream,
    const unsigned char *data,
    size_t length) {
    fputc('"', stream);
    for (size_t i = 0; i < length; ++i) {
        unsigned char ch = data[i];
        switch (ch) {
            case '\\': fputs("\\\\", stream); break;
            case '"': fputs("\\\"", stream); break;
            case '\n': fputs("\\n", stream); break;
            case '\r': fputs("\\r", stream); break;
            case '\t': fputs("\\t", stream); break;
            default:
                if (ch < 0x20) {
                    fprintf(stream, "\\u%04x", (unsigned int)ch);
                } else {
                    fputc(ch, stream);
                }
        }
    }
    fputc('"', stream);
}

static void weave_trace_json_cstr(FILE *stream, const char *value) {
    const char *safe = value != NULL ? value : "";
    weave_trace_json_bytes(
        stream,
        (const unsigned char *)safe,
        strlen(safe));
}

void weave_rt_trace_set_source(int64_t source_index, const char *source_path) {
    weave_trace_source_index = source_index;
    weave_trace_source_path = source_path;
}

void weave_rt_trace_event(
    const char *kind,
    const char *pass,
    const char *action,
    const char *source,
    int64_t start,
    int64_t length,
    int64_t detail_start,
    int64_t detail_length) {
    const char *path = getenv(WEAVEC_TRACE_EVENTS_ENV);
    if (path == NULL || *path == '\0' || source == NULL ||
        weave_trace_source_index < 0 || start < 0 || length < 0) {
        return;
    }

    FILE *stream = fopen(path, "a");
    if (stream == NULL) {
        return;
    }

    size_t span_start = (size_t)start;
    size_t span_end = weave_source_form_end(
        source, span_start, (size_t)length);

    fputs("{\"kind\":", stream);
    weave_trace_json_cstr(stream, kind);
    fputs(",\"pass\":", stream);
    weave_trace_json_cstr(stream, pass);
    fputs(",\"action\":", stream);
    weave_trace_json_cstr(stream, action);
    fprintf(stream, ",\"source_index\":%lld,\"source\":",
            (long long)weave_trace_source_index);
    weave_trace_json_cstr(stream, weave_trace_source_path);
    fprintf(stream,
            ",\"span\":{\"start_byte\":%lld,\"end_byte\":%lld},"
            "\"surface\":",
            (long long)span_start,
            (long long)span_end);
    weave_trace_json_bytes(
        stream,
        (const unsigned char *)source + span_start,
        span_end - span_start);
    fputs(",\"detail\":", stream);
    if (detail_start >= 0 && detail_length >= 0) {
        weave_trace_json_bytes(
            stream,
            (const unsigned char *)source + detail_start,
            (size_t)detail_length);
    } else {
        fputs("null", stream);
    }
    fputs("}\n", stream);
    fclose(stream);
}

static int weave_trace_write_document(
    const char *path,
    const char *status,
    const char *phase,
    char **sources,
    int source_count,
    const char *events_path) {
    if (path == NULL) {
        return 0;
    }

    FILE *output = fopen(path, "w");
    if (output == NULL) {
        fprintf(stderr, "weavec: cannot write trace %s: %s\n",
                path, strerror(errno));
        return 1;
    }

    fputs("{\n  \"format\": \"weavec-compilation-trace-v1\",\n", output);
    fputs("  \"status\": ", output);
    weave_trace_json_cstr(output, status);
    fputs(",\n  \"phase\": ", output);
    weave_trace_json_cstr(output, phase);
    fputs(",\n  \"sources\": [", output);
    for (int i = 0; i < source_count; ++i) {
        if (i != 0) {
            fputs(", ", output);
        }
        weave_trace_json_cstr(output, sources[i]);
    }
    fputs("],\n  \"events\": [", output);

    FILE *events = events_path != NULL ? fopen(events_path, "r") : NULL;
    if (events != NULL) {
        char *line = NULL;
        size_t capacity = 0;
        ssize_t length;
        int first = 1;
        while ((length = getline(&line, &capacity, events)) >= 0) {
            while (length > 0 &&
                   (line[length - 1] == '\n' || line[length - 1] == '\r')) {
                line[--length] = '\0';
            }
            if (length == 0) {
                continue;
            }
            fputs(first ? "\n    " : ",\n    ", output);
            fwrite(line, 1, (size_t)length, output);
            first = 0;
        }
        free(line);
        fclose(events);
        if (!first) {
            fputs("\n  ", output);
        }
    }
    fputs("]\n}\n", output);

    int failed = ferror(output);
    if (fclose(output) != 0) {
        failed = 1;
    }
    if (failed) {
        fprintf(stderr, "weavec: cannot finish trace %s: %s\n",
                path, strerror(errno));
        unlink(path);
        return 1;
    }
    return 0;
}
