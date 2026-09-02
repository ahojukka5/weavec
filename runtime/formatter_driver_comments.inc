// Canonical layout for the reserved `(comment STRING...)` surface form.
//
// A comment is an explicit tree node, not recovered trivia, so the printer
// serializes it structurally. It obeys the generic complete-form rule: one
// inline line when the whole form fits the 80-column budget at its current
// indentation, otherwise the head alone followed by one string literal per
// line. The generic list printer keeps a run of leading scalar children on the
// head line, which would make the multiline shape depend on how many strings
// happen to fit; a comment uses this dedicated shape instead so both renderings
// are byte-idempotent.

static int weave_fmt_is_comment_form(
    weave_fmt_context *context,
    int64_t list) {
    if (list == -1 || node_kind(context->tree, list) != node_list()) return 0;
    int64_t head = node_first_child(context->tree, list);
    if (head == -1 || node_kind(context->tree, head) != node_ident()) return 0;
    if (!weave_fmt_node_text_equals(context, head, "comment")) return 0;
    int64_t child = node_next_sibling(context->tree, head);
    if (child == -1) return 0;
    while (child != -1) {
        if (node_kind(context->tree, child) != node_string()) return 0;
        child = node_next_sibling(context->tree, child);
    }
    // A malformed comment, or one carrying semicolon comments in its gaps,
    // stays with the generic printer so formatting neither conceals the
    // compiler diagnostic nor drops recovered source.
    return !weave_fmt_list_has_comments(context, list);
}

static int weave_fmt_comment_fits_inline(
    weave_fmt_context *context,
    int64_t list,
    size_t indentation) {
    return weave_fmt_measure_list(
        context,
        list,
        WEAVE_FMT_UNKNOWN,
        weave_fmt_column_budget(indentation)) >= 0;
}

static int weave_fmt_format_comment(
    weave_fmt_context *context,
    int64_t list,
    int64_t head,
    size_t indentation,
    int force_inline) {
    int inline_mode = force_inline ||
        weave_fmt_comment_fits_inline(context, list, indentation);
    if (!weave_fmt_write_char(context, '(') ||
        !weave_fmt_write_atom(context, head)) {
        return 0;
    }
    int64_t text = node_next_sibling(context->tree, head);
    while (text != -1) {
        if (inline_mode) {
            if (!weave_fmt_write_char(context, ' ')) return 0;
        } else if (!weave_fmt_write_newline(context) ||
                   !weave_fmt_write_indent(context, indentation + 2)) {
            return 0;
        }
        if (!weave_fmt_write_atom(context, text)) return 0;
        text = node_next_sibling(context->tree, text);
    }
    return weave_fmt_write_char(context, ')');
}
