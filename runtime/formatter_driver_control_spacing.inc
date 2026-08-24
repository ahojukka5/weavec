static int weave_fmt_spacing_node_fits_inline(
    weave_fmt_context *context,
    int64_t node,
    size_t indentation) {
    if (node == -1) return 1;
    if (node_kind(context->tree, node) == node_list()) {
        /* Extern declarations are rendered by the canonical function printer as
         * one signature line. Measuring their pre-normalization tree is not
         * stable because legacy (params ...)/(returns ...) clauses become the
         * compact anonymous parameter list after the first formatter pass. */
        if (weave_fmt_list_headed(context, node, "extern")) return 1;
        weave_fmt_plan plan;
        if (weave_fmt_plan_list(context, node, &plan) &&
            plan.kind == WEAVE_FMT_PLAN_CONTROL) {
            return weave_fmt_control_fits_inline(
                context, &plan, indentation);
        }
    }
    return weave_fmt_measure_node(
        context,
        node,
        WEAVE_FMT_UNKNOWN,
        weave_fmt_column_budget(indentation)) >= 0;
}

static int weave_fmt_emit_control_stmt_separator(
    weave_fmt_context *context,
    int blank_line) {
    if (!weave_fmt_write_newline(context)) return 0;
    if (blank_line && !weave_fmt_write_char(context, '\n')) return 0;
    return 1;
}

static int weave_fmt_emit_control_stmts(
    weave_fmt_context *context,
    int64_t body,
    int variadic,
    size_t indentation) {
    if (body == -1) return 1;
    if (variadic) {
        int64_t stmt = body;
        int first = 1;
        int previous_multiline = 0;
        while (stmt != -1) {
            int current_multiline = !weave_fmt_spacing_node_fits_inline(
                context, stmt, indentation);
            if (!weave_fmt_emit_control_stmt_separator(
                    context,
                    !first && (previous_multiline || current_multiline)) ||
                !weave_fmt_write_indent(context, indentation) ||
                !weave_fmt_format_node(
                    context, stmt, indentation, WEAVE_FMT_UNKNOWN, 0)) {
                return 0;
            }
            first = 0;
            previous_multiline = current_multiline;
            stmt = node_next_sibling(context->tree, stmt);
        }
        return 1;
    }
    return weave_fmt_write_newline(context) &&
        weave_fmt_write_indent(context, indentation) &&
        weave_fmt_format_node(
            context, body, indentation, WEAVE_FMT_UNKNOWN, 0);
}
