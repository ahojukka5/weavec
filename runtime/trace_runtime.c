// SPDX-License-Identifier: Apache-2.0
//
// Private event transport and public weavec-compilation-trace-v1 serializer.
// Both event records and the final document use the shared checked JSON writer.

#ifndef WEAVEC_TRACE_EVENTS_ENV
#define WEAVEC_TRACE_EVENTS_ENV "WEAVEC_INTERNAL_TRACE_EVENTS"
#endif

static int64_t weave_trace_source_index = -1;
static const char *weave_trace_source_path = NULL;

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

    weave_json_writer writer;
    weave_json_writer_init_mode(&writer, stream, 0);
    int ok =
        weave_json_object_begin(&writer) &&
        weave_json_key(&writer, "kind") &&
        weave_json_string(&writer, kind != NULL ? kind : "") &&
        weave_json_key(&writer, "pass") &&
        weave_json_string(&writer, pass != NULL ? pass : "") &&
        weave_json_key(&writer, "action") &&
        weave_json_string(&writer, action != NULL ? action : "") &&
        weave_json_key(&writer, "source_index") &&
        weave_json_int64(&writer, weave_trace_source_index) &&
        weave_json_key(&writer, "source") &&
        weave_json_string(
            &writer,
            weave_trace_source_path != NULL ? weave_trace_source_path : "") &&
        weave_json_key(&writer, "span") &&
        weave_json_object_begin(&writer) &&
        weave_json_key(&writer, "start_byte") &&
        weave_json_uint64(&writer, (uint64_t)span_start) &&
        weave_json_key(&writer, "end_byte") &&
        weave_json_uint64(&writer, (uint64_t)span_end) &&
        weave_json_object_end(&writer) &&
        weave_json_key(&writer, "surface") &&
        weave_json_string_bytes(
            &writer,
            (const unsigned char *)source + span_start,
            span_end - span_start) &&
        weave_json_key(&writer, "detail");
    if (ok) {
        if (detail_start >= 0 && detail_length >= 0) {
            ok = weave_json_string_bytes(
                &writer,
                (const unsigned char *)source + (size_t)detail_start,
                (size_t)detail_length);
        } else {
            ok = weave_json_null(&writer);
        }
    }
    ok = ok &&
        weave_json_object_end(&writer) &&
        weave_json_writer_finish(&writer);
    int close_failed = fclose(stream) != 0;
    if (!ok || close_failed) {
        return;
    }
}

typedef struct weave_trace_document {
    const char *status;
    const char *phase;
    char **sources;
    int source_count;
    const char *events_path;
} weave_trace_document;

static int weave_trace_serialize_document(
    weave_json_writer *writer,
    const void *opaque) {
    const weave_trace_document *document = opaque;
    if (!weave_json_object_begin(writer) ||
        !weave_json_key(writer, "format") ||
        !weave_json_string(writer, "weavec-compilation-trace-v1") ||
        !weave_json_key(writer, "status") ||
        !weave_json_string(writer, document->status) ||
        !weave_json_key(writer, "phase") ||
        !weave_json_string(writer, document->phase) ||
        !weave_json_key(writer, "sources") ||
        !weave_json_array_begin(writer)) {
        return 1;
    }
    for (int i = 0; i < document->source_count; ++i) {
        if (!weave_json_string(writer, document->sources[i])) {
            return 1;
        }
    }
    if (!weave_json_array_end(writer) ||
        !weave_json_key(writer, "events") ||
        !weave_json_array_begin(writer)) {
        return 1;
    }

    FILE *events = NULL;
    if (document->events_path != NULL) {
        events = fopen(document->events_path, "r");
        if (events == NULL && errno != ENOENT) {
            return 1;
        }
    }
    if (events != NULL) {
        char *line = NULL;
        size_t capacity = 0;
        ssize_t length;
        while ((length = getline(&line, &capacity, events)) >= 0) {
            while (length > 0 &&
                   (line[length - 1] == '\n' ||
                    line[length - 1] == '\r')) {
                --length;
            }
            if (length != 0 && !weave_json_trusted_value(
                    writer,
                    (const unsigned char *)line,
                    (size_t)length)) {
                free(line);
                fclose(events);
                return 1;
            }
        }
        int failed = ferror(events);
        free(line);
        if (fclose(events) != 0) {
            failed = 1;
        }
        if (failed) {
            return 1;
        }
    }

    return weave_json_array_end(writer) &&
        weave_json_object_end(writer)
        ? 0
        : 1;
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
    weave_trace_document document = {
        .status = status,
        .phase = phase,
        .sources = sources,
        .source_count = source_count,
        .events_path = events_path,
    };
    return weave_publish_json_document(
        path,
        "trace document",
        weave_trace_serialize_document,
        &document);
}
