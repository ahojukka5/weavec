// SPDX-License-Identifier: Apache-2.0
//
// Native data/publication bridge for weavec-diagnostics-v1. Diagnostic
// classification and span discovery remain host/compiler mechanics; the public
// schema, field ordering, optional-field policy, and repair representation are
// owned by src/protocol/diagnostics.weave.

#ifndef WEAVEC_DIAGNOSTICS_JSON_C
#define WEAVEC_DIAGNOSTICS_JSON_C

// A compiler-owned wrapper may publish a logical source identity while using a
// different physical file solely to resolve byte offsets into line/column facts.
// Ordinary diagnostics leave this unset and preserve the historical behavior.
static const char *weave_diag_span_source_override = NULL;

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

extern const char *project_protocol_effective_diagnostic_phase(
    const char *current,
    const char *code);

extern int weave_protocol_diagnostics_serialize(
    void *writer,
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
    long long replacement_end_column);

static int weave_diagnostics_serialize(
    weave_json_writer *writer,
    const void *opaque) {
    const weave_diagnostics_document *document = opaque;
    const weave_diag_record *record = document->record;
    const weave_semantic_diagnostic *semantic = &document->semantic;
    int record_present = record != NULL && record->code != NULL;
    const char *effective_code = document->semantic_present
        ? semantic->code
        : (record_present ? record->code : NULL);
    const char *document_phase = project_protocol_effective_diagnostic_phase(
        document->phase,
        effective_code);
    const char *record_phase = record_present && record->phase != NULL
        ? project_protocol_effective_diagnostic_phase(
              record->phase,
              effective_code)
        : NULL;
    return weave_protocol_diagnostics_serialize(
        writer,
        document->status,
        document_phase,
        document->stable_exit_code,
        document->raw_exit_code,
        record_present,
        record_present ? record->code : NULL,
        record_present ? record->severity : NULL,
        record_phase,
        record_present ? record->message : NULL,
        record_present ? record->source : NULL,
        record_present ? record->span_origin : NULL,
        document->span.present,
        (long long)document->span.start_byte,
        (long long)document->span.end_byte,
        (long long)document->span.start_line,
        (long long)document->span.start_column,
        (long long)document->span.end_line,
        (long long)document->span.end_column,
        document->semantic_present,
        (int)semantic->flags,
        semantic->code,
        semantic->source,
        semantic->expected_type,
        semantic->actual_type,
        semantic->argument_index,
        semantic->expected_count,
        semantic->actual_count,
        semantic->operand_role,
        semantic->symbol,
        semantic->replacement,
        semantic->repair_confidence,
        document->replacement_span.present,
        (long long)document->replacement_span.start_byte,
        (long long)document->replacement_span.end_byte,
        (long long)document->replacement_span.start_line,
        (long long)document->replacement_span.start_column,
        (long long)document->replacement_span.end_line,
        (long long)document->replacement_span.end_column);
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
        const char *span_source = weave_diag_span_source_override != NULL
            ? weave_diag_span_source_override
            : record->source;
        span = weave_diagnostics_resolve_span(
            span_source,
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
