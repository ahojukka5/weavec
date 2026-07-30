// SPDX-License-Identifier: Apache-2.0
//
// Host serialization for semantic facts selected by the self-hosted frontend.
// This file is included after source_locations.c and trace_runtime.c so it can
// use their current source path and exact S-expression span expansion.

#ifndef WEAVEC_SEMANTIC_DIAGNOSTIC_RECORD_C
#define WEAVEC_SEMANTIC_DIAGNOSTIC_RECORD_C

static int weave_semantic_copy_cstr(
    char *destination,
    size_t capacity,
    const char *value) {
    if (destination == NULL || capacity == 0 || value == NULL) {
        return 0;
    }
    int written = snprintf(destination, capacity, "%s", value);
    return written >= 0 && (size_t)written < capacity;
}

static int weave_semantic_copy_slice(
    char *destination,
    size_t capacity,
    const char *source,
    size_t start,
    size_t length) {
    if (destination == NULL || capacity == 0 || source == NULL ||
        length >= capacity) {
        return 0;
    }
    memcpy(destination, source + start, length);
    destination[length] = '\0';
    return 1;
}

static int weave_semantic_write_record(
    const char *path,
    const weave_semantic_diagnostic *diagnostic) {
    int fd = open(path, O_WRONLY | O_CREAT | O_EXCL, 0600);
    if (fd < 0) {
        return 0;
    }
    const unsigned char *cursor = (const unsigned char *)diagnostic;
    size_t remaining = sizeof(*diagnostic);
    int ok = 1;
    while (remaining != 0) {
        ssize_t written = write(fd, cursor, remaining);
        if (written <= 0) {
            ok = 0;
            break;
        }
        cursor += (size_t)written;
        remaining -= (size_t)written;
    }
    if (close(fd) != 0) {
        ok = 0;
    }
    if (!ok) {
        unlink(path);
    }
    return ok;
}

void weave_rt_diag_record(
    const char *code,
    const char *source,
    int64_t start,
    int64_t length,
    const char *expected_type,
    const char *actual_type,
    int32_t argument_index,
    int32_t expected_count,
    int32_t actual_count,
    const char *operand_role,
    const char *symbol_source,
    int64_t symbol_start,
    int64_t symbol_length,
    int32_t repair_kind) {
    const char *path = getenv(WEAVEC_SEMANTIC_DIAGNOSTIC_ENV);
    if (path == NULL || *path == '\0' || code == NULL || source == NULL ||
        weave_trace_source_path == NULL || start < 0 || length < 0) {
        return;
    }

    size_t span_start = (size_t)start;
    size_t span_end = weave_source_form_end(
        source, span_start, (size_t)length);
    if (span_end < span_start) {
        return;
    }

    weave_semantic_diagnostic diagnostic = {
        .magic = WEAVE_SEMANTIC_DIAGNOSTIC_MAGIC,
        .version = WEAVE_SEMANTIC_DIAGNOSTIC_VERSION,
        .start_byte = span_start,
        .end_byte = span_end,
        .argument_index = argument_index,
        .expected_count = expected_count,
        .actual_count = actual_count,
    };
    if (!weave_semantic_copy_cstr(
            diagnostic.code, sizeof(diagnostic.code), code) ||
        !weave_semantic_copy_cstr(
            diagnostic.source, sizeof(diagnostic.source),
            weave_trace_source_path)) {
        return;
    }

    if (expected_type != NULL && *expected_type != '\0' &&
        weave_semantic_copy_cstr(
            diagnostic.expected_type, sizeof(diagnostic.expected_type),
            expected_type)) {
        diagnostic.flags |= WEAVE_SEMANTIC_HAS_EXPECTED_TYPE;
    }
    if (actual_type != NULL && *actual_type != '\0' &&
        weave_semantic_copy_cstr(
            diagnostic.actual_type, sizeof(diagnostic.actual_type),
            actual_type)) {
        diagnostic.flags |= WEAVE_SEMANTIC_HAS_ACTUAL_TYPE;
    }
    if (argument_index >= 0) {
        diagnostic.flags |= WEAVE_SEMANTIC_HAS_ARGUMENT_INDEX;
    }
    if (expected_count >= 0 && actual_count >= 0) {
        diagnostic.flags |= WEAVE_SEMANTIC_HAS_COUNTS;
    }
    if (operand_role != NULL && *operand_role != '\0' &&
        weave_semantic_copy_cstr(
            diagnostic.operand_role, sizeof(diagnostic.operand_role),
            operand_role)) {
        diagnostic.flags |= WEAVE_SEMANTIC_HAS_OPERAND_ROLE;
    }
    if (symbol_source != NULL && symbol_start >= 0 && symbol_length > 0 &&
        weave_semantic_copy_slice(
            diagnostic.symbol, sizeof(diagnostic.symbol), symbol_source,
            (size_t)symbol_start, (size_t)symbol_length)) {
        diagnostic.flags |= WEAVE_SEMANTIC_HAS_SYMBOL;
    }

    if (repair_kind == 1 && expected_type != NULL &&
        *expected_type != '\0') {
        int prefix = snprintf(
            diagnostic.replacement,
            sizeof(diagnostic.replacement),
            "(cast %s ", expected_type);
        size_t expression_length = span_end - span_start;
        if (prefix > 0 && (size_t)prefix < sizeof(diagnostic.replacement) &&
            expression_length + (size_t)prefix + 2 <
                sizeof(diagnostic.replacement)) {
            memcpy(
                diagnostic.replacement + prefix,
                source + span_start,
                expression_length);
            size_t used = (size_t)prefix + expression_length;
            diagnostic.replacement[used++] = ')';
            diagnostic.replacement[used] = '\0';
            diagnostic.replacement_start_byte = span_start;
            diagnostic.replacement_end_byte = span_end;
            (void)weave_semantic_copy_cstr(
                diagnostic.repair_confidence,
                sizeof(diagnostic.repair_confidence),
                "guaranteed-local");
            diagnostic.flags |= WEAVE_SEMANTIC_HAS_REPAIR;
        }
    }

    (void)weave_semantic_write_record(path, &diagnostic);
}

#endif
