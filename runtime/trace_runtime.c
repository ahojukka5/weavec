// SPDX-License-Identifier: Apache-2.0
//
// Private trace transport for the self-hosted compiler. Public event/document
// schemas and deterministic field ordering live in src/protocol/trace.weave.

#ifndef WEAVEC_TRACE_EVENTS_ENV
#define WEAVEC_TRACE_EVENTS_ENV "WEAVEC_INTERNAL_TRACE_EVENTS"
#endif

static int64_t weave_trace_source_index = -1;
static const char *weave_trace_source_path = NULL;

extern int weave_protocol_trace_event_serialize(
    void *writer,
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
    long long detail_length);

extern int weave_protocol_trace_document_serialize(
    void *writer,
    const char *status,
    const char *phase,
    char **sources,
    int source_count,
    const char *events_path);

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
    int detail_present = detail_start >= 0 && detail_length >= 0;
    const unsigned char *detail = detail_present
        ? (const unsigned char *)source + (size_t)detail_start
        : NULL;

    weave_json_writer writer;
    weave_json_writer_init_mode(&writer, stream, 0);
    int ok = weave_protocol_trace_event_serialize(
            &writer,
            kind,
            pass,
            action,
            (long long)weave_trace_source_index,
            weave_trace_source_path,
            (long long)span_start,
            (long long)span_end,
            (const unsigned char *)source + span_start,
            (long long)(span_end - span_start),
            detail_present,
            detail,
            detail_present ? (long long)detail_length : 0) == 0 &&
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
    return weave_protocol_trace_document_serialize(
        writer,
        document->status,
        document->phase,
        document->sources,
        document->source_count,
        document->events_path);
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
