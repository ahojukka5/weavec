static int weave_fmt_emit_function_header_named(
    weave_fmt_context *context,
    int64_t cursor,
    const char *name,
    size_t indentation,
    int *emitted_header) {
    int64_t scan = cursor;
    while (scan != -1) {
        if (weave_fmt_list_headed(context, scan, name)) {
            if (!weave_fmt_write_newline(context) ||
                !weave_fmt_write_indent(context, indentation) ||
                !weave_fmt_format_node(
                    context, scan, indentation, WEAVE_FMT_UNKNOWN, 0)) {
                return 0;
            }
            *emitted_header = 1;
        }
        scan = node_next_sibling(context->tree, scan);
    }
    return 1;
}

static int weave_fmt_emit_function_body_item(
    weave_fmt_context *context,
    int64_t node,
    size_t indentation,
    int header_present,
    int *emitted_body,
    int *previous_multiline,
    int *previous_holds_next) {
    int current_multiline = !weave_fmt_spacing_node_fits_inline(
        context, node, indentation);
    int current_opens_group = weave_fmt_spacing_opens_group(
        context, node, indentation);
    int blank_line = !*emitted_body
        ? header_present
        : (!*previous_holds_next &&
           (*previous_multiline || current_opens_group));
    if (!weave_fmt_write_newline(context) ||
        (blank_line && !weave_fmt_write_char(context, '\n')) ||
        !weave_fmt_write_indent(context, indentation) ||
        !weave_fmt_format_node(
            context, node, indentation, WEAVE_FMT_UNKNOWN, 0)) {
        return 0;
    }
    *emitted_body = 1;
    *previous_multiline = current_multiline;
    *previous_holds_next = weave_fmt_spacing_holds_next(
        context, node, indentation);
    return 1;
}

static int weave_fmt_format_function(
    weave_fmt_context *context,
    int64_t list,
    int64_t head,
    size_t indentation) {
    int64_t name = weave_fmt_nth_child(context, list, 1);
    int64_t params = weave_fmt_find_clause(context, list, "params");
    if (params == -1) {
        params = weave_fmt_nth_child(context, list, 2);
        if (params != -1 &&
            weave_fmt_list_headed(context, params, "type-params")) {
            params = node_next_sibling(context->tree, params);
        }
    }
    int64_t returns = weave_fmt_find_clause(context, list, "returns");
    int64_t return_type = returns != -1
        ? weave_fmt_nth_child(context, returns, 1)
        : (params == -1 ? -1 : node_next_sibling(context->tree, params));
    if (name == -1 || params == -1 || return_type == -1) return 0;

    if (!weave_fmt_write_char(context, '(') ||
        !weave_fmt_write_atom(context, head) ||
        !weave_fmt_write_char(context, ' ') ||
        !weave_fmt_write_atom(context, name) ||
        !weave_fmt_write_char(context, ' ') ||
        !weave_fmt_write_char(context, '(')) {
        return 0;
    }
    int64_t params_head = node_first_child(context->tree, params);
    int64_t pair = (params_head != -1 &&
        weave_fmt_node_text_equals(context, params_head, "params"))
        ? weave_fmt_nth_child(context, params, 1)
        : params_head;
    if (pair != -1 &&
        node_kind(context->tree, pair) == node_list() &&
        weave_fmt_child_count(context, pair) == 0 &&
        node_next_sibling(context->tree, pair) == -1) {
        pair = -1;
    }
    int first_pair = 1;
    while (pair != -1) {
        if (!first_pair && !weave_fmt_write_char(context, ' ')) return 0;
        first_pair = 0;
        if (!weave_fmt_format_node(
                context, pair, indentation + 2, WEAVE_FMT_UNKNOWN, 1)) {
            return 0;
        }
        pair = node_next_sibling(context->tree, pair);
    }
    if (!weave_fmt_write_char(context, ')') ||
        !weave_fmt_write_char(context, ' ') ||
        !weave_fmt_format_node(
            context, return_type, indentation + 2, WEAVE_FMT_UNKNOWN, 1)) {
        return 0;
    }

    int64_t cursor = returns != -1
        ? node_next_sibling(context->tree, returns)
        : node_next_sibling(context->tree, return_type);
    int has_pure = 0;
    int has_no_alloc = 0;
    int has_det = 0;
    int64_t scan = cursor;
    while (scan != -1) {
        if (weave_fmt_list_headed(context, scan, "pure")) has_pure = 1;
        if (weave_fmt_list_headed(context, scan, "no_alloc")) has_no_alloc = 1;
        if (weave_fmt_list_headed(context, scan, "deterministic")) has_det = 1;
        if (weave_fmt_list_headed(context, scan, "effects")) {
            int64_t mark = weave_fmt_nth_child(context, scan, 1);
            while (mark != -1) {
                if (weave_fmt_node_text_equals(context, mark, "pure")) {
                    has_pure = 1;
                }
                if (weave_fmt_node_text_equals(context, mark, "no_alloc")) {
                    has_no_alloc = 1;
                }
                if (weave_fmt_node_text_equals(context, mark, "deterministic")) {
                    has_det = 1;
                }
                mark = node_next_sibling(context->tree, mark);
            }
        }
        scan = node_next_sibling(context->tree, scan);
    }

    int emitted_header = 0;
    if (!weave_fmt_emit_function_header_named(
            context, cursor, "doc", indentation + 2, &emitted_header) ||
        !weave_fmt_emit_function_header_named(
            context, cursor, "example", indentation + 2, &emitted_header) ||
        !weave_fmt_emit_function_header_named(
            context, cursor, "uses", indentation + 2, &emitted_header)) {
        return 0;
    }
    if (has_pure || has_no_alloc || has_det) {
        if (!weave_fmt_write_newline(context) ||
            !weave_fmt_write_indent(context, indentation + 2) ||
            !weave_fmt_write_cstr(context, "(effects ")) {
            return 0;
        }
        int first_effect = 1;
        if (has_pure &&
            !weave_fmt_write_effect_ident(context, "pure", &first_effect)) {
            return 0;
        }
        if (has_no_alloc &&
            !weave_fmt_write_effect_ident(context, "no_alloc", &first_effect)) {
            return 0;
        }
        if (has_det &&
            !weave_fmt_write_effect_ident(
                context, "deterministic", &first_effect)) {
            return 0;
        }
        if (!weave_fmt_write_char(context, ')')) return 0;
        emitted_header = 1;
    }
    if (!weave_fmt_emit_function_header_named(
            context, cursor, "requires", indentation + 2, &emitted_header) ||
        !weave_fmt_emit_function_header_named(
            context, cursor, "ensures", indentation + 2, &emitted_header)) {
        return 0;
    }

    int64_t signature_end_node = returns != -1 ? returns : return_type;
    int64_t previous_source_node = signature_end_node;
    int emitted_body = 0;
    int previous_multiline = 0;
    int previous_holds_next = 0;
    scan = cursor;
    while (scan != -1) {
        if (weave_fmt_is_fn_header(context, scan) ||
            weave_fmt_list_headed(context, scan, "params") ||
            weave_fmt_list_headed(context, scan, "returns")) {
            previous_source_node = scan;
            scan = node_next_sibling(context->tree, scan);
            continue;
        }
        if (!emitted_body) {
            size_t gap_from = weave_fmt_node_end(context, previous_source_node);
            size_t gap_to = weave_fmt_node_start(context, scan);
            if (gap_from != 0 && gap_to >= gap_from &&
                !weave_fmt_emit_gap_comments(
                    context, gap_from, gap_to, indentation + 2)) {
                return 0;
            }
        }
        if (weave_fmt_list_headed(context, scan, "do") &&
            node_next_sibling(context->tree, scan) == -1) {
            int64_t stmt = weave_fmt_nth_child(context, scan, 1);
            while (stmt != -1) {
                if (!weave_fmt_emit_function_body_item(
                        context,
                        stmt,
                        indentation + 2,
                        emitted_header,
                        &emitted_body,
                        &previous_multiline,
                        &previous_holds_next)) {
                    return 0;
                }
                stmt = node_next_sibling(context->tree, stmt);
            }
            previous_source_node = scan;
            scan = node_next_sibling(context->tree, scan);
            continue;
        }
        if (!weave_fmt_emit_function_body_item(
                context,
                scan,
                indentation + 2,
                emitted_header,
                &emitted_body,
                &previous_multiline,
                &previous_holds_next)) {
            return 0;
        }
        previous_source_node = scan;
        scan = node_next_sibling(context->tree, scan);
    }
    return weave_fmt_write_char(context, ')');
}
