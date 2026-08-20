static int weave_fmt_format_node(
    weave_fmt_context *context,
    int64_t node,
    size_t indentation,
    weave_fmt_type expected,
    int force_inline);

static int weave_fmt_is_fn_header(
    const weave_fmt_context *context,
    int64_t node) {
    return weave_fmt_list_headed(context, node, "doc") ||
        weave_fmt_list_headed(context, node, "example") ||
        weave_fmt_list_headed(context, node, "uses") ||
        weave_fmt_list_headed(context, node, "effects") ||
        weave_fmt_list_headed(context, node, "requires") ||
        weave_fmt_list_headed(context, node, "ensures") ||
        weave_fmt_list_headed(context, node, "pure") ||
        weave_fmt_list_headed(context, node, "no_alloc") ||
        weave_fmt_list_headed(context, node, "deterministic");
}

static int weave_fmt_format_anonymous_list(
    weave_fmt_context *context,
    int64_t list,
    size_t indentation,
    int force_inline) {
    (void)force_inline;
    if (!weave_fmt_write_char(context, '(')) return 0;
    int64_t child = node_first_child(context->tree, list);
    int first = 1;
    while (child != -1) {
        if (!first && !weave_fmt_write_char(context, ' ')) return 0;
        first = 0;
        if (!weave_fmt_format_node(
                context, child, indentation + 2, WEAVE_FMT_UNKNOWN, 1)) {
            return 0;
        }
        child = node_next_sibling(context->tree, child);
    }
    return weave_fmt_write_char(context, ')');
}

static int weave_fmt_write_effect_ident(
    weave_fmt_context *context,
    const char *name,
    int *first) {
    if (!*first && !weave_fmt_write_char(context, ' ')) return 0;
    *first = 0;
    return weave_fmt_write_cstr(context, name);
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

    scan = cursor;
    while (scan != -1) {
        if (weave_fmt_list_headed(context, scan, "doc") ||
            weave_fmt_list_headed(context, scan, "example") ||
            weave_fmt_list_headed(context, scan, "uses")) {
            if (!weave_fmt_write_newline(context) ||
                !weave_fmt_write_indent(context, indentation + 2) ||
                !weave_fmt_format_node(
                    context, scan, indentation + 2, WEAVE_FMT_UNKNOWN, 0)) {
                return 0;
            }
        }
        scan = node_next_sibling(context->tree, scan);
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
    }
    scan = cursor;
    while (scan != -1) {
        if (weave_fmt_list_headed(context, scan, "requires") ||
            weave_fmt_list_headed(context, scan, "ensures")) {
            if (!weave_fmt_write_newline(context) ||
                !weave_fmt_write_indent(context, indentation + 2) ||
                !weave_fmt_format_node(
                    context, scan, indentation + 2, WEAVE_FMT_UNKNOWN, 0)) {
                return 0;
            }
        }
        scan = node_next_sibling(context->tree, scan);
    }

    int64_t signature_end_node = returns != -1 ? returns : return_type;
    int emitted_body = 0;
    scan = cursor;
    while (scan != -1) {
        if (weave_fmt_is_fn_header(context, scan) ||
            weave_fmt_list_headed(context, scan, "params") ||
            weave_fmt_list_headed(context, scan, "returns")) {
            scan = node_next_sibling(context->tree, scan);
            continue;
        }
        if (!emitted_body) {
            size_t gap_from = weave_fmt_node_end(context, signature_end_node);
            size_t gap_to = weave_fmt_node_start(context, scan);
            if (gap_from != 0 && gap_to >= gap_from &&
                !weave_fmt_emit_gap_comments(
                    context, gap_from, gap_to, indentation + 2)) {
                return 0;
            }
            emitted_body = 1;
        }
        if (weave_fmt_list_headed(context, scan, "do") &&
            node_next_sibling(context->tree, scan) == -1) {
            int64_t stmt = weave_fmt_nth_child(context, scan, 1);
            while (stmt != -1) {
                if (!weave_fmt_write_newline(context) ||
                    !weave_fmt_write_indent(context, indentation + 2) ||
                    !weave_fmt_format_node(
                        context, stmt, indentation + 2, WEAVE_FMT_UNKNOWN, 0)) {
                    return 0;
                }
                stmt = node_next_sibling(context->tree, stmt);
            }
            scan = node_next_sibling(context->tree, scan);
            continue;
        }
        if (!weave_fmt_write_newline(context) ||
            !weave_fmt_write_indent(context, indentation + 2) ||
            !weave_fmt_format_node(
                context, scan, indentation + 2, WEAVE_FMT_UNKNOWN, 0)) {
            return 0;
        }
        scan = node_next_sibling(context->tree, scan);
    }
    return weave_fmt_write_char(context, ')');
}

static int weave_fmt_emit_casted_integer(
    weave_fmt_context *context,
    int64_t value,
    weave_fmt_type target,
    size_t indentation,
    int force_inline) {
    (void)indentation;
    (void)force_inline;
    const char *type_name = weave_fmt_type_name(target);
    return type_name != NULL &&
        weave_fmt_write_cstr(context, "(cast ") &&
        weave_fmt_write_cstr(context, type_name) &&
        weave_fmt_write_char(context, ' ') &&
        weave_fmt_write_atom(context, value) &&
        weave_fmt_write_char(context, ')');
}

static int weave_fmt_prepare_function_scope(
    weave_fmt_context *context,
    int64_t list,
    size_t *saved_binding_count,
    weave_fmt_type *saved_return_type) {
    *saved_binding_count = context->binding_count;
    *saved_return_type = context->current_return_type;
    context->binding_count = 0;
    int64_t params = weave_fmt_find_clause(context, list, "params");
    int64_t returns = weave_fmt_find_clause(context, list, "returns");
    if (params == -1) {
        params = weave_fmt_nth_child(context, list, 2);
        if (params != -1 && node_kind(context->tree, params) == node_list()) {
            int64_t params_head = node_first_child(context->tree, params);
            if (params_head != -1 &&
                weave_fmt_node_text_equals(context, params_head, "type-params")) {
                params = node_next_sibling(context->tree, params);
            }
        }
    }
    int64_t return_type_node = -1;
    if (returns != -1) {
        return_type_node = weave_fmt_nth_child(context, returns, 1);
    } else if (params != -1) {
        return_type_node = node_next_sibling(context->tree, params);
    }
    context->current_return_type = weave_fmt_type_from_text(
        context, return_type_node);
    int64_t params_head = params == -1
        ? -1
        : node_first_child(context->tree, params);
    int64_t parameter = params_head != -1 &&
        weave_fmt_node_text_equals(context, params_head, "params")
        ? weave_fmt_nth_child(context, params, 1)
        : params_head;
    while (parameter != -1) {
        int64_t name = weave_fmt_nth_child(context, parameter, 0);
        int64_t type = weave_fmt_nth_child(context, parameter, 1);
        weave_fmt_add_binding(
            context,
            name,
            weave_fmt_type_from_text(context, type),
            WEAVE_FMT_BINDING_PARAM);
        parameter = node_next_sibling(context->tree, parameter);
    }
    return 1;
}

static void weave_fmt_restore_function_scope(
    weave_fmt_context *context,
    size_t saved_binding_count,
    weave_fmt_type saved_return_type) {
    context->binding_count = saved_binding_count;
    context->current_return_type = saved_return_type;
}

static int weave_fmt_emit_control_stmts(
    weave_fmt_context *context,
    int64_t body,
    int variadic,
    size_t indentation) {
    if (body == -1) return 1;
    if (variadic && weave_fmt_list_headed(context, body, "do")) {
        int64_t stmt = node_next_sibling(
            context->tree, node_first_child(context->tree, body));
        while (stmt != -1) {
            if (!weave_fmt_write_newline(context) ||
                !weave_fmt_write_indent(context, indentation) ||
                !weave_fmt_format_node(
                    context, stmt, indentation, WEAVE_FMT_UNKNOWN, 0)) {
                return 0;
            }
            stmt = node_next_sibling(context->tree, stmt);
        }
        return 1;
    }
    return weave_fmt_write_newline(context) &&
        weave_fmt_write_indent(context, indentation) &&
        weave_fmt_format_node(
            context, body, indentation, WEAVE_FMT_UNKNOWN, 0);
}

static int weave_fmt_format_control(
    weave_fmt_context *context,
    const weave_fmt_plan *plan,
    size_t indentation) {
    if (plan->virtual_head == NULL || plan->control_cond == -1) return 0;
    if (!weave_fmt_write_char(context, '(') ||
        !weave_fmt_write_cstr(context, plan->virtual_head) ||
        !weave_fmt_write_char(context, ' ') ||
        !weave_fmt_format_node(
            context,
            plan->control_cond,
            indentation + 2,
            WEAVE_FMT_BOOL,
            1)) {
        return 0;
    }
    if (strcmp(plan->virtual_head, "if") == 0) {
        if (!weave_fmt_write_newline(context) ||
            !weave_fmt_write_indent(context, indentation + 2) ||
            !weave_fmt_format_node(
                context,
                plan->control_then,
                indentation + 2,
                WEAVE_FMT_UNKNOWN,
                0)) {
            return 0;
        }
        if (plan->control_else != -1) {
            if (!weave_fmt_write_newline(context) ||
                !weave_fmt_write_indent(context, indentation + 2) ||
                !weave_fmt_format_node(
                    context,
                    plan->control_else,
                    indentation + 2,
                    WEAVE_FMT_UNKNOWN,
                    0)) {
                return 0;
            }
        }
    } else if (!weave_fmt_emit_control_stmts(
            context,
            plan->control_then,
            plan->control_variadic,
            indentation + 2)) {
        return 0;
    }
    return weave_fmt_write_char(context, ')');
}

static int weave_fmt_format_operator_child(
    weave_fmt_context *context,
    int64_t list,
    const weave_fmt_plan *plan,
    int64_t child,
    size_t actual_index,
    size_t indentation,
    int force_inline) {
    size_t operand_index = actual_index;
    if (plan->encoded_type == WEAVE_FMT_BOOL ||
        plan->encoded_type == WEAVE_FMT_PTR) {
        return weave_fmt_format_node(
            context,
            child,
            indentation,
            plan->encoded_type,
            force_inline);
    }

    int64_t left = plan->skip_name_child
        ? weave_fmt_nth_child(context, list, 2)
        : weave_fmt_nth_child(context, list, 1);
    int64_t right = plan->skip_name_child
        ? weave_fmt_nth_child(context, list, 3)
        : weave_fmt_nth_child(context, list, 2);
    weave_fmt_type left_seed = weave_fmt_seed_type(context, left);
    weave_fmt_type right_seed = weave_fmt_seed_type(context, right);
    size_t anchor = SIZE_MAX;
    if (left_seed != WEAVE_FMT_UNKNOWN) anchor = 0;
    else if (right_seed != WEAVE_FMT_UNKNOWN) anchor = 1;
    else if (plan->encoded_type != WEAVE_FMT_I32 &&
             plan->encoded_type != WEAVE_FMT_BOOL) anchor = 0;

    if (operand_index == anchor) {
        if (node_kind(context->tree, child) == node_int() &&
            plan->encoded_type != WEAVE_FMT_I32 &&
            plan->encoded_type != WEAVE_FMT_BOOL &&
            weave_fmt_cast_pair_admitted(WEAVE_FMT_I32, plan->encoded_type)) {
            return weave_fmt_emit_casted_integer(
                context,
                child,
                plan->encoded_type,
                indentation,
                force_inline);
        }
        return weave_fmt_format_node(
            context, child, indentation, WEAVE_FMT_UNKNOWN, force_inline);
    }
    return weave_fmt_format_node(
        context,
        child,
        indentation,
        plan->encoded_type,
        force_inline);
}

static int weave_fmt_format_constructor_field(
    weave_fmt_context *context,
    int64_t clause,
    const weave_fmt_struct_field *field,
    size_t indentation) {
    size_t clause_start = weave_fmt_node_start(context, clause);
    size_t clause_end = weave_fmt_node_end(context, clause);
    int64_t name = weave_fmt_nth_child(context, clause, 0);
    int64_t value = weave_fmt_nth_child(context, clause, 1);
    if (clause_start > context->source_length || clause_end == 0 ||
        name == -1 || value == -1) {
        return 0;
    }

    size_t name_start = weave_fmt_node_start(context, name);
    weave_fmt_gap head_gap = weave_fmt_scan_gap(
        context, clause_start + 1, name_start);
    if (!head_gap.valid ||
        !weave_fmt_write_indent(context, indentation) ||
        !weave_fmt_write_char(context, '(')) {
        return 0;
    }
    if (head_gap.comments != 0) {
        if (!weave_fmt_emit_gap_comments(
                context,
                clause_start + 1,
                name_start,
                indentation + 2) ||
            !weave_fmt_write_indent(context, indentation + 2)) {
            return 0;
        }
    }
    if (!weave_fmt_write_atom(context, name)) return 0;

    size_t name_end = weave_fmt_node_end(context, name);
    size_t value_start = weave_fmt_node_start(context, value);
    weave_fmt_gap value_gap = weave_fmt_scan_gap(
        context, name_end, value_start);
    if (!value_gap.valid) return 0;
    if (value_gap.comments != 0) {
        if (!weave_fmt_emit_gap_comments(
                context, name_end, value_start, indentation + 2) ||
            !weave_fmt_write_indent(context, indentation + 2)) {
            return 0;
        }
    } else if (!weave_fmt_write_char(context, ' ')) {
        return 0;
    }
    if (!weave_fmt_format_node(
            context,
            value,
            indentation + 2,
            field->type,
            value_gap.comments == 0)) {
        return 0;
    }

    size_t value_end = weave_fmt_node_end(context, value);
    weave_fmt_gap trailing = weave_fmt_scan_gap(
        context, value_end, clause_end - 1);
    if (!trailing.valid) return 0;
    if (trailing.comments != 0 &&
        (!weave_fmt_emit_gap_comments(
            context, value_end, clause_end - 1, indentation + 2) ||
         !weave_fmt_write_indent(context, indentation))) {
        return 0;
    }
    return weave_fmt_write_char(context, ')');
}

static int weave_fmt_format_constructor(
    weave_fmt_context *context,
    int64_t list,
    int64_t head,
    const weave_fmt_plan *plan,
    size_t indentation,
    weave_fmt_gap head_gap) {
    size_t list_start = weave_fmt_node_start(context, list);
    size_t list_end = weave_fmt_node_end(context, list);
    int64_t type = weave_fmt_nth_child(context, list, 1);
    if (list_start > context->source_length || list_end == 0 ||
        type == -1 || plan->structure == NULL) {
        return 0;
    }

    if (!weave_fmt_write_char(context, '(')) return 0;
    size_t head_start = weave_fmt_node_start(context, head);
    if (head_gap.comments != 0) {
        if (!weave_fmt_emit_gap_comments(
                context,
                list_start + 1,
                head_start,
                indentation + 2) ||
            !weave_fmt_write_indent(context, indentation + 2)) {
            return 0;
        }
    }
    if (!weave_fmt_write_cstr(context, "new")) return 0;

    size_t head_end = weave_fmt_node_end(context, head);
    size_t type_start = weave_fmt_node_start(context, type);
    weave_fmt_gap type_gap = weave_fmt_scan_gap(
        context, head_end, type_start);
    if (!type_gap.valid) return 0;
    if (type_gap.comments != 0) {
        if (!weave_fmt_emit_gap_comments(
                context, head_end, type_start, indentation + 2) ||
            !weave_fmt_write_indent(context, indentation + 2)) {
            return 0;
        }
    } else if (!weave_fmt_write_char(context, ' ')) {
        return 0;
    }
    if (!weave_fmt_write_atom(context, type)) return 0;

    for (size_t index = 0;
         index < plan->structure->field_count;
         ++index) {
        const weave_fmt_struct_field *field =
            &plan->structure->fields[index];
        int64_t clause = weave_fmt_constructor_clause_for_field(
            context, list, field);
        if (clause == -1) return 0;
        size_t gap_start = weave_fmt_source_gap_start_for_child(
            context, list, clause);
        size_t clause_start = weave_fmt_node_start(context, clause);
        weave_fmt_gap gap = weave_fmt_scan_gap(
            context, gap_start, clause_start);
        if (!gap.valid) return 0;
        if (gap.comments != 0) {
            if (!weave_fmt_emit_gap_comments(
                    context,
                    gap_start,
                    clause_start,
                    indentation + 2)) {
                return 0;
            }
        } else if (!weave_fmt_write_newline(context)) {
            return 0;
        }
        if (!weave_fmt_format_constructor_field(
                context, clause, field, indentation + 2)) {
            return 0;
        }
    }

    size_t trailing_start = weave_fmt_source_trailing_gap_start(
        context, list);
    weave_fmt_gap trailing = weave_fmt_scan_gap(
        context, trailing_start, list_end - 1);
    if (!trailing.valid) return 0;
    if (trailing.comments != 0) {
        if (!weave_fmt_emit_gap_comments(
                context,
                trailing_start,
                list_end - 1,
                indentation + 2) ||
            !weave_fmt_write_indent(context, indentation)) {
            return 0;
        }
    } else if (plan->structure->field_count != 0 &&
               (!weave_fmt_write_newline(context) ||
                !weave_fmt_write_indent(context, indentation))) {
        return 0;
    }
    return weave_fmt_write_char(context, ')');
}

