static int weave_fmt_reserve_structs(
    weave_fmt_context *context,
    size_t needed) {
    if (needed <= context->struct_capacity) return 1;
    size_t capacity = context->struct_capacity == 0
        ? 8 : context->struct_capacity * 2;
    while (capacity < needed) capacity *= 2;
    weave_fmt_struct *updated = realloc(
        context->structs, capacity * sizeof(*updated));
    if (updated == NULL) {
        context->semantic_overflow = 1;
        return 0;
    }
    context->structs = updated;
    context->struct_capacity = capacity;
    return 1;
}

static int weave_fmt_node_name_span(
    const weave_fmt_context *context,
    int64_t node,
    size_t *start_out,
    size_t *length_out) {
    if (node == -1 || node_kind(context->tree, node) != node_ident()) {
        return 0;
    }
    int64_t start = node_text_start(context->tree, node);
    int64_t length = node_text_len(context->tree, node);
    if (start < 0 || length <= 0 ||
        (uint64_t)start > context->source_length ||
        (uint64_t)length > context->source_length - (size_t)start) {
        return 0;
    }
    *start_out = (size_t)start;
    *length_out = (size_t)length;
    return 1;
}

static int weave_fmt_struct_field_equals_node(
    const weave_fmt_context *context,
    const weave_fmt_struct_field *field,
    int64_t node) {
    size_t start = 0;
    size_t length = 0;
    return weave_fmt_node_name_span(context, node, &start, &length) &&
        weave_fmt_name_spans_equal(
            context,
            field->name_start,
            field->name_length,
            start,
            length);
}

static void weave_fmt_add_struct(
    weave_fmt_context *context,
    int64_t declaration) {
    int64_t name = weave_fmt_nth_child(context, declaration, 1);
    size_t name_start = 0;
    size_t name_length = 0;
    if (!weave_fmt_node_name_span(
            context, name, &name_start, &name_length)) {
        return;
    }

    size_t field_count = 0;
    int64_t field_node = weave_fmt_nth_child(context, declaration, 2);
    while (field_node != -1) {
        ++field_count;
        field_node = node_next_sibling(context->tree, field_node);
    }

    weave_fmt_struct_field *fields = NULL;
    if (field_count != 0) {
        fields = calloc(field_count, sizeof(*fields));
        if (fields == NULL) {
            context->semantic_overflow = 1;
            return;
        }
    }

    int ambiguous = 0;
    field_node = weave_fmt_nth_child(context, declaration, 2);
    size_t field_index = 0;
    while (field_node != -1 && field_index < field_count) {
        int64_t field_head = weave_fmt_nth_child(context, field_node, 0);
        int64_t field_name = weave_fmt_nth_child(context, field_node, 1);
        int64_t field_type = weave_fmt_nth_child(context, field_node, 2);
        weave_fmt_type type = weave_fmt_type_from_text(context, field_type);
        size_t field_start = 0;
        size_t field_length = 0;
        if (node_kind(context->tree, field_node) != node_list() ||
            weave_fmt_child_count(context, field_node) != 3 ||
            !weave_fmt_node_text_equals(context, field_head, "field") ||
            !weave_fmt_node_name_span(
                context, field_name, &field_start, &field_length) ||
            type == WEAVE_FMT_UNKNOWN || type == WEAVE_FMT_VOID) {
            ambiguous = 1;
        } else {
            fields[field_index] = (weave_fmt_struct_field){
                .name_start = field_start,
                .name_length = field_length,
                .type = type,
            };
            for (size_t previous = 0; previous < field_index; ++previous) {
                if (weave_fmt_name_spans_equal(
                        context,
                        fields[previous].name_start,
                        fields[previous].name_length,
                        field_start,
                        field_length)) {
                    ambiguous = 1;
                    break;
                }
            }
        }
        ++field_index;
        field_node = node_next_sibling(context->tree, field_node);
    }

    for (size_t index = 0; index < context->struct_count; ++index) {
        weave_fmt_struct *existing = &context->structs[index];
        if (weave_fmt_name_spans_equal(
                context,
                existing->name_start,
                existing->name_length,
                name_start,
                name_length)) {
            existing->ambiguous = 1;
            free(fields);
            return;
        }
    }

    if (!weave_fmt_reserve_structs(context, context->struct_count + 1)) {
        free(fields);
        return;
    }
    context->structs[context->struct_count++] = (weave_fmt_struct){
        .name_start = name_start,
        .name_length = name_length,
        .fields = fields,
        .field_count = field_count,
        .ambiguous = ambiguous,
    };
}

static void weave_fmt_collect_structs(
    weave_fmt_context *context,
    int64_t root) {
    int64_t child = node_first_child(context->tree, root);
    while (child != -1) {
        if (node_kind(context->tree, child) == node_list()) {
            int64_t head = node_first_child(context->tree, child);
            if (head != -1 &&
                weave_fmt_node_text_equals(context, head, "struct")) {
                weave_fmt_add_struct(context, child);
            }
        }
        child = node_next_sibling(context->tree, child);
    }
}

static const weave_fmt_struct *weave_fmt_lookup_struct_node(
    const weave_fmt_context *context,
    int64_t name) {
    size_t start = 0;
    size_t length = 0;
    if (!weave_fmt_node_name_span(context, name, &start, &length)) {
        return NULL;
    }
    const weave_fmt_struct *result = NULL;
    for (size_t index = 0; index < context->struct_count; ++index) {
        const weave_fmt_struct *candidate = &context->structs[index];
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

static int64_t weave_fmt_constructor_clause_name(
    const weave_fmt_context *context,
    int64_t clause) {
    if (clause == -1 || node_kind(context->tree, clause) != node_list() ||
        weave_fmt_child_count(context, clause) != 2) {
        return -1;
    }
    int64_t name = weave_fmt_nth_child(context, clause, 0);
    return name != -1 && node_kind(context->tree, name) == node_ident()
        ? name : -1;
}

static int weave_fmt_struct_field_index(
    const weave_fmt_context *context,
    const weave_fmt_struct *structure,
    int64_t name,
    size_t *index_out) {
    for (size_t index = 0; index < structure->field_count; ++index) {
        if (weave_fmt_struct_field_equals_node(
                context, &structure->fields[index], name)) {
            *index_out = index;
            return 1;
        }
    }
    return 0;
}

static int64_t weave_fmt_constructor_clause_for_field(
    const weave_fmt_context *context,
    int64_t constructor,
    const weave_fmt_struct_field *field) {
    int64_t clause = weave_fmt_nth_child(context, constructor, 2);
    while (clause != -1) {
        int64_t name = weave_fmt_constructor_clause_name(context, clause);
        if (name != -1 && weave_fmt_struct_field_equals_node(
                context, field, name)) {
            return clause;
        }
        clause = node_next_sibling(context->tree, clause);
    }
    return -1;
}

static int weave_fmt_constructor_is_canonicalizable(
    const weave_fmt_context *context,
    int64_t constructor,
    const weave_fmt_struct *structure) {
    if (structure == NULL || structure->ambiguous ||
        weave_fmt_child_count(context, constructor) !=
            structure->field_count + 2) {
        return 0;
    }

    int64_t clause = weave_fmt_nth_child(context, constructor, 2);
    while (clause != -1) {
        int64_t name = weave_fmt_constructor_clause_name(context, clause);
        size_t field_index = 0;
        if (name == -1 || !weave_fmt_struct_field_index(
                context, structure, name, &field_index)) {
            return 0;
        }
        int64_t previous = weave_fmt_nth_child(context, constructor, 2);
        while (previous != clause) {
            int64_t previous_name = weave_fmt_constructor_clause_name(
                context, previous);
            if (previous_name != -1 &&
                weave_fmt_struct_field_equals_node(
                    context,
                    &structure->fields[field_index],
                    previous_name)) {
                return 0;
            }
            previous = node_next_sibling(context->tree, previous);
        }
        clause = node_next_sibling(context->tree, clause);
    }

    for (size_t index = 0; index < structure->field_count; ++index) {
        if (weave_fmt_constructor_clause_for_field(
                context, constructor, &structure->fields[index]) == -1) {
            return 0;
        }
    }
    return 1;
}

static size_t weave_fmt_source_gap_start_for_child(
    const weave_fmt_context *context,
    int64_t list,
    int64_t target) {
    int64_t child = node_first_child(context->tree, list);
    size_t previous_end = weave_fmt_node_start(context, list) + 1;
    while (child != -1) {
        if (child == target) return previous_end;
        previous_end = weave_fmt_node_end(context, child);
        if (previous_end == 0) return context->source_length + 1;
        child = node_next_sibling(context->tree, child);
    }
    return context->source_length + 1;
}

static size_t weave_fmt_source_trailing_gap_start(
    const weave_fmt_context *context,
    int64_t list) {
    int64_t child = node_first_child(context->tree, list);
    if (child == -1) return weave_fmt_node_start(context, list) + 1;
    int64_t next = node_next_sibling(context->tree, child);
    while (next != -1) {
        child = next;
        next = node_next_sibling(context->tree, child);
    }
    return weave_fmt_node_end(context, child);
}
