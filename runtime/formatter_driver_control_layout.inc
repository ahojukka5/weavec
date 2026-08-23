static int weave_fmt_measure_control_part(
    weave_fmt_context *context,
    int64_t node,
    weave_fmt_type expected,
    size_t *width,
    size_t limit) {
    if (node == -1 || *width >= limit) return 0;
    ++*width;
    int measured = weave_fmt_measure_node(
        context, node, expected, limit - *width);
    if (measured < 0 || (size_t)measured > limit - *width) return 0;
    *width += (size_t)measured;
    return 1;
}

static int weave_fmt_control_fits_inline(
    weave_fmt_context *context,
    const weave_fmt_plan *plan,
    size_t indentation) {
    if (plan->virtual_head == NULL || plan->control_cond == -1) return 0;
    size_t limit = weave_fmt_column_budget(indentation);
    size_t width = 1;
    if (!weave_fmt_measure_virtual(plan->virtual_head, &width, limit) ||
        !weave_fmt_measure_control_part(
            context, plan->control_cond, WEAVE_FMT_BOOL, &width, limit)) {
        return 0;
    }

    if (strcmp(plan->virtual_head, "if") == 0) {
        if (!weave_fmt_measure_control_part(
                context,
                plan->control_then,
                WEAVE_FMT_UNKNOWN,
                &width,
                limit)) {
            return 0;
        }
        if (plan->control_else != -1 &&
            !weave_fmt_measure_control_part(
                context,
                plan->control_else,
                WEAVE_FMT_UNKNOWN,
                &width,
                limit)) {
            return 0;
        }
    } else if (plan->control_variadic) {
        int64_t stmt = plan->control_then;
        while (stmt != -1) {
            if (!weave_fmt_measure_control_part(
                    context, stmt, WEAVE_FMT_UNKNOWN, &width, limit)) {
                return 0;
            }
            stmt = node_next_sibling(context->tree, stmt);
        }
    } else if (!weave_fmt_measure_control_part(
            context,
            plan->control_then,
            WEAVE_FMT_UNKNOWN,
            &width,
            limit)) {
        return 0;
    }

    return width < limit;
}

static int weave_fmt_format_control_inline_part(
    weave_fmt_context *context,
    int64_t node,
    size_t indentation,
    weave_fmt_type expected) {
    return weave_fmt_write_char(context, ' ') &&
        weave_fmt_format_node(context, node, indentation + 2, expected, 1);
}

static int weave_fmt_format_control_canonical(
    weave_fmt_context *context,
    const weave_fmt_plan *plan,
    size_t indentation) {
    if (plan->virtual_head == NULL || plan->control_cond == -1) return 0;
    int inline_mode = weave_fmt_control_fits_inline(context, plan, indentation);

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

    if (inline_mode) {
        if (strcmp(plan->virtual_head, "if") == 0) {
            if (!weave_fmt_format_control_inline_part(
                    context,
                    plan->control_then,
                    indentation,
                    WEAVE_FMT_UNKNOWN)) {
                return 0;
            }
            if (plan->control_else != -1 &&
                !weave_fmt_format_control_inline_part(
                    context,
                    plan->control_else,
                    indentation,
                    WEAVE_FMT_UNKNOWN)) {
                return 0;
            }
        } else if (plan->control_variadic) {
            int64_t stmt = plan->control_then;
            while (stmt != -1) {
                if (!weave_fmt_format_control_inline_part(
                        context, stmt, indentation, WEAVE_FMT_UNKNOWN)) {
                    return 0;
                }
                stmt = node_next_sibling(context->tree, stmt);
            }
        } else if (!weave_fmt_format_control_inline_part(
                context,
                plan->control_then,
                indentation,
                WEAVE_FMT_UNKNOWN)) {
            return 0;
        }
        return weave_fmt_write_char(context, ')');
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
