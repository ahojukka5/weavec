static int weave_fmt_format_list(
    weave_fmt_context *context,
    int64_t list,
    size_t indentation,
    weave_fmt_type expected,
    int force_inline) {
    size_t list_start = weave_fmt_node_start(context, list);
    size_t list_end = weave_fmt_node_end(context, list);
    int64_t head = node_first_child(context->tree, list);
    if (list_start > context->source_length || list_end == 0) {
        weave_fmt_fail(context);
        return 0;
    }
    if (head == -1 || node_kind(context->tree, head) != node_ident()) {
        int formatted = weave_fmt_format_anonymous_list(
            context, list, indentation, force_inline);
        if (!formatted) weave_fmt_fail(context);
        return formatted;
    }

    size_t head_start = weave_fmt_node_start(context, head);
    weave_fmt_gap head_gap = weave_fmt_scan_gap(
        context, list_start + 1, head_start);
    if (!head_gap.valid || !weave_fmt_write_indent(context, indentation)) {
        weave_fmt_fail(context);
        return 0;
    }

    int64_t access_name = -1;
    if (weave_fmt_can_unwrap_access(context, list, head, &access_name)) {
        return weave_fmt_write_atom(context, access_name);
    }
    int64_t replacement_value = -1;
    weave_fmt_type cast_target = WEAVE_FMT_UNKNOWN;
    const char *literal = NULL;
    if (weave_fmt_constant_replacement(
            context,
            list,
            head,
            expected,
            &replacement_value,
            &cast_target,
            &literal)) {
        if (literal != NULL) return weave_fmt_write_cstr(context, literal);
        if (cast_target != WEAVE_FMT_UNKNOWN) {
            return weave_fmt_emit_casted_integer(
                context,
                replacement_value,
                cast_target,
                indentation,
                force_inline);
        }
        return weave_fmt_write_atom(context, replacement_value);
    }

    size_t saved_binding_count = context->binding_count;
    weave_fmt_type saved_return_type = context->current_return_type;
    int function_scope = weave_fmt_node_text_equals(context, head, "fn") ||
        weave_fmt_node_text_equals(context, head, "entry");
    if (function_scope) {
        weave_fmt_prepare_function_scope(
            context, list, &saved_binding_count, &saved_return_type);
    }
    if (function_scope ||
        weave_fmt_node_text_equals(context, head, "extern")) {
        int formatted = weave_fmt_format_function(
            context, list, head, indentation);
        if (function_scope) {
            weave_fmt_restore_function_scope(
                context, saved_binding_count, saved_return_type);
        }
        if (!formatted) weave_fmt_fail(context);
        return formatted;
    }

    weave_fmt_plan plan;
    if (!weave_fmt_plan_list(context, list, &plan)) {
        if (function_scope) weave_fmt_restore_function_scope(
            context, saved_binding_count, saved_return_type);
        weave_fmt_fail(context);
        return 0;
    }
    if (plan.kind == WEAVE_FMT_PLAN_CONSTRUCTOR) {
        int formatted = weave_fmt_format_constructor(
            context, list, head, &plan, indentation, head_gap);
        if (function_scope) {
            weave_fmt_restore_function_scope(
                context, saved_binding_count, saved_return_type);
        }
        if (!formatted) weave_fmt_fail(context);
        return formatted;
    }
    if (plan.kind == WEAVE_FMT_PLAN_CONTROL) {
        int formatted = weave_fmt_format_control(
            context, &plan, indentation);
        if (function_scope) {
            weave_fmt_restore_function_scope(
                context, saved_binding_count, saved_return_type);
        }
        if (!formatted) weave_fmt_fail(context);
        return formatted;
    }

    int measured = weave_fmt_measure_list(
        context,
        list,
        expected,
        weave_fmt_column_budget(indentation));
    int inline_mode = head_gap.comments == 0 &&
        (force_inline || measured >= 0);

    if (!weave_fmt_write_char(context, '(')) goto failure;
    if (head_gap.comments != 0) {
        if (!weave_fmt_emit_gap_comments(
                context, list_start + 1, head_start, indentation + 2) ||
            !weave_fmt_write_indent(context, indentation + 2)) {
            goto failure;
        }
    }
    if (plan.kind == WEAVE_FMT_PLAN_CALL) {
        if (plan.callee_node == -1 ||
            !weave_fmt_write_atom(context, plan.callee_node)) {
            goto failure;
        }
    } else if (plan.kind == WEAVE_FMT_PLAN_NORMAL) {
        if (!weave_fmt_write_atom(context, head)) goto failure;
    } else if (!weave_fmt_write_cstr(context, plan.virtual_head)) {
        goto failure;
    }
    if (plan.virtual_second != NULL) {
        if (!weave_fmt_write_char(context, ' ') ||
            !weave_fmt_write_cstr(context, plan.virtual_second)) {
            goto failure;
        }
    }

    int64_t child = node_next_sibling(context->tree, head);
    size_t cursor = weave_fmt_node_end(context, head);
    if (plan.skip_name_child && child != -1) {
        cursor = weave_fmt_node_end(context, child);
        child = node_next_sibling(context->tree, child);
    }
    size_t actual_index = 0;
    int multiline_started = head_gap.comments != 0;
    while (child != -1) {
        size_t child_start = weave_fmt_node_start(context, child);
        weave_fmt_gap gap = weave_fmt_scan_gap(context, cursor, child_start);
        if (!gap.valid) goto failure;
        int child_measure = weave_fmt_measure_node(
            context,
            child,
            weave_fmt_expected_for_child(
                context, list, &plan, head, actual_index),
            weave_fmt_column_budget(indentation + 2));
        int scalar_prefix = child_measure >= 0 &&
            node_kind(context->tree, child) != node_list();
        if (gap.comments != 0) {
            if (!weave_fmt_emit_gap_comments(
                    context, cursor, child_start, indentation + 2)) {
                goto failure;
            }
            multiline_started = 1;
        }
        if (inline_mode || (!multiline_started && scalar_prefix && gap.comments == 0)) {
            if (!weave_fmt_write_char(context, ' ')) goto failure;
        } else {
            if (!weave_fmt_write_newline(context)) goto failure;
            multiline_started = 1;
        }
        int child_inline = inline_mode || (!multiline_started && scalar_prefix);
        int ok;
        if (plan.kind == WEAVE_FMT_PLAN_OPERATOR) {
            ok = weave_fmt_format_operator_child(
                context,
                list,
                &plan,
                child,
                actual_index,
                indentation + 2,
                child_inline);
        } else {
            ok = weave_fmt_format_node(
                context,
                child,
                indentation + 2,
                weave_fmt_expected_for_child(
                    context, list, &plan, head, actual_index),
                child_inline);
        }
        if (!ok) goto failure;
        if (node_kind(context->tree, child) == node_list()) {
            multiline_started = !inline_mode;
        }
        cursor = weave_fmt_node_end(context, child);
        if (cursor == 0) goto failure;
        ++actual_index;
        child = node_next_sibling(context->tree, child);
    }

    weave_fmt_gap trailing = weave_fmt_scan_gap(context, cursor, list_end - 1);
    if (!trailing.valid) goto failure;
    if (trailing.comments != 0) {
        if (!weave_fmt_emit_gap_comments(
                context, cursor, list_end - 1, indentation + 2) ||
            !weave_fmt_write_indent(context, indentation)) {
            goto failure;
        }
    }
    if (!weave_fmt_write_char(context, ')')) goto failure;

    if (weave_fmt_node_text_equals(context, head, "let") &&
        weave_fmt_child_count(context, list) == 4) {
        weave_fmt_add_binding(
            context,
            weave_fmt_nth_child(context, list, 1),
            weave_fmt_type_from_text(
                context, weave_fmt_nth_child(context, list, 2)),
            WEAVE_FMT_BINDING_LOCAL);
    }
    if (function_scope) {
        weave_fmt_restore_function_scope(
            context, saved_binding_count, saved_return_type);
    }
    return 1;

failure:
    if (function_scope) {
        weave_fmt_restore_function_scope(
            context, saved_binding_count, saved_return_type);
    }
    weave_fmt_fail(context);
    return 0;
}

static int weave_fmt_format_node(
    weave_fmt_context *context,
    int64_t node,
    size_t indentation,
    weave_fmt_type expected,
    int force_inline) {
    if (!weave_fmt_write_indent(context, indentation)) return 0;
    if (node_kind(context->tree, node) == node_list()) {
        return weave_fmt_format_list(
            context, node, indentation, expected, force_inline);
    }
    return weave_fmt_write_atom(context, node);
}

static int weave_fmt_format_document(
