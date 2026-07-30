static void weave_fmt_add_signature(
    weave_fmt_context *context,
    int64_t declaration) {
    int64_t name = weave_fmt_nth_child(context, declaration, 1);
    int64_t params = weave_fmt_nth_child(context, declaration, 2);
    int64_t returns = weave_fmt_nth_child(context, declaration, 3);
    if (name == -1 || params == -1 || returns == -1 ||
        node_kind(context->tree, name) != node_ident()) {
        return;
    }
    int64_t name_start_raw = node_text_start(context->tree, name);
    int64_t name_length_raw = node_text_len(context->tree, name);
    if (name_start_raw < 0 || name_length_raw <= 0) return;
    size_t name_start = (size_t)name_start_raw;
    size_t name_length = (size_t)name_length_raw;
    int64_t return_type_node = weave_fmt_nth_child(context, returns, 1);
    weave_fmt_type return_type = weave_fmt_type_from_text(
        context, return_type_node);

    size_t parameter_count = 0;
    int64_t parameter = weave_fmt_nth_child(context, params, 1);
    while (parameter != -1) {
        ++parameter_count;
        parameter = node_next_sibling(context->tree, parameter);
    }
    weave_fmt_type *parameter_types = NULL;
    if (parameter_count != 0) {
        parameter_types = calloc(parameter_count, sizeof(*parameter_types));
        if (parameter_types == NULL) {
            context->semantic_overflow = 1;
            return;
        }
        parameter = weave_fmt_nth_child(context, params, 1);
        size_t parameter_index = 0;
        while (parameter != -1 && parameter_index < parameter_count) {
            int64_t type_node = weave_fmt_nth_child(context, parameter, 1);
            parameter_types[parameter_index++] = weave_fmt_type_from_text(
                context, type_node);
            parameter = node_next_sibling(context->tree, parameter);
        }
    }

    for (size_t index = 0; index < context->signature_count; ++index) {
        weave_fmt_signature *existing = &context->signatures[index];
        if (weave_fmt_name_spans_equal(
                context,
                existing->name_start,
                existing->name_length,
                name_start,
                name_length)) {
            existing->ambiguous = 1;
            free(parameter_types);
            return;
        }
    }
    if (!weave_fmt_reserve_signatures(
            context, context->signature_count + 1)) {
        free(parameter_types);
        return;
    }
    context->signatures[context->signature_count++] = (weave_fmt_signature){
        .name_start = name_start,
        .name_length = name_length,
        .return_type = return_type,
        .parameters = parameter_types,
        .parameter_count = parameter_count,
    };
}

static void weave_fmt_collect_signatures(
    weave_fmt_context *context,
    int64_t root) {
    int64_t child = node_first_child(context->tree, root);
    while (child != -1) {
        if (node_kind(context->tree, child) == node_list()) {
            int64_t head = node_first_child(context->tree, child);
            if (head != -1 &&
                (weave_fmt_node_text_equals(context, head, "fn") ||
                 weave_fmt_node_text_equals(context, head, "entry") ||
                 weave_fmt_node_text_equals(context, head, "extern"))) {
                weave_fmt_add_signature(context, child);
            }
        }
        child = node_next_sibling(context->tree, child);
    }
}

static const weave_fmt_signature *weave_fmt_lookup_signature_node(
    const weave_fmt_context *context,
    int64_t name) {
    if (name == -1 || node_kind(context->tree, name) != node_ident()) return NULL;
    int64_t start_raw = node_text_start(context->tree, name);
    int64_t length_raw = node_text_len(context->tree, name);
    if (start_raw < 0 || length_raw <= 0) return NULL;
    size_t start = (size_t)start_raw;
    size_t length = (size_t)length_raw;
    const weave_fmt_signature *result = NULL;
    for (size_t index = 0; index < context->signature_count; ++index) {
        const weave_fmt_signature *candidate = &context->signatures[index];
        if (!candidate->ambiguous && weave_fmt_name_spans_equal(
                context,
                candidate->name_start,
                candidate->name_length,
                start,
                length)) {
            if (result != NULL) return NULL;
            result = candidate;
        }
    }
    return result;
}

