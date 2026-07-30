// SPDX-License-Identifier: Apache-2.0
//
// Typed serializer for weavec-diagnostics-v1. Diagnostic classification and
// span discovery remain in diagnostics_driver.c; this module owns schema
// serialization, semantic-sidecar enrichment, and transactional publication.

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
    weave_semantic_diagnostic semantic;
    weave_diagnostics_span replacement_span;
    int semantic_present;
} weave_diagnostics_document;

static int weave_diagnostics_bool(
    weave_json_writer *writer,
    int value) {
    const unsigned char *text = (const unsigned char *)(value ? "true" : "false");
    return weave_json_trusted_value(writer, text, value ? 4 : 5);
}

static int weave_diagnostics_write_span(
    weave_json_writer *writer,
    const weave_diagnostics_span *span) {
    if (span == NULL || !span->present) {
        return weave_json_null(writer);
    }
    return weave_json_object_begin(writer) &&
        weave_json_key(writer, "start_byte") &&
        weave_json_uint64(writer, span->start_byte) &&
        weave_json_key(writer, "end_byte") &&
        weave_json_uint64(writer, span->end_byte) &&
        weave_json_key(writer, "start_line") &&
        weave_json_uint64(writer, span->start_line) &&
        weave_json_key(writer, "start_column") &&
        weave_json_uint64(writer, span->start_column) &&
        weave_json_key(writer, "end_line") &&
        weave_json_uint64(writer, span->end_line) &&
        weave_json_key(writer, "end_column") &&
        weave_json_uint64(writer, span->end_column) &&
        weave_json_object_end(writer);
}

static int weave_diagnostics_write_repairs(
    weave_json_writer *writer,
    const weave_diagnostics_document *document) {
    if (!weave_json_array_begin(writer)) {
        return 0;
    }
    const weave_semantic_diagnostic *semantic = &document->semantic;
    if (document->semantic_present &&
        (semantic->flags & WEAVE_SEMANTIC_HAS_REPAIR) != 0) {
        if (!weave_json_object_begin(writer) ||
            !weave_json_key(writer, "kind") ||
            !weave_json_string(writer, "replace") ||
            !weave_json_key(writer, "replacement") ||
            !weave_json_string(writer, semantic->replacement) ||
            !weave_json_key(writer, "replacement_span") ||
            !weave_diagnostics_write_span(
                writer, &document->replacement_span) ||
            !weave_json_key(writer, "confidence") ||
            !weave_json_string(writer, semantic->repair_confidence) ||
            !weave_json_object_end(writer)) {
            return 0;
        }
    }
    return weave_json_array_end(writer);
}

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
        const weave_semantic_diagnostic *semantic = &document->semantic;
        const char *code = document->semantic_present
            ? semantic->code : record->code;
        const char *source = document->semantic_present
            ? semantic->source : record->source;
        const char *span_origin = document->semantic_present
            ? "compiler-semantic"
            : (record->span_origin != NULL ? record->span_origin : "none");
        int analysis_complete = document->semantic_present ||
            strcmp(span_origin, "compiler-preflight") == 0;

        if (!weave_json_object_begin(writer) ||
            !weave_json_key(writer, "code") ||
            !weave_json_string(writer, code) ||
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
            !weave_json_nullable_string(writer, source) ||
            !weave_json_key(writer, "span_origin") ||
            !weave_json_string(writer, span_origin) ||
            !weave_json_key(writer, "span") ||
            !weave_diagnostics_write_span(writer, &document->span) ||
            !weave_json_key(writer, "analysis_complete") ||
            !weave_diagnostics_bool(writer, analysis_complete)) {
            return 1;
        }

        if (document->semantic_present) {
            if ((semantic->flags & WEAVE_SEMANTIC_HAS_EXPECTED_TYPE) != 0 &&
                (!weave_json_key(writer, "expected_type") ||
                 !weave_json_string(writer, semantic->expected_type))) {
                return 1;
            }
            if ((semantic->flags & WEAVE_SEMANTIC_HAS_ACTUAL_TYPE) != 0 &&
                (!weave_json_key(writer, "actual_type") ||
                 !weave_json_string(writer, semantic->actual_type))) {
                return 1;
            }
            if ((semantic->flags & WEAVE_SEMANTIC_HAS_ARGUMENT_INDEX) != 0 &&
                (!weave_json_key(writer, "argument_index") ||
                 !weave_json_int64(writer, semantic->argument_index))) {
                return 1;
            }
            if ((semantic->flags & WEAVE_SEMANTIC_HAS_COUNTS) != 0 &&
                (!weave_json_key(writer, "expected_count") ||
                 !weave_json_int64(writer, semantic->expected_count) ||
                 !weave_json_key(writer, "actual_count") ||
                 !weave_json_int64(writer, semantic->actual_count))) {
                return 1;
            }
            if ((semantic->flags & WEAVE_SEMANTIC_HAS_OPERAND_ROLE) != 0 &&
                (!weave_json_key(writer, "operand_role") ||
                 !weave_json_string(writer, semantic->operand_role))) {
                return 1;
            }
            if ((semantic->flags & WEAVE_SEMANTIC_HAS_SYMBOL) != 0 &&
                (!weave_json_key(writer, "symbol") ||
                 !weave_json_string(writer, semantic->symbol))) {
                return 1;
            }
        }

        if (!weave_json_key(writer, "candidates") ||
            !weave_json_array_begin(writer) ||
            !weave_json_array_end(writer) ||
            !weave_json_key(writer, "related_locations") ||
            !weave_json_array_begin(writer) ||
            !weave_json_array_end(writer) ||
            !weave_json_key(writer, "repairs") ||
            !weave_diagnostics_write_repairs(writer, document) ||
            !weave_json_object_end(writer)) {
            return 1;
        }
    }

    return weave_json_array_end(writer) &&
        weave_json_object_end(writer)
        ? 0
        : 1;
}

static weave_diagnostics_span weave_diagnostics_resolve_span(
    const char *source,
    uint64_t start_byte,
    uint64_t end_byte) {
    weave_diagnostics_span span = {0};
    if (source == NULL || start_byte > end_byte) {
        return span;
    }
    size_t source_length = 0;
    unsigned char *source_data = weave_diag_read_file(
        source,
        &source_length);
    if (source_data == NULL || end_byte > source_length) {
        free(source_data);
        return span;
    }
    size_t start_line = 0;
    size_t start_column = 0;
    size_t end_line = 0;
    size_t end_column = 0;
    weave_diag_position(
        source_data,
        source_length,
        (size_t)start_byte,
        &start_line,
        &start_column);
    weave_diag_position(
        source_data,
        source_length,
        (size_t)end_byte,
        &end_line,
        &end_column);
    free(source_data);
    span = (weave_diagnostics_span){
        .start_byte = start_byte,
        .end_byte = end_byte,
        .start_line = start_line,
        .start_column = start_column,
        .end_line = end_line,
        .end_column = end_column,
        .present = 1,
    };
    return span;
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

    weave_semantic_diagnostic semantic = {0};
    int semantic_present = weave_semantic_read_env(&semantic);
    weave_diagnostics_span span = {0};
    weave_diagnostics_span replacement_span = {0};
    if (semantic_present) {
        span = weave_diagnostics_resolve_span(
            semantic.source,
            semantic.start_byte,
            semantic.end_byte);
        if ((semantic.flags & WEAVE_SEMANTIC_HAS_REPAIR) != 0) {
            replacement_span = weave_diagnostics_resolve_span(
                semantic.source,
                semantic.replacement_start_byte,
                semantic.replacement_end_byte);
            if (!replacement_span.present) {
                semantic.flags &= ~WEAVE_SEMANTIC_HAS_REPAIR;
            }
        }
        if (!span.present) {
            semantic_present = 0;
        }
    }
    if (!semantic_present && record != NULL && record->has_span &&
        record->source != NULL) {
        span = weave_diagnostics_resolve_span(
            record->source,
            record->start_byte,
            record->end_byte);
    }

    weave_diagnostics_document document = {
        .status = status,
        .phase = phase,
        .stable_exit_code = stable_exit_code,
        .raw_exit_code = raw_exit_code,
        .record = record,
        .span = span,
        .semantic = semantic,
        .replacement_span = replacement_span,
        .semantic_present = semantic_present,
    };
    return weave_publish_json_document(
        path,
        "diagnostics document",
        weave_diagnostics_serialize,
        &document);
}

#endif
