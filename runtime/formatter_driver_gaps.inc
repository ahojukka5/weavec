static weave_fmt_gap weave_fmt_scan_gap(
    const weave_fmt_context *context,
    size_t start,
    size_t end) {
    weave_fmt_gap result = {.valid = 1};
    if (start > end || end > context->source_length) {
        result.valid = 0;
        return result;
    }
    size_t index = start;
    while (index < end) {
        unsigned char ch = context->source[index];
        if (ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r') {
            ++index;
            continue;
        }
        if (ch != ';') {
            result.valid = 0;
            return result;
        }
        ++result.comments;
        while (index < end && context->source[index] != '\n') {
            ++index;
        }
    }
    return result;
}

static int weave_fmt_emit_gap_comments(
    weave_fmt_context *context,
    size_t start,
    size_t end,
    size_t indentation) {
    weave_fmt_gap gap = weave_fmt_scan_gap(context, start, end);
    if (!gap.valid) {
        weave_fmt_fail(context);
        return 0;
    }
    if (gap.comments == 0) {
        return 1;
    }
    size_t index = start;
    while (index < end) {
        while (index < end && context->source[index] != ';') {
            ++index;
        }
        if (index == end) {
            break;
        }
        size_t comment_start = index;
        while (index < end && context->source[index] != '\n') {
            ++index;
        }
        size_t comment_end = index;
        while (comment_end > comment_start + 1 &&
               (context->source[comment_end - 1] == ' ' ||
                context->source[comment_end - 1] == '\t' ||
                context->source[comment_end - 1] == '\r')) {
            --comment_end;
        }
        if (!weave_fmt_write_newline(context) ||
            !weave_fmt_write_indent(context, indentation) ||
            !weave_fmt_write_bytes(
                context,
                context->source + comment_start,
                comment_end - comment_start) ||
            !weave_fmt_write_char(context, '\n')) {
            return 0;
        }
    }
    return 1;
}

static weave_fmt_type weave_fmt_type_from_text(
    const weave_fmt_context *context,
    int64_t node) {
    if (node == -1) return WEAVE_FMT_UNKNOWN;
    if (weave_fmt_node_text_equals(context, node, "void")) return WEAVE_FMT_VOID;
    if (weave_fmt_node_text_equals(context, node, "i32")) return WEAVE_FMT_I32;
    if (weave_fmt_node_text_equals(context, node, "i64")) return WEAVE_FMT_I64;
    if (weave_fmt_node_text_equals(context, node, "f32")) return WEAVE_FMT_F32;
    if (weave_fmt_node_text_equals(context, node, "f64")) return WEAVE_FMT_F64;
    if (weave_fmt_node_text_equals(context, node, "bool")) return WEAVE_FMT_BOOL;
    if (weave_fmt_node_text_equals(context, node, "ptr")) return WEAVE_FMT_PTR;
    if (weave_fmt_node_text_equals(context, node, "Qubit")) return WEAVE_FMT_QUBIT;
    return WEAVE_FMT_UNKNOWN;
}

static const char *weave_fmt_type_name(weave_fmt_type type) {
    switch (type) {
        case WEAVE_FMT_VOID: return "void";
        case WEAVE_FMT_I32: return "i32";
        case WEAVE_FMT_I64: return "i64";
        case WEAVE_FMT_F32: return "f32";
        case WEAVE_FMT_F64: return "f64";
        case WEAVE_FMT_BOOL: return "bool";
        case WEAVE_FMT_PTR: return "ptr";
        case WEAVE_FMT_QUBIT: return "Qubit";
        default: return NULL;
    }
}

static int weave_fmt_type_is_numeric(weave_fmt_type type) {
    return type == WEAVE_FMT_I32 || type == WEAVE_FMT_I64 ||
        type == WEAVE_FMT_F32 || type == WEAVE_FMT_F64;
}

static int weave_fmt_reserve_signatures(
    weave_fmt_context *context,
    size_t needed) {
    if (needed <= context->signature_capacity) return 1;
    size_t capacity = context->signature_capacity == 0
        ? 16 : context->signature_capacity * 2;
    while (capacity < needed) capacity *= 2;
    weave_fmt_signature *updated = realloc(
        context->signatures, capacity * sizeof(*updated));
    if (updated == NULL) {
        context->semantic_overflow = 1;
        return 0;
    }
    context->signatures = updated;
    context->signature_capacity = capacity;
    return 1;
}

static int weave_fmt_reserve_bindings(
    weave_fmt_context *context,
    size_t needed) {
    if (needed <= context->binding_capacity) return 1;
    size_t capacity = context->binding_capacity == 0
        ? 32 : context->binding_capacity * 2;
    while (capacity < needed) capacity *= 2;
    weave_fmt_binding *updated = realloc(
        context->bindings, capacity * sizeof(*updated));
    if (updated == NULL) {
        context->semantic_overflow = 1;
        return 0;
    }
    context->bindings = updated;
    context->binding_capacity = capacity;
    return 1;
}

static int weave_fmt_name_spans_equal(
    const weave_fmt_context *context,
    size_t left_start,
    size_t left_length,
    size_t right_start,
    size_t right_length) {
    return left_length == right_length &&
        left_start <= context->source_length &&
        right_start <= context->source_length &&
        left_length <= context->source_length - left_start &&
        right_length <= context->source_length - right_start &&
        memcmp(
            context->source + left_start,
            context->source + right_start,
            left_length) == 0;
}

