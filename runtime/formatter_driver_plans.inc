static int weave_fmt_list_has_comments(
    const weave_fmt_context *context,
    int64_t list) {
    size_t list_start = weave_fmt_node_start(context, list);
    size_t list_end = weave_fmt_node_end(context, list);
    int64_t child = node_first_child(context->tree, list);
    if (list_end == 0 || child == -1) return 0;
    size_t cursor = list_start + 1;
    while (child != -1) {
        size_t child_start = weave_fmt_node_start(context, child);
        weave_fmt_gap gap = weave_fmt_scan_gap(context, cursor, child_start);
        if (!gap.valid || gap.comments != 0) return 1;
        cursor = weave_fmt_node_end(context, child);
        if (cursor == 0) return 1;
        child = node_next_sibling(context->tree, child);
    }
    weave_fmt_gap trailing = weave_fmt_scan_gap(context, cursor, list_end - 1);
    return !trailing.valid || trailing.comments != 0;
}

static weave_fmt_type weave_fmt_expr_type(
    weave_fmt_context *context,
    int64_t node,
    weave_fmt_type expected);

static weave_fmt_type weave_fmt_seed_type(
    weave_fmt_context *context,
    int64_t node) {
    if (node == -1) return WEAVE_FMT_UNKNOWN;
    if (node_kind(context->tree, node) == node_int()) return WEAVE_FMT_UNKNOWN;
    return weave_fmt_expr_type(context, node, WEAVE_FMT_UNKNOWN);
}

static weave_fmt_type weave_fmt_infer_canonical_operand_type(
    weave_fmt_context *context,
    int64_t left,
    int64_t right) {
    weave_fmt_type left_type = weave_fmt_seed_type(context, left);
    weave_fmt_type right_type = weave_fmt_seed_type(context, right);
    if (left_type == WEAVE_FMT_UNKNOWN && right_type == WEAVE_FMT_UNKNOWN) {
        return WEAVE_FMT_I32;
    }
    if (left_type == WEAVE_FMT_UNKNOWN) return right_type;
    if (right_type == WEAVE_FMT_UNKNOWN) return left_type;
    return left_type == right_type ? left_type : WEAVE_FMT_UNKNOWN;
}

static weave_fmt_type weave_fmt_constant_type(
    const weave_fmt_context *context,
    int64_t head) {
    if (weave_fmt_node_text_equals(context, head, "const_i32")) return WEAVE_FMT_I32;
    if (weave_fmt_node_text_equals(context, head, "const_i64")) return WEAVE_FMT_I64;
    if (weave_fmt_node_text_equals(context, head, "const_f32")) return WEAVE_FMT_F32;
    if (weave_fmt_node_text_equals(context, head, "const_f64")) return WEAVE_FMT_F64;
    if (weave_fmt_node_text_equals(context, head, "const_bool")) return WEAVE_FMT_BOOL;
    if (weave_fmt_node_text_equals(context, head, "const_null")) return WEAVE_FMT_PTR;
    if (weave_fmt_node_text_equals(context, head, "const_string_ptr")) return WEAVE_FMT_PTR;
    return WEAVE_FMT_UNKNOWN;
}

static weave_fmt_type weave_fmt_expr_type(
    weave_fmt_context *context,
    int64_t node,
    weave_fmt_type expected) {
    if (node == -1) return WEAVE_FMT_UNKNOWN;
    int32_t kind = node_kind(context->tree, node);
    if (kind == node_int()) {
        return weave_fmt_type_is_numeric(expected) ? expected : WEAVE_FMT_I32;
    }
    if (kind == node_string()) return WEAVE_FMT_PTR;
    if (kind == node_ident()) {
        if (weave_fmt_node_text_equals(context, node, "true") ||
            weave_fmt_node_text_equals(context, node, "false")) {
            return WEAVE_FMT_BOOL;
        }
        if (weave_fmt_node_text_equals(context, node, "null")) {
            return WEAVE_FMT_PTR;
        }
        return weave_fmt_lookup_binding(context, node, 0);
    }
    if (kind != node_list()) return WEAVE_FMT_UNKNOWN;
    int64_t head = node_first_child(context->tree, node);
    if (head == -1 || node_kind(context->tree, head) != node_ident()) {
        return WEAVE_FMT_UNKNOWN;
    }
    weave_fmt_type constant = weave_fmt_constant_type(context, head);
    if (constant != WEAVE_FMT_UNKNOWN) return constant;
    if (weave_fmt_node_text_equals(context, head, "param_get") ||
        weave_fmt_node_text_equals(context, head, "local_get")) {
        int64_t name = weave_fmt_nth_child(context, node, 1);
        return weave_fmt_lookup_binding(context, name, 0);
    }
    if (weave_fmt_node_text_equals(context, head, "call")) {
        const weave_fmt_signature *signature = weave_fmt_lookup_signature_node(
            context, weave_fmt_nth_child(context, node, 1));
        return signature != NULL ? signature->return_type : WEAVE_FMT_UNKNOWN;
    }
    {
        const weave_fmt_signature *direct = weave_fmt_lookup_signature_node(
            context, head);
        if (direct != NULL) return direct->return_type;
    }
    size_t base_length = 0;
    weave_fmt_type call_type = weave_fmt_parse_typed_suffix(
        context, head, &base_length);
    if (call_type != WEAVE_FMT_UNKNOWN &&
        base_length == 4 &&
        memcmp(
            context->source + (size_t)node_text_start(context->tree, head),
            "call",
            4) == 0) {
        return call_type;
    }
    if (weave_fmt_node_text_equals(context, head, "cast")) {
        return weave_fmt_type_from_text(
            context, weave_fmt_nth_child(context, node, 1));
    }
    weave_fmt_type cast_source = WEAVE_FMT_UNKNOWN;
    weave_fmt_type cast_target = WEAVE_FMT_UNKNOWN;
    if (weave_fmt_parse_cast_head(
            context, head, &cast_source, &cast_target)) {
        return cast_target;
    }
    if (weave_fmt_node_text_equals(context, head, "op")) {
        const char *compact = weave_fmt_compact_operator_from_name(
            context, weave_fmt_nth_child(context, node, 1));
        if (compact == NULL) return WEAVE_FMT_UNKNOWN;
        if (weave_fmt_compact_operator_is_bool_result(compact)) {
            return WEAVE_FMT_BOOL;
        }
        return weave_fmt_infer_canonical_operand_type(
            context,
            weave_fmt_nth_child(context, node, 2),
            weave_fmt_nth_child(context, node, 3));
    }
    if (weave_fmt_is_compact_operator_head(context, head)) {
        const char *compact = weave_fmt_compact_operator_from_name(context, head);
        if (compact != NULL &&
            weave_fmt_compact_operator_is_bool_result(compact)) {
            return WEAVE_FMT_BOOL;
        }
        return weave_fmt_infer_canonical_operand_type(
            context,
            weave_fmt_nth_child(context, node, 1),
            weave_fmt_nth_child(context, node, 2));
    }
    weave_fmt_type operand_type = WEAVE_FMT_UNKNOWN;
    int bool_result = 0;
    if (weave_fmt_operator_name(
            context, head, &operand_type, &bool_result) != NULL) {
        return bool_result ? WEAVE_FMT_BOOL : operand_type;
    }
    return WEAVE_FMT_UNKNOWN;
}

static int weave_fmt_write_atom(
    weave_fmt_context *context,
    int64_t node) {
    int32_t kind = node_kind(context->tree, node);
    int64_t start_raw = node_text_start(context->tree, node);
    int64_t length_raw = node_text_len(context->tree, node);
    if (start_raw < 0 || length_raw < 0 ||
        (uint64_t)start_raw > context->source_length ||
        (uint64_t)length_raw > context->source_length - (size_t)start_raw) {
        weave_fmt_fail(context);
        return 0;
    }
    if (kind == node_string()) {
        int64_t style = node_value(context->tree, node);
        if ((style == 1 || style == 3) &&
            !weave_fmt_write_char(context, '#')) {
            return 0;
        }
        if (style == 2 || style == 3) {
            if (!weave_fmt_write_char(context, '"') ||
                !weave_fmt_write_char(context, '"') ||
                !weave_fmt_write_char(context, '"')) {
                return 0;
            }
        } else if (!weave_fmt_write_char(context, '"')) {
            return 0;
        }
    }
    /* A decimal atom is an integer node that keeps its exact source span;
       node_value holds no usable value for it, so reprint only real integers
       and copy a decimal lexeme through untouched. */
    if (kind == node_int() &&
        memchr(context->source + (size_t)start_raw, '.',
               (size_t)length_raw) == NULL) {
        char buffer[32];
        int length = snprintf(
            buffer, sizeof(buffer), "%lld", (long long)node_value(context->tree, node));
        if (length < 0 || (size_t)length >= sizeof(buffer) ||
            !weave_fmt_write_bytes(context, buffer, (size_t)length)) {
            weave_fmt_fail(context);
            return 0;
        }
    } else if (!weave_fmt_write_bytes(
            context,
            context->source + (size_t)start_raw,
            (size_t)length_raw)) {
        return 0;
    }
    if (kind == node_string()) {
        int64_t style = node_value(context->tree, node);
        if (style == 2 || style == 3) {
            if (!weave_fmt_write_char(context, '"') ||
                !weave_fmt_write_char(context, '"') ||
                !weave_fmt_write_char(context, '"')) {
                return 0;
            }
        } else if (!weave_fmt_write_char(context, '"')) {
            return 0;
        }
    }
    return 1;
}

