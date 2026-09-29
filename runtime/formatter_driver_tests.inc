// Surface checks and canonical tag order for experimental test forms.
// The harness and `weavec test` are a later slice. This pass only admits the
// declaration shape the formatter and capability registry publish.

static int weave_fmt_portable_identifier(
    const unsigned char *text,
    size_t length) {
    if (length == 0) return 0;
    unsigned char first = text[0];
    if (!((first >= 'A' && first <= 'Z') || (first >= 'a' && first <= 'z'))) {
        return 0;
    }
    for (size_t index = 1; index < length; ++index) {
        unsigned char ch = text[index];
        int admitted = (ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z') ||
            (ch >= '0' && ch <= '9') || ch == '_' || ch == '-';
        if (!admitted) return 0;
    }
    return 1;
}

static int weave_fmt_node_portable_identifier(
    const weave_fmt_context *context,
    int64_t node) {
    if (node == -1 || node_kind(context->tree, node) != node_ident()) return 0;
    int64_t start = node_text_start(context->tree, node);
    int64_t length = node_text_len(context->tree, node);
    if (start < 0 || length <= 0) return 0;
    if ((size_t)start + (size_t)length > context->source_length) return 0;
    return weave_fmt_portable_identifier(
        context->source + (size_t)start, (size_t)length);
}

static int weave_fmt_same_text(
    const weave_fmt_context *context,
    int64_t left,
    int64_t right) {
    int64_t left_start = node_text_start(context->tree, left);
    int64_t left_length = node_text_len(context->tree, left);
    int64_t right_start = node_text_start(context->tree, right);
    int64_t right_length = node_text_len(context->tree, right);
    if (left_start < 0 || right_start < 0 || left_length != right_length ||
        left_length <= 0) {
        return 0;
    }
    return memcmp(
        context->source + (size_t)left_start,
        context->source + (size_t)right_start,
        (size_t)left_length) == 0;
}

static void weave_fmt_report_test(
    weave_fmt_context *context,
    int64_t node,
    const char *code,
    const char *message) {
    if (context->surface_rejected) return;
    int64_t offset = node_text_start(context->tree, node);
    if (offset < 0) offset = 0;
    long long line = 1;
    long long column = 1;
    for (int64_t index = 0; index < offset &&
         (size_t)index < context->source_length; ++index) {
        unsigned char ch = context->source[index];
        if (ch == '\n') {
            ++line;
            column = 1;
            continue;
        }
        if (ch < 128 || ch >= 192) ++column;
    }
    const char *path = context->input_path != NULL
        ? context->input_path : "<source>";
    fprintf(stderr, "weavec: error: %s:%lld:%lld: %s [%s]\n",
        path, line, column, message, code);
    context->surface_rejected = 1;
}

static void weave_fmt_check_tags(
    weave_fmt_context *context,
    int64_t tags) {
    int64_t head = node_first_child(context->tree, tags);
    int64_t tag = head == -1 ? -1 : node_next_sibling(context->tree, head);
    if (tag == -1) {
        weave_fmt_report_test(
            context, tags, "test.malformed-name",
            "test tag is not a portable identifier");
        return;
    }
    while (tag != -1) {
        if (!weave_fmt_node_portable_identifier(context, tag)) {
            weave_fmt_report_test(
                context, tag, "test.malformed-name",
                "test tag is not a portable identifier");
            return;
        }
        int64_t earlier = node_next_sibling(context->tree, head);
        while (earlier != tag) {
            if (weave_fmt_same_text(context, earlier, tag)) {
                weave_fmt_report_test(
                    context, tag, "test.duplicate-tag", "duplicate test tag");
                return;
            }
            earlier = node_next_sibling(context->tree, earlier);
        }
        tag = node_next_sibling(context->tree, tag);
    }
}

static void weave_fmt_check_test_form(
    weave_fmt_context *context,
    int64_t test,
    int allowed) {
    if (!allowed) {
        weave_fmt_report_test(
            context, test, "test.nested",
            "test declaration is nested");
        return;
    }
    int64_t name = weave_fmt_nth_child(context, test, 1);
    if (!weave_fmt_node_portable_identifier(context, name)) {
        int64_t span = name == -1 ? test : name;
        weave_fmt_report_test(
            context, span, "test.malformed-name",
            "test name is not a portable identifier");
        return;
    }
    int saw_tags = 0;
    int64_t child = node_next_sibling(
        context->tree, node_first_child(context->tree, test));
    child = child == -1 ? -1 : node_next_sibling(context->tree, child);
    while (child != -1) {
        if (node_kind(context->tree, child) == node_list() &&
            weave_fmt_node_text_equals(
                context, node_first_child(context->tree, child), "tags")) {
            if (saw_tags) {
                weave_fmt_report_test(
                    context, child, "test.duplicate-tag",
                    "a test has more than one tags clause");
                return;
            }
            saw_tags = 1;
            weave_fmt_check_tags(context, child);
            if (context->surface_rejected) return;
        }
        child = node_next_sibling(context->tree, child);
    }
}

static void weave_fmt_check_test_tree(
    weave_fmt_context *context,
    int64_t node,
    int allow_test) {
    if (context->surface_rejected || node == -1) return;
    if (node_kind(context->tree, node) != node_list()) return;
    int64_t head = node_first_child(context->tree, node);
    int is_test = weave_fmt_node_text_equals(context, head, "test");
    if (is_test) weave_fmt_check_test_form(context, node, allow_test);
    int child_allows = !is_test &&
        (weave_fmt_node_text_equals(context, head, "program") ||
         weave_fmt_node_text_equals(context, head, "module"));
    int64_t child = head;
    while (child != -1 && !context->surface_rejected) {
        weave_fmt_check_test_tree(context, child, child_allows);
        child = node_next_sibling(context->tree, child);
    }
}

static int weave_fmt_tag_before(
    const weave_fmt_context *context,
    int64_t left,
    int64_t right) {
    int64_t left_start = node_text_start(context->tree, left);
    int64_t left_length = node_text_len(context->tree, left);
    int64_t right_start = node_text_start(context->tree, right);
    int64_t right_length = node_text_len(context->tree, right);
    size_t shared = (size_t)(left_length < right_length
        ? left_length : right_length);
    int order = memcmp(
        context->source + (size_t)left_start,
        context->source + (size_t)right_start,
        shared);
    if (order < 0) return 1;
    if (order > 0) return 0;
    return left_length < right_length;
}

static int weave_fmt_format_tags(
    weave_fmt_context *context,
    int64_t list,
    int64_t head,
    size_t indentation) {
    size_t count = 0;
    int64_t child = node_next_sibling(context->tree, head);
    while (child != -1) {
        ++count;
        child = node_next_sibling(context->tree, child);
    }
    int64_t *ordered = NULL;
    if (count != 0) {
        ordered = malloc(count * sizeof(*ordered));
        if (ordered == NULL) {
            context->semantic_overflow = 1;
            return 0;
        }
        size_t index = 0;
        child = node_next_sibling(context->tree, head);
        while (child != -1 && index < count) {
            ordered[index++] = child;
            child = node_next_sibling(context->tree, child);
        }
        for (size_t index = 1; index < count; ++index) {
            int64_t current = ordered[index];
            size_t slot = index;
            while (slot > 0 &&
                   weave_fmt_tag_before(context, current, ordered[slot - 1])) {
                ordered[slot] = ordered[slot - 1];
                --slot;
            }
            ordered[slot] = current;
        }
    }
    if (!weave_fmt_write_char(context, '(') ||
        !weave_fmt_write_atom(context, head)) {
        free(ordered);
        return 0;
    }
    size_t cursor = weave_fmt_node_end(context, head);
    child = node_next_sibling(context->tree, head);
    int comments = 0;
    while (child != -1) {
        size_t child_start = weave_fmt_node_start(context, child);
        weave_fmt_gap gap = weave_fmt_scan_gap(context, cursor, child_start);
        if (!gap.valid) {
            free(ordered);
            return 0;
        }
        if (gap.comments != 0) {
            comments = 1;
            if (!weave_fmt_emit_gap_comments(
                    context, cursor, child_start, indentation + 2)) {
                free(ordered);
                return 0;
            }
        }
        cursor = weave_fmt_node_end(context, child);
        child = node_next_sibling(context->tree, child);
    }
    for (size_t index = 0; index < count; ++index) {
        if (comments) {
            if (!weave_fmt_write_newline(context) ||
                !weave_fmt_write_indent(context, indentation + 2)) {
                free(ordered);
                return 0;
            }
        } else if (!weave_fmt_write_char(context, ' ')) {
            free(ordered);
            return 0;
        }
        if (!weave_fmt_write_atom(context, ordered[index])) {
            free(ordered);
            return 0;
        }
    }
    free(ordered);
    return weave_fmt_write_char(context, ')');
}
