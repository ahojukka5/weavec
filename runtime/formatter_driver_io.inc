static void weave_fmt_fail(weave_fmt_context *context) {
    context->writer.failed = 1;
}

static int weave_fmt_write_bytes(
    weave_fmt_context *context,
    const void *data,
    size_t length) {
    if (context->writer.failed) {
        return 0;
    }
    if (length != 0 &&
        fwrite(data, 1, length, context->writer.stream) != length) {
        weave_fmt_fail(context);
        return 0;
    }
    if (length != 0) {
        const unsigned char *bytes = data;
        context->writer.at_line_start = bytes[length - 1] == '\n';
    }
    return 1;
}

static int weave_fmt_write_cstr(
    weave_fmt_context *context,
    const char *text) {
    return weave_fmt_write_bytes(context, text, strlen(text));
}

static int weave_fmt_write_char(weave_fmt_context *context, int value) {
    unsigned char byte = (unsigned char)value;
    return weave_fmt_write_bytes(context, &byte, 1);
}

static int weave_fmt_write_indent(
    weave_fmt_context *context,
    size_t indentation) {
    if (!context->writer.at_line_start) {
        return 1;
    }
    for (size_t index = 0; index < indentation; ++index) {
        if (!weave_fmt_write_char(context, ' ')) {
            return 0;
        }
    }
    return 1;
}

static int weave_fmt_write_newline(weave_fmt_context *context) {
    if (context->writer.at_line_start) {
        return 1;
    }
    return weave_fmt_write_char(context, '\n');
}

static int weave_fmt_node_text_equals(
    const weave_fmt_context *context,
    int64_t node,
    const char *text) {
    int64_t start = node_text_start(context->tree, node);
    int64_t length = node_text_len(context->tree, node);
    size_t expected = strlen(text);
    if (start < 0 || length < 0 || (uint64_t)start > context->source_length ||
        (uint64_t)length > context->source_length - (size_t)start ||
        (size_t)length != expected) {
        return 0;
    }
    return memcmp(context->source + (size_t)start, text, expected) == 0;
}

static int64_t weave_fmt_find_clause(
    const weave_fmt_context *context,
    int64_t list,
    const char *head) {
    int64_t child = node_first_child(context->tree, list);
    while (child != -1) {
        if (node_kind(context->tree, child) == node_list()) {
            int64_t child_head = node_first_child(context->tree, child);
            if (weave_fmt_node_text_equals(context, child_head, head)) {
                return child;
            }
        }
        child = node_next_sibling(context->tree, child);
    }
    return -1;
}

static int64_t weave_fmt_nth_child(
    const weave_fmt_context *context,
    int64_t list,
    size_t index) {
    int64_t child = node_first_child(context->tree, list);
    while (child != -1 && index != 0) {
        child = node_next_sibling(context->tree, child);
        --index;
    }
    return child;
}

static size_t weave_fmt_child_count(
    const weave_fmt_context *context,
    int64_t list) {
    size_t count = 0;
    int64_t child = node_first_child(context->tree, list);
    while (child != -1) {
        ++count;
        child = node_next_sibling(context->tree, child);
    }
    return count;
}

static size_t weave_fmt_list_end(
    const weave_fmt_context *context,
    size_t start) {
    if (start >= context->source_length || context->source[start] != '(') {
        return 0;
    }
    size_t depth = 0;
    int in_string = 0;
    int escaped = 0;
    int in_comment = 0;
    for (size_t index = start; index < context->source_length; ++index) {
        unsigned char ch = context->source[index];
        if (in_comment) {
            if (ch == '\n') {
                in_comment = 0;
            }
            continue;
        }
        if (in_string) {
            if (in_string == 3) {
                if (ch == '"' && index + 2 < context->source_length &&
                    context->source[index + 1] == '"' &&
                    context->source[index + 2] == '"') {
                    index += 2;
                    in_string = 0;
                }
                continue;
            }
            if (in_string == 2) {
                if (ch == '"') {
                    in_string = 0;
                }
                continue;
            }
            if (escaped) {
                escaped = 0;
            } else if (ch == '\\') {
                escaped = 1;
            } else if (ch == '"') {
                in_string = 0;
            }
            continue;
        }
        if (ch == ';') {
            in_comment = 1;
        } else if (ch == '#' && index + 1 < context->source_length &&
                   context->source[index + 1] == '"') {
            if (index + 3 < context->source_length &&
                context->source[index + 2] == '"' &&
                context->source[index + 3] == '"') {
                in_string = 3;
                index += 3;
            } else {
                in_string = 2;
                index += 1;
            }
        } else if (ch == '"') {
            if (index + 2 < context->source_length &&
                context->source[index + 1] == '"' &&
                context->source[index + 2] == '"') {
                in_string = 3;
                index += 2;
            } else {
                in_string = 1;
            }
        } else if (ch == '(') {
            ++depth;
        } else if (ch == ')') {
            if (depth == 0) {
                return 0;
            }
            --depth;
            if (depth == 0) {
                return index + 1;
            }
        }
    }
    return 0;
}

static size_t weave_fmt_node_start(
    const weave_fmt_context *context,
    int64_t node) {
    int64_t start = node_text_start(context->tree, node);
    if (start < 0 || (uint64_t)start > context->source_length) {
        return context->source_length + 1;
    }
    if (node_kind(context->tree, node) == node_string() && start > 0) {
        if (start >= 4 &&
            context->source[start - 4] == '#' &&
            context->source[start - 3] == '"' &&
            context->source[start - 2] == '"' &&
            context->source[start - 1] == '"') {
            return start - 4;
        }
        if (start >= 3 &&
            context->source[start - 3] == '"' &&
            context->source[start - 2] == '"' &&
            context->source[start - 1] == '"') {
            return start - 3;
        }
        if (start >= 2 &&
            context->source[start - 2] == '#' &&
            context->source[start - 1] == '"') {
            return start - 2;
        }
        if (context->source[start - 1] == '"') {
            return start - 1;
        }
    }
    return (size_t)start;
}

static size_t weave_fmt_node_end(
    const weave_fmt_context *context,
    int64_t node) {
    int32_t kind = node_kind(context->tree, node);
    size_t start = weave_fmt_node_start(context, node);
    if (start > context->source_length) {
        return 0;
    }
    if (kind == node_list()) {
        return weave_fmt_list_end(context, start);
    }
    int64_t text_start = node_text_start(context->tree, node);
    int64_t text_length = node_text_len(context->tree, node);
    if (text_start < 0 || text_length < 0 ||
        (uint64_t)text_start > context->source_length ||
        (uint64_t)text_length > context->source_length - (size_t)text_start) {
        return 0;
    }
    size_t end = (size_t)text_start + (size_t)text_length;
    if (kind == node_string() && end < context->source_length &&
        context->source[end] == '"') {
        int64_t style = node_value(context->tree, node);
        if ((style == 2 || style == 3) &&
            end + 2 < context->source_length &&
            context->source[end + 1] == '"' &&
            context->source[end + 2] == '"') {
            end += 3;
        } else {
            ++end;
        }
    }
    return end;
}

typedef struct weave_fmt_gap {
    size_t comments;
    int valid;
} weave_fmt_gap;

