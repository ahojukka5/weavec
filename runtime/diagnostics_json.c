// SPDX-License-Identifier: Apache-2.0
//
// Typed serializer for weavec-diagnostics-v1. Diagnostic classification and
// span discovery remain in diagnostics_driver.c; this module owns only schema
// serialization and transactional publication.

#ifndef WEAVEC_DIAGNOSTICS_JSON_C
#define WEAVEC_DIAGNOSTICS_JSON_C

typedef struct weave_diagnostics_span {
    uint64_t start_byte;
    uint64_t end_byte;
    uint64_t start_line;
    uint64_t start_column;
    uint64_t end_line;
    uint64_t end_column;
    int present;
} weave_diagnostics_span;

typedef struct weave_diagnostics_document {
    const char *status;
    const char *phase;
    int stable_exit_code;
    int raw_exit_code;
    const weave_diag_record *record;
    weave_diagnostics_span span;
} weave_diagnostics_document;

static int weave_diagnostics_serialize(
    weave_json_writer *writer,
    const void *opaque) {
    const weave_diagnostics_document *document = opaque;
    if (!weave_json_object_begin(writer) ||
        !weave_json_key(writer, "format") ||
        !weave_json_string(writer, "weavec-diagnostics-v1") ||
        !weave_json_key(writer, "status") ||
        !weave_json_string(writer, document->status) ||
        !weave_json_key(writer, "phase") ||
        !weave_json_string(writer, document->phase) ||
        !weave_json_key(writer, "exit_code") ||
        !weave_json_int64(writer, document->stable_exit_code) ||
        !weave_json_key(writer, "raw_exit_code") ||
        !weave_json_int64(writer, document->raw_exit_code) ||
        !weave_json_key(writer, "diagnostics") ||
        !weave_json_array_begin(writer)) {
        return 1;
    }

    const weave_diag_record *record = document->record;
    if (record != NULL && record->code != NULL) {
        if (!weave_json_object_begin(writer) ||
            !weave_json_key(writer, "code") ||
            !weave_json_string(writer, record->code) ||
            !weave_json_key(writer, "severity") ||
            !weave_json_string(
                writer,
                record->severity != NULL ? record->severity : "error") ||
            !weave_json_key(writer, "phase") ||
            !weave_json_string(
                writer,
                record->phase != NULL ? record->phase : document->phase) ||
            !weave_json_key(writer, "message") ||
            !weave_json_string(
                writer,
                record->message != NULL ? record->message : "compiler failed") ||
            !weave_json_key(writer, "source") ||
            !weave_json_nullable_string(writer, record->source) ||
            !weave_json_key(writer, "span_origin") ||
            !weave_json_string(
                writer,
                record->span_origin != NULL ? record->span_origin : "none") ||
            !weave_json_key(writer, "span")) {
            return 1;
        }
        if (document->span.present) {
            if (!weave_json_object_begin(writer) ||
                !weave_json_key(writer, "start_byte") ||
                !weave_json_uint64(writer, document->span.start_byte) ||
                !weave_json_key(writer, "end_byte") ||
                !weave_json_uint64(writer, document->span.end_byte) ||
                !weave_json_key(writer, "start_line") ||
                !weave_json_uint64(writer, document->span.start_line) ||
                !weave_json_key(writer, "start_column") ||
                !weave_json_uint64(writer, document->span.start_column) ||
                !weave_json_key(writer, "end_line") ||
                !weave_json_uint64(writer, document->span.end_line) ||
                !weave_json_key(writer, "end_column") ||
                !weave_json_uint64(writer, document->span.end_column) ||
                !weave_json_object_end(writer)) {
                return 1;
            }
        } else if (!weave_json_null(writer)) {
            return 1;
        }
        if (!weave_json_object_end(writer)) {
            return 1;
        }
    }

    return weave_json_array_end(writer) &&
        weave_json_object_end(writer)
        ? 0
        : 1;
}

static int weave_diag_write_result(
    const char *path,
    const char *status,
    const char *phase,
    int stable_exit_code,
    int raw_exit_code,
    const weave_diag_record *record) {
    if (path == NULL) {
        return 0;
    }

    weave_diagnostics_span span = {0};
    if (record != NULL && record->has_span && record->source != NULL) {
        size_t source_length = 0;
        unsigned char *source_data = weave_diag_read_file(
            record->source,
            &source_length);
        if (source_data != NULL) {
            size_t start_line = 0;
            size_t start_column = 0;
            size_t end_line = 0;
            size_t end_column = 0;
            weave_diag_position(
                source_data,
                source_length,
                record->start_byte,
                &start_line,
                &start_column);
            weave_diag_position(
                source_data,
                source_length,
                record->end_byte,
                &end_line,
                &end_column);
            span = (weave_diagnostics_span){
                .start_byte = record->start_byte,
                .end_byte = record->end_byte,
                .start_line = start_line,
                .start_column = start_column,
                .end_line = end_line,
                .end_column = end_column,
                .present = 1,
            };
            free(source_data);
        }
    }

    weave_diagnostics_document document = {
        .status = status,
        .phase = phase,
        .stable_exit_code = stable_exit_code,
        .raw_exit_code = raw_exit_code,
        .record = record,
        .span = span,
    };
    return weave_publish_json_document(
        path,
        "diagnostics document",
        weave_diagnostics_serialize,
        &document);
}

#endif
